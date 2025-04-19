# Verify the implant
# Check the implant
# Make sure the implant is active
# Ensure the implant is active
# Check if the implant belongs to the workspace
# Verify if the implant belongs to the workspace 

# Print loaded routes for diagnosis
utils.nimplant_print(f"Implants server routes: {list(app.url_map.iter_rules())}")

# If we have workspace_uuid, assign it to the implant
if workspace_uuid:
    np.workspace_uuid = workspace_uuid
    utils.nimplant_print(f"DEBUG: Assigning workspace UUID: {workspace_uuid} to implant")

# If the implant doesn't have workspace_uuid but we received one, we assign it now
if workspace_uuid and not hasattr(np, 'workspace_uuid'):
    np.workspace_uuid = workspace_uuid
    utils.nimplant_print(f"DEBUG: Assigning workspace UUID: {workspace_uuid} to implant")

# Save the workspace_uuid to the database
if hasattr(np, 'workspace_uuid') and np.workspace_uuid:
    utils.nimplant_print(f"DEBUG: Workspace UUID will be saved to database: {np.workspace_uuid}")

# Update check-in
np.checkin()
np.late = False  # Force non-late status when implant connects

# Print all available routes AFTER registering them
utils.nimplant_print(f"Implants server routes after registration: {list(app.url_map.iter_rules())}")

# Verify the implant
utils.nimplant_print(f"Result server - verify_nimplant called for {guid}")

# Make sure the implant is active
if not np.active:
    utils.nimplant_print(f"Implant {guid} not active, returning None")
    return None

# Check if the implant belongs to the workspace
if hasattr(np, 'workspace_uuid') and np.workspace_uuid and np.workspace_uuid != workspace_uuid:
    utils.nimplant_print(f"Implant {guid} belongs to workspace {np.workspace_uuid}, not {workspace_uuid}")
    return None 