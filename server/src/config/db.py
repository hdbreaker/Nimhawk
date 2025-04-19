import sqlite3
import src.servers.admin_api.commands.commands as commands
import src.servers.admin_api.models.nimplant_listener_model as listener
from src.servers.admin_api.models.nimplant_client_model import NimPlant
from src.global_models.c2_server_models import Server
import src.util.utils as utils
import src.util.time as utils_time
import hashlib
import os
import json
from src.config.config import config

db_path = "nimhawk.db"
con = sqlite3.connect(
    db_path, check_same_thread=False, detect_types=sqlite3.PARSE_DECLTYPES
)

# Use the Row type to allow easy conversions to dicts
con.row_factory = sqlite3.Row

# Handle bool as 1 (True) and 0 (False)
sqlite3.register_adapter(bool, int)
sqlite3.register_converter("BOOLEAN", lambda v: bool(int(v)))

# Flag to track if database has been initialized
db_initialized = False

# Function to verify if the database file exists
def db_file_exists():
    return os.path.exists(db_path) and os.path.isfile(db_path)

#
#   BASIC FUNCTIONALITY (Nimhawk)
#

def initialize_database():
    global db_initialized
    try:
        # First check if the database already exists and contains the necessary tables
        if db_file_exists():
            try:
                # Check if the database has the required tables
                table_count = con.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0]
                if table_count > 0:
                    # Database exists and has tables, no need to reinitialize schema
                    utils.nimplant_print("Database already exists and has tables, skipping schema initialization", skip_db_log=True)
                    db_initialized = True
                    # Still initialize default users if needed
                    initialize_default_users()
                    return
            except sqlite3.Error as e:
                utils.nimplant_print(f"Error checking existing database: {e}, will reinitialize", skip_db_log=True)
                # Continue with initialization if there was an error checking the database
                
        # File doesn't exist or is empty/corrupted, create new database
        file_existed = db_file_exists()
        utils.nimplant_print(f"Database file {'exists but needs initialization' if file_existed else 'does not exist'}", skip_db_log=True)
        
        utils.nimplant_print("Initializing database...", skip_db_log=True)
        
        # Create the server (configuration) table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS server
        (guid TEXT PRIMARY KEY, name TEXT, dateCreated DATETIME,
        xorKey INTEGER, managementIp TEXT, managementPort INTEGER, 
        listenerType TEXT, serverIp TEXT, listenerHost TEXT, listenerPort INTEGER, 
        registerPath TEXT, taskPath TEXT, resultPath TEXT, reconnectPath TEXT, implantCallbackIp TEXT, riskyMode BOOLEAN,
        sleepTime INTEGER, sleepJitter INTEGER, killDate TEXT,
        userAgent TEXT, httpAllowCommunicationKey TEXT, killed BOOLEAN)
        """
        )

        # Create the workspaces table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS workspaces
        (id INTEGER PRIMARY KEY AUTOINCREMENT, workspace_uuid TEXT UNIQUE, 
        workspace_name TEXT, creation_date TEXT)
        """
        )

        # Create the nimplant table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS nimplant
        (id INTEGER, guid TEXT PRIMARY KEY, serverGuid TEXT, active BOOLEAN, late BOOLEAN,
        cryptKey TEXT, ipAddrExt TEXT, ipAddrInt TEXT, username TEXT,
        hostname TEXT, osBuild TEXT, pid INTEGER, pname TEXT, riskyMode BOOLEAN,
        sleepTime INTEGER, sleepJitter INTEGER, killDate TEXT,
        firstCheckin TEXT, lastCheckin TEXT, pendingTasks TEXT,
        hostingFile TEXT, receivingFile TEXT, lastUpdate TEXT,
        workspace_uuid TEXT,
        FOREIGN KEY (serverGuid) REFERENCES server(guid),
        FOREIGN KEY (workspace_uuid) REFERENCES workspaces(workspace_uuid))
        """
        )

        # Create the server_history table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS server_history
        (id INTEGER PRIMARY KEY AUTOINCREMENT, serverGuid TEXT, result TEXT, resultTime TEXT,
        FOREIGN KEY (serverGuid) REFERENCES server(guid))
        """
        )

        # Create the nimplant_history table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS nimplant_history
        (id INTEGER PRIMARY KEY AUTOINCREMENT, nimplantGuid TEXT, taskGuid TEXT, task TEXT, taskFriendly TEXT,
        taskTime TEXT, result TEXT, resultTime TEXT, is_checkin BOOLEAN DEFAULT 0,
        FOREIGN KEY (nimplantGuid) REFERENCES nimplant(guid))
        """
        )

        # Create the file_transfers table to track file uploads and downloads
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS file_transfers
        (id INTEGER PRIMARY KEY AUTOINCREMENT, nimplantGuid TEXT, filename TEXT, size INTEGER,
        operation_type TEXT, timestamp TEXT,
        FOREIGN KEY (nimplantGuid) REFERENCES nimplant(guid))
        """
        )

        # Create a table to store file hash mappings to original filenames
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS file_hash_mapping
        (file_hash TEXT PRIMARY KEY, original_filename TEXT, file_path TEXT, upload_timestamp TEXT)
        """
        )

        # Create the users table
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS users
        (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE, 
        password_hash TEXT, salt TEXT, admin BOOLEAN, active BOOLEAN, 
        last_login TEXT, created_at TEXT)
        """
        )

        # Create session table for user authentication
        con.execute(
            """
        CREATE TABLE IF NOT EXISTS sessions
        (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, 
        token TEXT UNIQUE, created_at TEXT, expires_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id))
        """
        )

        # Migrate existing table to add new columns if they don't exist
        # This check is necessary to avoid errors if the column already exists
        try:
            con.execute("ALTER TABLE server ADD COLUMN reconnectPath TEXT")
            con.execute("ALTER TABLE server ADD COLUMN httpAllowCommunicationKey TEXT")
            con.commit()
            utils.nimplant_print("Database migrated - New columns added", skip_db_log=True)
        except sqlite3.OperationalError:
            # Column already exists, no problem
            pass
            
        # Migrate nimplant_history to add is_checkin column if it doesn't exist
        try:
            con.execute("ALTER TABLE nimplant_history ADD COLUMN is_checkin BOOLEAN DEFAULT 0")
            con.commit()
            utils.nimplant_print("Database migrated - is_checkin column added to nimplant_history", skip_db_log=True)
        except sqlite3.OperationalError:
            # Column already exists, no problem
            pass
            
        # Check if the file_hash_mapping table already exists
        try:
            # Check if the file_hash_mapping table already exists
            table_exists = con.execute(
                """SELECT count(*) FROM sqlite_master 
                   WHERE type='table' AND name='file_hash_mapping'"""
            ).fetchone()[0]
            
            if not table_exists:
                # Create the table if it doesn't exist
                con.execute(
                    """
                CREATE TABLE IF NOT EXISTS file_hash_mapping
                (file_hash TEXT PRIMARY KEY, original_filename TEXT, file_path TEXT, upload_timestamp TEXT)
                """
                )
                utils.nimplant_print("Created file_hash_mapping table for mapping file hashes", skip_db_log=True)
            else:
                utils.nimplant_print("The file_hash_mapping table already exists", skip_db_log=True)
        except sqlite3.OperationalError as e:
            utils.nimplant_print(f"Error checking file_hash_mapping table: {e}", skip_db_log=True)

        # Migrate nimplant table to add workspace_uuid if it doesn't exist
        try:
            con.execute("ALTER TABLE nimplant ADD COLUMN workspace_uuid TEXT")
            con.execute("ALTER TABLE nimplant ADD FOREIGN KEY (workspace_uuid) REFERENCES workspaces(workspace_uuid)")
            con.commit()
            utils.nimplant_print("Database migrated - Added workspace_uuid column to nimplant table", skip_db_log=True)
        except sqlite3.OperationalError:
            # Column already exists, no problem
            pass

        # Commit all table creations
        con.commit()
        
        # Mark database as initialized
        db_initialized = True
        utils.nimplant_print("Database schema initialized successfully", skip_db_log=True)

        # Initialize default user if configured
        initialize_default_users()

    except Exception as e:
        utils.nimplant_print(f"DB error during initialization: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)

# Function to ensure database is initialized before operations
def ensure_db_initialized():
    global db_initialized
    if not db_initialized:
        initialize_database()
    return db_initialized

# Function to generate a random salt
def generate_salt():
    return os.urandom(32).hex()

# Function to hash a password with a salt
def hash_password(password, salt):
    # Combine the password and salt, then hash using SHA-256
    password_hash = hashlib.pbkdf2_hmac(
        'sha256', 
        password.encode(), 
        salt.encode(), 
        100000  # Number of iterations
    ).hex()
    return password_hash

# Initialize default users from config.toml
def initialize_default_users():
    try:
        # Check if we have users in the database
        users_count = con.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        
        # If we already have users, skip initialization
        if users_count > 0:
            utils.nimplant_print("Users already exist, skipping initialization", skip_db_log=True)
            return
        
        # Try to get users from config.toml
        if "auth" in config and "users" in config["auth"]:
            for user in config["auth"]["users"]:
                email = user.get("email")
                password = user.get("password")
                is_admin = user.get("admin", False)
                
                if email and password:
                    create_user(email, password, is_admin)
                    utils.nimplant_print(f"Created user from config: {email}", skip_db_log=True)
        else:
            # If no users in config, create default admin user
            create_user("admin@nimhawk.com", "P4ssw0rd123$", True)
            utils.nimplant_print("Created default admin user: admin@nimhawk.com", skip_db_log=True)
            
    except Exception as e:
        utils.nimplant_print(f"Error initializing default users: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)

# Create a new user
def create_user(email, password, is_admin=False):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot create user, database not initialized", skip_db_log=True)
            return False
            
        # Generate a new salt for this user
        salt = generate_salt()
        
        # Hash the password with the salt
        password_hash = hash_password(password, salt)
        
        # Get current timestamp
        timestamp = utils_time.timestamp()
        
        # Insert the new user
        con.execute(
            """INSERT INTO users (email, password_hash, salt, admin, active, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (email, password_hash, salt, is_admin, True, timestamp)
        )
        con.commit()
        return True
        
    except Exception as e:
        utils.nimplant_print(f"Error creating user: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False

# Authenticate a user
def authenticate_user(email, password):
    try:
        utils.nimplant_print(f"DEBUG: authenticate_user - Searching for user: {email}", skip_db_log=True)
        
        # Get the user by email
        user = con.execute(
            """SELECT * FROM users WHERE email = ? AND active = 1""",
            (email,)
        ).fetchone()
        
        if not user:
            utils.nimplant_print(f"DEBUG: authenticate_user - User not found: {email}", skip_db_log=True)
            return None
        
        utils.nimplant_print(f"DEBUG: authenticate_user - User found: {email}, verifying password", skip_db_log=True)
        
        # Hash the provided password with the user's salt
        password_hash = hash_password(password, user["salt"])
        
        # Check if the hashed password matches
        if password_hash == user["password_hash"]:
            utils.nimplant_print(f"DEBUG: authenticate_user - Password correct for: {email}", skip_db_log=True)
            
            # Update last_login timestamp
            timestamp = utils_time.timestamp()
            con.execute(
                """UPDATE users SET last_login = ? WHERE id = ?""",
                (timestamp, user["id"])
            )
            con.commit()
            
            # Return user info (excluding sensitive data)
            return {
                "id": user["id"],
                "email": user["email"],
                "admin": user["admin"],
                "last_login": timestamp
            }
        else:
            utils.nimplant_print(f"DEBUG: authenticate_user - Password incorrect for: {email}", skip_db_log=True)
            utils.nimplant_print(f"DEBUG: Password hash calculated: {password_hash[:10]}...", skip_db_log=True)
            utils.nimplant_print(f"DEBUG: Password hash stored: {user['password_hash'][:10]}...", skip_db_log=True)
            return None
            
    except Exception as e:
        utils.nimplant_print(f"Authentication error: {e}")
        import traceback
        utils.nimplant_print(f"DEBUG: authenticate_user - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return None

# Create a new session token for a user
def create_session(user_id):
    try:
        utils.nimplant_print(f"DEBUG: create_session - Creating session for user_id: {user_id}", skip_db_log=True)
        
        # Generate a random token
        token = os.urandom(32).hex()
        
        # Get current timestamp
        created_at = utils_time.timestamp()
        utils.nimplant_print(f"DEBUG: create_session - Creation timestamp: {created_at}", skip_db_log=True)
        
        # Set expiration to 24 hours from now
        import datetime
        
        # Parse the date in the correct format (dd/MM/yyyy HH:mm:ss)
        try:
            # If timestamp is in ISO format, use fromisoformat
            if 'T' in created_at and '-' in created_at:
                dt_object = datetime.datetime.fromisoformat(created_at)
            else:
                # If it's in format dd/MM/yyyy HH:mm:ss, use strptime
                dt_object = datetime.datetime.strptime(created_at, '%d/%m/%Y %H:%M:%S')
                
            # Calculate expiration date (24 hours later)
            expires_dt = dt_object + datetime.timedelta(hours=24)
            
            # Convert to ISO format for storage
            expires_at = expires_dt.isoformat()
        except ValueError as e:
            # If there's an error with the format, use current date
            utils.nimplant_print(f"DEBUG: create_session - Error parsing date: {e}", skip_db_log=True)
            expires_at = (datetime.datetime.now() + datetime.timedelta(hours=24)).isoformat()
        
        utils.nimplant_print(f"DEBUG: create_session - Token generated, expires: {expires_at}", skip_db_log=True)
        
        # Insert the new session
        con.execute(
            """INSERT INTO sessions (user_id, token, created_at, expires_at)
               VALUES (?, ?, ?, ?)""",
            (user_id, token, created_at, expires_at)
        )
        con.commit()
        
        utils.nimplant_print(f"DEBUG: create_session - Session saved in DB", skip_db_log=True)
        return token
        
    except Exception as e:
        utils.nimplant_print(f"Error creating session: {e}")
        import traceback
        utils.nimplant_print(f"DEBUG: create_session - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return None

# Verify a session token
def verify_session(token):
    try:
        if not token:
            utils.nimplant_print(f"DEBUG: verify_session - No token provided", skip_db_log=True)
            return None
            
        utils.nimplant_print(f"DEBUG: verify_session - Token to verify: {token[:10]}...", skip_db_log=True)
            
        # Get current timestamp
        now = utils_time.timestamp()
        utils.nimplant_print(f"DEBUG: verify_session - Verifying token with current date: {now}", skip_db_log=True)
        
        # Get the session
        session = con.execute(
            """SELECT s.*, u.email, u.admin 
               FROM sessions s
               JOIN users u ON s.user_id = u.id
               WHERE s.token = ?""",
            (token,)
        ).fetchone()
        
        if not session:
            utils.nimplant_print(f"DEBUG: verify_session - Token not found in database", skip_db_log=True)
            return None
            
        utils.nimplant_print(f"DEBUG: verify_session - Token found in database, session: {dict(session)}", skip_db_log=True)
        
        # Convert to datetime object for comparison
        import datetime
        
        # Check expiration
        expires_at = session["expires_at"]
        utils.nimplant_print(f"DEBUG: verify_session - Expiration date: {expires_at}", skip_db_log=True)
        
        # Convert dates to datetime objects
        try:
            # Convert now to datetime object
            if 'T' in now and '-' in now:
                now_dt = datetime.datetime.fromisoformat(now)
            else:
                now_dt = datetime.datetime.strptime(now, '%d/%m/%Y %H:%M:%S')
            
            # Convert expires_at to datetime object
            if 'T' in expires_at and '-' in expires_at:
                expires_dt = datetime.datetime.fromisoformat(expires_at)
            else:
                expires_dt = datetime.datetime.strptime(expires_at, '%d/%m/%Y %H:%M:%S')
                
            # Check if session has expired
            if now_dt > expires_dt:
                utils.nimplant_print(f"DEBUG: verify_session - Session expired", skip_db_log=True)
                return None
                
            utils.nimplant_print(f"DEBUG: verify_session - Session valid", skip_db_log=True)
        except ValueError as e:
            utils.nimplant_print(f"DEBUG: verify_session - Error parsing date: {e}", skip_db_log=True)
            # If there's a parsing error, use another strategy
            try:
                # Try to compare strings directly if they're in the same format
                if now > expires_at:
                    utils.nimplant_print(f"DEBUG: verify_session - Session expired (string comparison)", skip_db_log=True)
                    return None
            except Exception as comp_error:
                utils.nimplant_print(f"DEBUG: verify_session - Error in comparison: {comp_error}", skip_db_log=True)
                # In case of error, assume the session is valid
        
        utils.nimplant_print(f"DEBUG: verify_session - Session valid for user: {session['email']}", skip_db_log=True)
        return {
            "user_id": session["user_id"],
            "email": session["email"],
            "admin": session["admin"]
        }
        
    except Exception as e:
        utils.nimplant_print(f"Error verifying session: {e}")
        import traceback
        utils.nimplant_print(f"DEBUG: verify_session - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return None

# Delete a session token
def delete_session(token):
    try:
        con.execute(
            """DELETE FROM sessions WHERE token = ?""",
            (token,)
        )
        con.commit()
        return True
        
    except Exception as e:
        utils.nimplant_print(f"Error deleting session: {e}")
        return False

# Define a function to compare the config to the last server object
def db_is_previous_server_same_config(nimplant_server: Server, xor_key) -> bool:
    try:
        nimplant_server = nimplant_server.asdict()

        # Get the previous server object
        previous_server = con.execute(
            """SELECT * FROM server WHERE NOT killed ORDER BY dateCreated DESC LIMIT 1"""
        ).fetchone()

        # If there is no previous server object, return True
        if previous_server is None:
            return False

        # Compare the config to the previous server object
        if (
            xor_key != previous_server["xorKey"]
            or nimplant_server["managementIp"] != previous_server["managementIp"]
            or nimplant_server["managementPort"] != previous_server["managementPort"]
            or nimplant_server["listenerType"] != previous_server["listenerType"]
            or nimplant_server["serverIp"] != previous_server["serverIp"]
            or nimplant_server["listenerHost"] != previous_server["listenerHost"]
            or nimplant_server["listenerPort"] != previous_server["listenerPort"]
            or nimplant_server["registerPath"] != previous_server["registerPath"]
            or nimplant_server["taskPath"] != previous_server["taskPath"]
            or nimplant_server["resultPath"] != previous_server["resultPath"]
            or nimplant_server["reconnectPath"] != previous_server["reconnectPath"]
            or nimplant_server["riskyMode"] != previous_server["riskyMode"]
            or nimplant_server["killDate"] != previous_server["killDate"]
            or nimplant_server["userAgent"] != previous_server["userAgent"]
            or nimplant_server["httpAllowCommunicationKey"] != previous_server["httpAllowCommunicationKey"]
        ):
            return False

        return True

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")

# Get the previous server object for session restoring
def db_get_previous_server_config():
    try:
        # Get the previous server object
        return con.execute(
            """SELECT * FROM server WHERE NOT killed ORDER BY dateCreated DESC LIMIT 1"""
        ).fetchone()

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")

# Get all the Implants for the previous server object
def db_get_previous_nimplants(server_guid):
    try:
        return con.execute(
            """SELECT * FROM nimplant WHERE serverGuid = ?""",
            (server_guid,),
        ).fetchall()

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")

# Create the server object (only runs when config has changed or no object exists)
def db_initialize_server(np_server: Server):
    try:
        con.execute(
            """INSERT INTO server
                       VALUES (:guid, :name, CURRENT_TIMESTAMP, :xorKey, :managementIp, :managementPort,
                       :listenerType, :serverIp, :listenerHost, :listenerPort, :registerPath,
                       :taskPath, :resultPath, :reconnectPath, :implantCallbackIp, :riskyMode, :sleepTime, :sleepJitter,
                       :killDate, :userAgent, :httpAllowCommunicationKey, :killed)""",
            np_server.asdict(),
        )
        con.commit()

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")

# Mark the server object as killed in the database, preventing it from being restored on next boot
def kill_server_in_db(server_guid):
    try:
        con.execute(
            """UPDATE server SET killed = 1 WHERE guid = ?""",
            (server_guid,),
        )
        con.commit()

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")

# Create a new nimplant object (runs once when Implant first checks in)
def db_initialize_nimplant(np: NimPlant, server_guid):
    try:
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Starting insertion of Implant {np.guid} for server {server_guid}", skip_db_log=True)
        
        # Check if an implant with this GUID already exists
        existing = con.execute(
            """SELECT guid FROM nimplant WHERE guid = ?""",
            (np.guid,)
        ).fetchone()
        
        # Check if the implant has a workspace_uuid
        workspace_uuid = getattr(np, "workspace_uuid", "")
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Implant workspace_uuid: {workspace_uuid}", skip_db_log=True)
        
        obj = {
            "id": np.id,
            "guid": np.guid,
            "serverGuid": server_guid,
            "active": np.active,
            "late": np.late,
            "cryptKey": np.encryption_key,
            "ipAddrExt": np.ip_external,
            "ipAddrInt": np.ip_internal,
            "username": np.username,
            "hostname": np.hostname,
            "osBuild": np.os_build,
            "pid": np.pid,
            "pname": np.pname,
            "riskyMode": np.risky_mode,
            "sleepTime": np.sleep_time,
            "sleepJitter": np.sleep_jitter,
            "killDate": np.kill_date,
            "firstCheckin": np.first_checkin,
            "lastCheckin": np.last_checkin,
            "pendingTasks": ", ".join([t for t in np.pending_tasks]),
            "hostingFile": np.hosting_file,
            "receivingFile": np.receiving_file,
            "lastUpdate": utils_time.timestamp(),
            "workspace_uuid": workspace_uuid
        }
        
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Object data prepared: {obj}", skip_db_log=True)

        # If it already exists, update instead of insert
        if existing:
            # Update existing implant
            con.execute(
                """UPDATE nimplant SET
                   active = :active, late = :late, cryptKey = :cryptKey,
                   ipAddrExt = :ipAddrExt, ipAddrInt = :ipAddrInt,
                   username = :username, hostname = :hostname, 
                   osBuild = :osBuild, pid = :pid, pname = :pname,
                   riskyMode = :riskyMode, sleepTime = :sleepTime,
                   sleepJitter = :sleepJitter, killDate = :killDate,
                   lastCheckin = :lastCheckin, pendingTasks = :pendingTasks,
                   hostingFile = :hostingFile, receivingFile = :receivingFile,
                   lastUpdate = :lastUpdate, workspace_uuid = :workspace_uuid
                 WHERE guid = :guid""",
                obj,
            )
        else:
            # Insert new implant
            con.execute(
                """INSERT INTO nimplant VALUES
                   (:id, :guid, :serverGuid, :active, :late,
                   :cryptKey, :ipAddrExt, :ipAddrInt, :username, :hostname, :osBuild, :pid, :pname,
                   :riskyMode, :sleepTime, :sleepJitter, :killDate, :firstCheckin,
                   :lastCheckin, :pendingTasks, :hostingFile, :receivingFile, :lastUpdate, :workspace_uuid)""",
                obj,
            )
        
        con.commit()
        
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Implant successfully inserted", skip_db_log=True)
        
        # Verify that the insert was successful
        verify = con.execute("SELECT guid FROM nimplant WHERE guid = ?", (np.guid,)).fetchone()
        if verify:
            utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Verification successful, Implant found in DB", skip_db_log=True)
        else:
            utils.nimplant_print(f"DEBUG: db_initialize_nimplant - ERROR: Verification failed, Implant not found in DB", skip_db_log=True)

    except Exception as e:
        try:
            con.rollback()
        except Exception as rollback_error:
            utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Rollback error: {rollback_error}", skip_db_log=True)
            
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - ERROR: {str(e)}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_initialize_nimplant - Traceback: {traceback.format_exc()}", skip_db_log=True)

# Update an existing nimplant object (runs every time Implant checks in)
def db_update_nimplant(np: NimPlant):
    try:
        # Get the workspace_uuid (if it exists)
        workspace_uuid = getattr(np, "workspace_uuid", "")
        
        # Process pendingTasks to ensure it is saved correctly
        if np.pending_tasks:
            # If it's already a string and doesn't contain brackets, assume it's a string list
            if isinstance(np.pending_tasks, str) and not (np.pending_tasks.startswith('[') and np.pending_tasks.endswith(']')):
                pending_tasks = np.pending_tasks
            else:
                # If it's a list, convert to string separated by commas
                try:
                    if isinstance(np.pending_tasks, list):
                        utils.nimplant_print(f"DEBUG: Converting pending_tasks list to string: {np.pending_tasks}")
                        pending_tasks = ", ".join([str(t) for t in np.pending_tasks])
                    else:
                        # If it's neither a string nor a list, convert to string
                        pending_tasks = str(np.pending_tasks)
                except Exception as e:
                    utils.nimplant_print(f"DEBUG: Error formatting pending_tasks: {str(e)}")
                    pending_tasks = ""
        else:
            pending_tasks = ""
            
        utils.nimplant_print(f"DEBUG: Final pending_tasks value: {pending_tasks}")
        
        obj = {
            "guid": np.guid,
            "active": np.active,
            "late": np.late,
            "ipAddrExt": np.ip_external,
            "ipAddrInt": np.ip_internal,
            "sleepTime": np.sleep_time,
            "sleepJitter": np.sleep_jitter,
            "lastCheckin": np.last_checkin,
            "pendingTasks": pending_tasks,
            "hostingFile": np.hosting_file,
            "receivingFile": np.receiving_file,
            "lastUpdate": utils_time.timestamp(),
            "workspace_uuid": workspace_uuid
        }

        con.execute(
            """UPDATE nimplant
                       SET active = :active, late = :late, ipAddrExt = :ipAddrExt,
                        ipAddrInt = :ipAddrInt, sleepTime = :sleepTime, sleepJitter = :sleepJitter,
                        lastCheckin = :lastCheckin, pendingTasks = :pendingTasks, hostingFile = :hostingFile,
                        receivingFile = :receivingFile, lastUpdate = :lastUpdate, workspace_uuid = :workspace_uuid
                       WHERE guid = :guid""",
            obj,
        )
        con.commit()
        
        # Verify that changes were saved correctly
        if np.pending_tasks:
            try:
                saved = con.execute(
                    """SELECT pendingTasks FROM nimplant WHERE guid = ?""",
                    (np.guid,)
                ).fetchone()
                
                if saved:
                    utils.nimplant_print(f"DEBUG: Verification of saving - pendingTasks: {saved[0]}")
            except Exception as e:
                utils.nimplant_print(f"DEBUG: Error verifying saving: {str(e)}")

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}")

# Write to Implant log
def db_nimplant_log(
    np: NimPlant, task_guid=None, task=None, task_friendly=None, result=None, is_checkin=False
):
    try:
        # Validate that the implant is valid
        if np is None or not hasattr(np, 'guid') or np.guid is None:
            utils.nimplant_print(f"ERROR: Invalid implant or GUID not available", skip_db_log=True)
            return
            
        ts = utils_time.timestamp()

        # Prepare individual values, we don't use a dictionary
        nimplant_guid = np.guid
        current_time = ts
        
        utils.nimplant_print(f"DEBUG: db_nimplant_log - Logging entry for implant {nimplant_guid}", skip_db_log=True)

        # If there is only a task, just log the task
        if task_guid is not None and task is not None and result is None:
            con.execute(
                """INSERT INTO nimplant_history (nimplantGuid, taskGuid, task, taskFriendly, taskTime, is_checkin)
                           VALUES (?, ?, ?, ?, ?, ?)""",
                (nimplant_guid, task_guid, task, task_friendly, current_time, is_checkin),
            )

        # If there are a task GUID and result, update the existing task with the result
        elif task_guid is not None and task is None and result is not None:
            con.execute(
                """UPDATE nimplant_history
                            SET result = ?, resultTime = ?, is_checkin = ?
                            WHERE taskGuid = ?""",
                (result, current_time, is_checkin, task_guid),
            )

        # If there is no task or task GUID but there is a result, log the result without task (console messages)
        elif task_guid is None and task is None and result is not None:
            con.execute(
                """INSERT INTO nimplant_history (nimplantGuid, result, resultTime, is_checkin)
                            VALUES (?, ?, ?, ?)""",
                (nimplant_guid, result, current_time, is_checkin),
            )

        # If there are both a result and a task (GUID may be None or have a value), log them all at once (server-side tasks)
        elif task is not None and result is not None:
            con.execute(
                """INSERT INTO nimplant_history (nimplantGuid, taskGuid, task, taskFriendly, taskTime, result, resultTime, is_checkin)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (nimplant_guid, task_guid, task, task_friendly, current_time, result, current_time, is_checkin),
            )

        # Other cases should not occur
        else:
            raise Exception("Unhandled logic case in db_nimplant_log() call")

        con.commit()
        utils.nimplant_print(f"DEBUG: db_nimplant_log - Entry logged successfully", skip_db_log=True)

    except Exception as e:
        try:
            con.rollback()
        except Exception as rollback_error:
            utils.nimplant_print(f"DEBUG: db_nimplant_log - Rollback error: {rollback_error}", skip_db_log=True)
            
        utils.nimplant_print(f"DB error: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_nimplant_log - Traceback: {traceback.format_exc()}", skip_db_log=True)

# Function to test the database connection
def test_db_connection():
    global con
    try:
        # Try to execute a simple query
        con.execute("SELECT 1").fetchone()
        return True
    except Exception as e:
        utils.nimplant_print(f"ERROR: Database connection failed: {e}", skip_db_log=True)
        
        # Attempt to reconnect
        try:
            con = sqlite3.connect(
                db_path, check_same_thread=False, detect_types=sqlite3.PARSE_DECLTYPES
            )
            con.row_factory = sqlite3.Row
            utils.nimplant_print(f"Database reconnection successful", skip_db_log=True)
            return True
        except Exception as reconnect_error:
            utils.nimplant_print(f"ERROR: Could not reconnect to database: {reconnect_error}", skip_db_log=True)
            return False

# Write to server log
def db_server_log(np_server: Server, result):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print(f"Cannot log to server, database not initialized", skip_db_log=True)
            return
            
        # Check database connection
        if not test_db_connection():
            utils.nimplant_print(f"ERROR: Cannot log to database - connection failed", skip_db_log=True)
            return
            
        # Validate parameters are correct
        if np_server is None or not hasattr(np_server, 'guid') or np_server.guid is None:
            utils.nimplant_print(f"ERROR: Invalid server or GUID not available", skip_db_log=True)
            return
            
        if result is None:
            result = ""  # Convert None to empty string to avoid errors
            
        # Get current timestamp
        try:
            ts = utils_time.timestamp()
            if not isinstance(ts, str):
                ts = str(ts)
                
            # Debug log of parameters before insertion
            utils.nimplant_print(f"DEBUG: Inserting log with guid={np_server.guid}, result type={type(result)}, ts type={type(ts)}", skip_db_log=True)
            
            # Ensure data types are as expected
            server_guid = str(np_server.guid) if np_server.guid is not None else ""
            result_str = str(result) if result is not None else ""
            
            # Ensure result is string
            if not isinstance(result_str, str):
                utils.nimplant_print(f"ERROR: Result is not a string after conversion: {result_str}", skip_db_log=True)
                result_str = ""
                
            # Verify all parameters are valid
            if not server_guid or not ts:
                utils.nimplant_print(f"ERROR: Invalid parameters for log: guid={server_guid}, ts={ts}", skip_db_log=True)
                return
                
            # Start an explicit transaction with error handling
            utils.nimplant_print(f"DEBUG: Starting transaction for server log", skip_db_log=True)
            
            # Try to use BEGIN TRANSACTION
            try:
                con.execute("BEGIN TRANSACTION")
                utils.nimplant_print(f"DEBUG: Transaction started successfully", skip_db_log=True)
                transaction_active = True
            except sqlite3.OperationalError as e:
                utils.nimplant_print(f"DEBUG: Transaction error: {e}", skip_db_log=True)
                # If there's an error starting the transaction, assume no active transaction
                transaction_active = False
                
            # Insert using valid parameters
            con.execute(
                "INSERT INTO server_history (serverGuid, result, resultTime) VALUES (?, ?, ?)",
                (server_guid, result_str, ts)
            )
            
            # Commit only if insertion was successful and we have an active transaction
            utils.nimplant_print(f"DEBUG: Insert successful, attempting to commit", skip_db_log=True)
            
            # Try-except for commit, just in case
            try:
                con.commit()
                utils.nimplant_print(f"DEBUG: Transaction committed successfully", skip_db_log=True)
            except sqlite3.OperationalError as commit_error:
                if "no transaction is active" in str(commit_error):
                    utils.nimplant_print(f"DEBUG: No transaction to commit, continuing", skip_db_log=True)
                else:
                    # If it's another commit error, propagate it
                    raise
            
        except Exception as error:
            utils.nimplant_print(f"ERROR inserting into database: {error}", skip_db_log=True)
            try:
                # Try to rollback without checking if there's an active transaction
                # Rollback fails silently if there's no active transaction
                con.rollback()
                utils.nimplant_print(f"DEBUG: Transaction rolled back", skip_db_log=True)
            except Exception as rollback_error:
                utils.nimplant_print(f"DEBUG: Rollback error: {rollback_error}", skip_db_log=True)
            raise

    except Exception as e:
        try:
            # Try to rollback without checking
            con.rollback()
            utils.nimplant_print(f"DEBUG: Transaction rolled back in exception handler", skip_db_log=True)
        except Exception as rollback_error:
            utils.nimplant_print(f"DEBUG: db_server_log - Rollback error: {rollback_error}", skip_db_log=True)
            
        utils.nimplant_print(f"DB error: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_server_log - Traceback: {traceback.format_exc()}", skip_db_log=True)

# Delete a nimplant from the database permanently
def db_delete_nimplant(nimplant_guid):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print(f"Cannot delete nimplant, database not initialized", skip_db_log=True)
            return False, "Database not initialized"
            
        # Check database connection
        if not test_db_connection():
            utils.nimplant_print(f"ERROR: Cannot delete nimplant - database connection failed", skip_db_log=True)
            return False, "Database connection failed"

        # First verify the implant exists
        exists = con.execute(
            """SELECT guid FROM nimplant WHERE guid = ?""",
            (nimplant_guid,)
        ).fetchone()
        
        if not exists:
            utils.nimplant_print(f"Implant with GUID {nimplant_guid} not found in database", skip_db_log=True)
            return False, "Implant not found"
        
        utils.nimplant_print(f"Deleting implant with GUID {nimplant_guid} from database", skip_db_log=True)
        
        # Begin transaction
        con.execute("BEGIN TRANSACTION")
        
        # Delete the implant from the nimplant table
        con.execute(
            """DELETE FROM nimplant WHERE guid = ?""",
            (nimplant_guid,)
        )
        
        # Delete associated history records
        deleted_history = con.execute(
            """DELETE FROM nimplant_history WHERE nimplantGuid = ?""",
            (nimplant_guid,)
        ).rowcount
        
        # Commit the transaction
        con.commit()
        
        utils.nimplant_print(f"Successfully deleted implant {nimplant_guid} and {deleted_history} history records", skip_db_log=True)
        return True, f"Implant deleted successfully with {deleted_history} history records"

    except Exception as e:
        try:
            con.rollback()
            utils.nimplant_print(f"Transaction rolled back after error", skip_db_log=True)
        except Exception as rollback_error:
            utils.nimplant_print(f"Error during rollback: {rollback_error}", skip_db_log=True)
            
        utils.nimplant_print(f"Error deleting implant: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_delete_nimplant - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False, f"Error deleting implant: {str(e)}"

#
#   FUNCTIONALITY FOR API
#

# Get server configuration (/api/server)
def db_get_server_info(server_guid):
    try:
        res = con.execute(
            """SELECT * FROM server WHERE guid = :serverGuid""",
            {"serverGuid": server_guid},
        ).fetchone()

        # Format as JSON-friendly object
        result_json = {
            "guid": res["guid"],
            "name": res["name"],
            "xorKey": res["xorKey"],
            "config": {
                "managementIp": res["managementIp"],
                "managementPort": res["managementPort"],
                "listenerType": res["listenerType"],
                "listenerIp": res["serverIp"],
                "implantCallbackIp": res["implantCallbackIp"],
                "listenerHost": res["listenerHost"],
                "listenerPort": res["listenerPort"],
                "registerPath": res["registerPath"],
                "taskPath": res["taskPath"],
                "resultPath": res["resultPath"],
                "reconnectPath": res["reconnectPath"],
                "riskyMode": res["riskyMode"],
                "sleepTime": res["sleepTime"],
                "sleepJitter": res["sleepJitter"],
                "killDate": res["killDate"],
                "userAgent": res["userAgent"],
                "httpAllowCommunicationKey": res["httpAllowCommunicationKey"],
                "maxReconnectionAttemps": config.get("implant", {}).get("maxReconnectionAttemps", 3),
            },
        }
        return result_json

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")
        return {}

# Get the last X entries of console history (/api/server/console[/<limit>/<offset>])
def db_get_server_console(guid, limit, offset):
    try:
        res = con.execute(
            """SELECT * FROM server_history WHERE serverGuid = ? LIMIT ? OFFSET ?""",
            (guid, limit, offset),
        ).fetchall()

        res = [dict(r) for r in res]
        return res

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")
        return {}

# Get overview of implants (/api/nimplants)
def db_get_nimplant_info(server_guid):
    try:
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Querying nimplants for server_guid: {server_guid}", skip_db_log=True)
        
        # Debug query
        count_total = con.execute("SELECT COUNT(*) FROM nimplant").fetchone()[0]
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Total Implants in the table: {count_total}", skip_db_log=True)
        
        count_server = con.execute("SELECT COUNT(*) FROM nimplant WHERE serverGuid = ?", (server_guid,)).fetchone()[0]
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Implants for this server: {count_server}", skip_db_log=True)
        
        # If there are no results for this server, let's see what's in the table
        if count_server == 0 and count_total > 0:
            sample = con.execute("SELECT guid, serverGuid FROM nimplant LIMIT 3").fetchall()
            utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Implant samples in the table: {sample}", skip_db_log=True)
        
        res = con.execute(
            """SELECT id, guid, active, late, ipAddrInt, ipAddrExt, username, hostname, pid, pname, lastCheckin, workspace_uuid
                FROM nimplant WHERE serverGuid = ?""",
            (server_guid,),
        ).fetchall()
        
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Results obtained: {len(res) if res else 0}", skip_db_log=True)
        
        if res:
            utils.nimplant_print(f"DEBUG: db_get_nimplant_info - First record: {dict(res[0])}", skip_db_log=True)
            
            # Convert to list of dictionaries
            nimplants = [dict(r) for r in res]
            
            # Check for "disconnected" status (based on recent activity)
            import datetime
            from datetime import timedelta
            
            # Current time
            now = datetime.datetime.now()
            
            for nimplant in nimplants:
                # Check if active
                if nimplant['active']:
                    try:
                        # Parse the lastCheckin timestamp
                        last_checkin = datetime.datetime.strptime(nimplant['lastCheckin'], '%d/%m/%Y %H:%M:%S')
                        time_diff = now - last_checkin
                        
                        # If more than 5 minutes have passed, mark as disconnected
                        if time_diff > timedelta(minutes=5):
                            nimplant['disconnected'] = True
                            # Also mark as late to maintain consistency if it's not already
                            if not nimplant['late']:
                                nimplant['late'] = True
                        else:
                            # If less than 5 minutes have passed, not disconnected
                            nimplant['disconnected'] = False
                            # Respect the original 'late' state
                    except (ValueError, TypeError) as e:
                        utils.nimplant_print(f"DEBUG: Error parsing lastCheckin timestamp: {e}", skip_db_log=True)
                        nimplant['disconnected'] = False
                        # Respect the original 'late' state
                else:
                    # If not active, simply inactive (not disconnected)
                    nimplant['disconnected'] = False
                    # Respect the original 'late' state
            
            return nimplants
        else:
            utils.nimplant_print(f"DEBUG: db_get_nimplant_info - No results found for server_guid: {server_guid}", skip_db_log=True)
            return []

    except Exception as e:
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - ERROR: {str(e)}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_get_nimplant_info - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return []

# Get details for nimplant (/api/nimplants/<guid>)
def db_get_nimplant_details(nimplant_guid):
    try:
        # Get basic nimplant information
        res = con.execute(
            """SELECT * FROM nimplant WHERE guid = ?""",
            (nimplant_guid,),
        ).fetchone()

        if res:
            res = dict(res)
            
            # Check for "disconnected" status (based on recent activity)
            import datetime
            from datetime import timedelta
            
            # If it's active, verify if a long time has passed since the last check-in
            if res['active']:
                try:
                    # Parse the lastCheckin timestamp
                    last_checkin = datetime.datetime.strptime(res['lastCheckin'], '%d/%m/%Y %H:%M:%S')
                    time_diff = datetime.datetime.now() - last_checkin
                    
                    # If more than 5 minutes have passed, mark as disconnected
                    if time_diff > timedelta(minutes=5):
                        res['disconnected'] = True
                        # Also mark as late to maintain consistency if it's not already
                        if not res['late']:
                            res['late'] = True
                    else:
                        # If less than 5 minutes have passed, not disconnected
                        res['disconnected'] = False
                        # Respect the original 'late' state
                except (ValueError, TypeError) as e:
                    utils.nimplant_print(f"DEBUG: Error parsing lastCheckin timestamp in details: {e}", skip_db_log=True)
                    res['disconnected'] = False
                    # Respect the original 'late' state
            else:
                # If not active, simply inactive (not disconnected)
                res['disconnected'] = False
                # Respect the original 'late' state
            
            # Calculate command count (commands issued to this Implant)
            command_count = con.execute(
                """SELECT COUNT(*) FROM nimplant_history 
                   WHERE nimplantGuid = ? AND task IS NOT NULL""",
                (nimplant_guid,)
            ).fetchone()[0]
            
            # Calculate check-in count from log entries
            try:
                # First we try to count the check-in messages in the history
                checkin_patterns = [
                    'checked in',
                    'check-in',
                    'checking in',
                    'Implant checked in'
                ]
                
                # Build the query
                query_parts = []
                params = [nimplant_guid]
                
                for pattern in checkin_patterns:
                    query_parts.append("result LIKE ?")
                    params.append(f'%{pattern}%')
                
                query = f"""
                    SELECT COUNT(*) FROM nimplant_history 
                    WHERE nimplantGuid = ? AND ({" OR ".join(query_parts)})
                """
                
                checkin_count_from_logs = con.execute(query, params).fetchone()[0]
                
                # Ensure a minimum of check-ins if there are records but no specific messages
                if checkin_count_from_logs == 0:
                    # If we don't find specific messages, count all results without an associated task
                    checkin_count_from_logs = con.execute(
                        """SELECT COUNT(*) FROM nimplant_history 
                           WHERE nimplantGuid = ? AND task IS NULL AND result IS NOT NULL""",
                        (nimplant_guid,)
                    ).fetchone()[0]
                
                # Ensure a minimum of 1 check-in if the implant exists
                checkin_count = max(1, checkin_count_from_logs)
                
            except Exception as e:
                utils.nimplant_print(f"Error counting check-ins: {e}")
                checkin_count = 1  # Default value
            
            # For data transferred, we don't have a direct field to track it
            # We'll calculate based on the length of command results as an approximation
            data_total = 0
            try:
                # Get all command results for this implant
                results = con.execute(
                    """SELECT result FROM nimplant_history 
                       WHERE nimplantGuid = ? AND result IS NOT NULL""",
                    (nimplant_guid,)
                ).fetchall() 
                
                # Sum up the length of all results (each character ~1 byte)
                for row in results:
                    if row["result"]:
                        # Check if it's a check-in message
                        if "Implant checked in, total check-ins:" in row["result"]:
                            # For simple check-ins, we only count 1 byte per ping
                            data_total += 1
                        else:
                            # For the rest of the results, we count the full length
                            data_total += len(row["result"])
                
                # Add estimated command size (average 100 bytes per command)
                data_total += command_count * 100
                
                # Add base overhead for headers and encryption (1KB per communication)
                # For simple check-ins, we use a reduced overhead of 256 bytes instead of 1KB
                checkins_overhead = checkin_count * 256  # 256 bytes per check-in
                commands_overhead = command_count * 1024  # 1KB per command
                data_total += commands_overhead + checkins_overhead
                
            except Exception as data_error:
                utils.nimplant_print(f"Error calculating data transferred: {data_error}")
                # Fallback to simple estimation
                data_total = (command_count + checkin_count) * 5120  # 5KB per communication

            data_transferred = data_total
            
            # Add statistics to the result
            res["command_count"] = command_count
            res["checkin_count"] = checkin_count
            res["data_transferred"] = data_transferred
            
        return res

    except Exception as e:
        utils.nimplant_print(f"DB error in db_get_nimplant_details: {e}")
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
        return {}

# Get the last X lines of console history for a specific implant (/api/nimplants/<guid>/console[/<limit>/<offset>])
def db_get_nimplant_console(nimplant_guid, limit, offset, order='desc'):
    try:
        # Determine the query order based on the parameter
        order_clause = "ASC" if order.lower() == 'asc' else "DESC"
        
        utils.nimplant_print(f"Fetching console history for {nimplant_guid}, limit: {limit}, offset: {offset}, order: {order_clause}")
        
        # SQL query to get only messages that are not check-ins
        query = f"""
            SELECT * FROM nimplant_history 
            WHERE nimplantGuid = ? 
            AND is_checkin = 0
            ORDER BY id {order_clause}
            LIMIT ? OFFSET ?
        """
        
        res = con.execute(
            query,
            (nimplant_guid, limit, offset),
        ).fetchall()

        if res:
            res = [dict(r) for r in res]

        return res

    except Exception as e:
        utils.nimplant_print(f"DB error: {e}")
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
        return {}

# Function to log file transfers (uploads or downloads)
def db_log_file_transfer(nimplant_guid, filename, size, operation_type):
    try:
        utils.nimplant_print(f"DEBUG: db_log_file_transfer - Registering file transfer: {filename}", skip_db_log=True)
        
        # Validate parameters
        if not nimplant_guid or not filename:
            utils.nimplant_print(f"DEBUG: db_log_file_transfer - Invalid parameters: guid={nimplant_guid}, filename={filename}", skip_db_log=True)
            return False
            
        # Get current timestamp
        timestamp = utils_time.timestamp()
        
        # Insert into file_transfers table
        con.execute(
            """INSERT INTO file_transfers (nimplantGuid, filename, size, operation_type, timestamp)
               VALUES (?, ?, ?, ?, ?)""",
            (nimplant_guid, filename, size or 0, operation_type, timestamp)
        )
        con.commit()
        
        utils.nimplant_print(f"DEBUG: db_log_file_transfer - Transfer registered successfully", skip_db_log=True)
        return True
        
    except Exception as e:
        utils.nimplant_print(f"DEBUG: db_log_file_transfer - Error: {str(e)}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_log_file_transfer - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False

# Function to get file transfer history for an implant
def db_get_file_transfers(nimplant_guid, limit=50):
    try:
        utils.nimplant_print(f"DEBUG: db_get_file_transfers - Querying transfers for: {nimplant_guid}", skip_db_log=True)
        
        # Query the file_transfers table
        res = con.execute(
            """SELECT * FROM file_transfers 
               WHERE nimplantGuid = ? 
               ORDER BY timestamp DESC 
               LIMIT ?""",
            (nimplant_guid, limit)
        ).fetchall()
        
        # Convert to list of dictionaries
        transfers = [dict(r) for r in res]
        
        utils.nimplant_print(f"DEBUG: db_get_file_transfers - Found {len(transfers)} transfers", skip_db_log=True)
        return transfers
        
    except Exception as e:
        utils.nimplant_print(f"DEBUG: db_get_file_transfers - Error: {str(e)}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_get_file_transfers - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return []
        
# Function to create a REST API that returns file transfers
def db_get_file_transfers_api(nimplant_guid=None, limit=50):
    try:
        # If a specific GUID is provided, filter by that implant
        if nimplant_guid:
            transfers = db_get_file_transfers(nimplant_guid, limit)
        else:
            # If no GUID is provided, get all transfers
            res = con.execute(
                """SELECT ft.*, n.hostname, n.username  
                   FROM file_transfers ft
                   LEFT JOIN nimplant n ON ft.nimplantGuid = n.guid
                   ORDER BY timestamp DESC 
                   LIMIT ?""",
                (limit,)
            ).fetchall()
            transfers = [dict(r) for r in res]
            
        return transfers
        
    except Exception as e:
        utils.nimplant_print(f"DEBUG: db_get_file_transfers_api - Error: {str(e)}", skip_db_log=True)
        return []

# Function to store file hash mapping to original filename
def db_store_file_hash_mapping(file_hash, original_filename, file_path):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot store file hash mapping, database not initialized", skip_db_log=True)
            return False
            
        # Get current timestamp
        timestamp = utils_time.timestamp()
        
        # Save the mapping to the database
        con.execute(
            """INSERT OR REPLACE INTO file_hash_mapping 
               (file_hash, original_filename, file_path, upload_timestamp) 
               VALUES (?, ?, ?, ?)""",
            (file_hash, original_filename, file_path, timestamp)
        )
        con.commit()
        
        utils.nimplant_print(f"DEBUG: db_store_file_hash_mapping - Saved hash {file_hash} for file {original_filename}", skip_db_log=True)
        return True
        
    except Exception as e:
        utils.nimplant_print(f"Error storing file hash mapping: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_store_file_hash_mapping - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False
        
# Function to get the original filename and path of a file from its hash
def db_get_file_info_by_hash(file_hash):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot retrieve file info, database not initialized", skip_db_log=True)
            return None, None
            
        # Query the mapping in the database
        res = con.execute(
            """SELECT original_filename, file_path FROM file_hash_mapping 
               WHERE file_hash = ?""",
            (file_hash,)
        ).fetchone()
        
        if res:
            # If the hash is found in the database, return original name and path
            original_filename = res["original_filename"]
            file_path = res["file_path"]
            utils.nimplant_print(f"DEBUG: db_get_file_info_by_hash - Found hash {file_hash}, original: {original_filename}", skip_db_log=True)
            return original_filename, file_path
        else:
            # If not found, return None for both values
            utils.nimplant_print(f"DEBUG: db_get_file_info_by_hash - Hash {file_hash} not found", skip_db_log=True)
            return None, None
            
    except Exception as e:
        utils.nimplant_print(f"Error retrieving file info by hash: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"DEBUG: db_get_file_info_by_hash - Traceback: {traceback.format_exc()}", skip_db_log=True)
        return None, None

# Functions to manage workspaces
def db_create_workspace(workspace_name):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot create workspace, database not initialized", skip_db_log=True)
            return None
            
        # Generate UUID for workspace
        import uuid
        workspace_uuid = str(uuid.uuid4())
        
        # Get current timestamp
        timestamp = utils_time.timestamp()
        
        # Insert the workspace
        con.execute(
            """INSERT INTO workspaces (workspace_uuid, workspace_name, creation_date)
               VALUES (?, ?, ?)""",
            (workspace_uuid, workspace_name, timestamp)
        )
        con.commit()
        
        utils.nimplant_print(f"Created workspace: {workspace_name} with UUID: {workspace_uuid}", skip_db_log=True)
        return workspace_uuid
    except Exception as e:
        utils.nimplant_print(f"Error creating workspace: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return None

def db_get_workspaces():
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot get workspaces, database not initialized", skip_db_log=True)
            return []
            
        # Get all workspaces
        res = con.execute(
            """SELECT * FROM workspaces ORDER BY creation_date DESC"""
        ).fetchall()
        
        # Convert to list of dictionaries
        workspaces = [dict(r) for r in res]
        return workspaces
    except Exception as e:
        utils.nimplant_print(f"Error getting workspaces: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return []

def db_assign_nimplant_to_workspace(nimplant_guid, workspace_uuid):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot assign nimplant to workspace, database not initialized", skip_db_log=True)
            return False
            
        # Verify workspace exists
        workspace = con.execute(
            """SELECT workspace_uuid FROM workspaces WHERE workspace_uuid = ?""",
            (workspace_uuid,)
        ).fetchone()
        
        if not workspace:
            utils.nimplant_print(f"Workspace with UUID {workspace_uuid} not found", skip_db_log=True)
            return False
            
        # Verify nimplant exists
        nimplant = con.execute(
            """SELECT guid FROM nimplant WHERE guid = ?""",
            (nimplant_guid,)
        ).fetchone()
        
        if not nimplant:
            utils.nimplant_print(f"Nimplant with GUID {nimplant_guid} not found", skip_db_log=True)
            return False
            
        # Assign nimplant to workspace
        con.execute(
            """UPDATE nimplant SET workspace_uuid = ? WHERE guid = ?""",
            (workspace_uuid, nimplant_guid)
        )
        con.commit()
        
        utils.nimplant_print(f"Assigned nimplant {nimplant_guid} to workspace {workspace_uuid}", skip_db_log=True)
        return True
    except Exception as e:
        utils.nimplant_print(f"Error assigning nimplant to workspace: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False

def db_remove_nimplant_from_workspace(nimplant_guid):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot remove nimplant from workspace, database not initialized", skip_db_log=True)
            return False
            
        # Remove nimplant from workspace (set workspace_uuid to NULL)
        con.execute(
            """UPDATE nimplant SET workspace_uuid = NULL WHERE guid = ?""",
            (nimplant_guid,)
        )
        con.commit()
        
        utils.nimplant_print(f"Removed nimplant {nimplant_guid} from workspace", skip_db_log=True)
        return True
    except Exception as e:
        utils.nimplant_print(f"Error removing nimplant from workspace: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False

def db_get_nimplants_by_workspace(workspace_uuid):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot get nimplants, database not initialized", skip_db_log=True)
            return []
            
        # Get all nimplants in this workspace
        res = con.execute(
            """SELECT * FROM nimplant WHERE workspace_uuid = ?""",
            (workspace_uuid,)
        ).fetchall()
        
        # Convert to list of dictionaries
        nimplants = [dict(r) for r in res]
        return nimplants
    except Exception as e:
        utils.nimplant_print(f"Error getting nimplants by workspace: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return []

def db_delete_workspace(workspace_uuid):
    try:
        # Ensure database is initialized
        if not ensure_db_initialized():
            utils.nimplant_print("Cannot delete workspace, database not initialized", skip_db_log=True)
            return False
            
        # First, remove workspace association from all nimplants
        con.execute(
            """UPDATE nimplant SET workspace_uuid = NULL WHERE workspace_uuid = ?""",
            (workspace_uuid,)
        )
        
        # Then delete the workspace
        con.execute(
            """DELETE FROM workspaces WHERE workspace_uuid = ?""",
            (workspace_uuid,)
        )
        con.commit()
        
        utils.nimplant_print(f"Deleted workspace {workspace_uuid}", skip_db_log=True)
        return True
    except Exception as e:
        utils.nimplant_print(f"Error deleting workspace: {e}", skip_db_log=True)
        import traceback
        utils.nimplant_print(f"Traceback: {traceback.format_exc()}", skip_db_log=True)
        return False
