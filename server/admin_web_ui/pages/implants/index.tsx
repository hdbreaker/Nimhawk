import { FaLaptopCode, FaEye, FaEyeSlash, FaTrash, FaSearch } from 'react-icons/fa'
import { Text, ScrollArea, Group, Card, Box, SimpleGrid, Flex, Button, SegmentedControl, Switch, Modal, Space, TextInput } from '@mantine/core'
import { useMediaQuery } from '@mantine/hooks'
import TitleBar from '../../components/TitleBar'
import type { NextPage } from 'next'
import NimplantOverviewCardList from '../../components/NimplantOverviewCardList'
import NimplantDrawer from '../../components/NimplantDrawer'
import { useState, useCallback, useEffect } from 'react'
import classes from '../../styles/liststyles.module.css'
import useSWR from 'swr'
import { endpoints, deleteNimplant } from '../../modules/nimplant'
import { swrFetcher } from '../../modules/apiFetcher'
import { useRouter } from 'next/router'

// Overview page for showing real-time information for all implants
const NimplantList: NextPage = () => {
  const router = useRouter()
  const largeScreen = useMediaQuery('(min-width: 800px)')
  const [selectedNimplant, setSelectedNimplant] = useState<string | null>(null)
  // State for implant filter - by default only show active ones
  const [showOnlyActive, setShowOnlyActive] = useState(true)
  // State for implant search
  const [searchTerm, setSearchTerm] = useState('')
  // State for deletion modal
  const [deleteModalOpen, setDeleteModalOpen] = useState(false)
  const [implantToDelete, setImplantToDelete] = useState<string | null>(null)
  
  // Get nimplants with SWR directly
  const { data: nimplants, mutate: refreshNimplants } = useSWR(
    endpoints.nimplants,
    swrFetcher,
    { refreshInterval: 2500 }
  )
  
  // Check URL parameters when loading the page
  useEffect(() => {
    const { delete: deleteGuid } = router.query
    if (deleteGuid && typeof deleteGuid === 'string') {
      setImplantToDelete(deleteGuid)
      setDeleteModalOpen(true)
    }
  }, [router.query])

  // Function to handle when an implant is killed
  const handleImplantKilled = useCallback(() => {
    // Refresh the list of implants immediately
    refreshNimplants()
    // Close the drawer
    setSelectedNimplant(null)
  }, [refreshNimplants])
  
  // Function to handle implant deletion
  const handleDeleteImplant = async () => {
    if (implantToDelete) {
      try {
        setDeleteModalOpen(false)
        // Clear URL parameter
        router.replace('/implants', undefined, { shallow: true })
        
        // Delete the implant
        const success = await deleteNimplant(implantToDelete)
        if (success) {
          // Update implant list
          refreshNimplants()
        }
      } catch (error) {
        console.error('Error deleting implant:', error)
      } finally {
        setImplantToDelete(null)
      }
    }
  }
  
  return (
    <>
      <TitleBar title="Implants" icon={<FaLaptopCode size='2em' />} />
      
      {/* Implant deletion modal */}
      <Modal
        opened={deleteModalOpen}
        onClose={() => {
          setDeleteModalOpen(false)
          router.replace('/implants', undefined, { shallow: true })
          setImplantToDelete(null)
        }}
        title={<b>Delete Implant!</b>}
        centered
      >
        Are you sure you want to delete this implant from the database? This action is irreversible.

        <Space h='xl' />

        <Button 
          onClick={handleDeleteImplant}
          leftSection={<FaTrash />} 
          style={{width: '100%'}}
          color="red"
        >
          Yes, permanently delete
        </Button>
      </Modal>
      
      <Box p="md" style={{ height: 'calc(100vh - 70px)', overflow: 'auto' }}>
        {/* Filters and search in the same row */}
        <Group justify="flex-end" mb="sm">
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
        </Group>
        
        <Card 
          withBorder 
          radius="md" 
          p={0}
          mb="lg"
          style={{
            overflow: 'hidden',
            borderColor: 'var(--mantine-color-gray-3)',
            boxShadow: '0 1px 3px rgba(0, 0, 0, 0.05)'
          }}
        >
          {/* Custom header */}
          <Box style={{ 
            display: 'flex', 
            padding: '16px 16px 16px',
            gap: '0',
            margin: '0', 
            alignItems: 'center',
            width: '100%',
            background: '#f6f8fa',
            borderBottom: '1px solid #e1e4e8',
            boxShadow: 'none'
          }}>
            {/* Column for Ping */}
            <Box style={{ width: '10%', textAlign: 'center' }}>
              <Text size="lg" fw={600} c="#24292e">Ping</Text>
            </Box>
            
            {/* Column for ID */}
            <Box style={{ width: '20%', paddingLeft: '0' }}>
              <Text size="lg" fw={600} c="#24292e">Implant ID</Text>
            </Box>
            
            {/* Column for System */}
            <Box style={{ width: '23%', paddingLeft: '0' }}>
              <Text size="lg" fw={600} c="#24292e">Operating System</Text>
            </Box>
            
            {/* Column for Network */}
            <Box style={{ width: '22%', paddingLeft: '0' }}>
              <Text size="lg" fw={600} c="#24292e">Network</Text>
            </Box>
            
            {/* Column for Workspace */}
            <Box style={{ width: '15%', paddingLeft: '0' }}>
              <Text size="lg" fw={600} c="#24292e">Workspace</Text>
            </Box>
            
            {/* Column for Actions */}
            <Box style={{ width: '10%', display: 'flex', justifyContent: 'center' }}>
              <Text size="lg" fw={600} c="#24292e">Action</Text>
            </Box>
          </Box>
          
          {/* Content - pass search to the component */}
          <NimplantOverviewCardList 
            onNimplantClick={setSelectedNimplant} 
            nimplantsData={Array.isArray(nimplants) ? nimplants : []}
            showOnlyActive={showOnlyActive}
            searchTerm={searchTerm}
            drawerOpen={selectedNimplant !== null}
          />
        </Card>
      </Box>

      <NimplantDrawer 
        opened={selectedNimplant !== null} 
        onClose={() => setSelectedNimplant(null)} 
        guid={selectedNimplant || ''}
        onKilled={handleImplantKilled}
      />
    </>
  )
}
export default NimplantList