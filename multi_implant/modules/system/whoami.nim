#[
    Cross-Platform whoami Command
    Gets current username using osproc
    Compatible with Linux, macOS, and other Unix-like systems
]#

import osproc, strutils
import ../../util/strenc

# Cross-platform whoami implementation
proc whoami*(): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Executing whoami command")
        
        # Use osproc to execute whoami command
        let output = execProcess("whoami").strip()
        
        when defined verbose:
            echo obf("DEBUG: whoami output: ") & output
        
        if output != "":
            return output
        else:
            return obf("unknown")
            
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: whoami failed: ") & e.msg
        return obf("ERROR: whoami failed - ") & e.msg 