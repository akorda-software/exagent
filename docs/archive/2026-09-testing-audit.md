# Registro de auditoría de testing — 2026-09-10

Registro fechado de esta sesión cerrada. El mandato es `docs/prompts/testing-audit.md`;
la síntesis mantenible está en `docs/development/testing-audit.md`. Las secciones
de checkpoints anteriores conservan su estado y próximos pasos de aquel momento;
el cierre vigente de esta ejecución está al final del registro.

## Contexto y autoridad recuperados

- Base real: `main`, HEAD `69c27475e9e185f1a562f6d70c62a42329554cbb`, árbol
  inicialmente limpio. `mix.exs` declara 1.3.0; las referencias a WIP sobre c08125b
  y nominal 1.2.0 corresponden al relevo anterior. Esta sesión no cambia versión.
- Orca 1.4.198-kukapu.1, runtime `12d450d9-8e48-4a05-9f77-393ae518ff4f`, host local,
  workspace `/home/kukapu/dev/projects/exAgent`.
- Run propio `run_801c5b1a6984`, generación 1, coordinador
  `term_b94a28fc-dd43-44d1-ad84-24147c80ab18`.
- El Run nocturno terminó sus 16 Tasks y los recursos de sus 15 workers están
  liberados. Su primer Dispatch reutilizado conserva una proyección histórica
  `retained` sin recurso; el Dispatch sucesor acredita el release. No se reutilizó
  ninguno de sus handles. La consulta de su correo por `check` rechazó autoridad
  (`consumer_fenced`); `inbox` de sólo lectura confirmó ausencia de correo pendiente.
- No se encontró otro Run activo de evaluación de backend. Los recursos históricos
  externos o asumidos por el usuario se conservan.

## Ownership inicial

| Task | Dispatch | Responsabilidad | Estado inicial |
|---|---|---|---|
| `task_670a9a56f275` | `ctx_7b9b9c62b5c5` | Auditoría readonly core/tools/scope/modelos/protocolos | Entregada; worker reutilizado |
| `task_f73b6a25aef0` | `ctx_982868645f45` | Auditoría readonly runtime/observabilidad/soporte/ejemplos/CI | Entregada; worker reutilizado |

Ambos lanzamientos confirman `openai/gpt-6-astra` efectivo; heartbeat y lectura del
mandato observados. No ejecutan suites ni editan fuentes. El coordinador posee
la ventana de compilación y los documentos de integración.

## Baseline compilado, antes de modificar pruebas

Prefijo por comando, con PATH directo y tooling aislado ya disponible:

```bash
env -u MIX_EXS -u MIX_PATH -u MIX_INSTALL_RESTORE_PROJECT_DIR \
  PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin \
  MIX_HOME=/tmp/opencode/exagent-native-otlp-mix \
  MIX_ARCHIVES=/tmp/opencode/exagent-native-otlp-mix/archives \
  HEX_HOME=/tmp/opencode/exagent-testing-audit-hex \
  REBAR_CACHE_DIR=/tmp/opencode/exagent-testing-audit-rebar \
  EXAGENT_OFFLINE=1 MIX_ENV=test <comando>
```

El hijo observó Elixir 1.20.0, OTP 29, `erl` efectivo de OTP 29.0.5,
homes/archives aislados y selectores de proyecto ausentes. No hubo instalaciones.

| Comando con ese prefijo | Resultado |
|---|---|
| `mix compile --force --warnings-as-errors` | Exit 0, 73 fuentes |
| `mix test --warnings-as-errors --seed 37556` | Exit 0, 620 correctos, 28 excluidos; 15.0 s (2.9 async + 12.1 sync), max_cases 48 |
| `mix run test/support/consolidation_probe.exs` | Exit 0, 14 indicadores de invariante verdaderos, siete escenarios; no son 14 casos ExUnit |
| `elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs` | Exit 0, 7 correctos, seed 0; 11 bloques ejecutados y cinco recetas/sintaxis |
| Elixir directo con ebin OTel/API/telemetry, `test/support/observability_processor_probe.exs` | Exit 0, 1 correcto, seed 0; copia instrumentada para scheduling R3 |

Logs temporales: `/tmp/opencode/exagent-testing-audit-baseline-{compile,test,c0,docs,r3}.log`.
Los avisos operacionales esperados no se confunden con warnings de compilación.
Proveedores reales/Postgres permanecen excluidos; la matriz de runtimes/paquete de
la noche no se atribuye a esta sesión.

