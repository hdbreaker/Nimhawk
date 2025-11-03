import strutils, os

# Read the file
let content = readFile("main.nim")
let lines = content.split("\n")

var newLines: seq[string] = @[]
var i = 0
var inTcpRelayBlock = false

while i < lines.len:
    let line = lines[i]
    
    # Check if we're at the try block that starts TCP relay processing
    if "let messages = pollRelayServerMessages()" in line:
        # Add lines up to the try block
        newLines.add(line)
        i += 1
        
        # Add the messageCount line
        if i < lines.len:
            newLines.add(lines[i])  # messageCount = messages.len
            i += 1
            
        # Add empty line
        if i < lines.len and lines[i].strip() == "":
            newLines.add(lines[i])
            i += 1
            
        # Add our clean replacement
        newLines.add("                    # TCP relay message processing removed - all messages will be empty")
        newLines.add("                    # Original TCP relay loop (550+ lines) replaced with empty processing")
        newLines.add("                    ")
        
        # Skip all malformed TCP relay code until we find the except
        inTcpRelayBlock = true
        while i < lines.len and inTcpRelayBlock:
            if "except Exception as e:" in lines[i] and "Error polling relay server" in (if i+2 < lines.len: lines[i+2] else: ""):
                # Found the correct except block
                newLines.add("                except Exception as e:")
                newLines.add("                    when defined debug:")
                newLines.add("                        echo \"[DEBUG] 🌐 HTTP Handler: Error polling relay server: \" & e.msg")
                i += 3  # Skip the except and next 2 lines
                inTcpRelayBlock = false
            else:
                i += 1
    else:
        newLines.add(line)
        i += 1

# Write the fixed file
writeFile("main_fixed.nim", newLines.join("\n"))
echo "Fixed file written to main_fixed.nim"
