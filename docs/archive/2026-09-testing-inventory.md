# Inventario de testing revisado — 2026-09-10

Inventario **de la base `69c2747`, antes de las mejoras**. No es un contador vivo.
Dos lecturas completas independientes por área; los dictámenes se aplican a
familias concretas, no autorizan borrar archivos. Síntesis y cambios finales en
[auditoría mantenida](../development/testing-audit.md).

## Tests raíz: 70 archivos, 648 casos generados

Rutas relativas a `test/exagent/`. Casos tras expansión de macros, no número de
declaraciones `test`. **M** mantener; **C** corregir observación/fixture;
**F** candidato a fusión condicionada; **X** externo excluido. Todos estos archivos
se leyeron íntegros; la tabla sintetiza los oráculos y contratos, no sólo nombres.

| Archivo | Casos | Contrato/camino y observación relevante | Dictamen |
|---|---:|---|---|
| `agent_test.exs` | 11 | Core sync: texto/instrucciones, deps, ToolReturn, output/retry, uso y límites. | M/C: efecto del batch y atribución exacta. |
| `core_contract_test.exs` | 25 | Core en tres modos: parciales, outcomes por ID, efectos, preflight, callbacks, terminales, ownership y codec. | M/C: gap de after-tool que transforma. |
| `streaming_test.exs` | 4 | Stream público TestModel: deltas, resultado, instrucciones, uso. | M/F: reduce completo no es backpressure. |
| `tools_test.exs` | 6 | Macro compilada, esquema/descripción literal, callable directo y loop. | M/C: contexto no observado. |
| `schema_test.exs` | 14 | AST/tipos/uniones/literales → JSON y aceptación/rechazo Tool. | M: defaults y exactos publicados. |
| `structured_output_test.exs` | 5 | Ecto final_result, retry/error/texto; un supuesto payload sólo usa TestModel. | M cuatro; F/eliminar ficticio con sustituto. |
| `output_schema_test.exs` | 13 | Required/opcional/null/embeds, reflexión y validación Ecto. | M/C: faltan enum tipado y longitud array. |
| `output_schema_contract_test.exs` | 5 | API/defaults, módulo frío y dos cuerpos reales de request OpenAI. | M: frontera de transporte independiente. |
| `tool_validation_test.exs` | 25 | JSV, refs/dialecto, JSON portable, casts inertes, cache, Unicode/uniqueItems; callbacks con positivo. | M. |
| `tool_definition_cache_test.exs` | 4 | Definición→run, cambio de schema, preflight sin requests y proyección sin cache. | M. |
| `tool_boundary_sequence_test.exs` | 4 | Ref/cache mutado, hooks efectivos, seis outcomes por ID y tamaño batch; journals reales. | M: seeds/iteraciones no son más casos. |
| `correctness_fixes_test.exs` | 10 | Retry, output/siblings, finish_reason, sufijo y Usage.details. | M/C: efecto de siblings y sufijo exacto. |
| `beam_hardening_test.exs` | 4 | Finch smoke, batch ordenado, timeout y telemetry tool/run. | M/C: cleanup/correlación. |
| `iteration_c_test.exs` | 9 | Límites, flags ModelProfile y hooks con mensajes/returns. | M/C: contar mensajes no basta. |
| `final_review_regression_test.exs` | 10 | After-model en tres modos, pérdida scope/subtotal, continuaciones/DOWN y diagnóstico seguro. | M: regresiones distintas. |
| `execution_scope_test.exs` | 22 | Admisión fanout, autoridad, coste por modelo, dedup, deadlines y owner/scope death. | M: efectos/requests/ledger por identidad. |
| `execution_scope_sequence_test.exs` | 7 | Árboles acotados y journals independientes por path/ancestry, límites y modelo efectivo. | M. |
| `coordination_test.exs` | 6 | Dos delegaciones y cuatro handoffs/policies; retorno/uso y cursor. | M/C: builder ignora contexto. |
| `permissions_test.exs` | 20 | Constructor/globs/resolución, deny/ask y matriz core/Server sin efectos. | M/C: observar callables en representantes. |
| `compaction_test.exs` | 28 | Estimación, partición, grupos por ocurrencia, autoridad y proyección/canónico. | M/C: observar input del modelo para no-compaction. |
| `models/opencode_test.exs` | 5 | Go/Zen/config/resolver/identity/finalmodel/credenciales. | M: no aceptación gateway. |
| `providers/openai_chat_test.exs` | 20 | Body Req, extra/precedencia, mensajes/tooldefs, parse/error. | M/C: supuesto roundtrip sólo codifica. |
| `providers/anthropic_test.exs` | 16 | System/bloques/tools/cache/extra y parse/thinking/firma. | M/C: replay y payload completos. |
| `providers/sse_test.exs` | 5 | LF/CRLF/CR en cortes, EOF/DONE/error, límites y laziness. | M: parser sin transporte. |
| `providers/streaming_test.exs` | 7 | Ensamble de índices/tools/usage/thinking, orden/truncado y cierre decoder. | M. |
| `providers/stream_transport_test.exs` | 11 | Req demand, halt/suspend/death, mailbox, límites, no retry/redirect y sockets TCP. | M: exigir peer closure. |
| `providers/protocol_fragmentation_test.exs` | 7 | Dos adapters/tres modos, UTF8, EOF sin efectos y continuaciones. | M: expected independiente además de paridad. |
| `mcp/protocol_test.exs` | 9 | JSON-RPC puro, to_tool y extracción de resultados. | M/C: Agent sin uso; schema false sin prueba. |
| `mcp/client_test.exs` | 31 | Pending/timer/monitor, IDs/respuestas tardías, handshake/frames y mocks. | M/C/F: mocks sin cierre; distinguir timeout real/inyección. |
| `mcp/client_e2e_test.exs` | 6 | Port Python real, init/ready, fallos y supervisor/parent stop. | M: exclusión adicional si falta Python. |
| `mcp/fragmentation_sequence_test.exs` | 2 | Sufijo UTF8 tardío y prefijos válidos antes de EOF/límite, por identidad. | M. |
| `server_test.exs` | 14 | Chat/async/eventos/abort/cola/stream/reset/model/history. | M/C/F: algunos counts/sleeps. |
| `server_run_options_test.exs` | 10 | Permisos/pricing/deadline/scope, cola y opciones internas protegidas. | M/C: forwarding no prueba FIFO. |
| `server_ownership_test.exs` | 12 | Guardian, tools/run DOWN en stop/kill, abort y siguiente run. | M: owners y modos distintos. |
| `server_persistence_test.exs` | 3 | ETS/JSON→restore, not_found y reinicio supervisado. | M/C: fidelidad y child global sin teardown. |
| `server_checkpoint_contract_test.exs` | 19 | Barreras Store, ACK, dirty/cola, save-only retry, parciales, proyecciones y carreras. | M: error/raise/exit/badret distintos. |
| `server/snapshot_test.exs` | 12 | Helpers/JSON, opacos y validación v1/v2/árbol. | M/C: contenido completo y títulos de privacidad. |
| `runtime_sequence_test.exs` | 4 | Tres seeds×64 comandos y owner crash: journal de requests/efectos/terminales/bytes. | M: modelo independiente. |
| `session_test.exs` | 9 | FSM, autoridad, writers concurrentes, eventos, SharedState y roster. | M/C: join real y `or true`. |
| `session_persistence_test.exs` | 5 | Codec/restart/not_found/refs confiables. | M/C: cleanup y fidelidad. |
| `session_fsm_contract_test.exs` | 18 | RR/Initiative/Supervisor, pausas/cursor/roster/handoff/legacy/custom. | M: políticas diferentes. |
| `session_cold_restore_test.exs` | 2 | Purge/load BEAM de policy confiable, ausencia codec y no save. | M: no inline equivalente. |
| `session_sequence_test.exs` | 5 | Tres seeds×48 comandos, due-list independiente y fallos codec/load/poisons. | M. |
| `session/turn_policy_test.exs` | 10 | Dispatcher público y defaults/orden/admisión de tres policies. | M. |
| `store_test.exs` | 9 | Normalize, CRUD/namespace/list, JSON/closure/PID. | M/C: fidelidad y secretos no introducidos. |
| `store/postgres_test.exs` | 4 X | Repo real: CRUD/restore y validación dispatcher. | C/X: tres expectativas desalineadas. |
| `store/session_postgres_test.exs` | 1 X | Session codec→tabla SQL distinta, carga/borrado. | M/X. |
| `serialization_test.exs` | 5 | Conversación completa, args JSON, timestamp fijo, opacos y root inválido. | M: gap Text/Thinking IDs no nulos. |
| `resume_integration_test.exs` | 1 | JSON→run nuevo→callback del modelo. | C: sólo longitudes del historial. |
| `event_test.exs` | 6 | Defaults/identidad/topics/envelope JSON. | M/C: completar campos declarados. |
| `event_error_projection_test.exs` | 5 | Errores anidados/directos, categorías y exclusión de modelo/body sintéticos. | M: canal rico distinto de automático. |
| `pubsub_test.exs` | 10 | Normalize/None/Local/Registry/multisubscriber/Phoenix opcional. | M/C: recepción selectiva no observa orden. |
| `observability/open_telemetry_test.exs` | 21 | Jerarquía, contexto/Logger, redactor/límites, streams, uso, checkpoint/cancelación. | M: sentinels efectivos. |
| `observability/bounded_processor_test.exs` | 16 | Cota/callback/fallo/timeout/flush/restart/owner/observer/bootstrap/config. | M/C: IDs de batches además de counts. |
| `observability/native_otlp_test.exs` | 4 | Cuatro VMs con assertions y marker: wire, fallos y lifecycle. | M: protobuf real, límites upstream explícitos. |
| `observability/native_otlp_scenario_test.exs` | 3 | Compuesto/cola-fallos/privacidad en VMs; 68 spans/11 POST dentro. | M. |
| `framework_evals_test.exs` | 4 | Datos tipados, efecto/restore, controles vivos y input alternativo. | M/C: manifiestos no vacíos y snapshot observado. |
| `scenarios/core_loop_safety_test.exs` | 4 | Args inválidos, hook/changeset raise y max_steps. | M/C: título y efecto de validación. |
| `scenarios/support_agent_test.exs` | 8 | Macro typed+Ecto/retry/uso/budget/batch/hook/deny. | M/C: sumas y efectos exactos. |
| `scenarios/provider_robustness_test.exs` | 7 | Ausente/null/vacío/malformed y uso parcial por adapter. | M/C: unknown frente cero. |
| `scenarios/multi_agent_test.exs` | 7 | Dos Server→SharedState, policies, delegación, handoff/eventos y pause/close. | M/C/F: evento viejo y contribución asimétrica. |
| `scenarios/permissions_mcp_test.exs` | 6 | Discovery→Tool→run, allow/deny/ask y error sin replay. | M/C: mocks y llamadas remotas observadas. |
| `scenarios/long_context_test.exs` | 7 | Summarizer recursivo/custom, tool, sufijo, dos runs y crecimiento. | M/C/F: contenido alimenta resumen, no sólo count. |
| `scenarios/store_and_args_safety_test.exs` | 3 | Dos argumentos no JSON y checkpoint closure/error/log. | M. |
| `scenarios/output_history_replay_test.exs` | 1 | Dos final_result: primer output y resolución de ambos IDs. | M. |
| `scenarios/real_providers_test.exs` | 22 X | 9 básicos+9 tools+3 streams+1 Ecto vía OpenRouter. | M/C/X: stream descartaba terminal error. |
| `scenarios/stateful_runtime_test.exs` | 7 | Script/reset, cola, abort, stream, deps, telemetry y correlación. | M/C/F: FIFO y telemetry propia. |
| `scenarios/server_concurrency_test.exs` | 3 | Stale idle obsoleto, abort tras fin y PubSub fallido. | C/F/M: reemplazar por handlers vivos. |
| `scenarios/crash_recovery_test.exs` | 4 (1 X) | Codec/restore, reset→kill, último checkpoint y cross-store. | M/C: payload y teardown. |
| `scenarios/session_leave_test.exs` | 6 | Roster current/noncurrent/last de tres policies y actor admitido. | M. |

