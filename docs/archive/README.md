# Archivo de documentación

Este directorio conserva evidencia y contexto de ejecuciones cerradas. No forma
parte de la navegación de uso ni del paquete documental vigente. Empieza por
[el índice actual](../README.md), [estado](../status.md) o
[roadmap](../development/roadmap.md) para trabajar sobre el presente.

## Consolidación de septiembre de 2026

- [Estado histórico hasta el2026-10-02](2026-10-02-status-history.md): copia íntegra
  del estado anterior a la reorganización documental. Sus pendientes y rutas
  pertenecen a cada fecha; el estado vigente vive en `docs/status.md`.

| Documento original | Ubicación conservada | Propósito histórico |
|---|---|---|
| `ROADMAP.md` | [roadmap](2026-09-consolidation/roadmap.md) | Fases originales y seguimiento C0–C8/nocturno. |
| `ACTION_PLAN.md` | [action-plan](2026-09-consolidation/action-plan.md) | Plan, decisiones operativas y evidencia detallada C0–C8/N01–N18. |
| `RESEARCH.md` | [research](2026-09-consolidation/research.md) | Auditoría y fuentes consultadas antes de la consolidación. |
| `ORCHESTRATION.md` | [orchestration](2026-09-consolidation/orchestration.md) | Run/Tasks/Dispatches, ownership, incidentes y cierre. |
| `NEXT_AGENT_PROMPT.md` | [night-handoff](2026-09-consolidation/night-handoff.md) | Mandato y backlog del relevo nocturno ya terminado. |

Las entradas «en curso», cifras intermedias, rutas antiguas y comandos del registro
pertenecen a su fecha. Los nombres antiguos se conservan en citas y logs para poder
contrastarlos con la evidencia; los enlaces navegables se reubican cuando procede.
No copiar sus órdenes como prompt activo. Los handles cerrados no se reutilizan.

## Plan de salida anterior y mandato de backend

Archivados al preparar el roadmap v2 el2026-09-21. Sus referencias a C7 diferido
y a H1–H6 conservan el contexto de su fecha; el nuevo alcance incluye C7 por
confirmación expresa del usuario.

- [Roadmap H1–H6/H3.0](2026-09-release-roadmap.md): planificación y evidencia previa.
- [Alcance H1](2026-09-release-scope.md): capacidades y exclusiones entonces acordadas.
- [Prompt anterior de backend](2026-09-backend-evaluation-prompt.md): mandato específico
  con Orca/modelos históricos; no obliga al nuevo ejecutor a usar esa orquestación.

## Evidencia del mandato v2

- [None explícito y binding estático](2026-09-27-reasoning-none-binding.md): subunidad
  autorizada posterior a admisión final, versiones y evidencia C7/TCP propias.
- [Admisión final stock ReqLLM](2026-09-27-final-argument-admission.md): cambio
  autorizado de contrato host, rojo/verde público, controles de pérdida y freeze.
- [Aclaración contractual ReqLLM tras G2](2026-09-27-reqllm-contract-clarification.md):
  distingue diagnósticos de fragmentos, resolución stock y política del adaptador;
  corrige la atribución categórica anterior, sin aplicar parches ni aceptar G2.

- [Preflight R0 de implement-v2](2026-09-21-r0-baseline.md): inventario, entorno
  aislado, baseline reproducido y accesos externos pendientes al activar el
  mandato de implementación el2026-09-21. R0 sólo hace preflight; R1 sigue abierto.
- [Dependencia y frontera host R1.1](2026-09-21-r1-1-reqllm.md): ReqLLM1.24.0,
  mínimo1.18 por grafo, consumidores TAR nativo/mínimo y gaps de uso/retries;
  R1 continúa sin adapter todavía.

- [Mint y adapter buffered R1.2/R1.3 parcial](2026-09-21-r1-buffered.md): evidencia
  nueva tras Mint, codec/snapshot, consumidores y bloqueos reales Google/usage.

- [Streaming stock y guards de review](2026-09-21-r1-streaming.md): protocolo
  predeclarado, bloqueo de bytes, args/redacted/perfil y evidencia nueva de seguridad.

- [R1.6/R1.7 textuales y Req compatible](2026-09-21-r1-textual.md): precedencia,
  instrucciones, total por instancia, HTTP real y escenario compuesto sin paridad falsa.

- [Sobre buffered y ownership host R1.2](2026-09-22-r1-envelope.md): gate stock,
  subset/codec, integración lógica, rojo/corrección de ownerkill y candidata acotada.

- [Adapter streaming R1.4](2026-09-22-r1-stream-adapter.md): integración pública,
  límites postdecode, ownership/ACK, regresión de snapshots y evidencia por artefacto.

- [Contabilidad cualificada R1.5](2026-09-25-r1-qualified-accounting.md): métricas
  stock, límites strict/estimated, snapshot3, regresiones frescas y distribución fija.

- [Composición mínima R1.3/6/7](2026-09-25-r1-qualified-composition.md): matriz de
  evidencia, escenarios stock TCP/restore/OTel e inventario preparatorio R1.8.

- [Runtime R3 parcial](2026-09-26-r3-runtime.md): namespaces, admisión, review
  aceptada y reproducción de retención que motivó la unidad siguiente.
- [Retención postdecode R3.4](2026-09-26-r3-retention.md): ADR/outcomes/markers,
  umbrales de smoke, rojos, gates y artefacto preparado para revisión independiente.

## Regla de archivo

- [C7 implementación/verificación owner](2026-09-27-c7-owner-matrix.md): árbol,
  Model recovery/retry, VM nueva, compuestos, cotas y consumidores fixedgraph;
  aceptación independiente bloqueada, no release ni gates externos certificados.

La entrega R2.3 se conserva en [Output tipado/nativo](2026-09-26-r2-output.md),
con matriz, gate stock, pérdida de refusal documentada, evidencia y freeze.

Archivar al cerrar una unidad grande, con fecha, motivo y enlace desde la
documentación actual cuando aporte trazabilidad. No almacenar credenciales ni
capabilities. Los artefactos temporales pueden desaparecer: conservar decisiones,
resultados relevantes y pruebas reproducibles dentro del repositorio.
