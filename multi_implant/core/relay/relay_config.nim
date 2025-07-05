import random, times, strutils

# Default relay configuration
const
    DEFAULT_IMPLANT_ID_PREFIX* = "NH-"
    DEFAULT_HEARTBEAT_INTERVAL* = 30  # seconds
    DEFAULT_MESSAGE_TIMEOUT* = 300    # seconds

# Global relay configuration
type
    RelayConfig* = object
        implantIDPrefix*: string
        heartbeatInterval*: int
        messageTimeout*: int
        isInitialized*: bool

    # New key management structure
    RelayKeyConfig* = object
        sharedKey*: string      # Shared key (compilation time) - for hop-to-hop encryption
        uniqueKey*: string      # Unique key (assigned by C2) - for final destination encryption
        implantID*: string      # ID of this implant
        isUniqueKeySet*: bool   # Whether unique key has been assigned by C2
        isSharedKeySet*: bool   # Whether shared key has been set

var g_relayConfig: RelayConfig
var g_keyConfig: RelayKeyConfig

# Initialize relay configuration
proc initRelayConfig*(): RelayConfig =
    result.isInitialized = true
    result.implantIDPrefix = DEFAULT_IMPLANT_ID_PREFIX
    result.heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL
    result.messageTimeout = DEFAULT_MESSAGE_TIMEOUT

# Get global relay configuration
proc getRelayConfig*(): RelayConfig =
    if not g_relayConfig.isInitialized:
        g_relayConfig = initRelayConfig()
    result = g_relayConfig

# Generate unique implant ID
proc generateImplantID*(suffix: string = ""): string =
    let config = getRelayConfig()
    let timestamp = epochTime().int64
    randomize()
    let randomPart = rand(1000..9999)
    
    if suffix != "":
        result = config.implantIDPrefix & suffix & "-" & $randomPart
    else:
        result = config.implantIDPrefix & $timestamp & "-" & $randomPart

# === NEW KEY MANAGEMENT FUNCTIONS ===

# Set shared key (compilation time key for hop-to-hop encryption)
proc setSharedKey*(key: string) =
    when defined debug:
        echo "[KEYEX] 🔑 === SET SHARED KEY ==="
        echo "[KEYEX] 🔑 Key type: SHARED (compilation time)"
        echo "[KEYEX] 🔑 Key length: " & $key.len
        echo "[KEYEX] 🔑 Key preview: " & (if key.len > 20: key[0..19] & "..." else: key)
        echo "[KEYEX] 🔑 Previous state: " & (if g_keyConfig.isSharedKeySet: "ALREADY SET" else: "NOT SET")
    
    g_keyConfig.sharedKey = key
    g_keyConfig.isSharedKeySet = true
    
    when defined debug:
        echo "[KEYEX] 🔑 ✅ Shared key set successfully"
        echo "[KEYEX] 🔑 === END SET SHARED KEY ==="

# Set unique key (assigned by C2 for final destination encryption)
proc setUniqueKey*(key: string) =
    when defined debug:
        echo "[KEYEX] 🔑 === SET UNIQUE KEY ==="
        echo "[KEYEX] 🔑 Key type: UNIQUE (C2 assigned)"
        echo "[KEYEX] 🔑 Key length: " & $key.len
        echo "[KEYEX] 🔑 Key preview: " & (if key.len > 20: key[0..19] & "..." else: key)
        echo "[KEYEX] 🔑 Previous state: " & (if g_keyConfig.isUniqueKeySet: "ALREADY SET" else: "NOT SET")
    
    g_keyConfig.uniqueKey = key
    g_keyConfig.isUniqueKeySet = true
    
    when defined debug:
        echo "[KEYEX] 🔑 ✅ Unique key set successfully"
        echo "[KEYEX] 🔑 === END SET UNIQUE KEY ==="

# Set implant ID in key config
proc setImplantID*(id: string) =
    when defined debug:
        echo "[KEYEX] 🆔 === SET IMPLANT ID ==="
        echo "[KEYEX] 🆔 New implant ID: " & id
        echo "[KEYEX] 🆔 Previous ID: " & (if g_keyConfig.implantID != "": g_keyConfig.implantID else: "NOT SET")
    
    g_keyConfig.implantID = id
    
    when defined debug:
        echo "[KEYEX] 🆔 ✅ Implant ID set successfully"
        echo "[KEYEX] 🆔 === END SET IMPLANT ID ==="

# Get shared key
proc getSharedKey*(): string =
    when defined debug:
        echo "[KEYEX] 🔑 === GET SHARED KEY ==="
        echo "[KEYEX] 🔑 Key state: " & (if g_keyConfig.isSharedKeySet: "AVAILABLE" else: "NOT SET")
        if g_keyConfig.isSharedKeySet:
            echo "[KEYEX] 🔑 Key length: " & $g_keyConfig.sharedKey.len
    
    if not g_keyConfig.isSharedKeySet:
        # Return empty string if not set - caller should handle this
        when defined debug:
            echo "[KEYEX] 🔑 ❌ Shared key not available"
            echo "[KEYEX] 🔑 === END GET SHARED KEY (EMPTY) ==="
        return ""
    
    result = g_keyConfig.sharedKey
    when defined debug:
        echo "[KEYEX] 🔑 ✅ Shared key retrieved"
        echo "[KEYEX] 🔑 === END GET SHARED KEY ==="

