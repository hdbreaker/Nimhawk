#[
    Cross-Platform cp Command
    Copy files and directories
    Compatible with Linux, macOS, and other Unix-like systems
]#

import os, strutils
import ../../util/strenc

proc cp*(args: seq[string]): string =
    try:
        if args.len != 2:
            return obf("ERROR: cp requires exactly two arguments.\nUsage: cp <source> <destination>")
        
        let srcPath = args[0]
        let dstPath = args[1]
        
        if not fileExists(srcPath) and not dirExists(srcPath):
            return obf("ERROR: Source does not exist: ") & srcPath
        
        when defined verbose:
            echo obf("DEBUG: Copying from ") & srcPath & obf(" to ") & dstPath
        
        # Copy file
        let srcInfo = getFileInfo(srcPath)
        if srcInfo.kind == pcFile:
            # Create parent directory if needed
            let parentDir = parentDir(dstPath)
            if parentDir != "" and not dirExists(parentDir):
                createDir(parentDir)
            
            copyFile(srcPath, dstPath)
            return obf("File copied successfully: ") & srcPath & obf(" -> ") & dstPath
        
        # Copy directory
        elif srcInfo.kind == pcDir:
            copyDir(srcPath, dstPath)
            return obf("Directory copied successfully: ") & srcPath & obf(" -> ") & dstPath
        
        else:
            return obf("ERROR: Unknown file type: ") & srcPath
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: cp failed: ") & e.msg
        return obf("ERROR: Copy failed - ") & e.msg 