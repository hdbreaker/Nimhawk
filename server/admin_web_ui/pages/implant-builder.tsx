import { useState, useEffect } from "react";
import { 
    Container, 
    Title, 
    Text, 
    Grid, 
    Card, 
    Button, 
    Group, 
    Stack, 
    Badge, 
    ThemeIcon,
    Paper,
    useMantineTheme,
    Loader,
    Alert,
    Modal,
    Select,
    Switch,
    TextInput,
    NumberInput,
    Checkbox,
    Divider,
    ScrollArea,
    Progress,
    Box
} from "@mantine/core";
import { 
    FaWindows, 
    FaLinux, 
    FaApple, 
    FaHammer, 
    FaFileDownload, 
    FaCog, 
    FaNetworkWired,
    FaRocket,
    FaExclamationTriangle,
    FaCheckCircle,
    FaFolder
} from "react-icons/fa";
import { notifications } from '@mantine/notifications';
import MainLayout from "../components/MainLayout";
import { getBuildOptions, buildImplant } from "../modules/nimplant";

interface ImplantType {
    id: string;
    name: string;
    description: string;
    icon: string;
    architectures: Architecture[];
}

interface Architecture {
    id: string;
    name: string;
    description: string;
}

interface BuildOptions {
    implant_types: ImplantType[];
}

interface RelayConfig {
    enabled: boolean;
    address: string;
    port: string;
    fast_mode: boolean;
}

