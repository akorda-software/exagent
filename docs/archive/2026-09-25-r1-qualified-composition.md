# R1.3 / R1.6 / R1.7 — composición mínima cualificada

Registro checkout-only, 2026-09-25, dispatch `task_08559dbb6a28`.
Owner único root; baseline `7f25b33` + WIP conservado, nominal1.3.0.
No cambio runtime, dependencia, backend por defecto ni contrato publicado: cuatro
oráculos nuevos cierran huecos de evidencia, reutilizando los gates aceptados.
Revisión fresca de este delta corresponde al coordinador y queda pendiente.

## Base recibida antes de avanzar

Review R1.5 `task_5b79c7a35e0c`, informe
`/tmp/opencode/exagent-r15-stock-review/REVIEW.md`: aceptable offline,
173/173 exit0, sin P1/P2 concretos pendientes en ese alcance. TAR
`3c7867ad00661bd426e74e9f86a9f5440168d0bcdecfbff65c1950575fcdae42`;
suite owner751/0/28, seed37556, consumidor48/0/0 de grafo fijo copiado y
coordinador40 exit0 comunicados. Esta recepción se registró en roadmap antes
de las nuevas pruebas; no se reabrió R1.5 ni R0/Jido.

## Matriz de criterios y demostraciones

Todos los nombres siguientes son tests concretos bajo `test/exagent/`.
La suite nueva reejecuta los gates previos; sus fronteras runtime están intactas.

| Unidad / criterio pertinente | Evidencia discriminante | Estado / límite |
|---|---|---|
| R1.3 perfil y metadata | `req_llm_envelope_test`: terminal failures/unqualified APIs; `req_llm_model_test`: signed Anthropic continuation, Google signature loss; `req_llm_safety_test` | Guard preIO fuera del Chat explícito; no se acepta metadata perdida |
| R1.3 historia/ID/envelope1 | `req_llm_envelope_test`: public run logical hooks/DI; history requires explicit codec | IDs/orden/resultados intactos, wire envuelve una vez; strings/marker ausente/schema inválido rechazan |
| R1.3 continuation2 ligada a destino | **Nuevo** restored qualified continuation bound to provider/model/endpoint | JSON roundtrip; alterar cada target o cambiar instancia model/endpoint rechaza sin IO |
| R1.3 hooks/schema | envelope tests effective hook arguments, subset, permissions; stream tests fragmented envelope | Args lógicos y efectivos validados, identidad no sustituible; refs/stricttrue siguen preIO |
| R1.3 compaction/JSON/snapshot3 | envelope Server restore/compaction y textual runtime existente; **nuevo compuesto** TCP+Session/ETS | Compaction sólo proyección, historia canónica conserva codec; snapshot3/restore no replay; lectores v1/v2 unknown se reejecutan en suite |
| R1.6 settings/precedencia/auth/gateway | `req_llm_options_test`: nil defaults, HTTP receive precedence, run overrides/auth isolation | Payload efectivo y auth por instancia; no borrar defaults por nil ni cruzar endpoint |
| R1.6 intentos/retries/redirects | options max_retries0/redirectfalse; `req_llm_timeout_test` real503/307 y budget/pool | Una request real en fallos/redirect; sin fallback/retry oculto |
| R1.6 sobre/repair/strict | envelope gate negativos y schema; reserved json_repair/max_retries/strict preIO | `json_repair:false`, strictfalse omitido en wire, no optional→required |
| R1.6 tool choice/output | **Nuevo** internal tool choice test y compuesto Ecto | auto/required según allow_text_output y Ecto; native rechaza preIO. No knob público nuevo; R2.3 native pendiente |
| R1.7 efecto/DI/delegación/retry | **Nuevo** qualified TCP delegation and Ecto retry | Dos endpoints loopback/modelos distintos; parent3+child2=5 requests,2 reservas de tool,1 efecto; Ecto changeset rechaza primer final_result y acepta segundo |
| R1.7 Session/Store/checkpoint/restore | Mismo compuesto, Server.chat stream_text:true | Save inicial falla con resultado preservado; nueva mutación bloqueada, checkpoint sólo guarda; Session restituye estado/ref; restore mantiene historia/uso y no repricia |
| R1.7 autoridad/Server.stream/Event | **Nuevo** Server public stream ancestor denial | Hijo pide allow pero ancestro niega effect:0 efectos,4 requests/2 reservas, ToolReturn denied; terminal público conserva normalized y coste unavailable |
| R1.7 OTel/contabilidad | Ambos nuevos compuestos + R1.5 stock matrix sync/stream_text/run_stream | Una generación por operación (6 con nuevo turno,4 denied); coste estimated/availability y provider_presence unknown; no generación adicional por checkpoint/historia |
| R1.7 lazy/bounds/terminal/cleanup | `req_llm_stream_test`, suite completa | Se reusan gates R1.4 intactos: una vista, chunks/bytes postdecode, incompleto0efectos, close/reap, cancel/progress ACK |

