# R1.8 — propuesta e inventario previo a retirada

Dispatch `task_51127c5dd54e`, HEAD7f25b33 con amplio WIP preservado, nominal1.3.0.
Recepción review R1.3/6/7 final registrada en roadmap§5 y handoff:4/4 nuevos,
identidad TARd2bfe978, contradicción documental cerrada, mínimo offline únicamente.
La sección inicial conserva el inventario escrito antes de eliminar módulos;
el resultado de implementación y los gates figuran al final. Decisión diseño8.26.

## Inventario exacto inicial

- Retirar `lib/exagent/models/{openai,openrouter,opencode,anthropic}.ex` después de
  migrar `lib/exagent/model.ex` y los callers siguientes.
- Retirar `lib/exagent/providers/{openai_chat,anthropic,sse,stream_transport,event_stream}.ex`.
  Sus únicos callers runtime son los wrappers, referencias mutuas y patrones de
  identidad en `lib/exagent/observability/open_telemetry.ex`.
- Conservar `models/req_llm{,_buffered,_stream,_envelope}.ex`, Model/Test,
  RunStream y todo el runtime de autoridad/uso/codec.
- Migrar identidad/sentinel en `test/exagent/{final_review_regression,
  server_checkpoint_contract,testing_audit_core}_test.exs` a ReqLLM/Test.
- Migrar garantías de payload Ecto en `test/exagent/output_schema_contract_test.exs`
  al sobre público; `iteration_c_test.exs` a capacidades reales cualificadas;
  `observability/open_telemetry_test.exs` a accounting semántico explícito.
- Reemplazar tests de constructor `test/exagent/models/opencode_test.exs` por
  resolución pública, rechazo/migración Go/Zen y auth por instancia.
- Revisar antes de retirar cada suite `test/exagent/providers/{openai_chat,
  anthropic,sse,streaming,protocol_fragmentation,stream_transport}_test.exs` y
  `test/exagent/scenarios/provider_robustness_test.exs`: parsers internos retirados
  dejan de ser superficie propia; framing/errores/invalidargs/cleanup conservados
  deben tener controles por ReqLLM/ExAgent, no borrarse sólo para obtener verde.
- `test/exagent/provider_usage_contract_test.exs` cambia oráculo de presencia wire
  legacy a normalized/unknown/strict; reutilizar matriz stock R1.5 y mantener
  cobertura custom reported parcial por separado.
- `test/support/consolidation_probe.exs` referencia SSE privado: migrar oráculo
  público de fragmentación/terminal, sin copiar tests internos upstream.
- Callers de ejemplos: `examples/{openrouter,streaming,structured_output,
  zai_anthropic}.exs`; live excluido `test/exagent/scenarios/real_providers_test.exs`.
- Referencias de distribución: `mix.exs` sólo grupos ExDoc; README, guías vigentes,
  arquitectura, snippets/probes de documentación y `skills/exagent-run-agent/SKILL.md`.
  No skills globales, consumidor externo, CI, dependencias ni lock.

## Criterio de compatibilidad y gate

Sin shim permanente: callers propios migran a Model.resolve/ReqLLM.new; custom y
Test intactos. Strings stock requieren opciones explícitas para auth/perfil; no
certifican Chat por nombre. OpenCode/ZAI shortcut rechaza explícitamente y guía
spec/endpoint exactos; OpenRouter catálogo no se convierte silenciosamente a OpenAI.
Auth_token Anthropic exige gate público equivalente antes de retirada.

Reusar R1.4/5/7 (run/stream/Server/Session/delegación/Ecto/autoridad/codec/OTel),
añadir sólo huecos de resolución/auth/errores. Registrar conteos antes/después y
razón de cada test retirado; ningún contador promete paridad. Freeze y TAR smoke
requieren identidad nueva y revisión fresca del coordinador; G2/C7 pendientes.

## Resultado implementado y alcance real