## Inventario aceptado y siguiente oleada

Informes completos leídos: `/tmp/opencode/exagent-testing-audit-{core,runtime}.md`.
Síntesis durable en `docs/development/testing-audit.md` e inventario de base en
`docs/archive/2026-09-testing-inventory.md`: 70 archivos, 648 casos, 19 soportes,
siete templates y 12 ejemplos. Los subtotales 403+247 descuentan los dos cruces de
permisos core/Server y Finch. CI existe y está versionado: la búsqueda glob inicial
no mostró `.github/workflows/ci.yml`; se corrigió esa observación con lectura directa.

Evals baseline: tres informes y criterios positivos, exit 0, seed 131415.
Load smoke baseline: 160 runs correctos en 20 filas, saturación separada de ocho
runs, 32 spans aceptados y 50 descartados bajo barrera; exit 0. JSON y logs en
`/tmp/opencode/exagent-testing-audit-baseline-{evals,load}.{json,log}`. Se comprueba
la fixture finita, no se publica una nueva medida de rendimiento ni concurrencia32.

| Task | Dispatch | Ownership y estado al checkpoint |
|---|---|---|
| `task_6c8da210dd2a` | `ctx_f3a2dd4624af` | Autor A reutilizado: reproducir uso incompleto/schema/MCP/delegación en VMs directas; sin editar biblioteca. |
| `task_f366692c30b6` | `ctx_fa40c433a455` | Autor fresco: tests core/protocolos, oráculos/contexto/hooks/cleanup MCP. |
| `task_39e2718b2433` | `ctx_61a76134ad1a` | Autor fresco: batches OTel, C0/evals/carga/paquete y CI. |
| `task_52c34ec04c8a` | `ctx_b2e7deaf1543` | Autor B reutilizado: tests runtime/eventos/cola/telemetry/codecs/cleanup y Repo sintético. |

Los cuatro usan Astra. Ningún worker hace builds compartidos; los controles usan
copias independientes de fuentes/BEAM. El autor core confirmó snapshot de 11
fuentes/839 BEAM-app sin symlinks en `/tmp/opencode/testing_audit_core_control`,
manifest `ec6f749faf279f9f7aec525557a7a1808386444cabb2194ad2380e086084306c`.
El coordinador conserva documentos y gates de integración.

Decisión CI: conservar combinaciones existentes, hacer explícito offline/test y
warnings, y añadir job de harness nativo. La automatización TAR host-specific se
mantiene pendiente; se verificarán sus fixtures/gates con artefacto local y se
registrarán separadamente los límites de ejecución CI. No se autorizan instalaciones
globales ni se suprime el diagnóstico gproc para volver verde.

Siguiente acción: recibir reproducciones con controles positivos, autorizar fixes
productivos acotados si procede; integrar fuentes congeladas, gates compilados y
revisión fresca. Mantener WIP, sin commits, publicación ni aceptación externa.

## Reproducciones y autoridad productiva — 09:04 UTC

`task_6c8da210dd2a` terminó con 45 casos temporales: 24 correctos/21 fallidos,
cero excluidos; los cuatro grupos devuelven exit 2 de ExUnit. No son 21 bugs ni
aceptación de fixes: son controles y reproducciones negativas de cuatro familias.
Informe `/tmp/opencode/exagent-testing-audit-contract-repros.md` y scripts
`exagent-testing-audit-repros-{g2,g3,g4,g5,support}.exs`, runner `...-run.py`.

- G2: siete fallos de 14; uso omitido/vacío certifica complete/known y permite
  efecto/segunda request bajo presupuesto. Cero explícito y usage nil son controles.
- G3: diez fallos de 17; enums tipados, exclusion y length comparados con Ecto y
  JSV sobre schema público. Dos positivos aislados impiden ocultar rechazo universal.
- G4: dos fallos de ocho; false por ambas keys de schema recibido de tools/list
  termina en tools/call. Casts/refs siguen rechazándose con observador vivo.
- G5: dos fallos de seis; builder recibe args/contexto correctos, pero prompt átomo
  llega vacío al hijo y así vuelve al padre. Keys string y colisiones discriminan.
- B07: reproducción adicional de codec pierde IDs Text/Thinking no nulos;
  `exagent-testing-audit-runtime-id-probe.exs`, exit 1 sobre copia congelada.

