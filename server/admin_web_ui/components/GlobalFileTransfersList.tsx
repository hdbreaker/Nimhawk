import { useState } from 'react';
import { Text, Table, Group, Badge, Loader, Center } from '@mantine/core';
import useSWR from 'swr';
import { endpoints } from '../modules/nimplant';
import { swrFetcher } from '../modules/apiFetcher';
import { format } from 'date-fns';

// Simple function to replace internationalization
const t = (text: string) => text;

interface FileTransferItem {
  id: number;
  nimplantGuid: string;
  filename: string;
  size: number;
  timestamp: string;
  operation_type: string;
  hostname?: string;
  username?: string;
}

interface GlobalFileTransfersListProps {
  limit?: number;
}

function GlobalFileTransfersList({ limit = 100 }: GlobalFileTransfersListProps) {
  // Get the transfer data with SWR
  const { data, error, isValidating } = useSWR<FileTransferItem[]>(
    endpoints.fileTransfers, // Without GUID to get all records
    swrFetcher,
    { refreshInterval: 10000 }
  );

  // Format file size to display
  const formatFileSize = (bytes: number | undefined): string => {
    if (bytes === undefined || isNaN(bytes)) return "N/A";
    if (bytes === 0) return "0 B";
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(1)} GB`;
  };

  // Format date to display
  const formatDate = (dateString: string): string => {
    try {
      const date = new Date(dateString);
      return format(date, 'dd/MM/yyyy HH:mm:ss');
    } catch (e) {
      return dateString;
    }
  };

  // Get simplified operation text
  const getOperationText = (operation: string): string => {
    if (operation && operation.includes('UPLOAD')) {
      return 'Upload';
    } else if (operation && operation.includes('DOWNLOAD')) {
      return 'Download';
    } else if (operation && operation.includes('VIEW')) {
      return 'View';
    }
    return operation || '';
  };

  // Get operation color
  const getOperationColor = (operation: string): string => {
    if (operation && operation.includes('UPLOAD')) {
      return 'blue'; // Blue color for uploads
    } else if (operation && operation.includes('DOWNLOAD')) {
      return 'green'; // Green color for downloads
    } else if (operation && operation.includes('VIEW')) {
      return 'violet'; // Violet color for views
    }
    return 'gray'; // Gray color for other types
  };

  // Render loading state
  if (!data && !error) {
    return (
      <Center style={{ width: '100%', padding: '20px' }}>
        <Loader size="sm" />
        <Text ml="xs" size="sm" c="dimmed">{t('Loading transfer history...')}</Text>
      </Center>
    );
  }

  // Render error state
  if (error) {
    return (
      <Text c="red" size="sm" style={{ padding: '10px' }}>
        {t('Error loading the transfer history')}
      </Text>
    );
  }

  // Render no transfers message
  if (!data || data.length === 0) {
    return (
      <Text c="dimmed" size="sm" style={{ padding: '10px', textAlign: 'center' }}>
        {t('No file transfer history')}
      </Text>
    );
  }

  // Limit data if necessary
  const limitedData = limit ? data.slice(0, limit) : data;

  // Render table of transfers
  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>{t('File')}</Table.Th>
          <Table.Th>{t('Implant GUID')}</Table.Th>
          <Table.Th>{t('User & Hostname')}</Table.Th>
          <Table.Th>{t('Size')}</Table.Th>
          <Table.Th>{t('Type')}</Table.Th>
          <Table.Th>{t('Date')}</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {limitedData.map((transfer) => (
          <Table.Tr key={transfer.id}>
            <Table.Td>
              <Text size="sm">{transfer.filename}</Text>
            </Table.Td>
            <Table.Td>
              <Text size="sm">
                {transfer.nimplantGuid ? `${transfer.nimplantGuid}` : transfer.nimplantGuid}
              </Text>
            </Table.Td>
            <Table.Td>
              <Text size="sm">
                {transfer.nimplantGuid ? `${transfer.username}@${transfer.hostname}` : transfer.nimplantGuid}
              </Text>
            </Table.Td>
            <Table.Td>
              <Text size="sm">{formatFileSize(transfer.size)}</Text>
            </Table.Td>
            <Table.Td>
              <Text size="sm" c={getOperationColor(transfer.operation_type)}>
                {getOperationText(transfer.operation_type)}
              </Text>
            </Table.Td>
            <Table.Td>
              <Text size="sm">{formatDate(transfer.timestamp)}</Text>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}

export default GlobalFileTransfersList; 