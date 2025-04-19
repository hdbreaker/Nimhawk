#!/usr/bin/env python3
"""
Script to create test implants in Nimhawk directly in the database.
This script avoids circular imports by working directly with SQLite.
"""
import os
import sys
import sqlite3
import datetime
from datetime import timedelta
import time
import random
import string
import uuid

def generate_guid(length=8):
    """Generate a random ID for an implant."""
    return ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(length))

def timestamp(dt=None):
    """Generate a timestamp in format dd/MM/yyyy HH:mm:ss."""
    if dt is None:
        dt = datetime.datetime.now()
    return dt.strftime("%d/%m/%Y %H:%M:%S")

def ensure_default_workspace(con):
    """Ensure a default workspace exists in the database."""
    print("Checking for default workspace...")
    
    # Check if a default workspace already exists
    default_workspace = con.execute(
        "SELECT workspace_uuid, workspace_name FROM workspaces WHERE workspace_name = 'Default'"
    ).fetchone()
    
    if default_workspace:
        print(f"  - Found existing default workspace with UUID: {default_workspace['workspace_uuid']}")
        return default_workspace['workspace_uuid']
    
    # Create a default workspace
    default_uuid = str(uuid.uuid4())
    print(f"  - Creating default workspace with UUID: {default_uuid}")
    con.execute(
        "INSERT INTO workspaces (workspace_uuid, workspace_name, creation_date) VALUES (?, ?, ?)",
        (default_uuid, "Default", timestamp())
    )
    con.commit()
    
    return default_uuid

