#[
    Cross-Platform Configuration Parser
    Embeds config.toml in binary at compile time
    Following the same pattern as Windows implant
]#

import parsetoml, tables, os, macros
from ../util/crypto import xorStringToByteSeq, xorByteSeqToString
from ../adapters/string_obfuscation_adapter import obf

# Allow us to re-write the static XOR key used for pre-crypto operations
# This is handled by the Python wrapper at compile time, the default value shouldn't be used
const INITIAL_XOR_KEY* {.intdefine.}: int = 459457925

# Parse the configuration file
# This constant will be stored in the binary itself (hence the XOR)
proc parseConfig*(): Table[string, string] =
    var config = initTable[string, string]()

    # Workspace identifier for this implant
    const workspace_uuid {.strdefine.}: string = ""

    # Embed the configuration as a XORed sequence of bytes at COMPILE-time
    # Note: obf cannot be used inside staticRead, so we use the path directly
    # The path will be embedded in the binary but config content is XORed
    # Path: from infrastructure/config/ go up two levels (../../) to project root
    const config_path = "../../config.toml"
    
    # Verificar si el archivo existe en tiempo de compilación
    # Si no existe, mostrar mensaje de error claro y detener la compilación
    # fileExists en static: evalúa desde el directorio de trabajo actual (raíz del proyecto)
    static:
        if not fileExists("config.toml"):
            error("ERROR: No se encuentra config.toml en la raíz del proyecto. Por favor, crea el archivo config.toml antes de compilar.")
    
    # Leer el archivo usando la ruta relativa al archivo fuente
    const embedded_conf = xorStringToByteSeq(staticRead(config_path), INITIAL_XOR_KEY)
    
    # Decode the configuration at RUNtime and parse the TOML to store it in a basic table
    var toml_config = parsetoml.parseString(xorByteSeqToString(embedded_conf, INITIAL_XOR_KEY))
    config[obf("hostname")]         = toml_config[obf("implants_server")][obf("hostname")].getStr()
    config[obf("listenerType")]     = toml_config[obf("implants_server")][obf("type")].getStr()
    config[obf("listenerPort")]     = $toml_config[obf("implants_server")][obf("port")].getInt()
    config[obf("listenerRegPath")]  = toml_config[obf("implants_server")][obf("registerPath")].getStr()
    config[obf("listenerTaskPath")] = toml_config[obf("implants_server")][obf("taskPath")].getStr()
    config[obf("listenerResPath")]  = toml_config[obf("implants_server")][obf("resultPath")].getStr()
    config[obf("reconnectPath")]    = toml_config[obf("implants_server")][obf("reconnectPath")].getStr()
    config[obf("implantCallbackIp")]       = toml_config[obf("implant")][obf("implantCallbackIp")].getStr()
    config[obf("killDate")]         = $toml_config[obf("implant")][obf("killDate")].getStr()
    config[obf("sleepTime")]        = $toml_config[obf("implant")][obf("sleepTime")].getInt()
    config[obf("sleepJitter")]      = $toml_config[obf("implant")][obf("sleepJitter")].getInt()
    config[obf("userAgent")]        = toml_config[obf("implant")][obf("userAgent")].getStr()
    config[obf("httpAllowCommunicationKey")] = toml_config[obf("implant")][obf("httpAllowCommunicationKey")].getStr()
    
    # Add workspace information if defined
    if workspace_uuid != "":
        config[obf("workspace_uuid")] = workspace_uuid
    
    return config