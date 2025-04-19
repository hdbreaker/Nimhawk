import base64
import binascii
import hashlib
import json
import os
import sys
import traceback

from datetime import datetime
from struct import pack, calcsize
from gzip import decompress
from time import sleep
from typing import Optional, IO
from zlib import compress

from flask import Request

from src.config.config import config

import src.config.db as db
import src.util.time as utils_time
from src.util.logger import nimplant_print
from src.servers.admin_api.models.nimplant_listener_model import np_server
from src.servers.admin_api.models.nimplant_client_model import NimPlant


# Log input and output to flat files per session
def log(message, target=None, **kwargs):
    from src.servers.admin_api.models.nimplant_listener_model import np_server
    np = np_server.get_nimplant_by_guid(target)

    log_directory = os.path.abspath(
        os.path.join(
            os.path.dirname(sys.argv[0]), "logs", f"server-{np_server.name}"
        )
    )
    os.makedirs(log_directory, exist_ok=True)

    if target is not None and np is not None:
        log_file = f"session-{np.id}-{np.guid}.log"
    else:
        log_file = "console.log"

    log_file_path = os.path.join(log_directory, log_file)
    with open(log_file_path, "a", encoding="utf-8") as f:
        f.write(message + "\n")
        
    # Pass additional parameters to nimplant_print
    nimplant_print(message, target, log_to_file=False, **kwargs)


# Pretty print function
def pretty_print(d):
    return json.dumps(d, sort_keys=True, indent=2, default=str)


# Get the server configuration as a YAML object
def get_config_json():
    res = {"GUID": np_server.guid, "Server Configuration": config}
    return json.dumps(res)


# Get last lines of file
# Credit 'S.Lott' on StackOverflow: https://stackoverflow.com/questions/136168/get-last-n-lines-of-a-file-similar-to-tail
def tail(f: IO[bytes], lines):
    block_size = 1024
    total_lines_wanted = lines
    f.seek(0, 2)
    block_end_byte = f.tell()
    lines_to_go = total_lines_wanted
    block_number = -1
    blocks = []
    while lines_to_go > 0 and block_end_byte > 0:
        if block_end_byte - block_size > 0:
            f.seek(block_number * block_size, 2)
            blocks.append(f.read(block_size))
        else:
            f.seek(0, 0)
            blocks.append(f.read(block_end_byte))
        lines_found = blocks[-1].count(b"\n")
        lines_to_go -= lines_found
        block_end_byte -= block_size
        block_number -= 1
    all_read_text = b"".join(reversed(blocks))
    return b"\n".join(all_read_text.splitlines()[-total_lines_wanted:])


def tail_nimplant_log(np: NimPlant = None, lines=100):
    from src.servers.admin_api.models.nimplant_listener_model import np_server
    log_directory = os.path.abspath(
        os.path.join( 
            os.path.dirname(sys.argv[0]), "logs", f"server-{np_server.name}"
        )
    )

    if np:
        log_file = f"session-{np.id}-{np.guid}.log"
        nimplant_id = np.guid
    else:
        log_file = "console.log"
        nimplant_id = "CONSOLE"

    log_file_path = os.path.join(log_directory, log_file)

    if os.path.exists(log_file_path):
        with open(log_file_path, "rb") as f:
            log_contents = tail(f, lines).decode("utf8")
    else:
        lines = 0
        log_contents = ""

    return {"id": nimplant_id, "lines": lines, "result": log_contents}


def dump_debug_info_for_exception(
    error: Exception, request: Optional[Request] = None
) -> None:
    # Capture the full traceback as a string
    traceback_str = "".join(
        traceback.format_exception(type(error), error, error.__traceback__)
    )

    # Log detailed error information
    nimplant_print("Detailed traceback:")
    nimplant_print(traceback_str)

    # Additional request context
    request_headers = dict(request.headers)
    request_method = request.method
    request_path = request.path
    request_query_string = request.query_string.decode("utf-8")
    request_remote_addr = request.remote_addr
    try:
        request_body_snippet = request.get_data(as_text=True)[
            :200
        ]  # Log only the first 200 characters
    except Exception as e:
        request_body_snippet = "Error reading request body: " + str(e)

    # Environment details
    environment_details = {
        "REQUEST_METHOD": request_method,
        "PATH_INFO": request_path,
        "QUERY_STRING": request_query_string,
        "REMOTE_ADDR": request_remote_addr,
        "REQUEST_HEADERS": request_headers,
        "REQUEST_BODY_SNIPPET": request_body_snippet,
    }

    # Log additional context
    nimplant_print("Request Details:")
    nimplant_print(json.dumps(environment_details, indent=4, ensure_ascii=False))

# Exit wrapper for console use
def exit_server_console():
    if np_server.has_active_nimplants():
        check = (
            str(
                input(
                    "Are you sure you want to exit? This will kill ALL active Implants! (Y/N): "
                )
            )
            .lower()
            .strip()
        )
        if check[0] == "y":
            exit_server()
    else:
        exit_server()

# Cleanly exit server
def exit_server():
    if np_server.has_active_nimplants():
        np_server.kill_all_nimplants()
        nimplant_print(
            "Waiting for all Implants to receive kill command... Do not force quit!"
        )
        while np_server.has_active_nimplants():
            sleep(1)

    nimplant_print("Exiting...")
    np_server.kill()
    os._exit(0)
     