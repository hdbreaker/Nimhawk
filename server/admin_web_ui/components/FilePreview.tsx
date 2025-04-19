import { useState, useEffect } from 'react';
import { Text, Image, Box, Paper, Loader, Group, Code, ScrollArea, Stack, Center, useMantineTheme, rem, Button, ActionIcon, Skeleton, Tooltip, Card } from '@mantine/core';
import { endpoints } from '../modules/nimplant';
import { api } from '../modules/apiFetcher';
import { FaFilePdf, FaFileAlt, FaFileImage, FaFileCode, FaFile, FaDownload, FaDatabase, FaFileExcel, FaFileWord, FaFileArchive, FaFileCsv } from 'react-icons/fa';
import { notifications } from '@mantine/notifications';

// Component to render the thumbnail according to the file type
const FileThumbnail = ({ fileName, fileType, imageBlob, pdfBlob, fileContent }: {
  fileName: string;
  fileType: string;
  imageBlob: string | null;
  pdfBlob: string | null;
  fileContent: string | null;
}) => {
  const theme = useMantineTheme();
  const extension = fileName.split('.').pop()?.toLowerCase() || '';
  
  // Render according to the file type
  switch (fileType) {
    case 'image':
      return (
        <Box 
          style={{ 
            width: '100%', 
            height: '180px', 
            border: '1px solid var(--mantine-color-gray-3)',
            borderRadius: '4px',
            overflow: 'hidden',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '5px',
            background: '#f9f9f9'
          }}
        >
          {imageBlob ? (
            <img 
              src={imageBlob}
              alt={fileName}
              style={{ 
                maxWidth: '100%', 
                maxHeight: '100%', 
                objectFit: 'contain' 
              }}
            />
          ) : (
            <Skeleton height={160} width="90%" />
          )}
        </Box>
      );
      
    case 'pdf':
      // For PDFs, show an icon with the extension
      return (
        <Box style={{ textAlign: 'center', width: '100%' }}>
          <Paper
            style={{
              width: '100%',
              height: '180px',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              background: '#f9f9f9',
              border: '1px solid var(--mantine-color-gray-3)',
              borderRadius: '4px',
            }}
          >
            <FaFilePdf size={64} color="#e74c3c" />
            <Text size="md" mt={10} fw={500}>.PDF</Text>
          </Paper>
        </Box>
      );
      
    case 'text':
      // For text files, show the first lines
      return (
        <Paper
          style={{
            width: '100%',
            height: '180px',
            padding: '10px',
            overflow: 'hidden',
            border: '1px solid var(--mantine-color-gray-3)',
            borderRadius: '4px',
            background: '#f9f9f9',
          }}
        >
          <Text size="xs" style={{ fontFamily: 'monospace', fontSize: '10px', lineHeight: '1.2' }}>
            {fileContent?.substring(0, 500) || 'No preview available'}
          </Text>
        </Paper>
      );
      
    default:
      // Specific icon according to extension
      let IconComponent = FaFile;
      let iconColor = theme.colors.gray[5];
      let extensionLabel = extension.toUpperCase();
      
      // Determine icon and color according to extension
      if (['js', 'ts', 'jsx', 'tsx'].includes(extension)) {
        IconComponent = FaFileCode;
        iconColor = "#f1c40f";
      } else if (['html', 'xml', 'css'].includes(extension)) {
        IconComponent = FaFileCode;
        iconColor = "#3498db";
      } else if (['json', 'yaml', 'yml'].includes(extension)) {
        IconComponent = FaFileCode;
        iconColor = "#2ecc71";
      } else if (['py', 'rb', 'java', 'c', 'cpp', 'cs'].includes(extension)) {
        IconComponent = FaFileCode;
        iconColor = "#9b59b6";
      } else if (['db', 'sqlite', 'mdb'].includes(extension)) {
        IconComponent = FaDatabase;
        iconColor = "#34495e";
      } else if (['xlsx', 'xls', 'csv'].includes(extension)) {
        IconComponent = extension === 'csv' ? FaFileCsv : FaFileExcel;
        iconColor = "#27ae60";
      } else if (['docx', 'doc', 'rtf'].includes(extension)) {
        IconComponent = FaFileWord;
        iconColor = "#2980b9";
      } else if (['zip', 'rar', '7z', 'tar', 'gz'].includes(extension)) {
        IconComponent = FaFileArchive;
        iconColor = "#795548";
      }
      
      return (
        <Box style={{ textAlign: 'center', width: '100%' }}>
          <Paper
            style={{
              width: '100%',
              height: '180px',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              background: '#f9f9f9',
              border: '1px solid var(--mantine-color-gray-3)',
              borderRadius: '4px',
            }}
          >
            <IconComponent size={64} color={iconColor} />
            <Text size="md" mt={10} fw={500}>.{extensionLabel}</Text>
          </Paper>
        </Box>
      );
  }
};

