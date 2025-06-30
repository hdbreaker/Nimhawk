#!/usr/bin/python3

# -----
#
#   Nimhawk Server - The "C2-ish"™ handler for the Implant payload
#   By Alejandro Parodi & Cas van Cooten (@hdbreaker_ & @chvancooten)
#
# -----

import threading
import time
import src.util.utils as utils

from src.servers.admin_api.admin_server_init import (
    admin_server,
    server_ip,
    server_port,
)
from src.config.db import (
    initialize_database,
    db_initialize_server,
    db_is_previous_server_same_config,
)

import src.util.utils as utils
from src.servers.implants_check.implants_check import (
    periodic_implant_checks
)

from src.servers.implants_api.implants_server_init import (
    nim_implants_server,
    listener_type,
    server_ip,
    listener_port,
)
from src.servers.admin_api.models.nimplant_listener_model import np_server
from src.util.misc.input import prompt_user_for_command

def start_servers(xor_key=459457925, name="Nimhawk"):
    # Initialize the SQLite database
    initialize_database()
    
    utils.nimplant_print(f"DEBUG: main - Starting server with xor_key={xor_key}, name={name}")
    
    # Important: Ensure that the server name and GUID are configured correctly
    np_server.name = name
    np_server.guid = name
    utils.nimplant_print(f"DEBUG: main - Configured np_server with name={np_server.name}, guid={np_server.guid}")

    # Restore the previous server session if config remains unchanged
    # Otherwise, initialize a new server session
    if db_is_previous_server_same_config(np_server, xor_key):
        utils.nimplant_print("Existing server session found, restoring...")
        utils.nimplant_print(f"DEBUG: main - Restoring server from DB")
        np_server.restore_from_db()
        # IMPORTANT: Verify that after restoration, the GUID is still correct
        utils.nimplant_print(f"DEBUG: main - After restore, server has name={np_server.name}, guid={np_server.guid}")
    else:
        utils.nimplant_print(f"DEBUG: main - Initializing new server")
        np_server.initialize(name, xor_key)
        utils.nimplant_print(f"DEBUG: main - Server initialized with GUID: {np_server.guid}")
        db_initialize_server(np_server)
        utils.nimplant_print(f"DEBUG: main - Server saved in DB")

    # Start daemonized Flask server for API communications
    t1 = threading.Thread(name="Listener", target=admin_server)
    t1.daemon = True
    t1.start()
    utils.nimplant_print(f"Started management server on http://{server_ip}:{server_port}.")

    # Start another thread for Implant listener
    t2 = threading.Thread(name="Listener", target=nim_implants_server, args=(xor_key,))
    t2.daemon = True
    t2.start()
    utils.nimplant_print(
        f"Started Implants listener on {listener_type.lower()}://{server_ip}:{listener_port}. CTRL-C to cancel waiting for Implants."
    )

    # Start another thread to periodically check if nimplants checked in on time
    t3 = threading.Thread(name="Listener", target=periodic_implant_checks)
    t3.daemon = True
    t3.start()

    # Run the console as the main thread
    while True:
        try:
            if np_server.is_active_nimplant_selected():
                prompt_user_for_command()
            elif np_server.has_active_nimplants():
                np_server.get_next_active_nimplant()
            else:
                pass

            time.sleep(0.5)

        except KeyboardInterrupt:
            utils.exit_server_console()
