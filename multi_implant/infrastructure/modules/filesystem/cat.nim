#[
    Cross-Platform cat Command
    Display file contents
    Compatible with Linux, macOS, and other Unix-like systems
]#

import os, strutils
import ../../util/strenc

proc cat*(args: seq[string]): string =
    try:
        if args.len != 1:
            return obf("ERROR: cat requires exactly one argument.\nUsage: cat <file>")
        
        let filePath = args[0]
        
        if not fileExists(filePath):
            return obf("ERROR: File does not exist: ") & filePath
        
        let info = getFileInfo(filePath)
        if info.kind != pcFile:
            return obf("ERROR: Path is not a file: ") & filePath
        
        when defined verbose:
            echo obf("DEBUG: Reading file: ") & filePath
        
        let content = readFile(filePath)
        
        when defined verbose:
            echo obf("DEBUG: File read successfully, ") & $content.len & obf(" bytes")
        
        return content
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: cat failed: ") & e.msg
        return obf("ERROR: Failed to read file - ") & e.msg 