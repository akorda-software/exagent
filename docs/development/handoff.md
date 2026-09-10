# Relevo de desarrollo

Este es el punto de entrada actual para retomar el trabajo, no un diario de todos
los Dispatches. Leer `AGENTS.md`, [estado](../status.md),
[roadmap](roadmap.md) y [principios/decisiones](../architecture/design.md).

## Última unidad: auditoría de testing — 2026-09-10

**Cerrada por el usuario. Retomar el desarrollo, no otra oleada de auditoría.**
Se acuerda probar ExAgent y su integración; el mantenimiento/testing interno de
Req, gproc y demás dependencias pertenece a sus mantenedores. Sus warnings quedan
anotados con menor prioridad y no bloquean por sí solos el desarrollo. Conservar
las regresiones de frontera cuando exista impacto real sobre una garantía nuestra.
La guía [verificación](verification.md) recoge este criterio y los gates habituales.

El usuario activó `docs/prompts/testing-audit.md`. Inventario readonly completo,
mejoras y dos revisiones frescas: [síntesis y backlog](testing-audit.md), con
655correctos/28excluidos en1.20/29 y1.17/27 y24contratos runtime del TAR. Strict
permanece rojo en los cuatro grafos por Req0.6.1/Mix1.20; exporter añade gproc/OTP29.
La CI está configurada y su driver probado localmente; no se ejecutó GitHub remoto.

Base real de esta sesión:69c2747, nominal1.3.0, inicialmente limpio. Las mejoras
siguen como WIP, sin commit/bump/publicación. El registro de autoridad, ownership,
provenance y recursos está en `docs/archive/2026-09-testing-audit.md`. Recuperar
Orca antes de asignar otro trabajo; no reutilizar handles cerrados de ese registro.
Prioridades concretas en [roadmap](roadmap.md), separando diagnósticos de paquete,
gaps P2 y aceptación externa autorizada.

## Contexto anterior

El usuario pidió recapitular el cierre nocturno y ordenar la documentación antes
de continuar con la elección de backend y la mejora del paquete. La documentación
vigente vive bajo `docs/`; los relevos nocturnos y sus órdenes quedaron archivados.
No volver a ejecutar N01–N18 por leer el archivo antiguo.

El usuario confirmó después que tiene algunas instancias de Opik y pidió resetear
contexto antes de continuar. Quedaron preparados dos prompts independientes, sin
lanzar Runs ni workers por esa preparación:

- `docs/prompts/backend-evaluation.md`: evaluación desde Opik existente; destino,
  versiones, histórico y acceso todavía por concretar.
- `docs/prompts/testing-audit.md`: auditoría de valor, duplicidad, falsos verdes y
  cobertura importante; implementar únicamente mejoras de tests justificadas.

Ambos mandatos usan Orca Tasks/Dispatch/workers con `openai/gpt-6-astra`, recuperación
de autoridad, revisión fresca y ownership de archivos/builds. Si se abren a la vez,
coordinar antes de escribir o compilar en este worktree compartido.

La reorganización está verificada: suite nativa619/28 seed348677, snippets7/7,
120 enlaces locales, ExDoc, formato y paquete24/24 runtime. El warning strict de
gproc/OTP29 y el Hex compartido pendiente siguen explícitos en [estado](../status.md).

## Base que debe preservarse

- Framework general y extensible; consumidores motivan mejoras, no reglas de dominio.
- WIP y untracked válidos sobre HEAD `c08125be71eada363d08ca463cc7df2ea7855e4a`.
  No reset/clean/stash/merge para reconstruir una base antigua.
- Contratos de la major en diseño/migración. Nominal1.2.0 no significa que el
  checkout pueda publicarse como patch1.x.
- Sin commit, bump, push, publicación, despliegue, reinicio, cambio global o
  modificación de consumidores sin petición expresa. Inferencia de workers no
  autoriza tests LLM pagados, DB real ni nuevos servicios.
- El Hex compartido está pendiente de reparación autorizada. Usar el
  [entorno aislado](environment.md) y comprobar destinos efectivos antes de bootstrap.

## Orca, si se solicita otra orquestación

Cargar la skill de orquestación y descubrir autoridad/Run/mail/flota de nuevo.
El Run nocturno `run_4315531152c9`, generación1, terminó16 Dispatches; sus15
workers están cerrados. No reutilizar handles del archivo ni suplantar el caller.
Los IDs son contexto histórico, no autoridad para una tarea nueva.

## Siguiente resultado útil

Continuar las unidades funcionales del [roadmap](roadmap.md), añadiendo pruebas de
sus cambios, sin anteponer una limpieza general de dependencias. Para
[backend](backend-evaluation.md), concretar la instancia Opik, acceso e histórico
y resolver su frontera de transporte con evidencia de integración; la aceptación
externa y C7 conservan su alcance propio.

Cuando el alcance del paquete esté terminado y el usuario pida una revisión final,
usar `docs/prompts/testing-review-final.md`: revisar lo cambiado desde esta auditoría,
los contratos nuevos, la instalación real del paquete y el valor/frecuencia de los
probes. La nota está diferida; no reactiva `docs/prompts/testing-audit.md`, no exige
un contador mayor de tests ni autoriza publicar o acceder a sistemas externos.
