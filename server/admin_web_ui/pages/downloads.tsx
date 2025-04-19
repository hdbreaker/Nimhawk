import { FaDownload, FaCloud, FaHistory } from 'react-icons/fa'
import { Card, Box, Title, Text, Tabs, Divider } from '@mantine/core'
import { useMediaQuery } from '@mantine/hooks'
import DownloadList from '../components/DownloadList'
import GlobalFileTransfersList from '../components/GlobalFileTransfersList'
import TitleBar from '../components/TitleBar'
import type { NextPage } from 'next'

const Downloads: NextPage = () => {
  const largeScreen = useMediaQuery('(min-width: 800px)')

  return (
    <>
      <TitleBar title="Downloads" icon={<FaDownload size='2em' />} />
      <Box p="md" style={{ height: 'calc(100vh - 70px)', overflow: 'auto' }}>
        {/* Header with title and description */}
        <Box mb="md">
          <Title order={3}>File Downloads</Title>
          <Text c="dimmed" size="sm">View and download files retrieved from implants</Text>
        </Box>
        
        <Tabs defaultValue="files">
          <Tabs.List mb="md">
            <Tabs.Tab value="files" leftSection={<FaCloud size={14} />}>Files</Tabs.Tab>
            <Tabs.Tab value="history" leftSection={<FaHistory size={14} />}>Transfer History</Tabs.Tab>
          </Tabs.List>
          
          <Tabs.Panel value="files">
            <Card 
              withBorder 
              radius="md" 
              p="md"
              mb="lg"
              style={{
                overflow: 'hidden',
                borderColor: 'var(--mantine-color-gray-3)',
                boxShadow: '0 1px 3px rgba(0, 0, 0, 0.05)'
              }}
            >
              <DownloadList />
            </Card>
          </Tabs.Panel>
          
          <Tabs.Panel value="history">
            <Card 
              withBorder 
              radius="md" 
              p="md"
              mb="lg"
              style={{
                overflow: 'hidden',
                borderColor: 'var(--mantine-color-gray-3)',
                boxShadow: '0 1px 3px rgba(0, 0, 0, 0.05)'
              }}
            >
              <Box mb="md">
                <Title order={4}>File Transfer History</Title>
                <Text size="sm" c="dimmed">All file operations including uploads, downloads, and views</Text>
              </Box>
              <GlobalFileTransfersList limit={100} />
            </Card>
          </Tabs.Panel>
        </Tabs>
      </Box>
    </>
  )
}
export default Downloads