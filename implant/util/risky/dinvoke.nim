import winim/lean
import strformat
import algorithm
import strutils
import ptr_math

# Definir offsets del PEB según arquitectura
when defined(WIN64):
    const PEB_OFFSET* = 0x60
else:
    const PEB_OFFSET* = 0x30

# Constantes necesarias
const 
    MZ* = 0x5A4D
    NTDLL_DLL* = "ntdll.dll"
    SYSCALL_STUB_SIZE*: int = 23  # Mantener esta constante para compatibilidad con código existente

# Definiciones de tipos para estructuras del PEB
type 
    ND_LDR_DATA_TABLE_ENTRY* {.bycopy.} = object
        InMemoryOrderLinks*: LIST_ENTRY
        InInitializationOrderLinks*: LIST_ENTRY
        DllBase*: PVOID
        EntryPoint*: PVOID
        SizeOfImage*: ULONG
        FullDllName*: UNICODE_STRING
        BaseDllName*: UNICODE_STRING
    PND_LDR_DATA_TABLE_ENTRY* = ptr ND_LDR_DATA_TABLE_ENTRY

    ND_PEB_LDR_DATA* {.bycopy.} = object
        Length*: ULONG
        Initialized*: UCHAR
        SsHandle*: PVOID
        InLoadOrderModuleList*: LIST_ENTRY
        InMemoryOrderModuleList*: LIST_ENTRY
        InInitializationOrderModuleList*: LIST_ENTRY
    PND_PEB_LDR_DATA* = ptr ND_PEB_LDR_DATA

    ND_PEB* {.bycopy.} = object
        Reserved1*: array[2, BYTE]
        BeingDebugged*: BYTE
        Reserved2*: array[1, BYTE]
        Reserved3*: array[2, PVOID]
        Ldr*: PND_PEB_LDR_DATA
    PND_PEB* = ptr ND_PEB

# Ayudantes para conversión de direcciones
proc `+`[T](a: ptr T, b: int): ptr T =
    cast[ptr T](cast[uint](a) + cast[uint](b * a[].sizeof))

proc `-`[T](a: ptr T, b: int): ptr T =
    cast[ptr T](cast[uint](a) - cast[uint](b * a[].sizeof))

template RVA*(atype: untyped, base_addr: untyped, rva: untyped): untyped =
    cast[atype](cast[ULONG_PTR](cast[ULONG_PTR](base_addr) + cast[ULONG_PTR](rva)))

template RVASub*(atype: untyped, base_addr: untyped, rva: untyped): untyped =
    cast[atype](cast[ULONG_PTR](cast[ULONG_PTR](base_addr) - cast[ULONG_PTR](rva)))

template RVA2VA(casttype, dllbase, rva: untyped): untyped =
    cast[casttype](cast[ULONG_PTR](dllbase) + rva)

# Función para verificar si un puntero es un DLL
proc is_dll*(hLibrary: PVOID): BOOL =
    if hLibrary == nil:
        return FALSE

    try:
        var dosHeader = cast[PIMAGE_DOS_HEADER](hLibrary)
        if dosHeader.e_magic != MZ:
            return FALSE

        var ntHeader = cast[PIMAGE_NT_HEADERS](cast[DWORD_PTR](hLibrary) + dosHeader.e_lfanew)
        if ntHeader.Signature != IMAGE_NT_SIGNATURE:
            return FALSE

        var Characteristics: USHORT = ntHeader.FileHeader.Characteristics
        if (Characteristics and IMAGE_FILE_DLL) != IMAGE_FILE_DLL:
            return FALSE

        return TRUE
    except:
        return FALSE

# Función para obtener la dirección base de una DLL (usando GetModuleHandle) - Método seguro
proc get_library_address_safe*(dllName: cstring): HANDLE =
    # Intentar primero con GetModuleHandleA para máxima compatibilidad
    var hMod = GetModuleHandleA(dllName)
    return cast[HANDLE](hMod)

# Implementación de GetSyscallStub para mantener compatibilidad con el código existente
proc GetSyscallStub*(functionName: LPCSTR, syscallStub: LPVOID): BOOL =
    # Implementación híbrida - intenta primero con APIs estándar 
    # para máxima compatibilidad y como fallback intenta acceso directo
    
    # 1. Obtener módulo ntdll.dll
    var ntdllBase = cast[HMODULE](get_library_address_safe(NTDLL_DLL))
    if ntdllBase == 0:
        return FALSE
    
    # 2. Obtener la dirección de la función usando GetProcAddress
    var funcAddr = GetProcAddress(ntdllBase, functionName)
    if funcAddr == nil:
        return FALSE
    
    # 3. Copiar el stub (primeros SYSCALL_STUB_SIZE bytes) a la memoria proporcionada
    try:
        copyMem(syscallStub, cast[LPVOID](funcAddr), SYSCALL_STUB_SIZE)
        return TRUE
    except:
        return FALSE 