## Soporte, templates y ejemplos completos

| Superficie | Archivos y camino/oráculo revisado | Decisión/límite |
|---|---|---|
| Fixtures `.ex` de schemas/tools | `default_output`, `optional_output`, `nested_optional_output`, `receipt`, `sample_tools`, `ticket`, `weather_report` | Mantener: callbacks/defaults/tipos distintos; contexto macro necesita observación. |
| Policy fría/Repo | `cold_session_policy.ex`, `ex_agent/test_repo.ex` | Mantener BEAM independiente; Repo externo opt-in. |
| Fragmentación | `protocol_fragmentation.exs` | Rand local/cortes UTF8, no parser/oráculo duplicado. |
| OTLP | `native_otlp_receiver.ex`, `native_otlp_probe.exs`, `native_otlp_scenario_probe.exs` | Loopback dinámico, owner/peer-close, codec oficial, callbacks de sentinels/IDs; cuatro y tres selectores. |
| R3 | `observability_processor_probe.exs` | Un test de copia instrumentada en memoria con barrera de scheduling. |
| Documentación | `documentation_probe.exs` | Siete tests, 16 bloques reales: 11 ejecutados con fixtures declaradas, cinco sintácticos. |
| Consolidación | `consolidation_probe.exs` | Siete escenarios/14 indicadores; corregir condición de éxito del gate. |
| Paquete | `package_acceptance.exs`, `package_acceptance_isolation.exs` | Bytes TAR/cuatro grafos/fases/tooling; exigir seis casos runtime reales, negativos de aislamiento sin installs. |
| Carga | `framework_load_probe.exs` | 18 filas+dos soaks+saturación, raw samples/percentiles/recursos; corregir gate de pérdidas normales. |
| Templates (siete) | `mix.exs.template`, `config/config.exs.template`, `graph.exs.template`, `test/test_helper.exs.template`, `test/package_test.exs.template`, `package_smoke.exs.template`, `package_tracing.exs.template` | Ninguno se omite: compile order/SDK ausente, runtime 6 por modo, datos/identidad/provenance; no convertir exit0 sin manifest en aceptación. |
| Evals | `framework_scenarios.exs`, `framework_evals.exs` | Tres reports/criterios reales; rechazar vacíos y comprobar snapshot tipado. |
| Demos locales | `demo.exs`, `stateful_agent.exs`, `multi_agent_session.exs`, `dnd_session.exs`, `observability.exs` | Demos con outputs/scripts, no suites semánticas; mensajes de éxito/contadores no certifican aceptación. |
| Receta | `durable_oban.exs` | Oban/DB comentados; parte ejecutada sólo codec. |
| Demos de proveedor | `openrouter.exs`, `zai_anthropic.exs`, `streaming.exs`, `structured_output.exs` | No ejecutadas; key ausente/exit0 o error impreso son skip/demo, no pase runtime. |
| Entradas | `test/test_helper.exs`, `mix.exs`, `.formatter.exs`, `config/config.exs`, `config/test.exs`, `.github/workflows/ci.yml` | Excluidos, compilación support/SDK, formato sin templates, DB bootstrap y matriz CI revisados. |

## Evidencia y límites de la lectura

Informes fuente completos en `/tmp/opencode/exagent-testing-audit-core.md` y
`/tmp/opencode/exagent-testing-audit-runtime.md`, entregados por Tasks
`task_670a9a56f275` y `task_f73b6a25aef0`. Este inventario persiste la síntesis para
no depender de la conservación de `/tmp`.

Se contrastó la implementación de las fronteras de ExAgent pertinentes. No se
revisaron íntegramente internals de dependencias, cada snippet de históricos/skills,
ni sistemas externos. Los archivos mixtos tienen ownership de implementación
exclusivo aunque la auditoría haya repartido sus familias. No se presenta una
búsqueda de nombres similares ni un muestreo como equivalencia de pruebas.
