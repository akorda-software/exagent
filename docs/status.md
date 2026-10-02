# Estado actual y recapitulación

**Base técnica aceptada: auditoría de testing del 2026-09-10.** El framework tiene una
base local ampliamente verificada. La aceptación de sistemas externos y la
publicación de la major siguen abiertas. La versión nominal del checkout es
**1.3.0**. Al iniciar el plan de producción el 2026-09-16, HEAD es `7f25b33` y
el árbol está limpio: la auditoría ya está integrada en Git. La base contiene
cambios incompatibles destinados a una major posterior. Los registros nocturnos
de abajo corresponden al nominal1.2.0.

## Trabajo vigente — 2026-10-02

Mandatos posteriores del usuario: pasada adicional crítica027 con subagentes y
objetivo028 de18 casos E2E OpenRouter real en `exAgentTest/chat_app`, ambos cerrados.
027 integra1P1/4P2 corregidos: C7 multirronda, subtotal de usage sparse y tres
fronteras del arnés OTLP, con regresiones.028 acepta18 escenarios reales mediante
ola inicial13/18 y repeticiones causales de cinco casos:40admisiones acumuladas,
reservaUSD1.00 deUSD1.50 y siete grupos propios cerrados; factura null. Mantiene
los rojos y fuentes por ola, sin contar exclusiones ni repetir pases anteriores.
Los E2E detectaron además el rechazo de instrucciones System en hojas de
coordinación, corregido en Frame sin formato nuevo;3regresiones y45adyacentes.
El consumidor usa ReqLLM stock, conserva `.env`/modelos y pasa precommit15offline/
18excl/exit0. [E2E del consumidor](development/real-consumer-e2e.md) fija perfiles,
oráculos y límites. No reutilizar el ledger G2 cerrado ni extrapolar el lote
múltiple inválido de06 a un pase secuencial o a todos los modelos del gateway.

El usuario amplió G4 para exigir **Langfuse y Opik igualmente validados** por
transporte nativo, API y UI del mismo escenario A10 y candidata identificada.
Langfuse y Opik pasan transporte nativo/API33/33 y los mismos doce casos UI con
248atributos. La aceptación es del perfil A10 finito, sin certificar estabilidad
del navegador. Su comparación histórica permanece separada. CI remoto pendiente.

La implementación v2 incluye secuencia, delegación durable10, Flow11 con router
host/paralelo plano/collect/fail_fast/C7, MCP stdio/HTTP con binding de aprobación,
retrieval y recetas LiveView/Oban. Flow limita ramas/concurrency a32(default4),
JSON de rama/merge a64KiB independientes y mantiene journal8MiB. Model/root y
cancelación/expiración generales no demostrados conservan sus guards. Contratos
y migración: [R6](development/r6-implementation.md) y diseño8.43–8.45.

Cualificación funcional común: candidata019 nominal1.3.0, TAR SHA256
`4629a1f2d22669b5fc352dcb62b8711cf11a4a2940a0c1fa25f3e98a8611c233`,
152 archivos distribuidos. ReqLLM1.24 oficial stock; Mint raíz1.10.2/floor1.10.2+
con los demás entries del lock intactos. No fork, bump o publicación.

- Suite integrada:2157pases/28excluidos, cero fallos funcionales,2276s y exit1
  por warnings de fixtures/adapter función. Corrección causal sólo de tests:
 136focales exit0/cero warnings. El FULL estricto rojo permanece conservado;
  estos casos se solapan con la suite, no son136casos adicionales.
- G2 real: GPT-4o-mini/OpenRouter chat_tools_v1,14/14casos,17requests/3efectos,
  reservaUSD0.425 frente a admisión20/USD0.50. Factura no observada y cero reruns.
  Otras familias/modalidades/perfiles no adquieren aceptación por este resultado.
- G3: PostgreSQL17.4 real,14fases incluyendo COMMIT/ACK perdido, dos resumers,
  FlowA8/restart/freshVM/recover y backup de su DB. SHOW5s,29hijos/PG cerrados;
  driver corregido importado con focales de interrupción/timeout.
- G4: native→Collector→Langfuse, pareja A10 de18+15spans. Una ola cinco POST;
  lectura final tres GET/734ms verifica33observaciones/667atributos/12modelos y
  uso/parentage/estados/privacidad. G4 visual aceptado tras inspección autorizada
  de la sesión del usuario:12observaciones/248atributos y cinco capturas verifican
  pausa/resume, IDs, reintentos, calidad/procedencia y cents estimados. Content
  desactivado explica Input null / Output undefined; tokens TestModel sintéticos.
  Recibo UIa2058c08…d8f3; cero reruns Producer/Collector/Model. API, ACK y UI no
  acreditan retención durable o factura.
- Opik ampliado: candidata025, proyecto sintético autorizado `tehsuso/exagent`.
  CincoPOST/33ACK; API cuatroGET2786ms y33/33,667attrs/12modelos/uso, recursos,
  UUID/parentage/estados/privacy. UI autenticada12casos/248attrs y siete vistas
  reales inspeccionadas; recibo e0a9be73…3e0f9. Navegación/captura inestables,
  conservadas como limitación, sin usarlas como evidencia positiva.
  Los fallosHTTP500ms/1s se conservan; perfil finalHTTP3s con guardCollector30s,
  sin retries. Langfuse/G2 no se repiten; cero proveedores pagados. Recibos y
  límites en [evaluación](development/backend-evaluation.md).
- G5 funcional: ocho grafos×siete contratos=56PASS en Elixir1.18.4/OTP28.0 y
 1.20.0/OTP29.0.5; SDK MCP5/5 y LiveViewTest/Oban SQL6/6 más crash73/recover0.
  Strictdiagnostics permanece RED por TOML/WebSockex/gproc oficiales, sin warns
  ExAgent. Últimas releases/rango grpcbox diagnosticados; CI remoto exacto pendiente.
- G6:18filas×200muestras, dos soaks200/c8 y saturación64/capacity32;
  cota de lote8, lote máximo observado2 y cleanup con TestModel. Sin SLO del LLM
  ni hardRAMpredecode.

ExDoc real corregido produce104HTML y2620targets locales válidos, sin enlaces
propios rotos. La candidata final incorpora documentación/soporte posteriores
a019; ese delta e identidad se sellan separadamente de los recibos funcionales.
La revisión final R9 está cerrada tras una pasada independiente de integración/
distribución, con seisP2 corregidos por focales del dueño y ninguno pendiente.
Los diagnósticos estrictos y la CI remota pendiente impiden afirmar que todos los
gates están cerrados.

