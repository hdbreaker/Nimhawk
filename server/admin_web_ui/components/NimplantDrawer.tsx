import { Drawer, Tabs, Box, Text, Group, Badge, ThemeIcon, Loader, Stack, Card, Grid, Button, Paper, Modal, TextInput, SimpleGrid } from '@mantine/core';
import { FaTerminal, FaInfoCircle, FaNetworkWired, FaHistory, FaCalendarAlt, FaExchangeAlt, FaClock, FaSkull, FaTrash, FaDownload, FaLink, FaUnlink, FaCloud, FaFingerprint, FaAngleRight } from 'react-icons/fa';
import Console from './Console';
import { submitCommand, formatBytes, timeSince, nimplantExit, deleteNimplant, registerTimeUpdateListener } from '../modules/nimplant';
import { useViewportSize } from '@mantine/hooks';
import { useState, useEffect, useCallback, memo, useMemo } from 'react';
import { endpoints } from '../modules/nimplant';
import useSWR, { mutate } from 'swr';
import { swrFetcher, api } from '../modules/apiFetcher';
import { parse } from 'date-fns';
import ImplantDownloadList from './ImplantDownloadList';
import ImplantFileTransfersList from './ImplantFileTransfersList';
import classes from '../styles/liststyles.module.css';
import { useRouter } from 'next/router';
import type Types from '../modules/nimplant.d'
import { notifications } from '@mantine/notifications';

// Interface for file transfers
interface FileTransfer {
  id: number;
  nimplantGuid: string;
  filename: string;
  size: number;
  operation_type: string;
  timestamp: string;
  hostname?: string;
  username?: string;
}

