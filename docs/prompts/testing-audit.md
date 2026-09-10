# Relevo: auditoría de valor y cobertura del testing

> **Mandato completado y cerrado el 2026-09-10.** Se conserva como contexto de la
> primera auditoría; sus instrucciones siguientes no son una tarea pendiente.
> El usuario decidió continuar el desarrollo y concentrar el testing en ExAgent
> y sus fronteras de integración, sin duplicar las suites de dependencias.
> Para una segunda revisión, al terminar el paquete y cuando se solicite, usar
> [la nota diferida](testing-review-final.md) y el estado vigente.

Eres el coordinador de una auditoría de testing de ExAgent. Trabaja en
`/home/kukapu/dev/projects/exAgent`, habla en español y lee este documento COMPLETO
antes de asignar trabajo. Si eres un worker con Dispatch, sigue sólo tu Task;
no abras otra orquestación por leer este relevo.

## 1. Mandato

El usuario quiere comprobar si **todos los tests actuales tienen sentido**, si
hay duplicados, scaffolding innecesario o falsos verdes, y si faltan pruebas
importantes de funcionalidades/contratos. No busca maximizar ni minimizar el
número de tests: busca confianza útil con un coste de mantenimiento razonable.

Realizar la auditoría completa por áreas y después implementar las consolidaciones,
correcciones de pruebas y regresiones importantes que estén justificadas. No
terminar con una lista genérica de consejos. Tampoco borrar masivamente ni ampliar
features de producción sólo para poder escribir más tests.

## 2. Lecturas y base

Lee, en orden:

1. `AGENTS.md`, `docs/README.md`, `docs/status.md`.
2. `docs/development/handoff.md`, `docs/development/roadmap.md`.
3. `docs/architecture/overview.md` y `docs/architecture/design.md`, sobre todo
   2.1–2.3 y las decisiones de contratos 8.2–8.9.
4. `docs/guides/migration.md`, `docs/guides/observability.md`, `docs/changelog.md`.
5. `docs/development/verification.md` y `docs/development/environment.md`.
6. `mix.exs`, `test/test_helper.exs`, soporte/fixtures y configuración CI pertinente.

La documentación se reorganizó bajo `docs/`. El contenido de `docs/archive/` es
evidencia histórica, no tareas activas. No reejecutar N01–N18 como otro mandato.

Referencia inicial, no sustituto de comprobar el estado real:

- 619 correctos/28 excluidos en el nativo tras reorganización, seed348677;
  cierre previo en1.20/29,1.18/28 y1.17/27:619/28, seed37556.
- Hay pruebas ExUnit, secuencias generadas, probes aislados, snippets y consumidores
  TAR. Sus denominadores no son intercambiables. Los excluidos de proveedores/DB
  no cuentan como aceptación runtime, aunque sus fuentes puedan auditarse.
- Mucho WIP/untracked válido sobre HEAD c08125be71eada363d08ca463cc7df2ea7855e4a.
  La mayoría de cambios no está commiteada; no usar git diff como si todo perteneciera
  a esta nueva sesión. Untracked no significa prescindible.
- Nominal1.2.0 contiene cambios de major pendientes. El objetivo es fortalecer y
  simplificar su verificación, no cambiar APIs cosméticamente.
- El usuario tiene instancias de Opik; su evaluación pertenece a otro frente.
  Esta auditoría no autoriza acceder a ellas ni decidir backend.

## 3. Orca y modelo: obligatorios

**Carga `orca-orchestration` antes de asignar trabajo.** Orquesta mediante Orca
Tasks/Dispatch/workers con **`openai/gpt-6-astra` para todos los workers**. No usar
otra red paralela de subagentes nativos ni el reparto GLM/Muse de la skill. No
cambiar el modelo o la configuración global del coordinador.

Recupera contexto real:

```bash
orca status --json
orca worktree current --json
orca orchestration run-current --json
orca orchestration run-list --json
```

Inspecciona Run, tareas, flota y correo antes de enlazar autoridad o crear el Run
de esta auditoría. El Run nocturno `run_4315531152c9` terminó y sus15 workers están
cerrados. No reutilizar handles históricos, inventar IDs/capabilities o suplir
autoridad con `--from`. No robar el Run de otro coordinador activo.

Plantillas de la CLI observada, sustituyendo IDs por recibos reales:

```bash
orca orchestration task-create --run <run_id> --task-title "Auditar un contrato" --spec "Objetivo, archivos, límites, aceptación y entrega" --json
orca orchestration worker-start --run <run_id> --task <task_id> --worktree path:/home/kukapu/dev/projects/exAgent --agent opencode --model openai/gpt-6-astra --json
orca orchestration check --run <run_id> --wait --timeout-ms 60000 --json
```

No existían worker-start --spec, worker-list --include-remote ni --effort para
OpenCode en esa versión. Redescubrir capacidades y consultar ayuda si cambia;
no actualizar/reiniciar Orca para adaptar los ejemplos. Verificar modelo y progreso.