El coordinador aceptó la dirección API antes de retirar (`msg_a890bcfb3847`), con
opciones explícitas, tuple/spec sin ambigüedad, custom/Test intactos y sin bloquear
un proveedor stock válido sólo por prefijo. Esto afinó la propuesta inicial:
`zai:` sí resuelve un provider stock, también fuera del catálogo; conserva `:zai`
y **ya no significa el viejo alias Anthropic**. La guía da migración explícita al
endpoint Anthropic, sin cambiar identidad silenciosamente ni declarar GLM
non-reasoning. OpenCode no tiene resolución stock y requiere spec/endpoint exactos.

Se retiraron exactamente los9 módulos runtime inventariados y sus referencias
ejecutables. ReqLLM.new conserva constructor único; resolve/2 acepta sus opciones,
rechaza claves desconocidas/duplicadas, sobrescritura model y opciones que stock
ignoraría dentro de tuplas. LLMDB.Model se trata antes de passthrough custom.
Ninguna selección automática de perfil ni lectura env por el adapter/resolver.
Auth_token se acepta sólo Anthropic, prevalece sobre api_key y usa auth_mode/access_token
públicos. Loopback comprueba cinco destinos/auth, modelo/path exactos, no API key
con Bearer, no subscription, error401 sanitizado y secretos ausentes en Inspect/history.
Un test serial con entorno sintético prueba que env no autoriza una instancia sin key.

Model/endpoint/provider binding, codec2/envelope1/continuation2, snapshot3,
accounting1/strict-estimated, ReqLLMBuffered/Stream/Envelope y lifecycle RunStream
quedan intactos. La única modificación OTel retira patrones de structs desaparecidos;
las semánticas cualificadas siguen proviniendo de Usage.accounting. Los tests de
sentinel conservan la misma exclusión de secretos; los de Ecto inspeccionan schema
lógico dentro del sobre (y required/extra exterior), no relajan validación.

## Retirada inicial de tests:88 menos,12 nuevos; follow-up añade1 caracterización

Inventario ejecutado antes de eliminar, log `r18-retired-inventory`:88 tests
expandidos,87 pasan y1 falla por el cambio **intencional** del resolver OpenCode.
No defecto nuevo del transporte ni motivo para conservar el antiguo alias.
La base era755 passes+28excluidos; resultado nuevo679+28 =755−88+12.
Los28 excluidos (22live,6Postgres) no cambian ni cuentan como aceptados.

| Archivo retirado bajo test/exagent | Tests expandidos | Razón y sustitución de garantías |
|---|---:|---|
| providers/openai_chat_test.exs |20| Helpers encode/parse/config y raw args ya no son API; wire extras arbitrarios rechazan en options. Historia/IDs/toolchoice/schema/errores públicos en req_llm_model/options/envelope; RequestError stock sanitizado en model_resolution. |
| providers/anthropic_test.exs |16| Parser/cache/alternancia propios desaparecen; thinking/tool/continuación no se anuncian por stock. Guards negativos req_llm_model/safety, auth/texto inicial real en model_resolution; no reimplementar codecs para conservar una suite privada. |
| providers/sse_test.exs |5| Gramática/frame buffer privados ya no existen. Stock recibe bytes SSE; req_llm_stream prueba fragmentos/terminal/invalidargs/cleanup y consolidación prueba CRLF fragmentado con mailbox ajeno. No suite interna upstream de todos los cortes/CR/JSON. |
| providers/streaming_test.exs |7| Materialización interleavada/thinking/signatures legacy retirada; paths no cualificados cierran. Envelope fragmentado y terminal inválido sin efectos, una vista, cierre éxito/halt/raise/owner/deadline y estado final: req_llm_stream. |
| providers/protocol_fragmentation_test.exs |7| Se retira adapter doble y parser propio; paridad run/stream_text/run_stream, IDs/historia/UTF8 lógico/JSON incompleto se ejercitan con TCP público en req_llm_stream. No promesa de fidelidad raw ni todas las gramáticas upstream. |
| providers/stream_transport_test.exs |13| Lifecycle y límites públicos pasan a R1.4; predecode byte/declared-chunk bound retirado por8.22, reemplazado por límites host postdecode documentados. Los2tests WIP Mint de garbage/extension migran a model_resolution con ExAgent/ReqLLM reales, ambos modos y cero efectos. |
| models/opencode_test.exs |5| Constructor/plan/env legacy retirado; model_resolution prueba resolución explícita, Go/Zen exactos y auth por instancia; sin plan/env automático ni alias perpetuo. |
| provider_usage_contract_test.exs |8| Presencia wire legacy ya no es inferible stock. R1.5 normalized/strict/estimated real se reutiliza en qualified_accounting/req_llm_stream;4 nuevos custom_usage_contract conservan reported parcial/nil/cero y control efecto1 en3 modos, incluido WIP previo de nil y quality. |
| scenarios/provider_robustness_test.exs |7| model_resolution prueba malformed JSON/null/lista/choices ausentes y error público sin efectos; sparse/zero y metadata en R1.5/guards. No se conserva detección de todo sibling wire: stock borra algunas entradas sin señal, como demuestra el follow-up P2 abajo; inválidos visibles sí invalidan batch0efectos. |

