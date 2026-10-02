# R1.4: adapter streaming cualificado — 2026-09-22

Registro de implementación acotada; gates finales en curso. HEAD7f25b33 más WIP
amplio preservado, nominal1.3.0. ReqLLM1.24.0 stock, Req0.7.4, Finch0.22,
Mint1.10.1; lock SHA256 `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.
Sin fork/patch/vendor/parser proveedor/transporte propio, instalación ni publicación.

## Base y decisión

Review Astra R1.2 `task_16e800274a86`, informe temporal
`/tmp/opencode/exagent-r12-envelope-review/REVIEW.md`: buffered parcial offline
aceptable para chat_tools_v1, P2 de deadline reproducido/corregido/revalidado, sin
P1/P2 concretos restantes en ese alcance. TAR51f36adc y715/0/28 son evidencia previa.
No se atribuye esa review al nuevo stream ni se declara independiente esta verificación.

Diseño8.24 fija contrato y migración. Model.request_stream, stream_text/run_stream
usan ReqLLM.stream_text + StreamResponse.process_stream(on_chunk/on_result) una vez,
Response final por la frontera buffered común y close público. Guards del resto
de perfiles intactos. Sólo ExAgent ejecuta tools tras validación completa.

## Umbrales previos y alcance medido

-4096 chunks,64KiB external_size/chunk,1MiB external_size sumado, postdecode;
no heap/RAM ni límite predecode. El frame rechazado ya está asignado; upstream
queue/accumulator puede adelantarse y process_stream retiene O(respuesta).
-4096 max_tokens si nil, explícito1..4096; timeout stream nil60s y explícito≤300s.
Buffered conserva default heredado; otros perfiles/framework no heredan ese techo.
-Bridge1 delta sin ACK y un terminal de timeout; progreso público1 snapshot pendiente
más estado actual del guardian, no historial creciente de copias. Historia canónica,
input/resultados de tools y eventos retenidos por caller se explican por separado.
-Fixtures finitas≤2MiB, framegrande256KiB; concurrencias1/8,32frames×4KiB con consumidor
suspendido. Cleanup≤2s y observación del heap productor<4MiB, predeclarado antes del run.
-Focal54 observó68032bytes por productor en todas las muestras1/8, mailboxowner0;
no representa memoria de toda la VM/upstream ni un SLO. DOWNs/socket cerrado verifican
cleanup. Scope existente limita concurrent requests y libera slot; sin controlador global.

## Rojos de desarrollo y correcciones

1. Vertical inicial2/3: readiness2s no alcanzó HTTP en arranque frío; diagnóstico
medido1831ms frente2ms caliente. Readiness pasa a5s, cleanup2s intacto; tests de
deadlines hacen warm-up con una interacción pública real, no mock. No se oculta
como bug de cleanup ni se atribuyen cifras instrumentadas a suite final.
2. Test pre-registro esperaba shutdown mientras prototipo aún usaba kill:4/5.
Productor no-trapping termina por shutdown, evitando crash reports de cancel normal;
regresión sigue matando owner con kill y observa transporte/metadata. Vertical5/5.
3. Focal6/10: tres fixtures usaban usage.requests inexistente (contrato real:
result.request_count); corregidas. La fixture de4098 chunks vacíos no producía chunks
en stock y agotó receive: cambiada a contenido real"x" sin rebajar el oráculo4096.
4. **Rojo real compartido:** test de RunStream/Model.Test con guardian suspendido
retuvo203 snapshots frente oracle1, exit2. Corregido con ACK correlacionado de progreso
y worker enlazado+monitorizado. Tests de guardian muerto, ACK obsoleto y owner muerto
con ACK pendiente cubren Test y ReqLLM; sin fallo silenciado ni terminal inventado.
5. Primera suite integrada:731/734,28excluidos, exit2. Tres tests CoreContract
existentes597/609/622 perdían cierre del source al cancelar: el progreso final
esperaba ACK del guardian ya cerrando antes del unwind del Enumerable. Review fresca
detectó el mismo P2. notify_progress ahora propaga la cancelación reservada; RunStream
marca cancel y no manda más snapshots tras él. Focal50/50 y suite734/0/28 después,
sin cambiar oráculos ni timeout100ms de los tests originales.
6. **P2 fresh review adicional:** productor con trap_exit podía sobrevivir shutdown
y dejar guardian esperando EXIT sin límite. Repro root APIModel+ReqLLM real bloquea
callback telemetry antes del registro:0/1,19excluidos,exit2 (r14-stream-trap-red).
Gracia100ms predeclarada, luego kill/reap del productor propio; sin tocar internals.
Regresión cubre timeout, ownerkill antes y durante registro con metadata/socket DOWN.
Focal53/53 incluye los dos probes originales del reviewer (shutdown y ACK→cancel)
contra fuentes raíz, no se declara una revisión independiente por ejecutarlos.

## Verificación registrada

Runner existente `/tmp/opencode/exagent-r11-run.py` conserva stdout/stderr completo,
comando/entorno/exits/tiempos en `/tmp/opencode/exagent-r11/r14-stream-*.{log,json}`.
Prefijo aislado de environment.md, Elixir1.20.0/OTP29.0.5, offline, seed37556.

| Fase | Comando tras prefijo | Resultado |
|---|---|---|
| r14-stream-focals | mix test test/exagent/req_llm_stream_test.exs test/exagent/req_llm_envelope_gate_test.exs test/exagent/req_llm_envelope_test.exs test/exagent/req_llm_timeout_test.exs test/exagent/streaming_test.exs test/exagent/req_llm_text_runtime_test.exs --warnings-as-errors --seed 37556 |54/54, exit0 |
| r14-stream-cancel-fix | mix test test/exagent/core_contract_test.exs test/exagent/req_llm_stream_test.exs test/exagent/streaming_test.exs --warnings-as-errors --seed 37556 |50/50,exit0 |
| r14-stream-review-fixes | mix test test/exagent/req_llm_stream_test.exs test/exagent/core_contract_test.exs test/exagent/streaming_test.exs /tmp/opencode/exagent-r14-stream-review/test/review_shutdown_test.exs /tmp/opencode/exagent-r14-stream-review/test/review_ack_cancel_test.exs --warnings-as-errors --seed 37556 |53/53,exit0 |
| r14-stream-reviewed-compile | mix compile --force --warnings-as-errors |80fuentes,exit0 |
| r14-stream-reviewed-suite | mix test --warnings-as-errors --seed 37556 |735/0/28,exit0 |
| r14-stream-format | mix format --check-formatted |exit0, previo al fallback100ms; repetir formato final |

Gate incluye texto/deltas/lazy/1request, tools vacías/no vacías, argumentos fragmentados,
invalididad/EOF/terminales incompletos con cero efectos, Ecto vacío/embed/null/retry,
IDs/continuation2/wrap-once/paridad buffered, halt/exception, registro/muerte,
timestampqueued, total/receive timeout, budgets de chunk/bytes/cantidad y scope/OTel.
No se borraron negativos R1.2. Avisos args_lost/timeout son estímulos negativos;
deprecación function adapter Req0.7.4 y aviso telemetry handler local se conservan.

## Pendiente al preparar este registro

Compile forzado, suite integrada, formato/docs y smoke TAR con grafo fijo se registran
al ejecutarse; revisión runtime Astra fresca corresponde al coordinador. G2 live,
R1.5, C7/R1.8 y cierre R1 no se aceptan por esta unidad. Sin accesos pagados/DB/backend,
sin cambios mix/lock/CI/globales/consumidores reales, commits ni bump.

## Recuperación y cierre de gates — 2026-09-25

El coordinador confirmó cerrar la implementación existente tras interrupción,
no rehacer R1.4 desde la base antigua del dispatch. Este intento no cambia fuentes
runtime ni tests: sólo añade evidencia y actualiza estado/handoff/roadmap. Preserva
los rojos anteriores y no atribuye su propia verificación a una revisión independiente.

Tooling existente revalidado: Elixir1.20.0/OTP29, homes/archives locales de
environment.md; runner `/tmp/opencode/exagent-r11-run.py`, sin instalaciones.
Cada fase nueva tiene comando, entorno, duración y exit en
`/tmp/opencode/exagent-r11/r14-recovery-<fase>.json`, salida completa `.log`.

| Fase nueva | Comando tras prefijo aislado | Resultado |
|---|---|---|
| preflight | elixir -e (versiones y homes) |1.20.0/29 y destinos aislados, exit0 |
| compile | mix compile --force --warnings-as-errors |80fuentes, exit0 |
| suite | mix test --warnings-as-errors --seed 37556 |735passed,0failed,28excluded, exit0 |
| focal | mix test test/exagent/req_llm_stream_test.exs test/exagent/core_contract_test.exs test/exagent/streaming_test.exs /tmp/opencode/exagent-r14-stream-review/test/review_shutdown_test.exs /tmp/opencode/exagent-r14-stream-review/test/review_ack_cancel_test.exs --warnings-as-errors --seed 37556 |53/53, exit0 |
| format | mix format --check-formatted |exit0 |
| preview (dev) | mix hex.build --output /tmp/opencode/exagent-r14-recovery.tar |exit0 |
| consumer-build | mix deps.compile |exit0, build nuevo de fuentes copiadas y paquete extraído |
| consumer-graph | mix run graph.exs |exit0, provenance110 módulos del paquete |
| consumer-tests | mix test --warnings-as-errors --seed 37556 |46/0/0, exit0 |
| links-python3 | /usr/bin/python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r14-recovery.tar |224links/42Markdown y102miembros idénticos, exit0 |
| docs (dev) | mix docs --warnings-as-errors --output /tmp/opencode/exagent-r14-recovery-docs |exit0 |
| snippets | elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |7/7, seed0, exit0 |

`consumer-*` usa cwd `/tmp/opencode/exagent-r14-recovery-consumer`; creado con
`python /tmp/opencode/exagent-stream-consumer.py /tmp/opencode/exagent-r14-recovery.tar /tmp/opencode/exagent-r14-recovery-consumer`.
El materializador existente comprueba checksum interno Hex, paths seguros,
bytes de todos los miembros frente al checkout y ausencia de symlinks. Copia
deps existentes y lock; no ejecuta deps.get ni descarga, y construye en un build
nuevo sin BEAM del checkout. Grafo efectivo ReqLLM1.24.0/Req0.7.4/Finch0.22.0/
Mint1.10.1, sin SDK/API OTel opt-in; el caso native trace condicional se ejecuta
en root, no se cuenta como pase del consumidor sin esa API. Es smoke del grafo
fijo, no resolución limpia desde Hex ni repetición de matriz mínima1.18.

**Identidad congelada:**

- TAR `/tmp/opencode/exagent-r14-recovery.tar`, SHA256
  `12e46f416f40fa4f73f3fe8dd8eca513d9061087b131ed2c29a68c8fccd62128`.
- Manifest `/tmp/opencode/exagent-r14-recovery-consumer/input-manifest.json`, SHA256
  `4d99ed082513f81ff9fac33bced047e92ad3fbe88158195ee081d0c78e5e9283`;
  hashes de102miembros, lock y test stream. `graph.term`/`provenance.term` y logs
  del consumidor conservan paths de fuentes/BEAM y grafo efectivo.
- Lock raíz y consumidor:
  `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.
