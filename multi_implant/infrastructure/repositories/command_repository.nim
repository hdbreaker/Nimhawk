#[
    Repository: CommandRepository
    Implements CommandRepositoryPort
    Manages command storage (in-memory for now)
]#

import ../../domain/models/command
import tables

type
    CommandRepository* = object
        commands*: Table[string, Command]
        results*: Table[string, CommandResult]
        commandsQueue*: seq[Command]  # Queue for commands from C2
        resultsQueue*: seq[CommandResult]  # Queue for results to C2
    
proc newCommandRepository*(): CommandRepository =
    ## Create a new CommandRepository instance
    result = CommandRepository(
        commands: initTable[string, Command](),
        results: initTable[string, CommandResult](),
        commandsQueue: @[],
        resultsQueue: @[]
    )

proc saveCommand*(repo: var CommandRepository, cmd: Command) =
    ## Save a command
    repo.commands[cmd.guid] = cmd

proc getCommand*(repo: CommandRepository, guid: string): Command =
    ## Get a command by GUID
    if guid in repo.commands:
        return repo.commands[guid]
    else:
        return newCommand("", "", @[])

proc saveResult*(repo: var CommandRepository, result: CommandResult) =
    ## Save a command result
    repo.results[result.guid] = result

proc getResult*(repo: CommandRepository, guid: string): CommandResult =
    ## Get a command result by GUID
    if guid in repo.results:
        return repo.results[guid]
    else:
        return newCommandResult("", "")

proc getAllPendingCommands*(repo: CommandRepository): seq[Command] =
    ## Get all pending commands from queue
    result = repo.commandsQueue

proc getAllPendingResults*(repo: CommandRepository): seq[CommandResult] =
    ## Get all pending results from queue
    result = repo.resultsQueue

proc addCommandToQueue*(repo: var CommandRepository, cmd: Command) =
    ## Add command to queue
    repo.commandsQueue.add(cmd)

proc addResultToQueue*(repo: var CommandRepository, result: CommandResult) =
    ## Add result to queue
    repo.resultsQueue.add(result)

proc clearCommandsQueue*(repo: var CommandRepository) =
    ## Clear commands queue
    repo.commandsQueue = @[]

proc clearResultsQueue*(repo: var CommandRepository) =
    ## Clear results queue
    repo.resultsQueue = @[]