Los8 nuevos `model_resolution_test` cubren specs/tuplas, custom/Test, catálogo y
fuera de catálogo, rechazo de perfiles, auth/env/headers/privacidad, framing inválido
y control válido, y malformed terminal. Los4 `custom_usage_contract_test` conservan
la garantía reportada independiente del proveedor. No se copia testing interno stock.
El probe de snippets añade1 caso (8/8), fuera del contador suite, para construir el
perfil del README con credencial sintética; ejemplos no autorizan IO durante tests.

Reusados sin cambios los gates R1.4/5/7: run/stream/Server/Session/ETS/delegación/
Ecto retry/hooks/autoridad ancestral/codec/restores/coste/OTel. Suite completa los
ejecuta; un fallo no se borra ni se reemplaza por Test para certificar ReqLLM.
El antiguo escenario live sigue excluido y ahora usa provider OpenRouter stock
con guards; no se marca Chat/non-reasoning por slug para forzar esos tests a pasar.

## Rojos diagnosticados

- `r18-migration-focal-01`: propuesta inicial suponía ZAI no catalogado; la API
  pública demuestra provider :zai válido. Se conserva identidad según instrucción.
  Otro fixture omitía schema raíz y el guard abortaba antes de IO: añadido type:object,
  manteniendo assert de recepción real y cero efecto para framing.
- `r18-migration-focal-02`: stock admite slugs ZAI no catalogados por fallback
  público; nuevo control inline externo conserva ID/provider sin warning esperado.
  Framing ya pasaba con error Mint observado en ambos modos y extensión válida.
- `r18-migration-focal-03`: RequestError es struct, no exception; el test llamaba
  Exception.message indebidamente. Se afirma body/model nil más inspect sanitizado,
  sin alterar runtime ni ocultar el error401 público.
- `r18-snippets-final`: delimitador sigil del nuevo probe inválido; corrección
  sintáctica mínima, conservado log rojo; `r18-snippets-final-02` pasa8/8.

## Evidencia owner

Runner existente `R11_REPORT_ONLY=1 python3 /tmp/opencode/exagent-r11-run.py`,
prefijo aislado environment.md, EXAGENT_OFFLINE=1 MIX_ENV=test, Elixir1.20/OTP29;
logs/JSON completos por label en `/tmp/opencode/exagent-r11/`.

| Label | Comando | Resultado |
|---|---|---|
| r18-api-01 | mix test test/exagent/model_resolution_test.exs --warnings-as-errors --seed 37556 |4/4 inicial exit0 |
| r18-migration-focal-04 | mix test test/exagent/{model_resolution,custom_usage_contract,output_schema_contract,iteration_c,observability/open_telemetry}_test.exs --warnings-as-errors --seed 37556 |48/48 exit0 |
| r18-force-compile | mix compile --force --warnings-as-errors |71fuentes exit0 |
| r18-suite-01 | mix test --warnings-as-errors --seed 37556 |679/0/28 exit0 |
| r18-format | mix format --check-formatted |exit0 |
| r18-snippets-final-02 | elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |8/8 seed0 exit0 |
| r18-consolidation | mix run test/support/consolidation_probe.exs --json /tmp/opencode/exagent-r18-consolidation.json |14 invariantes exit0 |

