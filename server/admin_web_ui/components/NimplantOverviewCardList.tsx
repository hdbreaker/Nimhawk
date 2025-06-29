import { FaRegMeh, FaSearch, FaFilter } from 'react-icons/fa'
import { getNimplants, restoreConnectionError, showConnectionError } from '../modules/nimplant'
import { Text, Group, Loader, TextInput, ActionIcon, Chip, Box, Button, Popover, Paper, Stack, SimpleGrid } from '@mantine/core'
import { useMediaQuery } from '@mantine/hooks'
import NimplantOverviewCard from './NimplantOverviewCard'
import type Types from '../modules/nimplant.d'
import { useEffect, Dispatch, SetStateAction, useState, useMemo } from 'react'

interface NimplantOverviewCardListProps {
  onNimplantClick: Dispatch<SetStateAction<string | null>>;
  nimplantsData?: any[]; // Implant data passed directly
  showOnlyActive?: boolean; // Option to filter and show only active implants
  searchTerm?: string; // Search term passed from parent component
  drawerOpen?: boolean; // New prop to indicate if a drawer is open
}

interface FilterOptions {
  status: string[];
  searchTerm: string;
  showOnlyActive: boolean;
}

// Component for single implant card (for 'implants' overview screen)
function NimplantOverviewCardList({ onNimplantClick, nimplantsData, showOnlyActive = true, searchTerm = '', drawerOpen = false }: NimplantOverviewCardListProps) {
  const largeScreen = useMediaQuery('(min-width: 800px)')
  const [filterOpened, setFilterOpened] = useState(false);
  const [filterOptions, setFilterOptions] = useState<FilterOptions>({
    status: [],
    searchTerm: searchTerm,
    showOnlyActive
  });

  // Update filterOptions when searchTerm changes
  useEffect(() => {
    setFilterOptions(prev => ({
      ...prev,
      searchTerm: searchTerm
    }));
  }, [searchTerm]);

  // Query API only if data is not passed directly
  const {nimplants, nimplantsLoading, nimplantsError} = !nimplantsData ? getNimplants() : { nimplants: nimplantsData, nimplantsLoading: false, nimplantsError: null };

  useEffect(() => {
    // Render placeholder if data is not yet available
    if (nimplantsError) {
      showConnectionError()
    } else if (nimplants) {
      restoreConnectionError()
    }
  }, [nimplants, nimplantsError])

  useEffect(() => {
    // Update the filter when the showOnlyActive prop changes
    setFilterOptions(prev => ({ ...prev, showOnlyActive }));
  }, [showOnlyActive]);

  // Filter implants according to search criteria and filters
  const filteredImplants = useMemo(() => {
    if (!nimplants || !Array.isArray(nimplants)) return [];

    return nimplants
      .filter(implant => {
        // Filter by active/inactive state
        if (filterOptions.showOnlyActive && !implant.active) {
          return false;
        }

        // Filter by specific state (active, late, disconnected, inactive)
        if (filterOptions.status.length > 0) {
          // Determine the real state based on the implant properties
          let implantStatus = 'unknown';
          
          if (!implant.active) {
            implantStatus = 'inactive';
          } else if (implant.disconnected) {
            implantStatus = 'disconnected';
          } else if (implant.late) {
            implantStatus = 'late';
          } else if (implant.active) {
            implantStatus = 'active';
          }

          if (!filterOptions.status.includes(implantStatus)) {
            return false;
          }
        }

        // Filter by search term (search in multiple fields)
        if (filterOptions.searchTerm) {
          const searchTermLower = filterOptions.searchTerm.toLowerCase();
          
          // Search in common fields
          const fieldsToSearch = [
            implant.guid,
            implant.hostname,
            implant.username,
            implant.ipAddrExt,
            implant.ipAddrInt,
            implant.osBuild,
            implant.pname,
            // Add workspace fields
            implant.workspace_name || 'Default',
            implant.workspace_uuid
          ];
          
          return fieldsToSearch.some(field => 
            field && field.toString().toLowerCase().includes(searchTermLower)
          );
        }

        return true;
      })
      // Sort by ID in descending order
      .sort((a, b) => {
        // Convert IDs to numbers to sort correctly
        const idA = parseInt(a.id, 10);
        const idB = parseInt(b.id, 10);
        
        // Sort from highest to lowest (descending)
        return idB - idA;
      });
  }, [nimplants, filterOptions]);

  // Function to handle search input change
  const handleSearchChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setFilterOptions(prev => ({
      ...prev,
      searchTerm: event.target.value
    }));
  };

  // Function to toggle status filter
  const toggleStatusFilter = (status: string) => {
    setFilterOptions(prev => {
      const newStatuses = prev.status.includes(status) 
        ? prev.status.filter(s => s !== status)
        : [...prev.status, status];
      
      return {
        ...prev,
        status: newStatuses
      };
    });
  };

  // Function to reset all filters
  const resetFilters = () => {
    setFilterOptions({
      status: [],
      searchTerm: '',
      showOnlyActive
    });
  };

  // Logic for displaying component
  if (nimplantsLoading || nimplantsError) {
    return (
      <Group py="xl" style={{ marginLeft: '55px', color: 'var(--mantine-color-gray-5)' }}>
        <Loader variant="dots" />
        <Text size="md">Loading...</Text>
      </Group>
    )
  } 

  // Check data length and return placeholder if no implants are active
  if (filteredImplants.length === 0) return (
    <>
      <Group py="xl" style={{ marginLeft: '55px', color: 'var(--mantine-color-gray-5)' }}>
        <FaRegMeh size='1.5em' />
        <Text size="md">No implants found...</Text>
      </Group>
      
      {/* Floating filter button with popover - Hide it if the drawer is open */}
      {!drawerOpen && (
        <Popover 
          opened={filterOpened} 
          onChange={setFilterOpened}
          position="top-end"
          shadow="md"
          width={350}
          styles={{
            dropdown: {
              borderRadius: '16px',
              boxShadow: '0 4px 15px rgba(0, 0, 0, 0.1)',
              border: '1px solid var(--mantine-color-gray-3)'
            }
          }}
        >
          <Popover.Target>
            <ActionIcon
              variant="filled"
              color="dark"
              radius="xl"
              size="xl"
              style={{
                position: 'fixed',
                bottom: '20px',
                right: '20px',
                zIndex: 999,
                boxShadow: '0 4px 10px rgba(0, 0, 0, 0.2)',
                transition: 'transform 0.2s ease, background-color 0.2s ease',
              }}
              styles={(theme) => ({
                root: {
                  '&:hover': {
                    transform: 'scale(1.05)',
                    backgroundColor: theme.colors.dark[7],
                  }
                }
              })}
              onClick={() => setFilterOpened((o) => !o)}
            >
              <FaFilter size={20} />
            </ActionIcon>
          </Popover.Target>
          <Popover.Dropdown>
            <Paper style={{ width: '100%' }} p="md" radius="lg">
              <Stack gap="md">
                <Text fw={600} size="sm">Status Filters</Text>
                <Chip.Group multiple value={filterOptions.status} onChange={(values) => setFilterOptions(prev => ({ ...prev, status: values }))}>
                  <SimpleGrid cols={2} spacing="xs">
                    <Chip value="active" color="green" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Active</Chip>
                    <Chip value="late" color="orange" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Late</Chip>
                    <Chip value="disconnected" color="red" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Disconnected</Chip>
                    <Chip value="inactive" color="dark" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Inactive</Chip>
                  </SimpleGrid>
                </Chip.Group>
                <Button onClick={resetFilters} variant="outline" fullWidth size="sm" radius="md" color="dark">
                  Reset Filters
                </Button>
              </Stack>
            </Paper>
          </Popover.Dropdown>
        </Popover>
      )}
    </>
  )

  // Otherwise render NimplantOverviewCard component for each implant
  return (
    <>
      {filteredImplants.map((np: Types.NimplantOverview) => (
        <NimplantOverviewCard 
          key={np.guid} 
          np={np} 
          largeScreen={largeScreen || false} 
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            onNimplantClick(np.guid);
          }}
        />
      ))}
      
      {/* Floating filter button with popover - Hide it if the drawer is open */}
      {!drawerOpen && (
        <Popover 
          opened={filterOpened} 
          onChange={setFilterOpened}
          position="top-end"
          shadow="md"
          width={350}
          styles={{
            dropdown: {
              borderRadius: '16px',
              boxShadow: '0 4px 15px rgba(0, 0, 0, 0.1)',
              border: '1px solid var(--mantine-color-gray-3)'
            }
          }}
        >
          <Popover.Target>
            <ActionIcon
              variant="filled"
              color="dark"
              radius="xl"
              size="xl"
              style={{
                position: 'fixed',
                bottom: '20px',
                right: '20px',
                zIndex: 999,
                boxShadow: '0 4px 10px rgba(0, 0, 0, 0.2)',
                transition: 'transform 0.2s ease, background-color 0.2s ease',
              }}
              styles={(theme) => ({
                root: {
                  '&:hover': {
                    transform: 'scale(1.05)',
                    backgroundColor: theme.colors.dark[7],
                  }
                }
              })}
              onClick={() => setFilterOpened((o) => !o)}
            >
              <FaFilter size={20} />
            </ActionIcon>
          </Popover.Target>
          <Popover.Dropdown>
            <Paper style={{ width: '100%' }} p="md" radius="lg">
              <Stack gap="md">
                <Text fw={600} size="sm">Status Filters</Text>
                <Chip.Group multiple value={filterOptions.status} onChange={(values) => setFilterOptions(prev => ({ ...prev, status: values }))}>
                  <SimpleGrid cols={2} spacing="xs">
                    <Chip value="active" color="green" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Active</Chip>
                    <Chip value="late" color="orange" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Late</Chip>
                    <Chip value="disconnected" color="red" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Disconnected</Chip>
                    <Chip value="inactive" color="dark" radius="md" variant="filled" styles={{ label: { width: '100%', justifyContent: 'center' } }}>Inactive</Chip>
                  </SimpleGrid>
                </Chip.Group>
                <Button onClick={resetFilters} variant="outline" fullWidth size="sm" radius="md" color="dark">
                  Reset Filters
                </Button>
              </Stack>
            </Paper>
          </Popover.Dropdown>
        </Popover>
      )}
    </>
  )
}

export default NimplantOverviewCardList