Autorización explícita: Task `task_d4a9684f200a`, Dispatch `ctx_3fe21c80717d`,
reutiliza al autor A para los cuatro fixes y nuevos tests de contrato. Es owner
de providers OpenAI/Anthropic, OutputSchema, MCP Protocol, Coordination y la
expectativa legacy de provider_robustness; no toca archivos de los otros autores.
La Task runtime recibió además ownership exclusivo de `lib/exagent/message.ex`
para B07. Decisiones/migración en diseño 8.10–8.11; no cambio de versión.

Al inspeccionar recursos después, Orca marca el terminal del autor B como
`user_owned`/`external_terminal` tras intervención del usuario. Su Dispatch vigente
continúa autorizado y con Astra observado; conservar esa propiedad al liquidar
recursos, sin forzar cierre. Los tres terminales restantes siguen propios.

## Primer gate compilado de mejoras — 09:18 UTC

Todos los owners confirmaron `lib/` y `test/support/*.ex` estables. Los autores B
y harness continuaron sólo con sus tests/scripts no incluidos en este focal.
Con el prefijo aislado del baseline, `mix compile --force --warnings-as-errors`
compiló **75 fuentes, exit 0**. El siguiente comando exacto se ejecutó mediante
Bash (expansión de llaves), con `pipefail` y logs por `tee`:

```bash
mix test test/exagent/{core_contract,structured_output,streaming,tools,coordination,correctness_fixes,compaction,iteration_c,testing_audit_core,provider_usage_contract,output_schema_reflection,coordination_prompt,mcp_schema_boundary,output_schema,output_schema_contract,schema,tool_validation,tool_definition_cache,execution_scope,execution_scope_sequence,tool_boundary_sequence}_test.exs test/exagent/{providers,mcp} test/exagent/scenarios/{real_providers,permissions_mcp,support_agent,long_context,provider_robustness}_test.exs --warnings-as-errors --seed 37556
```

Resultado: **351 correctos, 22 excluidos, exit 0**, 2.9 s; Elixir1.20/OTP29.
Logs `/tmp/opencode/exagent-testing-audit-core-compile.log` y
`/tmp/opencode/exagent-testing-audit-core-compiled-test.log`.
El focal no ejecuta los archivos runtime/harness todavía en edición; no es el
gate final de la suite completa.

Revisión fresca A: Task `task_75896e6dac98`, Dispatch `ctx_b6363beba2c9`, Astra,
readonly de los cambios core/protocolos y cuatro contratos. Los autores conservan
freeze mientras completan informes; no se confunde su `worker_done` con aprobación
técnica independiente.

## Gates runtime/harness e integración intermedia — 09:21–09:23 UTC

Con el mismo prefijo aislado:

```bash
mix test test/exagent/observability/bounded_processor_test.exs test/exagent/framework_evals_test.exs test/exagent/testing_audit_harness_test.exs --warnings-as-errors --seed 37556
elixir test/support/testing_audit_harness_ci.exs harness /tmp/opencode/exagent-testing-audit-harness-compiled
mix test test/exagent/{session,server,server_run_options,server_persistence,session_persistence,pubsub,beam_hardening,permissions,store,resume_integration,event,serialization,store_repo_contract,server_checkpoint_contract,server_ownership,session_fsm_contract,session_cold_restore,runtime_sequence,session_sequence}_test.exs test/exagent/server/snapshot_test.exs test/exagent/store/postgres_test.exs test/exagent/scenarios/{stateful_runtime,server_concurrency,crash_recovery,multi_agent}_test.exs --warnings-as-errors --seed 37556
mix test --warnings-as-errors --seed 37556
```

- Harness focal: **23 correctos, exit 0**, 1.3 s. Driver: seis fases exit0 y
  `warning_lines: []` (compile75, C0, docs7, R3, evals y smoke160). Logs
  `exagent-testing-audit-harness-{compiled-test,ci}.log` y
  `exagent-testing-audit-harness-compiled/summary.term` bajo `/tmp/opencode`.
- B congeló sus 21 archivos completos a las09:22:33 (`msg_5ec930061b41`):
  focal **193 correctos/5 excluidos**, exit0,1.9s; integrado **650/28**, exit0,
  15.9s (2.9 async/12.9 sync), max_cases48. Logs `...-runtime-compiled-test.log`
  y `...-integrated-test.log`.
