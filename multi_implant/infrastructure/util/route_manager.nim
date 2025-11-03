# Route Manager - Bidirectional routing system
import json, tables, times, strutils
# import proxy_structures  # Not needed for basic types

type
  RouteEntry* = object
    route*: seq[string]          # Chain of agent IDs: [GATEWAY, PIVOT, CUMULUS]
    timestamp*: DateTime         # When route was stored
    communicationArray*: JsonNode  # Original communication_array for reference

  RouteManager* = object
    routes*: Table[string, RouteEntry]  # agentId -> RouteEntry
    maxAge*: int                       # Maximum age in seconds

# Global route manager instance - initialize at compile time
var g_routeManager* = RouteManager(
  routes: initTable[string, RouteEntry](),
  maxAge: 300
)

proc initRouteManager*(maxAge: int = 300) {.gcsafe.} =
  # Re-initialize route manager with custom TTL
  {.cast(gcsafe).}:
    g_routeManager.routes = initTable[string, RouteEntry]()
    g_routeManager.maxAge = maxAge
  
  when defined debug:
    echo "[ROUTE_MANAGER] 🗺️ Initialized with TTL: " & $maxAge & " seconds"

proc extractRouteFromArray*(commArray: JsonNode): seq[string] {.gcsafe.} =
  # Extract route chain from communication_array
  var route: seq[string] = @[]
  
  proc traverseArray(node: JsonNode) =
    if node.hasKey("agentId"):
      let agentId = node["agentId"].getStr()
      if agentId != "":
        route.add(agentId)
    
    if node.hasKey("cumulus") and node["cumulus"].kind == JArray:
      for item in node["cumulus"].getElems():
        traverseArray(item)
  
  if commArray.kind == JArray and commArray.len > 0:
    traverseArray(commArray[0])
  
  when defined debug:
    echo "[ROUTE_MANAGER] 🗺️ Extracted route: " & $route
  
  return route

proc storeRoute*(finalAgentId: string, commArray: JsonNode) {.gcsafe.} =
  # Store route for bidirectional communication
  try:
    let route = extractRouteFromArray(commArray)
    
    if route.len == 0:
      when defined debug:
        echo "[ROUTE_MANAGER] ❌ Empty route for agent: " & finalAgentId
      return
    
    let entry = RouteEntry(
      route: route,
      timestamp: now(),
      communicationArray: commArray
    )
    
    {.cast(gcsafe).}:
      g_routeManager.routes[finalAgentId] = entry
    
    when defined debug:
      echo "[ROUTE_MANAGER] 📝 Stored route for " & finalAgentId
      echo "[ROUTE_MANAGER] 📝 Route chain: " & $route
      echo "[ROUTE_MANAGER] 📝 Route stored successfully"
    
  except CatchableError as e:
    when defined debug:
      echo "[ROUTE_MANAGER] ❌ Error storing route: " & e.msg

proc getRoute*(agentId: string): seq[string] {.gcsafe.} =
  # Get stored route for agent
  try:
    {.cast(gcsafe).}:
      if g_routeManager.routes.hasKey(agentId):
        let entry = g_routeManager.routes[agentId]
        
        # Check if route has expired
        let age = (now() - entry.timestamp).inSeconds
        if age > g_routeManager.maxAge:
          when defined debug:
            echo "[ROUTE_MANAGER] ⏰ Route expired for " & agentId & " (age: " & $age & "s)"
          g_routeManager.routes.del(agentId)
          return @[]
        
        when defined debug:
          echo "[ROUTE_MANAGER] 📍 Retrieved route for " & agentId & ": " & $entry.route
        
        return entry.route
      
      when defined debug:
        echo "[ROUTE_MANAGER] ❓ No route found for " & agentId
      
      return @[]
    
  except CatchableError as e:
    when defined debug:
      echo "[ROUTE_MANAGER] ❌ Error getting route: " & e.msg
    return @[]

proc buildRouteHeader*(route: seq[string]): string {.gcsafe.} =
  # Build X-Proxy-Route header value
  return route.join("|")

proc parseRouteHeader*(header: string): seq[string] {.gcsafe.} =
  # Parse X-Proxy-Route header value
  if header == "":
    return @[]
  return header.split("|")

proc cleanExpiredRoutes*() {.gcsafe.} =
  # Clean up expired routes
  {.cast(gcsafe).}:
    var toDelete: seq[string] = @[]
    let currentTime = now()
    
    for agentId, entry in g_routeManager.routes.pairs:
      let age = (currentTime - entry.timestamp).inSeconds
      if age > g_routeManager.maxAge:
        toDelete.add(agentId)
    
    for agentId in toDelete:
      g_routeManager.routes.del(agentId)
      when defined debug:
        echo "[ROUTE_MANAGER] 🗑️ Cleaned expired route for " & agentId
    
    if toDelete.len > 0:
      when defined debug:
        echo "[ROUTE_MANAGER] 🗑️ Cleaned " & $toDelete.len & " expired routes"

# Initialize route manager when module is imported
initRouteManager()