El [roadmap](development/roadmap.md) es la fuente única de estado. Recibos/SHA en
`docs/orchestration/2026-10-01-v2-codex/FINAL-CANDIDATE.md` (sólo checkout).
[Flujo vigente](development/execution-flow.md): una revisión máxima por objetivo,
sin re-review ni reruns rutinarios. El historial siguiente conserva lo observado
en cada fecha; sus pendientes no reactivan tareas ya cerradas.

## Base recibida: evidencia activa Frame9 aceptada offline acotada — 2026-09-29

Misma `Composition.resume/3`: única hoja activa con batch final/resuelto/accounting
aceptado/control completo, prefijos tools propios y output retry/success actual
atestado con/sin tools; approvals consumidas conservadas como historia resuelta.
No autorizan una request nueva aunque ID/args coincidan; current allow no supera
original ask. Validación Record y Retry.plans global antes de selección privada,
reducers con Record original, sin repricing/redebit; contadores host exactos separados
de uso normalizado/estimado cualificado. Recover explícito y referencia exacta.
Legacy7/8/single9, completed data-only y C7 primer batch todo-pending conservados.

Owner FULL1845pases/28excluidos/1410.3s exit0, compile109WA/formato global/diff0;
review favorable40existentes+4propios, identidad9+306. Padre9hashes/copia roundtrip,
mismos4probes corregidos4pases/16.7s/exit0, no casos adicionales; owner55=25+30.
Informes/SHA/log en [implementación R6](development/r6-implementation.md).
Owner54/55 rojo→4focales→FULL verde y harness fallidos preservados. Review original
3/4 por oráculo allow sobre ask sigue rojo; copia corregida4/4 sin source fix.

Fatal actual consumible falla operativamente sin C/refund final; fatal histórico
negativo y preparación typed host prioritaria intactos. Retry estructural unsupported;
excepción tool deja intent unresolved, no unknown confirmado. Parse token inflado
no prueba CAS válido oversized; capacidades JSON+cleanup/receipts/history separadas.
ETS/ficheros entre VMs no certifican SQL; callbacks iniciados sin preempción atómica.
No mixed/control parcial/raw/uncertain/delegación/router/paralelo/general R6 ni
SQL/live/producción. Siguiente: investigación estructural sólo lectura de
delegación+C7 quiescente/mixed-control, sin implementación activada.
Receipt docs5 posterior a los bytes revisados; nominal1.3.0, sin publicación.

## Base recibida: C7 secuencia todo-pending aceptado offline — 2026-09-29, anterior a evidencia activa

Frame9: A completed→B primer batch propio con dos approvals→pausa raíz confirmada
por ACK→decisiones host→nuevo claim→resume en VM nueva→C. Raíz y B proyectan paused,
B permanece running persistido; C no empieza durante pausa. Partial approve conserva
pending, último approve ready, deny administrativo terminal. Prefijo histórico sin
replay de efectos/callbacks ni repricing; contadores host, reservas y refund exactos,
uso normalizado/estimado cualificado. Espera humana fuera del active budget, bajo
TTL/deadline lógico; claim nuevo reserva saldo. Deadlines antiguos no se amplían.

Owner FULL1790pases/28excluidos/1121.2s exit0; review favorable271existentes+7propios,
compile108WA/formato global/diff0 e identidad15+303 intacta. Padre cotejó15hashes y
helper/runner, copió con roundtrip de rutas y reejecutó los mismos7probes:7pases/13.2s,
exit0, no casos adicionales. Los57casos owner son43+14. Informes/SHA/log padre y
provenance de los dos antiguos negativos recibidos en
[implementación R6](development/r6-implementation.md); fallos históricos conservados.

Allpending se certifica tras recoger resultados async: mixed siblings pueden tener
efectos y fallar cerrado sin pause/refund, sin barrera atómica preadmisión. Current
permission deny puede dejar outcomes denied y continuar C sin tools B; distinto de
deny administrativo. Refs/policy se verifican preclaim; schema/Model efectivo,
postclaim. Record2/Frame9 experimental direccional: lectores viejos rechazan filas C7
nuevas. No mixed/raw/delegación/general R6/router/paralelo/SQL/live/producción ni
binding MCP endpoint/principal; callbacks iniciados sin preempción garantizada.
Próximo trabajo: investigación sólo lectura, no nueva implementación activada.
Recepción docs5 posterior a los bytes revisados; nominal1.3.0, sin publicación.

## Base recibida: recuperación acotada aceptada offline — 2026-09-29, anterior a C7

`Composition.resume` admite ready9 empty/between/input sin operaciones propias,
terminal texto sin tool-history propia y typed-succeeded admitido. Completed sigue
data-only; recover administrativo explícito, un nuevo claim/attempt y un Writer/Scope
para el mismo lifetime. Prefijo cerrado sin callbacks/replay/repricing; árbol exacto,
ACK fresco, deadline cached y guard post-intent-ACK/observability preservan autoridad,
contadores host y parcial confirmado. Uso normalizado/estimado conserva cualificación.
Finito abandonado sigue agotado; ilimitado positivo bajo lease/TTL/cuotas. Autoridad
lógica nueva separada de lease/budget; deadlines antiguos persistidos no se amplían.
Callbacks ya iniciados no tienen garantía de preempción atómica.

Owner FULL1733pases/28excluidos/967.8s exit0, review fresca favorable29(2+10+17)+113
focales+3observability. Padre cotejó identidad6/6 y copió harness completo con rutas
verificadas por roundtrip; mismos15(2lateACK+10prior+3obs) pasan/12.6s exit0, no15casos
adicionales. Informes/SHA y log padre en [implementación R6](development/r6-implementation.md).
Históricos rojos P1/P2, harness y sampling10ms conservados, sin reinterpretarlos verdes.
Siguiente C7 composiciones: investigación sólo lectura, no mandato de implementación.

### Base recibida: secuencia durable e interop MCP SDK — 2026-09-28

`Composition.run/3` ejecuta N pasos durables con un único Scope/Writer/claim y
presupuesto, mapping de outputs confirmados y refund raíz sólo al finalizar.
Resultado parcial confirmado e inspección completed multileaf data-only; nuevas
raíces Frame9, lifetimes7/8 conservadas y subsets single-leaf9 aceptados.
Owner FULL1673pases/28excluidos/885.2s exit0. Review favorable62focales+5probes
previos en copia corregida+2nuevos terminales; padre26hashes y cambio único de
assertion cotejados, mismos7probes reejecutados7/7 en3.3s exit0, no7casos nuevos.
FULL1651/1652 y probe original4/5 permanecen fallidos históricos. Informes/hashes
y fronteras exactas en [implementación R6](development/r6-implementation.md).