- El summary harness anterior tiene hashes de dos tests B todavía en edición
  (`server_test` y `scenarios/stateful_runtime_test`); esas versiones no se
  ejecutaban en el harness. Los gates193/5 y650/28 sí son posteriores al freeze B.
  Reviewer B comprobó304/306 hashes y se aclaró la atribución por correo; no se
  presenta el manifest anterior como evidencia de las dos fuentes posteriores.

## Revisión independiente y fixes derivados

- Review A reprodujo dos P2 de OutputSchema en copia propia: booleanos cuando son
  nombres de Ecto.Enum y bounds `is`/min/max dependientes del orden o llamadas
  encadenadas. Ocho casos ampliados:2correctos/6fallidos; no son seis defectos.
- Task `task_d14dc4edce08`, Dispatch `ctx_1eee92b76b5c`, reutiliza al autor de
  tests core, distinto del autor original de G3, para corregir sólo
  `output_schema.ex` y `output_schema_reflection_test.exs`. Review A conserva
  independencia y revisará el delta congelado antes de cerrar. El650/28 anterior
  es deliberadamente una aceptación intermedia, no el gate de estos fixes.
- Review B fresca: `task_1c67147654e1`, Dispatch `ctx_3a0be5845f0d`, readonly de
  runtime/message/harness/CI; no duplica la revisión A.
- Task de ejecución `task_f2e2e8df4939`, Dispatch `ctx_ce779baf77e6`, reutiliza al
  autor de harness para mínimo1.17/27 y cuatro consumidores TAR nativos en copias
  independientes. No se denomina review independiente de su propio harness:
  esa responsabilidad es del reviewer B fresco. Espera freeze final antes de
  capturar WIP; bootstrap sólo local aislado si es necesario, con lock fijo.

Liquidación intermedia: autor G2–G5 `ctx_3fe21c80717d` released/terminal closed.
Autor runtime `ctx_b2e7deaf1543` terminó; release retornó **retained,
external_terminal, processAction none**. Se respeta el terminal bajo control del
usuario. Core y harness se reutilizaron con Tasks/Dispatch nuevos aún vivos, no
con handles cerrados. No hay cambios Git de publicación.

## Aceptación final de fuentes y revisión

Tras el freeze de Reflection, con el prefijo del baseline:

```bash
mix compile --force --warnings-as-errors
mix test test/exagent/{provider_usage_contract,output_schema_reflection,coordination_prompt,mcp_schema_boundary,output_schema,output_schema_contract,structured_output}_test.exs --warnings-as-errors --seed 37556
mix test --warnings-as-errors --seed 37556
mix format --check-formatted
```

Todos exit0:75fuentes, focal45/45 y **655correctos/28excluidos**, seed37556,
max_cases48,15.7s ExUnit. Logs `/tmp/opencode/exagent-testing-audit-final-{compile,test}.log`
y `...-reflection-compiled-test.log`. Es el gate posterior a los dos P2, no650/28.

- Review A aprobada tras repetir sus ocho reproducciones originales (8/8) y
 23contratos (23/23); también repitió T3 y cache-off mediante mutación de conducta.
 Informe `/tmp/opencode/exagent-testing-audit-core-review.md`.
- Review B aprobada sin defectos accionables del diff:54+21tests disjuntos en VMs
 propias, codec anterior rojo y cleanup observado antes de salir de la VM después
 de un assert fallido. Informe `/tmp/opencode/exagent-testing-audit-runtime-review.md`.
- La salida de la auditoría son36casos nuevos y uno ficticio eliminado:648→683
 totales raíz,620→655correctos y28excluidos constantes. Core+4netos, contratos+23,
 runtime+5 y harness+3. Se conservaron los candidatos de fusión sin control completo.
 El helper compartido reemplaza la mecánica de dos mocks, no doce tests de protocolo.

## Mínimo y TAR nuevo, con diagnóstico strict preservado

Captura autorizada por `msg_6c72d747c45e`, terminada09:43:06UTC:226archivos de WIP
tracked/untracked no ignorados, cero borrados, tres copias independientes.
ManifestSHA256 `ec9732722ab8dfe96c6067fe969b1a34467f7c2972a76ffbeda8e9b6bf9b4c56`;
lockoriginal `f99728b5362bd570aa85c8d6a2ebfe178655ba3b726ba04a416990227f4d85f4`.
Datos en `/tmp/opencode/exagent-testing-audit-acceptance-20260910/`.

