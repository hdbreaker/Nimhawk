import { useState, useRef, useEffect } from 'react';
import { Text, Table, Group, Badge, Loader, Center, Tooltip } from '@mantine/core';
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
}

interface ImplantFileTransfersListProps {
  guid: string;
}

const TruncatedText = ({ text, maxWidth = '250px' }: { text: string; maxWidth?: string }) => {
  const textRef = useRef<HTMLDivElement>(null);
  const [isTruncated, setIsTruncated] = useState(false);
  
  useEffect(() => {
    if (textRef.current) {
      setIsTruncated(textRef.current.scrollWidth > textRef.current.clientWidth);
    }
  }, [text]);

  const textStyle: React.CSSProperties = {
    maxWidth,
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis'
  };

  return isTruncated ? (
    <Tooltip label={text} multiline withArrow>
      <Text ref={textRef} size="sm" style={textStyle}>
        {text}
      </Text>
    </Tooltip>
  ) : (
    <Text ref={textRef} size="sm" style={textStyle}>
      {text}
    </Text>
  );
};

function ImplantFileTransfersList({ guid }: ImplantFileTransfersListProps) {
  // Get transfer data with SWR
  const { data, error, isValidating } = useSWR<FileTransferItem[]>(
    guid ? endpoints.fileTransfers + `/${guid}` : null,
    swrFetcher,
    { 
      refreshInterval: guid ? 30000 : 0, // Increased to 30s - file transfers don't change often
      revalidateOnFocus: false // Disable to reduce requests
    }
  );

  // Format file size for display
  const formatFileSize = (bytes: number | undefined): string => {
    if (bytes === undefined || isNaN(bytes)) return "N/A";
    if (bytes === 0) return "0 B";
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(1)} GB`;
  };

  // Format date for display
  const formatDate = (dateString: string): string => {
    try {
      const date = new Date(dateString);
      return format(date, 'dd/MM/yyyy HH:mm:ss');
    } catch (e) {
      return dateString;
    }
  };

  // Get simplified text for the operation
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

  // Get color for the operation
  const getOperationColor = (operation: string): string => {
    if (operation && operation.includes('UPLOAD')) {
      return 'blue'; // Color blue for uploads
    } else if (operation && operation.includes('DOWNLOAD')) {
      return 'green'; // Color green for downloads
    } else if (operation && operation.includes('VIEW')) {
      return 'violet'; // Color violet for views
    }
    return 'gray'; // Color gray for other types
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
        {t('Error loading transfer history')}
      </Text>
    );
  }

  // Render no transfers message
  if (!data || data.length === 0) {
    return (
      <Text c="dimmed" size="sm" style={{ padding: '10px', textAlign: 'center' }}>
        {t('No file transfer history for this implant')}
      </Text>
    );
  }

  // Render transfers table
  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>{t('File')}</Table.Th>
          <Table.Th>{t('Size')}</Table.Th>
          <Table.Th>{t('Type')}</Table.Th>
          <Table.Th>{t('Date')}</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {data.map((transfer) => (
          <Table.Tr key={transfer.id}>
            <Table.Td>
              <TruncatedText text={transfer.filename} />
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

export default ImplantFileTransfersList; 