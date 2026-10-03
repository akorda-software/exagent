# R3.4 postdecode retention — owner verification, 2026-09-26

Task task_7ee9a6612939 / dispatch ctx_8d3f10e792f2. Baseline R3 parcial aceptada
gate_115377365ca5, TAR29e35296/source643ade77. Estados sólo en roadmap§5.
ADR8.32 escrito antes del código; shape aprobada por coordinación, incluyendo
omisión explícita de metadata contable oversized, sin asumir Usage arbitrario pequeño.

## Reproducción y límites previos

Runner `python3 /tmp/opencode/exagent-r11-run.py LABEL COMANDO...`, tooling aislado
existente de environment.md, EXAGENT_OFFLINE=1/MIX_ENV=test, logs+JSON con exit en
`/tmp/opencode/exagent-r11`. `r34-output-gap-repro` ejecuta la reproducción anterior:
efecto1/requests2/tool65536B/history68792B/H1024, sólo siguiente run rechaza; exit0.

## Perfil de medición finita (umbrales escritos antes del smoke)

Modelo público custom determinista, sin IO externo; tres oleadas de ocho owners
concurrentes, P8192/H16384, cada stream produce dos deltas de256B y una Response
de512B. La enumeración se suspende causalmente tras primer delta hasta orden
explícita del test. Durante suspensión: como máximo un mensaje de datos pendiente
por bridge propio; ningún avance al segundo delta, owner/worker vivos. Al reanudar
cuatro owners concluyen y cuatro se cancelan explícitamente; repetir con owners
nuevos y exigir los24 cierres y DOWN de cada worker≤1s después del cierre.
Plazo total del caso10s. No throughput/SLO ni latencia de LLM inferidos.

Cada callback registra sólo máximos/contadores de tamaños externos, no copias de
payload: historia≤H, datos result-shaped (output/messages/new_messages/usage/
pending_response)≤2H+P+65536; eventos públicos serializados se contrastan contra
16×(2H+P+65536), margen explícito para proyección JSON y duplicación de texto.
RAM de worker≤16MiB en este fixture es un umbral operacional observado aparte,
no una equivalencia con EFT ni hard RAM predecode. La cantidad de24 runs es smoke
finito, no prueba universal de ausencia de fugas; ownership/cleanup foundation y
enumeración de copias complementan la medición.

Casos de batch cuentan diario externo: dos oversized, uno pequeño, uno confirmado
antes de timeout de after-hook y uno incierto durante callable; cinco efectos
observados, una request, status4succeeded/1unknown, sin replay. H40960/P8192.

**Extensión previa al smoke multistep:** por revisión de coordinación se añade un
run S3 con dos tools de6144B y Response final6144B en seis deltas1024B; H24576/P8192.
Debe completar3 requests/2 efectos/3 cierres, historia final entre80% y100% de H,
máximo data≤2H+P+65536, contexto tool≤H+4096 y RAM del worker observada≤32MiB.
Se miden máximos por progress durante todos los pasos (incluido el tercero con
frames previos), no sólo el resultado final; DOWN del worker≤1s al terminar.
Es una muestra finita de la cota paramétrica, no demostración RAM universal.

## Evidencia incremental y rojos

- first-compile: exit0.
- contract-focal-01:9/11, exit2; fixtures usaban aridades incorrectas de Capability
  y medían Response cruda antes de qualification en lugar del objeto canónico.
  Se corrigieron fixtures y se añadió check P del objeto canónico antes de append.
- foundation-focal-01:108/111, exit2; nuevos11 pasan, tres expectativas de versión
  snapshot3 requieren4 tras la migración deliberada. Sin fallo de core demostrado.
- contract-focal-02:41/41, exit0; dieciséis nuevos+accounting/snapshot foundation.

## Correcciones posteriores y evidencia causal

- suite-01:728/737, exit2. Rojos: readiness100ms bajo carga; admisión actual H ya
  no permite añadir prompt a historia exacta; dos races suspendían Server y
  exigían fin del worker sin consumir ACK; dos expectativas snapshot3; exact keys
  de definición; fixture load esperaba done pero Enumerable devolvía halted; y
  RequestError.model se había eliminado sin necesidad. Se conserva el modelo
  confiable en errores pequeños; originales oversized siguen fuera. La barrera
  completion-first ahora usa :sys.install sobre la recepción del terminal real,
  antes de publicar/handle_info: abort compite en cola. No fake ACK ni prueba de
  no-op después de publicar. Abort-first verifica worker vivo esperando consumo.
