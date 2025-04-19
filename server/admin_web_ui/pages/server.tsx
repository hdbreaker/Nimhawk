import { restoreConnectionError, showConnectionError } from '../modules/nimplant'
import { FaInfoCircle, FaServer, FaTerminal, FaSkull, FaChevronDown, FaChevronUp, FaHammer, FaSync } from 'react-icons/fa'
import { Tabs, Text, Box, Group, Stack, Button, Paper, useMantineTheme, Divider, Collapse, Grid } from '@mantine/core'
import { useEffect, useState, useRef, useCallback } from 'react'
import { getServerInfo, endpoints } from '../modules/nimplant'
import ExitServerModal from '../components/modals/ExitServer'
import BuildImplantModal from '../components/modals/BuildImplant'
import type { NextPage } from 'next'
import * as nimplantModule from '../modules/nimplant'
import { getServerEndpoint, getImplantEndpoint, SERVER_BASE_URL } from '../config';
import { api } from '../modules/apiFetcher';
import useSWR from 'swr';

// Define server info type
interface ServerConfig {
  managementIp: string;
  managementPort: number;
  listenerType: string;
  listenerIp: string;
  listenerHost?: string;
  listenerPort: number;
  registerPath: string;
  taskPath: string;
  resultPath: string;
  reconnectPath: string;
  riskyMode: boolean;
  sleepTime: number;
  sleepJitter: number;
  killDate: string;
  userAgent: string;
  httpAllowCommunicationKey: string;
  maxReconnectionAttemps?: number;
  implant?: {
    httpAllowCommunicationKey?: string;
    userAgent?: string;
    sleepTime?: number;
    sleepJitter?: number;
    killDate?: string;
    maxReconnectionAttemps?: number;
  };
  listener?: {
    registerPath?: string;
    taskPath?: string;
    resultPath?: string;
    reconnectPath?: string;
    type?: string;
    ip?: string;
    port?: number;
  };
  implants_server?: {
    registerPath?: string;
    taskPath?: string;
    resultPath?: string;
    reconnectPath?: string;
    type?: string;
    ip?: string;
    port?: number;
    maxReconnectionAttemps?: number;
  };
  server?: {
    ip?: string;
    port?: number;
  };
}

interface ServerInfo {
  guid: string;
  name: string;
  xorKey: string;
  config: ServerConfig;
}