# Get unique key
proc getUniqueKey*(): string =
    when defined debug:
        echo "[KEYEX] 🔑 === GET UNIQUE KEY ==="
        echo "[KEYEX] 🔑 Key state: " & (if g_keyConfig.isUniqueKeySet: "AVAILABLE" else: "NOT SET")
        if g_keyConfig.isUniqueKeySet:
            echo "[KEYEX] 🔑 Key length: " & $g_keyConfig.uniqueKey.len
    
    if not g_keyConfig.isUniqueKeySet:
        # Return empty string if not set - caller should handle this
        when defined debug:
            echo "[KEYEX] 🔑 ❌ Unique key not available"
            echo "[KEYEX] 🔑 === END GET UNIQUE KEY (EMPTY) ==="
        return ""
    
    result = g_keyConfig.uniqueKey
    when defined debug:
        echo "[KEYEX] 🔑 ✅ Unique key retrieved"
        echo "[KEYEX] 🔑 === END GET UNIQUE KEY ==="

# Check if unique key is available
proc hasUniqueKey*(): bool =
    result = g_keyConfig.isUniqueKeySet and g_keyConfig.uniqueKey != ""
    when defined debug:
        echo "[KEYEX] 🔑 Has unique key check: " & $result

# Check if shared key is available
proc hasSharedKey*(): bool =
    result = g_keyConfig.isSharedKeySet and g_keyConfig.sharedKey != ""
    when defined debug:
        echo "[KEYEX] 🔑 Has shared key check: " & $result

# Get current implant ID from key config
proc getCurrentImplantID*(): string =
    result = g_keyConfig.implantID
    when defined debug:
        echo "[KEYEX] 🆔 Get current implant ID: " & (if result != "": result else: "NOT SET")

# Clear all keys (for security purposes)
proc clearKeys*() =
    when defined debug:
        echo "[KEYEX] 🧹 === CLEAR ALL KEYS ==="
        echo "[KEYEX] 🧹 Clearing shared key: " & (if g_keyConfig.isSharedKeySet: "YES" else: "ALREADY EMPTY")
        echo "[KEYEX] 🧹 Clearing unique key: " & (if g_keyConfig.isUniqueKeySet: "YES" else: "ALREADY EMPTY")
        echo "[KEYEX] 🧹 Clearing implant ID: " & (if g_keyConfig.implantID != "": g_keyConfig.implantID else: "ALREADY EMPTY")
    
    g_keyConfig.sharedKey = ""
    g_keyConfig.uniqueKey = ""
    g_keyConfig.isSharedKeySet = false
    g_keyConfig.isUniqueKeySet = false
    
    when defined debug:
        echo "[KEYEX] 🧹 ✅ All keys cleared successfully"
        echo "[KEYEX] 🧹 === END CLEAR ALL KEYS ==="

# Get key config status for debugging
proc getKeyConfigStatus*(): tuple[hasShared: bool, hasUnique: bool, implantID: string] =
    result.hasShared = hasSharedKey()
    result.hasUnique = hasUniqueKey()
    result.implantID = g_keyConfig.implantID
    
    when defined debug:
        echo "[KEYEX] 📊 === KEY CONFIG STATUS ==="
        echo "[KEYEX] 📊 Has shared key: " & $result.hasShared
        echo "[KEYEX] 📊 Has unique key: " & $result.hasUnique
        echo "[KEYEX] 📊 Implant ID: " & (if result.implantID != "": result.implantID else: "NOT SET")
        echo "[KEYEX] 📊 === END KEY CONFIG STATUS ==="

# === INITIALIZATION EXAMPLE ===

# Example function showing proper key initialization
proc initializeRelayKeys*(implantID: string, sharedKeyFromCompilation: string = "", uniqueKeyFromC2: string = "") =
    ## Initialize the relay key system with proper keys
    ## 
    ## Parameters:
    ## - implantID: The unique ID for this implant/relay
    ## - sharedKeyFromCompilation: The shared key embedded at compilation time (for hop-to-hop encryption)
    ## - uniqueKeyFromC2: The unique key assigned by C2 (for final destination encryption)
    ##
    ## Example usage:
    ##   # At startup with compilation-time shared key:
    ##   initializeRelayKeys("NH-12345-6789", SHARED_KEY_FROM_CONFIG)
    ##   
    ##   # Later when C2 assigns unique key:
    ##   setUniqueKey(uniqueKeyFromC2Registration)
    
    # Set implant ID
    setImplantID(implantID)
    
    # Set shared key if provided (compilation time)
    if sharedKeyFromCompilation != "":
        setSharedKey(sharedKeyFromCompilation)
        when defined debug:
            echo "[DEBUG] 🔑 Shared key set from compilation (length: " & $sharedKeyFromCompilation.len & ")"
    
    # Set unique key if provided (from C2)
    if uniqueKeyFromC2 != "":
        setUniqueKey(uniqueKeyFromC2)
        when defined debug:
            echo "[DEBUG] 🔑 Unique key set from C2 (length: " & $uniqueKeyFromC2.len & ")"
    
    when defined debug:
        let status = getKeyConfigStatus()
        echo "[DEBUG] 🔑 Key initialization completed:"
        echo "[DEBUG] 🔑 - Implant ID: " & status.implantID
        echo "[DEBUG] 🔑 - Has shared key: " & $status.hasShared
        echo "[DEBUG] 🔑 - Has unique key: " & $status.hasUnique 