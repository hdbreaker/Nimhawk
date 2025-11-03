#[
    Mapper: ImplantMapper
    Maps between domain Implant and infrastructure ListenerEntity
]#

import ../../domain/models/implant
import ../entities/listener_entity

proc toDomain*(entity: ListenerEntity, role: ImplantRole = STANDARD): Implant =
    ## Convert ListenerEntity to domain Implant model
    result = Implant(
        id: entity.id,
        initialized: entity.initialized,
        registered: entity.registered,
        role: role,
        listenerType: entity.listenerType,
        listenerHost: entity.listenerHost,
        implantCallbackIp: entity.implantCallbackIp,
        listenerPort: entity.listenerPort,
        registerPath: entity.registerPath,
        taskPath: entity.taskPath,
        resultPath: entity.resultPath,
        reconnectPath: entity.reconnectPath,
        userAgent: entity.userAgent,
        httpAllowCommunicationKey: entity.httpAllowCommunicationKey,
        uniqueXorKey: entity.uniqueXorKey,
        sleepTime: entity.sleepTime,
        sleepJitter: entity.sleepJitter,
        killDate: entity.killDate
    )

proc toEntity*(implant: Implant): ListenerEntity =
    ## Convert domain Implant model to ListenerEntity
    result = ListenerEntity(
        id: implant.id,
        initialized: implant.initialized,
        registered: implant.registered,
        listenerType: implant.listenerType,
        listenerHost: implant.listenerHost,
        implantCallbackIp: implant.implantCallbackIp,
        listenerPort: implant.listenerPort,
        registerPath: implant.registerPath,
        taskPath: implant.taskPath,
        resultPath: implant.resultPath,
        reconnectPath: implant.reconnectPath,
        userAgent: implant.userAgent,
        httpAllowCommunicationKey: implant.httpAllowCommunicationKey,
        uniqueXorKey: implant.uniqueXorKey,
        sleepTime: implant.sleepTime,
        sleepJitter: implant.sleepJitter,
        killDate: implant.killDate
    )

proc updateEntityFromDomain*(entity: var ListenerEntity, implant: Implant) =
    ## Update ListenerEntity from domain Implant model
    entity.id = implant.id
    entity.initialized = implant.initialized
    entity.registered = implant.registered
    entity.listenerType = implant.listenerType
    entity.listenerHost = implant.listenerHost
    entity.implantCallbackIp = implant.implantCallbackIp
    entity.listenerPort = implant.listenerPort
    entity.registerPath = implant.registerPath
    entity.taskPath = implant.taskPath
    entity.resultPath = implant.resultPath
    entity.reconnectPath = implant.reconnectPath
    entity.userAgent = implant.userAgent
    entity.httpAllowCommunicationKey = implant.httpAllowCommunicationKey
    entity.uniqueXorKey = implant.uniqueXorKey
    entity.sleepTime = implant.sleepTime
    entity.sleepJitter = implant.sleepJitter
    entity.killDate = implant.killDate

