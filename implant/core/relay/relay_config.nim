import random, times, strutils
from ../../util/crypto import xorString

# Default relay configuration
const
    DEFAULT_RELAY_KEY_SEED* = 0x1337BEEF
    DEFAULT_IMPLANT_ID_PREFIX* = "NH-"
    DEFAULT_HEARTBEAT_INTERVAL* = 30  # seconds
    DEFAULT_MESSAGE_TIMEOUT* = 300    # seconds

# Global relay configuration
type
    RelayConfig* = object
        baseCryptoKey*: string
        implantIDPrefix*: string
        heartbeatInterval*: int
        messageTimeout*: int
        isInitialized*: bool

var g_relayConfig: RelayConfig

# Generate deterministic crypto key based on seed
proc generateRelayKey*(seed: int = DEFAULT_RELAY_KEY_SEED): string =
    randomize(seed)
    result = ""
    for i in 0..15:  # 16 byte key for AES-128
        result.add(char(rand(256)))

# Derive unique key for specific implant using base key + implant ID
proc deriveImplantKey*(baseKey: string, implantID: string): string =
    # XOR base key with implant ID hash for unique per-implant keys
    let idHash = implantID.len * 0x1337  # Simple hash
    result = xorString(baseKey, idHash)
    
    # Ensure key is exactly 16 bytes for AES-128
    if result.len < 16:
        result = result & repeat("\x00", 16 - result.len)
    elif result.len > 16:
        result = result[0..15]

# Initialize relay configuration
proc initRelayConfig*(customKey: string = ""): RelayConfig =
    result.isInitialized = true
    result.implantIDPrefix = DEFAULT_IMPLANT_ID_PREFIX
    result.heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL
    result.messageTimeout = DEFAULT_MESSAGE_TIMEOUT
    
    if customKey != "":
        result.baseCryptoKey = customKey
    else:
        result.baseCryptoKey = generateRelayKey()

# Get global relay configuration
proc getRelayConfig*(): RelayConfig =
    if not g_relayConfig.isInitialized:
        g_relayConfig = initRelayConfig()
    result = g_relayConfig

# Set custom crypto key
proc setRelayCryptoKey*(key: string) =
    if not g_relayConfig.isInitialized:
        g_relayConfig = initRelayConfig()
    g_relayConfig.baseCryptoKey = key

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

# Get derived key for specific implant
proc getImplantKey*(implantID: string): string =
    let config = getRelayConfig()
    result = deriveImplantKey(config.baseCryptoKey, implantID) 