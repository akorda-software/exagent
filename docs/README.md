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
| Ejecutar escenarios reales desde el consumidor Phoenix | [E2E con OpenRouter](development/real-consumer-e2e.md) |
| Revisar el valor, los oráculos y los gaps de las pruebas | [Auditoría de testing](development/testing-audit.md) |
| Resolver el entorno local de desarrollo | [Entorno y tooling](development/environment.md) |
| Entender primitivas atómicas y límites de continuación | [Persistencia R4](development/r4-implementation.md) |
| Configurar MCP Streamable HTTP y conocer sus límites | [Implementación MCP R7.4a](development/r7-mcp-implementation.md) |
| Integrar aprobación persistida en un job externo | [Receta de jobs C7](development/continuation-jobs.md) |
| Consultar datos externos sin ampliar autoridad | [Receta de retrieval](development/external-retrieval.md) |
| Reanudar herramientas MCP con identidad estable | [Binding durable MCP](development/mcp-continuation-binding.md) |
| Acotar el ciclo de vida del transporte OTLP | [Receta OTLP aislada](development/otlp-isolated-transport.md) |
| Exportar OTLP mediante un Collector propio | [Ruta Collector HTTP](development/otlp-collector-transport.md) |
| Integrar continuaciones con LiveView y Oban | [Recetas de framework](development/framework-integrations.md) |
| Componer extracción, especialistas y revisión humana | [Recetas de coordinación](development/coordination-recipes.md) |
| Elegir la siguiente unidad útil | [Hoja de ruta](development/roadmap.md) |
| Ejecutar sin cadenas de revisiones | [Flujo vigente](development/execution-flow.md) |
| Conocer qué incluye la próxima major y qué queda fuera | [Alcance de la versión](development/release-scope.md) |
| Comprobar qué debe demostrar la v2 en producción | [Matriz de aceptación](development/production-acceptance.md) |
| Comparar ExAgent con Jido y evaluar continuidad o adopción | [Auditoría comparativa Jido](development/jido-comparison.md) |
| Entender la dirección del paquete y la integración prevista de ReqLLM | [ExAgent sobre ReqLLM](development/framework-direction.md) |
| Preparar la comparación Langfuse/Opik | [Aceptación del backend](development/backend-evaluation.md) |
| Retomar una sesión de trabajo | `docs/prompts/continue-native.md` y CURRENT del run enlazado (sólo checkout) |
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
- **Roadmap:** mantener resultados, subunidades, dependencias y criterios de cierre.
  R0–R9 se siguen únicamente allí; alcance y matriz de aceptación describen producto
  y oráculos sin duplicar estados. Al acabar una unidad, actualizar evidencia.
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

- **Entrada actual:** `docs/prompts/continue-native.md` (sólo checkout). Consultar el
  estado resumido vigente y sólo el encargo pertinente; no releer todos los relevos.
- `docs/prompts/implement-v2.md`: ejecutar iterativamente R0–R9 cuando se encargue
  su activación; ReqLLM primero, C7 incluido, gates de producción y relevo explícitos.
- Los relevos fechados y `continue-v2-reqllm.md` conservan contexto histórico de
  contratos/aceptaciones. No dictan la siguiente tarea ni rondas extra de revisión.
- `docs/prompts/backend-evaluation.md`: continuar desde las instancias Opik
  existentes como unidad R7/A10/G4, con evaluación verificable y alcance sintético.
- `docs/prompts/testing-audit.md`: mandato de la auditoría ya cerrada, conservado
  como contexto; no volver a ejecutarlo automáticamente.
- `docs/prompts/testing-review-final.md`: única revisión de la integración/distribución
  candidata R9 y delta no revisado; no segunda auditoría de unidades ya aceptadas.

Leer el archivo elegido entero y respetar su estado de activación antes de asignar
trabajo. Prepararlos no inicia una ejecución; los registros bajo `docs/archive/`
siguen siendo históricos. La política de alcance del testing está en
[verificación](development/verification.md).
Los prompts operativos no forman parte del paquete ni de los extras de ExDoc.