interface FilePreviewProps {
  fileName: string;
  implantGuid?: string;
}

const FilePreview = ({ fileName, implantGuid }: FilePreviewProps) => {
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [fileContent, setFileContent] = useState<string | null>(null);
  const [fileType, setFileType] = useState<string>('unknown');
  const [fileUrl, setFileUrl] = useState<string>('');
  const [imageBlob, setImageBlob] = useState<string | null>(null);
  const [pdfBlob, setPdfBlob] = useState<string | null>(null);
  const theme = useMantineTheme();

  useEffect(() => {
    const fetchFileContent = async () => {
      setLoading(true);
      setError(null);
      
      try {
    // Determine file type based on extension
      const extension = fileName.split('.').pop()?.toLowerCase() || '';
        const isImage = ['jpg', 'jpeg', 'png', 'gif', 'svg', 'webp', 'bmp'].includes(extension);
        const isPdf = extension === 'pdf';
        const isText = ['txt', 'log', 'json', 'csv', 'xml', 'html', 'md', 'js', 'ts', 'py', 'sh', 'bat', 'ps1', 'config', 'ini', 'conf', 'c', 'cpp', 'h', 'cs', 'java', 'json', 'yaml', 'yml'].includes(extension);
        
        console.log("FilePreview: Loading file with preview=true parameter");
        
        // Construct correct URL based on whether it's an implant file or not
        let baseUrl;
        if (implantGuid) {
          baseUrl = `${endpoints.downloads}/${implantGuid}/${fileName}`;
        } else {
          baseUrl = endpoints.getDownload(fileName);
        }
        
        // Add the preview=true parameter using URLSearchParams
        const url = new URL(baseUrl, window.location.origin);
        url.searchParams.set('preview', 'true');
        
        console.log("FilePreview: Request URL:", url.toString());
        
        // Store base URL for download button (without the preview parameter)
        if (implantGuid) {
          setFileUrl(`${endpoints.downloads}/${implantGuid}/${fileName}`);
        } else {
          setFileUrl(endpoints.getDownload(fileName));
        }
        
        // Get the auth token
        const token = localStorage.getItem('auth_token');
        
        // Set up authorization headers
        const headers: HeadersInit = {
          'Content-Type': 'application/json',
        };
        
        if (token) {
          headers['Authorization'] = `Bearer ${token}`;
        }

        if (isImage) {
          setFileType('image');
          // For images, load the blob to avoid authentication problems
          const response = await fetch(url.toString(), {
            method: 'GET',
            headers,
            credentials: 'include',
          });
          
          if (!response.ok) {
            throw new Error(`Error ${response.status}: ${response.statusText}`);
          }
          
          const blob = await response.blob();
          const objectUrl = URL.createObjectURL(blob);
          setImageBlob(objectUrl);
          setLoading(false);
          return;
        } else if (isPdf) {
          setFileType('pdf');
          // For PDFs, load the blob to avoid authentication problems
          const response = await fetch(url.toString(), {
            method: 'GET',
            headers,
            credentials: 'include',
          });
          
          if (!response.ok) {
            throw new Error(`Error ${response.status}: ${response.statusText}`);
          }
          
          const blob = await response.blob();
          const objectUrl = URL.createObjectURL(blob);
          setPdfBlob(objectUrl);
          setLoading(false);
          return;
        } else if (!isText) {
          // Binary or unknown file type
          setFileType('binary');
          setError('This file type cannot be previewed');
          setLoading(false);
          return;
        }
        
        // For text files, get the content
        const response = await fetch(url.toString(), {
          method: 'GET',
          headers,
          credentials: 'include',
        });
        
        if (!response.ok) {
          throw new Error(`Error ${response.status}: ${response.statusText}`);
        }
        
        // Get the content as text for preview
        const text = await response.text();
        setFileContent(text);
        setFileType('text');
      } catch (error: any) {
        console.error('Error loading file:', error);
        setError(`Error loading file: ${error.message}`);
      } finally {
        setLoading(false);
      }
    };
    
    if (fileName) {
      fetchFileContent();
    }
    
    // Clean up object URLs when unmounting
    return () => {
      if (imageBlob) {
        URL.revokeObjectURL(imageBlob);
      }
      if (pdfBlob) {
        URL.revokeObjectURL(pdfBlob);
      }
    };
  }, [fileName, implantGuid]);

  // Function to download the file
  const handleDownload = () => {
    // Get the auth token
    const token = localStorage.getItem('auth_token');
    
    // Set up authorization headers
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
    };
    
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    
    // Show loading notification
    notifications.show({
      id: 'file-downloading',
      loading: true,
      title: 'Downloading file',
      message: fileName,
      color: 'blue',
      autoClose: false,
    });
    
    // Download with fetch and auth
    fetch(fileUrl, {
        method: 'GET',
        headers,
      credentials: 'include',
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
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      
      notifications.update({
        id: 'file-downloading',
        title: 'Download completed',
        message: fileName,
        color: 'green',
        loading: false,
        autoClose: 3000,
      });
    })
    .catch(error => {
      console.error('Download error:', error);
      notifications.update({
        id: 'file-downloading',
        title: 'Download error',
        message: `Error: ${error.message}`,
        color: 'red',
        loading: false,
        autoClose: 5000,
      });
    });
  };

  // Render content based on file type
  const renderContent = () => {
    if (loading) {
      return (
        <Center p="xl">
          <Skeleton height={300} width="100%" />
        </Center>
      );
    }
    
    if (error) {
      return (
        <Box p="md" style={{ textAlign: 'center' }}>
          <Text color="red" size="lg">{error}</Text>
          <Text size="sm" color="dimmed" mt="md">
            This file cannot be previewed, but you can download it using the download button.
        </Text>
        </Box>
      );
    }
    
    switch (fileType) {
      case 'image':
        return (
          <Box style={{ textAlign: 'center', padding: '20px' }}>
            {imageBlob && (
              <img 
                src={imageBlob}
              alt={fileName}
              style={{ maxWidth: '100%', maxHeight: '70vh' }}
            />
            )}
          </Box>
        );
        
      case 'pdf':
        return (
          <Box style={{ height: '70vh', width: '100%' }}>
            {pdfBlob && (
              <iframe 
                src={pdfBlob}
                width="100%" 
                height="100%" 
                style={{ border: 'none' }}
                title={fileName}
              />
            )}
          </Box>
        );
        
      case 'binary':
        return (
          <Box p="md" style={{ textAlign: 'center' }}>
            <Text color="dimmed" size="lg">
              This file cannot be previewed (binary file).
            </Text>
          </Box>
        );
        
      case 'text':
        return (
          <ScrollArea h={500} scrollbarSize={6} style={{ width: '100%' }}>
            <Box p="md" style={{ fontFamily: 'monospace', whiteSpace: 'pre-wrap', fontSize: '14px' }}>
              {fileContent || 'Could not load file content.'}
            </Box>
          </ScrollArea>
        );
        
      default:
        return (
          <Stack align="center" justify="center" py="xl">
            <FaFile size={rem(64)} color={theme.colors.gray[5]} />
            <Text fw={500} mt="md">Preview not available</Text>
            <Text size="sm" c="dimmed">This file type cannot be previewed</Text>
          </Stack>
        );
    }
  };

  return (
    <Box>
      {renderContent()}
    </Box>
  );
};

// Export the download button component for use in the modal header
export function DownloadActionButton({ onClick }: { onClick: () => void }) {
  return (
    <Tooltip label="Descargar archivo" withArrow position="left">
  <Button 
    variant="outline"
        color="gray"
        size="sm"
        leftSection={<FaDownload size="0.9rem" />}
    onClick={onClick}
    radius="md"
        style={{ 
          border: '1px solid var(--mantine-color-gray-2)',
          backgroundColor: '#f9f9f9',
          color: 'var(--mantine-color-gray-7)'
    }}
  >
    Download
  </Button>
    </Tooltip>
);
}

export default FilePreview; 