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
from src.servers.admin_api.models.nimplant_client_model import NimPlant
import src.util.utils as utils
from src.global_models.c2_server_models import Server

# Parse configuration from 'config.toml'
try:
    initialSleepTime = config["implant"]["sleepTime"]
    initialSleepJitter = config["implant"]["sleepJitter"]
    killDate = config["implant"]["killDate"]
except KeyError as e:
    utils.nimplant_print(
        f"ERROR: Could not load configuration, check your 'config.toml': {str(e)}"
    )
    os._exit(1)


class NimplantServer(Server):
    def __init__(self):
        self.nimplant_list: List[NimPlant] = []
        self.active_nimplant_guid = None

        # Initialize Server attributes
        self.guid = None
        self.name = None
        self.date_created = datetime.now()
        self.xor_key = None
        self.killed = False
        self.management_ip = config["admin_api"]["ip"]
        self.management_port = config["admin_api"]["port"]
        self.listener_type = config["implants_server"]["type"]
        self.server_ip = config["admin_api"]["ip"]
        self.listener_host = config["implants_server"]["hostname"]
        self.listener_port = config["implants_server"]["port"]
        self.register_path = config["implants_server"]["registerPath"]
        self.reconnect_path = config["implants_server"]["reconnectPath"]
        self.task_path = config["implants_server"]["taskPath"]
        self.result_path = config["implants_server"]["resultPath"]
        self.implant_callback_ip = config["implant"]["implantCallbackIp"]
        self.risky_mode = config["implant"]["riskyMode"]
        self.sleep_time = config["implant"]["sleepTime"]
        self.sleep_jitter = config["implant"]["sleepJitter"]
        self.kill_date = config["implant"]["killDate"]
        self.user_agent = config["implant"]["userAgent"]
        self.http_allow_communication_key = config["implant"]["httpAllowCommunicationKey"]


    def asdict(self):
        return {
            "guid": self.guid,
            "name": self.name,
            "xorKey": self.xor_key,
            "managementIp": self.management_ip,
            "managementPort": self.management_port,
            "listenerType": self.listener_type,
            "serverIp": self.server_ip,
            "listenerHost": self.listener_host,
            "listenerPort": self.listener_port,
            "registerPath": self.register_path,
            "reconnectPath": self.reconnect_path,
            "implantCallbackIp": self.implant_callback_ip,
            "taskPath": self.task_path,
            "resultPath": self.result_path,
            "riskyMode": self.risky_mode,
            "sleepTime": self.sleep_time,
            "sleepJitter": self.sleep_jitter,
            "killDate": self.kill_date,
            "userAgent": self.user_agent,
            "killed": self.killed,
            "httpAllowCommunicationKey": self.http_allow_communication_key,
        }

    def initialize(self, name, xor_key):
        self.guid = "".join(
            random.choice(string.ascii_letters + string.digits) for i in range(8)
        )
        self.xor_key = xor_key

        if not name == "":
            self.name = name
        else:
            self.name = self.guid

    def restore_from_db(self):
        previous_server = db.db_get_previous_server_config()

        self.guid = previous_server["guid"]
        self.xor_key = previous_server["xorKey"]
        self.name = previous_server["name"]

        previous_nimplants = db.db_get_previous_nimplants(self.guid)
        for previous_nimplant in previous_nimplants:
            np = NimPlant()
            np.restore_from_database(previous_nimplant)
            self.add(np)

    def add(self, np):
        self.nimplant_list.append(np)

    def select_nimplant(self, nimplant_id):
        if len(nimplant_id) == 8:
            # Select by GUID
            res = [np for np in self.nimplant_list if np.guid == nimplant_id]
        else:
            # Select by sequential ID
            res = [np for np in self.nimplant_list if np.id == nimplant_id]

        if res and res[0].active:
            utils.nimplant_print(f"Starting interaction with Implant #{res[0].id}.")
            self.active_nimplant_guid = res[0].guid
        else:
            utils.nimplant_print("Invalid Implant ID.")

    def get_next_active_nimplant(self):
        guid = [np for np in self.nimplant_list if np.active][0].guid
        self.select_nimplant(guid)

    def get_active_nimplant(self):
        res = [np for np in self.nimplant_list if np.guid == self.active_nimplant_guid]
        if res:
            return res[0]
        else:
            return None

    def get_nimplant_by_guid(self, guid):
        res = [np for np in self.nimplant_list if np.guid == guid]
        if res:
            return res[0]
        else:
            return None

    def has_active_nimplants(self):
        for np in self.nimplant_list:
            if np.active and not np.late:
                return True
        return False

    def is_active_nimplant_selected(self):
        if self.active_nimplant_guid is not None:
            return self.get_active_nimplant().active
        else:
            return False

    def kill(self):
        db.kill_server_in_db(self.guid)

    def kill_all_nimplants(self):
        for np in self.nimplant_list:
            np.kill()

    def get_nimplant_info(self, include_all=False):
        result = "\n"
        result += "{:<4} {:<8} {:<15} {:<15} {:<15} {:<15} {:<20} {:<20}\n".format(
            "ID",
            "GUID",
            "EXTERNAL IP",
            "INTERNAL IP",
            "USERNAME",
            "HOSTNAME",
            "PID",
            "LAST CHECK-IN",
        )
        for np in self.nimplant_list:
            if include_all or np.active:
                result += (
                    "{:<4} {:<8} {:<15} {:<15} {:<15} {:<15} {:<20} {:<20}\n".format(
                        np.id,
                        np.guid,
                        np.ip_external,
                        np.ip_internal,
                        np.username,
                        np.hostname,
                        f"{np.pname} ({np.pid})",
                        f"{np.last_checkin} ({np.get_last_checkin_seconds()}s ago)",
                    )
                )

        return result.rstrip()

    def check_late_nimplants(self):
        for np in self.nimplant_list:
            np.is_late()


# Initialize global class to keep implant objects in
np_server = NimplantServer()