- suite-red-focal-01:60/60 exit0 (siete archivos afectados); suite-02:738/0/28 exit0.
- Autorrevisión encontró combinación contable grande: comprobar por registro no
  basta para sumas Scope/Server o costes. Se añadió comprobación de ambos agregados
  y del resumen con coste, priorizando campos canónicos que caben (aliases
  incluidos), sin un límite arbitrario pequeño por número. accounting-focal-03
  falla81/82: Scope.check sólo miraba liveness y permitía éxito pese al marker
  agregado; check/admission ahora rechazan ese marker. accounting-focal-04:82/82.
- final-suite:742/743,28 excluidos, exit2; único rojo readiness100ms inicial del
  fixture pending-byte, repetido desde suite-01. Diagnóstico no lo escondió:
  esperó el mensaje y mantuvo assert elapsed≤100, observó**307ms**,742/743 exit2.
  Coordinador autorizó únicamente readiness1s, manteniendo async y todos los
  oráculos bytes/orden/abort/deadlines. No se amplió timeout de runtime ni race.
  Focal nuevo27/27 y final-suite-02:743/0/28 exit0 después de ese cambio.

## Oráculos y alcance de implementación

`test/exagent/retention_contract_test.exs` contiene23 casos públicos; el smoke
añade2. Se preserva el foundation pertinente en el focal139 y suite completa.

| Frontera | Evidencia discriminante |
|---|---|
| P/H/Usage | EFT exacto/+1 para Response, ToolReturn, historia agregada y Usage4096; input rechazado sin request; slots de batch insuficientes0tools/0efectos. |
| Post-effect | Sync/stream_text/run_stream/Server chat/Server stream: un efecto confirmado, content omitido explícitamente, request1, sin replay; final history≤H. |
| Batch | Dos oversized+succeeded pequeño+confirmed antes de after-hook timeout+unknown durante callable: IDs/orden intactos,5efectos/1request,4succeeded/1unknown, H40960. |
| Hooks/errores | Inflación after_model0efectos y after_tool1efecto con marker; causa gigante no vuelve en error/progress; contenido confirmado válido sobrevive a fallo del hook. |
| Accounting | Summary canónico/source/quality/availability preservado; aliases, número grande que cabe, dimensión que no cabe unavailable≠0, precio gigante sin repricing, agregados Scope/Server acotados. |
| History/restore | Canonical no truncada; input actual que no cabe conserva historia anterior; omitted-v1 JSON+snapshot4+ETS real efímero/restored template rechazan otra request antes de IO. Compaction/continuation/native siguen foundation. |
| Stream/resources | Delta custom oversized nunca publicado; partial oversized y unknown no autorizan calls. R1 stock TCP/ownership y cleanup se reutilizan; ACK del bridge Server y guard RunStream acotan las copias en cola. |
| Carga finita |3×8 owners:12completados/12cancelados,24cierres,36deltas, un mensaje bridge pendiente como máximo y DOWN≤1s. S3:3requests/2effects/cierres3, cerca de H sin borrar confirmados. |

Máximos observados del smoke S1: data5219B/history2021B/event projection5107B;
S3: history22805B de24576, data52423B de122880, context9757B, worker RAM109360B
en root (67944B en consumidor). Son unidades distintas: EFT vs memoria reportada
por Process.info. Las3requests S3 conservan los dos resultados6144B, más output6144B.
No se infiere RAM upstream ni todo workflow a partir de25 casos o24owners.

La cota de retención por vista pública es2H+P+64KiB. La retención total de copias
depende de S pasos, C tasks simultáneas y R/T/nodos de Scope: frames protect/try
pueden conservar estados previos, tasks contienen contexto e historia, Scope
retiene Usage/terminal_usage y costes por operación. Es un perfil parametrizado,
con crecimiento O((S+C)H + (R+T)×Usage + buffers P), no una afirmación de RAM≤H.
Los25 oráculos y los smokes contrastan límites/ejecución finitos; callbacks/modelo
vivo/deps/definitions y mailboxes de consumidores PubSub pertenecen a la app.
Las respuestas/tool results originales pueden existir durante decode/validación
antes del check; nunca se vuelven a almacenar en un error/marker como escape.

