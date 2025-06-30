import os, osproc, strutils, net, nativesockets

# Cross-platform system info functions
proc getLocalIP*(): string =
    try:
        let hostname = nativesockets.getHostname()
        let hostInfo = gethostbyname(hostname)
        if hostInfo.addrList.len > 0:
            return $hostInfo.addrList[0]
        else:
            return "127.0.0.1"
    except:
        return "127.0.0.1"

proc getUsername*(): string =
    try:
        when defined(windows):
            return execProcess("whoami").strip()
        else:
            return execProcess("whoami").strip()
    except:
        return "unknown"

proc getSysHostname*(): string =
    try:
        when defined(windows):
            return execProcess("hostname").strip()
        else:
            return execProcess("hostname").strip()
    except:
        return "unknown"

proc getOSInfo*(): string =
    try:
        when defined(windows):
            return "Windows"
        elif defined(linux):
            return "Linux " & execProcess("uname -r").strip()
        elif defined(macosx):
            return "macOS " & execProcess("uname -r").strip()
        else:
            return "Unknown"
    except:
        return "Unknown"

proc getCurrentPID*(): int =
    try:
        return getCurrentProcessId()
    except:
        return 0

proc getCurrentProcessName*(): string =
    try:
        return getAppFilename().extractFilename()
    except:
        return "unknown" 