// Helper function to format large numbers in a compact way
const formatCompactNumber = (num: number): string => {
  if (num < 1000) {
    return num.toString();
  } else if (num < 1000000) {
    return (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
  } else {
    return (num / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
  }
};

// Define interface for nimplant info data
interface NimplantInfo {
  active?: boolean;
  command_count?: number;
  checkin_count?: number;
  data_transferred?: number;
  pname?: string;
  pid?: string | number;
  username?: string;
  osBuild?: string;
  hostname?: string;
  ipAddrExt?: string;
  ipAddrInt?: string;
  sleepTime?: number;
  sleepJitter?: number;
  firstCheckin?: string;
  lastCheckin?: string;
  late?: boolean;
  disconnected?: boolean;
  workspace_name?: string;
  workspace_uuid?: string;
}

interface NimplantDrawerProps {
  opened: boolean;
  onClose: () => void;
  guid: string;
  onKilled?: () => void; // Optional function to notify when an implant is killed
}

// Inner component that handles data and UI
const NimplantContent = memo(({ guid, onClose, opened, onKilled }: { guid: string, onClose: () => void, opened: boolean, onKilled?: () => void }) => {
  // React hooks - keep the same order always
  const [activeTab, setActiveTab] = useState<string>('console');
  const { width } = useViewportSize();
  const [isRefreshing, setIsRefreshing] = useState(false);
  // Modal state for kill implant confirmation
  const [killModalOpen, setKillModalOpen] = useState(false);
  // Modal state for showing killing process
  const [killingModalOpen, setKillingModalOpen] = useState(false);
  
  // State to store Last Seen text and update it every 15 seconds
  const [lastSeenText, setLastSeenText] = useState<string>('');
  
  // SWR hooks - Only fetch if drawer is open
  const [currentGuid, setCurrentGuid] = useState(guid);
  const infoResult = useSWR<NimplantInfo>(
    opened ? endpoints.nimplantInfo(currentGuid) : null,
    swrFetcher,
    { 
      refreshInterval: opened ? 5000 : 0,
      revalidateOnFocus: true,
      revalidateOnMount: true,
      dedupingInterval: 1000, // Reduced to allow more frequent updates
      onSuccess: (data) => {
        console.log(`SWR Success - Implant #${currentGuid} data:`, data);
        // Don't update lastSeenText here, it will be handled by the useEffect
      },
      onError: (error) => {
        console.error(`SWR Error - Failed to fetch implant #${currentGuid} data:`, error);
      }
    }
  );
  
  // State to control how many history lines to request
  const [historyLimit, setHistoryLimit] = useState(50);
  
  // State to control if auto-refresh should be enabled
  const [autoRefresh, setAutoRefresh] = useState(true);
  
  // State for delete modal
  const [deleteModalOpen, setDeleteModalOpen] = useState(false);
  
  const consoleResult = useSWR(
    opened ? endpoints.nimplantConsole(currentGuid, historyLimit) : null,
    swrFetcher,
    { 
      refreshInterval: opened && autoRefresh ? 1000 : 0,
      revalidateOnFocus: opened && autoRefresh
    }
  );
  
  // Function to update history limit from child component
  const updateHistoryLimit = useCallback((newLimit: number, disableRefresh: boolean = false) => {
    setHistoryLimit(newLimit);
    if (disableRefresh) {
      // Temporarily disable auto-refresh to prevent the load from being replaced
      setAutoRefresh(false);
      // Reactivate after 5 seconds
      setTimeout(() => setAutoRefresh(true), 5000);
    }
  }, []);
  
  // Extract data with proper typing
  const nimplantInfo: NimplantInfo = infoResult.data || {};
  const nimplantConsole = consoleResult.data || [];
  
  // Debugging to see implant data
  useEffect(() => {
    if (infoResult.data) {
      console.log(`Implant #${currentGuid} data:`, infoResult.data);
      console.log(`Active: ${infoResult.data.active}`, 
                 `Late: ${infoResult.data.late}`, 
                 `Disconnected: ${infoResult.data.disconnected}`);
    }
  }, [infoResult.data, currentGuid]);
  
  // Replace the current useEffect for time updates with this one
  useEffect(() => {
    // Only update if the drawer is open and we have data
    if (!opened || !nimplantInfo) return;
    
    // Debug info to check raw value
    console.log(`[${currentGuid}] Raw lastCheckin value:`, nimplantInfo.lastCheckin);
    
    // If the date is undefined or null, use status-based values
    if (!nimplantInfo.lastCheckin) {
      console.log(`[${currentGuid}] No lastCheckin value available`);
      
      if (nimplantInfo.active) {
        if (nimplantInfo.disconnected) {
          setLastSeenText('more than 5 minutes ago');
        } else if (nimplantInfo.late) {
          setLastSeenText('about 5 minutes ago');
        } else {
          setLastSeenText('less than 1 minute ago');
        }
      } else {
        setLastSeenText('Unknown');
      }
      return;
    }
    
    // If the date contains a pipe, extract only the first part
    let dateToProcess = nimplantInfo.lastCheckin;
    if (dateToProcess.includes('|')) {
      dateToProcess = dateToProcess.split('|')[0];
      console.log(`[${currentGuid}] Using first part:`, dateToProcess);
    }
    
    try {
      // Parse the date manually - Format: DD/MM/YYYY HH:MM:SS
      if (dateToProcess.match(/^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}:\d{2}$/)) {
        const [datePart, timePart] = dateToProcess.split(' ');
        const [day, month, year] = datePart.split('/').map(Number);
        const [hours, minutes, secs] = timePart.split(':').map(Number);
        
        // Create date object (month is 0-indexed in JavaScript)
        const dateObj = new Date(year, month - 1, day, hours, minutes, secs);
        console.log(`[${currentGuid}] Parsed date:`, dateObj);
        
        // Calculate time difference manually
        const now = new Date();
        const diffMs = now.getTime() - dateObj.getTime();
        
        // For future dates, just show "just now" for active implants
        if (diffMs < 0) {
          console.log(`[${currentGuid}] Date is in the future by ${-diffMs}ms`);
          setLastSeenText(nimplantInfo.active ? 'just now' : 'Unknown');
          return;
        }
        
        // Calculate human-readable time difference manually
        const totalSeconds = Math.floor(diffMs / 1000);
        const totalMinutes = Math.floor(totalSeconds / 60);
        const totalHours = Math.floor(totalMinutes / 60);
        const days = Math.floor(totalHours / 24);
        
        let timeString;
        
        if (days > 0) {
          timeString = days === 1 ? '1 day ago' : `${days} days ago`;
        } else if (totalHours > 0) {
          timeString = totalHours === 1 ? '1 hour ago' : `${totalHours} hours ago`;
        } else if (totalMinutes > 0) {
          timeString = totalMinutes === 1 ? '1 minute ago' : `${totalMinutes} minutes ago`;
        } else {
          timeString = 'less than a minute ago';
        }
        
        console.log(`[${currentGuid}] Manually calculated time:`, timeString);
        setLastSeenText(timeString);
      } else {
        // If date format doesn't match expected pattern, fall back to status
        console.log(`[${currentGuid}] Date format doesn't match expected pattern`);
        
        if (nimplantInfo.active) {
          if (nimplantInfo.disconnected) {
            setLastSeenText('more than 5 minutes ago');
          } else if (nimplantInfo.late) {
            setLastSeenText('about 5 minutes ago');
          } else {
            setLastSeenText('less than 1 minute ago');
          }
        } else {
          setLastSeenText('Unknown');
        }
      }
    } catch (error) {
      console.error(`[${currentGuid}] Error processing lastCheckin:`, error);
      
      if (nimplantInfo.active) {
        if (nimplantInfo.disconnected) {
          setLastSeenText('more than 5 minutes ago');
        } else if (nimplantInfo.late) {
          setLastSeenText('about 5 minutes ago');
        } else {
          setLastSeenText('less than 1 minute ago');
        }
      } else {
        setLastSeenText('Unknown');
      }
    }
  }, [opened, nimplantInfo, currentGuid]);
  
  // Simplified statistics function that uses backend values when available
  const getStatistics = useCallback(() => {
    if (!nimplantInfo) {
      return { commandCount: 0, checkinCount: 0, dataTransferred: 0 };
    }
    
    return {
      commandCount: nimplantInfo.command_count || 0,
      checkinCount: nimplantInfo.checkin_count || 0,
      dataTransferred: nimplantInfo.data_transferred || 0
    };
  }, [nimplantInfo]);
  
  // Get statistics
  const stats = getStatistics();
  
  // Drawer width
  const drawerWidth = Math.min(Math.floor(width * 0.75), 1200);
  
  // Reset tab when drawer opens
  useEffect(() => {
    if (opened) {
      setActiveTab('console');
      
      // Force a revalidation when the drawer opens
      infoResult.mutate();
      
      // We can also make a direct fetch
      handleRefresh();
    }
  }, [opened]);
  
  // Command handler (memoized to avoid recreations)
  const handleCommand = useCallback((guid: string, command: string) => {
    submitCommand(guid, command);
  }, []);
  
  // Function to kill the implant
  const handleKillImplant = useCallback(() => {
    // Close confirmation modal
    setKillModalOpen(false);
    
    // Show killing in progress modal
    setKillingModalOpen(true);
    
    // Kill the implant
    nimplantExit(currentGuid);
    
    // Wait 3 seconds before closing
    setTimeout(() => {
      // Force a refresh of the implants list with revalidation completa
      mutate(endpoints.nimplants, undefined, { revalidate: true });
      
      // Close the killing modal
      setKillingModalOpen(false);
      
      // Notify parent that implant was killed
      if (onKilled) {
        onKilled();
      } else {
        // If no callback, just close the drawer
        onClose();
      }
    }, 1000);
  }, [currentGuid, onClose, onKilled]);
  
  // Function to delete implant
  const handleDeleteImplant = useCallback(() => {
    // Close delete confirmation modal
    setDeleteModalOpen(false);
    
    // Show deletion in progress modal
    setKillingModalOpen(true);
    
    // If the implant is in state DISCONNECTED, first queue a kill command
    if (nimplantInfo?.active && nimplantInfo?.disconnected) {
      // Send kill command to queue if the implant reconnects
      nimplantExit(currentGuid);
      
      // Wait a moment to ensure the kill command has been registered
      setTimeout(() => {
        // Then delete from the database
        deleteNimplant(currentGuid).then(success => {
          // Force refresh of implants list
          mutate(endpoints.nimplants, undefined, { revalidate: true });
          
          // Close modals
          setKillingModalOpen(false);
          
          // Notify parent that implant was deleted
          if (success) {
            if (onKilled) {
              onKilled();
            } else {
              onClose();
            }
          }
        }).catch(error => {
          console.error('Error deleting implant:', error);
          setKillingModalOpen(false);
        });
      }, 1000);
    } else {
      // For inactive implants, delete directly
      deleteNimplant(currentGuid).then(success => {
        mutate(endpoints.nimplants, undefined, { revalidate: true });
        setKillingModalOpen(false);
        
        if (success) {
          if (onKilled) {
            onKilled();
          } else {
            onClose();
          }
        }
      }).catch(error => {
        console.error('Error deleting implant:', error);
        setKillingModalOpen(false);
      });
    }
  }, [currentGuid, onClose, onKilled, nimplantInfo]);
  
  // Status indicator component
  const StatusIndicator = ({ isActive, lastCheckin }: { isActive?: boolean, lastCheckin?: string }) => {
    // Common styles for all badges
    const badgeStyle = {
      textTransform: 'none' as const,
      width: '150px', // Increased width significantly to ensure "Disconnected" fits
      display: 'flex',
      justifyContent: 'center',
      padding: '0 10px' // Added padding for better readability
    };
    
    // Determine state based on GUID
    if (currentGuid.includes('TESTX01A')) {
      // Active implant (demo)
      return (
        <Badge 
          color="green" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Active
        </Badge>
      );
    } else if (currentGuid.includes('TESTX02L')) {
      // Late implant (demo)
      return (
        <Badge 
          color="orange" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Late
        </Badge>
      );
    } else if (currentGuid.includes('TESTX03D')) {
      // Implante disconnected (demo)
      return (
        <Badge 
          color="red" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Disconnected
        </Badge>
      );
    } else if (currentGuid.includes('TESTX04I')) {
      // Inactive implant (demo)
      return (
        <Badge 
          color="black" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Inactive
        </Badge>
      );
    }
    
    // Fallback in case state cannot be determined
    const rawData = infoResult.data;
    
    // If we still don't have data, show an appropriate indicator
    if (!rawData) {
      return (
        <Badge 
          color="gray" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Loading...
        </Badge>
      );
    }
    
    // Use API data for other implants with ordered priority:
    
    if (rawData.active === false) {
      return (
        <Badge 
          color="black" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Inactive
        </Badge>
      );
    } else if (rawData.active === true && rawData.disconnected === true) {
      return (
        <Badge 
          color="red" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Disconnected
        </Badge>
      );
    } else if (rawData.active === true && rawData.late === true) {
      return (
        <Badge 
          color="orange" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Late
        </Badge>
      );
    } else if (rawData.active === true) {
      return (
        <Badge 
          color="green" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Active
        </Badge>
      );
    } else {
      // Fallback in case state cannot be determined
      return (
        <Badge 
          color="gray" 
          size="lg" 
          radius="sm" 
          variant="dot"
          style={badgeStyle}
        >
          Unknown
        </Badge>
      );
    }
  };
  
  // Function to refresh implant data
  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await api.get(endpoints.nimplantInfo(currentGuid));
      infoResult.mutate(); // Force a refresh of the SWR cache
      setIsRefreshing(false);
    } catch (error) {
      console.error('Error refreshing implant data:', error);
      setIsRefreshing(false);
    }
  };
  
  const router = useRouter();
  
  // Add this state variable definition
  const [activeImplantId, setActiveImplantId] = useState<string | null>(null);
  
  // Implementation that keeps the drawer open but sends the select command
  const handleImplantSelect = (implantId: string) => {
    console.log(`Switching to implant ID: ${implantId}`);
    
    // Get the mapping from implant ID to GUID
    api.get(`${endpoints.nimplants}`)
      .then(response => {
        // Find the implant with the matching ID
        const targetImplant = response.find((imp: any) => 
          imp.id === implantId || imp.id === Number(implantId)
        );
        
        if (targetImplant && targetImplant.guid) {
          const newGuid = targetImplant.guid;
          
          
          // Show notification
          notifications.show({
            title: 'Switching Implant',
            message: `Changing to Implant #${implantId} (${newGuid})`,
            color: 'blue',
            autoClose: 1500
          });
          
          // Update the current GUID state - this will trigger all the rerendering
          setTimeout(() => {
            setCurrentGuid(newGuid);
            // Force refresh of data
            infoResult.mutate();
            consoleResult.mutate();
            
            // Show completion notification
            notifications.show({
              title: 'Switch Completed',
              message: `Now controlling Implant #${implantId} (${newGuid})`,
              color: 'green',
              autoClose: 3000
            });
            
            // Add this: Scroll console to bottom after data refresh
            setTimeout(() => {
              const consoleElement = document.querySelector('.console-output-container');
              if (consoleElement) {
                consoleElement.scrollTop = consoleElement.scrollHeight;
              }
            }, 100);
          }, 500);
        } else {
          notifications.show({
            title: 'Command Sent',
            message: `Selected implant #${implantId}, but couldn't find GUID information`,
            color: 'yellow',
            autoClose: 1500
          });
        }
      })
      .catch(error => {
        console.error('Error fetching implants:', error);
      });
  };
  
  // Add a useEffect to synchronize the guid prop with currentGuid
  useEffect(() => {
    if (guid !== currentGuid) {
      setCurrentGuid(guid);
    }
  }, [guid]);
  
  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={drawerWidth}
      title={
        <Group style={{ width: '100%' }} justify="apart">
          <Stack gap={5} style={{ flex: 1 }}>
            <Group gap="xs" align="center" wrap="nowrap">
              <Text 
                fw={600} 
                size="lg"
              >
                Implant ID: 
                <span style={{ 
                  color: nimplantInfo?.active 
                    ? nimplantInfo?.disconnected 
                      ? 'var(--mantine-color-red-7)'  // Disconnected
                      : nimplantInfo?.late 
                        ? 'var(--mantine-color-orange-7)'  // Late
                        : 'var(--mantine-color-green-7)'  // Active
                    : 'var(--mantine-color-gray-7)',  // Inactive
                  fontWeight: 700,
                  borderBottom: `2px solid ${
                    nimplantInfo?.active 
                      ? nimplantInfo?.disconnected 
                        ? 'var(--mantine-color-red-5)'  // Disconnected
                        : nimplantInfo?.late 
                          ? 'var(--mantine-color-orange-5)'  // Late
                          : 'var(--mantine-color-green-5)'  // Active
                      : 'var(--mantine-color-gray-5)'  // Inactive
                  }`,
                  paddingBottom: '2px'
                }}>
                  {` ${nimplantInfo?.id || '?'} - ${currentGuid}`}
                </span>
              </Text>
              {nimplantInfo && (
                <>
                  <StatusIndicator isActive={nimplantInfo?.active} lastCheckin={nimplantInfo?.lastCheckin} />
                  {nimplantInfo?.workspace_name && nimplantInfo.workspace_name !== 'Default' ? (
                    <Badge 
                      color="blue" 
                      variant="light" 
                      size="xs"
                      style={{ 
                        fontWeight: 600,
                        fontSize: '0.75rem',
                        borderRadius: '4px',
                        height: '25px',
                        padding: '0 8px',
                        textTransform: 'uppercase'
                      }}
                    >
                      Workspace: {nimplantInfo.workspace_name}
                    </Badge>
                  ) : nimplantInfo?.workspace_uuid && (!nimplantInfo.workspace_name) ? (
                    <Badge 
                      color="gray" 
                      variant="light" 
                      size="xs"
                      style={{ 
                        fontWeight: 600,
                        fontSize: '0.75rem',
                        borderRadius: '4px',
                        height: '25px',
                        padding: '0 8px',
                        textTransform: 'uppercase'
                      }}
                      title={`UUID completo: ${nimplantInfo.workspace_uuid}`}
                    >
                      Workspace: {nimplantInfo.workspace_uuid.substring(0, 8)}...
                    </Badge>
                  ) : (
                    <Badge 
                      color="gray" 
                      variant="light" 
                      size="xs"
                      style={{ 
                        fontWeight: 600,
                        fontSize: '0.75rem',
                        borderRadius: '4px',
                        height: '25px',
                        padding: '0 8px',
                        textTransform: 'uppercase'
                      }}
                    >
                      Workspace: Default
                    </Badge>
                  )}
                </>
              )}
            </Group>
            {nimplantInfo && (
              <Text size="sm" c="dimmed">
                Last seen: {lastSeenText || 'Unknown'}
              </Text>
            )}
          </Stack>
        </Group>
      }
      withCloseButton={true}
      styles={{
        root: {
          height: '100vh',
          overflow: 'hidden'
        },
        inner: {
          height: '100%',
          overflow: 'hidden'
        },
        body: {
          height: 'calc(100% - 60px)',
          padding: 0,
          overflow: 'hidden'
        },
        content: {
          height: '100%',
          overflow: 'hidden'
        },
        header: {
          borderBottom: '1px solid var(--mantine-color-gray-3)',
          padding: '15px 20px',
          position: 'relative',
        },
        overlay: {
          transition: 'opacity 300ms ease',
        }
      }}
      transitionProps={{
        duration: 300,
        exitDuration: 300,
        timingFunction: 'ease'
      }}
    >
      {/* Modal of confirmation to kill the implant */}
      <Modal
        opened={killModalOpen}
        onClose={() => setKillModalOpen(false)}
        title={<b>Danger zone!</b>}
        centered
      >
        Are you sure you want to kill this Implant?

        <Box style={{ height: 20 }} /> {/* Space */}

        <Button 
          onClick={handleKillImplant}
          leftSection={<FaSkull />} 
          style={{width: '100%'}}
          color="red"
        >
          Yes, kill kill kill!
        </Button>
      </Modal>

      {/* Modal for confirming the deletion of the implant */}
      <Modal
        opened={deleteModalOpen}
        onClose={() => setDeleteModalOpen(false)}
        title={<b>{nimplantInfo?.active && nimplantInfo?.disconnected ? 'Queue Kill & Delete Implant' : 'Delete Implant'}</b>}
        centered
      >
        {nimplantInfo?.active && nimplantInfo?.disconnected ? (
          <>
            This implant is disconnected. We will:
            <ol>
              <li>Queue a kill command in case it reconnects</li>
              <li>Delete it from the database</li>
            </ol>
            Are you sure you want to proceed?
          </>
        ) : (
          <>
            Are you sure you want to delete this implant from the database? This action is irreversible.
          </>
        )}

        <Box style={{ height: 20 }} /> {/* Space */}

        <Button 
          onClick={handleDeleteImplant}
          leftSection={<FaTrash />} 
          style={{width: '100%'}}
          color="red"
        >
          {nimplantInfo?.active && nimplantInfo?.disconnected ? 'Yes, queue kill and delete' : 'Yes, permanently delete'}
        </Button>
      </Modal>

      {/* Modal that shows the implant deletion process */}
      <Modal
        opened={killingModalOpen}
        onClose={() => {}} // We don't allow closing this modal manually
        title={<b>Killing Implant...</b>}
        centered
        withCloseButton={false}
      >
        <Box style={{ textAlign: 'center', padding: '20px 0' }}>
          <Loader size="md" style={{ margin: '0 auto 20px auto' }}/>
          <Text>Terminating the implant process...</Text>
        </Box>
      </Modal>

      <Tabs 
        defaultValue="console" 
        value={activeTab} 
        onChange={(value) => value && setActiveTab(value)} 
        style={{ height: '100%' }}
        styles={{
          tab: {
            fontSize: '0.9rem',
            padding: '10px 16px',
            fontWeight: 500,
            height: '42px',
            '&[data-active]': {
              fontWeight: 600
            }
          },
          list: {
            borderBottom: '1px solid var(--mantine-color-gray-3)',
            paddingLeft: '12px'
          },
          panel: {
            paddingTop: 0
          }
        }}
      >
        <Tabs.List px="md" mb="xs">
          <Tabs.Tab value="console" leftSection={<FaTerminal size={15} />}>Console</Tabs.Tab>
          <Tabs.Tab value="info" leftSection={<FaInfoCircle size={15} />}>Process</Tabs.Tab>
          <Tabs.Tab value="network" leftSection={<FaNetworkWired size={15} />}>Network</Tabs.Tab>
          <Tabs.Tab value="downloads" leftSection={<FaDownload size={15} />}>Downloads</Tabs.Tab>
          <Tabs.Tab value="history" leftSection={<FaHistory size={15} />}>History</Tabs.Tab>
          <div style={{ flex: 1 }}></div>
          <Tabs.Tab 
            value="kill" 
            style={{ 
              color: 'var(--mantine-color-red-6)',
              cursor: 'pointer',
              opacity: 1
            }}
            leftSection={nimplantInfo?.active && !nimplantInfo?.disconnected ? <FaSkull size={15} /> : <FaTrash size={15} />}
            onClick={(e) => {
              e.preventDefault();
              if (nimplantInfo?.active && !nimplantInfo?.disconnected) {
                setKillModalOpen(true);
              } else {
                setDeleteModalOpen(true);
              }
            }}
          >
            {nimplantInfo?.active && !nimplantInfo?.disconnected 
              ? 'Kill Implant' 
              : nimplantInfo?.active && nimplantInfo?.disconnected 
                ? 'Queue Kill & Delete' 
                : 'Delete Implant'}
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel 
          value="console" 
          style={{ 
            height: 'calc(100% - 48px)',
            overflowY: 'auto',
            padding: '0'
          }}
        >          
          {/* Console component already has its own padding and scroll structures */}
          {opened && (
            <Console 
              guid={currentGuid}
              allowInput={true}
              consoleData={nimplantConsole}
              disabled={!nimplantInfo?.active}
              inputFunction={handleCommand}
              historyLimit={historyLimit}
              onUpdateHistoryLimit={updateHistoryLimit}
              onImplantSelect={handleImplantSelect}
            />
          )}
        </Tabs.Panel>

        <Tabs.Panel value="info" style={{ height: 'calc(100% - 48px)', overflow: 'auto', padding: '0' }}>
          <Box p="md" pt="xs">
            {/* Create custom process information panel */}
            {opened && nimplantInfo && (
              <Stack>
                <Paper shadow="xs" radius="md" p="md" style={{ border: '1px solid #E9ECEF' }}>
                  <Text fw={600} size="sm" mb="md">Process Information</Text>
                  <Grid>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Process name</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (
                          `${nimplantInfo?.pname || 'Unknown'} (ID ${nimplantInfo?.pid || 'Unknown'})`
                        )}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Username</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.username || 'Unknown')}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Operating System</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.osBuild || 'Unknown')}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Hostname</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.hostname || 'Unknown')}
                      </Text>
                    </Grid.Col>
                  </Grid>
                </Paper>
              </Stack>
            )}
          </Box>
        </Tabs.Panel>
        
        <Tabs.Panel value="network" style={{ height: 'calc(100% - 48px)', overflow: 'auto', padding: '0' }}>
          <Box p="md" pt="xs">
            {opened && (
              <Stack>
                <Paper shadow="xs" radius="md" p="md" style={{ border: '1px solid #E9ECEF' }}>
                  <Text fw={600} size="sm" mb="md">Network Information</Text>
                  <Grid>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>External IP</Text>
                      <Text fw={500} style={{ fontFamily: 'monospace' }}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.ipAddrExt || 'Unknown')}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Internal IP</Text>
                      <Text fw={500} style={{ fontFamily: 'monospace' }}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.ipAddrInt || 'Unknown')}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Hostname</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.hostname || 'Unknown')}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Username</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : (nimplantInfo?.username || 'Unknown')}
                      </Text>
                    </Grid.Col>
                  </Grid>
                </Paper>
                
                <Paper shadow="xs" radius="md" p="md" style={{ border: '1px solid #E9ECEF' }}>
                  <Text fw={600} size="sm" mb="md">Implant communication</Text>
                  <Grid>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Sleep Time</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : `${nimplantInfo?.sleepTime || '0'} seconds`}
                      </Text>
                    </Grid.Col>
                    <Grid.Col span={6}>
                      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Jitter</Text>
                      <Text fw={500}>
                        {infoResult.isLoading ? <Loader size="xs" /> : `${nimplantInfo?.sleepJitter !== undefined ? nimplantInfo.sleepJitter : '0'}%`}
                      </Text>
                    </Grid.Col>
                  </Grid>
                </Paper>
              </Stack>
            )}
          </Box>
        </Tabs.Panel>
        
        <Tabs.Panel value="history" style={{ height: 'calc(100% - 48px)', overflow: 'auto', padding: '0' }}>
          <Box p="md" pt="xs">
            {opened && (
              <>
                <Paper shadow="xs" radius="md" p="md" style={{ border: '1px solid #E9ECEF' }}>
                  <Text fw={600} size="sm" mb="md">Activity statistics</Text>
                  <Grid>
                    <Grid.Col span={4}>
                      <Card padding="md" radius="md" style={{ backgroundColor: '#f8f9fa' }}>
                        <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Command Count</Text>
                        <Text fw={700} size="xl" c="blue">
                          {infoResult.isLoading ? <Loader size="xs" /> : (formatCompactNumber(stats.commandCount || 0))}
                        </Text>
                      </Card>
                    </Grid.Col>
                    <Grid.Col span={4}>
                      <Card padding="md" radius="md" style={{ backgroundColor: '#f8f9fa' }}>
                        <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Check-in Count</Text>
                        <Text fw={700} size="xl" c="teal">
                          {infoResult.isLoading ? <Loader size="xs" /> : (formatCompactNumber(stats.checkinCount || 0))}
                          {nimplantInfo?.active && <Text span size="sm" ml={5}>(Active)</Text>}
                        </Text>
                      </Card>
                    </Grid.Col>
                    <Grid.Col span={4}>
                      <Card padding="md" radius="md" style={{ backgroundColor: '#f8f9fa' }}>
                        <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={2}>Data Transferred</Text>
                        <Text fw={700} c="dimmed"  size="xl">
                          {infoResult.isLoading ? <Loader size="xs" /> : (formatBytes(stats.dataTransferred || 0))}
                        </Text>
                      </Card>
                    </Grid.Col>
                  </Grid>
                </Paper>

                {/* Section of dynamic log file history */}
                <Paper shadow="xs" radius="md" p="md" mt="lg" style={{ border: '1px solid #E9ECEF' }}>
                  <Text fw={700} size="sm" mb="md">Activity Log</Text>
                  
                  <FileTransferLog guid={currentGuid} />
                </Paper>
              </>
            )}
          </Box>
        </Tabs.Panel>
        
        <Tabs.Panel value="downloads" style={{ height: 'calc(100% - 48px)', overflow: 'auto', padding: '0' }}>
          <Box p="md" pt="xs">
            {opened && (
              <Paper shadow="xs" radius="md" p="md" style={{ border: '1px solid #E9ECEF' }}>
                <Box mb="md">
                  <Text fw={600} size="lg">Downloaded Files</Text>
                  <Text size="sm" c="dimmed">Files downloaded from this implant</Text>
                </Box>
                
                <div>
                  <ImplantDownloadList guid={currentGuid} />
                </div>
              </Paper>
            )}
          </Box>
        </Tabs.Panel>
      </Tabs>
    </Drawer>
  );
});
NimplantContent.displayName = 'NimplantContent';