Warnings de function adapter Req y errores operacionales negativos siguen en logs.
Lock SHA256 c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b,
ReqLLM1.24.0/Req0.7.4/Finch0.22/Mint1.10.1. Nominal1.3.0; sin cambio deps/floors/CI.
Distribución se identifica abajo al congelar. Revisión fresca independiente pendiente;
no G2/G3/G4/G5 nuevo, hard RAM predecode, C7 durable, R1 completa ni R2 iniciada.

## Primer freeze, distribución y entrega previa al P2

Primer TAR `/tmp/opencode/exagent-r18.tar`, SHA256
`47fed300df3c593c6abb990683d4583fa2e341ce3f51a2f59f622420aa278afc`.
93 miembros byte-idénticos con checkout;9 fuentes eliminadas frente a102 miembros
del TAR base R1.3/6/7 d2bfe978. Las únicas3fuentes runtime modificadas son
`lib/exagent/model.ex`, `models/req_llm.ex` y `observability/open_telemetry.ex`.
`mix.exs` sólo cambia grupos ExDoc; el comprobador confirma bloque deps intacto.
Config y todos los demás helpers/runtime aceptados permanecen intactos.

Manifest `/tmp/opencode/exagent-r18-identity.json` SHA256
`cf8d9841b19f0b98b30fb333cb880190816ee2fe20a4eebe4e621bc30021535d`:
hashes de93miembros y fuentes propias lib/test/config/examples/skills/mix/README,
inventario exacto añadido/retirado/modificado. Diffs comparativos:
`/tmp/opencode/exagent-r18-package.diff` contra TARd2bfe978 y
`/tmp/opencode/exagent-r18-tests.diff` contra copia independiente revisada R1.3/6/7.
Además de lo empaquetado cambian el registro actual, prompt de continuación,
skill local exagent-run-agent y20paths test/probes (9retirados,2nuevos,9migrados).
No se modifica ORCA_CHECKPOINT, skills globales ni aplicaciones consumidoras.

| Label final | Comando / entorno | Resultado |
|---|---|---|
| r18-final-format | mix format --check-formatted |exit0 |
| r18-final-docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r18-docs |exit0 |
| r18-final-preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r18.tar |exit0 |
| r18-final-identity | python3 /tmp/opencode/exagent-r18-identity.py |93miembros exactos, deps y lock intactos, exit0 |
| r18-consumer-materialize | python3 /tmp/opencode/exagent-r18-consumer.py /tmp/opencode/exagent-r18.tar /tmp/opencode/exagent-r18-consumer |checksum+miembros comprobados; fuentes y lock copiados sin symlinks/BEAM root, exit0 |
| r18-consumer-build | R11_CWD=/tmp/opencode/exagent-r18-consumer mix deps.compile |build nuevo de grafo fijo copiado, exit0 |
| r18-consumer-tests | mismo cwd, mix test --warnings-as-errors --seed 37556 |62/0/0 exit0 |
| r18-consumer-graph | mismo cwd, mix run graph.exs |provenance de98módulos desde paquete, exit0 |
| r18-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r18.tar |225enlaces/45Markdown,93miembros exactos, exit0 |

Manifest consumidor `/tmp/opencode/exagent-r18-consumer/input-manifest.json` SHA256
`8cd397d0174d44059840fd545e580139e1859a27484849dedc6c3dd952564bff`.
Reutiliza fixtures/probes TAR existentes y añade copias exactas de12tests R1.8;
el custom Model externo de fixture sigue ejecutando sin API privada. Tiene50casos
previos+12nuevos; compuestos SDK OTel siguen verificados en root, no en grafo mínimo.
No deps.get, instalación ni resolución nueva: **no es G5 nuevo**. Warnings upstream
de la compilación copiada quedan en su log; no warnings propios del gate final.
Sin repetir matriz mínima1.18, paidLLM, DB, Opik, CI remota, servicios/reinicios,
commit/push/PR/bump/publicación. `git diff --check` exit0.

Un rojo de tooling `r18-identity` detectó el directorio providers vacío, que Hex
incluía como miembro no-file: tras verificar que estaba vacío se quitó con rmdir,
sin tocar archivos adicionales ni relajar checker; preview/identity nuevos pasan.
El primer preview intermedio9679974d precede al cierre de prosa del estado; el hash
47fed300 anterior es el freeze entregado, con runtime/tests iguales a los gates.

