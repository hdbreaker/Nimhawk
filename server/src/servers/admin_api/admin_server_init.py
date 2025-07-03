import os
from threading import Thread
import datetime
from datetime import datetime as dt
import src.util.time as utils_time

import flask
from flask_cors import CORS
from gevent.pywsgi import WSGIServer
from werkzeug.utils import secure_filename
import src.util.utils as utils

from src.servers.admin_api.commands.commands_parser import get_commands, handle_command
from src.config.config import config
from src.util.crypto import random_string
import src.servers.admin_api.commands.commands as commands
from src.servers.admin_api.models.nimplant_listener_model import np_server

from src.config.db import (
    db_get_nimplant_console,
    db_get_nimplant_details,
    db_get_nimplant_info,
    db_get_server_console,
    db_get_server_info,
    db_delete_nimplant,
    db_update_nimplant,
    authenticate_user,
    create_session,
    verify_session,
    delete_session,
    initialize_database,
    ensure_db_initialized,
    db_log_file_transfer,
    db_get_file_transfers_api,
    db_store_file_hash_mapping,
    db_get_nimplants_by_workspace,
    db_get_workspaces,
    db_create_workspace,
    db_delete_workspace,
    db_assign_nimplant_to_workspace,
    db_remove_nimplant_from_workspace,
    db_get_nimplant_relay_role,
)

from functools import wraps

# Import the dynamic Implants Server proxy
from src.servers.admin_api.proxy.implants_server_proxy import implants_server_proxy


# Parse server configuration
server_ip = config["admin_api"]["ip"]
server_port = config["admin_api"]["port"]
# These values are not set fixed, they will be set from start_servers

utils.nimplant_print(f"DEBUG: admin_server_init - Using server with guid={np_server.guid}, name={np_server.name}")

# Check if authentication is enabled
auth_enabled = config.get("auth", {}).get("enabled", True)

# Get absolute path to web directory
current_dir = os.path.dirname(os.path.abspath(__file__))

utils.nimplant_print(f"DEBUG: Current directory: {current_dir}")

