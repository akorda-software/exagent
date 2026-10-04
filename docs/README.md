# Documentation map

This is the source repository's maintainer index. The public manual starts at
[Documentation for applications](guides/index.md); its navigation contains usage
guides and API contracts. Internal plans and dated records below are not published
in HexDocs. ExAgent 2.0.1 is available on [Hex](https://hex.pm/packages/exagent/2.0.1).

## Learn and build

| Start from | Read next |
|---|---|
| Your first agent | [Getting started](guides/getting-started.md) |
| A function the model may call | [Tools and structured output](guides/tools-and-output.md) |
| A provider, gateway or budget | [Models, budgets and limits](guides/models-and-limits.md) |
| A conversation or streaming UI | [Runtime and events](guides/runtime-and-events.md) |
| A restart or human decision | [Durability and approvals](guides/durability-and-approvals.md) |
| Several agents or shared state | [Coordination](guides/coordination.md) |
| Deterministic application tests | [Testing](guides/testing.md) |
| Traces and backend diagnosis | [Observability](guides/observability.md) |
| External tools over stdio or HTTP | [MCP](guides/mcp.md) |
| An unexpected result or error | [Troubleshooting](guides/troubleshooting.md) |

The [documentation home](home.md) gives the layer map.
[Integration notes for coding agents](guides/agents.md) provide a compact API map
and contract checklist. ExDoc's generated `llms.txt` and per-page Markdown use
the same sources as the human-facing site.

## Integrate with your application

| Integration | Recipe and boundary |
|---|---|
| Queue jobs and human approval | [Persisted continuation jobs](development/continuation-jobs.md) |
| Phoenix, LiveView and Oban | [Framework integrations](development/framework-integrations.md) |
| Extraction, specialists and review | [Coordination recipes](development/coordination-recipes.md) |
| External data as an application tool | [Retrieval](development/external-retrieval.md) |
| MCP with stable approval identity | [MCP continuation binding](development/mcp-continuation-binding.md) |
| OTLP with an owned process lifecycle | [Isolated exporter](development/otlp-isolated-transport.md) |
| OTLP through an owned Collector | [Collector route](development/otlp-collector-transport.md) |

Runnable recipes live in `examples/` in the checkout and package. Their guides
distinguish offline demos from real provider, SQL and backend acceptance.

## Understand the contract

| Question | Reference |
|---|---|
| What is actually supported? | [Support and release status](status.md) |
| How do the layers fit together? | [Architecture](architecture/overview.md) |
| Why were these contracts selected? | [Design decisions](architecture/design.md) |
| What changes from 1.x? | [Migration](guides/migration.md) |
| What changed in 2.0? | [Changelog](changelog.md) |

The [project README](../README.md) preserves the compact API tour. The ExDoc
**Modules** tab and search provide function-level reference.

## Mantener ExAgent

Estos documentos describen el trabajo del paquete. Para integrar una aplicación,
las guías anteriores son la entrada habitual.

| Objetivo | Documento |
|---|---|
| Estado y orden de trabajo R0–R9 | [Roadmap](development/roadmap.md) |
| Alcance de v2 y oráculos de producción | [Release scope](development/release-scope.md), [Acceptance](development/production-acceptance.md) |
| Rutina local, exclusiones y gates | [Verificación](development/verification.md) |
| Publicar una versión oficial desde GitHub | [Publicación en Hex](development/releasing.md) |
| Versiones actuales y actualizaciones compatibles | [Dependencias](development/dependencies.md) |
| Causa y tratamiento de límites conocidos | [Límites conocidos](development/known-limits.md) |
| Tooling por proyecto | [Entorno](development/environment.md) |
| E2E real y límites observados | [Consumidor real](development/real-consumer-e2e.md) |
| Langfuse/Opik y ownership ExAgent frente a ReqLLM | [Backend evaluation](development/backend-evaluation.md) |
| Valor y cobertura del testing | [Testing audit](development/testing-audit.md) |
| Método de ejecución vigente | [Execution flow](development/execution-flow.md) |
| Persistencia/continuación/composición/MCP | [R4](development/r4-implementation.md), [R5](development/r5-implementation.md), [R6](development/r6-implementation.md), [R7](development/r7-mcp-implementation.md) |
| Decisiones de backend y dirección | [ReqLLM](development/framework-direction.md), [Jido comparison](development/jido-comparison.md), [OTLP record](development/otlp-transport.md) |
| Relevo operativo | [Handoff](development/handoff.md) |

En el checkout, comenzar por `AGENTS.md`, `docs/prompts/continue-native.md`
y el CURRENT enlazado. Leer sólo el contrato necesario para el objetivo. Un
prompt preparado no activa tareas ni autoriza modificar consumidores o publicar.

## Mantener las páginas y la evidencia

- Guías: explicar el contrato actual, sus requisitos y su siguiente paso. Los
  ejemplos locales seleccionados se ejecutan desde el Markdown real.
- Estado/roadmap: separar comportamiento implementado, evidencia, limitaciones y
  futuro. Cada cifra tiene fecha y alcance; excluidos no son pases.
- Arquitectura/changelog: documentar decisiones y cambios observables sin crear
  contratos alternativos en las guías.
- Histórico: conservar los resultados fechados y sus errores. Los archivos bajo
  `docs/archive/` y `docs/orchestration/` son evidencia, no tareas activas.
  El [catálogo histórico](https://github.com/akorda-software/exagent/tree/main/docs/archive)
  permanece en el repositorio, fuera de la navegación de uso y del paquete.
- Verificación: comprobar ejemplos, ExDoc estricto, enlaces, recursos visuales,
  Markdown/`llms.txt` y el TAR real después de reorganizar páginas.

`AGENTS.md` permanece en la raíz del checkout; `skills/` mantiene su estructura
de descubrimiento. Los prompts y registros operativos no forman parte del paquete.
