import { useState, useEffect } from 'react';
import { Box, Skeleton, useMantineTheme } from '@mantine/core';
import NextImage from 'next/image';
import { FaFilePdf, FaFileAlt, FaFileImage, FaFileCode, FaFile, FaDatabase, FaFileExcel, FaFileWord, FaFileArchive, FaFileCsv } from 'react-icons/fa';
import { endpoints } from '../modules/nimplant';

interface FileTypeIconProps {
  fileName: string;
  fileId: string;
  isImplant?: boolean;
}

const FileTypeIcon = ({ fileName, fileId, isImplant = true }: FileTypeIconProps) => {
  const theme = useMantineTheme();
  const extension = fileName.split('.').pop()?.toLowerCase() || '';
  const isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].includes(extension);
  const [imgError, setImgError] = useState(false);
  const [imageLoading, setImageLoading] = useState(isImage);
  const [imageSrc, setImageSrc] = useState<string | null>(null);
  
  // Effect to load the image with appropriate authentication
  useEffect(() => {
    if (isImage && !imgError) {
      const loadImage = async () => {
        try {
          // Get token from localStorage
          const token = localStorage.getItem('auth_token');
          
          // Create appropriate headers
          const headers: HeadersInit = {
            'Content-Type': 'application/json',
          };
          
          if (token) {
            headers['Authorization'] = `Bearer ${token}`;
          }
          
          // Determine the image URL
          let url;
          if (isImplant) {
            // For ImplantDownloadList, we use the implant guid
            url = `${endpoints.downloads}/${fileId}/${fileName}`;
          } else {
            // For GlobalDownloadList
            url = endpoints.getDownload(fileName);
          }
          
          // Load the image using fetch to handle authentication
          const response = await fetch(url, {
            method: 'GET',
            headers,
            credentials: 'include'
          });
          
          if (!response.ok) {
            throw new Error(`Error ${response.status}: ${response.statusText}`);
          }
          
          // Convert to blob and create URL
          const blob = await response.blob();
          const objectUrl = URL.createObjectURL(blob);
          setImageSrc(objectUrl);
          setImageLoading(false);
        } catch (error) {
          console.error('Error loading thumbnail:', error);
          setImgError(true);
          setImageLoading(false);
        }
      };
      
      loadImage();
      
      // Clean up URL when unmounting
      return () => {
        if (imageSrc) {
          URL.revokeObjectURL(imageSrc);
        }
      };
    }
  }, [fileName, fileId, isImage, imgError, isImplant]);
  
  // For images, show a real thumbnail
  if (isImage && !imgError) {
    return (
      <Box 
        style={{ 
          width: '60px',
          height: '60px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          border: '1px solid var(--mantine-color-gray-2)',
          borderRadius: '4px',
          overflow: 'hidden',
          backgroundColor: '#f8f9fa',
          position: 'relative'
        }}
      >
        {imageLoading && (
          <Box style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Skeleton width={50} height={50} radius="sm" />
          </Box>
        )}
        {imageSrc && !imageLoading && (
          <NextImage 
            src={imageSrc}
            alt={fileName}
            width={60}
            height={60}
            style={{ 
              width: '100%', 
              height: '100%', 
              objectFit: 'contain'
            }}
            onError={() => {
              setImgError(true);
              setImageLoading(false);
            }}
            unoptimized
          />
        )}
      </Box>
    );
  }
  
  // For other file types, show an icon
  let IconComponent = FaFile;
  let iconColor = '#8c8c8c';
  
    // Determine icon and color based on extension
  if (extension === 'pdf') {
    IconComponent = FaFilePdf;
    iconColor = "#e74c3c";
  } else if (['js', 'ts', 'jsx', 'tsx'].includes(extension)) {
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
  } else if (['txt', 'log', 'md', 'ini', 'config', 'conf'].includes(extension)) {
    IconComponent = FaFileAlt;
    iconColor = "#7f8c8d";
  } else if (isImage) {
    IconComponent = FaFileImage;
    iconColor = "#3498db";
  }
  
  return (
    <Box 
      style={{ 
        width: '60px',
        height: '60px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        border: '1px solid var(--mantine-color-gray-2)',
        borderRadius: '4px',
        backgroundColor: '#f8f9fa'
      }}
    >
      <IconComponent size={30} color={iconColor} />
    </Box>
  );
};

export default FileTypeIcon; 