## 4. Primera oleada: inventario y auditoría de sólo lectura

Empieza pequeño con **dos Tasks independientes**:

1. Core, herramientas, scope, modelos/proveedores y protocolos.
2. Server/Session/snapshots, observabilidad, tooling de pruebas, ejemplos/evals y CI.

Los dos primeros workers investigan y entregan propuestas; no editan tests ni
ejecutan suites compartidas simultáneamente. Un único responsable del baseline
compilado. Usa artefactos congelados independientes si necesitas otra ventana.

Inventariar **toda** la superficie: test files/casos, helpers, fixtures, probes,
ejemplos auto-verificados y comandos CI, incluidos tests excluidos. Registrar
contrato, capa, camino de ejecución, oráculo, recurso/efecto observado y resultado
de revisión. Una búsqueda de nombres parecidos no equivale a revisar duplicidad.
Marcar cualquier zona no revisada con motivo, nunca presentar un muestreo como
auditoría exhaustiva. No volcar619 descripciones sin síntesis útil.

## 5. Criterios de valor, duplicidad y defectos del test

Clasificar por familias con ejemplos concretos y referencias a archivos/tests:

- **Mantener:** protege una invariante, modo, frontera o fallo distinto. El mismo
  comportamiento en core, Server, stream o consumidor sin SDK puede requerir tests
  distintos. La matriz de compile order/SDK ausente no se sustituye con la suite raíz.
- **Fusionar:** mismo contrato, entradas equivalentes, mismo camino/fallo y mismo
  poder discriminante. Explicar qué test restante conserva la garantía y por qué
  el refactor reduce mantenimiento sin esconder casos.
- **Eliminar:** redundancia real o prueba vacía/obsoleta demostrada. No establecer
  una cuota de borrado. Revisar el WIP antes y dejar trazabilidad de lo retirado.
- **Corregir:** falsas pasadas, oráculos incompletos, fixtures que no reciben los
  datos declarados, timing frágil, cleanup defectuoso, snapshots o mocks excesivos.
- **Añadir:** un riesgo importante sin cobertura equivalente y una observación
  que demuestre el contrato, no otra variante nominal para contar más casos.

Examinar especialmente:

1. Tests que sólo afirman `passed`, counts o que no hubo excepción, sin resultado,
   efecto, identidad, uso o estado observable.
2. Esperados calculados por el mismo código privado que se está probando; mocks
   que evitan precisamente la frontera bajo test; sentinels nunca introducidos.
3. Round-trips que sólo decodifican sin comparar datos, sumas que esconden atribución
   incorrecta y copias de fixtures gigantes que divergen silenciosamente.
4. Tests privados sobre detalles accidentales frente a invariantes públicas.
   **Defaults, esquemas, errores y formatos publicados también son contratos:**
   comparar campos exactos no es automáticamente «copiar la implementación».
5. Races ocultadas con sleep/timeouts mayores, suposiciones de orden/batching no
   prometidas, procesos/timers/ETS sin owner y contaminación de otras pruebas.
6. Duplicación aparente de sync/stream/Server, versiones, dialectos o permisos que
   en realidad protege caminos distintos. Justificar antes de fusionarla.
7. Helpers de pruebas que convierten el oráculo en otra implementación del framework.
   Compartir sólo lo común; no borrar la independencia de los modelos de referencia.

## 6. Gaps prioritarios que hay que contrastar, no presuponer

- Efectos antes de fallos, ausencia de replay implícito, todos los outcomes de batch
  y respuesta/tool efectiva después de hooks.
- Validación antes de efectos: tipos, keys ambiguas, refs/dialectos/casts, cache
  invalidada; JSV y Ecto conservan sus responsabilidades distintas.
- Scope anidado/concurrente: autoridad heredada, admisión, uso/coste por identidad,
  unknown distinto de cero y subtotales después de pérdida de owner/scope.
- Paridad sync/stream, terminal único, laziness, suspensión/halt/death, framing UTF8,
  truncado, límites, MCP late replies y mailbox ajeno.
- Server/Session: cola/busy/abort, checkpoint confirmado, dirty, retry-save sin
  efectos, restore corrupto/futuro/v1/v2, codecs/policy confiables y FSM.
- Privacidad/contexto: datos realmente observados, redacción antes de exportar,
  Logger/baggage aislados, cancelación y diferencia entre canales ricos y automáticos.
- Paquete/API opcional: bytes TAR, ausencia SDK, orden de compilación, distintas
  versiones y provenance; diagnósticos por fase separados de runtime.
- Snippets/evals/carga: datos que alimentan resultados, controles negativos vivos,
  fuentes/percentiles comprobables y límites de mediciones/probes instrumentados.

La noche ya cubrió muchos de estos puntos. Consultar sus pruebas antes de agregar
algo. Un gap de una feature futura/no implementada se registra como tal: no se
construye la feature durante esta auditoría. No reabrir ReqLLM o C7 por conveniencia.

