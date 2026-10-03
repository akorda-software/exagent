# Relevo ejecutable — ExAgent v2, orquestación nativa

**Relevo histórico:** entrada vigente `docs/prompts/continue-native.md` y método
`docs/development/execution-flow.md`. Ownership/pendientes inferiores describen
2026-09-28, no la siguiente tarea. No reactivar reviews o reruns del padre.

Continúa el desarrollo autorizado de ExAgent v2 desde el estado real del checkout,
sin repetir trabajo aceptado. Usa subagentes nativos de OpenCode, NO Orca. Resuelve
por unidades funcionales verificables con revisión independiente; no conviertas
esta lectura en otra auditoría general ni en una cadena fija de agentes.

## 1. Proyecto y memoria

- Repositorio: `/home/kukapu/dev/projects/exAgent`.
- Padre anterior: `ses_f1ace1c64ffeH58YvL9GT86SNi`; HEAD observado `7f25b33`.
- Hay muchísimo WIP legítimo tracked/untracked; no restaurar HEAD ni usar
  reset/stash/clean. No commits, pushes, bump, publicación ni consumidores por este
  relevo. Cualquier autorización externa histórica debe comprobarse en su fuente;
  este prompt no amplía permisos.
- Lee primero `AGENTS.md` y
  `docs/orchestration/2026-09-27-native-f1ace1/CURRENT.md`.
  Después sólo las fichas relevantes. CURRENT contiene también hitos históricos;
  sus recepciones posteriores prevalecen sobre antiguos pendientes.
- Lee `docs/README.md`, `docs/status.md`, diseño2.1–2.3 y8.38,
  `docs/development/roadmap.md`, `docs/changelog.md`,
  `docs/development/r6-implementation.md` y `docs/development/environment.md`.
- Roadmap§5 es el tablero de aceptación. No reabrir R0/Jido ni reejecutar gates
  antiguos por rutina. ReqLLM oficial stock, sin forks/patches/monkeypatch/Jido.
- Para un padre nuevo, crea memoria en un run nuevo bajo docs/orchestration y
  enlaza el anterior; no sobrescribas su CURRENT mientras siga teniendo escritor.
  Los hijos del padre anterior NO son transferibles al nuevo padre.

## 2. Ownership liberado tras error de runtime

**Actualización posterior al segundo reinicio:** el worker
`ses_f1959c317ffe2HZ2l1PTh1sIXm` terminó con error explícito
`Agent not found: "worker"`. Ya NO está activo. El padre comprobó únicamente los
tres BEAM ajenos preexistentes, hashes11/11 intactos y gates terminados en disco.
Libera propiedad producto/build ROOT para el siguiente orquestador; no se ha
despachado revisión ni otro worker. Este padre sólo actualiza el relevo.

No intentar continuar ese hijo desde un padre nuevo ni reparar configuración
global por el error de perfil. Usa los agentes realmente disponibles en tu runtime.
Antes de escribir, contrasta CURRENT y que no haya aparecido otro owner posterior.
Recupera desde archivos actuales y artefactos, nunca sobrescribiendo con baseline.
No polling, sleeps ni mensajes de “cómo vas”; no mates procesos ajenos.

## 3. Baseline aceptado: NO repetir

R6 sigue incompleto, pero están aceptados offline:

1. Constructor/binding, Scope estructural y raíz persistida vacía.
2. Paso único real: input/link confirmado antes del IO, output después; mismo
   loop/Writer/CAS/Store/Scope. Evidencia Model/tools/Retry/output y cleanup.
   Review72, padre35, owner FULL1043/0/28. Ficha `tasks/r6-evidence-contract.md`.
3. Restore input0 (input confirmado/request0 sin operaciones) y completed
   data-only: Frame7 con autoridad raíz/hoja, actual∩original, claim ganador antes
   de codecs. Review171, padre46, owner FULL1088/0/28.
   `/tmp/opencode/exagent-restore-floor-recheck-f199cb6f/REPORT.md`.
   P1 piso singular actual cerrado: persistido se añade como conjunción, no lo pisa.
4. Primera response TEXTUAL confirmada step1→cierre: un Model confirmado, sin
   request nuevo ni repricing histórico. Review169, padre37, owner FULL1125/0/28.
   `/tmp/opencode/exagent-text-review-f19634a3/REPORT.md`, SHA
   `e33afbafb943d5a8fd03533064f7e0eba53cab6fe5b99a0608cdd8d7f2fd4a0c`.

Conserva esos oráculos y los negativos. No atribuyas las suites owner a reviewers
ni extrapoles estos resultados a SQL/live/distribución o R6 completo.
Frame4–6 auténticos se leen para inspección, no se ejecutan sin piso de autoridad.
Dos probes históricos que suponían writer6 permanecen rojos por cambio a7;
incompatibilidad verificada y equivalentes7 verdes. No editar ni relabelar originales.

## 4. Unidad actual: output succeeded atestado — NO aceptada todavía

Encargo íntegro y decisiones aprobadas:
`docs/orchestration/2026-09-27-native-f1ace1/tasks/r6-output-success.md`.

Sólo primera response1 con una atestación output1 succeeded y resultado portable:
consumir partes exactas una vez y cerrar mediante loop/Writer existentes, sin Ecto,
reflexión schema, Model, after_model, mapping, siblings ni nueva output_resolution.
Sin retry, batches, efectos tool previos, formatos/tokens/motor nuevos ni A→B.
Resultado restaurado es JSON portable, no reconstruir struct Ecto.

