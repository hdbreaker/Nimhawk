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
    Box,
    Flex,
    rem
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
    FaFolder,
    FaArrowRight,
    FaMicrochip,
    FaGlobe
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
    const typedBuildOptions = buildOptions as BuildOptions;
    
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
            const implantTypeData = typedBuildOptions?.implant_types.find((t: ImplantType) => t.id === selectedImplantType);
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
            <div style={{ 
                position: 'fixed',
                top: '0',
                left: '80px',
                right: '0',
                bottom: '0',
                paddingTop: '80px',
                paddingBottom: '16px',
                paddingLeft: '16px',
                paddingRight: '16px',
                overflowY: 'auto',
                backgroundColor: '#f8f9fa'
            }}>
                <Group justify="center">
                    <Loader size="lg" />
                    <Text>Loading build options...</Text>
                </Group>
            </div>
        );
    }
    
    if (buildOptionsError) {
        return (
            <div style={{ 
                position: 'fixed',
                top: '0',
                left: '80px',
                right: '0',
                bottom: '0',
                paddingTop: '80px',
                paddingBottom: '16px',
                paddingLeft: '16px',
                paddingRight: '16px',
                overflowY: 'auto',
                backgroundColor: '#f8f9fa'
            }}>
                <Alert color="red" title="Error" icon={<FaExclamationTriangle />}>
                    Failed to load build options. Please check your connection to the server.
                </Alert>
            </div>
        );
    }
    
    const selectedImplantTypeData = typedBuildOptions?.implant_types.find((t: ImplantType) => t.id === selectedImplantType);
    
    return (
        <div style={{ 
            position: 'fixed',
            top: '0',
            left: '80px',
            right: '0',
            bottom: '0',
            paddingTop: '80px',
            paddingBottom: '16px',
            paddingLeft: '16px',
            paddingRight: '16px',
            overflowY: 'auto',
            backgroundColor: '#f8f9fa'
        }}>
                <Stack gap="xl">
                    <div>
                        <Title order={2} mb="md">Build Implants</Title>
                        <Text color="dimmed" size="lg">
                            Choose the type of implant to build for your target environment
                        </Text>
                    </div>
                    
                    <Stack gap="lg">
                        {typedBuildOptions?.implant_types.map((implantType: ImplantType) => (
                            <Card
                                key={implantType.id}
                                shadow="sm"
                                padding="xl"
                                radius="lg"
                                withBorder
                                style={{
                                    cursor: "pointer",
                                    transition: "all 0.2s ease",
                                    border: `1px solid ${theme.colors.gray[3]}`,
                                    background: theme.colors.gray[0]
                                }}
                                styles={{
                                    root: {
                                        '&:hover': {
                                            transform: 'translateY(-2px)',
                                            boxShadow: theme.shadows.md,
                                            borderColor: implantType.id === "windows" ? theme.colors.blue[4] : theme.colors.orange[4],
                                            background: theme.white
                                        }
                                    }
                                }}
                                onClick={() => handleImplantTypeSelect(implantType.id)}
                            >
                                <Flex 
                                    align="center" 
                                    justify="space-between" 
                                    gap="xl"
                                    wrap="wrap"
                                    style={{ minHeight: rem(80) }}
                                >
                                    {/* Left section - Icon and content */}
                                    <Flex align="center" gap="xl" style={{ flex: 1, minWidth: rem(300) }}>
                                        <ThemeIcon 
                                            size={70} 
                                            radius="xl" 
                                            variant="light"
                                            color={implantType.id === "windows" ? "blue" : "orange"}
                                            style={{ flexShrink: 0 }}
                                        >
                                            {getIconForImplantType(implantType.icon)}
                                        </ThemeIcon>
                                        
                                        <div style={{ flex: 1 }}>
                                            <Group gap="md" mb="xs">
                                                <Title order={3} style={{ margin: 0 }}>
                                                    {implantType.name}
                                                </Title>
                                                <Badge 
                                                    color={implantType.id === "windows" ? "blue" : "orange"}
                                                    variant="light"
                                                    size="md"
                                                    leftSection={<FaMicrochip size={12} />}
                                                >
                                                    {implantType.architectures.length} Architecture{implantType.architectures.length !== 1 ? 's' : ''}
                                                </Badge>
                                            </Group>
                                            <Text color="dimmed" size="sm" mb="sm">
                                                {implantType.description}
                                            </Text>
                                            
                                            {/* Architecture preview */}
                                            <Group gap="xs">
                                                {implantType.architectures.slice(0, 3).map((arch: Architecture, index: number) => (
                                                    <Badge 
                                                        key={arch.id}
                                                        color="gray" 
                                                        variant="outline" 
                                                        size="xs"
                                                    >
                                                        {arch.name}
                                                    </Badge>
                                                ))}
                                                {implantType.architectures.length > 3 && (
                                                    <Badge color="gray" variant="outline" size="xs">
                                                        +{implantType.architectures.length - 3} more
                                                    </Badge>
                                                )}
                                            </Group>
                                        </div>
                                    </Flex>
                                    
                                    {/* Right section - Action button and features */}
                                    <Flex align="center" gap="lg" style={{ flexShrink: 0 }}>
                                                                {/* Features indicators */}
                                        <Stack gap="xs" align="flex-start" style={{ display: 'flex' }} visibleFrom="sm">
                                            {implantType.id === "windows" && (
                                                <>
                                                    <Group gap="xs">
                                                        <FaCog size={14} color={theme.colors.blue[6]} />
                                                        <Text size="xs" color="dimmed">Full Features</Text>
                                                    </Group>
                                                    <Group gap="xs">
                                                        <FaWindows size={14} color={theme.colors.blue[6]} />
                                                        <Text size="xs" color="dimmed">Windows Only</Text>
                                                    </Group>
                                                </>
                                            )}
                                            {implantType.id === "multi_os" && (
                                                <>
                                                    <Group gap="xs">
                                                        <FaGlobe size={14} color={theme.colors.orange[6]} />
                                                        <Text size="xs" color="dimmed">Cross Platform</Text>
                                                    </Group>
                                                    <Group gap="xs">
                                                        <FaNetworkWired size={14} color={theme.colors.orange[6]} />
                                                        <Text size="xs" color="dimmed">Relay Support</Text>
                                                    </Group>
                                                </>
                                            )}
                                        </Stack>
                                        
                                        <Button
                                            leftSection={<FaHammer size={16} />}
                                            rightSection={<FaArrowRight size={14} />}
                                            color={implantType.id === "windows" ? "blue" : "orange"}
                                            size="md"
                                            radius="md"
                                            variant="filled"
                                            style={{ minWidth: rem(160) }}
                                        >
                                            Build Now
                                        </Button>
                                    </Flex>
                                </Flex>
                            </Card>
                        ))}
                    </Stack>
                </Stack>
            
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
                                    color="orange"
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
        </div>
    );
}

export default ImplantBuilderPage; 