MCP SDK oficial Python2.2.0: stdio2024-11-05 y HTTP2025-06-18 JSON/SSE ×
session/stateless, tools textuales localhost con Client/Tool/permisos reales.
Owner5/5 y review5/5 sin skips son los mismos cinco casos; padre cotejó identidad
de cinco módulos MCP ROOT/copia, sin rerun propio. Evidencia y hashes en
[roadmap](development/roadmap.md). Harness portable pendiente de integración;
límites65KiB/pending4/tools4 sólo HTTP, stdio defaults8MiB/128, sin estrés.

**Pendiente vigente:** evidencia activa multileaf fuera del subset final/resuelto aceptado,
C7 composiciones fuera del primer batch todo-pending aceptado, raw/uncertain recovery,
delegación estructural, router/paralelo y R6 general. En MCP, binding C7 de endpoint/
principal, OAuth/TLS, cancel/reconnect/chaos con SDK, protocolo2026 y otros SDK.
Estas recepciones no aceptan SQL/live/producción ni cierran R7.4/A9/R7/G4.
La recepción documental es posterior a los bytes revisados; versión nominal1.3.0.

## Base recibida: Frame8 final/control/prefix aceptado offline — 2026-09-28

Aceptado sólo single-leaf Frame8: prefijos confirmados continuables y batch actual
final/resuelto con accounting aceptado/control completo, seleccionado por request
actual. Consume returns una vez, conserva primer fatal y contadores sin replay ni
repricing; nueva IO bajo autoridad original∩actual. Codec/binding/fingerprint y
Model.validate_resume host siguen vigentes; preparación typed puede fallar antes
del fatal portable conservando evidencia, sin reconstruir excepciones BEAM.
Review50casos distintos (43focales+3independientes+4adyacentes), sin P1/P2 reproducible;
padre source12/12 y3probes intactos WA48seed37556 exit0/9.3s. Owner FULL1568pases/
28excluidos/716.8s exit0, compile107/focal261 (99nuevos) y MCP37 son evidencia separada.
MCP sólo corrigió oracle test con dos órdenes causales; runtime intacto. Informes,
SHA y `parent-probes.*` en [implementación R6](development/r6-implementation.md).
Los FULL fallidos históricos conservan resultados. No restore general/raw/uncertain/
no-control/rejected/omitted/legacy7tools/approval-retryplans/delegación/A→B ni R6
completo/SQL/cloud/live. Recepción documental posterior a los bytes revisados.

## Base recibida: MCP HTTP y Frame8+OTel integrados aceptados offline — 2026-09-28

MCP HTTP privado aceptado121focales+6+2review/padre8probes, patch exacto9rutas
ffb311e8 integrado sobre ROOT. Gates nuevos:121MCP+8probes intactos+69adyacentes,
FULL1467pases/28excluidos WA48seed37556 (508.9s), compile106/formato/diff exit0.
Padre acepta MCP integrado en alcance offline: diff/docs revisados,377/377hashes
y9/9rutas privadas byte-idénticas en la entrega revisada;77pases ROOT
(8probes intactos+69adyacentes),20.9s, WA48seed37556 exit0. Este review es separado
del FULL owner anterior; REPORT9b192949 y logs `parent-review.*` identificados en
[roadmap](development/roadmap.md). Esta recepción sólo cambia documentación.
Contrato en diseño8.40. HTTP1-only
app-owned es precondición confiable, no detección fiable de HTTP2. MCP2025-06-18,
JSON/SSE terminal-aware, sin redirect/replay y retención postdelivery acotada,
sin hard RAM upstream. C7 binding endpoint/principal permanece abierto; la interop
SDK acotada posterior figura arriba. No aceptación R7.4/A9/R7/G4 ni R6 completos.

Productor/validator Frame8 aceptado offline: review95 (55+33+7), padre7probes
intactos WA48seed37556 exit0; source19/19 cotejado. FULL1409/28 es evidencia owner.
Nuevas raíces8 conservan observación accounting y control postsettle; omisión rechaza
antes de aplicar contribución y conserva subtotal partial. Legacy7 conserva7 durante
su lifetime; no datos inferidos ni cierre de los rojos históricos usage/retry.
El productor por sí solo no abrió restore tools/prefijos/batches; la excepción
final/control/prefix vigente se delimita arriba. Subset sin tools y completed
data-only conservan sus límites. No aceptación R6 completa.

OTel privado aceptado tras fix P2: reviewer145focales+9oráculos y padre9 intactos;
patch5a060902 integrado sólo en OTel y dos tests nuevos. Paused cierra intento sin
error, correlación acotada y referencia plana versión entera1; accounting lifetime
no sumable entre intentos. Nueva identidad ROOT: focal476+9oráculos, FULL1423pases/
28excluidos WA48seed37556 exit0,509.6s; compile102/formato/diff exit0. Evidencia y
manifiestos en roadmap, separados de los tests privados. Review integrada aceptada:
REPORTc58bcc93,9oráculos+69focales ROOT exit0, source369/369 intacto y sin P1/P2
en alcance. FULL1423/28 es evidencia del integrador anterior, no de esa review.
R7/G4/admin tracing siguen
abiertos; Langfuse sólo referencia provisional, sin elección ni despliegue final.

## Base recibida: contadores runtime-owned aceptados offline — 2026-09-28

Seis campos internos protegidos tras cada capability Model, antes del siguiente
hook/admisión/IO. Se preservan transformaciones legítimas y comportamiento de mapas
genéricos; migración de escrituras indebidas documentada para la major pendiente.
Review124focales+8probes, padre8probes intactos WA48 exit0;15/15hashes cotejados.
Owner FULL1354pases/28excluidos/compile101 separado; identidad en roadmap§5.
Sólo protección del productor: evidencia durable usage/control y contadores legacy
siguen pendientes, sin nuevos formatos ni apertura restore con tools ni cierre R6.

## Base recibida: cardinalidad batch aceptada; evidencia usage/control pendiente — 2026-09-28

Validación estructural común rechaza borrado/reducción coordinada de batches y
counts por decode y CAS, ligada a calls por request. Review141focales+4probes,
padre4probes intactos WA48 exit0;13/13hashes cotejados. Owner FULL1310pases/28excluidos
separado; identidad en roadmap§5. No habilita restore tras tools.
Usage sigue sin evidencia durable por call: ToolReturn.usage no se serializa ni
entra en hashes Outcome. Retry/control también requieren contrato explícito; los
dos rojos diagnósticos permanecen. No cierre R6 ni aceptación SQL/live.

## Base recibida: cadena output atestada R6 aceptada offline — 2026-09-28

