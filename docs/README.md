# Documentación de ExAgent

El [README del proyecto](../README.md) es la entrada para instalar y probar la
biblioteca. Este índice organiza las guías, las decisiones y el trabajo de
mantenimiento. Describe el checkout de consolidación, todavía sin publicar como major.

## Por dónde empezar

| Necesidad | Documento |
|---|---|
| Saber qué está implementado y qué falta | [Estado actual](status.md) |
| Entender las capas y sus garantías | [Arquitectura actual](architecture/overview.md) |
| Revisar principios y decisiones de contrato | [Diseño y decisiones](architecture/design.md) |
| Adaptar un consumidor de 1.x | [Guía de migración](guides/migration.md) |
| Configurar trazas y entender sus límites | [Observabilidad](guides/observability.md) |
| Ejecutar tests, probes y comprobaciones del paquete | [Verificación](development/verification.md) |
| Resolver el entorno local de desarrollo | [Entorno y tooling](development/environment.md) |
| Elegir la siguiente unidad útil | [Hoja de ruta](development/roadmap.md) |
| Preparar la comparación Langfuse/Opik | [Aceptación del backend](development/backend-evaluation.md) |
| Retomar una sesión de trabajo | [Relevo de desarrollo](development/handoff.md) |
| Consultar cambios publicados y pendientes | [Changelog](changelog.md) |

## Histórico

Los planes C0–C8, el backlog nocturno N01–N18, la investigación y los registros
Orca originales se conservan en `docs/archive/2026-09-consolidation/` del checkout.
Su catálogo está en `docs/archive/README.md`, o en el
[archivo del repositorio](https://github.com/akorda-software/exagent/tree/main/docs/archive).
Son evidencia fechada, no una segunda hoja de ruta ni instrucciones activas.
El paquete y la navegación principal de ExDoc incluyen la documentación vigente;
los registros operativos históricos permanecen en el repositorio.

## Cómo mantener esta documentación

- **Estado:** guardar aquí sólo la última aceptación significativa y sus límites.
  Cada cifra debe tener fecha, alcance y prueba reproducible; excluidos no son pases.
- **Guías:** explicar el uso actual. Los snippets deben seguir funcionando con
  las fixtures del probe de documentación cuando corresponda.
- **Arquitectura:** el mapa de capas vive en `architecture/overview.md`; principios
  y decisiones razonadas, en `architecture/design.md`. No duplicar contratos divergentes.
- **Roadmap:** mantener una lista corta de siguientes resultados, dependencias y
  criterios de cierre. Al acabar una unidad, actualizar estado y evidencia.
- **Changelog:** registrar cambios observables y migración. Los logs de una sesión
  no sustituyen una entrada de cambio de contrato.
- **Archivo:** conservar íntegra la evidencia útil de una ejecución cerrada,
  con fecha y aviso de que no está vigente. Los enlaces se pueden reubicar;
  resultados, errores y restricciones históricos no se reescriben como éxitos nuevos.
- **Enlaces y paquete:** al mover una guía, actualizar README, AGENTS, `mix.exs`,
  las referencias y los probes que leen sus codeblocks. Seguir
  [el gate documental](development/verification.md).

`README.md`, `AGENTS.md` y `LICENSE` permanecen en la raíz como entradas del
repositorio. `skills/` conserva su estructura de descubrimiento para agentes;
no es una copia alternativa de estas guías ni se mueve como si fuera prosa suelta.

## Prompts para nuevas sesiones (sólo checkout)

- `docs/prompts/backend-evaluation.md`: continuar desde las instancias Opik
  existentes, con evaluación verificable y mejoras del paquete justificadas.
- `docs/prompts/testing-audit.md`: auditar valor/cobertura, duplicados y falsos
  verdes; consolidar o añadir pruebas con evidencia.

Son mandatos completos e independientes de la conversación anterior, con Orca y
Astra. Leer el archivo elegido entero antes de asignar trabajo. Prepararlos no
inicia una ejecución; los registros bajo `docs/archive/` siguen siendo históricos.
Los prompts operativos no forman parte del paquete ni de los extras de ExDoc.
