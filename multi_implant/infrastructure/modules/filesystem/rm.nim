#[
    Cross-Platform rm Command
    Remove files and directories
    Compatible with Linux, macOS, and other Unix-like systems
]#

import os, strutils
import ../../util/strenc

proc rm*(args: seq[string]): string =
    try:
        if args.len < 1 or args.len > 2:
            return obf("ERROR: rm requires one or two arguments.\nUsage: rm <file/directory> [recursive]")
        
        let targetPath = args[0]
        let recursive = if args.len == 2: (args[1].toLowerAscii() == "true" or args[1] == "-r") else: false
        
        if not fileExists(targetPath) and not dirExists(targetPath):
            return obf("ERROR: Path does not exist: ") & targetPath
        
        when defined verbose:
            echo obf("DEBUG: Removing: ") & targetPath & (if recursive: obf(" (recursive)") else: "")
        
        # Remove file
        let info = getFileInfo(targetPath)
        if info.kind == pcFile:
            removeFile(targetPath)
            return obf("File removed successfully: ") & targetPath
        
        # Remove directory
        elif info.kind == pcDir:
            if recursive:
                removeDir(targetPath)
                return obf("Directory removed recursively: ") & targetPath
            else:
                # Try to remove empty directory
                try:
                    removeDir(targetPath)
                    return obf("Empty directory removed: ") & targetPath
                except:
                    return obf("ERROR: Directory not empty. Use 'rm ") & targetPath & obf(" -r' to remove recursively")
        
        else:
            return obf("ERROR: Unknown file type: ") & targetPath
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: rm failed: ") & e.msg
        return obf("ERROR: Remove failed - ") & e.msg 