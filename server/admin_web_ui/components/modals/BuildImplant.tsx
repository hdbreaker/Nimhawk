import { Button, Modal, Text, Group, Switch, Box, Loader, Alert, Progress, Select, Divider, Paper, Stack, Title, Badge, ThemeIcon, ScrollArea, useMantineTheme } from "@mantine/core"
import { FaHammer, FaFileDownload, FaPlus, FaFolder, FaCheckCircle, FaExclamationTriangle, FaTrash, FaExclamationCircle } from "react-icons/fa"
import { buildImplant, endpoints } from "../../modules/nimplant";
import { Dispatch, SetStateAction, useState, useEffect, useCallback } from "react";
import { notifications } from '@mantine/notifications';

interface IProps {
    modalOpen: boolean;
    setModalOpen: Dispatch<SetStateAction<boolean>>;
}

interface Workspace {
    id: number;
    workspace_uuid: string;
    workspace_name: string;
    creation_date: string;
}

function BuildImplantModal({ modalOpen, setModalOpen }: IProps) {
    const theme = useMantineTheme();
    const [isDebug, setIsDebug] = useState(false);
    const [isBuilding, setIsBuilding] = useState(false);
    const [buildResult, setBuildResult] = useState<any>(null);
    const [buildId, setBuildId] = useState<string | null>(null);
    const [buildStatus, setBuildStatus] = useState<any>(null);
    const [error, setError] = useState<string | null>(null);
    
    // Workspace related states
    const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
    const [selectedWorkspace, setSelectedWorkspace] = useState<string | null>(null);
    const [searchValue, setSearchValue] = useState('');
    const [isCreatingWorkspace, setIsCreatingWorkspace] = useState(false);
    
    // New states for delete modal
    const [deleteModalOpen, setDeleteModalOpen] = useState(false);
    const [workspaceToDelete, setWorkspaceToDelete] = useState<{uuid: string, name: string} | null>(null);
    
    // Load workspaces when modal opens
    useEffect(() => {
        if (modalOpen) {
            fetchWorkspaces();
        }
    }, [modalOpen]);
    
    // Fetch workspaces from the server
    const fetchWorkspaces = async () => {
        try {
            // Obtain token from localStorage
            const token = localStorage.getItem('auth_token');
            
            const response = await fetch(`${endpoints.workspaces}`, {
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                console.log("Fetched workspaces:", data);
                setWorkspaces(data);
            } else {
                console.error("Error fetching workspaces:", await response.text());
            }
        } catch (err) {
            console.error("Error fetching workspaces:", err);
        }
    };
    
    // Handle workspace creation when no match is found
    function handleCreateFromSearch() {
        if (!searchValue.trim()) return;
        
        const workspaceName = searchValue;
        console.log("Attempting to create workspace from search:", workspaceName);
        
        // Store the name we're trying to create so we can keep showing the button
        const nameToCreate = searchValue;
        
        try {
            setIsCreatingWorkspace(true);
            
            // Make direct API call without using the createWorkspace function
            const token = localStorage.getItem('auth_token');
            
            // Use .then instead of async/await to avoid potential problems
            fetch(endpoints.workspaces, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                },
                body: JSON.stringify({ workspace_name: workspaceName })
            })
            .then(response => {
                console.log(`Create workspace API response status: ${response.status}`);
                return response.text().then(text => {
                    console.log(`Create workspace API response text:`, text);
                    if (!response.ok) {
                        throw new Error(`Server error: ${text}`);
                    }
                    return text;
                });
            })
            .then(responseText => {
                // Try to parse JSON response
                let data;
                try {
                    data = JSON.parse(responseText);
                    console.log("Parsed response data:", data);
                } catch (e) {
                    console.error("Failed to parse JSON response:", e);
                    throw new Error("Invalid server response format");
                }
                
                // Show success notification
                notifications.show({
                    title: 'Success',
                    message: `Workspace "${workspaceName}" created`,
                    color: 'green',
                });
                
                // Refresh workspaces list
                fetchWorkspaces().then(() => {
                    // Set the newly created workspace as selected
                    if (data && data.workspace_uuid) {
                        console.log("Setting selected workspace to:", data.workspace_uuid);
                        setSelectedWorkspace(data.workspace_uuid);
                    }
                    
                    // Clear search
                    setSearchValue('');
                });
            })
            .catch(error => {
                console.error("Error creating workspace:", error);
                setError(`Failed to create workspace: ${error instanceof Error ? error.message : String(error)}`);
                
                // Reset search value to what the user had typed to allow retrying
                setSearchValue(nameToCreate);
                
                // Show error notification
                notifications.show({
                    title: 'Error',
                    message: `Failed to create workspace: ${error instanceof Error ? error.message : String(error)}`,
                    color: 'red',
                });
            })
            .finally(() => {
                setIsCreatingWorkspace(false);
            });
        } catch (error) {
            console.error("Error in handleCreateFromSearch:", error);
            setIsCreatingWorkspace(false);
            setError(`Error: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    
    // Poll for build status when buildId is available
    useEffect(() => {
        if (!buildId) return;
        
        const checkBuildStatus = async () => {
            try {
                // Obtain token from localStorage
                const token = localStorage.getItem('auth_token');
                
                const response = await fetch(`${endpoints.build}/status/${buildId}`, {
                    headers: {
                        'Content-Type': 'application/json',
                        ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                    }
                });
                const status = await response.json();
                
                setBuildStatus(status);
                
                if (status.status === 'completed') {
                    setIsBuilding(false);
                    setBuildResult(status);
                } else if (status.status === 'failed') {
                    setIsBuilding(false);
                    setError(status.error || "Compilation failed. Check the logs for more details.");
                } else {
                    // Continue polling
                    setTimeout(checkBuildStatus, 2000);
                }
            } catch (err) {
                console.error("Error checking build status:", err);
                setTimeout(checkBuildStatus, 5000);
            }
        };
        
        checkBuildStatus();
    }, [buildId]);

    const handleBuild = async () => {
        setIsBuilding(true);
        setError(null);
        setBuildResult(null);
        setBuildStatus(null);
        
        try {
            // Call buildImplant with workspace parameter
            buildImplant(isDebug, (data) => {
                if (data && data.build_id) {
                    setBuildId(data.build_id);
                } else {
                    setIsBuilding(false);
                    setError("Failed to start build process");
                }
            }, selectedWorkspace);
        } catch (err) {
            console.error("Error starting build:", err);
            setIsBuilding(false);
            setError("Failed to start build process. Check the connection to the server.");
        }
    };

    const handleClose = () => {
        setModalOpen(false);
        setIsBuilding(false);
        setBuildResult(null);
        setBuildStatus(null);
        setBuildId(null);
        setError(null);
        setSelectedWorkspace(null);
        setSearchValue('');
    };

    const handleDownload = () => {
        if (buildResult && buildResult.download_url) {
            // Get the authentication token from localStorage
            const token = localStorage.getItem('auth_token');
            
            // Include the token as a URL parameter for authentication
            const downloadUrl = `${endpoints.server.replace('/api/server', '')}${buildResult.download_url}?token=${token}`;
            
            window.open(downloadUrl, '_blank');
        }
    };

    // Calculate progress information
    const getProgressInfo = () => {
        if (!buildStatus) return "Starting compilation...";
        return buildStatus.progress || "Compiling implants...";
    };
    
    // Prepare workspace data for Select component
    const workspaceSelectData = [
        { value: 'Default', label: 'Default (No Workspace)', uuid: '' },
        ...workspaces.filter(ws => ws.workspace_name !== 'Default').map(ws => ({ 
            value: ws.workspace_uuid, 
            label: ws.workspace_name,
            uuid: ws.workspace_uuid
        }))
    ];

    // Custom component for dropdown options
    const CustomSelectOption = ({ option }: { option: { label: string, uuid?: string } }) => {
        if (!option.uuid) return <div>{option.label}</div>;
        
        return (
            <Group justify="space-between" style={{ width: '100%' }}>
                <Text>{option.label}</Text>
                {option.uuid && option.uuid !== '' && (
                    <Button
                        variant="subtle"
                        color="red"
                        size="xs"
                        onClick={(e) => {
                            e.stopPropagation();
                            const workspace = workspaces.find(w => w.workspace_uuid === option.uuid);
                            if (workspace && option.uuid) {
                                handleDeleteWorkspace(option.uuid, workspace.workspace_name);
                            }
                        }}
                        title="Delete workspace"
                        disabled={isBuilding || buildResult !== null}
                        styles={{ root: { padding: '2px 6px', minWidth: 'auto' } }}
                    >
                        ✕
                    </Button>
                )}
            </Group>
        );
    };
    
    // Check if search value matches any existing workspace
    const searchValueExists = workspaceSelectData.some(
        item => item.label.toLowerCase() === searchValue.toLowerCase()
    );
    
    // Add a new function to delete workspaces
    const handleDeleteWorkspace = (workspaceUuid: string, workspaceName: string) => {
        setWorkspaceToDelete({uuid: workspaceUuid, name: workspaceName});
        setDeleteModalOpen(true);
    };
    
    // Add function to confirm the deletion
    const confirmDeleteWorkspace = async () => {
        if (!workspaceToDelete) return;
        
        try {
            setDeleteModalOpen(false);
            
            // Get token from localStorage
            const token = localStorage.getItem('auth_token');
            
            const response = await fetch(`${endpoints.workspaces}/${workspaceToDelete.uuid}`, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                }
            });
            
            if (response.ok) {
                // Show success notification
                notifications.show({
                    title: 'Success',
                    message: `Workspace "${workspaceToDelete.name}" deleted successfully`,
                    color: 'green',
                });
                
                // If the deleted workspace was the selected one, clear the selection
                if (selectedWorkspace === workspaceToDelete.uuid) {
                    setSelectedWorkspace(null);
                }
                
                // Update the workspaces list
                await fetchWorkspaces();
            } else {
                const errorText = await response.text();
                console.error(`Error deleting workspace: ${errorText}`);
                notifications.show({
                    title: 'Error',
                    message: `Failed to delete workspace: ${errorText}`,
                    color: 'red',
                });
            }
        } catch (error) {
            console.error("Error deleting workspace:", error);
            notifications.show({
                title: 'Error',
                message: `Error deleting workspace: ${error instanceof Error ? error.message : String(error)}`,
                color: 'red',
            });
        } finally {
            setWorkspaceToDelete(null);
        }
    };

    return (
        <>
            {/* Confirmation modal to delete workspace */}
            <Modal
                opened={deleteModalOpen}
                onClose={() => setDeleteModalOpen(false)}
                title={<Title order={4} c="red.7">Delete Workspace</Title>}
                centered
                size="md"
                radius="md"
                padding="xl"
                zIndex={1000}
                styles={{
                    header: { 
                        backgroundColor: theme.colors.gray[0],
                        borderBottom: `1px solid ${theme.colors.gray[2]}`,
                        padding: '15px 20px'
                    },
                    body: { padding: '20px' },
                    overlay: {
                        zIndex: 1000
                    },
                    inner: {
                        zIndex: 1000
                    }
                }}
            >
                <Stack>
                    <Group>
                        <ThemeIcon color="red" size="lg" radius="xl">
                            <FaExclamationCircle />
                        </ThemeIcon>
                        <Text size="lg" fw={500}>Are you sure?</Text>
                    </Group>
                    
                    <Text>
                        You are about to delete the workspace &quot;{workspaceToDelete?.name}&quot;. This action cannot be undone.
                    </Text>
                    
                    <Text size="sm" c="dimmed" mt="xs">
                        All implants associated with this workspace will be returned to the default group.
                    </Text>
                    
                    <Divider my="md" />
                    
                    <Group justify="space-between">
                        <Button
                            variant="subtle" 
                            onClick={() => setDeleteModalOpen(false)}
                        >
                            Cancel
                        </Button>
                        
                        <Button
                            color="red"
                            leftSection={<FaTrash size={14} />}
                            onClick={confirmDeleteWorkspace}
                        >
                            Delete Workspace
                        </Button>
                    </Group>
                </Stack>
            </Modal>

            {/* Main modal to build implants */}
            <Modal
                opened={modalOpen}
                onClose={handleClose}
                title={<Title order={4}>Build Implants</Title>}
                centered
                size="lg"
                radius="md"
                padding="xl"
                styles={{
                    header: { 
                        backgroundColor: theme.colors.gray[0],
                        borderBottom: `1px solid ${theme.colors.gray[2]}`,
                        padding: '15px 20px' 
                    },
                    body: { padding: '20px' },
                }}
            >
                <Stack>
                    <Text size="sm" color="dimmed">
                        This process will compile the complete implant package (EXE, DLL, and shellcode).
                        Compilation can take several minutes, especially the first time.
                    </Text>

                    <Paper p="md" radius="md" withBorder>
                        <Stack>
                            <Title order={5}>Build Options</Title>
                            
                            <Switch 
                                checked={isDebug}
                                onChange={(e) => setIsDebug(e.currentTarget.checked)}
                                label={
                                    <Group>
                                        <Text>Debug Mode</Text>
                                        {isDebug && <Badge color="orange" size="xs">Debug</Badge>}
                                    </Group>
                                }
                                description="Compiles with additional debugging information"
                                disabled={isBuilding || buildResult !== null}
                                styles={{
                                    label: { fontWeight: 500 },
                                    thumb: { 
                                        backgroundColor: isDebug ? '#fff' : undefined,
                                    },
                                    track: {
                                        backgroundColor: isDebug ? theme.colors.orange[6] : undefined
                                    }
                                }}
                                size="md"
                                color={isDebug ? "orange" : "dark"}
                            />
                        </Stack>
                    </Paper>

                    <Paper p="md" radius="md" withBorder>
                        <Stack>
                            <Group justify="apart">
                                <Title order={5}>Workspace</Title>
                                <Badge color="gray" variant="light">Optional</Badge>
                            </Group>
                            
                            <Select
                                placeholder="Search or create workspace"
                                label="Assign to workspace"
                                leftSection={<FaFolder size={14} />}
                                data={workspaceSelectData}
                                value={selectedWorkspace}
                                onChange={setSelectedWorkspace}
                                clearable
                                searchable
                                searchValue={searchValue}
                                onSearchChange={setSearchValue}
                                disabled={isBuilding || buildResult !== null || isCreatingWorkspace}
                                styles={{ 
                                    root: { marginBottom: 10 },
                                    input: { borderRadius: 8 },
                                    dropdown: { maxHeight: 200 }
                                }}
                                renderOption={({ option }) => (
                                    <CustomSelectOption option={option} />
                                )}
                            />
                            
                            {searchValue.trim() !== '' && !searchValueExists && !isCreatingWorkspace && (
                                <Button 
                                    onClick={handleCreateFromSearch}
                                    onMouseDown={() => {
                                        console.log("Mouse down on create workspace button");
                                        handleCreateFromSearch();
                                    }}
                                    leftSection={<FaPlus size={14} />}
                                    size="xs"
                                    color="dark"
                                    variant="gradient"
                                    gradient={{ from: 'gray.5', to: 'dark', deg: 45 }}
                                    styles={{ 
                                        root: { 
                                            marginTop: -5,
                                            position: 'relative',
                                            zIndex: 10,
                                            boxShadow: theme.shadows.xs,
                                            transition: 'all 0.2s ease',
                                            '&:hover': {
                                                transform: 'translateY(-1px)',
                                                boxShadow: theme.shadows.sm
                                            }
                                        } 
                                    }}
                                    fullWidth
                                >
                                    Create &quot;{searchValue}&quot; workspace
                                </Button>
                            )}
                        </Stack>
                    </Paper>

                    {error && (
                        <Alert 
                            color="red" 
                            title="Error" 
                            icon={<FaExclamationTriangle />}
                            radius="md"
                        >
                            {error}
                        </Alert>
                    )}

                    {isBuilding && (
                        <Paper p="md" radius="md" withBorder shadow="sm">
                            <Stack>
                                <Group justify="center" style={{ width: '100%' }}>
                                    <Loader size="sm" color={isDebug ? "orange" : "dark"} />
                                    <Text fw={500} color="dark" ta="center">{getProgressInfo()}</Text>
                                    <Loader size="sm" color={isDebug ? "orange" : "dark"} />
                                </Group>
                                <Progress
                                    animated
                                    value={100}
                                    color={isDebug ? "orange" : "dark"}
                                    size="md"
                                    radius="xl"
                                    striped
                                />
                                <Group justify="center" style={{ width: '100%' }}>
                                    <Text size="xs" color="dimmed">
                                        This process may take several minutes...
                                    </Text>
                                </Group>
                            </Stack>
                        </Paper>
                    )}

                    {buildResult && buildResult.status === 'completed' && (
                        <Paper p="md" radius="md" withBorder shadow="sm">
                            <Stack>
                                <Group>
                                    <ThemeIcon color={isDebug ? "orange" : "dark"} size="lg" radius="xl">
                                        <FaCheckCircle />
                                    </ThemeIcon>
                                    <Title order={5} style={{ color: isDebug ? theme.colors.orange[7] : theme.colors.dark[7] }}>Compilation Successful</Title>
                                </Group>
                                
                                <Divider />
                                
                                <Text size="sm" fw={500}>Generated files:</Text>
                                <ScrollArea style={{ height: 120 }} offsetScrollbars scrollbarSize={8}>
                                    {buildResult.files && buildResult.files.map((file: string, index: number) => (
                                        <Box 
                                            key={index}
                                            p="xs"
                                            mb={5}
                                            style={{ 
                                                fontFamily: 'monospace',
                                                backgroundColor: theme.colors.gray[0],
                                                borderRadius: 4,
                                                fontSize: '0.85rem'
                                            }}
                                        >
                                            {file}
                                        </Box>
                                    ))}
                                </ScrollArea>
                            </Stack>
                        </Paper>
                    )}

                    <Divider my="sm" />

                    <Group justify="center">
                        {!buildResult ? (
                            <Button
                                onClick={handleBuild}
                                leftSection={<FaHammer />}
                                disabled={isBuilding}
                                color={isDebug ? "orange" : "dark"}
                                size="md"
                                fullWidth
                                radius="md"
                                styles={{
                                    root: {
                                        boxShadow: theme.shadows.sm,
                                        transition: 'all 0.3s ease',
                                        '&:hover': {
                                            transform: 'translateY(-2px)',
                                            boxShadow: theme.shadows.md
                                        }
                                    }
                                }}
                            >
                                {isBuilding ? "Compiling..." : "Build Implants"}
                                {isDebug && !isBuilding && <Badge ml="xs" size="sm" color="orange">Debug</Badge>}
                            </Button>
                        ) : (
                            <Button
                                onClick={handleDownload}
                                leftSection={<FaFileDownload />}
                                color={isDebug ? "orange" : "dark"}
                                size="md"
                                fullWidth
                                radius="md"
                                styles={{
                                    root: {
                                        boxShadow: theme.shadows.sm,
                                        transition: 'all 0.3s ease',
                                        '&:hover': {
                                            transform: 'translateY(-2px)',
                                            boxShadow: theme.shadows.md
                                        }
                                    }
                                }}
                            >
                                Download implants
                            </Button>
                        )}
                    </Group>
                </Stack>
            </Modal>
        </>
    )
}

export default BuildImplantModal 