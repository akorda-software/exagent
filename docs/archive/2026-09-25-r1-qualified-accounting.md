# R1.5 stock: contabilidad cualificada — 2026-09-25

Registro de Task `task_17bcc68fdef1`, dispatch `ctx_6f0c38b372cc`, Astra fresco.
HEAD `7f25b33` + WIP amplio preservado; nominal1.3.0 sin bump. ReqLLM1.24.0,
Req0.7.4/Finch0.22/Mint1.10.1 oficiales existentes, mix/lock/CI sin cambios de esta
unidad. Lock SHA256 `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.
Diseño8.25 precede estabilización de API; plan readonly anterior leído completo,
aplicando las decisiones del coordinador en lugar de sus propuestas superadas.

## Base y alcance

R1.4 recibió aceptación fresca STREAM PARCIAL offline chat_tools_v1, review
`task_dbfcf7b3c823`:123 casos propios/0 fallos, coordinador53 focales, owner
compile80/suite735/0/28 y smoke46/0/0 de grafo fijo. TAR
`12e46f416f40fa4f73f3fe8dd8eca513d9061087b131ed2c29a68c8fccd62128`.
Es evidencia R1.4, no R1 completa ni aceptación contable. Históricos conservados.

Esta unidad sólo adapta métricas públicas stock. No fork/vendor/patch/monkeypatch,
parser proveedor, SSE paralelo o Jido; no installs, catálogo nuevo, liveLLM/DB/Opik,
consumidores reales, config global, reinicios, commits ni publicación. C7, R1.8,
R2 y G2–G6 externos permanecen fuera del cierre de esta Task.

## Contratos y rutas

- `lib/exagent/message.ex`: Usage.accounting mapa string-key allowlisted1, fuente,
  calidad, availability dimensional, semánticas y coste cents/subtotal estimado;
  helpers internos comunes sin nueva jerarquía. Zero válido, no presencia wire.
  Codec JSON conserva calificación; persisted sin marker legacy_snapshot/unknown.
- `models/req_llm.ex`: buffered/stream comparten Response.usage pública; ni
  call_metadata como segunda fuente ni lectura del StreamResponse ya cerrado.
  ModelProfile.accounting_quality declarativa evita branch proveedor en core.
  USD×100 una vez, precedencia total_cost/cost.total; componentes sin moneda USD
  quedan unavailable. Fuente/unidad del public API, no tabla de precios del host.
- `usage_limits.ex`/`execution_scope.ex`: strict default, estimated opt-in con
  request_limit en scope métrico o ancestro; host-only no bloquea por accounting.
  Checks retrospectivos, competencia atómica, sin saldo reservado ni hard cap.
  Intentos Model y reservas tool son los contadores exactos; no nuevo dispatched.
- Ledger por identidad: acumulativo reemplaza, terminal nil sella y conserva
  subtotal/coste previo sin repricing, idéntico repite resultado sin callbacks,
  contradictorio rechaza. Cobertura de input/output/coste es independiente.
  `estimate_cost` mantiene aridades/precedencia y no se prueba con uso0 inventado.
- Agregados details: sólo total_tokens/cache_read/cache_write/reasoning, aliases
  existentes canónicos una vez y string sobre atom; metadata arbitraria omitida
  al agregar pero conservada por operación/historia. Fold3/restore asociativos,
  sin sumar version/price ni reintroducir metadata conflictiva.
- Core/Server/RunStream/OTel: respuesta canónica incluye accounting ya calculado,
  sin repricing al proyectar; pérdida de ledger/owner degrada cobertura y expone
  subtotal con cost_cents nil. Una generación por operación, etiquetas acotadas,
  sin metadata/secret dumps. Cache exclusivo exige dimensiones para GenAI input;
  input inclusivo y reasoning subset no se suman dos veces.
- Server.Snapshot3/SnapshotData: lectores1/2 legacy unknown con valores preservados,
  futuros/corruptos rechazan. Session2 sólo contiene coordinación/policy, no Usage
  ni historia: sin cambio cosmético. Continuation2/envelope1 intactos; restore sólo
  suma nuevo run, nunca convierte historia en operaciones o precio nuevo.

## Gates y oráculos

`qualified_accounting_test.exs`: ReqLLM real/transporte sintético para ausente,
null, sparse, zero y positivo con misma quality normalized; strict zero/positivo
preIO; spec pública con pricing USD positivo/cero y moneda EUR/nil; callback
unknown/error/aridades/precedencia; custom nil/sparse/zero con efecto contado y
strict por dimensión; bounds ancestrales, competición última request, codec
JSON/v3/v2/corrupto/futuro, terminalnil/duplicado/conflicto, alias/fold/restore.

`req_llm_stream_test.exs`: fixture TCP R1.4 ampliada con uso público sintético;
tools+segundo turno en run/stream_text/run_stream,21 combinaciones con7casos de uso,
strictstream preIO y controles de efecto1/request2. Stock buffered sin uso produce
ceros normalizados; stream sin metadata pública conserva nil/unavailable, sin
inventar paridad de números ni leer metadata después de process_stream.
Los guards/Envelope/terminal/cleanup/deadline/ACK originales siguen ejecutándose.

`req_llm_text_runtime_test.exs`: Server/Session/Store/checkpoint fallido/restore,
3requests=3precios=3generaciones, subtotal9/6tokens y1.5cents tras tercer run,
sin repricing al restore o retry-save; OTel normalized/estimated y privacidad.
Scope/sequence/provider_usage/OTel existentes conservan ancestros heterogéneos,
retries, reservas, delegación sin doble ToolReturn y fallos.

## Rojos conservados y causas

- Vertical01 exit3 (2/5): fixture usaba UsageLimits en run opts en vez de definición,
  Test.new inexistente;02/03 (4/5) suponían campo wire Chat sin extra.wire explícito.
  Fixture corregida a API pública real, campos total y perfil;04 5/5 exit0.
- Stream01 25/26 y diagnóstico0/1: la expectativa de complete para stream sin
  metadata era falsa. Se observó public nil; oráculo ahora exige nil/unavailable
  en missing/null stream, con efecto y segundo turno intactos. No nil→0 en host.
- Focal01 48/75 y suite01 717/745: contratos antiguos comparaban struct sin marker,
  snapshot2, nil→0 y probes precio0. Migración explícita preserva oráculos numéricos,
  calidad nueva, efectos/IDs y no-replay. Suite02 741/745: core debía guardar
  accounting canónico para roundtrip; precio parcial pasa a subtotal. Focal03 52/52.
- Ejemplo `examples/framework_scenarios.exs` autorizado expresamente fuera del
  ownership inicial:17 callbacks incluían9probes0. Ahora deriva8=2reportesroot+
  3reporteschild×2ancestros, diario exacto índice/input/output, subtotal0.25; sexta
  request falla sin reporte. Conserva efecto1, autorización, retry explícito,
  checkpoint-only y restore sin replay. No cambios al harness/checker.
- Pricing focal9/10: cost legacy en spec explícita no se convierte en componentes
  en ese camino stock. Fixture usa pricing público documentado por LLMDB;10/10
  con USD→cents positivo/cero, EUR/nil unavailable. No patch upstream ni tabla propia.
- Review fresca `task_5b79c7a35e0c`: probes independientes detectaron P2 dimensional,
  precio-only/subtotalnil y details no aditivos/aliases. Al ejecutar las6probes
  intactas contra root,3ya pasaban por correcciones simultáneas y3fallaron en details.
  Fix canónico/metadata omitida;25/25 con esas6probes+oráculos propios, exit0.
  El coordinador comunicó revalidación independiente14/14; dictamen final espera TAR.
- Suite03 750/751: antigua aserción de metadata arbitraria agregada. Se mantiene
  comprobación exacta de cache.read por operación/historia y exige agregado vacío,
  conforme a la corrección causal, no se elimina el control de preservación.

## Evidencia reproducible del owner

Runner existente `/tmp/opencode/exagent-r11-run.py`, siempre R11_REPORT_ONLY=1;
logs nuevos `.log` completos y `.json` con comando/entorno/exits/tiempo en
`/tmp/opencode/exagent-r11/`. Prefijo environment.md comprobado: Elixir1.20.0/OTP29,
MIX_HOME y archives temporales existentes, EXAGENT_OFFLINE=1 MIX_ENV=test. No deps.get.
Todas las invocaciones mix test usan `--warnings-as-errors --seed 37556`.

| Label r15-stock-* | Comando / alcance | Resultado |
|---|---|---|
| preflight | elixir -e versiones/homes/offline |exit0 |
| vertical-04 | mix test qualified_accounting_test |5/5 exit0, primer checkpoint |
| focals-04 | qualified_accounting, scope, scope_sequence, provider_usage, OTel, ReqLLM stream/text-runtime |91/91 exit0, previo a details |
| review-probes-before-details | mix test probe reviewer intacta absoluta |3/6 exit2, rojo preservado |
| review-probes-after-details | probe reviewer + qualified_accounting + scope_sequence |25/25 exit0 |
| force-compile | mix compile --force --warnings-as-errors |80fuentes exit0 |
| format | mix format --check-formatted |exit0 |
| suite-04 | mix test --warnings-as-errors --seed 37556 |751/0/28 exit0 |
| links | python3 /tmp/opencode/exagent-release-doc-check.py |224 enlaces/42Markdown exit0, antes de actualización final de evidencia |

Avisos conservados: Req function-adapter deprecado, handlers telemetry locales,
args_lost/timeout/killed y checkpoint negativos. Los28 excluidos son22integración
proveedores y6Postgres, no pases. Sin nueva aceptación live o matriz mínima1.18.

## Freeze y distribución

Fuentes runtime verificadas: message SHA256
`ae1969f2d42fa6ace1f6ed9ba39aef80c2aae6e80b0f881a155a6982d0cdb425`, scope
`385e67d06040dc28e95d4270cd820348a3ce44ba115f0ace6b8e0553d801580c`, adapter
`a029c46318b9b977bdc54d5ca4eb8f70b8fce2cadd48043c35445795df98a7f3`.
TAR `/tmp/opencode/exagent-r15-stock.tar`, SHA256
`3c7867ad00661bd426e74e9f86a9f5440168d0bcdecfbff65c1950575fcdae42`.
Manifest `/tmp/opencode/exagent-r15-stock-consumer/input-manifest.json`, SHA256
`2f483ec28a0de653645d2daf54ebdc450ba8a0d445e5943b04cf53b6b7f754b9`.
Materializador comprueba checksum interno Hex, paths y102miembros regulares
idénticos byte-a-byte al checkout; archivo/prompts/tests/deps fuera del TAR.
Dependencias/lock existentes copiados, sin symlinks ni BEAM del checkout; build
nuevo en `/tmp/opencode/exagent-r15-stock-consumer`. No resolución limpia/G5 nuevo.

| Label final r15-stock-* | Comando tras el mismo runner/prefijo | Resultado |
|---|---|---|
| docs | R11_MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-r15-stock-docs |exit0 |
| snippets | elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |7/7 seed0 exit0 |
| preview | R11_MIX_ENV=dev mix hex.build --output /tmp/opencode/exagent-r15-stock.tar |exit0 |
| consumer-materialize | python3 /tmp/opencode/exagent-stream-consumer.py /tmp/opencode/exagent-r15-stock.tar /tmp/opencode/exagent-r15-stock-consumer |checksum/bytes/source copy, exit0 |
| consumer-build | R11_CWD=/tmp/opencode/exagent-r15-stock-consumer mix deps.compile |exit0,68fuentes ExAgent del paquete (sin test/support root) |
| consumer-tests | mismo cwd, mix test --warnings-as-errors --seed 37556 |48/0/0 exit0 |
| consumer-graph | mismo cwd, mix run graph.exs |provenance110 módulos, exit0 |
| final-links | python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-r15-stock.tar |225enlaces/43Markdown,102miembros idénticos, exit0 |
| final-format | mix format --check-formatted |exit0 tras todas las ediciones de tests |
| final-record-links | mismo checker con TAR final, tras añadir este registro |225enlaces/43Markdown,102miembros idénticos, exit0 |

Grafo efectivo ReqLLM1.24.0/Req0.7.4/Finch0.22/Mint1.10.1, sin Jido/SQL ni
OTel API/SDK obligatorios. Caso trace condicional del test stream se verifica en
root instrumentado, no se cuenta como pase del consumidor mínimo. Los avisos
upstream Toml/WebSockex de su build nuevo están íntegros: exit0 no implica
compilación de dependencias sin warnings. La fixture empaquetada añade oráculos
normalized/strict-preIO/estimated-hostbounded sin debilitar guards/efectos/historia.

Fuentes runtime y docs empaquetados congelados al comunicar `msg_70bea164da06` al
coordinador; esta evidencia posterior sólo modifica este registro checkout-only.
Review final fresca `task_5b79c7a35e0c` corresponde al coordinador; no autoaceptada.

Siguiente paso acotado: comunicar freeze/TAR y cerrar dictamen fresco R1.5.
No abrir R1.8/R2 por leer el relevo ni declarar R1/v2 completa.
