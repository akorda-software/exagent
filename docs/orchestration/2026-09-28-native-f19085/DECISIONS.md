# Decisiones vigentes de ejecución — 2026-10-01

- **Simplificar por petición del usuario:** objetivos funcionales, un dueño causal,
  como máximo una revisión independiente y ningún re-review/rerun rutinario del padre.
  Sustituye la cadena de microsubsets de las fichas anteriores. Política operativa
  única en `docs/development/execution-flow.md`; no se modifica configuración global.
- **Primero runtime real:** reutilizar CAS10/contrato sellado para producer/restore,
  C7 quiescente y recuperación; no otro análisis R0/Jido/propuesta/validadores.
  El encargo admite checkpoints parciales de código, sin nueva revisión por checkpoint.
- **Memoria compacta:** historial anterior preservado byte-identical en
  `history/2026-10-01-before-flow-simplification.md`; CURRENT vuelve a ser estado
  actual, no acumulación de sesiones. Rojo histórico y evidencia externa pendiente intactos.
- **Aceptar sólo exhaustion interno:** review46f13439 y rerun padre anterior7/7 con
  fuentes actuales respaldan cierre P1. No nuevos tests por prosa ni productor/VM/R6
  aceptados. Recibo único en `docs/development/r6-implementation.md`.