**Elixir1.17.3/OTP27.3.4.17**: deps y75fuentes desde build vacío independiente,
compile y suite exit0, **655correctos/0fallos/28excluidos**, seed37556;14.9s ExUnit.
No se usaron BEAM históricos para validar las fuentes nuevas. Se comprobaron117
módulos compilados contra fuentes/build propios. Comandos efectivos, con preflight
dentro de cada hijo y los paths propios registrados en `<fase>.json`:

```text
mix deps.get --check-locked
mix compile --force --warnings-as-errors
mix test --warnings-as-errors --seed 37556
mix run --no-start /tmp/opencode/exagent-testing-audit-acceptance-provenance.exs
```

PATH mínimo:
`/tmp/opencode/exagent-night-package-toolchain/otp-27.3.4.17/bin:/tmp/opencode/exagent-night-package-toolchain/elixir-1.17.3/bin:/usr/bin:/bin`.
Todos los homes/archives/deps/build/caches apuntan a la copia117; los JSON del driver
registran argv/entorno/cwd/exit completos. El script driver y el resumen de ejecución
son `/tmp/opencode/exagent-testing-audit-acceptance-driver.py` y
`/tmp/opencode/exagent-testing-audit-acceptance.json`.

**TAR runtime**:93miembros regulares comparados con el freeze, construido09:43:38,
SHA256 `66b6a5f9402a38a19f06e062382384da031ceec34c4ce419c36654c833f9a600`.
Comando con entorno nativo aislado, después de preflight:

```bash
elixir test/support/package_acceptance.exs --tar /tmp/opencode/exagent-testing-audit-acceptance-20260910/preview.tar --checksum 66b6a5f9402a38a19f06e062382384da031ceec34c4ce419c36654c833f9a600 --work-dir /tmp/opencode/exagent-night-package-testing-audit-20260910 --mode all --lock /tmp/opencode/exagent-testing-audit-acceptance-20260910/source/mix.lock --seed 771506
```

| Grafo1.20/29 | Runtime passed/fail/excluded/skipped | Strict | Diagnóstico real |
|---|---|---|---|
| none |6/0/0/0|failed|1deprecación Req0.6.1, compile-edge|
| api |6/0/0/0|failed|1deprecación Req0.6.1, compile-edge|
| sdk |6/0/0/0|failed|1deprecación Req0.6.1, compile-edge|
| exporter |6/0/0/0|failed|1Req/compile-edge +9gproc1.2.0/compile|

El runner conserva **exit1** pese a24/24contratos runtime:13líneas de warning,
ninguna propia de ExAgent. Req declara `xref: [exclude: ...]`, deprecado por Mix1.20;
la compilación1.17 no emite ese diagnóstico. Todos los subprocesses individuales
devuelven0; la verificación por fase es precisamente la que evita ocultar warnings
de dependencias. Se verifican seis nombres/estados reales y104módulos por consumidor,
lock fijo y orden SDK. No se corrigieron ni suprimieron diagnósticos upstream.

El único bootstrap fue Hex2.5.1/Rebar3 local en el directorio nuevo del runner,
autorizado después de comprobar homes/archives/caches efectivos. No se reparó el
Hex compartido ni se instalaron runtimes/servicios. Las VMs propias finalizaron,
con cero procesos supervivientes según los grupos/sesiones registrados. Informe
completo `/tmp/opencode/exagent-testing-audit-acceptance.md` y `package-summary.json`.

## Cierre documental y preview equivalente

Los documentos finales actualizan estado, roadmap, migración, decisiones8.10–8.11,
changelog, índice, verificación y handoff. Se verificaron **134enlaces locales en
25Markdown**, ExDoc warnings-as-errors y formato global. Comandos del coordinador:

```bash
python3 /tmp/opencode/exagent-doc-links.py
EXAGENT_OFFLINE=1 MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-testing-audit-docs
EXAGENT_OFFLINE=1 MIX_ENV=test mix hex.build --output /tmp/opencode/exagent-testing-audit-final-preview.tar
python3 /tmp/opencode/exagent-testing-audit-doc-package-check.py /tmp/opencode/exagent-testing-audit-acceptance-20260910/preview.tar /tmp/opencode/exagent-testing-audit-final-preview.tar
git diff --check
```

