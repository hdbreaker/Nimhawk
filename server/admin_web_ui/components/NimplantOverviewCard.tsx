import { FaLink, FaUnlink, FaNetworkWired, FaCloud, FaFingerprint, FaClock, FaAngleRight } from 'react-icons/fa'
import { Text, Group, Stack, Box, Flex, Badge } from '@mantine/core'
import { timeSince, endpoints, registerTimeUpdateListener } from '../modules/nimplant';
import React, { useEffect, useState } from "react";
import type Types from '../modules/nimplant.d'
import classes from '../styles/liststyles.module.css'
import { swrFetcher } from '../modules/apiFetcher';
import useSWR from 'swr'

type NimplantOverviewCardType = {
  np: Types.NimplantOverview
  largeScreen: boolean,
  onClick?: (e: React.MouseEvent) => void
}

// Component for single Implant card (for 'implants' overview screen)
function NimplantOverviewCard({np, largeScreen, onClick} : NimplantOverviewCardType) {
  const [lastSeen, setLastSeen] = useState<string>('Loading...');
  const [originalLastCheckin, setOriginalLastCheckin] = useState<string | null>(null);
  
  // Determine if we need detailed information
  // We need detailed info if the implant is active but doesn't have lastCheckin data
  const needsDetailedInfo = np.active && (!np.lastCheckin || np.lastCheckin === 'undefined');
  
  const { data: detailedInfo } = useSWR<Types.Nimplant>(
    // Condition: only call if we need detailed info
    needsDetailedInfo ? endpoints.nimplantInfo(np.guid) : null,
    swrFetcher,
    { 
      // No refresh automatically, we only need the info once
      revalidateOnFocus: false,
      dedupingInterval: 10000
    }
  );
  
  // Monitor when detailed info arrives or lastCheckin changes
  useEffect(() => {
    // Debug info to check raw value
    console.log(`[${np.guid}] Raw lastCheckin value:`, np.lastCheckin);
    
    // If the date is undefined or null, use status-based values
    if (!np.lastCheckin) {
      console.log(`[${np.guid}] No lastCheckin value available`);
      setLastSeen(np.active ? 'less than 1 minute ago' : 'Unknown');
      return;
    }
    
    // If the date contains a pipe, extract only the first part
    let dateToProcess = np.lastCheckin;
    if (dateToProcess.includes('|')) {
      dateToProcess = dateToProcess.split('|')[0];
      console.log(`[${np.guid}] Using first part:`, dateToProcess);
    }
    
    try {
      // Parse the date manually - Format: DD/MM/YYYY HH:MM:SS
      if (dateToProcess.match(/^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}:\d{2}$/)) {
        const [datePart, timePart] = dateToProcess.split(' ');
        const [day, month, year] = datePart.split('/').map(Number);
        const [hours, minutes, secs] = timePart.split(':').map(Number);
        
        // Create date object (month is 0-indexed in JavaScript)
        const dateObj = new Date(year, month - 1, day, hours, minutes, secs);
        console.log(`[${np.guid}] Parsed date:`, dateObj);
        
        // Calculate time difference manually
        const now = new Date();
        const diffMs = now - dateObj;
        
        // For future dates, just show "just now" for active implants
        if (diffMs < 0) {
          console.log(`[${np.guid}] Date is in the future by ${-diffMs}ms`);
          setLastSeen(np.active ? 'just now' : 'Unknown');
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
        
        console.log(`[${np.guid}] Manually calculated time:`, timeString);
        setLastSeen(timeString);
      } else {
        // If date format doesn't match expected pattern, fall back to status
        console.log(`[${np.guid}] Date format doesn't match expected pattern`);
        
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
    } catch (error) {
      console.error(`[${np.guid}] Error processing lastCheckin:`, error);
      setLastSeen(np.active ? 'less than 1 minute ago' : 'Unknown');
    }
  }, [np.lastCheckin, np.active, np.disconnected, np.late, np.guid]);

  const handleClick = (e: React.MouseEvent) => {
    if (onClick) {
      e.preventDefault();
      e.stopPropagation();
      onClick(e);
    }
  };

  // Get proper styles based on implant status
  const getStatusStyle = () => {
    // Disconnected implants (active but without check-in for more than 5 minutes)
    if (np.active && np.disconnected) {
      return {
        opacity: 0.9,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-red-5)'
      };
    } 
    // Inactive implants (that have closed correctly)
    else if (!np.active) {
      return {
        opacity: 0.7,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-gray-8)'
      };
    } 
    // Late implants (late) but not disconnected
    else if (np.late) {
      return {
        opacity: 0.9,
        background: 'var(--mantine-color-gray-0)',
        borderLeft: '4px solid var(--mantine-color-orange-5)'
      };
    }
    // Normal active implants
    return {
      opacity: 1,
      background: 'white',
      borderLeft: '4px solid var(--mantine-color-green-5)'
    };
  };

  const statusStyle = getStatusStyle();
  
  return (
    <div className={classes.fullRowHover} onClick={handleClick} style={{...statusStyle, position: 'relative'}}>
      <Flex px={16} py="md" style={{ width: '100%', alignItems: 'center' }}>
        {/* Column for status icon (ping) */}
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
        
        {/* Column for implant ID */}
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

        {/* Column for System */}
        <Box style={{ width: '23%', paddingLeft: '0' }}>
          <Stack gap={3}>
            <Text>{np.username || 'Unknown'} @ {np.hostname || 'Unknown'}</Text>
            <Group gap={4} align="center" style={{ color: 'var(--mantine-color-gray-5)' }}>
              <FaFingerprint size={12} style={{ minWidth: '16px' }} />
              <Text size="sm">PID: {np.pid || 'Unknown'}</Text>
            </Group>
          </Stack>
        </Box>

        {/* Column for Network */}
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

        {/* Column for Workspace */}
        <Box style={{ width: '15%', paddingLeft: '0' }}>
          <Stack gap={3}>
            {/* Conditional workspace visualization */}
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
        
        {/* Column for Actions */}
        <Box style={{ width: '10%', display: 'flex', justifyContent: 'center' }}>
          {onClick && <FaAngleRight size="1.5em" className={classes.actionIcon} />}
        </Box>
      </Flex>
    </div>
  )
}

export default NimplantOverviewCard