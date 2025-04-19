<div align="center">
  <img src="docs/images/nimhawk.png" height="150">

  <h1>Nimhawk Developer Guide</h1>

[![PRs Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen.svg)](http://makeapullrequest.com)
[![Platform](https://img.shields.io/badge/Implant-Windows%20x64-blue.svg)](https://github.com/yourgithub/nimhawk)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0-red.svg)](https://github.com/yourgithub/nimhawk/releases)
</div>

This document provides detailed information about the structure of the Nimhawk project, guidelines for developers who wish to contribute or modify the code, and documentation on recent improvements implemented.

# Table of contents

- [Project overview](#project-overview)
- [Quick start guide](#quick-start-guide)
- [Project architecture](#project-architecture)
  - [Project structure](#project-structure)
  - [Main components](#main-components)
  - [Communication flow](#communication-flow)
- [Development guide](#development-guide)
  - [Development environment setup](#development-environment-setup)
  - [Adding new features](#adding-new-features)
  - [Security considerations](#security-considerations)
  - [Pull request process](#pull-request-process)
- [Feature documentation](#feature-documentation)
  - [Enhanced reconnection system](#1-enhanced-reconnection-system)
  - [Multi-status implant support](#2-multi-status-implant-support)
  - [Search and filtering capabilities](#3-search-and-filtering-capabilities)
  - [User interface improvements](#4-user-interface-improvements)
  - [Implant deletion API](#5-implant-deletion-api)
- [Subsystem architecture](#subsystem-architecture)
  - [Workspace system architecture](#workspace-system-architecture)
  - [File exchange system implementation](#file-exchange-system-implementation)
- [Future plans](#future-plans)
- [Contributing](#contributing)
- [License](#license)
- [Support the project](#support-the-project)

## Project overview

Nimhawk is a modular Command & Control (C2) framework designed with security, flexibility, and extensibility in mind. The project is heavily based on [NimPlant](https://github.com/chvancooten/NimPlant) by [Cas van Cooten](https://github.com/chvancooten) ([@chvancooten](https://twitter.com/chvancooten)), whose excellent work provided the foundation for this project.

Nimhawk consists of three main components:
- **Implant**: Written in Nim for cross-platform compatibility and evasion
- **Server**: Python-based C2 infrastructure with two separate server components
- **Admin UI**: Modern web interface built with React/Next.js and Mantine

The framework builds upon NimPlant's core functionality while adding enhanced features such as a modular architecture, improved security measures, and a completely renovated graphical interface with modern authentication.

## Quick start guide

### Prerequisites
- Python 3.8+
- Nim compiler (if building implants from source)
- MinGW (for cross-compilation from Linux/macOS)

### Installation
```bash
# Clone the repository
git clone https://github.com/hdbreaker/nimhawk.git
cd nimhawk

# Create configuration
cp config.toml.example config.toml
# Edit config.toml with your settings

# Create Python virtual environment
cd server
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Start the server
```bash
python3 nimhawk.py server
```

### Access the web interface
Open `http://localhost:5000` in your browser (or the configured port)
- Default credentials: admin@nimhawk.com / P4ssw0rd123$

## Project architecture

### Project structure

The project structure has been reorganized to improve modularity and facilitate collaborative development:

```
Nimhawk/
├── docs/                       # Documentation and images
│   └── images/                 # Screenshots and images
│
├── implant/                    # Nim implant source code
│   ├── NimPlant.nim            # Main implant entry point
│   ├── NimPlant.nimble         # Nim package configuration
│   ├── nim.cfg                 # Nim compiler configuration
│   ├── modules/                # Specific functionality modules
│   ├── config/                 # Implant configuration handling
│   ├── core/                   # Core functionality
│   ├── selfProtections/        # Evasion and protection mechanisms
│   └── util/                   # General utilities
│
├── server/                     # Server component
│   ├── admin_web_ui/           # Web administration interface
│   │   ├── components/         # Reusable React components
│   │   ├── modules/            # Business logic modules
│   │   ├── pages/              # Next.js pages
│   │   └── ...                 # Other UI files
│   │
│   ├── src/                    # Server source code
│   │   ├── config/             # Server configuration
│   │   ├── servers/            # Server implementations
│   │   │   ├── admin_api/      # Admin interface API
│   │   │   └── implants_api/   # Implant communication API
│   │   │
│   │   └── util/               # Server utilities
│   │
│   ├── downloads/              # Files downloaded from implants
│   ├── logs/                   # Server and implant logs
│   └── uploads/                # Files to upload to implants
│
├── detection/                  # Detection analysis tools 
│
├── config.toml.example         # Example configuration file template
├── nimhawk.py                  # Main script for managing the C2
├── LICENSE                     # License information
├── README.md                   # Main documentation
└── DEVELOPERS.md               # This development guide
```

### Main components

#### 1. Implant

The Nimhawk agent is written in Nim to provide a lightweight, evasive implant with HTTP(S) communication capabilities. It builds upon the foundation created by [Cas van Cooten](https://github.com/chvancooten) in NimPlant.

**Key implant features:**
- Reconnection system with exponential backoff
- Secure encryption key transfer
- Mutex to prevent multiple simultaneous executions
- Enhanced registry management with proper cleanup during reconnection
- Encrypted communication with the server
- Support for various command types (filesystem, network, execution, etc.)
- Robust error handling for network disconnection scenarios

#### 2. Backend Server

The Nimhawk backend is written in Python and consists of two independent servers:

**Implants Server:**
- Exclusively handles communication with implants
- Processes implant check-ins and results
- Uses machine-to-machine authentication with pre-shared keys
- No direct communication with Web UI

**Admin API Server:**
- Provides the REST API for the web interface
- Manages user authentication and authorization
- Never communicates directly with implants
- Interacts with the database for CRUD operations
- Can be configured in API-only mode by setting Flask's static folders to None

**UI Development in API-Only Mode:**
When running the Admin server in API-only mode:
- The server acts as a pure REST API without serving static files
- Front-end development requires running the Next.js server separately
- API calls from the development server must be configured with proper CORS handling
- This separation allows for more flexible development and deployment options

#### 3. Admin Web Interface

The web interface is built with React/Next.js and the Mantine component framework:

**UI Features:**
- Modern, responsive interface
- User authentication system
- Web panel for implant compilation
- Real-time visualization of information and results
- Detailed panels for implant management

#### 4. Database

Nimhawk uses SQLite to store all information:

- **nimhawk.db**: SQLite database storing information about implants, users, command history, and downloaded files
- Both servers (Implants and Admin) read from and write to this database
- Serves as the data coordination point between components

### Communication flow

The project architecture implements strictly separated communication paths:

1. **Implant ↔ Implants Server**:
   - HTTP(S) communication with customizable paths
   - Authentication via pre-shared key (`httpAllowCommunicationKey`)
   - Custom HTTP headers for authentication (`X-Correlation-ID`)
   - Improved reconnection mechanism with registry cleanup and proper error handling
   - Status code-based response handling for better reliability
   - Automatic retry logic with exponential backoff

2. **Web UI ↔ Admin API Server**:
   - HTTPS communication with REST API
   - Authentication based on usernames and passwords
   - Session management with configurable expiration

3. **Data Coordination**:
   - SQLite database as central storage point
   - No direct communication between implants and web UI
   - All data shared through the database

## Development guide

### Development environment setup

#### Python Environment

Nimhawk's server component uses Python virtual environments to manage dependencies:

1. **Create a virtual environment**:
   ```bash
   # Navigate to the server directory
   cd server/
   
   # Create a virtual environment
   python3 -m venv venv
   
   # Activate the virtual environment
   # On Linux/macOS:
   source venv/bin/activate
   # On Windows:
   venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   # Install all required packages
   pip install -r requirements.txt
   ```

#### UI Development

The web interface is built with Next.js and uses npm for dependency management and development workflows. Here's how to set up and run the UI in development mode:

1. **Set up the development environment**:
   ```bash
   # Navigate to the UI directory
   cd server/admin_web_ui/
   
   # Install dependencies
   npm install
   ```

2. **Available npm commands**:
   ```bash
   # Start development server with hot reloading at http://localhost:3000
   npm run dev
   
   # Build the production version of the UI
   npm run build
   
   # Run compiled version of the UI
   npm run start
   
   # Lint the code for quality checks
   npm run lint
   ```

3. **Development workflow**:
   - Make changes to components in the `components/` directory
   - Modify pages in the `pages/` directory
   - Changes will automatically reload in the browser
   - Ensure that the backend server is running for API calls to work
   - The backend serves the production build, but during development, you'll connect to the backend API directly from the Next.js dev server

4. **Building for production**:
   ```bash
   # Build the UI for production
   npm run build
   
   # The output will be placed in the .next/ directory
   # The backend server will serve these files automatically
   ```

When working in development mode, the UI will run on port 3000, while the backend API typically runs on port 5000. The development server is configured to proxy API requests to the backend server, so both need to be running simultaneously during development.

#### Cross-Compiling with nim.cfg

For building Windows payloads from Linux or macOS:

1. **Install MinGW toolchain**:
   ```bash
   # On macOS
   brew install mingw-w64
   
   # On Linux (Debian/Ubuntu)
   apt-get install mingw-w64
   ```

2. **Configure nim.cfg** with the correct paths to the MinGW toolchain

### Adding new features

#### 1. Agent Modules
- Create new module in appropriate directory under `implant/modules/`
- Implement command handler
- Register in command parser
- Update documentation and help system

#### 2. Server Endpoints
- Add route handler in the appropriate server (implants or admin)
- Implement business logic
- Update API documentation
- Add security measures

#### 3. UI Components
- Create React component in `server/admin_web_ui/components/`
- Add to component library
- Implement state management
- Add styling

### Security considerations

#### 1. Agent Security
- Use encrypted communication
- Minimize detection surface
- Implement evasion techniques where appropriate

#### 2. Server Security
- Validate all input
- Implement rate limiting
- Use secure sessions
- Monitor for abuse

#### 3. UI Security
- Implement robust authentication
- Validate user input
- Use secure protocols
- Handle sensitive data properly

### Pull request process

1. Ensure your code works locally
2. Run tests to verify you're not introducing regressions
3. Document the changes made
4. Submit a PR with a clear description of the purpose
5. Respond to review comments

## Feature documentation

### 1. Enhanced reconnection system

The reconnection system has been significantly improved:

- **Registry Cleanup**: Implants now automatically remove previous registry entries before registering a new implant ID
- **Prevention of Orphaned Entries**: The cleanup process ensures that no registry artifacts remain after implant termination
- **Error Handling**: Improved error handling for registry operations, with proper logging
- **Status Code Handling**: Added support for handling specific status codes (like 410) to properly manage inactive implants
- **Cleaner Reconnection Flow**: Streamlined the reconnection process with better state management
- **Technical Implementation**: Added `removeImplantIDFromRegistry` function to properly clean up registry entries

#### Implementation Details

The reconnection flow has been reimplemented as follows:

1. Before attempting reconnection, the implant retrieves its stored ID from the registry
2. The implant then attempts to reconnect using an OPTIONS request to the `reconnectPath` endpoint
3. The server validates the implant ID and responds with appropriate status codes:
   - 200: Successful reconnection, new encryption key is provided
   - 410: Implant is marked as inactive on the server
   - 404: Implant ID is no longer recognized
4. Based on the response code, the implant decides how to proceed:
   - For 200: Update encryption key and continue operation
   - For 410/404: Remove the old implant ID from registry using `removeImplantIDFromRegistry()` and request a new ID
5. If reconnection fails, the registry entry is properly cleaned up before requesting a new implant ID

Key code improvements in `webClientListener.nim`:

```nim
proc removeImplantIDFromRegistry() =
  # Clean up registry entry before requesting a new ID
  try:
    let key = openKey(HKEY_CURRENT_USER, regPath, samWrite)
    key.deleteValue(regId)
    close(key)
    echo "DEBUG: Successfully removed implant ID from registry"
  except:
    echo "DEBUG: Error removing implant ID from registry"
```

The reconnection system now properly handles various failure scenarios, including network interruptions, server-side implant deregistration, and error conditions, ensuring a more robust and reliable operation.

### 2. Multi-status implant support

A visual tracking system has been implemented that provides clear status indicators:

- **Active Implants**: Displayed in green, indicating recently checked-in implants
- **Late Implants**: Displayed in orange, for implants that have missed recent check-ins but are still considered active
- **Disconnected Implants**: Displayed in red, for implants that have not checked in for more than 5 minutes
- **Inactive Implants**: Displayed in black, for implants that have been explicitly marked as inactive

These improvements enhance operational awareness by providing immediate visual feedback on implant status.

#### Inactive implant management

A key feature addition is the ability to properly manage inactive implants:

- **Deletion of Inactive Implants**: Operators can now delete inactive implants from the server database
- **Automatic Cleanup**: When an implant is deleted, all associated records and files are properly removed
- **Server-Side Implementation**: The Admin API includes endpoints for deleting inactive implants:
  ```python
  @app.route('/api/nimplants/<guid>', methods=['DELETE'])
  @require_auth
  def delete_nimplant(guid):
      # Check if implant exists and is inactive
      implant_details = db_get_nimplant_details(guid)
      if not implant_details:
          return flask.jsonify({"error": "Implant not found"}), 404
      
      if implant_details.get("active", True):
          return flask.jsonify({"error": "Cannot delete an active implant"}), 400
      
      # Delete the implant if inactive
      success = db_delete_nimplant(guid)
      if success:
          return flask.jsonify({"message": "Implant deleted successfully"}), 200
      else:
          return flask.jsonify({"error": "Failed to delete implant"}), 500
  ```
- **Client-Side Integration**: The UI provides delete buttons for inactive implants with confirmation dialogs
- **Operational Security**: This feature helps maintain a clean database by removing implants that are no longer needed

#### Server-Side Implementation

The multi-status system is implemented through a combination of backend logic and frontend representation:

1. **Backend Status Determination**:
   - In `db.py`, the `db_get_nimplant_details` function was enhanced to calculate implant status based on:
     - Stored `active` flag for inactive implants
     - Time comparison between `last_check_in` and current time
     - Configurable thresholds for "late" and "disconnected" states
   - Status determination logic example:
   ```python
   # Pseudo-code from db.py
   if not implant_data["active"]:
       implant_data["status"] = "inactive"
   else:
       try:
           last_check = iso8601.parse_date(implant_data["last_check_in"])
           now = datetime.now(timezone.utc)
           time_difference = (now - last_check).total_seconds()
           
           if time_difference > 300:  # 5 minutes
               implant_data["status"] = "disconnected"
           elif time_difference > 120:  # 2 minutes
               implant_data["status"] = "late"
           else:
               implant_data["status"] = "active"
       except:
           implant_data["status"] = "unknown"
   ```

2. **Implant Server Response Codes**:
   - The `reconnect_nimplant` endpoint now returns status code 410 for inactive implants
   - This informs the implant to clean up registry entries and terminate or re-register
   - Helps maintain synchronization between server and client status

3. **Frontend Implementation**:
   - The React components were enhanced to visually represent different implant states:
   - `NimplantOverviewCard.tsx` implements status-based styling:
     ```typescript
     // Status color determination
     const getStatusColor = (status: string): string => {
       switch(status) {
         case 'active': return 'green';
         case 'late': return 'orange';
         case 'disconnected': return 'red';
         case 'inactive': return 'dark';
         default: return 'gray';
       }
     };
     ```
   - `NimplantDrawer.tsx` includes a `StatusIndicator` component that displays the current state:
     ```typescript
     const StatusIndicator = ({ status }: { status: string }) => {
       return (
         <Group spacing="xs">
           <ThemeIcon color={getStatusColor(status)} size="sm" radius="xl">
             <IconCircleFilled size="16" />
           </ThemeIcon>
           <Text size="sm" fw={500} tt="capitalize">{status}</Text>
         </Group>
       );
     };
     ```
   - All status information is updated in real-time through the API polling mechanism
   - Inactive implants display a delete button in both the card view and details drawer:
     ```typescript
     // Delete button implementation in NimplantOverviewCard.tsx
     {nimplant.status === 'inactive' && (
       <Button 
         color="red" 
         variant="subtle" 
         size="xs"
         onClick={(e) => {
           e.stopPropagation();
           openDeleteConfirmModal(nimplant.guid);
         }}
       >
         <IconTrash size={16} />
       </Button>
     )}
     
     // Confirmation modal
     const openDeleteConfirmModal = (guid: string) => modals.openConfirmModal({
       title: 'Delete Implant',
       centered: true,
       children: (
         <Text size="sm">
           Are you sure you want to delete this inactive implant? This action cannot be undone.
         </Text>
       ),
       labels: { confirm: 'Delete', cancel: 'Cancel' },
       confirmProps: { color: 'red' },
       onConfirm: () => deleteImplant(guid),
     });
     ```

### 3. Search and filtering capabilities

Advanced search and filtering capabilities have been implemented to enhance operator efficiency when managing multiple implants. These features provide powerful tools for quickly locating specific implants and focusing on relevant subsets of implants based on their status.

#### Search Implementation

The search functionality was implemented with real-time filtering:

1. **Frontend Implementation**:
   - A search input component was added to the ImplantList page:
   ```typescript
   // In pages/implants/index.tsx
   const [searchTerm, setSearchTerm] = useState<string>('');
   
   // Search input component
   <TextInput
     placeholder="Search implants..."
     leftSection={<FaSearch size={14} />}
     value={searchTerm}
     onChange={(e) => setSearchTerm(e.currentTarget.value)}
     size="sm"
     style={{ width: '300px' }}
     styles={(theme: any) => ({
       input: {
         borderRadius: theme.radius.xl,
       },
     })}
   />
   ```

2. **Search Logic**:
   - The search function filters implants by matching the search term against multiple properties:
   ```typescript
   // Filtered implants based on search term
   const filteredImplants = implants.filter(imp => {
     if (!searchTerm) return true;
     
     const searchLower = searchTerm.toLowerCase();
     return (
       imp.hostname?.toLowerCase().includes(searchLower) ||
       imp.username?.toLowerCase().includes(searchLower) ||
       imp.guid?.toLowerCase().includes(searchLower) ||
       imp.ipAddrInt?.toLowerCase().includes(searchLower) ||
       imp.ipAddrExt?.toLowerCase().includes(searchLower) ||
       imp.osBuild?.toLowerCase().includes(searchLower) ||
       imp.pname?.toLowerCase().includes(searchLower)
     );
   });
   ```

3. **Optimizations**:
   - The search is performed client-side for immediate results without additional server load
   - Debouncing was implemented to prevent excessive re-renders during typing
   - Search logic is case-insensitive and supports partial matches
   - Performance is maintained through efficient React state management

#### Status Filter Implementation

Status filters were implemented to allow toggling visibility of implants by status:

1. **Filter UI Component**:
   ```typescript
   // In components/StatusFilters.tsx
   const StatusFilters = ({ 
     activeFilters, 
     onFilterChange 
   }: StatusFiltersProps) => {
     return (
       <Paper p="md" radius="md" withBorder>
         <Stack spacing="xs">
           <Title order={6}>Status Filters</Title>
           
           <Group spacing="xs">
             {statusOptions.map((status) => (
               <Button
                 key={status.value}
                 variant={activeFilters.includes(status.value) ? "filled" : "outline"}
                 color={status.color}
                 leftIcon={status.icon}
                 size="xs"
                 onClick={() => onFilterChange(status.value)}
               >
                 {status.label}
               </Button>
             ))}
           </Group>
           
           <Button 
             variant="subtle" 
             size="xs"
             onClick={() => onFilterChange('reset')}
           >
             Reset Filters
           </Button>
         </Stack>
       </Paper>
     );
   };
   ```

2. **Filter State Management**:
   ```typescript
   // In pages/implants/index.tsx
   const [statusFilters, setStatusFilters] = useState<string[]>([]);
   
   const handleFilterChange = (status: string) => {
     if (status === 'reset') {
       setStatusFilters([]);
       return;
     }
     
     setStatusFilters(prev => {
       if (prev.includes(status)) {
         return prev.filter(s => s !== status);
       } else {
         return [...prev, status];
       }
     });
   };
   
   // Apply filters to implants
   const filteredByStatus = statusFilters.length > 0
     ? filteredImplants.filter(imp => statusFilters.includes(imp.status))
     : filteredImplants;
   ```

3. **Integration with Search**:
   - Filters are applied after the search term, allowing combined searching and filtering
   - The filtering system maintains the original implant array to allow toggling filters on/off
   - Visual feedback indicates which filters are currently active

#### "Show Inactive" Toggle Implementation

The "Show Inactive" toggle was implemented as a global filter with its own state:

1. **Component Implementation**:
   ```typescript
   // In pages/implants/index.tsx
   const [showOnlyActive, setShowOnlyActive] = useState<boolean>(true);
   
   // Toggle switch
   <Group>
     <Text size="sm" fw={500}>Show inactive:</Text>
     <Switch
       checked={!showOnlyActive}
       onChange={() => setShowOnlyActive(!showOnlyActive)}
       color="teal"
       size="md"
       thumbIcon={
         showOnlyActive ? (
           <FaEyeSlash size="0.6rem" color="white" />
         ) : (
           <FaEye size="0.6rem" color="white" />
         )
       }
     />
   </Group>
   ```

2. **Filter Logic**:
   ```typescript
   // Final filtering with "show inactive" logic applied
   const displayedImplants = showOnlyActive
     ? filteredByStatus.filter(imp => imp.status !== 'inactive')
     : filteredByStatus;
   ```

3. **Persistence**:
   - The state is persisted in local storage to maintain user preference across sessions
   - Default state is "OFF" to focus on active implants by default
   - The toggle is prominently displayed in the header area for easy access

#### Integration with API and Data Refresh

The search and filtering system is fully integrated with the real-time data refresh mechanism:

1. **Preserving State During Updates**:
   ```typescript
   // Preserve search and filter state when new data arrives
   useEffect(() => {
     const fetchImplants = async () => {
       const result = await getImplants();
       if (result.success) {
         setImplants(result.data);
         // Filters and search term are maintained in React state
         // and automatically reapplied to the new data
       }
     };
     
     fetchImplants();
     const interval = setInterval(fetchImplants, refreshInterval);
     return () => clearInterval(interval);
   }, [refreshInterval]);
   ```

2. **Performance Considerations**:
   - The filtering system is optimized to handle large numbers of implants
   - Memoization is used to prevent unnecessary re-renders
   - Updates only affect the data, not the filter/search state

#### Usage in Operations

This search and filtering system significantly improves operational capabilities:

1. **Quick Target Identification**:
   - Operators can quickly locate specific implants by hostname, username, or IP
   - Combined filtering allows focusing on, for example, only active implants in a specific subnet

2. **Operational Awareness**:
   - Status filters provide immediate visibility into problematic implants
   - The "Show Inactive" toggle helps manage the lifecycle of implants

3. **Large-Scale Operations**:
   - The system scales effectively to handle hundreds of implants
   - Performance remains smooth even with extensive filtering and searching

4. **Workflow Enhancement**:
   - The integrated search and filtering creates a seamless workflow for operators
   - Visual indicators make it immediately clear which filters are active

The search and filtering capabilities add significant value to the operational use of Nimhawk, particularly in enterprise environments where managing larger numbers of implants is common.

### 4. User interface improvements

- Implant details side panel (NimplantDrawer) completely redesigned
- More comprehensive information about implant status
- Display of relevant metrics such as check-in count
- Better organization of information to facilitate analysis
- Color-coded status indicators for quick visual assessment

### 5. Implant deletion API

The ability to delete inactive implants has been implemented with a comprehensive approach that ensures data integrity:

#### API Implementation

```python
# In admin_server_init.py
@app.route('/api/nimplants/<guid>', methods=['DELETE'])
@require_auth
def delete_nimplant(guid):
    """
    DELETE endpoint to remove an inactive implant from the database.
    Only inactive implants can be deleted for safety reasons.
    """
    # Validate GUID format to prevent injection
    if not utils.is_valid_guid(guid):
        return flask.jsonify({"error": "Invalid GUID format"}), 400
        
    # Check if implant exists and is inactive
    implant_details = db_get_nimplant_details(guid)
    if not implant_details:
        return flask.jsonify({"error": "Implant not found"}), 404
    
    if implant_details.get("active", True):
        return flask.jsonify({"error": "Cannot delete an active implant"}), 400
    
    # Delete the implant
    success = db_delete_nimplant(guid)
    if success:
        # Log the deletion
        utils.nimplant_print(f"Implant {guid} deleted by administrator")
        return flask.jsonify({"message": "Implant deleted successfully"}), 200
    else:
        return flask.jsonify({"error": "Failed to delete implant"}), 500
```

#### Database Operations

The `db_delete_nimplant` function handles the comprehensive deletion of all implant-related data:

```python
# In db.py
def db_delete_nimplant(guid):
    """
    Delete an implant and all its associated data from the database.
    This includes command history, file downloads, and check-ins.
    """
    try:
        with get_db_connection() as con:
            # Begin transaction
            con.execute("BEGIN TRANSACTION")
            
            # Delete command history
            con.execute("DELETE FROM command_history WHERE nimplant_id = ?", (guid,))
            
            # Delete file downloads
            con.execute("DELETE FROM downloads WHERE nimplant_id = ?", (guid,))
            
            # Delete check-ins
            con.execute("DELETE FROM check_ins WHERE nimplant_id = ?", (guid,))
            
            # Delete the implant itself
            con.execute("DELETE FROM nimplants WHERE id = ?", (guid,))
            
            # Commit transaction
            con.execute("COMMIT")
            
        # Delete any downloaded files associated with this implant
        download_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "downloads", guid)
        if os.path.exists(download_dir) and os.path.isdir(download_dir):
            shutil.rmtree(download_dir)
            
        return True
    except Exception as e:
        utils.nimplant_print(f"ERROR: Failed to delete implant {guid}: {e}")
        # Rollback transaction if something goes wrong
        if 'con' in locals():
            con.execute("ROLLBACK")
        return False
```

#### Security Considerations

The implant deletion feature includes several security measures:

1. **Inactive-Only Deletion**: Only implants marked as inactive can be deleted, preventing accidental deletion of active connections
2. **Authorization Required**: The endpoint is protected by the `@require_auth` decorator to ensure only authenticated users can delete implants
3. **GUID Validation**: The GUID is validated to prevent SQL injection or other attacks
4. **Transaction-Based**: Database operations are wrapped in a transaction to maintain data integrity
5. **Comprehensive Cleanup**: All related data and files are deleted to prevent orphaned records
6. **Error Handling**: Robust error handling with transaction rollback in case of failure
7. **Audit Logging**: All deletion operations are logged for accountability

## Subsystem architecture

### Workspace system architecture

Workspaces are primarily managed through the following database tables:

- **workspaces**: Stores workspace metadata including UUID, name, and creation date
- **nimplant**: Contains a workspace_uuid field that references the workspaces table

**Key relationships:**
- One-to-many relationship between workspaces and implants
- Implants may belong to at most one workspace or none (NULL workspace_uuid)

The workspace system is implemented through these primary functions in `db.py`:

1. **db_create_workspace(workspace_name)**: 
   - Creates a new workspace with a generated UUID
   - Returns the UUID of the newly created workspace
   - Used by the API endpoint for workspace creation

2. **db_get_workspaces()**:
   - Retrieves all workspaces ordered by creation date
   - Returns workspace data including UUID, name, and creation date
   - Used for populating workspace lists in the UI

3. **db_assign_nimplant_to_workspace(nimplant_guid, workspace_uuid)**:
   - Assigns an existing implant to a specific workspace
   - Updates the workspace_uuid field in the implant record
   - Used when manually assigning implants to workspaces

4. **db_remove_nimplant_from_workspace(nimplant_guid)**:
   - Removes an implant from its current workspace (sets workspace_uuid to NULL)
   - Used when unassigning an implant from a workspace

5. **db_get_nimplants_by_workspace(workspace_uuid)**:
   - Retrieves all implants assigned to a specific workspace
   - Returns detailed implant information for each matching record
   - Used for filtering implants by workspace in the UI

6. **db_delete_workspace(workspace_uuid)**:
   - Deletes a workspace and removes all implant associations
   - Does not delete the implants themselves
   - Updates all implants to have NULL workspace_uuid

**API Endpoints:**

The workspace API is implemented in `admin_server_init.py` with these endpoints:

- **GET /api/workspaces**: Lists all workspaces
- **POST /api/workspaces**: Creates a new workspace
- **DELETE /api/workspaces/<workspace_uuid>**: Deletes a specific workspace
- **GET /api/workspaces/<workspace_uuid>/nimplants**: Lists implants in a workspace
- **POST /api/workspaces/assign**: Assigns implant to workspace
- **POST /api/workspaces/remove**: Removes implant from workspace

**Frontend Implementation:**

The workspace UI components include:

1. **WorkspaceSelector.tsx**: Component for workspace selection and management
2. **WorkspaceBadge.tsx**: Visual representation of workspace with color coding
3. **CreateWorkspaceModal.tsx**: Modal for creating new workspaces

**Communication Flow:**

The workspace UUID is passed to implants through the X-Robots-Tag HTTP header. This occurs at two key points:

1. **Initial Registration**: When an implant first registers, it can include the workspace UUID in the header
2. **Reassignment**: When an implant is assigned to a different workspace, the change is stored in the database

### File exchange system implementation

File transfers are tracked through these primary tables:

- **file_transfers**: Records metadata about each transfer operation
- **file_hash_mapping**: Maps file hashes to original filenames and paths
- **downloads**: Contains information about files downloaded from implants

**Core Functions:**

The file exchange system is implemented through these key functions in `db.py`:

1. **db_log_file_transfer(nimplant_guid, filename, size, operation_type)**:
   - Records a file transfer operation in the database
   - Tracks the implant GUID, filename, size, and operation type
   - Used for logging all file operations (upload, download, view)

2. **db_get_file_transfers(nimplant_guid, limit=50)**:
   - Retrieves file transfer history for a specific implant
   - Limited to the specified number of most recent transfers
   - Used for displaying implant-specific file history

3. **db_get_file_transfers_api(nimplant_guid=None, limit=50)**:
   - Returns file transfers with optional filtering by implant
   - Used by the API endpoint for retrieving transfer history
   - Includes hostname and username information from nimplant table

4. **db_store_file_hash_mapping(file_hash, original_filename, file_path)**:
   - Creates or updates a mapping between file hash and original filename
   - Ensures original filenames are preserved even with hash-based storage
   - Critical for file identification and retrieval

5. **db_get_file_info_by_hash(file_hash)**:
   - Retrieves original filename and path based on file hash
   - Used when serving files through the API
   - Returns None for both values if hash is not found

**File Storage Organization:**

Files are stored in the filesystem with this structure:

- **downloads/{nimplant_guid}/**:
  - Contains files downloaded from a specific implant
  - Files are named with their MD5 hash to avoid conflicts
  - Original filenames are stored in the database

- **uploads/**:
  - Contains files prepared for upload to implants
  - Used as a staging area before transfer
  - Files are cleaned up after successful transfer

**API Endpoints:**

The file exchange API is implemented with these endpoints:

- **GET /api/downloads**: Lists all downloaded files
- **GET /api/downloads/{nimplant_guid}/{filename}**: Serves a specific file
- **GET /api/file-transfers**: Lists all file transfers
- **GET /api/file-transfers/{nimplant_guid}**: Lists transfers for an implant
- **POST /api/upload**: Uploads a file to the server for transfer to implants

**Frontend Components:**

Key UI components for file management:

1. **FileListComponent.tsx**: Generic component for displaying file lists
2. **DownloadList.tsx**: Component for displaying global download lists
3. **ImplantDownloadList.tsx**: Component for implant-specific downloads
4. **FilePreview.tsx**: Component for rendering file previews
5. **FileTypeIcon.tsx**: Component for displaying appropriate file type icons

**Transfer Process Flow:**

The complete file transfer process works as follows:

##### Download Process (implant to server):
1. Client issues a download command for a specific file
2. Command is queued as a pending task for the implant
3. Implant executes the task, reads the file, and encodes it
4. Implant transmits file data to server via POST request to resultPath
5. Server decodes the data and saves it to downloads/{nimplant_guid}/
6. Server logs the transfer in the database with operation type "DOWNLOAD"
7. File is accessible via the downloads endpoint with its recorded metadata

##### Upload Process (server to implant):
1. Client uploads a file through the web interface or API
2. File is saved to the uploads directory with a unique identifier
3. A task is created for the implant to download the file
4. Implant requests the file via the task_path endpoint
5. Server serves the file to the implant
6. Implant saves the file to the specified location
7. Implant confirms completion and server logs the transfer

**Security Considerations:**

The file exchange system implements several security measures:

1. **Authentication**: All file transfers require proper authentication
2. **Encryption**: File data is encrypted during transit
3. **Integrity Verification**: File hashes are verified after transfer
4. **Access Control**: Files are only accessible to authorized users
5. **Content Validation**: Basic validation of file types and contents

**Error Handling:**

The system includes robust error handling for:

1. **File Not Found**: When requested files don't exist
2. **Permission Issues**: When files can't be read or written
3. **Transmission Errors**: When data becomes corrupted during transfer
4. **Storage Limits**: When disk space is insufficient
5. **Concurrent Access**: When multiple operations target the same resource

## Future plans

We have made significant progress on several planned improvements, with successful implementation of the enhanced reconnection system and multi-status implant support. We continue to work on other key areas:

### Already Implemented
- ✅ Enhanced reconnection system with registry cleanup
- ✅ Multi-status implant visualization system
- ✅ UI improvements for better operational awareness
- ✅ Server-side status determination logic
- ✅ Inactive implant deletion functionality

### In Progress
- **Advanced Evasion Techniques**:
  - NTDLL Unhook
  - AMSI and ETW patching/bypassing mechanisms
  - Sleep obfuscation techniques (Ekko is already in place thanks to @chvancooten)
  - Memory payload protection (encryption at rest)

- **Stealthiness Analysis Framework**:
  - Expanding the `detection` directory from Nimplant's original detection rules to a comprehensive toolkit
  - Implementing PE-sieve integration for runtime memory analysis
  - Creating ThreatCheck-like functionality to identify specific detection signatures

### Planned
- **Payload Delivery Mechanisms**:
  - Classic DLL Injection
  - Remote Shellcode Injection
  - Process Hollowing with advanced unmapping techniques
  - Thread Hijacking with context manipulation
  - APC Injection (standard and early bird variants)
  - And many additional techniques

- **Defense Evasion**:
  - Anti-sandbox detection techniques
  - Anti-analysis countermeasures
  - Stack spoofing for hiding call stacks

## Contributing

If you're interested in contributing to Nimhawk, we welcome your input and expertise. The project is designed with modularity in mind to make contributions more accessible.

### Contributing Guidelines

1. **Fork the repository** and create a feature branch from the main branch
2. **Make your changes** following the established code style and architecture
3. **Add tests** if applicable for the new functionality
4. **Update documentation** to reflect changes made
5. **Submit a pull request** with a clear description of the changes and their purpose

### Contributing to the reconnection system

If you wish to further enhance the reconnection system, here are some areas to focus on:

1. **Advanced Registry Handling**:
   - Implement additional storage locations for increased resilience
   - Add encryption for stored registry values
   - Implement registry monitoring for tampering detection

2. **Connection Resilience**:
   - Enhance proxy support for reconnection paths
   - Implement additional transport methods for challenging network environments
   - Add circuit breaker patterns to prevent excessive reconnection attempts

3. **Additional Status States**:
   - Implement more granular status tracking (e.g., "sleeping", "awaiting commands", etc.)
   - Add customizable thresholds for the different status states

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Support the project

If you find Nimhawk useful for your work, consider supporting the project:

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/hdbreaker9s)