Aplicar el PATH/prefijo seguro al Mix y al Elixir hijo del comparador. Logs ExDoc y
Hex en `exagent-testing-audit-final-{docs,package}.log`. Preview documental final:
SHA256 **`955205142f4f390c1c0ff5d538c95fd86aa96ece39d27303d54373decc69152c`**.
Se comparan93archivos contra el checkout: sólo cambian cinco Markdown respecto
del TAR runtime (`status`, `changelog`, `handoff`, `testing-audit`, `roadmap`).

El primer control de metadata byte a byte falló: la captura copiada y el checkout
enumeran archivos y keys de requirements en distinto orden. Se investigó el diff
completo antes de continuar. El comparador final parsea términos Erlang, rechaza
keys duplicadas y compara metadata semántica, incluyendo todas las requirements;
sólo normaliza orden de objetos/lista de archivos. Un control cambia la requirement
y es rechazado. Metadata equivalente, checksum interno válido y **ningún cambio
runtime/requirements**; no se repite la matriz para esa diferencia documental.
Los helpers del control están en `/tmp/opencode/exagent-testing-audit-{doc-package-check.py,metadata-check.exs}`.

## Estado final y siguiente acción

**11Tasks y11Dispatches completados; seis workers Astra.** Se cerraron/liberaron
los cinco terminales propios. El terminal runtime
`term_42bba2c6-17e8-40d1-8617-25e01f609c0f` permanece bajo control del usuario:
release devolvió retained/external_terminal sin acción de proceso. No hay Tasks
activas, correo pendiente ni recursos propios reclaimable. Las seis proyecciones
`retained` de la lista incluyen intentos históricos reutilizados sin recurso y las
dos referencias a ese único terminal externo; no representan seis workers activos.

HEAD y nominal1.3.0 se conservan; `mix.lock` no tiene diff. Los cambios quedan como
WIP sin stage/commit/bump/push/publicación. No se ejecutaron proveedores pagados,
Postgres, backends de trazas ni aplicaciones consumidoras. Los resultados de CI
son configuración y ejecución local del driver, no una corrida remota GitHub.

Siguiente acción concreta: resolver Req/Mix1.20 y gproc/OTP29 sin ocultar warnings,
repetir los grafos afectados y hacer portable el bootstrap TAR de CI. Los gaps P2
restantes y las aceptaciones externas/futuras están priorizados en la síntesis
mantenida; esta auditoría no los presenta como cubiertos por655tests offline.

## Acuerdo posterior de cierre y prioridades — 2026-09-10

El usuario aclaró que el testing interno de dependencias corresponde a sus
mantenedores y pidió documentar el criterio, cerrar esta auditoría y continuar
el desarrollo. La recomendación de anteponer los warnings Req/gproc al trabajo
funcional fue excesiva y queda sustituida por este acuerdo: seguimiento externo
de menor prioridad, con prioridad propia sólo si afecta una garantía de ExAgent.
Los resultados y exit1 strict anteriores se conservan íntegros como evidencia.

La guía de verificación delimita pruebas propias, integración y paquete consumidor,
con gates proporcionales al cambio. Roadmap/status/handoff registran la auditoría
cerrada y la continuidad del desarrollo; los puntos P2 son referencias para las
unidades pertinentes, no una nueva oleada obligatoria. La nota diferida
`docs/prompts/testing-review-final.md` se reserva para el paquete funcionalmente
terminado y una petición de revisión final. No activa otro Run ni autoriza publicar.

Verificación de esta aclaración documental:141enlaces locales en26Markdown,
ExDoc warnings-as-errors, snippets7/7 seed0 y `git diff --check`, todos correctos.
Preview `/tmp/opencode/exagent-testing-closure-preview.tar`,93archivos,
SHA256 `dd5a17f1409c598e7b8fba5d3eea1c250f1627591bee79e86473d0e8e4f668c2`.
Comparado con el preview documental anterior: sólo cambian siete páginas bajo
`docs/`, metadata equivalente y requisitos idénticos; prompts y archivo siguen
fuera del paquete. La evidencia runtime655/28 sigue siendo la de la auditoría,
no una nueva ejecución de la suite por este cambio de prioridades. Se preservó
el WIP previo; esta aclaración sólo modifica documentación y no inicia workers.
