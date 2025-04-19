import { Button, FileButton, Modal, Group, Text, Box, Card, Badge, TextInput, Divider, Tooltip, useMantineTheme } from "@mantine/core"
import { Dispatch, SetStateAction, useState } from "react";
import { FaUpload, FaFileAlt, FaFolder, FaInfoCircle } from "react-icons/fa";
import { notifications } from "@mantine/notifications";
import { api } from "../../modules/api";
import { endpoints, submitCommand } from "../../modules/nimplant";

interface IProps {
    modalOpen: boolean;
    setModalOpen: Dispatch<SetStateAction<boolean>>;
    npGuid: string | undefined;
}

function UploadModal({ modalOpen, setModalOpen, npGuid }: IProps) {
    const [file, setFile] = useState<File | null>(null);
    const [targetPath, setTargetPath] = useState("");
    const [submitLoading, setSubmitLoading] = useState(false);
    const theme = useMantineTheme();

    const submit = async () => {
        // Check if a file is selected
        if (!file || file === null) {
            return;
        }

        try {
            setSubmitLoading(true);
            
            // Upload the file directly to server
            const formData = new FormData();
            formData.append('file', file);
            formData.append('filename', file.name);
            
            // Add the nimplant GUID to the request if available
            let uploadUrl = endpoints.upload;
            if (npGuid) {
                uploadUrl = `${endpoints.upload}?nimplant_guid=${npGuid}`;
            }
            
            // Upload and get the unique hash for the file
            const uploadResult = await api.upload(uploadUrl, formData);
            
            // Show notification for successful upload
            notifications.show({
                title: 'Success',
                message: 'File uploaded to server',
                color: 'green',
            });
            
            // Create and submit the command with the file hash
            // The server should have generated a unique hash for this file
            let uploadCommand = '';
            if (targetPath && targetPath.trim() !== '') {
                uploadCommand = `upload ${uploadResult.hash} ${targetPath.trim()}`;
            } else {
                uploadCommand = `upload ${uploadResult.hash}`;
            }
            
            // Debug the command for troubleshooting
            console.log(`Sending upload command: ${uploadCommand}`);
            
            // Submit the command to the implant
            if (npGuid) {
                submitCommand(npGuid, uploadCommand);
            }
            
            // Close modal
            setModalOpen(false);
            setFile(null);
            setTargetPath("");
            
        } catch (error) {
            notifications.show({
                title: 'Error',
                message: `Upload failed: ${error instanceof Error ? error.message : String(error)}`,
                color: 'red',
            });
        } finally {
            setSubmitLoading(false);
        }
    };
    
    // Function to format file size
    const formatFileSize = (bytes: number): string => {
        if (bytes < 1024) return bytes + ' bytes';
        else if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        else if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
        else return (bytes / 1073741824).toFixed(1) + ' GB';
    };

    return (
        <Modal
            opened={modalOpen}
            onClose={() => setModalOpen(false)}
            title={<Group><FaUpload size={18} /><Text fw={700} size="lg">Upload File</Text></Group>}
            size="md"
            centered
            padding="lg"
            radius="md"
            overlayProps={{
                blur: 3,
            }}
        >
            <Box mb="md">
                <Text size="sm" c="dimmed">
                    Transfer a file from your machine to the target system.
                </Text>
            </Box>
            
            <Divider my="md" label="File Selection" labelPosition="center" />
            
            <Box mb={20}>
                <Group mb="md" justify="center">
                    <FileButton onChange={setFile} accept="*/*">
                        {(props) => (
                            <Button 
                                variant="outline" 
                                leftSection={<FaFileAlt />} 
                                {...props}
                                radius="md"
                                size="md"
                            >
                                Select file
                            </Button>
                        )}
                    </FileButton>
                </Group>
                
                {file && (
                    <Card 
                        p="md" 
                        withBorder
                        radius="md"
                        shadow="sm"
                    >
                        <Group justify="space-between">
                            <Group>
                                <FaFileAlt size={20} />
                                <div>
                                    <Text fw={500}>{file.name}</Text>
                                    <Text size="xs" c="dimmed">{formatFileSize(file.size)}</Text>
                                </div>
                            </Group>
                            <Badge variant="light">Selected</Badge>
                        </Group>
                    </Card>
                )}
            </Box>
            
            <Divider my="md" label="Destination" labelPosition="center" />
            
            <Box mb={20}>
                <Group mb="xs" gap="xs">
                    <FaFolder size={16} />
                    <Text size="sm" fw={500}>Destination Path</Text>
                    <Tooltip label="If not specified, the original filename will be used in the current directory">
                        <Box style={{ display: 'inline-block', cursor: 'help' }}>
                            <FaInfoCircle size={14} />
                        </Box>
                    </Tooltip>
                </Group>
                
                <TextInput
                    placeholder="C:\Path\To\Destination\file.txt (optional)"
                    value={targetPath}
                    onChange={(event) => setTargetPath(event.currentTarget.value)}
                    radius="md"
                    leftSection={<FaFolder size={16} />}
                />
            </Box>
            
            <Divider my="lg" />
            
            <Group justify="flex-end" gap="md">
                <Button 
                    variant="subtle" 
                    onClick={() => setModalOpen(false)}
                    radius="md"
                >
                    Cancel
                </Button>
                <Button 
                    onClick={submit}
                    leftSection={<FaUpload size={16} />}
                    disabled={!file}
                    loading={submitLoading}
                    radius="md"
                >
                    Upload File
                </Button>
            </Group>
        </Modal>
    )
}

export default UploadModal