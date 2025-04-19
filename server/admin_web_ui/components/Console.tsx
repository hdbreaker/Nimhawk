import styles from "../styles/console.module.css";
import { Autocomplete, Button, Group, ScrollArea, Stack } from "@mantine/core";
import { consoleToText, getCommands } from "../modules/nimplant";
import { FaTerminal } from "react-icons/fa";
import { getHotkeyHandler, useFocusTrap, useMediaQuery } from "@mantine/hooks";
import ExecuteAssemblyModal from "./modals/Cmd-Execute-Assembly";
import InlineExecuteModal from "./modals/Cmd-Inline-Execute";
import React, { useEffect, useRef, useState } from "react";
import ShinjectModal from "./modals/Cmd-Shinject";
import UploadModal from "./modals/Cmd-Upload";

type ConsoleType = {
  allowInput? : boolean
  consoleData : any
  disabled? : boolean
  guid?: string
  inputFunction?: (guid: string, command: string) => void
  historyLimit?: number
  onUpdateHistoryLimit?: (newLimit: number, disableAutoRefresh?: boolean) => void
}

// Define the console data structure for typing
interface ConsoleEntry {
  task: boolean;
  taskFriendly: string | null;
  taskId: string | null;
  taskTime: string | null;
  result: string;
  resultTime: string | null;
}