## Gates finales y comandos

Labels siguientes bajo `/tmp/opencode/exagent-r11`, con prefijo `r34-`;
cada JSON contiene argv/cwd/allowlist/env/exit/duración y cada log salida íntegra.
Runtime Elixir1.20.0/OTP29; el grafo mínimo copiado no es resolución limpia G5.

| Label / comando | Resultado |
|---|---|
| final-compile / mix compile --force --warnings-as-errors |74 fuentes, exit0 |
| final-focal / mix test10 archivos pertinentes --seed37556 --warnings-as-errors |139/0/0, exit0 |
| readiness-final-focal / mix test payload+runtime_sequence+checkpoint --seed37556 |27/0/0, exit0 |
| final-suite-02 / mix test --seed37556 --warnings-as-errors |**743/0/28**, exit0 |
| final-format-02 / mix format --check-formatted |exit0 |
| final-snippets / elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs |9/0/0 seed0, exit0 |
| final-docs y docs-delivery / MIX_ENV=dev mix docs --warnings-as-errors --output destino aislado |ambos exit0; segundo incorpora cierre de prosa |
| final-links / python3 /tmp/opencode/exagent-release-doc-check.py |229 enlaces/49 Markdown, exit0 |
| preview / mix hex.build --output /tmp/opencode/exagent-r34-final.tar |96 miembros, nominal1.3.0, exit0 |
| consumer-materialize / python3 /tmp/opencode/exagent-r34-consumer.py TAR DESTINO |bytes exactos+deps físicas fijas, exit0 |
| consumer-build / mix deps.compile |build/cache Rebar propios, exit0 |
| consumer-tests / mix test --warnings-as-errors --seed37556 |**116/0/0**, exit0, incluidos25 nuevos casos |
| consumer-graph / mix run graph.exs |101 módulos sólo paquete, sin SQL/Phoenix/OTel SDK obligatorio, exit0 |

Warnings TOML/WebSockex en compilación de deps y deprecación Req adapter-fn en
fixtures se conservan íntegros; no warnings propios silenciados. Los28 excluidos
son22provider/6Postgres, no aceptaciones G2/G3. Snippets posteriores no cambiaron
runtime; el ajuste final de prosa se verificó con ExDoc y contenido TAR/consumidor.

## Artefactos/freeze y revisión pendiente

TAR final `/tmp/opencode/exagent-r34-final.tar`, SHA256
`6f517907d79c0cbc3d3c5d42abe8198d2369be96498d4af4071a402427917ce3`.
Consumidor `/tmp/opencode/exagent-r34-consumer`, grafo copiado y25 pruebas nuevas
idénticas a root. No consumidor real modificado ni instalaciones/descargas.
`/tmp/opencode/exagent-r34-freeze.py` compara source R3 aceptado, root,96 miembros
TAR y consumidor, checksums/tests/logs/scripts; produce manifiesto
`/tmp/opencode/exagent-r34-identity.json`, diff `exagent-r34-source.diff` y snapshot
`exagent-r34-source.tar.gz`. El SHA del source se registra en ese manifiesto y
relevo del coordinador para evitar hash autorreferente en este documento.

Contrato final para R4: Server snapshot4 lee1/2/3; Message omitted-v1 y marker1;
Usage accounting1 y continuation2/envelope1 intactos. Store/RuntimeIdentity/Session
no cambiados; la omisión es un error terminal diagnóstico, no continuación C7.
Review fresca requerida antes de aceptar R3.4/fase. No G2/G5 limpio, R4/C7,
hard RAM upstream, publicación, cambios mix/lock/CI ni ORCA_CHECKPOINT por este worker.

## Fixes de review — task_afc057579b81 / ctx_fa4af2f2e0c4

Baseline exacta sourcea92657dee7b6002b5cbb9bb2e8d5fb4b11915789051a09c862771c354e030147,
TAR6f517907d79c0cbc3d3c5d42abe8198d2369be96498d4af4071a402427917ce3.
Reviewer task_d3420f865920 conserva su copia y Task para revalidación independiente.
Coordinador autorizó añadir pending_response/nilcodec a los dos P2 iniciales.

### Reproducción y causa

