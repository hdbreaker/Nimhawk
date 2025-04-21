import { Button, Chip, FileButton, Flex, Input, Modal, SimpleGrid, Space, Text } from "@mantine/core"
import { Dispatch, SetStateAction, useState } from "react";
import { FaTerminal } from "react-icons/fa"
import { submitCommand, endpoints } from "../../modules/nimplant";
import { api } from "../../modules/api";
import { notifications } from "@mantine/notifications";

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

    console.log(`[ExecuteAssemblyModal] Component rendered. npGuid: ${npGuid}`);

    const submit = async () => {
        console.log("[ExecuteAssemblyModal] SUBMIT FUNCTION CALLED.");
        
        console.log(`[ExecuteAssemblyModal] Checking state: assemblyFile=${assemblyFile?.name}, npGuid=${npGuid}`);
        
        if (!assemblyFile) {
            console.log("[ExecuteAssemblyModal] ABORT: No assembly file selected.");
            notifications.show({ 
                title: 'Input Required',
                message: 'Please select a .NET binary file first.',
                color: 'orange',
            });
            return;
        }

        if (!npGuid) {
            console.error("[ExecuteAssemblyModal] ABORT: npGuid is undefined.");
            notifications.show({
                title: 'Error',
                message: 'No active Nimplant selected.',
                color: 'red',
            });
            return; 
        }

        console.log("[ExecuteAssemblyModal] Checking required objects/vars:");
        console.log("[ExecuteAssemblyModal] typeof api.upload:", typeof api?.upload);
        console.log("[ExecuteAssemblyModal] typeof endpoints.upload:", typeof endpoints?.upload);
        if (typeof api?.upload !== 'function' || typeof endpoints?.upload !== 'string') {
            const errorMsg = "Code Error: api.upload or endpoints.upload is not configured correctly.";
            console.error(`[ExecuteAssemblyModal] ABORT: ${errorMsg}`);
             notifications.show({ title: 'Code Error', message: errorMsg, color: 'red' });
             return;
        }

        try {
            console.log("[ExecuteAssemblyModal] Entering TRY block. Setting loading=true.");
            setSubmitLoading(true);

            console.log("[ExecuteAssemblyModal] FormData created.");

            const formData = new FormData();
            formData.append('file', assemblyFile);
            formData.append('filename', assemblyFile.name);
            console.log("[ExecuteAssemblyModal] FormData created.");

            let uploadUrl = `${endpoints.upload}?nimplant_guid=${npGuid}`;
            console.log(`[ExecuteAssemblyModal] Final Upload URL: ${uploadUrl}`);

            console.log("[ExecuteAssemblyModal] >>> Calling api.upload NOW...");
            const uploadResult = await api.upload(uploadUrl, formData); 
            console.log("[ExecuteAssemblyModal] <<< api.upload finished. Result:", uploadResult);

            if (!uploadResult || !uploadResult.hash) {
                 const errorMsg = "File upload failed or did not return a valid hash.";
                 console.error(`[ExecuteAssemblyModal] ${errorMsg}`);
                 throw new Error(errorMsg);
            }
             notifications.show({ 
                title: 'Upload Success',
                message: `File uploaded. Hash: ${uploadResult.hash}`,
                color: 'green',
            });

            const amsi = patchAmsi ? 1 : 0;
            const etw = patchEtw ? 1 : 0;
            const argsString = assemblyArguments.trim() ? ` ${assemblyArguments.trim()}` : ""; 
            const executeCommand = `execute-assembly BYPASSAMSI=${amsi} BLOCKETW=${etw} "${uploadResult.hash}"${argsString}`;
            console.log(`[ExecuteAssemblyModal] Final Command: ${executeCommand}`); 

            console.log(`[ExecuteAssemblyModal] >>> Calling submitCommand for npGuid: ${npGuid}`);
            submitCommand(npGuid, executeCommand, callbackClose); 
            console.log("[ExecuteAssemblyModal] <<< submitCommand called.");

        } catch (error) {
            console.error("[ExecuteAssemblyModal] CATCH block executed. Error:", error);
            notifications.show({
                title: 'Operation Error',
                message: `Process failed: ${error instanceof Error ? error.message : String(error)}`,
                color: 'red',
            });
            console.log("[ExecuteAssemblyModal] Setting loading=false in CATCH block.");
            setSubmitLoading(false);
        }
    };

    const callbackClose = () => {
        console.log("[ExecuteAssemblyModal] CALLBACK_CLOSE called. Resetting state."); 
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
            <FileButton 
                onChange={(file) => {
                    console.log("[ExecuteAssemblyModal] File selected:", file);
                    setAssemblyFile(file);
                }}
                accept=".exe,.dll"
            >
                {(props) => <Button color={"gray"} {...props}>
                    {assemblyFile ? "File: " + assemblyFile.name  : "Select .NET binary (.exe/.dll)"}
                </Button>}
            </FileButton>
            
            {/* Arguments and options */}
            <Input 
                placeholder="Arguments (optional)"
                value={assemblyArguments}
                onChange={(event) => setAssemblyArguments(event.currentTarget.value)}
            />

            <Flex
                gap="xl"
                justify="center"
                align="center"
                >
                <Chip checked={patchAmsi} onChange={(checked) => setPatchAmsi(checked)} variant="outline">Patch AMSI</Chip>
                <Chip checked={patchEtw} onChange={(checked) => setPatchEtw(checked)} variant="outline">Block ETW</Chip>
            </Flex>

            </SimpleGrid>

            <Space h='xl' />

            {/* Submit button */}
            <Button 
                onClick={submit}
                leftSection={<FaTerminal />}
                style={{width: '100%'}}
                loading={submitLoading}
                disabled={!assemblyFile || submitLoading}
            >
                Execute
            </Button>
        </Modal>
    )
}

export default ExecuteAssemblyModal