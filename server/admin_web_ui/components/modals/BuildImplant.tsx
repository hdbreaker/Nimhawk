import { Button, Modal, Text, Group, Stack, Title, useMantineTheme, ThemeIcon } from "@mantine/core"
import { FaHammer, FaWindows, FaLinux, FaApple, FaArrowRight } from "react-icons/fa"
import { Dispatch, SetStateAction } from "react";
import { useRouter } from 'next/router';

interface IProps {
    modalOpen: boolean;
    setModalOpen: Dispatch<SetStateAction<boolean>>;
}

function BuildImplantModal({ modalOpen, setModalOpen }: IProps) {
    const theme = useMantineTheme();
    const router = useRouter();
    
    // Redirect to the new implant builder page
    const handleRedirectToBuilder = () => {
        setModalOpen(false);
        router.push('/implant-builder');
    };

    const handleClose = () => {
        setModalOpen(false);
    };

    return (
        <>
            {/* Main modal to redirect to new builder */}
            <Modal
                opened={modalOpen}
                onClose={handleClose}
                title={<Title order={4}>Build Implants</Title>}
                centered
                size="md"
                radius="md"
                padding="xl"
                styles={{
                    header: { 
                        backgroundColor: theme.colors.gray[0],
                        borderBottom: `1px solid ${theme.colors.gray[2]}`,
                        padding: '15px 20px' 
                    },
                    body: { padding: '20px' },
                }}
            >
                <Stack>
                    <Text size="sm" color="dimmed" ta="center">
                        We've upgraded the implant builder with new features and better organization!
                    </Text>

                    <Group justify="center" my="md">
                        <ThemeIcon size={60} radius="xl" variant="light" color="blue">
                            <FaWindows size={32} />
                        </ThemeIcon>
                        <ThemeIcon size={60} radius="xl" variant="light" color="orange">
                            <Group gap={4}>
                                <FaLinux size={20} />
                                <FaApple size={20} />
                            </Group>
                        </ThemeIcon>
                    </Group>

                    <Stack gap="xs" ta="center">
                        <Text fw={500} size="lg">New Features:</Text>
                        <Text size="sm">• Windows x64 & Multi-Platform support</Text>
                        <Text size="sm">• Advanced architecture selection</Text>
                        <Text size="sm">• Relay client configuration</Text>
                        <Text size="sm">• Enhanced build options</Text>
                    </Stack>

                    <Button
                        onClick={handleRedirectToBuilder}
                        leftSection={<FaHammer />}
                        rightSection={<FaArrowRight />}
                        color="dark"
                        size="md"
                        fullWidth
                        radius="md"
                        mt="md"
                        styles={{
                            root: {
                                boxShadow: theme.shadows.sm,
                                transition: 'all 0.3s ease',
                                '&:hover': {
                                    transform: 'translateY(-2px)',
                                    boxShadow: theme.shadows.md
                                }
                            }
                        }}
                    >
                        Open Advanced Builder
                    </Button>
                </Stack>
            </Modal>
        </>
    )
}

export default BuildImplantModal 