Runner existente, prefijo de labels `r34-p2-`, logs+JSON en exagent-r11; seed37556.
`probes-red-01` ejecutó los seis probes del reviewer **antes de editar**:1/6,
exit2. Crash reason RunStream210040B/Server210036B frente4096; ledger
record_result210041B; hook pending data213942B frente106496; omitted content
restaurado como string `"nil"`. El error ordinario oversized era el control verde.

Se acota el error monitor antes de crear RunError/salida del guard, y el resultado
del estimador antes de enviarlo al proceso Scope (incluido su resultado idempotente).
La proyección pública previa ya acotaba errores ordinarios pero no esas fronteras.
Se normaliza pending_response al estado interno confirmado al validar hooks; no
se elimina la transformación válida de la Response en messages. Sólo el nil de
ToolReturn con marker se codifica null; no se altera el codec legacy.

Rutas equivalentes revisadas: RunStream startup/guardian/worker sin progreso usan
el mismo bound; Server abort/missing terminal/crash comparten failure; duplicado
Scope consume el record_result ya acotado, sin estimator ni nuevos contadores.
No se integró R4/Store/Continuation ni se reabrió el core ajeno a esas rutas.

### Rojos preservados y verificaciones

- `probes-green-01`:5/6 exit2, alias Retention inexistente en Server; corregido al
  nombre cualificado existente. `probes-green-02`:6/6 exit0, crash75B/ledger84B,
  pending data3689B. No se modifica el archivo de pruebas independiente.
- `regressions-01`:5/11 exit3; fixture exigía request_count1 después de muerte antes
  del siguiente ACK (contrato vigente conserva subtotal0), esperaba razón pequeña
  sin wrapper model_request_failed y generaba warnings por ramas constantes.
  Se corrigió el fixture, no la contabilidad runtime; control negativo conserva
  una request efectiva en diario y cero replay. `regressions-02`:145/145 exit0.
- `focal-final`:146/146 exit0, diez archivos;12 regresiones nuevas incluyen límite
  del ledger observado en callback público y duplicados/no dobleprecio/cleanup,
  ocho controles crash/error pequeño/grande sobre RunStream/Server, transformación
  válida junto a pending gigante y omitted nil JSON/snapshot4 con legacy control.
- `compile-final`:74 fuentes exit0. `suite-final`:755/0/28 exit0;22provider/6Postgres
  excluidos, no aceptación live ni DB. Smokes H/P/ACK previos siguen verdes.
- `format-final`, `docs-final` y `links-final` exit0 (229 enlaces/49 Markdown);
  `snippets-final`9/9 seed0 exit0. `preview` genera96 miembros, nominal1.3.0.
  `consumer-materialize/build/tests/graph` exit0:128/0/0 seed37556 sobre TAR exacto,
 12 regresiones nuevas byte-idénticas,101 módulos sólo del paquete, dependencias
  copiadas físicamente y build/Rebar aislados. Warnings upstream conservados.
- Tras leer el dictamen completo se extendió el mismo test contable con estimador
  que raise/throw210KB y control pequeño exacto; no cambió runtime ni package.
  `estimator-controls-final` y `consumer-estimator-controls`:12/12 exit0 cada uno;
  `format-final-02` exit0. La suite755 y consumidor128 anteriores siguen siendo
  evidencia del mismo runtime, con esta ampliación posterior comprobada focalmente.
  El freeze final es `exagent-r34-p2-v2-{identity.json,source.tar.gz,source.diff}`;
  se conserva también el primer freeze previo a extender esos controles.

Los artefactos posteriores usan prefijo `exagent-r34-p2-`, sin sobrescribir la
baseline. Manifiesto/diff/source TAR congelan delta contra baseR34, package y
consumidor de grafo fijo copiado. Revalidación independiente pendiente; estos
resultados no son autoaceptación R3.4/C7 ni resolución limpia G5.
# Final acceptance received before R4 integration — 2026-09-26

Independent task_d3420f865920 closes all four P2 findings on source
`05a024593553491c86e576535b5093d77ec05ceb4c2725024fdb919aa8e1efbf` and package
`8775e6657bea8f427792d7314796401f85b9f468453a7e7cb077a21ef8005176`:
forced compile74, unchanged independent probes6/6 and focal85/85 exit0.
Gate_1a7cfef26f1f accepts R3 offline; owner suite755/0/28 and consumer128/0/0
remain owner evidence. Historical findings/results below are preserved; R4
integration has separate evidence and does not imply C7 or external acceptance.
