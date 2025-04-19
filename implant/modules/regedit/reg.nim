import winim/core
from strutils import join, split, startsWith, replace, toUpperAscii

# Query or modify the Windows registry
proc reg*(args : varargs[string]) : string =
    # Variables locales con tipos explícitos
    var
        command: string
        path: string
        key: string
        value: string
        hKey: HKEY
        rootKey: HKEY
        subKey: string
        status: LONG
        result: string = ""

    # Parse arguments
    case args.len:
        of 2:
            command = args[0]
            path = args[1]
        of 3:
            command = args[0]
            path = args[1]
            key = args[2]
        of 4:
            command = args[0]
            path = args[1]
            key = args[2]
            value = args[3..^1].join(obf(" "))
        else:
            return obf("Invalid number of arguments received. Usage: 'reg [query|add] [path] <optional: key> <optional: value>'.")

    # Parse the registry path
    try:
        path = path.replace(obf("\\\\"), obf("\\"))

        # Determine root key
        if path.startsWith("HKEY_CURRENT_USER"):
            rootKey = HKEY_CURRENT_USER
            subKey = path.replace("HKEY_CURRENT_USER\\", "")
        elif path.startsWith("HKEY_LOCAL_MACHINE"):
            rootKey = HKEY_LOCAL_MACHINE
            subKey = path.replace("HKEY_LOCAL_MACHINE\\", "")
        elif path.startsWith("HKEY_CLASSES_ROOT"):
            rootKey = HKEY_CLASSES_ROOT
            subKey = path.replace("HKEY_CLASSES_ROOT\\", "")
        elif path.startsWith("HKEY_USERS"):
            rootKey = HKEY_USERS
            subKey = path.replace("HKEY_USERS\\", "")
        else:
            return obf("Invalid registry path.")

        # Open registry key based on command
        var dwAccess: REGSAM = KEY_READ
        if command == obf("add"):
            dwAccess = dwAccess or KEY_WRITE

        status = RegOpenKeyEx(rootKey, subKey, 0, dwAccess, addr hKey)
        if status != ERROR_SUCCESS:
            return obf("Failed to open registry key.")
    except:
        return obf("Error accessing registry path.")

    # Query an existing registry value
    if command == obf("query"):
        if key == "":
            var
                i: DWORD = 0
                valueNameSize: DWORD = 256
                valueName = newString(256)
                valueType: DWORD
                valueData = newString(1024)
                valueDataSize: DWORD = 1024

            while true:
                valueNameSize = 256
                valueDataSize = 1024
                status = RegEnumValue(hKey, i, cast[LPWSTR](addr valueName[0]), addr valueNameSize, nil,
                                     addr valueType, cast[LPBYTE](addr valueData[0]), addr valueDataSize)
                if status != ERROR_SUCCESS:
                    break

                result.add("- " & valueName[0..<valueNameSize.int] & obf(": ") & valueData[0..<valueDataSize.int] & "\n")
                i += 1
        else:
            var
                valueType: DWORD
                valueData = newString(1024)
                valueDataSize: DWORD = 1024

            status = RegQueryValueEx(hKey, key, nil, addr valueType, cast[LPBYTE](addr valueData[0]), addr valueDataSize)
            if status == ERROR_SUCCESS:
                result.add(valueData[0..<valueDataSize.int])
            else:
                result.add(obf("Failed to query registry value."))

    # Add a value to the registry
    elif command == obf("add"):
        let valueLen = value.len.DWORD
        status = RegSetValueEx(hKey, key, 0, REG_SZ, cast[LPBYTE](unsafeAddr value[0]), valueLen)
        if status == ERROR_SUCCESS:
            result.add(obf("Successfully set registry value."))
        else:
            result.add(obf("Failed to set registry value."))
    else:
        result.add(obf("Unknown reg command. Please use 'reg query' or 'reg add'."))

    RegCloseKey(hKey)
    return result