No acepta universalidad de providers, reasoning/native/refs/stricttrue,
C7 durable, CAS, Postgres, Opik real ni G2/G3/G4/G5 nuevos. El approval callback
existente no se equipara a aprobación persistida. El transporte TCP sólo emite
fixtures sintéticas y se cierra en teardown; ReqLLM real realiza la interacción.
No se ejecutan tools desde sus callbacks ni se reemplaza Model por un mock.

### Oráculos contables del compuesto

El primer resultado tiene5 operaciones modelo,2 reservas tools y1 efecto; input15,
output10 normalizados y coste estimado2.5cents. El estimador aridad2 se invoca7 veces:
3 operaciones parent +2 child por2 ancestros. El diario distingue3parent/4child;
no se confunden callbacks por ancestro con generaciones ni con doble suma.
Checkpoint fallido/retry y restore mantienen7; un nuevo turno añade una operación,
una estimación y una generación: totales históricos input18/output12/coste3cents.
Cada historia wire contiene el sobre exactamente una vez, IDs y resultados pareados;
prompts/deps parent/child no cruzan. La historia padre no importa historia del hijo.

El segundo escenario tiene4 operaciones,2 reservas y0efectos por denegación ancestral.
Stock carece de precio para estos specs sintéticos: tokens normalizados disponibles,
coste unavailable/nil en resultado, Server, Event y OTel. No se exporta factura0.

## Rojos preservados y clasificación

Logs `r137-focal-01` a `04` no son defectos runtime nuevos:

1. Fixture usaba validate_inclusion Ecto, proyectado como enum JSV: rechazo temprano
   correcto, no retry changeset. Se usa validate_change como gate Ecto existente.
2. Estimador aridad1 es homogéneo: precio child desconocido correcto. Fixture cambia
   a aridad2 para dos modelos, sin alterar herencia/contrato.
3. Aserción esperó5 callbacks globales: contrato por ancestro da7. Coordinador lo
   señaló y lectura de descriptors lo confirmó; añadido diario y no-reprice explícitos.
4. Aserción OTel esperaba ausencia input gen_ai: perfil cualificado tiene semántica
   inclusive conocida. Se comprueban normalized_input3, output2, quality normalized,
   provider_presence unknown e input_semantics inclusive, sin atribuir presencia wire.

## Verificación owner

Runner existente `/tmp/opencode/exagent-r11-run.py`, `R11_REPORT_ONLY=1`,
prefijo aislado environment.md; logs/JSON completos en `/tmp/opencode/exagent-r11/`.
EXAGENT_OFFLINE=1 MIX_ENV=test, Elixir1.20/OTP29; no instalación ni deps.get.

| Label | Comando | Resultado |
|---|---|---|
| r137-focal-05 | mix test test/exagent/req_llm_envelope_test.exs test/exagent/req_llm_text_runtime_test.exs --warnings-as-errors --seed 37556 |16/16 exit0 |
| r137-compile | mix compile --force --warnings-as-errors |80fuentes exit0 |
| r137-suite | mix test --warnings-as-errors --seed 37556 |755/0/28 exit0 |

Los28 excluidos continúan22 proveedores live+6Postgres; avisos de function adapter
Req y logs negativos se conservan. No son fallos ni pases externos.

