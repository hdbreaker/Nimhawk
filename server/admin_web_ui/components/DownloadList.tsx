import { FaRegMeh, FaDownload, FaChevronLeft, FaChevronRight } from 'react-icons/fa'
import { formatBytes, formatTimestamp, getDownloads, getNimplants, endpoints } from '../modules/nimplant'
import { Text, Group, Stack, ActionIcon, Tooltip, Modal, Title, Badge, Box, Button } from '@mantine/core'
import { notifications } from '@mantine/notifications'
import { useMediaQuery } from '@mantine/hooks'
import { useState, useEffect, useCallback } from 'react'
import FilePreview, { DownloadActionButton } from './FilePreview'
import FileListComponent, { FileItem } from './FileListComponent'
import FileTypeIcon from './FileTypeIcon'

function DownloadList() {
  const { downloads, downloadsLoading, downloadsError } = getDownloads()
  const { nimplants, nimplantsLoading, nimplantsError } = getNimplants()
  const largeScreen = useMediaQuery('(min-width: 800px)')
  const [previewFile, setPreviewFile] = useState<string | null>(null)
  const [previewModalOpen, setPreviewModalOpen] = useState(false)
  const [currentFileIndex, setCurrentFileIndex] = useState<number>(-1)

  // Cast downloads to the correct type
  const downloadFiles = downloads as FileItem[] || []

  // Check if modal should be open
  useEffect(() => {
    console.log('Modal state:', { previewModalOpen, previewFile, currentFileIndex })
  }, [previewModalOpen, previewFile, currentFileIndex])

  // Define all callbacks at the component's top level to maintain hook consistency
  // Navigate to previous file
  const navigatePrevious = useCallback(() => {
    if (downloadFiles && downloadFiles.length > 0 && currentFileIndex > 0) {
      const prevIndex = currentFileIndex - 1;
      setCurrentFileIndex(prevIndex);
      setPreviewFile(downloadFiles[prevIndex].name);
    }
  }, [currentFileIndex, downloadFiles]);

  // Navigate to next file
  const navigateNext = useCallback(() => {
    if (downloadFiles && downloadFiles.length > 0 && currentFileIndex < downloadFiles.length - 1) {
      const nextIndex = currentFileIndex + 1;
      setCurrentFileIndex(nextIndex);
      setPreviewFile(downloadFiles[nextIndex].name);
    }
  }, [currentFileIndex, downloadFiles]);

  // Handle keyboard navigation
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (previewModalOpen) {
      if (e.key === 'ArrowLeft') {
        navigatePrevious();
      } else if (e.key === 'ArrowRight') {
        navigateNext();
      }
    }
  }, [previewModalOpen, navigatePrevious, navigateNext]);

  // Add and remove event listener for keyboard navigation
  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [handleKeyDown]);

  // Handle file download
  const handleDownload = (e: React.MouseEvent, fileItem: FileItem) => {
    e.stopPropagation(); // Prevent event propagation when clicking download
    
    try {
      notifications.show({
        id: 'downloading',
        loading: true,
        title: 'Downloading file',
        message: `${fileItem.name}`,
        color: 'blue',
        autoClose: false,
      });

      // Get token from localStorage
      const token = localStorage.getItem('auth_token');
      
      // Create appropriate headers
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };
      
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      // Use a URL that does not include the preview parameter to register as a download
      let downloadUrl = '';
      if (fileItem.nimplant) {
        downloadUrl = `${endpoints.downloads}/${fileItem.nimplant}/${fileItem.name}`;
      } else {
        downloadUrl = endpoints.getDownload(fileItem.name);
      }
      
      // Use programmatic fetch with authorization header - ensures explicit downloads
      fetch(downloadUrl, { 
        method: 'GET',
        headers,
        credentials: 'include'
      })
      .then(response => {
        if (!response.ok) {
          throw new Error(`Error ${response.status}: ${response.statusText}`);
        }
        return response.blob();
      })
      .then(blob => {
        // Create object URL and trigger download
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = fileItem.name;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
        
        notifications.update({
          id: 'downloading',
          title: 'Download complete',
          message: `${fileItem.name}`,
          color: 'green',
          loading: false,
          autoClose: 3000,
        });
      })
      .catch(error => {
        console.error('Download error:', error);
        notifications.update({
          id: 'downloading',
          title: 'Download error',
          message: `Error: ${error.message}`,
          color: 'red',
          loading: false,
          autoClose: 5000,
        });
      });
    } catch (error) {
      notifications.update({
        id: 'downloading',
        title: 'Download error',
        message: `Could not download ${fileItem.name}`,
        color: 'red',
        loading: false,
        autoClose: 5000,
      });
    }
  };

  // Function to directly download from preview modal
  const handleModalDownload = () => {
    if (previewFile) {
      // Get token from localStorage
      const token = localStorage.getItem('auth_token');
      
      // Create appropriate headers
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };
      
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      
      // Show loading notification
      notifications.show({
        id: 'modal-downloading',
        loading: true,
        title: 'Downloading file',
        message: previewFile,
        color: 'blue',
        autoClose: false,
      });
      
      // Build URL without the preview parameter to register as a download
      let downloadUrl = '';
      if (downloadFiles && currentFileIndex >= 0 && downloadFiles[currentFileIndex]?.nimplant) {
        // If it has an associated implant, use the implant download URL
        downloadUrl = `${endpoints.downloads}/${downloadFiles[currentFileIndex].nimplant}/${previewFile}`;
      } else {
        // For general files, use the normal download URL
        downloadUrl = endpoints.getDownload(previewFile);
      }
      
      // Use programmatic fetch with authorization header - without preview parameter
      fetch(downloadUrl, { 
        method: 'GET',
        headers,
        credentials: 'include'
      })
      .then(response => {
        if (!response.ok) {
          throw new Error(`Error ${response.status}: ${response.statusText}`);
        }
        return response.blob();
      })
      .then(blob => {
        // Create object URL and trigger download
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = previewFile;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
        
        notifications.update({
          id: 'modal-downloading',
          title: 'Download complete',
          message: previewFile,
          color: 'green',
          loading: false,
          autoClose: 3000,
        });
      })
      .catch(error => {
        console.error('Download error:', error);
        notifications.update({
          id: 'modal-downloading',
          title: 'Download error',
          message: `Error: ${error.message}`,
          color: 'red',
          loading: false,
          autoClose: 5000,
        });
      });
    }
  };

  // Function to open the preview
  const handlePreview = (name: string) => {
    console.log("Opening preview for:", name);
    const file = downloadFiles.find(download => download.name === name);
    if (file) {
      const index = downloadFiles.findIndex((download) => download.name === name);
      setCurrentFileIndex(index);
      setPreviewFile(name);
      setPreviewModalOpen(true);
    }
  };

  // Function to render thumbnails
  const renderThumbnail = (fileName: string, fileId: string) => {
    return <FileTypeIcon fileName={fileName} fileId={fileId} isImplant={false} />;
  };

  // Function to render host information for each file
  const renderExtraInfo = (file: FileItem) => {
    const nimplantsList = nimplants as any[] || [];
    const implant = nimplantsList.find((nimplant) => nimplant.guid === file.nimplant);
    if (implant) {
      return (
        <Text size="xs" c="dimmed">
          {implant.username}@{implant.hostname}
        </Text>
      );
    }
    return null;
  };

  // Check data length and return placeholder if no downloads are present
  if (!downloadFiles || downloadFiles.length === 0) {
    return (
      <Group py="xl" style={{ marginLeft: '20px', color: 'var(--mantine-color-gray-5)' }}>
        <FaRegMeh size='1.5em' />
        <Text size="md">Nothing here...</Text>
      </Group>
    );
  }

  // Otherwise render an overview of downloads
  return (
    <>
      {/* File preview modal */}
      <Modal
        opened={previewModalOpen}
        onClose={() => setPreviewModalOpen(false)}
        size={largeScreen ? "70%" : "100%"}
        padding="md"
        withCloseButton={true}
        centered
        overlayProps={{
          opacity: 0.55,
          blur: 3,
        }}
        styles={{
          header: {
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            height: '60px',
            position: 'relative',
            paddingRight: '10px' // Reduce right padding to accommodate the buttons
          },
          close: {
            position: 'static', // Change to static to keep it in the natural flow
            margin: '0 0 0 15px' // Increase left margin to separate from download button
          },
          body: {
            paddingBottom: '50px' // Add space for the page counter at the bottom
          }
        }}
        title={
          <Group style={{ alignItems: 'center', height: '100%', gap: '8px' }}>
            <Title order={4} style={{ lineHeight: 1, margin: 0 }}>{previewFile}</Title>
          </Group>
        }
      >
        {/* Display header actions as a group */}
        <Group style={{ 
          position: 'absolute',
          top: '15px',
          right: '38px', // Increase right distance to move away from X button
          zIndex: 1000,
          gap: '4px',
          justifyContent: 'flex-end'
        }}>
          {previewFile && <DownloadActionButton onClick={handleModalDownload} />}
        </Group>

        {/* Navigation buttons */}
        {downloadFiles && downloadFiles.length > 1 && (
          <>
            {currentFileIndex > 0 && (
              <ActionIcon
                variant="light"
                color="dark"
                size="xl"
                radius="xl"
                style={{
                  position: 'absolute',
                  left: '20px',
                  top: '50%',
                  transform: 'translateY(-50%)',
                  zIndex: 1000,
                  boxShadow: '0 2px 10px rgba(0,0,0,0.2)'
                }}
                onClick={navigatePrevious}
              >
                <FaChevronLeft size="1.5rem" />
              </ActionIcon>
            )}

            {currentFileIndex < downloadFiles.length - 1 && (
              <ActionIcon
                variant="light"
                color="dark"
                size="xl"
                radius="xl"
                style={{
                  position: 'absolute',
                  right: '20px',
                  top: '50%',
                  transform: 'translateY(-50%)',
                  zIndex: 1000,
                  boxShadow: '0 2px 10px rgba(0,0,0,0.2)'
                }}
                onClick={navigateNext}
              >
                <FaChevronRight size="1.5rem" />
              </ActionIcon>
            )}
          </>
        )}

        {previewFile && 
          <FilePreview 
            fileName={previewFile} 
            implantGuid={downloadFiles && currentFileIndex >= 0 ? 
              downloadFiles[currentFileIndex]?.nimplant : undefined}
          />
        }
        
        {/* File counter at the bottom center */}
        <Box 
          style={{ 
            position: 'absolute', 
            bottom: '15px', 
            left: '50%', 
            transform: 'translateX(-50%)',
            zIndex: 999
          }}
        >
          <Badge 
            variant="filled" 
            color="dark" 
            size="lg" 
            radius="md"
            styles={{
              root: {
                fontWeight: 600,
                textTransform: 'none',
                padding: '0 15px',
                height: '30px',
                boxShadow: '0 2px 5px rgba(0,0,0,0.15)',
                fontSize: '14px',
                minWidth: '70px',
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center'
              }
            }}
          >
            {currentFileIndex + 1} / {downloadFiles.length}
          </Badge>
        </Box>
      </Modal>

      {/* File list */}
      <FileListComponent 
        files={downloadFiles}
        isLoading={downloadsLoading}
        onDownload={handleDownload}
        onPreview={handlePreview}
        renderThumbnail={renderThumbnail}
        error={downloadsError}
        fileIdField="nimplant"
        extraInfoRender={renderExtraInfo}
        noFilesMessage="Nothing here..."
      />
    </>
  )
}

export default DownloadList