#[
    Cross-Platform ls Command
    Lists directory contents
    Compatible with all platforms using Nim os module
]#

import os, strutils, times
import ../../util/strenc

# Cross-platform ls implementation
proc ls*(args: seq[string]): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Listing directory contents")
        
        var targetDir = "."
        if args.len > 0:
            targetDir = args[0]
        
        when defined verbose:
            echo obf("DEBUG: Listing directory: ") & targetDir
        
        if not dirExists(targetDir):
            return obf("ERROR: Directory does not exist: ") & targetDir
        
        var output = ""
        
        # List directory contents
        for kind, path in walkDir(targetDir):
            let name = path.extractFilename()
            
            case kind:
            of pcFile:
                try:
                    let info = getFileInfo(path)
                    let size = getFileSize(path)
                    let modTime = info.lastWriteTime.format("yyyy-MM-dd HH:mm")
                    output.add("FILE  " & modTime & " " & $size & " " & name & "\n")
                except:
                    output.add("FILE  [ERROR] " & name & "\n")
            of pcDir:
                try:
                    let info = getFileInfo(path)
                    let modTime = info.lastWriteTime.format("yyyy-MM-dd HH:mm")
                    output.add("DIR   " & modTime & " <DIR> " & name & "\n")
                except:
                    output.add("DIR   [ERROR] " & name & "\n")
            else:
                output.add("OTHER " & name & "\n")
        
        if output == "":
            return obf("Directory is empty")
        else:
            return output.strip()
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: ls command failed: ") & e.msg
        return obf("ERROR: ls command failed - ") & e.msg 