- `lib/exagent/models/req_llm_stream.ex`:
  `12c0eec414aadd4517f767c1bc7017012da2327ea0d16cfd1025956a3fe73be0`.
- `lib/exagent/run_stream.ex`:
  `28cae865ba7fee9094343c3b798472cb0f1721e8101233b34de73acde1cbd44f`.
- `lib/exagent.ex`:
  `407df08253657017f65541a200c953091884caa628f66f1e15c72d8566469317`.
- `lib/exagent/models/req_llm.ex`:
  `c64c12650c35cf8e809f403b2065085cad33bd0ba6f0af8bfeed94f281210e43`.
- `test/exagent/req_llm_stream_test.exs`:
  `787fe18b3e0a686b9544bc137409e26d08d5aa30149abbb8a2f286cbc794121f`.

**Medida y diagnósticos conservados.** Focal root: productor68032bytes, mailbox
owner0 en concurrencias1/8; consumidor mínimo:26640bytes/0, mismas concurrencias.
Ambos bajo el oracle predeclarado4MiB, sin extenderlo a upstream/VM ni RAM dura.
Warnings de compilación de deps: Toml charlists/cláusulas inalcanzables y WebSockex
pin en bitstrings. Runtime conserva deprecación del function adapter Req, aviso de
handler local telemetry y errores/args_lost/killed/timeout de estímulos negativos.
ExAgent compile forzado y ExDoc con warnings-as-errors devuelven0; esto no declara
ausencia de warnings en dependencias. Un intento del checker documental llamó
`python` dentro del PATH aislado que sólo tiene `python3`: FileNotFoundError/exit1
antes de ejecutar el checker, log `r14-recovery-links.log` vacío; se corrigió sólo
el comando a `/usr/bin/python3`, con etiqueta nueva y exit0. No se modificó tooling.

**Estado de aceptación al freeze:** gates del owner terminados; revisión Astra
independiente de recuperación `task_dbfcf7b3c823` a cargo del coordinador, sin
atribuirle aquí un dictamen aún no recibido. Próxima unidad R1.5 tras aceptación
R1.4; uso sigue unknown, C7/R1.8 y G2–G6 pendientes según roadmap. El TAR incluye
el estado revalidado anterior al dictamen; este registro checkout-only conserva
la evidencia posterior sin modificar sus bytes ni reescribir el histórico.