Atestación ACTUAL success/retry tras N respuestas Model confirmadas, historia mixta
con Retry sin call y siblings sin ejecución. Consume sólo decisión actual, sin
revalidación histórica ni repricing; mismo loop/Writer y límites, runtime delta
sólo CompositionRestore. Review208focales+7probes, padre7probes intactos WA48 exit0;
manifiesto17/17 cotejado. Owner FULL1287pases/28excluidos/compile101 separado.
Identidad en roadmap§5. TextoN sin atestación actual, batches incluso finalizados,
incertidumbre, A→B/delegación y SQL/live siguen fuera; no cierre R6.

## Base recibida: primer output retry R6 aceptado offline — 2026-09-28

Atestación retry response1 consumida sin revalidar args históricos, configuración
host postclaim y nueva request admitida bajo autoridad actual∩original. Consumo y
contador persisten con intent existente, sin repricing histórico ni nuevo motor.
Review167focales+5probes, padre5probes intactos WA48 exit0; hashes11/11 cotejados.
Owner FULL1211pases/28excluidos/compile101 separado. Evidencia en roadmap§5.
Restore de request2/response2 y batches/incertidumbre sigue bloqueado; completed y
tokens sólo datos. R6/A→B/delegado y SQL/live siguen abiertos.

## Base recibida: output succeeded R6 aceptado offline — 2026-09-28

Primera response1 con una atestación succeeded portable, consumida sin nueva
validación Ecto/reflexión, request Model ni ejecución de siblings. Resultado JSON,
partes exactas una vez, mismo loop/Writer/CAS/Scope y ledger sin repricing.
Revisión independiente109focales+5probes; padre5probes intactos, exit0. Owner
FULL1153/0/28 WA48/compile100/formato0 separado; identidad y límites en roadmap§5.
Fallos del FULL histórico conservados con causa desconocida. No retry/general,
A→B, SQL/live ni R6 completo. Siguiente unidad: output retry confirmado.

## Base recibida: restore textual R6 aceptado offline — 2026-09-28

Primera respuesta textual confirmada→cierre sin nuevo Model/mapping/after_model
ni recálculo del coste histórico, sobre Frame7 y el loop/Writer existentes.
Review169/0 con matriz37 final, input0 y pisos; padre37/0. Owner FULL1125/0/28
WA48/compile99 separado. Evidencia y límites en roadmap§5. No atestaciones
ejecutables, restore general, A→B, SQL/live ni R6 completo.

## Base recibida: restore input0 R6 aceptado offline — 2026-09-28

Sobre el paso único aceptado, Frame7 conserva autoridad efectiva raíz/hoja y
restaura input confirmado/request0 sin operaciones mediante claim CAS fresco.
Completed se consulta sin callbacks. Review171/171 tras cerrar P1 del floor
actual; padre46/0; owner FULL1088/0/28 WA48/compile99. VM nueva, carrera, permisos,
límites, presupuesto y legacy cubiertos en el alcance. Evidencia en roadmap§5.
No restore general, response/raw/atestación pendiente, A→B ni R6 completo.

## Base recibida: paso único R6 aceptado offline — 2026-09-28

Paso→hoja real sobre raíz estructural y el mismo Writer/CAS/Scope, con input
confirmado antes del IO y output después. Frame5/6 valida evidencia Model/tools/
Retry/output tipado; reservas y cleanup pre-write conservados. Review integrada
más fix mínimo final:72pases independientes con siete probes intactos y ningún
P1/P2 restante en alcance; padre35pases. Owner FULL1043/0/28 WA48 seed37556 y
compile97. Identidad, informes y límites en roadmap§5.

No restauración ejecutable desde bytes, A→B, pausa delegada de composición ni R6
completo. SQL/live anteriores no cualifican automáticamente estos cambios.
Siguiente unidad: persistir el piso de autoridad raíz y restaurar una hoja.

## Base recibida: admisión/none/binding/terminal aceptados offline — 2026-09-27

El coordinador aceptó admisión2a74, none/bindingb609 y prioridad terminaldda4 tras
reviews frescas separadas, además del harness portable7files75af. Contratos en
ADR8.35–37; continuation3/Frame3/Abort2, capas/guards y stock1.24 íntegros. Última
suite owner947/0/28 WA y compile93 corresponden al runtime terminal; fuente/paquete
finales se identifican en el registro de la unidad, sin reatribuir bytes anteriores.

G2 final exacto: gpt-4o-mini14/14 sobre2a74 más2controlesstream b609; Luna none13/14
enb609, length_stream **no cualificado**; GLM5.3Flash/DeepSeek4.1Flash sólo un texto
buffered cada uno, sin tools.40admisiones/7efectos/USD2.37 reserva, factura desconocida.
El delta terminal no prueba el terminal original de Luna ni extrapola live a bytes
posteriores. Tooling habitual checkout-only: `test/support/openrouter_qualification`,
opt-in --live, ledger nuevo, límites explícitos y autorización permanente para cambios
relevantes. Suite por defecto sigue offline. R6/R7 y cierre de release siguen abiertos.
Tabla única roadmap§5 y registro `docs/archive/2026-09-27-reasoning-none-binding.md`.

## Base recibida: C7 y admisión final — 2026-09-27

El coordinador acepta el framework C7 de source8b3b junto con el delta SQL4b89
separado, tras el dictamen independiente final en
`/tmp/opencode/exagent-r5-review/final8b3b/REVIEW.md`. El TARba17 aún conserva el SQL
anterior: no es una distribución corregida. Gates reales y release siguen separados.
La adaptación autorizada de admisión final sobre stock1.24 distingue diagnósticos
históricos de errores/pérdidas explícitos, manteniendo sobre/schema y autoridad;
diseño8.35 y roadmap§5 registran contrato y verificación actual. G2 histórico sigue
rojo hasta recalificación live; G5 limpio sobreba17 no cubre estos nuevos bytes.
Las secciones inferiores conservan evidencia fechada previa a esta recepción.

## Histórico: R4 aceptada offline; siguiente R5/C7 — 2026-09-26

**Recepción documental posterior al freeze aceptado:** coordinador msg_57de32de8f89
acepta R4.1–R4.6 sobre sourcecdd2a042/TARac544712/manifest1488bbd6. Review final
task_60fd56a7fead: compile80/focal33/snippets9/deltas279/TAR103 independientes exit0,
P2cleanup/P3guías cerrados, sin P1/P2 concreto en alcance. Artefactos inmutables;
esta prosa posterior no forma parte de esos bytes. Siguiente Task fresca R5/C7
autorizada después del cierre del owner R4; G3 real y demás gates externos abiertos.

