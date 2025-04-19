import { useState, useEffect } from 'react';
import { Text, Group, Box, ActionIcon, Skeleton, Table, ThemeIcon, Tooltip, LoadingOverlay, Center, Badge, Paper } from '@mantine/core';
import { FaDownload, FaFolder } from 'react-icons/fa';
import { format } from 'date-fns';
import { formatBytes } from '../modules/nimplant';
import classes from '../styles/filelist.module.css';

// Interfaces
export interface FileItem {
  name: string;
  size: number;
  lastmodified: number;
  // Optional field for ImplantDownloadList
  nimplant?: string;
}

interface FileListComponentProps {
  files: FileItem[] | null;
  isLoading: boolean;
  onDownload: (e: React.MouseEvent, fileItem: FileItem) => void;
  onPreview: (fileName: string) => void;
  renderThumbnail: (fileName: string, fileId: string) => React.ReactNode;
  // Optional fields
  error?: any;
  fileIdField?: string; // The field used to identify the file (nimplant or id)
  extraInfoRender?: (fileItem: FileItem) => React.ReactNode;
  noFilesMessage?: string;
  emptyIcon?: React.ReactNode;
}

const FileListComponent = ({
  files,
  isLoading,
  onDownload,
  onPreview,
  renderThumbnail,
  error,
  fileIdField = 'nimplant',
  extraInfoRender,
  noFilesMessage = 'No files available',
  emptyIcon = <FaFolder size={24} />
}: FileListComponentProps) => {
  
  // Render a skeleton during loading
  if (isLoading) {
    return (
      <div className={classes.skeletonContainer}>
        {[1, 2, 3].map((i) => (
          <Paper key={i} withBorder p="md" radius="md" mb="sm" className={classes.skeletonItem}>
            <Group align="center" wrap="nowrap">
              <Skeleton height={60} width={60} radius="md" />
              <Box style={{ flex: 1 }}>
                <Skeleton height={20} width="80%" mb={8} />
                <Skeleton height={14} width="50%" />
              </Box>
              <Skeleton height={20} width={80} mr={20} />
              <Skeleton height={20} width={120} mr={10} />
              <Skeleton height={36} width={36} radius="xl" />
            </Group>
          </Paper>
        ))}
      </div>
    );
  }

  // Render a message if there are no files
  if (!files || files.length === 0) {
    return (
      <Box py="xl" ta="center" className={classes.emptyContainer}>
        <ThemeIcon size={60} radius="xl" color="gray" variant="light" mb="md">
          {emptyIcon}
        </ThemeIcon>
        <Text fw={500} size="lg">{noFilesMessage}</Text>
      </Box>
    );
  }

  return (
    <Box className={classes.fileListContainer}>
      <LoadingOverlay visible={isLoading} />
      
      {/* Fixed header */}
      <Paper withBorder p="xs" radius="md" mb="md" className={classes.tableHeader}>
        <Group justify="apart" wrap="nowrap">
          <Group style={{ width: '70px', justifyContent: 'center' }}>
            <Text fw={600} size="sm">Thumb</Text>
          </Group>
          <Text fw={600} size="sm" style={{ flex: 1 }}>Filename</Text>
          <Text fw={600} size="sm" style={{ width: '100px', textAlign: 'right' }}>Size</Text>
          <Text fw={600} size="sm" style={{ width: '170px', textAlign: 'center' }}>Downloaded</Text>
          <Text fw={600} size="sm" style={{ width: '80px', textAlign: 'center' }}>Action</Text>
        </Group>
      </Paper>
      
      {/* File list */}
      <div className={classes.fileList}>
        {files.map((file) => (
          <Paper 
            key={file.name}
            withBorder
            p="md" 
            radius="md"
            mb="sm"
            className={classes.fileItem}
            onClick={(e) => {
              e.preventDefault();
              onPreview(file.name);
            }}
            style={{ cursor: 'pointer' }}
          >
            <Group align="center" wrap="nowrap">
              <Box style={{ width: '70px', display: 'flex', justifyContent: 'center' }}>
                {renderThumbnail(file.name, file[fileIdField as keyof FileItem] as string)}
              </Box>
              
              <Box style={{ flex: 1 }}>
                <Text size="sm" fw={500} lineClamp={1}>{file.name}</Text>
                {extraInfoRender && extraInfoRender(file)}
              </Box>
              
              <Badge 
                variant="light" 
                color="dark" 
                style={{ width: '100px', textAlign: 'center' }}
              >
                {formatBytes(file.size)}
              </Badge>
              
              <Text size="sm" c="dimmed" style={{ width: '170px', textAlign: 'center' }}>
                {format(new Date(file.lastmodified * 1000), 'dd/MM/yyyy HH:mm')}
              </Text>
              
              <Box style={{ width: '80px', display: 'flex', justifyContent: 'center' }}>
                <Tooltip label="Download file" withArrow position="left">
                  <ActionIcon 
                    color="dark" 
                    variant="filled" 
                    onClick={(e) => {
                      e.stopPropagation(); // Stop propagation to prevent onPreview from being triggered
                      onDownload(e, file);
                    }}
                    radius="xl"
                    size="lg"
                  >
                    <FaDownload size="1rem" />
                  </ActionIcon>
                </Tooltip>
              </Box>
            </Group>
          </Paper>
        ))}
      </div>
    </Box>
  );
};

export default FileListComponent; 