Checkpoint fuente/TAR comunicado como `msg_7771f8af38c8`; reviewer fresco asignado
por coordinador `task_a7e85474a9ef`, `ctx_64bf3a9638a2`. Este registro checkout-only
se completa después de congelar y está excluido del TAR. Dictamen pendiente: el
owner no autoacepta R1 completa ni declara candidata/live. Siguiente acción es
review independiente y sus hallazgos, no iniciar R2 por lectura del mandato.

## Follow-up P2: pérdida upstream no detectable por la frontera pública

Mensajes coordinador `msg_66dbb1421725`, `msg_bf3f5767168a` y `msg_28fd06e16ae2`:
review fresco demostró que migración prometía rechazar cualquier sibling malformed
wire, pero stock puede borrarlo y devolver sólo la llamada válida. No es efecto
de la llamada inválida ni ampliación de autoridad; sí una afirmación pública
excesiva. Se reproduce sin cambiar runtime en TCP real, primero con la expectativa
incorrecta original: `r18-loss-boundary-red` exit2,0/1.

`req_llm_loss_boundary_test.exs` mantiene matriz de8casos por API pública stock y
ExAgent: control válido1efecto; sibling id-only/null/name-only perdido1efecto de
la única llamada válida; JSON truncado/sobre ausente/schema inválido **visibles**
rechazan batch completo0efectos; válido+sibling perdido con permiso deny0efectos.
IDs de retorno y reservas host comprobados. En los3casos perdidos, tool_calls,
error, provider_meta, message.metadata y call_metadata públicos son idénticos al
control válido: error nil, metadata sin flag de drop. No señal pública que permita
rechazo selectivo de ese batch. El negativo visible, incluida invalidez expuesta
por stock, se conserva sin repair/default/clamp. No parser privado ni fork.

Coordinador confirma alcance8.22: se validan **todas las llamadas semánticas
expuestas**; no se conserva una promesa raw sobre entradas desaparecidas ni se
cuentan como reservas host. Se corrigen diseño8.26, migración, changelog, tabla
única roadmap/handoff/status y esta matriz, sin cambiar lib/guards. Caracterización
durable ahora1 test adicional: total13nuevos y suite **680/0/28** =755−88+13.
El rojo original y el log del reviewer se conservan, no se oculta la limitación.

Gates nuevos del follow-up: `r18-loss-boundary-green` ejecuta caracterización+
envelope+stream,36/36 exit0; `r18-lossfix-suite` completa680/0/28 seed37556 exit0.
Compile71 y resto de pruebas runtime previas siguen sobre fuentes lib idénticas;
el test nuevo y documentos requieren nuevo TAR/manifest y smoke identificados abajo.

### Freeze final tras el P2

`/tmp/opencode/exagent-r18-lossfix.tar`, SHA256
`6a2eb6aa4832c1b4719c98d8ada9179c07c233c427fbfedd6702a3714c01e9d6`.
Manifest `/tmp/opencode/exagent-r18-lossfix-identity.json`, SHA256
`be16bc2c52361a1f73a75d1953b6e92fbf57b852ec76e39afb52a2b6eddaf619`;
diffs `exagent-r18-lossfix-{package,tests}.diff` en `/tmp/opencode`.
Checkpoint final `msg_0a626c0401ff` informa al coordinador/reviewer. El TAR47fed300
anterior y su consumidor62/0/0 se conservan como evidencia previa, no el artefacto
final nuevo. Este registro excluido del paquete se completa después del freeze.

`r18-lossfix-compare` exit0 demuestra:93miembros idénticos root/TAR, sólo6documentos
empaquetados cambiaron respecto al freeze anterior;198fuentes propias previas
lib/test/config/examples/skills/mix/README permanecen byte-idénticas y se añade
únicamente `test/exagent/req_llm_loss_boundary_test.exs`. Lock c20a0cb9 intacto.
Comparación durable temporal: `/tmp/opencode/exagent-r18-lossfix-comparison.json`.
No nueva edición runtime ni necesidad de repetir compile71 después del follow-up.