Delta exclusivo R4 corregido integrado sobre R3.4 aceptada, sin modificar sus
codecs/runtime. Compile80, focal121 y seam3/3, suite803/0/28 seed37556 exit0;
formato, snippets9/9, ExDoc, links233/53 y plan57 exit0. Tabla única roadmap§5;
fuentes/TAR/consumidor y evidencia nueva en `docs/archive/2026-09-26-r4-integration.md`.
Aceptación integrada recibida arriba; R5/C7 y SQLlive/G3 permanecen abiertos.

Review independiente task_d3420f865920 cierra los cuatro P2 de retención sobre
source05a02459 y TAR8775e665: compile74, probes6/6 y focal85/85 exit0. La suite
owner755/0/28 y consumidor128/0/0 fijo son evidencia reutilizada de esa identidad.
Gate_1a7cfef26f1f acepta R3 offline y permite integrar el delta R4 corregido
sourceb3498467; sus nuevos bytes integrados requieren review propia tras gates owner.
R5/C7 y gates externos permanecen abiertos.

Diseño8.30/31: namespaces confiables Server/Session/Store/Event y admisión Server
por bytes externos Erlang input/pending/history; historia no truncada. Compile
forzado73, focal122/122 y **suite718/0/28 seed37556** exit0; formato y snippets9/9
seed0 exit0. Smoke16 namespaces/48 requests-terminales/16 rechazos conserva
aislamiento y cola. Artefacto/consumidor/rojos en
`docs/archive/2026-09-26-r3-runtime.md`. Review task_529ac64dfe7e acepta el alcance
parcial sin P1/P2: compile73/focal38/probes5/snippets9 independientes; coordinador
identidad95/258/focal17 exit0, gate_115377365ca5. TAR29e35296/source643ade77.

