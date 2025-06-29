#[
    Cross-Platform ps Command
    Lists running processes using ps command
    Compatible with Linux, macOS, and other Unix-like systems
]#

import osproc, strutils
import ../../util/strenc

# Cross-platform ps implementation
proc ps*(): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Listing running processes")
        
        # Use different ps commands based on platform
        var psCommand = ""
        when defined(linux):
            psCommand = "ps aux"
        elif defined(macosx):
            psCommand = "ps aux"
        else:
            psCommand = "ps aux"  # Default for Unix-like systems
        
        let output = execProcess(psCommand).strip()
        
        when defined verbose:
            echo obf("DEBUG: ps command executed successfully")
        
        if output != "":
            return output
        else:
            return obf("No processes found")
            
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: ps command failed: ") & e.msg
        return obf("ERROR: ps command failed - ") & e.msg 