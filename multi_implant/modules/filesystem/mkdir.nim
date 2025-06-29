#[
    Cross-Platform mkdir Command
    Create directories
    Compatible with Linux, macOS, and other Unix-like systems
]#

import os, strutils
import ../../util/strenc

proc mkdir*(args: seq[string]): string =
    try:
        if args.len != 1:
            return obf("ERROR: mkdir requires exactly one argument.\nUsage: mkdir <directory>")
        
        let dirPath = args[0]
        
        if dirExists(dirPath):
            return obf("ERROR: Directory already exists: ") & dirPath
        
        when defined verbose:
            echo obf("DEBUG: Creating directory: ") & dirPath
        
        # Create directory with parent directories if needed
        createDir(dirPath)
        
        if dirExists(dirPath):
            return obf("Directory created successfully: ") & dirPath
        else:
            return obf("ERROR: Failed to create directory: ") & dirPath
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: mkdir failed: ") & e.msg
        return obf("ERROR: Directory creation failed - ") & e.msg 