# Relevo de desarrollo

Este es el punto de entrada actual para retomar el trabajo, no un diario de todos
los Dispatches. Leer `AGENTS.md`, [estado](../status.md),
[roadmap](roadmap.md) y [principios/decisiones](../architecture/design.md).

## Mandato actual

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

Seguir el prompt elegido. Para [backend](backend-evaluation.md), concretar cuál de
las instancias Opik usar, acceso e histórico, resolver el gate de transporte y
comparar con el mismo escenario sintético. La aceptación real de proveedores/DB/consumidores y C7 son
unidades independientes, todavía abiertas. No confundir esa planificación con
permiso de instalar una plataforma o publicar la major.
