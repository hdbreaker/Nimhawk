#[
    Cross-Platform pwd Command
    Gets current working directory
    Compatible with all platforms
]#

import os, strutils
import ../../util/strenc

# Cross-platform pwd implementation
proc pwd*(): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Getting current directory")
        
        let currentDir = getCurrentDir()
        
        when defined verbose:
            echo obf("DEBUG: Current directory: ") & currentDir
        
        return currentDir
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: pwd command failed: ") & e.msg
        return obf("ERROR: pwd command failed - ") & e.msg 