| Label final | Gate | Resultado |
|---|---|---|
| r18-loss-boundary-green | mix test test/exagent/req_llm_loss_boundary_test.exs test/exagent/req_llm_envelope_test.exs test/exagent/req_llm_stream_test.exs --warnings-as-errors --seed 37556 |36/36 exit0 |
| r18-lossfix-suite | mix test --warnings-as-errors --seed 37556 |680/0/28 exit0 |
| r18-lossfix-format | mix format --check-formatted |exit0 |
| r18-lossfix-docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r18-lossfix-docs |exit0 |
| r18-lossfix-preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r18-lossfix.tar |exit0 |
| r18-lossfix-identity | python3 /tmp/opencode/exagent-r18-identity.py /tmp/opencode/exagent-r18-lossfix.tar |93miembros exactos, exit0 |
| r18-lossfix-consumer-materialize | python3 /tmp/opencode/exagent-r18-consumer.py /tmp/opencode/exagent-r18-lossfix.tar /tmp/opencode/exagent-r18-lossfix-consumer |fuentes/lock copiados de nuevo sin symlinks/BEAM root, exit0 |
| r18-lossfix-consumer-build | R11_CWD=/tmp/opencode/exagent-r18-lossfix-consumer mix deps.compile |build nuevo grafo fijo, exit0 |
| r18-lossfix-consumer-tests | mismo cwd, mix test --warnings-as-errors --seed 37556 |63/0/0 exit0 |
| r18-lossfix-consumer-graph | mismo cwd, mix run graph.exs |provenance98módulos, exit0 |
| r18-lossfix-compare | python3 /tmp/opencode/exagent-r18-lossfix-compare.py |identidad antes/después y consumidor, exit0 |
| r18-lossfix-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r18-lossfix.tar |225enlaces/45Markdown,93miembros exactos, exit0 |

Manifest nuevo consumidor `/tmp/opencode/exagent-r18-lossfix-consumer/input-manifest.json`
SHA256 `778b7485824ec3adbce01bd18962115acc58c65311fc1bc846570679a3bf1c72`.
63=50previos+13nuevos, incluyendo caracterización TCP P2. Mantiene grafo fijo
copiado, no G5 nuevo; las limitaciones y exclusiones anteriores no cambian.
Recepción final del dictamen fresco sigue pendiente del coordinador; P2 de prosa
reproducido/corregido por owner con el límite aceptado8.22, no autoaceptado.

## Cierre recuperado y recepción del dictamen — 2026-09-26

El párrafo anterior conserva el estado al congelar TAR6a2eb6aa. En la recuperación
`ctx_83d9bc26b51b`, el coordinador confirmó el dictamen final de
`task_a7e85474a9ef` / `ctx_64bf3a9638a2`, leído en
`/tmp/opencode/exagent-r18-review/REVIEW.md`: **perfil mínimo offline aceptable
sobre TAR6a2eb6aa, P2 documental cerrado y sin P1/P2 concretos pendientes**.
El reviewer compiló71fuentes y ejecutó6/6 (cinco escenarios propios más el test
owner TCP), seed81537; suite680/0/28 y consumidor63/0/0 son evidencia owner previa,
no ejecuciones independientes del reviewer ni nuevos pases de esta recuperación.
Recepción registrada en la tabla única roadmap§5, handoff, status y prompt; próximo
R2.1 en otra Task con contexto fresco, no iniciado aquí. G2/R1 completo/C7 pendientes.

### Delta documental preservado y comprobación funcional

La interrupción dejó **cinco archivos lib**, no seis, con docstrings corregidos:
`capability.ex`, `compaction.ex`, `coordination.ex`, `mcp/client.ex` y
`usage_limits.ex`. Los ejemplos ya no proponen strings sin credenciales/perfil;
Capability usa Test, compaction recibe instancias confiables, coordinación/MCP
reciben el modelo cualificado, MCP desempaqueta `{:ok, tools}` y UsageLimits explica
estimated con límite finito. `examples/durable_oban.exs` cambia sólo un comentario
a factory confiable. Tres skills **locales** (`exagent-server`, `exagent-session`,
`exagent-tools`) explican auth/perfil explícitos y reutilizan `chat_model`.
Los otros ejemplos migrados antes del freeze revisado permanecen byte-idénticos.