function Console({ 
  allowInput, 
  consoleData, 
  disabled, 
  guid, 
  inputFunction,
  historyLimit = 25, // Default value reduced to 25 entries
  onUpdateHistoryLimit 
}: ConsoleType) {
  const largeScreen = useMediaQuery('(min-width: 800px)');

  // Define viewport and stickyness as state
  const consoleViewport = useRef<HTMLDivElement>(null);
  const [sticky, setSticky] = useState(true);
  const [previousLength, setPreviousLength] = useState(0);
  const [userScrolled, setUserScrolled] = useState(false);
  const [localConsoleData, setLocalConsoleData] = useState<ConsoleEntry[]>([]);
  const [loadingMoreHistory, setLoadingMoreHistory] = useState(false);
  
  // Trap focus on command input by default
  const focusTrapRef = useFocusTrap();
  
  // Define states
  const [autocompleteOptions, setAutocompleteOptions] = useState<string[]>([]);
  const [dropdownOpened, setDropdownOpened] = useState(false);
  const [enteredCommand, setEnteredCommand] = useState('');
  const [historyPosition, setHistoryPosition] = useState(0);
  const [modalExecAsmOpened, setModalExecAsmOpened] = useState(false);
  const [modalInlineExecOpened, setModalInlineExecOpened] = useState(false);
  const [modalshinjectOpened, setModalShinjectOpened] = useState(false);
  const [modalUploadOpened, setModalUploadOpened] = useState(false);

  // Define dynamic autocomplete options
  const {commandList, commandListLoading, commandListError} = getCommands();

  // Initialize localConsoleData when consoleData changes
  useEffect(() => {
    if (consoleData && Array.isArray(consoleData)) {
      setLocalConsoleData([...consoleData]);
    }
  }, [consoleData]);
  
  // Define a utility function to handle command and clear the input field
  const handleSubmit = () => {
    // Avoid sending empty command or when dropdown is open
    if (enteredCommand.trim() === '' || (dropdownOpened && autocompleteOptions.length > 0)) {
      return;
    }
    
    // Validation to ensure we have what's needed to execute commands
    if (inputFunction === undefined || guid === undefined) {
      return;
    }

    // Commands that open specific modals - not sent to server
    if (enteredCommand === 'execute-assembly') {
      setModalExecAsmOpened(true);
    }
    else if (enteredCommand === 'inline-execute') {
      setModalInlineExecOpened(true);
    }
    else if (enteredCommand === 'shinject') {
      setModalShinjectOpened(true);
    }
    else if (enteredCommand === 'upload') {
      setModalUploadOpened(true);
    }
    // All other commands (including 'help') are sent to the server
    else {
      inputFunction(guid, enteredCommand);
    }

    // Clear input field and reset history position
    setHistoryPosition(0);
    setEnteredCommand('');
    
    // Reset user scrolled flag and set sticky to true when submitting command
    setUserScrolled(false);
    setSticky(true);
  }

  // Define a utility function to handle command history with up/down keys
  const handleHistory = (direction: number) => {
    const commandHistory = localConsoleData.filter((i:ConsoleEntry) => i.taskFriendly !== null);
    const histLength : number = commandHistory.length
    var newPos : number = historyPosition + direction

    // Only allow history browsing when there is history and the input field is empty or matches a history entry
    if (histLength === 0 || !commandHistory.some((i:ConsoleEntry) => i.taskFriendly == enteredCommand) && enteredCommand !== '') return;
    
    // Trigger history browsing only with the 'up' direction
    if (historyPosition === 0 && direction === 1) return;
    if (historyPosition === 0 && direction === -1) newPos = histLength;
    
    // Handle bounds, including clearing the input field if the end is reached
    if (newPos < 1) newPos = 1;
    else if (newPos > histLength) {
      setHistoryPosition(0);
      setEnteredCommand('');
      return;
    };

    setHistoryPosition(newPos);
    setEnteredCommand(commandHistory[histLength - newPos]['taskFriendly'] as string);
  }

  // Set hook for handling manual scrolling
  const handleScroll = (pos: { x: number; y: number; }) => {
    if (!consoleViewport.current) return;
    
    const { scrollHeight, clientHeight } = consoleViewport.current;
    const isAtBottom = Math.abs((pos.y + clientHeight) - scrollHeight) < 20;
    
    // Mark if user has manually scrolled
    if (!isAtBottom && !userScrolled) {
      setUserScrolled(true);
    }
    
    if (isAtBottom) {
      setSticky(true);
      setUserScrolled(false);
    } else {
      setSticky(false);
    }
  }

  // Function to scroll to bottom
  const scrollToBottom = () => {
    if (!consoleViewport.current) return;
    
    setTimeout(() => {
      if (!consoleViewport.current) return;
      consoleViewport.current.scrollTo({ 
        top: consoleViewport.current.scrollHeight, 
        behavior: 'auto' 
      });
    }, 10);
  }
  
  // Auto-scroll when new data arrives
  useEffect(() => {
    if (!localConsoleData) return;
    
    const currentLength = localConsoleData.length;
    
    // Only make scroll if there's new data and not manually scrolled
    // Or if we're in sticky mode (user is at the bottom)
    if (currentLength > previousLength) {
      setPreviousLength(currentLength);
      
      if (sticky && !userScrolled) {
        scrollToBottom();
      }
    }
  }, [localConsoleData, previousLength, sticky, userScrolled]);

  // Initial scroll when component mounts
  useEffect(() => {
    // Only make initial scroll, but don't set up an interval
    scrollToBottom();
  }, []);

  // Recalculate autocomplete options
  useEffect(() => {
    const getCompletions = (): string[] => {
      if (enteredCommand === '') return [];
  
      var completionOptions: string[] = [];
  
      // Add base command completions
      if (!commandListLoading && !commandListError) {
        completionOptions = (commandList as any[]).map((a) => a['command'])
      }
      
      // Add history completions, ignore duplicates
      localConsoleData.forEach((entry: ConsoleEntry) => {
        if (entry.taskFriendly !== null) {
          const value: string = entry.taskFriendly;
          if (!completionOptions.includes(value)){
            completionOptions.push(value);
          }
        }
      });
  
      return completionOptions.filter((o) => o.startsWith(enteredCommand) && o != enteredCommand);
    }

    setAutocompleteOptions(getCompletions());
  }, [enteredCommand, commandListLoading, commandListError, localConsoleData, commandList]);

  // Function to load more history
  const loadMoreHistory = () => {
    if (!guid) return;
    
    // Indicate that we're loading more history
    setLoadingMoreHistory(true);
    
    // Increase history limit (multiply by 3 for a more noticeable increment)
    const newLimit = historyLimit * 3;
    console.log(`Increasing history limit from ${historyLimit} to ${newLimit}`);
    
    if (onUpdateHistoryLimit) {
      // Pass true as second parameter to temporarily disable automatic refresh
      onUpdateHistoryLimit(newLimit, true);
    }
    
    // The next SWR update will use this new limit
    // The effect that listens for changes in consoleData will update the data
    
    // Show loading indicator for longer to give time for data to load
    setTimeout(() => {
      setLoadingMoreHistory(false);
      // Make scroll to show old content
      if (consoleViewport.current) {
        consoleViewport.current.scrollTop = 0;
      }
    }, 1000);
  };

  return (
    <Stack 
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '95%',
        width: '100%',
        padding: '12px 16px 10px 16px',
        boxSizing: 'border-box',
      }}
    >
      {/* Modals */}
      <ExecuteAssemblyModal modalOpen={modalExecAsmOpened} setModalOpen={setModalExecAsmOpened} npGuid={guid} />
      <InlineExecuteModal modalOpen={modalInlineExecOpened} setModalOpen={setModalInlineExecOpened} npGuid={guid} />
      <ShinjectModal modalOpen={modalshinjectOpened} setModalOpen={setModalShinjectOpened} npGuid={guid} />
      <UploadModal modalOpen={modalUploadOpened} setModalOpen={setModalUploadOpened} npGuid={guid} />
        
      {/* Code view window */}
      <div
        ref={consoleViewport}
        onScroll={(e) => {
          const element = e.currentTarget;
          handleScroll({ 
            x: element.scrollLeft, 
            y: element.scrollTop 
          });
        }}
        style={{
          flex: 1,
          fontSize: largeScreen ? '14px' : '12px',
          padding: largeScreen ? '14px' : '6px',
          whiteSpace: 'pre-wrap',
          fontFamily: 'monospace',
          color: 'var(--mantine-color-gray-8)',
          backgroundColor: 'var(--mantine-color-gray-0)',
          border: '1px solid var(--mantine-color-gray-4)',
          borderRadius: '4px',
          overflow: 'auto',
          height: '100%',
          // Native scrollbar style 
          scrollbarWidth: 'auto',
          scrollbarColor: 'var(--mantine-color-gray-6) var(--mantine-color-gray-1)'
        }}
      >
        {/* Button to load more history at the top */}
        {localConsoleData && localConsoleData.length > 0 && (
          <Button 
            variant="subtle" 
            size="xs" 
            onClick={loadMoreHistory} 
            loading={loadingMoreHistory}
            style={{ 
              display: 'block',
              margin: '0 auto 10px auto',
              opacity: 0.7
            }}
          >
            Load more history ({historyLimit} commands currently)
          </Button>
        )}
        
        {/* Console content */}
        {!localConsoleData ? "Loading..." : consoleToText(localConsoleData)}
      </div>

      {/* Command input field */}
      {allowInput ? (
        <Group 
          style={{
            marginTop: '4px',
          }}
        >
          <Autocomplete 
            data={autocompleteOptions}
            disabled={disabled}
            leftSection={<FaTerminal size={14} />}
            onChange={setEnteredCommand}
            onDropdownClose={() => setDropdownOpened(false)}
            onDropdownOpen={() => setDropdownOpened(true)}
            placeholder={disabled ? "Implant is not active" : "Type command here..."}
            ref={focusTrapRef}
            value={enteredCommand}
            onKeyDown={getHotkeyHandler([
              ['Enter', handleSubmit],
              ['Tab', () => autocompleteOptions.length > 0 && setEnteredCommand(autocompleteOptions[0])],
              ['ArrowUp', () => handleHistory(-1)],
              ['ArrowDown', () => handleHistory(1)],
            ])}
            style={{
              flex: '1',
            }}
          />
          <Button disabled={disabled} onClick={handleSubmit}>Run command</Button>
        </Group>
      ) : null}
    </Stack>
  )
}

export default Console