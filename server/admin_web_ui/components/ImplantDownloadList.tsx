import { useState, useEffect } from 'react';
import { Text, Group, Box, Button, ActionIcon, Modal, Title, Badge } from '@mantine/core';
import { FaChevronLeft, FaChevronRight, FaDownload } from 'react-icons/fa';
import useSWR from 'swr';
import { endpoints } from '../modules/nimplant';
import { swrFetcher } from '../modules/apiFetcher';
import { format } from 'date-fns';
import FilePreview, { DownloadActionButton } from './FilePreview';
import { notifications } from '@mantine/notifications';
import { useMediaQuery } from '@mantine/hooks';
import FileListComponent, { FileItem } from './FileListComponent';
import FileTypeIcon from './FileTypeIcon';

// Simple function to replace internationalization
// This function only returns the original text without translating
const t = (text: string) => text;

interface ImplantDownloadListProps {
  guid: string;
}

function ImplantDownloadList({ guid }: ImplantDownloadListProps) {
  const largeScreen = useMediaQuery('(min-width: 800px)');
  const [previewFile, setPreviewFile] = useState<string | null>(null);
  const [previewModalOpen, setPreviewModalOpen] = useState(false);
  const [currentFileIndex, setCurrentFileIndex] = useState<number>(-1);

  // Get the download data with SWR
  const { data, error, isValidating, mutate } = useSWR<FileItem[]>(
    endpoints.downloads + `?guid=${guid}`,
    swrFetcher,
    { refreshInterval: 10000 }
  );

  // Previous navigation
  const navigatePrevious = () => {
    if (data && data.length > 0 && currentFileIndex > 0) {
      const prevIndex = currentFileIndex - 1;
      setCurrentFileIndex(prevIndex);
      setPreviewFile(data[prevIndex].name);
    }
  };

  // Next navigation
  const navigateNext = () => {
    if (data && data.length > 0 && currentFileIndex < data.length - 1) {
      const nextIndex = currentFileIndex + 1;
      setCurrentFileIndex(nextIndex);
      setPreviewFile(data[nextIndex].name);
    }
  };

  // Keyboard handling for navigation
  const handleKeyDown = (e: KeyboardEvent) => {
    if (previewModalOpen) {
      if (e.key === 'ArrowLeft') {
        navigatePrevious();
      } else if (e.key === 'ArrowRight') {
        navigateNext();
      }
    }
  };

  // Add and remove event listener for keyboard navigation
  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [previewModalOpen, currentFileIndex, data]);

  // Download button handler
  const handleDownload = (e: React.MouseEvent, file: FileItem) => {
    e.stopPropagation(); // Prevent event propagation when downloading
    
    try {
      notifications.show({
        id: 'downloading',
        loading: true,
        title: 'Descargando archivo',
        message: `${file.name}`,
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
      
      // Use programmatic fetch with correct authorization header and endpoint
      fetch(`${endpoints.downloads}/${guid}/${file.name}`, { 
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
        // Create object URL and activate download
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = file.name;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
        
        notifications.update({
          id: 'downloading',
          title: 'Descarga completada',
          message: `${file.name}`,
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
        message: `Could not download ${file.name}`,
        color: 'red',
        loading: false,
        autoClose: 5000,
      });
    }
  };

  // Function to download directly from the preview modal
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
        title: 'Descargando archivo',
        message: previewFile,
        color: 'blue',
        autoClose: false,
      });
      
      // Use programmatic fetch with correct authorization header and endpoint
      fetch(`${endpoints.downloads}/${guid}/${previewFile}`, { 
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
        // Create object URL and activate download
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
          title: 'Descarga completada',
          message: previewFile,
          color: 'green',
          loading: false,
          autoClose: 3000,
        });
      })
      .catch(error => {
        console.error('Error de descarga:', error);
        notifications.update({
          id: 'modal-downloading',
          title: 'Error de descarga',
          message: `Error: ${error.message}`,
          color: 'red',
          loading: false,
          autoClose: 5000,
        });
      });
    }
  };

  // Function to open the preview
  const handlePreview = (fileName: string) => {
    if (data) {
      const index = data.findIndex((file) => file.name === fileName);
      setCurrentFileIndex(index);
      setPreviewFile(fileName);
      setPreviewModalOpen(true);
    }
  };

  // Function to render the thumbnail
  const renderThumbnail = (fileName: string, fileId: string) => {
    return <FileTypeIcon fileName={fileName} fileId={fileId} isImplant={true} />;
  };

  // Function to render additional information
  const renderExtraInfo = (file: FileItem) => {
    return (
      <Text size="xs" c="dimmed">{t('Implant ID')}: {guid}</Text>
    );
  };

  return (
    <>
      <FileListComponent 
        files={data || null}
        isLoading={!data && !error}
        onDownload={handleDownload}
        onPreview={handlePreview}
        renderThumbnail={renderThumbnail}
        error={error}
        fileIdField="nimplant"
        extraInfoRender={renderExtraInfo}
        noFilesMessage={t('No files downloaded from this implant.\nFiles downloaded will appear in this section.')}
      />
      
      {/* Only show FilePreview when an file is selected */}
      {previewModalOpen && previewFile && (
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
              paddingRight: '10px'
            },
            close: {
              position: 'static',
              margin: '0 0 0 15px'
            },
            body: {
              paddingBottom: '50px'
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
            right: '38px',
            zIndex: 1000,
            gap: '4px',
            justifyContent: 'flex-end'
          }}>
            {previewFile && <DownloadActionButton onClick={handleModalDownload} />}
          </Group>

          {/* Navigation buttons */}
          {data && data.length > 1 && (
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

              {currentFileIndex < data.length - 1 && (
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

          <FilePreview
            fileName={previewFile}
            implantGuid={guid}
          />
          
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
              {currentFileIndex + 1} / {data?.length || 0}
            </Badge>
          </Box>
        </Modal>
      )}
    </>
  );
}

export default ImplantDownloadList; 