def create_demo_implants():
    """Create test implants with different states for demonstration."""
    print("Creating test implants...")
    
    # Path to the database
    db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server", "nimhawk.db")
    print(f"Connecting to database: {db_path}")
    
    # Connect to the database
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    
    # Check what servers exist in the database
    server_guids = []
    try:
        # Get the most recent server (first in the table)
        cursor = con.execute("SELECT guid, name FROM server ORDER BY dateCreated DESC LIMIT 1")
        server = dict(cursor.fetchone())
        server_guid = server["guid"]
        server_name = server["name"]
        print(f"Using the most recent server: guid={server_guid}, name={server_name}")
    except Exception as e:
        print(f"Error querying servers: {e}")
        print("Using 'NimHawk' as default GUID")
        server_guid = "NimHawk"
    
    print(f"Implants will be created with serverGuid: {server_guid}")
    
    # Ensure a default workspace exists
    default_workspace_uuid = ensure_default_workspace(con)
    print(f"Using workspace UUID: {default_workspace_uuid}")
    
    # Define implant data
    implants = [
        # Implant 1: Normal active
        {
            "guid": "TESTX01A",
            "id": 1,
            "active": True,
            "late": False,
            "cryptKey": "testkeyABC123",
            "ipAddrExt": "203.0.113.10",
            "ipAddrInt": "192.168.1.10",
            "username": "testuser",
            "hostname": "DESKTOP-TEST01",
            "osBuild": "Windows 10 Pro x64",
            "pid": 1234,
            "pname": "explorer.exe",
            "riskyMode": False,
            "sleepTime": 10,
            "sleepJitter": 5,
            "killDate": "31/12/2024 23:59:59",
            "firstCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=5)),
            "lastCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=1)),
            "workspace_uuid": default_workspace_uuid,
        },
        
        # Implant 2: Active but "late" (more than 2 minutes without check-in)
        {
            "guid": "TESTX02L",
            "id": 2,
            "active": True,
            "late": True,
            "cryptKey": "testkeyDEF456",
            "ipAddrExt": "203.0.113.20",
            "ipAddrInt": "192.168.1.20",
            "username": "lateuser",
            "hostname": "DESKTOP-TEST02",
            "osBuild": "Windows 11 Pro x64",
            "pid": 5678,
            "pname": "chrome.exe",
            "riskyMode": False,
            "sleepTime": 10,
            "sleepJitter": 5,
            "killDate": "31/12/2024 23:59:59",
            "firstCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=10)),
            "lastCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=3)),
            "workspace_uuid": default_workspace_uuid,
        },
        
        # Implant 3: Active but "disconnected" (more than 5 minutes without check-in)
        {
            "guid": "TESTX03D",
            "id": 3,
            "active": True,
            "late": True,
            "cryptKey": "testkeyGHI789",
            "ipAddrExt": "203.0.113.30",
            "ipAddrInt": "192.168.1.30",
            "username": "disconnuser",
            "hostname": "DESKTOP-TEST03",
            "osBuild": "Windows 10 Enterprise x64",
            "pid": 9012,
            "pname": "firefox.exe",
            "riskyMode": False,
            "sleepTime": 10,
            "sleepJitter": 5,
            "killDate": "31/12/2024 23:59:59",
            "firstCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=20)),
            "lastCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=10)),
            "workspace_uuid": default_workspace_uuid,
        },
        
        # Implant 4: Inactive 
        # (properly closed)
        {
            "guid": "TESTX04I",
            "id": 4,
            "active": False,
            "late": False,
            "cryptKey": "testkeyJKL012",
            "ipAddrExt": "203.0.113.40",
            "ipAddrInt": "192.168.1.40",
            "username": "inactiveuser",
            "hostname": "DESKTOP-TEST04",
            "osBuild": "Windows Server 2019",
            "pid": 3456,
            "pname": "cmd.exe",
            "riskyMode": False,
            "sleepTime": 10,
            "sleepJitter": 5,
            "killDate": "31/12/2024 23:59:59",
            "firstCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=60)),
            "lastCheckin": timestamp(datetime.datetime.now() - timedelta(minutes=30)),
            "workspace_uuid": default_workspace_uuid,
        }
    ]
    
    # Insert implants into the database
    for i, implant in enumerate(implants, 1):
        try:
            # Delete implant if it already exists (to avoid UNIQUE constraint errors)
            try:
                con.execute("DELETE FROM nimplant WHERE guid = ?", (implant["guid"],))
                con.execute("DELETE FROM nimplant_history WHERE nimplantGuid = ?", (implant["guid"],))
                con.commit()
                print(f"  - Deleted previous implant {implant['guid']}")
            except Exception as e:
                print(f"  - Could not delete previous implant {implant['guid']}: {e}")
            
            # Initialize the implant in the database
            print(f"  - Creating implant {i}: {implant['guid']} ({implant['username']}@{implant['hostname']})")
            
            # Insert into nimplant table
            con.execute(
                """INSERT INTO nimplant (
                    id, guid, serverGuid, active, late,
                    cryptKey, ipAddrExt, ipAddrInt, username,
                    hostname, osBuild, pid, pname, riskyMode,
                    sleepTime, sleepJitter, killDate,
                    firstCheckin, lastCheckin, pendingTasks, workspace_uuid
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    implant["id"], implant["guid"], server_guid, 
                    implant["active"], implant["late"],
                    implant["cryptKey"], implant["ipAddrExt"], implant["ipAddrInt"], 
                    implant["username"], implant["hostname"], implant["osBuild"],
                    implant["pid"], implant["pname"], implant["riskyMode"],
                    implant["sleepTime"], implant["sleepJitter"], implant["killDate"],
                    implant["firstCheckin"], implant["lastCheckin"], None, implant["workspace_uuid"]
                )
            )
            
            # Add a history entry for the first check-in
            con.execute(
                """INSERT INTO nimplant_history (nimplantGuid, task, taskFriendly, taskTime, result, resultTime, is_checkin)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (implant["guid"], None, None, implant["firstCheckin"], f"Implant checked in from {implant['ipAddrExt']}", implant["firstCheckin"], 1)
            )
            
            # Add a history entry for the last check-in
            con.execute(
                """INSERT INTO nimplant_history (nimplantGuid, task, taskFriendly, taskTime, result, resultTime, is_checkin)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (implant["guid"], None, None, implant["lastCheckin"], f"Implant checked in from {implant['ipAddrExt']}", implant["lastCheckin"], 1)
            )
            
            con.commit()
            print(f"  - Implant {implant['guid']} created successfully!")
        except Exception as e:
            print(f"  - Error creating implant {i}: {e}")
            import traceback
            print(traceback.format_exc())
    
    # Close the database connection
    con.close()
    
    print("Implant creation process completed!")
    print("** To see the new implants: **")
    print("1. Restart the Nimhawk server")
    print("2. Reload the web page")

if __name__ == "__main__":
    create_demo_implants() 