# HTTP Client Registry for Gateway
# Manages connected HTTP relay clients automatically

import times, tables, json, strutils

type
  HttpRelayClientInfo* = object
    agentId*: string
    ip*: string
    port*: int
    lastSeen*: Time
    firstSeen*: Time
    requestCount*: int
    isActive*: bool

  HttpClientRegistry* = object
    clients*: Table[string, HttpRelayClientInfo]
    timeoutSeconds*: int
    lastCleanup*: Time

# Global registry instance
var g_httpClientRegistry* {.global.}: HttpClientRegistry

# Initialize the HTTP client registry
proc initHttpClientRegistry*(timeoutSeconds: int = 300) =
  g_httpClientRegistry = HttpClientRegistry(
    clients: initTable[string, HttpRelayClientInfo](),
    timeoutSeconds: timeoutSeconds,
    lastCleanup: getTime()
  )
  when defined debug:
    echo "[HTTP_REGISTRY] 🏗️ HTTP Client Registry initialized with timeout: " & $timeoutSeconds & "s"

# Register or update a client from /proxy request
proc registerHttpClient*(agentId: string, ip: string, port: int = 0) {.gcsafe.} =
  {.cast(gcsafe).}:
    let now = getTime()
    
    if agentId in g_httpClientRegistry.clients:
      # Update existing client
      g_httpClientRegistry.clients[agentId].lastSeen = now
      g_httpClientRegistry.clients[agentId].requestCount += 1
      g_httpClientRegistry.clients[agentId].isActive = true
      
      when defined debug:
        echo "[HTTP_REGISTRY] 🔄 Updated client: " & agentId & " (requests: " & $g_httpClientRegistry.clients[agentId].requestCount & ")"
    else:
      # Register new client
      let clientInfo = HttpRelayClientInfo(
        agentId: agentId,
        ip: ip,
        port: port,
        lastSeen: now,
        firstSeen: now,
        requestCount: 1,
        isActive: true
      )
      g_httpClientRegistry.clients[agentId] = clientInfo
      
      when defined debug:
        echo "[HTTP_REGISTRY] ✅ Registered new client: " & agentId & " from " & ip

# Get list of active HTTP clients
proc getActiveHttpClients*(): seq[string] =
  var activeClients: seq[string] = @[]
  
  for agentId, client in g_httpClientRegistry.clients:
    if client.isActive:
      activeClients.add(agentId)
  
  return activeClients

# Get client info
proc getHttpClientInfo*(agentId: string): HttpRelayClientInfo =
  if agentId in g_httpClientRegistry.clients:
    return g_httpClientRegistry.clients[agentId]
  else:
    # Return empty client info
    return HttpRelayClientInfo()

# Check if client is active
proc isHttpClientActive*(agentId: string): bool =
  if agentId in g_httpClientRegistry.clients:
    return g_httpClientRegistry.clients[agentId].isActive
  return false

# Clean up inactive clients
proc cleanupInactiveHttpClients*() =
  let now = getTime()
  let timeoutDuration = initDuration(seconds = g_httpClientRegistry.timeoutSeconds)
  var removedClients: seq[string] = @[]
  
  for agentId, client in g_httpClientRegistry.clients:
    let timeSinceLastSeen = now - client.lastSeen
    
    if timeSinceLastSeen > timeoutDuration:
      g_httpClientRegistry.clients[agentId].isActive = false
      removedClients.add(agentId)
      
      when defined debug:
        echo "[HTTP_REGISTRY] ⏰ Client timeout: " & agentId & " (inactive for " & $timeSinceLastSeen.inSeconds & "s)"
  
  # Remove inactive clients completely after 2x timeout
  let removeAfter = initDuration(seconds = g_httpClientRegistry.timeoutSeconds * 2)
  var deletedClients: seq[string] = @[]
  
  for agentId, client in g_httpClientRegistry.clients:
    let timeSinceLastSeen = now - client.lastSeen
    
    if timeSinceLastSeen > removeAfter:
      g_httpClientRegistry.clients.del(agentId)
      deletedClients.add(agentId)
      
      when defined debug:
        echo "[HTTP_REGISTRY] 🗑️ Removed client: " & agentId & " (inactive for " & $timeSinceLastSeen.inSeconds & "s)"
  
  g_httpClientRegistry.lastCleanup = now
  
  when defined debug:
    if removedClients.len > 0 or deletedClients.len > 0:
      echo "[HTTP_REGISTRY] 🧹 Cleanup completed - Deactivated: " & $removedClients.len & ", Removed: " & $deletedClients.len

# Get registry status for debugging
proc getHttpRegistryStatus*(): string =
  cleanupInactiveHttpClients()  # Clean before reporting
  
  var status = "=== HTTP CLIENT REGISTRY ===\n"
  status &= "Total clients: " & $len(g_httpClientRegistry.clients) & "\n"
  
  let activeClients = getActiveHttpClients()
  status &= "Active clients: " & $activeClients.len & "\n"
  status &= "Timeout: " & $g_httpClientRegistry.timeoutSeconds & "s\n"
  status &= "Last cleanup: " & $g_httpClientRegistry.lastCleanup & "\n\n"
  
  if activeClients.len > 0:
    status &= "Active client list:\n"
    for agentId in activeClients:
      let client = g_httpClientRegistry.clients[agentId]
      let timeSinceLastSeen = getTime() - client.lastSeen
      status &= "  • " & agentId & " - " & client.ip
      if client.port > 0:
        status &= ":" & $client.port
      status &= " (last seen: " & $timeSinceLastSeen.inSeconds & "s ago, requests: " & $client.requestCount & ")\n"
  else:
    status &= "No active clients\n"
  
  return status

# Extract agent_id and IP from /proxy request
proc extractClientInfoFromProxy*(data: string): tuple[agentId: string, ip: string] =
  try:
    let jsonData = parseJson(data)
    let commArray = jsonData["communication_array"]
    
    if commArray.len > 0:
      let firstNode = commArray[0]
      let agentId = firstNode["agent_id"].getStr()
      let ipInfo = firstNode["ip"].getStr()
      
      # Extract IP from "ip:port" format
      let ipParts = ipInfo.split(":")
      let ip = if ipParts.len > 0: ipParts[0] else: ""
      
      return (agentId: agentId, ip: ip)
    
  except Exception:
    when defined debug:
      echo "[HTTP_REGISTRY] ❌ Failed to extract client info: " & getCurrentExceptionMsg()
  
  return (agentId: "", ip: "")

# Auto-register client from /proxy request
proc autoRegisterFromProxy*(data: string) {.gcsafe.} =
  try:
    # Skip auto-registration for special Gateway commands
    let jsonData = parseJson(data)
    if jsonData.hasKey("command"):
      when defined debug:
        echo "[HTTP_REGISTRY] 🔐 Skipping auto-registration for command: " & jsonData["command"].getStr()
      return
  except:
    when defined debug:
      echo "[HTTP_REGISTRY] ❌ Failed to parse JSON for command check: " & getCurrentExceptionMsg()
    return
  
  let clientInfo = extractClientInfoFromProxy(data)
  
  if clientInfo.agentId != "" and clientInfo.ip != "":
    registerHttpClient(clientInfo.agentId, clientInfo.ip)