const ServerInfo: NextPage = () => { 
  const adminEndpoint = getServerEndpoint();
  const implantEndpoint = getImplantEndpoint();

  console.log("Admin Endpoint:", adminEndpoint);
  console.log("Implant Endpoint:", implantEndpoint);
  
  const [exitModalOpen, setExitModalOpen] = useState(false);
  const [buildModalOpen, setBuildModalOpen] = useState(false);
  
  // Manage server info state manually
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [serverInfoLoading, setServerInfoLoading] = useState(true);
  const [serverInfoError, setServerInfoError] = useState<Error | null>(null);
  
  // States for server connection status and endpoints
  const [adminStatus, setAdminStatus] = useState('disconnected');
  const [implantStatus, setImplantStatus] = useState('disconnected');
  const [serverStatus, setServerStatus] = useState('disconnected');
  const [lastImplantSuccessCheck, setLastImplantSuccessCheck] = useState(0);
  const [failedImplantChecks, setFailedImplantChecks] = useState(0);
  
  // State to track the last verification time (moved here to fix linting error)
  const [lastCheckTime, setLastCheckTime] = useState(0);
  const [lastCheckSource, setLastCheckSource] = useState('initial');
  
  // Function to fetch server info using axios
  const fetchServerInfo = async () => {
    setServerInfoLoading(true);
    setServerInfoError(null);
    
    try {
      console.log('Attempting to fetch server information');
      
      // Use the api.get function from our centralized module
      const data = await api.get(`${SERVER_BASE_URL}/api/server`);
      
      console.log('Server info received:', data);
      setServerInfo(data);
    } catch (error) {
      console.error('Error fetching server info:', error);
      setServerInfoError(error instanceof Error ? error : new Error(String(error)));
    } finally {
      setServerInfoLoading(false);
    }
  };
  
  // Fetch server info on mount
  useEffect(() => {
    fetchServerInfo();
  }, []);
  
  // Add refresh button to page
  const handleRefresh = () => {
    fetchServerInfo();
  };
  
  const theme = useMantineTheme();
  
  // States to control collapsible sections
  const [connectionOpen, setConnectionOpen] = useState(true);
  const [headersOpen, setHeadersOpen] = useState(true);
  const [configOpen, setConfigOpen] = useState(true);
  const [pathsOpen, setPathsOpen] = useState(true);
  
  // States and refs for interactive console
  const [command, setCommand] = useState('');
  const [forceRefresh, setForceRefresh] = useState(false);
  const bottomRef = useRef(null);

  // Access endpoints through the complete module
  const { endpoints } = nimplantModule;

  // Function to start checks and update the overall status
  const checkServerStatus = useCallback(async () => {
    console.log("🔄 Starting full verification");
    
    //  Avoid multiple checks in a short time in manual calls, 
    // but allow periodic checks
    const now = Date.now();
    let shouldSkip = false;
    
    // Only apply the restriction if it's a manual call and not the periodic check
    if (now - lastCheckTime < 60000 && lastCheckSource === 'manual') { 
      console.log("⏱️ Recent verification, skipping to avoid excessive traffic");
      shouldSkip = true;
    }
    
    // If we are in a periodic check, mark it
    if (lastCheckSource === 'periodic') {
      console.log("⏱️ Periodic server check - will continue regardless of time");
      shouldSkip = false;
    }
    
    if (shouldSkip) return;
    
    // Update timestamp
    setLastCheckTime(now);
    
    // Local variables to follow the status of each endpoint
    let adminConnected = false;
    let implantConnected = false;
    
    try {
      // Verify Admin API
      try {
        console.log(`🔍 Verifying Admin API: ${adminEndpoint}`);
        
        // Use the api.get function
        await api.get(adminEndpoint);
        console.log("✅ Connection successful to Admin API");
        adminConnected = true;
      } catch (error) {
        console.error('❌ Error checking Admin API:', error);
        adminConnected = false;
      }
      
      // Verify Implant API
      try {
        // Determine endpoint
        console.log(`🔍 Verifying Implant API: ${implantEndpoint}`);
        
        if (implantEndpoint !== "") {
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 3000);
          
          // No authentication needed for implant API
          const response = await fetch(implantEndpoint, {
            method: 'GET',
            headers: { 'Content-Type': 'application/json' },
            signal: controller.signal
          });
        
          clearTimeout(timeoutId);
        
          if (response.ok) {
            console.log(`🟢 Implant API responded with status: ${response.status}`);
            setLastImplantSuccessCheck(Date.now());
            setFailedImplantChecks(0);
            implantConnected = true;
          } else {
            console.warn(`⚠️ Error in Implant API response: ${response.status}`);
            implantConnected = false;
          }
        }
      } catch (error) {
        console.error('❌ Error connecting to Implant API:', error);
        implantConnected = false;
      }
      
      // Update all states at once
      console.log(`Verification results - Admin: ${adminConnected ? 'connected' : 'disconnected'}, Implant: ${implantConnected ? 'connected' : 'disconnected'}`);
      
      // Update individual states
      setAdminStatus(adminConnected ? 'connected' : 'disconnected');
      setImplantStatus(implantConnected ? 'connected' : 'disconnected');
      
      // Update general status
      if (adminConnected && implantConnected) {
        console.log("✅ Both endpoints connected - Server CONNECTED");
        setServerStatus('connected');
      } else {
        console.log("⚠️ At least one endpoint disconnected - Server DISCONNECTED");
        console.log(`  - Admin API: ${adminConnected ? 'connected' : 'disconnected'}`);
        console.log(`  - Implant API: ${implantConnected ? 'connected' : 'disconnected'}`);
        setServerStatus('disconnected');
      }
    } catch (error) {
      console.error("❌ General error during verification:", error);
      setAdminStatus('disconnected');
      setImplantStatus('disconnected');
      setServerStatus('disconnected');
    }
  }, [adminEndpoint, implantEndpoint, lastCheckTime, lastCheckSource]);

  // Check server status periodically
  useEffect(() => {
    console.log("⏱ Setting up periodic server status checks");
    
    // Initial check
    setLastCheckSource('initial');
    checkServerStatus();
    
    // Verify every 1 minute as required
    const checkInterval = setInterval(() => {
      setLastCheckSource('periodic');
      checkServerStatus();
    }, 60000); // 1 minute
    
    // Cleanup
    return () => {
      console.log("🧹 Cleaning up periodic checks");
      clearInterval(checkInterval);
    };
  }, [checkServerStatus]);

  // Modified to avoid excessive verifications when serverInfo changes
  useEffect(() => {
    if (serverInfo && serverInfo.config) {
      console.log("🔄 Server data updated:", serverInfo.name);
      
      // Set the source as manual for this check
      setLastCheckSource('manual');
      checkServerStatus();
    }
  }, [serverInfo, checkServerStatus]);

  // Define interface for CollapsibleHeader props
  interface CollapsibleHeaderProps {
    title: string;
    isOpen: boolean;
    toggleOpen: () => void;
  }

  // Component for section headers with more space
  const CollapsibleHeader = ({ title, isOpen, toggleOpen }: CollapsibleHeaderProps) => (
    <Group 
      justify="apart" 
      mb="md" 
      style={{ 
        cursor: 'pointer',
        marginTop: '10px'  // Added top margin
      }}
      onClick={toggleOpen}
    >
      <Text size="sm" fw={600} color="#1A1A1A" style={{ textTransform: 'uppercase', letterSpacing: '1px' }}>
        {title}
      </Text>
      {isOpen ? <FaChevronUp size={14} /> : <FaChevronDown size={14} />}
    </Group>
  );

  // Component for a data row (with table style)
  interface DataRowProps {
    label: string;
    value: string;
    isCode?: boolean;
    isAlt?: boolean;
  }

  const DataRow = ({ label, value, isCode = false, isAlt = false }: DataRowProps) => (
    <tr style={{ 
      backgroundColor: isAlt ? '#FCFCFC' : 'white',
    }}>
      <td style={{ 
        padding: '0.8rem 1.5rem', 
        borderBottom: '1px solid #F1F3F5',
        width: '30%'
      }}>
        <Text size="sm" fw={600} color="#212529"><b>{label}</b></Text>
      </td>
      <td style={{ 
        padding: '0.8rem 1.5rem', 
        borderBottom: '1px solid #F1F3F5',
        width: '70%'
      }}>
        <Text fw={500} color="#1A1A1A" style={{ 
          fontFamily: isCode ? 'monospace' : 'inherit',
          fontSize: isCode ? '0.85rem' : 'inherit',
          wordBreak: 'break-word'
        }}>
          {value}
        </Text>
      </td>
    </tr>
  );

  // Component for general status indicator
  const StatusIndicator = ({ status }: { status: string }) => {
    console.log(`🔴🟢 Rendering StatusIndicator with status: ${status}`);
    
    return (
      <tr style={{ backgroundColor: 'white' }}>
        <td style={{ 
          padding: '0.8rem 1.5rem', 
          borderBottom: '1px solid #F1F3F5',
          width: '30%'
        }}>
          <Text size="sm" fw={600} color="#212529"><b>Status</b></Text>
        </td>
        <td style={{ 
          padding: '0.8rem 1.5rem', 
          borderBottom: '1px solid #F1F3F5',
          width: '70%'
        }}>
          <Group gap="xs">
            <Box
              style={{
                width: '10px',
                height: '10px',
                borderRadius: '50%',
                backgroundColor: status === 'connected' ? '#4CAF50' : '#FF5252',
                display: 'inline-block'
              }}
            />
            <Text fw={500} color={status === 'connected' ? '#4CAF50' : '#FF5252'}>
              {status === 'connected' ? 'Connected' : 'Disconnected'}
            </Text>
          </Group>
        </td>
      </tr>
    );
  };

  // Component for status indicator of a specific endpoint
  interface EndpointStatusIndicatorProps {
    label: string;
    value: string;
    status: string;
    isAlt?: boolean;
  }

  const EndpointStatusIndicator = ({ label, value, status, isAlt = false }: EndpointStatusIndicatorProps) => {
    return (
      <tr style={{ 
        backgroundColor: isAlt ? '#FCFCFC' : 'white',
      }}>
        <td style={{ 
          padding: '0.8rem 1.5rem', 
          borderBottom: '1px solid #F1F3F5',
          width: '30%'
        }}>
          <Text size="sm" fw={600} color="#212529"><b>{label}</b></Text>
        </td>
        <td style={{ 
          padding: '0.8rem 1.5rem', 
          borderBottom: '1px solid #F1F3F5',
          width: '70%'
        }}>
          <Group gap="md" justify="apart">
            <Box
              style={{
                width: '10px',
                height: '10px',
                borderRadius: '50%',
                backgroundColor: status === 'connected' ? '#4CAF50' : '#FF5252',
                display: 'inline-block'
              }}
            />
            <Text fw={500} color="#1A1A1A" style={{ 
              fontFamily: 'monospace',
              fontSize: '0.85rem',
              wordBreak: 'break-word'
            }}>
              {value}
            </Text>
          </Group>
        </td>
      </tr>
    );
  };


  // We only render indicators when we have server information
  const renderEndpointIndicators = () => {
    // If there is no serverInfo, we show only loading indicators
    if (!serverInfo || !serverInfo.config) {
      return (
        <tbody>
          <tr style={{ backgroundColor: 'white' }}>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '30%'
            }}>
              <Text size="sm" fw={600} color="#212529"><b>Status</b></Text>
            </td>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '70%'
            }}>
              <Group gap="xs">
                <Box
                  style={{
                    width: '10px',
                    height: '10px',
                    borderRadius: '50%',
                    backgroundColor: serverInfoLoading ? '#FFC107' : '#FF5252',
                    display: 'inline-block'
                  }}
                />
                <Text fw={500} color={serverInfoLoading ? '#FFC107' : '#FF5252'}>
                  {serverInfoLoading ? 'Loading...' : 'Disconnected'}
                </Text>
              </Group>
            </td>
          </tr>
          <DataRow 
            label="Server GUID" 
            value="Loading..." 
            isCode={true} 
            isAlt={true}
          />
          <tr style={{ backgroundColor: 'white' }}>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '30%'
            }}>
              <Text size="sm" fw={600} color="#212529"><b>Admin API endpoint</b></Text>
            </td>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '70%'
            }}>
              <Text fw={500} color="#1A1A1A" style={{ 
                fontFamily: 'monospace',
                fontSize: '0.85rem',
                wordBreak: 'break-word'
              }}>
                Loading...
              </Text>
            </td>
          </tr>
          <tr style={{ backgroundColor: '#FCFCFC' }}>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '30%'
            }}>
              <Text size="sm" fw={600} color="#212529"><b>Implants API 3ndpoint</b></Text>
            </td>
            <td style={{ 
              padding: '0.8rem 1.5rem', 
              borderBottom: '1px solid #F1F3F5',
              width: '70%'
            }}>
              <Text fw={500} color="#1A1A1A" style={{ 
                fontFamily: 'monospace',
                fontSize: '0.85rem',
                wordBreak: 'break-word'
              }}>
                Loading...
              </Text>
            </td>
          </tr>
        </tbody>
      );
      
    }
    
    // If there is serverInfo, we show all indicators with data
    const config = serverInfo.config;
    const adminApiEndpoint = `http://${config.server?.ip || config.managementIp}:${config.server?.port || config.managementPort}`;
    
    // Fix the construction of implantApiEndpoint to properly use the correct implantCallbackIp property
    const implantApiEndpoint = `${config.implants_server?.type === "HTTPS" || config.listenerType === "HTTPS" ? "https://" : "http://"}${config.implants_server?.ip || config.listenerIp}${
      (config.implants_server?.port || config.listenerPort) && 
      (config.implants_server?.port || config.listenerPort) !== 80 ? 
      `:${config.implants_server?.port || config.listenerPort}` : ''
    }`;
    
    return (
      <tbody>
        <tr style={{ backgroundColor: 'white' }}>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '30%'
          }}>
            <Text size="sm" fw={600} color="#212529"><b>Status</b></Text>
          </td>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '70%'
          }}>
            <Group gap="xs">
              <Box
                style={{
                  width: '10px',
                  height: '10px',
                  borderRadius: '50%',
                  backgroundColor: '#4CAF50',
                  display: 'inline-block'
                }}
              />
              <Text fw={500} color='#4CAF50'>
                Connected
              </Text>
            </Group>
          </td>
        </tr>
        <DataRow 
          label="Server GUID" 
          value={serverInfo.name} 
          isCode={true} 
          isAlt={true}
        />
        <tr style={{ backgroundColor: 'white' }}>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '30%'
          }}>
            <Text size="sm" fw={600} color="#212529"><b>Admin API endpoint</b></Text>
          </td>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '70%'
          }}>
            <Group gap="xs">
              <Box
                style={{
                  width: '10px',
                  height: '10px',
                  borderRadius: '50%',
                  backgroundColor: '#4CAF50',
                  display: 'inline-block'
                }}
              />
              <Text fw={500} color="#1A1A1A" style={{ 
                fontFamily: 'monospace',
                fontSize: '0.85rem',
                wordBreak: 'break-word'
              }}>
                {adminApiEndpoint}
              </Text>
            </Group>
          </td>
        </tr>
        <tr style={{ backgroundColor: '#FCFCFC' }}>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '30%'
          }}>
            <Text size="sm" fw={600} color="#212529"><b>Implants API endpoint</b></Text>
          </td>
          <td style={{ 
            padding: '0.8rem 1.5rem', 
            borderBottom: '1px solid #F1F3F5',
            width: '70%'
          }}>
            <Group gap="xs">
              <Box
                style={{
                  width: '10px',
                  height: '10px',
                  borderRadius: '50%',
                  backgroundColor: '#4CAF50',
                  display: 'inline-block'
                }}
              />
              <Text fw={500} color="#1A1A1A" style={{ 
                fontFamily: 'monospace',
                fontSize: '0.85rem',
                wordBreak: 'break-word'
              }}>
                {implantApiEndpoint}
              </Text>
            </Group>
          </td>
        </tr>
      </tbody>
    );
  };

  return (
    <Box style={{ height: 'calc(100vh - 70px)', position: 'relative' }}>
      <ExitServerModal modalOpen={exitModalOpen} setModalOpen={setExitModalOpen} />
      <BuildImplantModal modalOpen={buildModalOpen} setModalOpen={setBuildModalOpen} />
      
      <Box 
        p="md" 
        style={{ 
          borderBottom: '1px solid #E9ECEF',
          backgroundColor: 'white'
        }}
      >
        <Group justify="apart" align="center">
          <Group gap="md">
            <FaServer size={24} color="#1A1A1A" />
            <Text fw={300} size="xl" style={{ color: '#1A1A1A' }}>Server Information</Text>
          </Group>
          
          <Group>
            {/* Status indicator */}
            <Group gap="xs">
              <Box
                style={{
                  width: '10px',
                  height: '10px',
                  borderRadius: '50%',
                  backgroundColor: serverInfo ? '#4CAF50' : '#FF5252',
                  display: 'inline-block'
                }}
              />
              <Text size="sm" color={serverInfo ? '#4CAF50' : '#FF5252'} fw={500}>
                {serverInfo ? 'Connected' : 'Disconnected'}
              </Text>
            </Group>
            
            {/* Refresh button */}
            <Button
              variant="subtle"
              size="sm"
              onClick={handleRefresh}
              loading={serverInfoLoading}
              leftSection={<FaSync size={14} />}
              style={{ marginLeft: '8px' }}
            >
              Refresh
            </Button>
          </Group>
        </Group>
      </Box>
      
      <Tabs 
        defaultValue="serverinfo" 
        styles={{
          root: {
            height: 'calc(100% - 60px)',
          },
          panel: {
            height: 'calc(100% - 50px)',
            padding: 0
          },
          list: {
            borderBottom: '1px solid #E9ECEF',
            padding: '0 20px'
          },
          tab: {
            fontWeight: 400,
            padding: '15px 20px',
            color: '#495057',
          }
        }}
      >
        <Tabs.List>
          <Tabs.Tab value="serverinfo" leftSection={<FaInfoCircle size={14} />}>Information</Tabs.Tab>
      </Tabs.List>

        <Tabs.Panel value="serverinfo" style={{ padding: '0', overflow: 'auto', height: '100%' }}>
          <Box p="xl">
            <Stack gap={20}>
              {/* Connection Information - Colapsable */}
              <Box style={{ marginBottom: '10px' }}>
                <CollapsibleHeader 
                  title="Server information" 
                  isOpen={connectionOpen} 
                  toggleOpen={() => setConnectionOpen(!connectionOpen)} 
                />
                
                <Collapse in={connectionOpen}>
                  <Paper 
                    shadow="xs"
                    radius="md"
                    style={{ 
                      border: '1px solid #DEE2E6',
                      backgroundColor: 'white',
                      overflow: 'hidden'
                    }}
                  >
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                      {renderEndpointIndicators()}
                    </table>
                  </Paper>
                </Collapse>
              </Box>
              
              {/* Implant Headers - Colapsable */}
              <Box style={{ marginBottom: '10px' }}>
                <CollapsibleHeader 
                  title="Implants headers" 
                  isOpen={headersOpen} 
                  toggleOpen={() => setHeadersOpen(!headersOpen)} 
                />
                
                <Collapse in={headersOpen}>
                  <Paper 
                    shadow="xs"
                    radius="md"
                    style={{ 
                      border: '1px solid #DEE2E6',
                      backgroundColor: 'white',
                      overflow: 'hidden'
                    }}
                  >
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                      <tbody>
                        <DataRow 
                          label="HTTP communication key" 
                          value={serverInfo?.config?.implant?.httpAllowCommunicationKey || serverInfo?.config?.httpAllowCommunicationKey || '-'} 
                          isCode={true} 
                          isAlt={true} 
                        />
                        <DataRow 
                          label="User agent" 
                          value={serverInfo?.config?.implant?.userAgent || serverInfo?.config?.userAgent || '-'} 
                          isCode={true} 
                        />
                      </tbody>
                    </table>
                  </Paper>
                </Collapse>
              </Box>
              
              {/* Implant Communication Paths - Colapsable */}
              <Box style={{ marginBottom: '10px' }}>
                <CollapsibleHeader 
                  title="Implants communication paths" 
                  isOpen={pathsOpen} 
                  toggleOpen={() => setPathsOpen(!pathsOpen)} 
                />
                
                <Collapse in={pathsOpen}>
                  <Paper 
                    shadow="xs"
                    radius="md"
                    style={{ 
                      border: '1px solid #DEE2E6',
                      backgroundColor: 'white',
                      overflow: 'hidden'
                    }}
                  >
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                      <tbody>
                      <DataRow 
                          label="Implant Callback URL" 
                          value={`${serverInfo?.config?.listenerType === "HTTPS" ? "https://" : "http://"}${serverInfo?.config?.implantCallbackIp || 'Loading...'}`} 
                          isCode={true} 
                        />
                        <DataRow 
                          label="Register path" 
                          value={serverInfo?.config?.implants_server?.registerPath || serverInfo?.config?.registerPath || 'Loading...'} 
                          isCode={true} 
                        />
                        <DataRow 
                          label="Task path" 
                          value={serverInfo?.config?.implants_server?.taskPath || serverInfo?.config?.taskPath || 'Loading...'} 
                          isCode={true} 
                          isAlt={true} 
                        />
                        <DataRow 
                          label="Result path" 
                          value={serverInfo?.config?.implants_server?.resultPath || serverInfo?.config?.resultPath || 'Loading...'} 
                          isCode={true} 
                        />
                        <DataRow 
                          label="Reconnect path" 
                          value={serverInfo?.config?.implants_server?.reconnectPath || serverInfo?.config?.reconnectPath || 'Loading...'} 
                          isCode={true} 
                          isAlt={true} 
                        />
                        <DataRow 
                          label="Max reconnection attemps" 
                          value={String(serverInfo?.config?.implant?.maxReconnectionAttemps || serverInfo?.config?.maxReconnectionAttemps || '3')} 
                          isCode={true} 
                          isAlt={true} 
                        />
                      </tbody>
                    </table>
                  </Paper>
                </Collapse>
              </Box>

              {/* Implant Configuration - Colapsable */}
              <Box style={{ marginBottom: '10px' }}>
                <CollapsibleHeader 
                  title="Implants configuration" 
                  isOpen={configOpen} 
                  toggleOpen={() => setConfigOpen(!configOpen)} 
                />
                
                <Collapse in={configOpen}>
                  <Paper 
                    shadow="xs"
                    radius="md"
                    style={{ 
                      border: '1px solid #DEE2E6',
                      backgroundColor: 'white',
                      overflow: 'hidden'
                    }}
                  >
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                      <tbody>
                        <DataRow 
                          label="Sleep interval" 
                          value={serverInfo ? `${serverInfo?.config?.implant?.sleepTime || serverInfo?.config?.sleepTime} seconds` : 'Loading...'} 
                        />
                        <DataRow 
                          label="Jitter" 
                          value={serverInfo ? `${serverInfo?.config?.implant?.sleepJitter || serverInfo?.config?.sleepJitter}%` : 'Loading...'} 
                          isAlt={true} 
                        />
                        <DataRow 
                          label="Kill date" 
                          value={serverInfo?.config?.implant?.killDate || serverInfo?.config?.killDate || '-'} 
                        />
                        <DataRow 
                          label="HTTP XOR Key" 
                          value={serverInfo?.xorKey || '-'} 
                          isCode={true} 
                          isAlt={true} 
                        />
                      </tbody>
                    </table>
                  </Paper>
                </Collapse>
              </Box>

              {/* Action buttons - Static position below the cards */}
              <Box style={{ display: 'flex', justifyContent: 'center', marginTop: '1rem', gap: '1rem' }}>
                <Button
                  onClick={() => setBuildModalOpen(true)}
                  leftSection={<FaHammer size={16} />}
                  variant="filled"
                  color="dark"
                  size="md"
                  styles={{
                    root: {
                      fontWeight: 500,
                      transition: 'all 0.3s ease',
                      padding: '0 1.5rem',
                      '&:hover': {
                        transform: 'translateY(-1px)'
                      }
                    }
                  }}
                >
                  Build Implants
                </Button>
              
                <Button
                  onClick={() => setExitModalOpen(true)}
                  leftSection={<FaSkull size={16} />}
                  variant="subtle"
                  color="red"
                  size="md"
                  styles={{
                    root: {
                      fontWeight: 500,
                      transition: 'all 0.3s ease',
                      padding: '0 1.5rem',
                      '&:hover': {
                        backgroundColor: 'rgba(225, 45, 45, 0.15)',
                        transform: 'translateY(-1px)'
                      }
                    }
                  }}
                >
                  Kill Server
                </Button>
              </Box>
            </Stack>
          </Box>
      </Tabs.Panel>
    </Tabs>
    </Box>
  )
}

export default ServerInfo