## 7. Implementar por unidades y comprobar poder discriminante

Tras revisar los hallazgos, asigna nuevas Tasks de implementación con ownership
exclusivo. Prioriza falsos verdes/regresiones importantes; después consolidación
de duplicados demostrados y limpieza de soporte realmente inútil.

Antes de retirar/fusionar un test, deja el contrato protegido, test sustituto y
justificación. Preserva todo WIP ajeno a esa limpieza; no borrar archivos por ser
untracked. No usar reset/clean/stash para comparar con una base antigua.

Para un oráculo dudoso, usa controles positivos/negativos y, cuando aporte,
inyección de un fallo realista o mutación acotada en copia aislada. Distinguir
mutar expected data de mutar el comportamiento observado; no vender lo primero
como una corrupción productiva reproducida. No añadir hooks de test a producción
ni mutar código compartido mientras otros lo usan. Barreras causales y seeds fijas;
nada de sleeps largos o asserts rebajados para ocultar carreras.

Si aparece un bug de biblioteca, reproducir y registrarlo por separado. Corregir
sólo con ownership y alcance explícitos del coordinador; nunca adaptar el contrato
productivo al fixture equivocado ni debilitar schema/permisos para volver a verde.

## 8. Verificación, límites y supervisión

Leer `docs/development/environment.md` antes de usar Mix. El Hex compartido sigue
pendiente de reparación autorizada; no instalar ni reparar globals. Usar PATH y
homes/archives/caches efectivos aislados. Dependencias nuevas sólo si necesarias,
locales y justificadas; no instalar una plataforma de coverage/mutation por inercia.
Fijar sólo `MIX_HOME` no basta: comprobar también `MIX_ARCHIVES`, `MIX_EXS` y el
`erl` efectivo dentro del hijo, evitando shims que reescriban el entorno.
Aplicar `systematic-debugging` y `verification-before-completion` cuando corresponda.

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test <archivos-focales> --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
```

Aplicar el prefijo seguro del entorno cuando haga falta. No --no-compile como
aceptación de fuentes cambiadas. Un solo owner de builds compartidos. Ejecuciones
directas con BEAM existentes pueden investigar un caso, pero se etiquetan como
tales y van seguidas del gate compilado pertinente. No repetir la matriz completa
o el benchmark4000 tras cada cambio pequeño sin motivo.

Mantener los tests de proveedor/DB excluidos salvo autorización expresa. Su
existencia y sus gaps pueden revisarse en lectura. No bajar floors Mint/HPAX/JSV,
ocultar warnings gproc, suprimir diagnósticos, desactivar tests fallidos o crear
otra semántica de ejecución para mejorar una cifra.

Sin commit, bump, push/PR, merge/reset/clean/stash, publish, despliegue, reinicio,
cambio global, datos reales, LLM pagados ni cambios de consumidores. Fixtures
sintéticas, puertos loopback dinámicos, recursos poseídos y trabajo finito.
Usar `apply_patch` para ediciones manuales, conservando el trabajo ajeno.

Correo FIFO completo antes de ACK; responder `reply --id` a preguntas y procesar
también el lote devuelto por ACK. Workers comprueban correo/heartbeat y entregan
worker_done una sola vez; revisores no implementan bajo Tasks readonly. Revisión
final fresca y liberación de recursos propios terminados. No cerrar el turno
simplemente dejando workers activos ni prometer seguir pensando en segundo plano.

Si backend evaluation está activo en otro chat, no robar su Run ni compartir
escrituras/builds sin coordinación con su owner. Seguir en lectura o con un
artefacto congelado hasta acordar la ventana. No aislar en un worktree de HEAD
que silenciosamente pierda el WIP no commiteado.

## 9. Entrega final

Guardar una síntesis mantenible en `docs/development/testing-audit.md`, con una
tabla pequeña contrato/familia, estado, evidencia, acción y limitación; anexar
inventario detallado si hace falta. Actualizar roadmap/status y verification cuando
cambie el procedimiento. Logs extensos de la sesión, al archivo fechado.

Entregar:

- Áreas realmente revisadas y cualquier hueco de auditoría.
- Tests mantenidos/fusionados/eliminados/corregidos/añadidos, con motivos y ejemplos.
- Garantías conservadas y gaps importantes cerrados o pendientes, por prioridad.
- Bugs productivos frente a bugs de fixtures/harness/oráculo, claramente separados.
- Comandos, seeds, runtimes, pass/fail/excluded y, si se mide, tiempo de suite antes/
  después bajo condiciones comparables. Menos tests no equivale a menos cobertura,
  ni más tests a más confianza: explicar cambios de parametrización/denominadores.
- Estado Git, recursos Orca liquidados y siguiente acción concreta.

**Primera acción:** recuperar contexto/autoridad, establecer baseline apropiado y
lanzar el inventario en dos frentes readonly. Continuar a las mejoras justificadas
y su revisión, no terminar al primer verde ni con recomendaciones sin evidencia.