Binding declarativo host versionado, especialmente output_ref. Cambiar schema
sin versionar refs es incumplimiento del host: no afirmar detección semántica del
código. Descriptor persistido no selecciona módulos ni autoriza un nuevo request.
Atestación result_omitted bloquea preclaim; copia terminal omitida por capacidad
conserva error/marker existente. Floors, presupuesto y ledger intactos.

Artefactos de implementación y recuperación:
`/tmp/opencode/output-success-20260928-061414/`:
- `REPORT.md`: al último punto leído, Milestone3, focal197/197, compile100 WA,
  formato/diff-check0. Estos son resultados owner, no aceptación.
- `baseline-sources.tar`, baseline.patch/status/head: base anterior preservada.
- `RESTART-RECOVERY.md`, `RESTART-SHA256SUMS`: observación del padre al reinicio.
- `red.log`, first/green/matrix/focal/compile/format/full.log: conservar rojos.

Padre comparó11archivos frente al tar: runtime ExAgent/CompositionRestore/
OutputResolution; test textual actualizado, nuevo test output-success y2support;
4docs contractuales. Sin cambios entonces en Frame/Writer/Authority/Scope/Record.
La expansión detectó un fallo causal de fail/2: ante límite de historia fabricaba
stubs incompatibles con la atestación; corrección acotada pendiente de revisar.

**Histórico conservado:** full.log interrumpido sin resumen/exit,
con3fallos de ContinuationTreeBoundariesTest antes de SIGTERM06:41:21.910:
timeouts de operaciones y aserción de retry authorization exacto/+1. No asumir
que son sólo el reinicio o scheduler. La causa histórica no está establecida.

**Evidencia nueva recuperada por el padre tras el error de perfil:**
- `boundary-recovery.log` + `.exit`:7/7,11.4s, exit0.
- `full-recovery.log` + `.exit`:1153pases/28excluidos,290.2s, exit0, WA48 según
  runner/comando del trabajo reanudado. No serialización ni edición de los11
  archivos entre checkpoint y comprobación del padre.
- SHA full-recovery.log:
  `8634f8cc3eadaef980f4ddcde9877101b9d9d61d5accaa2ef7f6a49fc9fdd970`.
- REPORT.md llega hasta diagnóstico focal; su frase «full pendiente» es anterior
  al log completo nuevo. Falta consolidar la entrega final y revisión independiente.

No repetir la suite completa por desconocer estos artefactos: primero coteja logs,
fuentes y límites. Un full verde posterior no borra los fallos históricos ni
demuestra su causa. La unidad output-success sigue NO aceptada independientemente.

## 5. Siguiente acción tras cesión de ownership

1. Leer entrega final/recuperable del worker y contrastar hashes/delta actual;
   no repetir implementación si está hecha. Si hubo interrupción, inventariar
   parcial/procesos y continuar sin perder cambios.
2. Resolver los fallos concretos pendientes, si los hay, con reproducción causal;
   no serializar la suite ni relajar guards/timeouts para fingir verde.
3. Con implementación y gates owner completos, encargar review FRESCA independiente
   del delta output-success, con ownership exclusivo de build y sin editar producto.
   Verificar preflight sin Ecto, lifecycle/claim, partes exactas, omisiones/fail,
   ACK, ledger sin repricing, límites y regresiones input0/texto/floors.
4. Resolver hallazgos, revalidar y sólo entonces consolidar aceptación en roadmap,
   diseño/changelog/status/r6-implementation y memoria.
5. Continuar unidades restantes de R6: output retry confirmado, demás fronteras
   de restore/batches/incertidumbre, secuencia A→B y pausa/reanudación delegada;
   después router/paralelo y R7–R9 según dependencias. No cerrar R6 por slices.

## 6. Verificación y límites operativos

- Shell sin TTY. Usa herramientas reales y patch para edits. Un escritor por
  archivo y un owner de builds ROOT. Lee environment.md para prefijo aislado:
  EXAGENT_OFFLINE=1 MIX_ENV=test y
  MIX_BUILD_PATH=/home/kukapu/dev/projects/exAgent/_build/test.
- Suite habitual: `mix test --seed 37556 --warnings-as-errors --max-cases 48`,
  timeout≥600000. No tests pagados por defecto, no SQL/live por este relevo.
- No tocar Hex/mise/configuración global, secretos ni infraestructura. Tres BEAM
  preexistentes3339/2963360/4019033 fueron ajenos; revalidar contexto, nunca matarlos
  por un test de este proyecto.
- Workers anteriores con invalid_encrypted_content NO se continúan; su trabajo
  recuperado y aceptado está en el repo/fichas. El último worker fue reanudado por
  su mismo padre tras cancelación y terminó con error de perfil; no está activo.
- No prometer continuidad ante caídas. Informes tempranos bajo /tmp/opencode,
  memoria por hitos en repo, manifiestos y deltas frente a baseline preservado.
- No modelo distinto sin petición aplicable. Preferencias históricas de modelos
  constan en CURRENT; Opus estaba bloqueado por OAuth, no reparar credenciales.
- G2/G3/G4/G5 parciales previos no cualifican automáticamente nuevos bytes.
  R7, R8–R9, G4 UI/exporter, CI remota exacta y Luna length_stream siguen pendientes.

Continúa hasta el resultado autorizado verificable o un bloqueo real. Comunica
hitos con brevedad; no pidas permiso rutinario dentro del alcance, no publiques
ni atribuyas éxito a trabajo pendiente de review.
