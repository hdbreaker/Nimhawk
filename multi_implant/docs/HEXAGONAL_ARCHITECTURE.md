# Arquitectura Hexagonal - Documentación

## Estado Actual

Se ha implementado la base de la arquitectura hexagonal en el proyecto multi_implant. La refactorización sigue los principios SOLID y separa las responsabilidades en capas claramente definidas.

## Estructura Implementada

### Domain Layer (Dominio)

**Modelos de Dominio** (`domain/models/`):
- `command.nim` - Representa comandos y resultados de comandos
- `implant.nim` - Representa el estado y configuración del implant
- `relay_connection.nim` - Representa conexiones y configuración de relay
- `network_health.nim` - Representa métricas de salud de red

**Puertos** (`domain/ports/`):
- **IN (Entrada)** - Interfaces que el dominio expone:
  - `command_handler_port.nim` - Manejo de comandos
  - `relay_handler_port.nim` - Manejo de relay
  - `communication_port.nim` - Comunicación con C2
  
- **OUT (Salida)** - Interfaces que el dominio necesita:
  - `command_repository_port.nim` - Persistencia de comandos
  - `relay_repository_port.nim` - Persistencia de relay
  - `communication_repository_port.nim` - Comunicación con C2
  - `system_info_port.nim` - Información del sistema

### Application Layer (Aplicación)

**Servicios** (`applications/services/`):
- `command_service.nim` - Servicio para ejecución de comandos (SRP aplicado)

**Casos de Uso** (`applications/usecases/`):
- `execute_command_usecase.nim` - Orquesta la ejecución de comandos
- `register_implant_usecase.nim` - Orquesta el registro del implant
- `poll_commands_usecase.nim` - Orquesta el polling de comandos
- `relay_management_usecase.nim` - Orquesta operaciones de relay

### Infrastructure Layer (Infraestructura)

**Repositorios** (`infrastructure/repositories/`):
- `communication_repository.nim` - Implementa comunicación con C2
- `command_repository.nim` - Implementa almacenamiento de comandos
- `relay_repository.nim` - Implementa almacenamiento de relay
- `system_info_repository.nim` - Implementa obtención de información del sistema

**Mappers** (`infrastructure/mappers/`):
- `implant_mapper.nim` - Convierte entre dominio Implant y infraestructura Listener
- `command_mapper.nim` - Convierte entre representaciones de comandos

**Config** (`infrastructure/config/`):
- `config_loader.nim` - Wrapper para el parser de configuración existente

## Principios SOLID Aplicados

### Single Responsibility Principle (SRP)
- Cada servicio/usecase tiene una única responsabilidad
- CommandService solo maneja ejecución de comandos
- Cada usecase orquesta un caso de uso específico

### Open/Closed Principle (OCP)
- Los comandos pueden extenderse sin modificar código existente
- Los puertos permiten nuevas implementaciones sin cambiar el dominio

### Liskov Substitution Principle (LSP)
- Los repositorios implementan los puertos y son intercambiables
- Las implementaciones respetan los contratos de los puertos

### Interface Segregation Principle (ISP)
- Los puertos están segregados por responsabilidad
- No hay interfaces "gordas" con múltiples responsabilidades

### Dependency Inversion Principle (DIP)
- El dominio no depende de infraestructura
- Las capas superiores dependen de abstracciones (puertos)
- La infraestructura implementa los puertos

## Compatibilidad Hacia Atrás

El código existente sigue funcionando:
- `cmdParser.nim` ha sido refactorizado pero mantiene la misma interfaz pública
- Las funciones existentes siguen disponibles
- La migración puede hacerse gradualmente

## Próximos Pasos

### Pendiente de Implementar

1. **Refactorizar webClientListener.nim**
   - Mover lógica a adaptadores de infraestructura
   - Usar repositorios para comunicación

2. **Refactorizar sistema relay**
   - Mover a adaptadores de infraestructura
   - Integrar con repositorios

3. **Refactorizar main.nim**
   - Simplificar a orquestador mínimo
   - Implementar inyección de dependencias
   - Usar casos de uso para orquestar flujos

4. **Validación SOLID**
   - Revisar código refactorizado
   - Asegurar cumplimiento de principios

5. **Testing**
   - Verificar funcionalidad existente
   - Agregar tests para nueva arquitectura

## Ejemplo de Uso

### Ejecutar un Comando (Nueva Arquitectura)

```nim
import applications/services/command_service
import domain/models/command

let service = newCommandService()
let cmd = newCommand("guid-123", "ls", @["/tmp"])
let result = service.executeCommand(listener, cmd.command, cmd.guid, cmd.args)
```

### Registrar Implant (Nueva Arquitectura)

```nim
import applications/usecases/register_implant_usecase
import infrastructure/repositories/communication_repository
import infrastructure/repositories/system_info_repository

let commRepo = newCommunicationRepository()
let sysInfoRepo = newSystemInfoRepository()
let useCase = newRegisterImplantUseCase(commRepo, sysInfoRepo)

var implant = newImplant()
let success = await useCase.register(implant)
```

## Beneficios de la Nueva Arquitectura

1. **Testabilidad**: Interfaces claras facilitan el testing
2. **Mantenibilidad**: Separación de responsabilidades
3. **Escalabilidad**: Fácil agregar nuevas funcionalidades
4. **Flexibilidad**: Cambiar implementaciones sin afectar dominio
5. **Claridad**: Código más organizado y fácil de entender

## Notas de Implementación

- Los puertos usan "concept" de Nim, que define contratos
- Los repositorios implementan estos contratos
- Los mappers convierten entre capas de dominio e infraestructura
- Se mantiene compatibilidad hacia atrás durante la transición