Por acuerdo explícito, R3.1/2/3/5/6 y admisión R3.4 forman esta unidad parcial.
**Evidencia inicial R3.4, sustituida por aceptación anterior:** ADR8.32 implementa
P/H agregados postdecode, reserva de outcomes, Usage/error acotados y omisión
explícita preservando efectos. Snapshot4/omitted-v1 bloquean replay y Server usa
ACKs. Compile forzado74/focal139/**suite743/0/28 seed37556**, formato/ExDoc y
snippets9/9 seed0 exit0. Smoke24 cierres y máximos EFT data5219B/history2021B/
event5107B; S3 añade3requests/2effects/cierres3, history22805/24576 y data52423B.
Artefacto/consumidor/rojos se identifican en `docs/archive/2026-09-26-r3-retention.md`;
la revalidación final se identifica arriba. No cierre C7/G2/G5 limpio.

### Base recibida: R2 aceptada offline

Diseño8.29 y gate stock público preceden native explícito: output_mode:native,
output_profile:chat_json_schema_v1 sobre chat_tools_v1, schema exacto no estricto y
Ecto autoridad final. Ecto-tool/sobre, vacío/embeds/null/defaults, retries contados,
historia/continuación y function_tools con un efecto quedan comprobados offline.
Stock pierde refusal junto a contenido válido (que puede producir output localmente
válido); señal pública expuesta se rechaza. No detección wire total ni G2.
Tras corregir P2 preadmisión y fixture OTLP, compile71, **suite707/0/28
seed37556** y consumidor80/0/0 fijo pasan. Review task_f955b8e8ea60 cierra P2:
compile71/focal32 seed92624, contraste fixture1/3→3/3, sin P1/P2 pendientes;
coordinador17/17 e identidad93/253 exit0. TARf6b549f5/source7eb34210 aceptados
offline por gate_60c09b5f327e. Registro: `docs/archive/2026-09-26-r2-output.md`.
R3 avanza según cabecera; atomicidad Store/C7 runtime siguen en R4/R5.
No nuevo G2 ni resolución limpia G5.

### Base recibida: R2 base aceptada offline

R2.1/2/4/5/6: diseño8.27–28 clasifica API y diseña paused para R4/R5 sin fingir
runtime C7; consolida identidad before-tool universal, selección ejecutable por
request, callable/contexto/errores y capacidades extra explícitas. Codec y guards
R1 se reutilizan. Compile forzado71, suite **687/0/28 seed37556**, focal98, formato,
snippets8/8/ExDoc y consumidor63/0/0 de TAR6e0585bc (grafo fijo copiado) exit0;
registro de rojos y artefacto final docs-only byte-verificado en
`docs/archive/2026-09-26-r2-base.md`. Review task_28d681ef6334 aceptada sin P1/P2:
compile71/focal54/probes6 seed82619, coordinador focal38 exit0, TAR482e26a3 y
source1eefe618 verificados. R2.3 aceptada posteriormente según cabecera, sin
aceptación externa. El único tablero de subunidades continúa en roadmap§5.

## Base recibida: R1.8 aceptada en perfil mínimo offline — 2026-09-26

Review final R1.3/6/7 recibida:4/4 e identidad TARd2bfe978, corrección documental
cerrada. R1.8 retira9 módulos duplicados y migra resolución/specs/auth/ejemplos/
Ecto/OTel; conserva Model custom/Test y fronteras host cualificadas. Compile71,
focal48 más36 de revisión y suite **680/0/28 seed37556** exit0, formato/snippets8/8 y probe de
consolidación público exit0. Identidad y evidencia de distribución en el registro;
review fresca `task_a7e85474a9ef` acepta TAR6a2eb6aa sin P1/P2 concretos pendientes,
con compile71 y focal6/6 independientes. Cierre documental26Sep preserva AST
funcional y tests/config/mix/lock; su artefacto/gates nuevos constan en el registro,
sin atribuir nueva revisión independiente de prosa. R2 base se registra arriba.
Inventario: `docs/archive/2026-09-25-r1-retirement.md`; R1/C7/G2 no cerrados.
Review P2 corrigió una promesa wire excesiva: stock puede borrar siblings malformed
sin señal pública. Matriz TCP distingue perdidos frente a inválidos visibles;
estos últimos invalidan el batch sin efectos y los válidos requieren autoridad.

### Base R1.3/6/7 recibida

R1.5 recibió dictamen final fresco `task_5b79c7a35e0c`:173/173 exit0,
sin P1/P2 concretos pendientes, TAR `3c7867ad…`; consumidor48/0/0 fijo copiado,
sin nuevo G5. El tramo mínimo `chat_tools_v1` R1.3/6/7 añade cuatro oráculos:
binding continuation/target, tool_choice interno y dos compuestos TCP reales con
delegación/Ecto retry/Server stream/Session/ETS/checkpoint/OTel. Runtime intacto;
compile80 y suite **755/0/28 seed37556**, exit0. Matriz y rojos de fixtures en
`docs/archive/2026-09-25-r1-qualified-composition.md`. Dictamen final fresco recibido;
R1.8 vigente arriba. C7 y G2 pendientes.

### Base R1.5 recibida

Usage.accounting v1 califica métricas y coste estimado; strict por defecto y
estimated con request_limit efectivo, contrato declarativo ModelProfile, snapshot
Server3 y proyecciones coherentes. Diseño8.25/migración detallan ruptura, subtotales,
moneda y agregación de detalles. Compile80 y suite **751/0/28 seed37556**, exit0;
gates ReqLLM stock con transporte sintético/TCP y oráculos custom, ancestros,
JSON/restore/OTel. Rojos y correcciones preservados en el registro checkout-only
`docs/archive/2026-09-25-r1-qualified-accounting.md`. Review fresca R1.5
`task_5b79c7a35e0c` aceptó el freeze/TAR final con173 casos. No aceptación R1
completa, C7 o G2 live.

R1.4 recibe aceptación fresca **STREAM PARCIAL offline chat_tools_v1**:
review `task_dbfcf7b3c823`,123 casos propios/0 fallos, coordinador53 focales exit0,
TAR `12e46f416f40fa4f73f3fe8dd8eca513d9061087b131ed2c29a68c8fccd62128`.
Smoke46/0/0 con grafo fijo copiado, sin nuevo G5. Estas cifras son R1.4,
separadas de la nueva evidencia contable R1.5 de arriba.

### Recuperación R1.4 anterior al dictamen

Perfil Chat explícito integrado en Model.request_stream, stream_text y run_stream,
con process_stream público de una vista y traducción/Envelope buffered compartida.
Guardian/registro/close/deadlines y límites postdecode64KiB/1MiB/4096; RunStream
compartido acota progresos con ACK tras repro203→1. Compile80/suite735/0/28 exit0
seed37556 tras corregir/reprobar P2 de shutdown atrapado y finalizador custom al
cancelar progreso; focales53/53 incluyen probes del reviewer. Cierre de revisión
runtime fresca pendiente; distribución/docs se identifican por artefacto en el registro.
La recuperación del25Sep reejecutó compile80, suite735/0/28 y focales53/53
con los probes previos, todos exit0, sin cambiar fuentes runtime ni lock.
Son ejecuciones nuevas con prefijo aislado; no una aceptación de la review interrumpida.
Diseño8.24/migración y registro
checkout-only `docs/archive/2026-09-22-r1-stream-adapter.md` delimitan contrato.
R1.5 unknown, G2 live, C7 y cierre R1 siguen pendientes.

### Base recibida: sobre buffered cualificado y review aceptada parcialmente

Review fresca `task_16e800274a86` acepta el subset buffered offline del TAR51f36adc,
con P2 deadline corregido y revalidado, sin P1/P2 concretos restantes en ese alcance.
Esa aceptación y las cifras siguientes corresponden a R1.2, no al stream nuevo.

**Nueva evidencia R1.2 acotada:** gate stock generate_text/process_stream y
envelope1, integración buffered `chat_tools_v1`, codec continuation2, Tool/JSV,
Ecto-tool, hooks/approval/ancestros, Server/JSON/compaction y ownership HTTP.
Compile forzado79 y suite **715/0/28 seed37556**, Elixir1.20.0/OTP29.0.5, exit0;
focales30/30 iniciales y timeout10/10 tras P2deadline, formato/diffcheck0. Lock `c20a0cb9…` intacto. Revisión fresca recibida;
cualificación live pendiente; distribución se identifica por artefacto en el
registro checkout-only `docs/archive/2026-09-22-r1-envelope.md`.

El perfil exige OpenAI, metadata explícita `openai_chat`, tools enabled,
reasoning disabled y no strict; esquema reference-free documentado en diseño8.23.
Se valida el objeto lógico y el sobre obligatorio, no bytes raw perdidos. Calls
históricas sin codec o inválidas rechazan; guards de otros perfiles siguen activos.
Un rojo TCP nuevo de owner kill con total_timeout perdió cleanup upstream:
guardian host común buffered lo corrige y hereda deadline público sin config global.
P2 de revisión fresca también reproducido/corregido: timestamp monotónico rechaza
finalización tardía aunque el guardian estuviera suspendido; review final recibida.
En esa unidad no se habilitó stream ExAgent, R1.5/uso ni C7. Memoria de una Response buffered es
O(respuesta); no se acepta aquí perfil operativo de retención stream por bytes.

### Contexto del replanteo anterior y fronteras restantes

El [roadmap R0–R9](development/roadmap.md) es el único tablero. El usuario confirma
ExAgent propio sobre ReqLLM y **C7 incluido** en v2, sustituyendo su aplazamiento.
El [alcance](development/release-scope.md) define capacidades/límites y la
[matriz de aceptación](development/production-acceptance.md) sus oráculos/gates.
Las apps actuales son pruebas de concepto y no condicionan esta versión.

**Decisión aprobada:** [diseño8.22](architecture/design.md)
elige release oficial ReqLLM stock sin fork/vendor/patch/monkeypatch/parser privado
ni runtime Jido. Primera acción: gate R1.2 del sobre obligatorio `{arguments: objeto}`
con runtime ReqLLM real/transporte sintético, antes de retirar guards. El gate
buffered nuevo de arriba prueba la hipótesis en el subset, con schema/efectivos tras hooks,
history/codec versionados y C7/autoridad/no-replay intactos.

El objetivo revisado separa contadores host exactos de métricas normalizadas/estimadas
con calidad/procedencia, y sustituye hard RAM predecode por límites propios postdecode,
concurrencia/deadlines y cleanup medidos. Mínimo Chat-compatible sin reasoning/provider-native
con tools/Ecto/stream en modelo/endpoint exactos por cualificar; otras familias por
capacidad probada, ninguna pérdida silenciosa. Los criterios restantes siguen abiertos.
Relevo checkout-only: `docs/prompts/continue-v2-reqllm.md`.

Mandato activado el2026-09-21: R0 y R1.1 ejecutadas, nominal1.3.0 intacto.
ReqLLM1.24.0 está añadido y su API host buffered probada con transporte sintético;
el adapter buffered ExAgent está implementado, C7 sigue pendiente. R1.1 eleva mínimo a Elixir1.18
por `llm_db` obligatorio, con decisión autorizada en diseño8.15 y migración.
H1–H6/H3.0 son históricos, no otro tablero.

**Evidencia histórica R1.1 (2026-09-21):** compile forzado75 fuentes y suite nativa **658/0/28**,
seed37556, Elixir1.20.0/OTP29.0.5; consumidores mínimos del mismo TAR **9/0/0**
en1.18.4/OTP28.0 y1.20.0/OTP29.0.5, grafos sin SQL/Jido/OTel SDK/API.
No se repitió toda la suite raíz en1.18. Warnings TOML/WebSockex y deprecación del
adapter sintético Req0.7 se conservan: compile exit0 no es strict limpio.
Registro sólo checkout `docs/archive/2026-09-21-r1-1-reqllm.md`; revisión fresca
R1 y gates externos pendientes. Advisory Mint1.10.0 raíz CVE-2026-82672 registrado
aparte de warnings; posteriormente se corrigió con autorización a1.10.1.

**Evidencia posterior Mint/R1.2:** compile77 y suite **672/0/28** seed37556 sin
instrumentación, focal transporte13/0 y consumidores nuevo TAR **9/0/0** en los
mismos dos pares, ahora con adapter ExAgent+custom Model. Mensajes/JSON/snapshot
preservan continuación portable probada (firma Anthropic y Responses encrypted
reasoning); Google tools se rechazan temporalmente por pérdida upstream de firma,
R1.3 parcial. Uso desconocido temporal no acepta R1.5. Review fresca R1.1 recibida;
no sustituye review del adapter nuevo ni R1.4–R1.6. Registro sólo checkout
`docs/archive/2026-09-21-r1-buffered.md`, incluidos dos rojos previos de readiness
100ms cuya causa sigue abierta, sin aumento de timeout para esconderlos.

**Actualización tras review fresca:** el TAR61eaffda no acepta tools R1.2 ni
Anthropic completa R1.3: stock convierte args[]→{} y pierde redacted_thinking.
Se reprodujeron tres rojos y se añadieron guards temporales antes de IO; custom,
Test y legacy no cambian. Perfil thinking ahora respeta capacidad. Suite nueva
**678/0/28** seed37556 y compile77; R1.4 sólo caracterizada7/7, bloqueada por falta
de límite público de bytes predecode. No se adopta spike ni fork. Registro sólo
checkout `docs/archive/2026-09-21-r1-streaming.md` incluye consumidor nuevo/gates y
la evidencia posterior readiness155ms que justificó corregir sólo esa barrera.
Las cifras anteriores mantienen su revisión; guards no equivalen a fix upstream.

**R1.6/R1.7 textual posterior:** recibo por instancia e instrucciones corregidos,
total_timeout por instancia autorizado, Req0.7.4 requerido tras fallo TCP real de
Req0.6.1; se conserva Finch0.22 en root. Compile77 y suite **691/0/28** seed37556.
Un compuesto Server/Session/ETS/hooks/compaction/scope/OTel usa ReqLLM real con
transporte sintético (3requests/3generaciones/3spans), sin aceptar backend externo;
los timeouts/redirect/retry sí se probaron con TCP loopback. Estado parcial, guards
intactos, sin paridad R1.8 ni R2. Registro `docs/archive/2026-09-21-r1-textual.md`.

Los resultados históricos que siguen
conservan su fecha y denominadores; los futuros candidatos se verificarán de nuevo
en las fronteras pertinentes.
También **691/0/28**, SHAs/locks/TAR anteriores son históricos hasta nuevos gates;
esta revisión documental no vuelve a aceptar herramientas, stream, uso ni C7.

## Última aceptación: auditoría de testing

Inventario readonly completo, mejoras y dos revisiones frescas por área. Se
corrigieron falsos verdes de eventos/cola/telemetry, oráculos de datos/efectos y
cleanup; la auditoría reprodujo y cerró cinco familias de defectos de biblioteca.
Se retiró un test ficticio de payload sólo después de comprobar sus sustitutos
mediante mutación del adapter. Detalle y backlog en
[auditoría de testing](development/testing-audit.md).

**Auditoría cerrada por acuerdo del usuario; se retoma el desarrollo.** El testing
se centra en los contratos e integración de ExAgent; los internals de sus
dependencias corresponden a sus mantenedores. Los warnings Req/gproc se conservan
como seguimiento externo y no bloquean por sí solos esa continuidad. El
[criterio de verificación](development/verification.md) delimita responsabilidades
y frecuencia; la segunda revisión queda diferida al paquete funcionalmente terminado.

| Runtime de esta unidad | Compile forzado | Correctos | Fallos | Excluidos |
|---|---:|---:|---:|---:|
| Elixir1.20.0 / OTP29.0.5 | 75 fuentes | 655 | 0 | 28 |
| Elixir1.17.3 / OTP27.3.4.17 | 75 fuentes + dependencias desde build vacío | 655 | 0 | 28 |

Seed37556, warnings-as-errors. Los28excluidos son22proveedores y6Postgres;
no son aceptación de esos sistemas. No se repitió1.18/28 en esta unidad.
Harness compilado23/23; C0 exige14indicadores, docs7/7, R3instrumentado1/1,
tres reports de evals y load smoke160, todos con exit0.

**Paquete runtime24/24, strict pendiente en los cuatro grafos nativos.** El TAR
de93archivos, seed771506, pasa seis nombres ExUnit por none/API/SDK/exporter,
sin excluidos/skips. Cada grafo emite una deprecación `xref.exclude` de Req0.6.1
bajo Mix1.20; exporter añade los nueve warnings gproc/OTP29 conocidos. El runner
retiene **exit1**, aunque el runtime pase. No se cambió lock, floors ni dependencias
para ocultarlo. La CI quedó explícitamente offline y con artefactos por fase;
su driver pasó localmente, no se atribuye una ejecución remota GitHub.

La ejecución de auditoría terminó como WIP sobre69c2747; posteriormente quedó
integrada en7f25b33. El archivo `docs/archive/2026-09-testing-audit.md` conserva
comandos, provenance, controles negativos y liquidación de Orca.

## Qué hemos consolidado

| Área | Resultado vigente |
|---|---|
| Core y streaming | Un loop para sync, `stream_text` y stream público; resultado completo o RunError con progreso, historial y modelo conocidos. |
| Tools | Validación JSV antes de efectos, permisos sobre la tool efectiva, JSON portable, outcomes de batch y retries explícitos. Ecto valida el output final. |
| Delegación | Scope compartido, admisión atómica, autoridad de ancestros y contabilidad por identidad sin sumar dos veces los hijos. |
| Runtime y snapshots | Ownership y cancelación, checkpoint confirmado, estado dirty y retry sólo de save; snapshots v2 con lectura v1 validada y policy confiable. |
| Protocolos | Streaming/SSE y MCP con límites, fragmentación Unicode, terminales y cleanup comprobados localmente. |
| Observabilidad | OTel opcional y app-owned, contenido off, redacción previa, processor acotado; OTLP nativo realmente decodificado en loopback. |
| Aceptación | Consumidores de bytes TAR, tres runtimes, escenarios compuestos, secuencias con oráculos independientes, evals y medidas finitas. |

Durante la noche se añadieron **40 tests raíz**. Las correcciones de biblioteca
se centraron en compilar correctamente el processor con SDK opcional en Elixir
1.17 y 1.20. También se corrigieron supuestos de fixtures, dos snippets README y
el runner de aceptación: selectores Mix heredados, destinos con enlaces, warnings
por fase y colisión entre el grafo y su diagnóstico. No se presentan esas
correcciones de tooling como bugs del loop de agentes.

## Evidencia de la consolidación anterior

| Runtime | Compile forzado | Correctos | Fallos | Excluidos |
|---|---:|---:|---:|---:|
| Elixir 1.20.0 / OTP 29.0.5 | 73 fuentes | 619 | 0 | 28 |
| Elixir 1.18.4 / OTP 28.0 | 73 fuentes | 619 | 0 | 28 |
| Elixir 1.17.3 / OTP 27.3.4.17 | 73 fuentes | 619 | 0 | 28 |

Seed `37556`; warnings-as-errors para el proyecto. En los tres runtimes:
C0 **14/14** invariantes, snippets **7/7** y probe R3 aislado **1/1**. Los tests
excluidos son proveedores reales y Postgres, no aceptación implícita de esos sistemas.

- Paquete: **72/72 contratos runtime** en doce consumidores sin symlink al checkout.
  Once pasan también strict; el exporter/OTP29 conserva **exit 1** por nueve
  warnings de gproc. No quedan warnings propios de ExAgent en esos consumidores.
- OTLP compuesto: **68 spans en 11 POST** inspeccionados, con uso por request,
  jerarquía, cancelación, checkpoint, privacidad y aislamiento de contexto.
- Carga: **4.000 runs medidos correctos** y **12.200 spans locales** sin pérdida
  normal; la saturación separada admite 32 spans y descarta 610 de forma observable.
  Son medidas sintéticas con definiciones reutilizadas, no latencia de LLM ni SLO.
- N14 concluyó **sin optimización nueva**: la medición no identificó un hotspot
  causal que justificara alterar la base o retirar controles.

El [procedimiento de verificación](development/verification.md) mantiene los
comandos actuales. El registro completo está en
[la evidencia histórica de consolidación](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/action-plan.md).
Los artefactos `/tmp/opencode/exagent-night-final-verification.*` y el TAR
`exagent-night-final-reviewed-preview.tar` pertenecen a esa aceptación anterior;
la reorganización documental produce un artefacto local distinto.

## Histórico: límites de la consolidación anterior (previos a R5/C7 aceptado)

1. **HTTP nativo OTel no certificado para una VM longeva:** el exporter 1.10.0
   conserva perfiles/átomos y puede dejar solicitudes TCP tras timeout/shutdown.
   Su callback exitoso ignora `partial_success` y convierte booleanos en strings.
   La [guía de observabilidad](guides/observability.md) delimita lo probado.
2. **Backend por elegir:** el usuario confirmó instancias de Opik existentes;
   faltan destinos, acceso e histórico. Partir de ellas y comparar la información
   recuperada en API/UI antes de justificar un cambio a Langfuse u otra opción.
3. **Aceptación externa abierta:** proveedores/modelos y Postgres se verifican en R8.
   R8 acepta consumidores representativos del paquete. La adaptación real de
   Dragonex/WhoamAI queda para después por decisión del usuario; las fixtures no
   certifican esas aplicaciones.
4. **C7 pendiente de implementación:** ahora incluido en el alcance v2 por decisión
   expresa del2026-09-21. El código actual conserva aprobación síncrona; snapshot
   no equivale a continuación persistida ni a replay de efectos. R4/R5 lo desarrollan.
5. **Tooling del host:** un bootstrap nocturno sobrescribió accidentalmente el Hex
   compartido por heredar `MIX_ARCHIVES`. Se contuvo y corrigió el runner; la
   reparación del Hex compartido sigue pendiente de autorización. Los gates
   finales utilizaron tooling aislado. Véase [entorno](development/environment.md).

## Situación de trabajo

La ejecución nocturna cerró como WIP, incluidos los untracked, sobre HEAD
`c08125be71eada363d08ca463cc7df2ea7855e4a`, sin commit, merge, bump, publicación,
despliegue ni modificación de consumidores durante aquella ejecución. Orca terminó:
16 Dispatches, 15 workers distintos cerrados; sus handles no se reutilizan.

Al iniciar la auditoría de testing se observó HEAD `69c2747` y árbol limpio: la
consolidación ya estaba integrada en Git. El baseline reproducido fue620/28,
seed37556; sus mejoras se integraron posteriormente en7f25b33. La prioridad activa
está en [el roadmap R0–R9](development/roadmap.md); la
[auditoría de testing](development/testing-audit.md) permanece cerrada.

## Reorganización documental verificada — 2026-09-10

Las guías vigentes, arquitectura, roadmap y relevo están ahora bajo `docs/`;
los cinco registros grandes de la ejecución anterior se conservaron en el archivo.
Se actualizaron las referencias, los lectores de snippets y el manifiesto.

- Suite nativa de esta unidad: **619 correctos, 28 excluidos**, seed `348677`.
  La matriz1.18/1.17 de arriba sigue siendo evidencia de la consolidación anterior;
  no se repitió ni se atribuye como nueva verificación de esta organización.
- Snippets: **7/7**, seed0; **120 enlaces locales** comprobados en20 Markdown.
- ExDoc y formato global pasan con los nuevos grupos/rutas; no hay colisión entre
  el README raíz y el índice documental.
- Preview con91 archivos: documentación vigente incluida, `docs/archive/` excluido.
  Los cuatro consumidores nativos pasan **24/24 contratos runtime**. None/API/SDK
  pasan strict; exporter mantiene el exit1 conocido por nueve warnings gproc.
- El control de aislamiento pasa con el nuevo manifiesto, sin instalar nada en
  esa comprobación ni modificar el tooling compartido.

Las salidas temporales están en `/tmp/opencode/exagent-docs-reorganized/` y
`/tmp/opencode/exagent-night-package-docs-reorganization/`. La versión y los
contratos runtime no cambiaron. El siguiente trabajo es confirmar el entorno
autorizado para la comparación de backend, siguiendo su plan específico.
