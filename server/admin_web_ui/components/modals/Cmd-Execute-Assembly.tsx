import { Button, Chip, FileButton, Flex, Input, Modal, SimpleGrid, Space, Text } from "@mantine/core"
import { Dispatch, SetStateAction, useState } from "react";
import { FaTerminal } from "react-icons/fa"
import { submitCommand, uploadFile } from "../../modules/nimplant";


interface IProps {
    modalOpen: boolean;
    setModalOpen: Dispatch<SetStateAction<boolean>>;
    npGuid: string | undefined;
}

function ExecuteAssemblyModal({ modalOpen, setModalOpen, npGuid }: IProps) {
    const [assemblyFile, setAssemblyFile] = useState<File | null>(null);
    const [assemblyArguments, setAssemblyArguments] = useState("");
    const [patchAmsi, setPatchAmsi] = useState(true);
    const [patchEtw, setPatchEtw] = useState(true);
    const [submitLoading, setSubmitLoading] = useState(false);

    const submit = async () => {
        // Check if a file is selected
        if (!assemblyFile || assemblyFile === null) {
            return;
        }
        
        try {
            setSubmitLoading(true);
            const formData = new FormData();
            formData.append('file', assemblyFile);
            formData.append('filename', assemblyFile.name);
            let uploadUrl = endpoints.upload;
            if (npGuid) {
                uploadUrl = `${endpoints.upload}?nimplant_guid=${npGuid}`;
            }

            // 1. Sube el archivo
            const uploadResult = await api.upload(uploadUrl, formData); // Llama a /api/upload

            // 2. Prepara los argumentos
            const amsi = patchAmsi ? 1 : 0;
            const etw = patchEtw ? 1 : 0;
            const executeCommand = `execute-assembly BYPASSAMSI=${amsi} BLOCKETW=${etw} "${uploadResult.hash}" ${assemblyArguments}`;

            console.log(`Sending execute-assembly command: ${executeCommand}`); // Verifica el comando aquí

            // 3. Envía el comando correcto al backend
            if (npGuid) {
                submitCommand(npGuid, executeCommand, callbackClose);
            }

        } catch (error) {
            // ... (manejo de error) ...
        }
    };

    const callbackClose = () => {
        // Reset state
        setModalOpen(false);
        setAssemblyFile(null);
        setAssemblyArguments("");
        setPatchAmsi(true);
        setPatchEtw(true);
        setSubmitLoading(false);
    };

    return (
        <Modal
            opened={modalOpen}
            onClose={() => setModalOpen(false)}
            title={<b>Execute-Assembly: Execute .NET program</b>}
            size="auto"
            centered
        >
            <Text>Execute a .NET (C#) program in-memory.</Text>
            <Text>Caution: Running execute-assembly will load the CLR!</Text>

            <Space h='xl' />

            <SimpleGrid cols={1}>
            {/* File selector */}
            <FileButton onChange={setAssemblyFile}>
                {(props) => <Button color={"gray"} {...props}>
                    {assemblyFile ? "File: " + assemblyFile.name  : "Select .NET binary"}
                </Button>}
            </FileButton>
            
            {/* Arguments and options */}
            <Input 
                placeholder="Arguments"
                value={assemblyArguments}
                onChange={(event) => setAssemblyArguments(event.currentTarget.value)}
            />

            <Flex
                gap="xl"
                justify="center"
                align="center"
                >
                <Chip checked={patchAmsi} onChange={setPatchAmsi} variant="outline">Patch AMSI</Chip>
                <Chip checked={patchEtw} onChange={setPatchEtw} variant="outline">Block ETW</Chip>
            </Flex>

            </SimpleGrid>

            <Space h='xl' />

            {/* Submit button */}
            <Button 
                onClick={submit}
                leftSection={<FaTerminal />}
                style={{width: '100%'}}
                loading={submitLoading}
            >
                Execute
            </Button>
        </Modal>
    )
}

export default ExecuteAssemblyModal