# Define the API server
def admin_server():
    # Create Flask instance inside the function to keep it separate from implants server
    app = flask.Flask(
        __name__,
        # API only mode - no static files or templates
        static_url_path=None,
        static_folder=None,
        template_folder=None,
    )

    app.secret_key = random_string(32)
    
    # Authentication middleware decorator
    def require_auth(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            # Skip auth check if authentication is disabled
            if not auth_enabled:
                return f(*args, **kwargs)
                
            # Skip auth for login endpoint and static resources
            if flask.request.path == '/api/auth/login' or \
               flask.request.path.startswith('/static/') or \
               flask.request.path == '/favicon.ico' or \
               flask.request.path == '/login' or \
               flask.request.path == '/register' or \
               flask.request.path == '/reconnect' or \
               flask.request.path == '/task' or \
               flask.request.path.startswith('/task/') or \
               flask.request.path == '/result' or \
               flask.request.path == '/alive':
                return f(*args, **kwargs)
                
            # Get auth token from cookie, header, or URL parameter (search in all places)
            token = None
            
            # 1. Check URL query parameters first (highest priority for download links)
            token_from_query = flask.request.args.get('token')
            if token_from_query:
                utils.nimplant_print(f"DEBUG: Found token in query parameters: {token_from_query[:10]}...")
                token = token_from_query
            
            # 2. If no token in URL, check cookie
            if not token:
                token = flask.request.cookies.get('auth_token')
                
            # 3. If still no token, check Authorization header
            if not token:
                auth_header = flask.request.headers.get('Authorization')
                if auth_header and auth_header.startswith('Bearer '):
                    token = auth_header.split(' ')[1]
            
            utils.nimplant_print(f"DEBUG: Final token used - {token[:10] if token else 'None'}")
            
            if not token:
                utils.nimplant_print(f"DEBUG: No token found in any source - Path: {flask.request.path}")
                # For API requests, return JSON error
                if flask.request.path.startswith('/api/'):
                    return flask.jsonify({
                        'error': 'Authentication required',
                        'message': 'You must be logged in to access this resource'
                    }), 401
                # For web requests, redirect to login page
                return flask.redirect('/login')
                
            # Verify the token
            user = verify_session(token)
            if not user:
                utils.nimplant_print(f"DEBUG: Token verification failed - Path: {flask.request.path}")
                # For API requests, return JSON error
                if flask.request.path.startswith('/api/'):
                    return flask.jsonify({
                        'error': 'Invalid or expired session',
                        'message': 'Please log in again'
                    }), 401
                # For web requests, redirect to login page
                return flask.redirect('/login')
                
            # If we get here, the token is valid
            utils.nimplant_print(f"DEBUG: Token verified successfully for user: {user['email']}")
            
            # Add user to request context
            flask.g.user = user
            
            return f(*args, **kwargs)
        return decorated
    
    utils.nimplant_print(f"DEBUG: Starting API Server on {server_ip}:{server_port}")
    
    # Initialize database before starting server
    utils.nimplant_print(f"Initializing database before starting server...")
    if ensure_db_initialized():
        utils.nimplant_print(f"Database initialized successfully")
    else:
        utils.nimplant_print(f"WARNING: Error initializing database. Server may not function correctly.")
    
    # Global variable to store build status
    if not hasattr(app, 'build_status'):
        app.build_status = {}
        
    # Function that performs the compilation in a separate thread
    def build_process(build_id, debug, workspace=None, implant_type="windows", architecture=None, relay_config=None):
        import os
        import subprocess
        import zipfile
        import datetime
        import traceback
        from pathlib import Path
        
        try:
            # Update status
            app.build_status[build_id] = {
                'status': 'running',
                'progress': 'Starting compilation process',
                'timestamp': datetime.datetime.now().isoformat()
            }
            
            # Path of the nimhawk.py script at the project root (two levels up)
            current_dir = os.path.dirname(os.path.abspath(__file__))
            nimplant_script = os.path.abspath(os.path.join(current_dir, "..", "..", "..", "..", "nimhawk.py"))
            
            app.build_status[build_id]['progress'] = f'Looking for script at: {nimplant_script}'
            utils.nimplant_print(f"Looking for script at: {nimplant_script}")
            
            # Verify the script exists
            if not os.path.exists(nimplant_script):
                # Try with another relative path (one level up from the current directory)
                nimplant_script = os.path.abspath(os.path.join(current_dir, "..", "..", "..", "nimhawk.py"))
                app.build_status[build_id]['progress'] = f'Trying alternative path: {nimplant_script}'
                utils.nimplant_print(f"Trying alternative path: {nimplant_script}")
                
                if not os.path.exists(nimplant_script):
                    error_msg = f"Error: Implant script not found at {nimplant_script}"
                    utils.nimplant_print(error_msg)
                    app.build_status[build_id] = {
                        'status': 'failed',
                        'error': error_msg,
                        'timestamp': datetime.datetime.now().isoformat()
                    }
                    return
            
            # Get the directory where the script is located
            nimplant_dir = os.path.dirname(nimplant_script)
            app.build_status[build_id]['progress'] = f'Script directory: {nimplant_dir}'
            utils.nimplant_print(f"Script directory: {nimplant_dir}")
            
            # Determine release directory and downloads directory based on implant type
            if implant_type == "windows":
                release_dir = os.path.join(nimplant_dir, "implant", "release")
                app.build_status[build_id]['progress'] = f'Windows implant - Release directory: {release_dir}'
            else:  # multi-os
                release_dir = os.path.join(nimplant_dir, "multi_implant", "bin")
                app.build_status[build_id]['progress'] = f'Multi-OS implant - Release directory: {release_dir}'
            
            utils.nimplant_print(f"Release directory: {release_dir}")
            
            # Downloads directory where the ZIP file will be moved
            downloads_dir = os.path.join(nimplant_dir, "server", "downloads")
            app.build_status[build_id]['progress'] = f'Downloads directory: {downloads_dir}'
            utils.nimplant_print(f"Downloads directory: {downloads_dir}")
            
            # Create downloads directory if it doesn't exist
            os.makedirs(downloads_dir, exist_ok=True)
            
            # Ensure the release directory exists
            os.makedirs(release_dir, exist_ok=True)

            # NEW CODE: Empty the release folder before compiling
            app.build_status[build_id]['progress'] = 'Cleaning release directory...'
            utils.nimplant_print(f"Cleaning release directory: {release_dir}")
            try:
                # List all files in the release folder
                for filename in os.listdir(release_dir):
                    file_path = os.path.join(release_dir, filename)
                    # Check if it's a regular file (not a directory)
                    if os.path.isfile(file_path):
                        # Delete the file
                        os.unlink(file_path)
                        utils.nimplant_print(f"Deleted file: {file_path}")
                    # If there are subdirectories, we can also delete them
                    elif os.path.isdir(file_path):
                        import shutil
                        shutil.rmtree(file_path)
                        utils.nimplant_print(f"Deleted directory: {file_path}")
                utils.nimplant_print(f"Release directory cleaned successfully")
            except Exception as clean_error:
                error_msg = f"Error cleaning release directory: {str(clean_error)}"
                utils.nimplant_print(error_msg)
                # Continue with the compilation despite the cleaning error
            
            # Build the command to execute based on implant type
            if implant_type == "windows":
                # Windows implant using nimhawk.py
                if debug:
                    cmd = ["python3", "nimhawk.py", "compile", "all", "nim-debug"]
                    variant = "windows_debug"
                else:
                    cmd = ["python3", "nimhawk.py", "compile", "all"]
                    variant = "windows_release"
                    
                # Add workspace parameter if specified
                if workspace:
                    cmd.extend(["--workspace", workspace])
                    variant += f"_workspace_{workspace}"
                    app.build_status[build_id]['progress'] = f'Using workspace: {workspace}'
                    utils.nimplant_print(f"Using workspace: {workspace}")
                    
            else:  # multi-os
                # Multi-OS implant using Makefile
                cmd = ["make", "-C", "multi_implant"]
                
                # Add architecture target
                if architecture:
                    cmd.append(architecture)
                    variant = f"multi_os_{architecture}"
                else:
                    cmd.append("all")
                    variant = "multi_os_all"
                
                # Add debug flag if enabled
                if debug:
                    cmd.append("DEBUG=1")
                    variant += "_debug"
                
                # Add relay configuration if provided
                if relay_config:
                    if relay_config.get('enabled', False):
                        relay_address = relay_config.get('address', '')
                        relay_port = relay_config.get('port', '')
                        fast_mode = relay_config.get('fast_mode', False)
                        
                        if relay_address and relay_port:
                            cmd.append(f"RELAY_ADDRESS=relay://{relay_address}:{relay_port}")
                            variant += "_relay"
                            
                        if fast_mode:
                            cmd.append("FAST_MODE=1")
                            variant += "_fast"
                            
                        app.build_status[build_id]['progress'] = f'Relay configuration: {relay_address}:{relay_port}, Fast mode: {fast_mode}'
                        utils.nimplant_print(f"Relay configuration: {relay_address}:{relay_port}, Fast mode: {fast_mode}")
                
                # Add workspace as environment variable if specified
                if workspace:
                    # For multi-os, we'll add it as a custom define
                    cmd.append(f"WORKSPACE_UUID={workspace}")
                    variant += f"_workspace_{workspace}"
                    app.build_status[build_id]['progress'] = f'Using workspace: {workspace}'
                    utils.nimplant_print(f"Using workspace: {workspace}")
            
            # Save current directory to restore it later
            original_dir = os.getcwd()
            
            try:
                # Change to the script directory so it can find config.toml
                os.chdir(nimplant_dir)
                app.build_status[build_id]['progress'] = f'Changed to directory: {nimplant_dir}'
                utils.nimplant_print(f"Changed to directory: {nimplant_dir}")
                
                # Verify that config.toml exists
                if not os.path.exists(os.path.join(nimplant_dir, "config.toml")):
                    error_msg = f"Error: config.toml not found in {nimplant_dir}"
                    utils.nimplant_print(error_msg)
                    app.build_status[build_id] = {
                        'status': 'failed',
                        'error': error_msg,
                        'timestamp': datetime.datetime.now().isoformat()
                    }
                    return
                
                # Execute the compilation command from the script directory
                app.build_status[build_id]['progress'] = f'Executing compilation command: {" ".join(cmd)}'
                utils.nimplant_print(f"Executing compilation command: {' '.join(cmd)}")
                
                # Use subprocess.Popen for better output control and to avoid encoding errors
                try:
                    process = subprocess.Popen(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=False  # Use binary mode to avoid encoding problems
                    )
                    
                    # Update status
                    app.build_status[build_id]['progress'] = 'Building implants, this may take several minutes...'
                    
                    stdout_data, stderr_data = process.communicate()
                    
                    # Try to decode with error handling
                    try:
                        stdout_text = stdout_data.decode('utf-8', errors='replace')
                    except:
                        stdout_text = str(stdout_data)
                        
                    try:
                        stderr_text = stderr_data.decode('utf-8', errors='replace')
                    except:
                        stderr_text = str(stderr_data)
                    
                    exit_code = process.returncode
                    
                    app.build_status[build_id]['progress'] = f'Compilation completed with code: {exit_code}'
                    utils.nimplant_print(f"Command completed with code: {exit_code}")
                    
                    if stdout_text:
                        utils.nimplant_print(f"Standard output: {stdout_text[:500]}...")
                    if stderr_text:
                        utils.nimplant_print(f"Error output: {stderr_text[:500]}...")
                        
                    if exit_code != 0:
                        error_msg = f"Compilation failed with code {exit_code}"
                        utils.nimplant_print(error_msg)
                        app.build_status[build_id] = {
                            'status': 'failed',
                            'error': error_msg,
                            'stdout': stdout_text,
                            'stderr': stderr_text,
                            'timestamp': datetime.datetime.now().isoformat()
                        }
                        return
                
                except Exception as compile_error:
                    error_msg = f"Error executing command: {str(compile_error)}"
                    utils.nimplant_print(error_msg)
                    app.build_status[build_id] = {
                        'status': 'failed',
                        'error': error_msg,
                        'timestamp': datetime.datetime.now().isoformat()
                    }
                    return
                
                # Verify that the files were created based on implant type
                if implant_type == "windows":
                    expected_files = ["implant.exe", "implant-selfdelete.exe", "implant.dll", "implant.bin"]
                else:  # multi-os
                    # Check for multi-os binaries based on architecture
                    if architecture == "all":
                        expected_files = [
                            "nimhawk_linux_x64", "nimhawk_linux_arm64", 
                            "nimhawk_linux_mipsel", "nimhawk_linux_arm",
                            "nimhawk_darwin_intelx64", "nimhawk_darwin_arm64"
                        ]
                    elif architecture:
                        # Single architecture
                        if architecture == "darwin":
                            expected_files = ["nimhawk_darwin_intelx64", "nimhawk_darwin_arm64"]
                        elif architecture == "linux_x64":
                            expected_files = ["nimhawk_linux_x64"]
                        elif architecture == "linux_arm64":
                            expected_files = ["nimhawk_linux_arm64"]
                        elif architecture == "linux_mipsel":
                            expected_files = ["nimhawk_linux_mipsel"]
                        elif architecture == "linux_arm":
                            expected_files = ["nimhawk_linux_arm"]
                        elif architecture == "darwin_intelx64":
                            expected_files = ["nimhawk_darwin_intelx64"]
                        elif architecture == "darwin_arm64":
                            expected_files = ["nimhawk_darwin_arm64"]
                        else:
                            expected_files = ["nimhawk_linux_x64"]  # fallback
                    else:
                        expected_files = ["nimhawk_linux_x64"]  # fallback
                
                found_files = []
                
                app.build_status[build_id]['progress'] = 'Verifying generated files...'
                
                for file in expected_files:
                    file_path = os.path.join(release_dir, file)
                    if os.path.exists(file_path):
                        found_files.append(file_path)
                    else:
                        utils.nimplant_print(f"Expected file not found: {file_path}")
                
                if not found_files:
                    error_msg = "No compilation files were generated"
                    utils.nimplant_print(error_msg)
                    app.build_status[build_id] = {
                        'status': 'failed',
                        'error': error_msg,
                        'timestamp': datetime.datetime.now().isoformat()
                    }
                    return
                
                # Generate name for the ZIP file
                timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                zip_filename = f"implants_{variant}_{timestamp}.zip"
                
                app.build_status[build_id]['progress'] = 'Creating ZIP file with implants...'
                
                # Try multiple locations for the downloads directory
                download_dirs = [
                    # Relative path from current location
                    os.path.abspath("server/downloads"),
                    # Downloads directory determined earlier
                    downloads_dir,
                    # Create a directory next to the current script
                    os.path.join(os.path.dirname(os.path.abspath(__file__)), "downloads"),
                    # Downloads directory relative to the project
                    os.path.join(nimplant_dir, "server", "downloads")
                ]
                
                # Make sure at least one of these directories exists
                zip_path = None
                for download_dir in download_dirs:
                    try:
                        os.makedirs(download_dir, exist_ok=True)
                        zip_path = os.path.join(download_dir, zip_filename)
                        utils.nimplant_print(f"Saving ZIP to: {zip_path}")
                        
                        # Create the ZIP file with the generated files
                        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                            for file in found_files:
                                zipf.write(file, os.path.basename(file))
                                
                        # If we get here, the ZIP was created successfully
                        utils.nimplant_print(f"ZIP created successfully at: {zip_path}")
                        break
                    except Exception as zip_error:
                        utils.nimplant_print(f"Error creating ZIP in {download_dir}: {str(zip_error)}")
                        continue
                
                if not zip_path or not os.path.exists(zip_path):
                    error_msg = "Could not create ZIP file"
                    utils.nimplant_print(error_msg)
                    app.build_status[build_id] = {
                        'status': 'failed',
                        'error': error_msg,
                        'timestamp': datetime.datetime.now().isoformat()
                    }
                    return
                
                # URL to download the ZIP file
                download_url = f"/api/get-download/{zip_filename}"
                
                # Save the path of the zip file in an application variable so it is available
                # for the download endpoint
                if not hasattr(app, 'download_files'):
                    app.download_files = {}
                app.download_files[zip_filename] = zip_path
                
                utils.nimplant_print(f"ZIP file registered for download: {zip_filename} at {zip_path}")
                
                # Update final status
                app.build_status[build_id] = {
                    'status': 'completed',
                    'message': f"Implants compiled successfully ({variant})",
                    'files': [os.path.basename(f) for f in found_files],
                    'download_url': download_url,
                    'download_filename': zip_filename,
                    'zip_path': zip_path,
                    'timestamp': datetime.datetime.now().isoformat()
                }
                
            finally:
                # Restore the original directory
                os.chdir(original_dir)
                utils.nimplant_print(f"Restored to original directory: {original_dir}")
            
        except Exception as e:
            error_msg = f"Compilation failed with exception: {str(e)}\n{traceback.format_exc()}"
            utils.nimplant_print(error_msg)
            app.build_status[build_id] = {
                'status': 'failed',
                'error': error_msg,
                'timestamp': datetime.datetime.now().isoformat()
            }
            
    # Authentication endpoints
    @app.route("/api/auth/login", methods=["POST", "OPTIONS"])
    def login():
        # Handle OPTIONS requests for CORS preflight
        if flask.request.method == "OPTIONS":
            response = flask.make_response()
            origin = flask.request.headers.get('Origin')
            if origin:
                response.headers.add('Access-Control-Allow-Origin', origin)
            else:
                response.headers.add('Access-Control-Allow-Origin', '*')
            response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
            response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
            response.headers.add('Access-Control-Allow-Credentials', 'true')
            return response
            
        try:
            utils.nimplant_print(f"DEBUG: Login request received")
            
            # Debug request headers
            headers_dict = dict(flask.request.headers)
            utils.nimplant_print(f"DEBUG: Login request headers: {headers_dict}")
            
            if not flask.request.is_json:
                utils.nimplant_print(f"DEBUG: Error - Request is not JSON")
                return flask.jsonify({"error": "Invalid request, JSON expected"}), 400
                
            data = flask.request.get_json()
            utils.nimplant_print(f"DEBUG: Login data received: {data.keys() if data else 'None'}")
            
            email = data.get("email")
            password = data.get("password")
            
            utils.nimplant_print(f"DEBUG: Attempting to authenticate user: {email}")
            
            if not email or not password:
                utils.nimplant_print(f"DEBUG: Error - Incomplete credentials")
                return flask.jsonify({
                    "error": "Missing credentials",
                    "message": "Email and password are required"
                }), 400
                
            # Authenticate the user
            user = authenticate_user(email, password)
            
            if not user:
                utils.nimplant_print(f"DEBUG: Error - Authentication failed for {email}")
                return flask.jsonify({
                    "error": "Authentication failed",
                    "message": "Invalid email or password"
                }), 401
                
            utils.nimplant_print(f"DEBUG: User {email} authenticated successfully")
                
            # Create a session token
            token = create_session(user["id"])
            
            if not token:
                utils.nimplant_print(f"DEBUG: Error - Could not create session for {email}")
                return flask.jsonify({
                    "error": "Session creation failed",
                    "message": "Could not create session"
                }), 500
                
            utils.nimplant_print(f"DEBUG: Session created for {email}, token length: {len(token)}, first 10 chars: {token[:10]}...")
                
            # Calculate session expiration time
            session_duration = config.get("auth", {}).get("session_duration", 24)
            expiration = datetime.datetime.now() + datetime.timedelta(hours=session_duration)
                
            # Create response
            response = flask.jsonify({
                "success": True,
                "message": "Authentication successful",
                "token": token,  # Include the token in the response
                "user": {
                    "email": user["email"],
                    "admin": user["admin"],
                    "last_login": user["last_login"]
                }
            })
            
            # Set the auth token as a cookie
            response.set_cookie(
                'auth_token', 
                token, 
                httponly=True, 
                secure=flask.request.is_secure, 
                samesite='Lax',
                expires=expiration
            )
            
            # Debug response
            utils.nimplant_print(f"DEBUG: Login response prepared for {email}")
            utils.nimplant_print(f"DEBUG: Response includes cookie: auth_token={token[:10]}...")
            
            # Add CORS headers explicitly for this response
            origin = flask.request.headers.get('Origin')
            if origin:
                response.headers.add('Access-Control-Allow-Origin', origin)
                response.headers.add('Access-Control-Allow-Credentials', 'true')
            
            return response, 200
                
        except Exception as e:
            utils.nimplant_print(f"Login error: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Login traceback: {traceback.format_exc()}")
            return flask.jsonify({
                "error": "Authentication error",
                "message": "An error occurred during authentication"
            }), 500
    
    @app.route("/api/auth/logout", methods=["POST", "OPTIONS"])
    @require_auth
    def logout():
        # Handle OPTIONS requests for CORS preflight
        if flask.request.method == "OPTIONS":
            response = flask.make_response()
            origin = flask.request.headers.get('Origin')
            if origin:
                response.headers.add('Access-Control-Allow-Origin', origin)
            else:
                response.headers.add('Access-Control-Allow-Origin', '*')
            response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
            response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
            response.headers.add('Access-Control-Allow-Credentials', 'true')
            return response
            
        try:
            # Get the token from cookie or header
            token = flask.request.cookies.get('auth_token')
            if not token:
                auth_header = flask.request.headers.get('Authorization')
                if auth_header and auth_header.startswith('Bearer '):
                    token = auth_header.split(' ')[1]
            
            if token:
                # Delete the session
                delete_session(token)
            
            # Create response
            response = flask.jsonify({
                "success": True,
                "message": "Logged out successfully"
            })
            
            # Clear the auth cookie
            response.delete_cookie('auth_token')
            
            return response, 200
                
        except Exception as e:
            utils.nimplant_print(f"Logout error: {str(e)}")
            return flask.jsonify({
                "error": "Logout error",
                "message": "An error occurred during logout"
            }), 500
    
    @app.route("/api/auth/verify", methods=["GET", "OPTIONS"])
    def verify_auth():
        # Handle OPTIONS requests for CORS preflight
        if flask.request.method == "OPTIONS":
            response = flask.make_response()
            origin = flask.request.headers.get('Origin')
            if origin:
                response.headers.add('Access-Control-Allow-Origin', origin)
            else:
                response.headers.add('Access-Control-Allow-Origin', '*')
            response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
            response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS')
            response.headers.add('Access-Control-Allow-Credentials', 'true')
            return response
        
        # Detailed information log for diagnostics
        utils.nimplant_print(f"DEBUG: Verify Auth - Full headers: {dict(flask.request.headers)}")
        utils.nimplant_print(f"DEBUG: Verify Auth - Cookies: {dict(flask.request.cookies)}")
        
        # Get token from any possible source
        token = None

        # 1. Look in cookies
        token_from_cookie = flask.request.cookies.get('auth_token')
        if token_from_cookie:
            utils.nimplant_print(f"DEBUG: Found token in cookie: {token_from_cookie[:10]}...")
            token = token_from_cookie
        
        # 2. Look in Authorization header
        if not token:
            auth_header = flask.request.headers.get('Authorization')
            utils.nimplant_print(f"DEBUG: Authorization header in verify: {auth_header}")
            
            if auth_header and auth_header.startswith('Bearer '):
                token_from_header = auth_header.split(' ')[1]
                utils.nimplant_print(f"DEBUG: Found token in Authorization header: {token_from_header[:10]}...")
                token = token_from_header
        
        # 3. Look as URL parameter
        token_from_query = flask.request.args.get('token')
        if not token and token_from_query:
            utils.nimplant_print(f"DEBUG: Found token in query parameters: {token_from_query[:10]}...")
            token = token_from_query
            
        if not token:
            utils.nimplant_print(f"DEBUG: No token found in verify request through any method")
            return flask.jsonify({
                "authenticated": False,
                "message": "No authentication token found"
            }), 401
        
        # Manually verify the token
        user = verify_session(token)
        if not user:
            utils.nimplant_print(f"DEBUG: Invalid token in verify request: {token[:10]}...")
            return flask.jsonify({
                "authenticated": False,
                "message": "Invalid or expired token"
            }), 401
            
        # If we get here, the token is valid
        utils.nimplant_print(f"DEBUG: Token verified successfully for user: {user['email']}")
        return flask.jsonify({
            "authenticated": True,
            "user": {
                "email": user["email"],
                "admin": user["admin"]
            }
        }), 200
    
    # Apply authentication middleware to all routes
    if auth_enabled:
        utils.nimplant_print(f"Authentication enabled for API Server")
    else:
        utils.nimplant_print(f"WARNING: Authentication disabled for API Server")
    
    # All existing routes should be protected with require_auth
    @app.route("/api/build", methods=["GET", "POST"])
    @require_auth
    def build():
        import uuid
        
        try:
            # Get build parameters
            debug = False
            workspace = None
            implant_type = "windows"  # default to windows
            architecture = None
            relay_config = None
            
            if flask.request.method == "POST":
                data = flask.request.get_json()
                if data:
                    if "debug" in data:
                        debug = data["debug"]
                    if "workspace" in data:
                        workspace = data["workspace"]
                    if "implant_type" in data:
                        implant_type = data["implant_type"]
                    if "architecture" in data:
                        architecture = data["architecture"]
                    if "relay_config" in data:
                        relay_config = data["relay_config"]
            
            # Generate a unique ID for this build
            build_id = str(uuid.uuid4())
            
            # Initialize the build status
            app.build_status[build_id] = {
                'status': 'pending',
                'message': 'Initializing compilation...',
                'timestamp': datetime.datetime.now().isoformat()
            }
            
            # Start the compilation in a separate thread
            thread = Thread(target=build_process, args=(build_id, debug, workspace, implant_type, architecture, relay_config))
            thread.daemon = True  # The thread will close when the main program terminates
            thread.start()
            
            # Return the build ID immediately
            return flask.jsonify({
                'success': True,
                'message': 'Compilation started in the background',
                'build_id': build_id
            }), 202  # 202 Accepted
            
        except Exception as e:
            error_msg = f"Error starting compilation: {str(e)}"
            utils.nimplant_print(error_msg)
            return flask.jsonify(success=False, error=error_msg), 500
            
    # Endpoint to query the status of a compilation
    @app.route("/api/build/status/<build_id>", methods=["GET"])
    @require_auth
    def build_status(build_id):
        try:
            if not hasattr(app, 'build_status') or build_id not in app.build_status:
                return flask.jsonify({
                    'status': 'unknown',
                    'error': 'Unknown or expired build ID'
                }), 404
            
            status = app.build_status[build_id]
            
            # If the build has finished (successfully or with error), delete the status after returning it
            # to free memory after a reasonable time
            if status.get('status') in ['completed', 'failed'] and 'timestamp' in status:
                # Calculate how much time has passed since it finished
                last_update = datetime.datetime.fromisoformat(status['timestamp'])
                now = datetime.datetime.now()
                elapsed = now - last_update
                
                # If more than 30 minutes have passed, clean up the status
                if elapsed.total_seconds() > 1800:  # 30 minutes
                    del app.build_status[build_id]
                    utils.nimplant_print(f"Build status {build_id} deleted due to expiration")
            
            return flask.jsonify(status), 200
            
        except Exception as e:
            error_msg = f"Error querying build status: {str(e)}"
            utils.nimplant_print(error_msg)
            return flask.jsonify(success=False, error=error_msg), 500

    # Get available commands
    @app.route("/api/commands", methods=["GET"])
    @require_auth
    def get_command_list():
        return flask.jsonify(get_commands()), 200

    # Get available implant build options
    @app.route("/api/build/options", methods=["GET"])
    @require_auth
    def get_build_options():
        return flask.jsonify({
            "implant_types": [
                {
                    "id": "windows",
                    "name": "Windows x64",
                    "description": "Windows implant with full functionality",
                    "icon": "windows",
                    "architectures": [
                        {
                            "id": "x64",
                            "name": "Windows x64",
                            "description": "Standard Windows 64-bit implant"
                        }
                    ]
                },
                {
                    "id": "multi_os",
                    "name": "Multi-Platform",
                    "description": "Cross-platform implant for Linux, macOS, and embedded systems",
                    "icon": "multi_platform",
                    "architectures": [
                        {
                            "id": "all",
                            "name": "All Platforms",
                            "description": "Build for all supported architectures"
                        },
                        {
                            "id": "linux_x64",
                            "name": "Linux x86_64",
                            "description": "Linux 64-bit Intel/AMD"
                        },
                        {
                            "id": "linux_arm64",
                            "name": "Linux ARM64",
                            "description": "Linux 64-bit ARM (Raspberry Pi 4, etc.)"
                        },
                        {
                            "id": "linux_arm",
                            "name": "Linux ARM",
                            "description": "Linux 32-bit ARM (Raspberry Pi 3, etc.)"
                        },
                        {
                            "id": "linux_mipsel",
                            "name": "Linux MIPS Little-Endian",
                            "description": "Linux MIPS (routers, embedded devices)"
                        },
                        {
                            "id": "darwin",
                            "name": "macOS Universal",
                            "description": "Both Intel and Apple Silicon"
                        },
                        {
                            "id": "darwin_intelx64",
                            "name": "macOS Intel x64",
                            "description": "macOS Intel processors"
                        },
                        {
                            "id": "darwin_arm64",
                            "name": "macOS Apple Silicon",
                            "description": "macOS M1/M2/M3 processors"
                        }
                    ]
                }
            ]
        }), 200

    # Get download information
    @app.route("/api/downloads", methods=["GET"])
    @require_auth
    def get_downloads():
        try:
            utils.nimplant_print(f"DEBUG: /api/downloads - Request received")
            
            # Check if filtering by guid
            nimplant_guid = flask.request.args.get('guid')
            utils.nimplant_print(f"DEBUG: /api/downloads - Filtering by GUID: {nimplant_guid}")
            
            downloads_path = os.path.abspath(
                f"downloads/server-{np_server.guid}"
            )
            utils.nimplant_print(f"DEBUG: /api/downloads - Looking in path: {downloads_path}")
            
            # Check if directory exists
            if not os.path.exists(downloads_path):
                utils.nimplant_print(f"DEBUG: /api/downloads - Path not found")
                os.makedirs(downloads_path, exist_ok=True)
                utils.nimplant_print(f"DEBUG: /api/downloads - Created empty directory")
                return flask.jsonify([]), 200
                
            res = []
            try:
                items = os.scandir(downloads_path)
                for item in items:
                    # If filtering by guid, only process that implant's folder
                    if nimplant_guid and item.is_dir() and item.name == f"nimplant-{nimplant_guid}":
                        downloads = os.scandir(item.path)
                        for download in downloads:
                            if download.is_file():
                                res.append(
                                    {
                                        "name": download.name,
                                        "nimplant": nimplant_guid,
                                        "size": download.stat().st_size,
                                        "lastmodified": download.stat().st_mtime,
                                    }
                                )
                    # If no filter, process all folders
                    elif not nimplant_guid and item.is_dir() and item.name.startswith("nimplant-"):
                        downloads = os.scandir(item.path)
                        nimplant_id = item.name.split("-")[1]
                        for download in downloads:
                            if download.is_file():
                                res.append(
                                    {
                                        "name": download.name,
                                        "nimplant": nimplant_id,
                                        "size": download.stat().st_size,
                                        "lastmodified": download.stat().st_mtime,
                                    }
                                )

                res = sorted(res, key=lambda x: x["lastmodified"], reverse=True)
                utils.nimplant_print(f"DEBUG: /api/downloads - Found {len(res)} items")
                return flask.jsonify(res), 200
            except FileNotFoundError:
                utils.nimplant_print(f"DEBUG: /api/downloads - No items found")
                return flask.jsonify([]), 200
        except Exception as e:
            utils.nimplant_print(f"ERROR: /api/downloads - Exception: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: /api/downloads - Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500

    # Download a file from the downloads folder
    @app.route("/api/downloads/<nimplant_guid>/<filename>", methods=["GET"])
    @require_auth
    def get_download(nimplant_guid, filename):
        try:
            # Log detailed request
            utils.nimplant_print(f"DEBUG: get_download - Request URL: {flask.request.url}", skip_db_log=True)
            utils.nimplant_print(f"DEBUG: get_download - Query params: {flask.request.args}", skip_db_log=True)
            
            downloads_path = os.path.abspath(
                f"downloads/server-{np_server.guid}/nimplant-{nimplant_guid}"
            )
            
            # Check if it's a preview request or actual download
            is_preview = flask.request.args.get('preview', 'false').lower() == 'true'
            operation_type = "VIEW" if is_preview else "UI_DOWNLOAD"
            
            utils.nimplant_print(f"DEBUG: get_download - Operation type: {operation_type} (preview param: {is_preview})", skip_db_log=True)
            
            # Try to get the file size before sending it
            try:
                file_path = os.path.join(downloads_path, filename)
                if os.path.exists(file_path):
                    file_size = os.path.getsize(file_path)
                    
                    # Log the operation in the database
                    try:
                        db_log_file_transfer(nimplant_guid, filename, file_size, operation_type)
                        utils.nimplant_print(f"{operation_type} file logged: {filename} ({file_size} bytes)", skip_db_log=True)
                    except Exception as log_error:
                        utils.nimplant_print(f"Error logging {operation_type} file: {str(log_error)}", skip_db_log=True)
            except Exception as size_error:
                utils.nimplant_print(f"Error getting file size: {str(size_error)}", skip_db_log=True)
            
            return flask.send_from_directory(
                downloads_path, filename, as_attachment=True
            )
        except FileNotFoundError:
            return flask.jsonify("File not found"), 404

    # New API route to get file transfer history
    @app.route("/api/file-transfers", methods=["GET"])
    @app.route("/api/file-transfers/<nimplant_guid>", methods=["GET"])
    @require_auth
    def get_file_transfers(nimplant_guid=None):
        try:
            # Get the limit if provided in the query
            limit = flask.request.args.get('limit', 50, type=int)
            
            # Get the transfers
            transfers = db_get_file_transfers_api(nimplant_guid, limit)
            
            return flask.jsonify(transfers), 200
            
        except Exception as e:
            utils.nimplant_print(f"Error getting file transfers: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500

    # Download server compiled implants
    @app.route("/api/get-download/<filename>", methods=["GET"])
    @require_auth
    def get_server_download(filename):
        try:
            utils.nimplant_print(f"Request for file download: {filename}")
            
            # First check if we have the file registered in the application variable
            if hasattr(app, 'download_files') and filename in app.download_files:
                file_path = app.download_files[filename]
                utils.nimplant_print(f"File found in application registry: {file_path}")
                
                if os.path.exists(file_path) and os.path.isfile(file_path):
                    directory = os.path.dirname(file_path)
                    utils.nimplant_print(f"Sending file from {directory}")
                    return flask.send_from_directory(directory, os.path.basename(file_path), as_attachment=True)
                else:
                    utils.nimplant_print(f"Registered file not found in the filesystem: {file_path}")
            
            # Search in multiple possible locations for the file
            possible_paths = [
                # Relative path from the server location
                os.path.abspath("server/downloads"),
                # Path within the Nimhawk project
                os.path.abspath(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))), "server", "downloads")),
                # Path one level up (to handle different structures)
                os.path.abspath(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "downloads")),
                # Path from the project root
                os.path.abspath(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))), "server", "downloads"))
            ]
            
            # Add the current directory path
            current_dir = os.getcwd()
            possible_paths.append(os.path.join(current_dir, "server", "downloads"))
            possible_paths.append(os.path.join(current_dir, "downloads"))
            
            utils.nimplant_print(f"Looking for file {filename} to download")
            
            # Check each possible path
            for path in possible_paths:
                full_path = os.path.join(path, filename)
                utils.nimplant_print(f"Looking in: {full_path}")
                
                if os.path.exists(full_path) and os.path.isfile(full_path):
                    utils.nimplant_print(f"File found at: {full_path}")
                    return flask.send_from_directory(path, filename, as_attachment=True)
            
            # If we get here, the file was not found
            utils.nimplant_print(f"File not found in any location. Paths checked: {possible_paths}")
            
            # Last option: try to search by filename regardless of path
            for root, dirs, files in os.walk(current_dir):
                if filename in files:
                    file_path = os.path.join(root, filename)
                    utils.nimplant_print(f"File found through recursive search: {file_path}")
                    return flask.send_file(file_path, as_attachment=True)
            
            return flask.jsonify(
                error="File not found", 
                paths_checked=possible_paths
            ), 404
            
        except Exception as e:
            error_msg = f"Error downloading file: {str(e)}"
            utils.nimplant_print(error_msg)
            return flask.jsonify(error=error_msg), 500

    # Get server configuration
    @app.route("/api/server", methods=["GET"])
    @require_auth
    def get_server_info():
        utils.nimplant_print(f"DEBUG: /api/server - User authenticated: {flask.g.user}")
        try:
            server_info = db_get_server_info(np_server.guid)
            utils.nimplant_print(f"DEBUG: /api/server - Got server info successfully")
            return flask.jsonify(server_info), 200
        except Exception as e:
            utils.nimplant_print(f"ERROR: /api/server - Exception: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: /api/server - Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500

    # Get the last X lines of console history
    @app.route("/api/server/console", methods=["GET"])
    @app.route("/api/server/console/<lines>", methods=["GET"])
    @app.route("/api/server/console/<lines>/<offset>", methods=["GET"])
    @require_auth
    def get_server_console(lines="1000", offset="0"):
        # Process input as string and check if valid
        if not lines.isnumeric() or not offset.isnumeric():
            return flask.jsonify("Invalid parameters"), 400

        return flask.jsonify(db_get_server_console(np_server.guid, lines, offset)), 200

    # Exit the server
    @app.route("/api/server/exit", methods=["POST"])
    @require_auth
    def post_exit_server():
        Thread(target=utils.exit_server).start()
        return flask.jsonify("Exiting server..."), 200

    # Upload a file to the server's "uploads" folder
    @app.route("/api/upload", methods=["POST"])
    @require_auth
    def post_upload():
        import hashlib
        
        upload_path = os.path.abspath(f"uploads/server-{np_server.guid}")

        if "file" not in flask.request.files:
            return flask.jsonify({"error": "No file part"}), 400

        file = flask.request.files["file"]
        if file.filename == "":
            return flask.jsonify({"error": "No file selected"}), 400

        if file:
            # CRITICAL: Get targetPath if it was sent
            target_path = flask.request.form.get('targetPath', '')
            utils.nimplant_print(f"DEBUG: Received targetPath: '{target_path}'")
            
            # Save the file physically with its original name
            os.makedirs(upload_path, exist_ok=True)
            filename = secure_filename(file.filename)
            full_path = os.path.join(upload_path, filename)
            file.save(full_path)
            
            # Calculate hash of the file
            file_hash = hashlib.md5(full_path.encode("UTF-8")).hexdigest()
            
            # CRITICAL: If there is targetPath, use it as the stored name instead of the original
            original_filename = target_path.strip() if target_path.strip() else filename
            utils.nimplant_print(f"DEBUG: Using filename for DB: '{original_filename}'")
            
            # Store in the database with the correct name
            db_store_file_hash_mapping(file_hash, original_filename, full_path)
            
            # Register the file in the NimPlant object for hosting
            # Find the active nimplant (if any) to host the file
            nimplant_guid = flask.request.args.get('nimplant_guid')
            np = None
            
            if nimplant_guid:
                np = np_server.get_nimplant_by_guid(nimplant_guid)
            
            # If we found a valid nimplant, register the file for hosting
            if np:
                np.host_file(full_path)
                utils.nimplant_print(f"File {filename} registered for hosting with hash {file_hash}", np.guid)
            else:
                # Log error about missing nimplant
                utils.nimplant_print(f"File {filename} uploaded and hash {file_hash} generated, but no valid nimplant to host it")
            
            return flask.jsonify({
                "result": "File uploaded", 
                "path": full_path,
                "hash": file_hash,
                "filename": filename
            }), 200
        else:
            return flask.jsonify({"error": "File upload failed"}), 400

    # Endpoint to list implants (all or by workspace)
    @app.route("/api/nimplants", methods=["GET"])
    @require_auth
    def get_nimplants():
        workspace_uuid = flask.request.args.get('workspace_uuid')
        try:
            # If a workspace_uuid is specified, filter by that workspace
            if workspace_uuid is not None:
                utils.nimplant_print(f"DEBUG: Getting implants for workspace_uuid: {workspace_uuid}")
                nimplants = db_get_nimplants_by_workspace(workspace_uuid)
            else:
                # Otherwise, get all implants
                nimplants = db_get_nimplant_info(np_server.guid)
                utils.nimplant_print(f"DEBUG: Getting all implants, count: {len(nimplants)}")
            
            # For each implant, determine if it's disconnected based on time
            now = datetime.datetime.now()
            for nimplant in nimplants:
                # Check if it's active
                if nimplant.get('active', False):
                    try:
                        # Convert lastCheckin to date object
                        last_checkin = datetime.datetime.strptime(
                            nimplant['lastCheckin'], '%d/%m/%Y %H:%M:%S'
                        )
                        time_diff = now - last_checkin
                        
                        # If more than 5 minutes passed without check-in, it's disconnected
                        if time_diff > datetime.timedelta(minutes=5):
                            nimplant['disconnected'] = True
                        else:
                            nimplant['disconnected'] = False
                    except (ValueError, TypeError) as e:
                        # Error parsing the date, don't mark as disconnected
                        nimplant['disconnected'] = False
                        utils.nimplant_print(f"DEBUG: Error parsing date for implant {nimplant.get('guid')}: {e}")
                else:
                    # If it's not active, it's not disconnected
                    nimplant['disconnected'] = False
            
            # Add workspace name for each implant
            # Create a dictionary of workspace names for quick lookup
            workspace_dict = {}  # Define workspace_dict here - before any calls or exceptions
            try:
                workspaces = db_get_workspaces()
                utils.nimplant_print(f"DEBUG: Total workspaces found: {len(workspaces)}")
                
                # Now we create the dictionary
                workspace_dict = {ws['workspace_uuid']: ws['workspace_name'] for ws in workspaces}
                
                # Browse through the first workspaces for debugging and verify format
                for i, ws in enumerate(workspaces[:5]):
                    utils.nimplant_print(f"DEBUG: Example workspace #{i+1}: uuid={ws.get('workspace_uuid')}, name={ws.get('workspace_name')}")
            except Exception as e:
                utils.nimplant_print(f"ERROR: Could not get workspaces: {e}")
                workspaces = []  # Ensure workspaces is also defined
            
            # Assign workspace name and relay role to each implant
            for nimplant in nimplants:
                ws_uuid = nimplant.get('workspace_uuid')
                
                if not ws_uuid:
                    utils.nimplant_print(f"DEBUG: Implant {nimplant['guid']} has no workspace_uuid assigned")
                    nimplant['workspace_name'] = "Default"
                    continue
                    
                utils.nimplant_print(f"DEBUG: Implant {nimplant['guid']} has workspace_uuid: {ws_uuid}")
                
                # Method 1: Look in preloaded dictionary
                if ws_uuid in workspace_dict:
                    nimplant['workspace_name'] = workspace_dict[ws_uuid]
                    utils.nimplant_print(f"DEBUG: Assigned workspace name from dictionary: {nimplant['workspace_name']}")
                else:
                    # Method 2: Direct database search
                    utils.nimplant_print(f"DEBUG: workspace_uuid {ws_uuid} not found in dictionary, searching directly in DB")
                    try:
                        # Import connection to the DB for direct queries
                        from src.config.db import con
                        
                        workspace_row = con.execute(
                            "SELECT workspace_name FROM workspaces WHERE workspace_uuid = ?", 
                            (ws_uuid,)
                        ).fetchone()
                        
                        if workspace_row and workspace_row[0]:
                            nimplant['workspace_name'] = workspace_row[0]
                            utils.nimplant_print(f"DEBUG: Found in DB: {nimplant['workspace_name']}")
                            # Update dictionary for future lookups
                            workspace_dict[ws_uuid] = workspace_row[0]
                        else:
                            utils.nimplant_print(f"DEBUG: workspace_uuid {ws_uuid} does not exist in the DB: {ws_uuid}")
                            nimplant['workspace_name'] = "Default"
                    except Exception as db_error:
                        utils.nimplant_print(f"ERROR: Direct workspace query failed: {str(db_error)}")
                        nimplant['workspace_name'] = "Default"
                
                # Add relay role information (use from database or default to STANDARD)
                nimplant['relay_role'] = nimplant.get('relay_role') or 'STANDARD'
            
            return flask.jsonify(nimplants)
        except Exception as e:
            utils.nimplant_print(f"Error getting nimplants: {e}")
            import traceback
            utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": str(e)}), 500

    # Get a specific nimplant with its details
    @app.route("/api/nimplants/<guid>", methods=["GET"])
    @require_auth
    def get_nimplant(guid):
        try:
            utils.nimplant_print(f"DEBUG: get_nimplant - Requesting details for GUID: {guid}", skip_db_log=True)
            
            # Get detailed information about this implant from db
            nimplant_info = db_get_nimplant_details(guid)
            
            utils.nimplant_print(f"DEBUG: get_nimplant - db_get_nimplant_details returned: {type(nimplant_info)}", skip_db_log=True)
            
            if not nimplant_info:
                utils.nimplant_print(f"DEBUG: get_nimplant - No implant found for GUID: {guid}", skip_db_log=True)
                return flask.jsonify({"error": "Implant not found"}), 404
            
            utils.nimplant_print(f"DEBUG: get_nimplant - Implant found, processing workspace info", skip_db_log=True)
            
            # Add workspace name
            if 'workspace_uuid' in nimplant_info and nimplant_info['workspace_uuid']:
                # Find the workspace name
                workspaces = db_get_workspaces()
                for ws in workspaces:
                    if ws['workspace_uuid'] == nimplant_info['workspace_uuid']:
                        nimplant_info['workspace_name'] = ws['workspace_name']
                        break
                else:
                    # If not found, use Default
                    nimplant_info['workspace_name'] = "Default"
            else:
                # If it doesn't have workspace_uuid, use Default
                nimplant_info['workspace_name'] = "Default"
            
            utils.nimplant_print(f"DEBUG: get_nimplant - Returning implant info successfully", skip_db_log=True)
            return flask.jsonify(nimplant_info)
        except Exception as e:
            utils.nimplant_print(f"ERROR: get_nimplant - Exception occurred: {e}")
            import traceback
            utils.nimplant_print(f"ERROR: get_nimplant - Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": str(e)}), 500

    # Get the last X lines of console history for a specific nimplant
    @app.route("/api/nimplants/<guid>/console", methods=["GET"])
    @app.route("/api/nimplants/<guid>/console/<lines>", methods=["GET"])
    @app.route("/api/nimplants/<guid>/console/<lines>/<offset>", methods=["GET"])
    @require_auth
    def get_nimplant_console(guid, lines="1000", offset="0"):
        # Process input as string and check if valid
        if not lines.isnumeric() or not offset.isnumeric():
            return flask.jsonify("Invalid parameters"), 400

        # Get parameter to sort results (desc = most recent first)
        order = flask.request.args.get('order', 'asc')

        if np_server.get_nimplant_by_guid(guid):
            return flask.jsonify(db_get_nimplant_console(guid, lines, offset, order)), 200
        else:
            return flask.jsonify("Invalid Implant GUID"), 404

    # Issue a command to a specific nimplant
    @app.route("/api/nimplants/<guid>/command", methods=["POST"])
    @require_auth
    def post_nimplant_command(guid):
        np = np_server.get_nimplant_by_guid(guid)
        data = flask.request.json
        command = data["command"]

        if np and command:
            handle_command(command, np)
            return flask.jsonify(f"Command queued: {command}"), 200
        else:
            return flask.jsonify("Invalid Implant GUID or command"), 404

    # Delete a nimplant from the database (only inactive ones)
    @app.route("/api/nimplants/<guid>", methods=["DELETE"])
    @require_auth
    def delete_nimplant(guid):
        try:
            # First check if the implant exists and get its status
            np = np_server.get_nimplant_by_guid(guid)
            
            if not np:
                utils.nimplant_print(f"DELETE request for non-existent implant: {guid}")
                return flask.jsonify({
                    "success": False,
                    "error": "Implant not found"
                }), 404
            
            # Check if the implant is active but disconnected
            is_disconnected = False
            if np.active:
                try:
                    last_checkin = datetime.datetime.strptime(np.last_checkin, '%d/%m/%Y %H:%M:%S')
                    time_diff = datetime.datetime.now() - last_checkin
                    
                    # If more than 5 minutes passed without check-in, consider it disconnected
                    if time_diff > datetime.timedelta(minutes=5):
                        is_disconnected = True
                except (ValueError, TypeError, AttributeError) as e:
                    utils.nimplant_print(f"Error checking disconnection state: {str(e)}")
            
            # Only prevent deletion if the implant is active AND not disconnected
            if np.active and not is_disconnected:
                utils.nimplant_print(f"Attempt to delete active implant: {guid}")
                return flask.jsonify({
                    "success": False,
                    "error": "Cannot delete an active implant. Kill it first or wait until it disconnects (5+ minutes without check-in)."
                }), 400
            
            # Delete from database
            success, message = db_delete_nimplant(guid)
            
            if success:
                # Also remove from server's in-memory list if it's there
                np_server.nimplant_list = [n for n in np_server.nimplant_list if n.guid != guid]
                
                
                utils.nimplant_print(f"Implant {guid} successfully deleted from database")
                return flask.jsonify({
                    "success": True,
                    "message": "Implant deleted successfully"
                }), 200
            else:
                utils.nimplant_print(f"Error deleting implant {guid}: {message}")
                return flask.jsonify({
                    "success": False,
                    "error": message
                }), 500
        
        except Exception as e:
            utils.nimplant_print(f"Error in delete_nimplant endpoint: {str(e)}")
            import traceback
            utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
            return flask.jsonify({
                "success": False,
                "error": f"Server error: {str(e)}"
            }), 500

    # Exit a specific nimplant
    @app.route("/api/nimplants/<guid>/exit", methods=["POST"])
    @require_auth
    def post_nimplant_exit(guid):
        try:
            utils.nimplant_print(f"DEBUG: Attempting to send kill command to implant with GUID: {guid}")
            
            np = np_server.get_nimplant_by_guid(guid)
            
            if np:
                utils.nimplant_print(f"DEBUG: Current state of pending tasks: {np.pending_tasks}")
                
                # Use the kill() method directly
                np.kill()
                utils.nimplant_print(f"DEBUG: kill() method executed")
                
                # Verify that the task was added correctly
                utils.nimplant_print(f"DEBUG: Pending tasks state after kill(): {np.pending_tasks}")
                
                # If we use the kill() method, we don't need to call db_update_nimplant manually 
                # since the kill() method already does it
                
                # Verify pending tasks in the database
                try:
                    from src.config.db import con
                    db_tasks = con.execute(
                        "SELECT pendingTasks FROM nimplant WHERE guid = ?", (guid,)
                    ).fetchone()
                    
                    if db_tasks and db_tasks[0]:
                        utils.nimplant_print(f"DEBUG: Pending tasks in the database: {db_tasks[0]}")
                        return flask.jsonify({"success": True, "message": "Kill command sent to Implant"}), 200
                    else:
                        utils.nimplant_print(f"DEBUG: No pending tasks found in the database")
                        # Try to add the task again, but in a more direct way
                        command_guid = np.add_task(["kill"], task_friendly="kill")
                        utils.nimplant_print(f"DEBUG: Additional attempt to add kill task, GUID: {command_guid}")
                        utils.nimplant_print(f"DEBUG: Final state of pending tasks: {np.pending_tasks}")
                        
                        # Make sure the implant is active
                        np.active = True
                        np.late = False
                        db.db_update_nimplant(np)
                        
                        return flask.jsonify({"success": True, "message": "Kill command sent to Implant (retry method)"}), 200
                except Exception as db_error:
                    utils.nimplant_print(f"ERROR checking database: {str(db_error)}")
                    import traceback
                    utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
                    
                    # If there's an error in verification, we assume it was successful
                    return flask.jsonify({"success": True, "message": "Kill command sent to Implant (assumed)"}), 200
            else:
                utils.nimplant_print(f"DEBUG: Implant with GUID {guid} not found in server list")
                
                # Try to find in the database
                implant_info = db_get_nimplant_details(guid)
                if implant_info:
                    utils.nimplant_print(f"DEBUG: Implant found in database but not in server list. May be inactive or disconnected.")
                    return flask.jsonify({"error": "Implant exists but is not active. Try deleting instead."}), 400
                else:
                    utils.nimplant_print(f"DEBUG: Implant with GUID {guid} not found in database")
                    return flask.jsonify({"error": "Invalid Implant GUID"}), 404
                    
        except Exception as e:
            utils.nimplant_print(f"ERROR in post_nimplant_exit: {str(e)}")
            import traceback
            utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": f"Server error: {str(e)}"}), 500
            
    # Endpoint to list workspaces
    @app.route("/api/workspaces", methods=["GET"])
    @require_auth
    def api_get_workspaces():
        try:
            workspaces = db_get_workspaces()
            return flask.jsonify(workspaces), 200
        except Exception as e:
            utils.nimplant_print(f"Error getting workspaces: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500
            
    @app.route("/api/workspaces", methods=["POST"])
    @require_auth
    def api_create_workspace():
        try:
            data = flask.request.json
            if not data or "workspace_name" not in data:
                return flask.jsonify({"error": "Missing workspace name"}), 400
                
            workspace_name = data["workspace_name"]
            workspace_uuid = db_create_workspace(workspace_name)
            
            if workspace_uuid:
                return flask.jsonify({
                    "workspace_uuid": workspace_uuid,
                    "workspace_name": workspace_name,
                    "creation_date": utils_time.timestamp()
                }), 201
            else:
                return flask.jsonify({"error": "Failed to create workspace"}), 500
                
        except Exception as e:
            utils.nimplant_print(f"Error creating workspace: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500
            
    @app.route("/api/workspaces/<workspace_uuid>", methods=["DELETE"])
    @require_auth
    def api_delete_workspace(workspace_uuid):
        try:
            success = db_delete_workspace(workspace_uuid)
            if success:
                return flask.jsonify({"success": True, "message": "Workspace deleted"}), 200
            else:
                return flask.jsonify({"error": "Failed to delete workspace"}), 500
                
        except Exception as e:
            utils.nimplant_print(f"Error deleting workspace: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500
            
    @app.route("/api/workspaces/<workspace_uuid>/nimplants", methods=["GET"])
    @require_auth
    def get_nimplants_in_workspace(workspace_uuid):
        try:
            nimplants = db_get_nimplants_by_workspace(workspace_uuid)
            return flask.jsonify(nimplants), 200
            
        except Exception as e:
            utils.nimplant_print(f"Error getting nimplants in workspace: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500
            
    @app.route("/api/workspaces/assign", methods=["POST"])
    @require_auth
    def assign_to_workspace():
        try:
            data = flask.request.get_json()
            if not data or "nimplant_guid" not in data or "workspace_uuid" not in data:
                return flask.jsonify({"error": "Both nimplant_guid and workspace_uuid are required"}), 400
                
            nimplant_guid = data["nimplant_guid"]
            workspace_uuid = data["workspace_uuid"]
            
            success = db_assign_nimplant_to_workspace(nimplant_guid, workspace_uuid)
            if success:
                return flask.jsonify({"success": True, "message": "Nimplant assigned to workspace"}), 200
            else:
                return flask.jsonify({"error": "Failed to assign nimplant to workspace"}), 500
                
        except Exception as e:
            utils.nimplant_print(f"Error assigning nimplant to workspace: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500
            
    @app.route("/api/workspaces/remove", methods=["POST"])
    @require_auth
    def remove_from_workspace():
        try:
            data = flask.request.get_json()
            if not data or "nimplant_guid" not in data:
                return flask.jsonify({"error": "nimplant_guid is required"}), 400
                
            nimplant_guid = data["nimplant_guid"]
            
            success = db_remove_nimplant_from_workspace(nimplant_guid)
            if success:
                return flask.jsonify({"success": True, "message": "Nimplant removed from workspace"}), 200
            else:
                return flask.jsonify({"error": "Failed to remove nimplant from workspace"}), 500
                
        except Exception as e:
            utils.nimplant_print(f"Error removing nimplant from workspace: {str(e)}")
            import traceback
            utils.nimplant_print(f"DEBUG: Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500

    # ============================================================================
    # RELAY CHAIN RELATIONSHIPS ENDPOINTS  
    # ============================================================================

    @app.route("/api/chain-relationships", methods=["GET"])
    @require_auth
    def get_chain_relationships():
        """Get all chain relationship information for distributed topology visualization"""
        try:
            from ...config import db
            
            relationships = db.db_get_all_chain_relationships()
            
            # Convert to format suitable for frontend
            chain_data = []
            for rel in relationships:
                chain_data.append({
                    "nimplant_guid": rel["nimplant_guid"],
                    "parent_guid": rel["parent_guid"],
                    "role": rel["role"],
                    "listening_port": rel["listening_port"],
                    "last_update": rel["last_update"],
                    "hostname": rel["hostname"],
                    "username": rel["username"],
                    "internal_ip": rel["internal_ip"],
                    "external_ip": rel["external_ip"],
                    "os_build": rel["os_build"],
                    "status": "online" if rel["active"] else "disconnected" if not rel["active"] else "late" if rel["late"] else "unknown"
                })
            
            utils.nimplant_print(f"🔗 API: Returned {len(chain_data)} chain relationships")
            
            return flask.jsonify({
                "chain_relationships": chain_data,
                "total_count": len(chain_data)
            })
            
        except Exception as e:
            utils.nimplant_print(f"Error getting chain relationships: {e}")
            import traceback
            utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
            return flask.jsonify({"error": "Internal server error"}), 500

    @app.errorhandler(Exception)
    def all_exception_handler(error):
        # Improved error logging
        utils.nimplant_print(f"ERROR in route {flask.request.path}: {str(error)}")
        utils.nimplant_print(f"Error type: {type(error).__name__}")
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
        
        return flask.jsonify({
            "status": "error",
            "message": str(error),
            "path": flask.request.path,
            "error_type": type(error).__name__
        }), 500

    # Configure API-only CORS settings
    CORS(
        app,
        supports_credentials=True,
        resources={r"/*": {"origins": "*"}},
        allow_headers=["Content-Type", "Authorization", "X-Requested-With"],
        methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    )

    # Configure preflight OPTIONS responses (without adding duplicates)
    @app.after_request
    def after_request(response):
        # Only add CORS headers if they don't exist already
        if 'Access-Control-Allow-Origin' not in response.headers:
            # If request has Origin header, use that value, otherwise use '*'
            origin = flask.request.headers.get('Origin')
            if origin:
                response.headers.add('Access-Control-Allow-Origin', origin)
            else:
                response.headers.add('Access-Control-Allow-Origin', '*')
        
        # Specify allowed headers (if they don't exist already)
        if 'Access-Control-Allow-Headers' not in response.headers:
            response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
        
        # Specify allowed methods (if they don't exist already)
        if 'Access-Control-Allow-Methods' not in response.headers:
            response.headers.add('Access-Control-Allow-Methods', 'GET, PUT, POST, DELETE, OPTIONS')
        
        # Always allow credentials (important for cookies)
        if 'Access-Control-Allow-Credentials' not in response.headers:
            response.headers.add('Access-Control-Allow-Credentials', 'true')
        
        # Ensure the pre-flight response has a 200 status code
        if flask.request.method == 'OPTIONS' and response.status_code == 500:
            return flask.make_response(('', 200))
            
        return response

    # Create dynamic proxy endpoints for Implants Server routes
    utils.nimplant_print(f"DEBUG: Setting up dynamic Implants Server proxy...")
    try:
        implants_server_proxy.create_proxy_endpoints(app, require_auth)
        utils.nimplant_print(f"DEBUG: Implants Server proxy endpoints created successfully")
        
        # Check Implants Server health
        if implants_server_proxy.health_check():
            utils.nimplant_print(f"DEBUG: Implants Server health check: OK")
        else:
            utils.nimplant_print(f"WARNING: Implants Server health check failed - proxy endpoints may not work")
            
    except Exception as e:
        utils.nimplant_print(f"ERROR: Failed to setup Implants Server proxy: {e}")
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}")

    # Print all registered routes for debugging
    utils.nimplant_print(f"DEBUG: All registered routes in admin_server:")
    for rule in app.url_map.iter_rules():
        utils.nimplant_print(f"DEBUG:   {rule.endpoint} => {rule.rule} [{', '.join(rule.methods)}]")

    http_server = WSGIServer((server_ip, server_port), app, log=None)
    http_server.serve_forever()