function ImplantBuilderPage() {
    const theme = useMantineTheme();
    const { buildOptions, buildOptionsLoading, buildOptionsError } = getBuildOptions();
    
    const [selectedImplantType, setSelectedImplantType] = useState<string | null>(null);
    const [buildModalOpen, setBuildModalOpen] = useState(false);
    const [selectedArchitecture, setSelectedArchitecture] = useState<string>("");
    const [isDebug, setIsDebug] = useState(false);
    const [workspace, setWorkspace] = useState<string>("");
    
    // Relay configuration
    const [relayConfig, setRelayConfig] = useState<RelayConfig>({
        enabled: false,
        address: "",
        port: "9999",
        fast_mode: false
    });
    
    // Build status
    const [isBuilding, setIsBuilding] = useState(false);
    const [buildResult, setBuildResult] = useState<any>(null);
    const [buildId, setBuildId] = useState<string | null>(null);
    const [buildStatus, setBuildStatus] = useState<any>(null);
    const [error, setError] = useState<string | null>(null);
    
    // Poll for build status when buildId is available
    useEffect(() => {
        if (!buildId) return;
        
        const checkBuildStatus = async () => {
            try {
                const token = localStorage.getItem('auth_token');
                
                const response = await fetch(`/api/build/status/${buildId}`, {
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
    
    const handleImplantTypeSelect = (implantType: string) => {
        setSelectedImplantType(implantType);
        setBuildModalOpen(true);
        
        // Set default architecture based on implant type
        if (implantType === "windows") {
            setSelectedArchitecture("x64");
        } else if (implantType === "multi_os") {
            setSelectedArchitecture("all");
        }
        
        // Reset other states
        setIsBuilding(false);
        setBuildResult(null);
        setBuildStatus(null);
        setBuildId(null);
        setError(null);
    };
    
    const handleBuild = async () => {
        setIsBuilding(true);
        setError(null);
        setBuildResult(null);
        setBuildStatus(null);
        
        try {
            const implantTypeData = buildOptions?.implant_types.find(t => t.id === selectedImplantType);
            if (!implantTypeData) {
                throw new Error("Invalid implant type selected");
            }
            
            buildImplant(
                isDebug,
                (data) => {
                    if (data && data.build_id) {
                        setBuildId(data.build_id);
                    } else {
                        setIsBuilding(false);
                        setError("Failed to start build process");
                    }
                },
                workspace || null,
                selectedImplantType!,
                selectedArchitecture || null,
                relayConfig.enabled ? relayConfig : null
            );
        } catch (err) {
            console.error("Error starting build:", err);
            setIsBuilding(false);
            setError("Failed to start build process. Check the connection to the server.");
        }
    };
    
    const handleDownload = () => {
        if (buildResult && buildResult.download_url) {
            const token = localStorage.getItem('auth_token');
            const downloadUrl = `${buildResult.download_url}?token=${token}`;
            window.open(downloadUrl, '_blank');
        }
    };
    
    const handleClose = () => {
        setBuildModalOpen(false);
        setSelectedImplantType(null);
        setIsBuilding(false);
        setBuildResult(null);
        setBuildStatus(null);
        setBuildId(null);
        setError(null);
        setSelectedArchitecture("");
        setWorkspace("");
        setRelayConfig({
            enabled: false,
            address: "",
            port: "9999",
            fast_mode: false
        });
    };
    
    const getProgressInfo = () => {
        if (!buildStatus) return "Starting compilation...";
        return buildStatus.progress || "Compiling implants...";
    };
    
    const getIconForImplantType = (iconType: string) => {
        switch (iconType) {
            case "windows":
                return <FaWindows size={48} color={theme.colors.blue[6]} />;
            case "multi_platform":
                return (
                    <Group gap={8}>
                        <FaLinux size={24} color={theme.colors.orange[6]} />
                        <FaApple size={24} color={theme.colors.gray[7]} />
                    </Group>
                );
            default:
                return <FaCog size={48} color={theme.colors.gray[6]} />;
        }
    };
    
    if (buildOptionsLoading) {
        return (
            <MainLayout>
                <Container size="xl" py="xl">
                    <Group justify="center">
                        <Loader size="lg" />
                        <Text>Loading build options...</Text>
                    </Group>
                </Container>
            </MainLayout>
        );
    }
    
    if (buildOptionsError) {
        return (
            <MainLayout>
                <Container size="xl" py="xl">
                    <Alert color="red" title="Error" icon={<FaExclamationTriangle />}>
                        Failed to load build options. Please check your connection to the server.
                    </Alert>
                </Container>
            </MainLayout>
        );
    }
    
    const selectedImplantTypeData = buildOptions?.implant_types.find(t => t.id === selectedImplantType);
    
    return (
        <MainLayout>
            <Container size="xl" py="xl">
                <Stack>
                    <div>
                        <Title order={2} mb="md">Build Implants</Title>
                        <Text color="dimmed" size="lg">
                            Choose the type of implant to build for your target environment
                        </Text>
                    </div>
                    
                    <Grid>
                        {buildOptions?.implant_types.map((implantType) => (
                            <Grid.Col key={implantType.id} span={{ base: 12, md: 6 }}>
                                <Card
                                    shadow="md"
                                    padding="xl"
                                    radius="md"
                                    style={{
                                        cursor: "pointer",
                                        transition: "all 0.3s ease",
                                        border: `2px solid ${theme.colors.gray[2]}`,
                                    }}
                                    styles={{
                                        root: {
                                            '&:hover': {
                                                transform: 'translateY(-4px)',
                                                boxShadow: theme.shadows.lg,
                                                borderColor: theme.colors.blue[4]
                                            }
                                        }
                                    }}
                                    onClick={() => handleImplantTypeSelect(implantType.id)}
                                >
                                    <Stack align="center" gap="md">
                                        <ThemeIcon 
                                            size={80} 
                                            radius="xl" 
                                            variant="light"
                                            color={implantType.id === "windows" ? "blue" : "orange"}
                                        >
                                            {getIconForImplantType(implantType.icon)}
                                        </ThemeIcon>
                                        
                                        <div style={{ textAlign: "center" }}>
                                            <Title order={3} mb="xs">{implantType.name}</Title>
                                            <Text color="dimmed" size="sm">
                                                {implantType.description}
                                            </Text>
                                        </div>
                                        
                                        <Badge 
                                            color={implantType.id === "windows" ? "blue" : "orange"}
                                            variant="light"
                                            size="lg"
                                        >
                                            {implantType.architectures.length} Architecture{implantType.architectures.length !== 1 ? 's' : ''}
                                        </Badge>
                                        
                                        <Button
                                            fullWidth
                                            leftSection={<FaHammer />}
                                            color={implantType.id === "windows" ? "blue" : "orange"}
                                            size="md"
                                            radius="md"
                                        >
                                            Build {implantType.name}
                                        </Button>
                                    </Stack>
                                </Card>
                            </Grid.Col>
                        ))}
                    </Grid>
                </Stack>
            </Container>
            
            {/* Build Configuration Modal */}
            <Modal
                opened={buildModalOpen}
                onClose={handleClose}
                title={
                    <Title order={4}>
                        Build {selectedImplantTypeData?.name} Implant
                    </Title>
                }
                size="lg"
                centered
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
                        Configure your {selectedImplantTypeData?.name.toLowerCase()} implant build options
                    </Text>
                    
                    {/* Architecture Selection */}
                    <Paper p="md" radius="md" withBorder>
                        <Stack>
                            <Title order={5}>Architecture</Title>
                            <Select
                                placeholder="Select target architecture"
                                data={selectedImplantTypeData?.architectures.map(arch => ({
                                    value: arch.id,
                                    label: arch.name,
                                    description: arch.description
                                })) || []}
                                value={selectedArchitecture}
                                onChange={(value) => setSelectedArchitecture(value || "")}
                                disabled={isBuilding || buildResult !== null}
                                searchable
                                clearable={selectedImplantType === "multi_os"}
                            />
                        </Stack>
                    </Paper>
                    
                    {/* Debug Mode */}
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
                                size="md"
                                color={isDebug ? "orange" : "dark"}
                            />
                        </Stack>
                    </Paper>
                    
                    {/* Relay Configuration - Only for Multi-OS */}
                    {selectedImplantType === "multi_os" && (
                        <Paper p="md" radius="md" withBorder>
                            <Stack>
                                <Group justify="apart">
                                    <Title order={5}>Relay Configuration</Title>
                                    <Badge color="blue" variant="light">Multi-OS Only</Badge>
                                </Group>
                                
                                <Switch
                                    checked={relayConfig.enabled}
                                    onChange={(e) => setRelayConfig(prev => ({ ...prev, enabled: e.currentTarget.checked }))}
                                    label={
                                        <Group>
                                            <FaNetworkWired size={16} />
                                            <Text>Enable Relay Mode</Text>
                                        </Group>
                                    }
                                    description="Configure implant as a relay client"
                                    disabled={isBuilding || buildResult !== null}
                                    size="md"
                                    color="blue"
                                />
                                
                                {relayConfig.enabled && (
                                    <Stack gap="sm" pl="md">
                                        <Group grow>
                                            <TextInput
                                                label="Relay Server Address"
                                                placeholder="192.168.1.100"
                                                value={relayConfig.address}
                                                onChange={(e) => setRelayConfig(prev => ({ ...prev, address: e.currentTarget.value }))}
                                                disabled={isBuilding || buildResult !== null}
                                            />
                                            <TextInput
                                                label="Relay Server Port"
                                                placeholder="9999"
                                                value={relayConfig.port}
                                                onChange={(e) => setRelayConfig(prev => ({ ...prev, port: e.currentTarget.value }))}
                                                disabled={isBuilding || buildResult !== null}
                                            />
                                        </Group>
                                        
                                        <Checkbox
                                            checked={relayConfig.fast_mode}
                                            onChange={(e) => setRelayConfig(prev => ({ ...prev, fast_mode: e.currentTarget.checked }))}
                                            label={
                                                <Group>
                                                    <FaRocket size={14} />
                                                    <Text size="sm">Fast Mode (0.5-1s intervals)</Text>
                                                </Group>
                                            }
                                            description="Enable faster communication intervals for relay clients"
                                            disabled={isBuilding || buildResult !== null}
                                        />
                                    </Stack>
                                )}
                            </Stack>
                        </Paper>
                    )}
                    
                    {/* Workspace */}
                    <Paper p="md" radius="md" withBorder>
                        <Stack>
                            <Group justify="apart">
                                <Title order={5}>Workspace</Title>
                                <Badge color="gray" variant="light">Optional</Badge>
                            </Group>
                            <TextInput
                                placeholder="Workspace UUID (optional)"
                                label="Assign to workspace"
                                leftSection={<FaFolder size={14} />}
                                value={workspace}
                                onChange={(e) => setWorkspace(e.currentTarget.value)}
                                disabled={isBuilding || buildResult !== null}
                            />
                        </Stack>
                    </Paper>
                    
                    {/* Error Display */}
                    {error && (
                        <Alert color="red" title="Error" icon={<FaExclamationTriangle />} radius="md">
                            {error}
                        </Alert>
                    )}
                    
                    {/* Build Progress */}
                    {isBuilding && (
                        <Paper p="md" radius="md" withBorder shadow="sm">
                            <Stack>
                                <Group justify="center">
                                    <Loader size="sm" color={isDebug ? "orange" : "dark"} />
                                    <Text fw={500} ta="center">{getProgressInfo()}</Text>
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
                                <Text size="xs" color="dimmed" ta="center">
                                    This process may take several minutes...
                                </Text>
                            </Stack>
                        </Paper>
                    )}
                    
                    {/* Build Success */}
                    {buildResult && buildResult.status === 'completed' && (
                        <Paper p="md" radius="md" withBorder shadow="sm">
                            <Stack>
                                <Group>
                                    <ThemeIcon color={isDebug ? "orange" : "dark"} size="lg" radius="xl">
                                        <FaCheckCircle />
                                    </ThemeIcon>
                                    <Title order={5} style={{ color: isDebug ? theme.colors.orange[7] : theme.colors.dark[7] }}>
                                        Compilation Successful
                                    </Title>
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
                    
                    {/* Action Buttons */}
                    <Group justify="center">
                        {!buildResult ? (
                            <Button
                                onClick={handleBuild}
                                leftSection={<FaHammer />}
                                disabled={isBuilding || !selectedArchitecture}
                                color={isDebug ? "orange" : "dark"}
                                size="md"
                                fullWidth
                                radius="md"
                            >
                                {isBuilding ? "Compiling..." : `Build ${selectedImplantTypeData?.name}`}
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
                            >
                                Download Implants
                            </Button>
                        )}
                    </Group>
                </Stack>
            </Modal>
        </MainLayout>
    );
}

export default ImplantBuilderPage; 