| Label final | Comando / entorno adicional | Resultado |
|---|---|---|
| r137-format | mix format --check-formatted |exit0 |
| r137-docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r137-docs |exit0 |
| r137-snippets | elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |7/7 seed0 exit0 |
| r137-preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r137.tar |exit0 |
| r137-consumer-materialize | python3 /tmp/opencode/exagent-stream-consumer.py /tmp/opencode/exagent-r137.tar /tmp/opencode/exagent-r137-consumer |checksum y102miembros byte-idénticos, exit0 |
| r137-consumer-build | R11_CWD=/tmp/opencode/exagent-r137-consumer mix deps.compile |exit0, build nuevo sobre fuentes copiadas |
| r137-consumer-tests | mismo cwd, mix test --warnings-as-errors --seed 37556 |50/0/0 exit0 |
| r137-consumer-graph | mismo cwd, mix run graph.exs |provenance110 módulos, exit0 |
| r137-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r137.tar |226enlaces/44Markdown,102miembros idénticos, exit0 |

`git diff --check` exit0. TAR SHA256
`853056cb8b6eee1f5fa8de9ae7bdf3772570c3bbe3f7a2e80cd2056b89a1ccb2`;
manifest `/tmp/opencode/exagent-r137-consumer/input-manifest.json` SHA256
`e124852a6c35555e1ded5f1766ce8fe4c67a0a91d7608b75d50257d74979bb42`.
Lock intacto SHA256 `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.
Grafo ReqLLM1.24.0/Req0.7.4/Finch0.22/Mint1.10.1. El smoke copia fuentes/lock
existentes y compila de cero, sin symlinks/BEAM del root ni resolución nueva:
no es G5 nuevo. Incluye los dos tests nuevos de envelope/choice y los probes stream;
los dos compuestos con SDK OTel se verifican en root, no en el consumidor mínimo.
Warnings upstream del build copiado permanecen en log (Toml/WebSockex); no se
atribuyen al proyecto ni se ocultan. No nueva matriz runtime mínimo1.18.

Delta exclusivo de esta unidad: `test/exagent/req_llm_envelope_test.exs` (+2tests),
`test/exagent/req_llm_text_runtime_test.exs` (+2compuestos y helpers locales), este
registro y docs/README, architecture/design (estado R1.5), archive/README, changelog,
development/{roadmap,handoff}, status y prompts/continue-v2-reqllm. El resto del WIP
existente se preserva; ninguna edición a lib/config/examples/mix/lock/CI.

## Inventario mínimo preparatorio R1.8 (no ejecutado)

| Retirada/migración candidata | Consumidores/referencias concretos que debe actualizar R1.8 |
|---|---|
| `lib/exagent/models/{openai,openrouter,opencode,anthropic}.ex` wrappers legacy | `Model.resolve/1`, examples/openrouter, streaming, structured_output, zai_anthropic; skill exagent-run-agent; tests models/opencode y resolución/scenarios reales |
| `lib/exagent/providers/{openai_chat,anthropic}.ex` codecs/request/stream adapters | wrappers anteriores; provider_usage_contract parse_response/Config, providers/* tests y OTel input_semantics branches de structs legacy |
| `lib/exagent/providers/{sse,stream_transport,event_stream}.ex` transporte/parser/materialización propios | providers OpenAIChat/Anthropic; tests SSE/fragmentation/stream transport/Enumerable; test/support/consolidation_probe SSE; docs locales en wrappers stream_options |
| Grupos ExDoc y referencias públicas | `mix.exs` líneas157–164 (readonly en esta Task), README/model specs/snippets y migración; no retirar módulos y dejar docs/struct patterns rotos |
| Tests que sólo necesitan identidad/sentinel de modelo | final_review_regression, server_checkpoint_contract, testing_audit_core, output_schema_contract; migrar a custom/Test o ReqLLM según el oráculo, sin reescribir cifras por borrar casos |

Ruta propuesta para la siguiente unidad: conservar struct custom y `test:` en
`Model.resolve/1`; resolver specs generales mediante `Models.ReqLLM.new` y las
APIs públicas stock, con una decisión major/migración previa para strings legacy,
auth y gateways. No inferir `chat_tools_v1` por prefijo/nombre: exige provider OpenAI,
metadata `openai_chat`, tools enabled/reasoning disabled explícitos y schema soportado.
Un string de catálogo por sí solo no certifica tools ni Chat frente a Responses.
OpenRouter/OpenCode/ZAI necesitan traducción explícita de endpoint/auth/spec (plan
OpenCode y auth_token Anthropic incluidos), o rechazo documentado de la combinación
no cualificada; nunca fallback a transporte viejo para eludir guards.

Eliminar helpers privados sólo después de migrar sus consumidores concretos;
`ReqLLMBuffered/ReqLLMStream/ReqLLMEnvelope` son fronteras host cualificadas, no
transporte/parser propio retirables. Conservar Model dispatch/Test/custom,
Message/Continuation/Usage, lifecycle RunStream y los nuevos oráculos. No capa legacy
general permanente; puente sólo con consumidor/retirada explícitos, si se demuestra
necesario. Esta Task deja todos esos módulos y el backend por defecto intactos.

## Follow-up documental de revisión fresca — 2026-09-25

Dispatch `task_5aa7153c088b`, continuación documental acotada. Reviewer fresco
`ctx_c6cf985f5f8c` confirmó4/4 nuevos e identidad runtime/TAR, sin P1/P2 runtime,
pero encontró que la tabla vigente roadmap§5 aún pedía cerrar R1.5 y declaraba
pendientes los gates R1.6 y el compuesto R1.7. Era una contradicción documental
real de la entrega, no un gate runtime fallido.

Se corrigen sólo las filas R1.3/5/6/7, el rótulo histórico de la revalidación R1.4
y la siguiente acción de §5 en `docs/development/roadmap.md`: R1.5 aceptada173/173
más coordinador40, nuevos gates del perfil mínimo verificados y cierre documental
de review pendiente. Siguiente R1.8 en otra Task tras dictamen, con Astra fresco;
no rehacer R1.5. Entradas actuales de handoff/status/prompt ya expresaban
review R1.3/6/7→R1.8, por lo que permanecen byte-idénticas. Este registro
checkout-only es el único otro documento editado en el follow-up.

Nuevo preview nominal1.3.0: `/tmp/opencode/exagent-r137-docfix.tar`, SHA256
`d2bfe978ba2d2906fd31be39378cdee971fac761239d6808319110001de4387d`.
Se conserva `/tmp/opencode/exagent-r137.tar`, SHA853056cb… de la entrega anterior.
Identidad:102 miembros coinciden byte-a-byte con checkout; respecto al TAR anterior
101 idénticos y **único miembro cambiado `docs/development/roadmap.md`**.
Las68fuentes lib, tests previos y lock c20a0cb9… permanecen idénticos.
Se reutiliza smoke50/0/0 del consumidor fijo anterior verificando todos sus bytes
empaquetados y lock; no nueva suite runtime, build de consumidor ni matriz.

Gates nuevos con el runner/prefijo existente, logs/JSON en
`/tmp/opencode/exagent-r11/`, todos **exit0**:

| Label | Comando |
|---|---|
| r137-docfix-final-docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r137-docfix-docs |
| r137-docfix-final-preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r137-docfix.tar |
| r137-docfix-final-plan | python3 /tmp/opencode/exagent-v2-plan-check.py /tmp/opencode/exagent-r137-docfix.tar |
| r137-docfix-record-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r137-docfix.tar |
| r137-docfix-final-identity | python3 /tmp/opencode/exagent-r137-docfix-identity.py |

`git diff --check` exit0. Diff exclusivo empaquetado:
`/tmp/opencode/exagent-r137-docfix.diff`; evidencia de comparación/checksums y
reutilización del consumidor: `/tmp/opencode/exagent-r137-docfix-identity.json`.
No cambio a lib/test/config/mix/lock/CI ni a los guards, y no publicación.
El cierre documental del dictamen corresponde al reviewer/coordinador.
