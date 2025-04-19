import os
import sys
from datetime import datetime
import src.util.time as utils_time
import src.config.db as db
import src.util.utils as utils

def log_to_file(message, target=None, np_server=None):
    from src.servers.admin_api.models.nimplant_listener_model import np_server
    log_directory = os.path.abspath(
        os.path.join(
            "logs", f"server-{np_server.name if np_server else 'unknown'}"
        )
    )
    os.makedirs(log_directory, exist_ok=True)

    if target is not None:
        log_file = f"session-{target}.log"
    else:
        log_file = "console.log"

    log_file_path = os.path.join(log_directory, log_file)
    with open(log_file_path, "a", encoding="utf-8") as f:
        f.write(message + "\n")

def nimplant_print(msg, np_server=None, log_to_file=True, show_time=True, show_name=True, skip_db_log=False, **kwargs):
    from datetime import datetime
    from src.servers.admin_api.models.nimplant_listener_model import np_server as server_instance

    # Handle string GUID as np_server parameter
    if isinstance(np_server, str):
        nimplant_guid = np_server
        
        # Check if we can get the nimplant object for better display
        if hasattr(server_instance, 'get_nimplant_by_guid'):
            nimplant = server_instance.get_nimplant_by_guid(np_server)
            if nimplant and show_name:
                server_name = f"[Implant {nimplant.id}]"
            else:
                server_name = f"[{np_server}]" if show_name else ""
        else:
            server_name = f"[{np_server}]" if show_name else ""
    else:
        # Original behavior for object with name attribute
        server_name = "[" + np_server.name + "]" if np_server and show_name and hasattr(np_server, 'name') else ""

    time = "[" + datetime.now().strftime("%H:%M:%S") + "]" if show_time else ""

    fullMessage = f"{time} {server_name} {msg}"
    print(fullMessage.strip())

    try:
        # Write to db log if np_server was passed and skip_db_log is False
        if np_server and not skip_db_log:
            # If np_server is a string (GUID)
            if isinstance(np_server, str):
                if hasattr(server_instance, 'guid') and server_instance.guid:
                    from src.config.db import db_server_log
                    db_server_log(server_instance, msg)
            # Original case - np_server is an object
            elif hasattr(np_server, "guid") and np_server.guid:
                from src.config.db import db_server_log
                db_server_log(np_server, msg)
    except Exception as e:
        print(f"Error writing to db: {str(e)}")

    if log_to_file:
        try:
            log_file = os.path.join("logs", "admin_api_nimhawk.log")
            os.makedirs(os.path.dirname(log_file), exist_ok=True)
            with open(log_file, "a") as f:
                f.write(fullMessage.strip() + "\n")
        except Exception as e:
            print(f"Error writing to log file: {str(e)}") 