// Component to show the file transfer history
const FileTransferLog = ({ guid }: { guid: string }) => {
  return <ImplantFileTransfersList guid={guid} />;
};

// Main component that manages when to show the drawer
export default function NimplantDrawer({ opened, onClose, guid, onKilled }: NimplantDrawerProps) {
  // Use an empty guid if there is none selected
  const safeGuid = guid || '';
  
  // Always render NimplantContent component, but pass the opened prop
  // so it can manage its internal state
  return <NimplantContent guid={safeGuid} onClose={onClose} opened={opened} onKilled={onKilled} />;
}

type NimplantOverviewCardType = {
  np: Types.NimplantOverview
  largeScreen: boolean,
  onClick?: (e: React.MouseEvent) => void
}

// Component for single Implant card (for 'implants' overview screen)
function NimplantOverviewCard({np, largeScreen, onClick} : NimplantOverviewCardType) {
  // This is the ONLY state we need for the time display
  const [lastSeen, setLastSeen] = useState<string>('Loading...');
  
  // Determine if we need detailed information
  const needsDetailedInfo = np.active && (!np.lastCheckin || np.lastCheckin === 'undefined');
  
  const { data: detailedInfo } = useSWR<Types.Nimplant>(
    needsDetailedInfo ? endpoints.nimplantInfo(np.guid) : null,
    swrFetcher,
    { revalidateOnFocus: false, dedupingInterval: 10000 }
  );
  
  // THIS IS THE KEY EFFECT - Mirrors exactly what's in NimplantDrawer.tsx
  useEffect(() => {
    // For debugging
    console.log(`[${np.guid}] Setting up time display`);
    
    // If disconnected for any reason, show fixed status
    if (!np.lastCheckin || np.lastCheckin.includes('1970') || np.lastCheckin.includes('1969')) {
      console.log(`[${np.guid}] Invalid lastCheckin detected:`, np.lastCheckin);
      
      // Force exact time text based on status
      if (np.active) {
        if (np.disconnected) {
          setLastSeen('more than 5 minutes ago');
        } else if (np.late) {
          setLastSeen('about 5 minutes ago');
        } else {
          setLastSeen('less than 1 minute ago');
        }
      } else {
        setLastSeen('Unknown');
      }
      return;
    }
    
    // Function to update time from the valid date
    const updateTime = () => {
      console.log(`[${np.guid}] Running time update`);
      const timeString = timeSince(np.lastCheckin);
      
      // Detect invalid time results (years ago)
      if (timeString && !timeString.includes('years ago')) {
        setLastSeen(timeString);
      } else {
        console.log(`[${np.guid}] Invalid time result:`, timeString);
        
        // Use status-based time descriptions
        if (np.active) {
          if (np.disconnected) {
            setLastSeen('more than 5 minutes ago');
          } else if (np.late) {
            setLastSeen('about 5 minutes ago');
          } else {
            setLastSeen('less than 1 minute ago');
          }
        } else {
          setLastSeen('Unknown');
        }
      }
    };
    
    // Call immediately
    updateTime();
    
    // Register with the timer system
    const unregister = registerTimeUpdateListener(updateTime);
    return () => unregister();
  }, [np.guid, np.lastCheckin, np.active, np.late, np.disconnected]);
  
  // Rest of component unchanged
  const handleClick = (e: React.MouseEvent) => {
    if (onClick) {
      e.preventDefault();
      e.stopPropagation();
      onClick(e);
    }
  };

  const getStatusStyle = () => {
    if (np.active && np.disconnected) {
      return {
        opacity: 0.9,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-red-5)'
      };
    } else if (!np.active) {
      return {
        opacity: 0.7,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-gray-8)'
      };
    } else if (np.late) {
      return {
        opacity: 0.9,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-orange-5)'
      };
    }
    return {
      opacity: 1,
      background: 'white',
      borderLeft: '4px solid var(--mantine-color-green-5)'
    };
  };

  const statusStyle = getStatusStyle();
  
  return (
    <div className={classes.fullRowHover} onClick={handleClick} style={{...statusStyle, position: 'relative'}}>
      {/* Component UI unchanged */}
      <Flex px={16} py="md" style={{ width: '100%', alignItems: 'center' }}>
        <Box style={{ width: '10%', display: 'flex', justifyContent: 'center' }}>
          <div style={{ 
            color: np.active && np.disconnected ? 'var(--mantine-color-red-7)' :
                  np.late ? 'var(--mantine-color-orange-3)' : 
                  np.active ? 'var(--mantine-color-green-3)' : 
                  'var(--mantine-color-gray-7)'
          }}>
            {np.active && !np.disconnected && !np.late ? <FaLink size='1.5em' /> : <FaUnlink size='1.5em' />}
          </div>
        </Box>
        
        <Box style={{ width: '20%', paddingLeft: '0' }}>
          <Stack gap={3}>
            <Group align="center" gap="xs">
              <Text fw="bold" style={{ color: 'var(--mantine-color-dark-6)' }}>
                {largeScreen ? `${np.id} - ${np.guid}` : np.guid}
              </Text>
              {np.active && np.disconnected && (
                <Badge size="xs" color="red" variant="light">Disconnected</Badge>
              )}
              {!np.active && (
                <Badge size="xs" color="dark" variant="light">Inactive</Badge>
              )}
              {np.late && np.active && !np.disconnected && (
                <Badge size="xs" color="orange" variant="light">Late</Badge>
              )}
              {np.active && !np.late && !np.disconnected && (
                <Badge size="xs" color="green" variant="light">Active</Badge>
              )}
            </Group>

            <Group gap={4} align="center" style={{ color: 'var(--mantine-color-gray-5)' }}>
              <FaClock size={12} style={{ minWidth: '16px' }} />
              <Text size="sm">{lastSeen}</Text>
            </Group>
          </Stack>
        </Box>

        <Box style={{ width: '23%', paddingLeft: '0' }}>
          <Stack gap={3}>
            <Text>{np.username || 'Unknown'} @ {np.hostname || 'Unknown'}</Text>
            <Group gap={4} align="center" style={{ color: 'var(--mantine-color-gray-5)' }}>
              <FaFingerprint size={12} style={{ minWidth: '16px' }} />
              <Text size="sm">PID: {np.pid || 'Unknown'}</Text>
            </Group>
          </Stack>
        </Box>

        <Box style={{ width: '22%', paddingLeft: '0' }}>
          <Stack gap={3}>
            <Group gap={4} align="center">
              <FaNetworkWired size={12} style={{ minWidth: '16px' }} />
              <Text style={{ fontFamily: 'monospace', fontSize: '0.92rem' }}>
                {np.ipAddrInt}
              </Text>
            </Group>
            <Group gap={4} align="center" style={{ color: 'var(--mantine-color-gray-5)' }}>
              <FaCloud size={12} style={{ minWidth: '16px' }} />
              <Text size="sm" style={{ fontFamily: 'monospace' }}>
                {np.ipAddrExt}
              </Text>
            </Group>
          </Stack>
        </Box>

        <Box style={{ width: '15%', paddingLeft: '0' }}>
          <Stack gap={3}>
            {np.workspace_name && np.workspace_name !== 'Default' ? (
              <Group gap="xs">
                <Badge 
                  color="blue" 
                  variant="light" 
                  size="xs"
                  style={{ 
                    fontWeight: 600,
                    fontSize: '0.75rem',
                    borderRadius: '4px',
                    height: '25px',
                    padding: '0 8px',
                    textTransform: 'uppercase'
                  }}
                >
                  {np.workspace_name}
                </Badge>
              </Group>
            ) : np.workspace_uuid && (!np.workspace_name) ? (
              <Group gap="xs">
                <Badge 
                  color="gray" 
                  variant="light" 
                  size="xs"
                  style={{ 
                    fontWeight: 600,
                    fontSize: '0.75rem',
                    borderRadius: '4px',
                    height: '25px',
                    padding: '0 8px',
                    textTransform: 'uppercase'
                  }}
                  title={`Complete UUID: ${np.workspace_uuid}`}
                >
                  {np.workspace_uuid.substring(0, 8)}...
                </Badge>
              </Group>
            ) : (
              <Group gap="xs">
                <Badge 
                  color="gray" 
                  variant="light" 
                  size="xs"
                  style={{ 
                    fontWeight: 600,
                    fontSize: '0.75rem',
                    borderRadius: '4px',
                    height: '25px',
                    padding: '0 8px',
                    textTransform: 'uppercase'
                  }}
                >
                  Default
                </Badge>
              </Group>
            )}
          </Stack>
        </Box>
        
        <Box style={{ width: '10%', display: 'flex', justifyContent: 'center' }}>
          {onClick && <FaAngleRight size="1.5em" className={classes.actionIcon} />}
        </Box>
      </Flex>
    </div>
  )
} 