Se comprobó checksum del TAR6a y cada miembro contra la copia del reviewer antes
de usarla como base. `exagent-r18-docclose-ast.exs` compara el AST de **59fuentes lib**,
ignorando únicamente atributos doc/moduledoc/typedoc y metadata line/column:
**ninguna diferencia funcional**. El diff textual confirma que lo excluido es
documentación. Inventario de199fuentes propias conservado; todos los tests,
config, mix.exs y mix.lock byte-idénticos a la entrega revisada. Helpers ReqLLM,
guards, lifecycle, codec y contabilidad intactos. No se repite suite/matriz ni se
atribuye revisión fresca de nuevos bytes documentales por esta equivalencia.

Esta recuperación modifica además seis documentos empaquetados (índice, diseño,
changelog, handoff, roadmap, status), prompt de continuación y este registro
checkout-only para recibir el dictamen. No otras retiradas ni cambios a fuentes
funcionales, dependencias/floors/CI/nominal o aplicaciones consumidoras.

### Gates nuevos y artefacto final documental

Runner/prefijo existentes, `R11_REPORT_ONLY=1`, sin instalaciones ni deps.get;
logs/JSON en `/tmp/opencode/exagent-r11/`. Todos los gates siguientes **exit0**:

| Label | Gate | Evidencia |
|---|---|---|
| r18-docclose-compare / final-compare | python3 /tmp/opencode/exagent-r18-docclose-compare.py | TAR revisado/copia y final/root exactos; inventario199, tests/config/mix/lock y manifest consumidor previo verificados |
| r18-docclose-ast | elixir /tmp/opencode/exagent-r18-docclose-ast.exs | AST funcional idéntico59lib |
| r18-docclose-compile | mix compile --force --warnings-as-errors |71fuentes, Elixir1.20/OTP29 |
| r18-docclose-format | mix format --check-formatted |sin diferencias |
| r18-docclose-snippets | elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |8/8 seed0; auth sintética, sin proveedor live |
| r18-docclose-docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r18-docclose-docs |HTML/Markdown/EPUB |
| r18-docclose-preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r18-docclose.tar |preview nominal1.3.0 |
| r18-docclose-identity | python3 /tmp/opencode/exagent-r18-identity.py /tmp/opencode/exagent-r18-docclose.tar |93miembros exactos |
| r18-docclose-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r18-docclose.tar |225enlaces/45Markdown |
| r18-docclose-plan | python3 /tmp/opencode/exagent-v2-plan-check.py /tmp/opencode/exagent-r18-docclose.tar |57unidades,10escenarios,6gates |

TAR final `/tmp/opencode/exagent-r18-docclose.tar`, SHA256
`5484bf0ac22df0b605bb71c543875617b01c01d4ee5e726d9a90ec6de1871d88`.
Manifest `/tmp/opencode/exagent-r18-docclose-identity.json`, SHA256
`48ad28801ebf2bcdb7b169e8a5c3ba89a0c23c950eabdb141b13473a32f0fe6d`.
Diff contra el TAR revisado: `/tmp/opencode/exagent-r18-docclose.diff`;
comparación `/tmp/opencode/exagent-r18-docclose-comparison.json`.
Los diffs `exagent-r18-docclose-{package,tests}.diff` son contra la baseline R1.3/6/7,
no sólo este cierre. Checkpoint fuente/TAR `msg_e149f9c4e78b`.

Se reutiliza evidencia consumidor63/0/0 del TAR6a sin un nuevo build/ejecución:
manifest SHA778b7485… y sus tests se verificaron otra vez, grafo/lock idénticos y
AST funcional lib equivalente. **No es un smoke nuevo del TAR5484 ni G5 nuevo**;
el nuevo artefacto tiene gates de empaquetado/compilación/documentación e identidad.
Lock sigue c20a0cb9…, ReqLLM1.24.0/Req0.7.4/Finch0.22/Mint1.10.1. La pérdida de
siblings upstream sigue documentada, no resuelta. No live/DB/Opik/publicación ni R2.
