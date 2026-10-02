# R6 — secuencia durable: implementación y aceptación acotada

## Flow11 — router/fan-out/fan-in/C7, 2026-10-01, implementación/verificación offline completas

`Coordination.Flow.new/run/resume` implementa router host explícito y paralelo
plano con max32 ramas/concurrency32(default4), inputs raíz independientes, ordered
merge, fail_fast(default)/collect y el journal/scope/approvals únicos. ADR8.44
registra causa, alternativas, formatos, impacto/migración y límites. Frame11 sólo
Flow, read9/10 conservado, sin conversión, rootModel ni request ficticia.

Collect A8 real conserva Afailed+B(D)paused+C parcial, decide/reanuda y completa
sin repetir A. Nuevo host/VM sólo JSON ejecuta D hasta final, crash71 antes del
wrapper B, recover explícito y otra VM termina B/C. Fuentes Model/tool/hooks y
contadores históricos exactos conservados. Crashes73 separados durante selector
y merge vuelven uncertain en otra VM sin callback replay ni active-budget refund.
Muerte real de owner con Model en vuelo conserva efectos y guards uncertain.

Focales anteriores y rojos en
`/tmp/opencode/exagent-v2-codex-t6qgpstl/flow/` (no sumar reruns):

- `matrix-third.log`:12pases,exit0 (orden/desorden/concurrency, known host-failure,
  router, collect C7, ordinary retry exhaustion, límitesJSON rama/merged±1, typed).
- `vm-matrix.log`:13pases,exit1 sólo warning de variable fixture; warning eliminado.
- `admission-second.log`:12/12,7.1s,exit0 (ACK before/after cuatro fases host,
  deadline after lateACK, global authority, gramática y constructor).
- `admission-third.log`:15/16,exit2; `admission-fourth.log`:17/18,exit2. Nuevo
  oráculo deny suponía counter/Effect legacy9; durable10/11 cuenta2 host intentos
  denied sin ejecutar tool callback ni crear Effect externo. Test corregido exige
  source host/permission_denied y ToolReturns denied, sin cambiar runtime.
- `flow-matrix-final01.log`:31/34,86.0s,exit3. Typed omission tenía boundary
  original checkpoint y no output; test conserva ese marker/attestation. A10 halló
  ausencia real del span delegation durable y parentage bajo run padre. Corregido
  productor observacional; `typed-deny-spans-fix01.log`:3/3,9.3s,exit0.
- `fatal-drain-focal01.log`:0/1,exit2; fail_fast dejaba claimed pese a raw sibling
  conocido. Owner reconoce rama drenada sin asignarle fatal ficticio; sólo root
  cierra tras DOWN global y certificado original. `fatal-drain-focal02.log`:1/1,
  exit0. Variante unknown original intent permanece running/rawnil; se conserva
  su oráculo de incertidumbre y no se inventa un raw unknown confirmado.
- `pipeline-first.log`:recipe pública exit0,7requests/3toolAttempts/2effects.
  `examples/flow_pipeline.exs` define execute(tracing,context) sin IO al importar;
  sólo `--self-test` ejecuta. A10 nativo agrega17spans,18con application parent,
  mismo trace y ancestry Flow→branch y tool→delegation→D. Terminal resume sinspan.

Recibos finales del owner, sin reruns del padre/reviewer:

- `flow-matrix-final03.log`:59/59,87.7s,exit0 en fuente previa a los findings.
  `regression10-9-final01.log`:183/183,155.2s,exit0 de12 familias causales10/9,
  en esa misma fuente anterior. Los reruns no se suman como casos nuevos.
- Review única009: `review009.md`/`review009-report.json`,3 findings. P1:
  Model ya admitido llega con tool_calls después del ask hermano y queda claimed;
  variante worker registrado aún sin nodo. Rojo `review-race-red01.log`0/1 y
  no-node `review-fixes01.log`; fix `review-race-fixes02.log`2/2,7.2s,exit0.
- El mismo P1 impedía recover de approval/draining conocido tras ACK perdido:
  `review-approval-recovery-red01.log`0/2 invalid_record; fix02 2/2,6.5s,exit0,
  call_wait/node_suspend recover ready→pause sin repetir Model/effects.
- Dos P2: plazo actual de rama descartada/completed bloqueaba la activa (rojo
  `review-repros01.log`0/2), y ACKclaim tardío omitía plazo actual antes de codecs
  (hallazgo estático, sin atribuir un rojo original). `review-timing-trace03.log`
  4/4,9.5s,exit0 ejecuta unchosen/completed y lateACK root/leaf. `review-delegate-deadline04.log`
  4/4,11.2s,exit0 amplía lateACK a delegado y exige0 codec/resolver/Model/effects,
  claim+revision confirmados intactos, sin refund ni token perdido inventados.
- `review-boundary-variants03.log`:5/5,exit0, Model tardío ordinary/delegate,
  batch ACK antes/después y muerte real con Model incierto durante approval drain.
  Unknown conserva intentos/efectos y presupuesto abandonado; no resume/replay.
  Rojos variants01/02 preservados: lease fixture5s clampa timeout del delegado;
  prueba final usa15s para esa variante sin cambiar defaults/guards. Budget finito
  abandona su reserva y bloquea resume; casos known de recover usan presupuesto
  ilimitado, y uncertain conserva finito20s. Captura exacta espera node_suspend
  ACK de A antes de matar owner, evitando un CAS concurrente ya admitido.
- `flow-matrix-final04.log`:73/73,149.3s,exit0 en fuente final post-fixes:
  16 runtime+34 admission+23 observabilidad. `deadline-compat-after-review.log`:
  11/11,10.2s,39excluidos,exit0 (7 admission10 y4 plazos públicos resume9), necesario
  por check del plazo efectivo antes/después del codec compartido. Son84 casos
  distintos en fuente final;183 anteriores se cualifican aparte.
- Todos test commands: `mix test ... --warnings-as-errors --max-cases 48 --seed 37556
  --timeout 600000`; trace sólo identifica focales. Prefijo local aislado, argumentos,
  exits y SHA completos en `flow/REPORT.md`. `format-after-review.log`,
  `compile-after-review.log`, `source-check-after-review.log`, `diff-after-review.log`:
  exit0. Manifiesto21 fuentes final `final-source-after-review.sha256` SHA256
  `2f705e59c0b4dc31ddd4e4f2f09473ec19aa9a36246f514f5fa7d6a921c601a1`;
  lockROOT sigue `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.

Una revisión1/1 terminada; las correcciones son recibos del implementador y no
una segunda pasada independiente. El reviewer incluye recepción acotada de la
receta016 ejecutada por el padre en consumer/freeze propio, con otro lock identificado.
SQL/A8, backend A10/live, candidata/FULL y distribución tienen gates distintos;
estos84 offline no los atribuyen. Se conservan guards Model/root sin certificado
y límites originales; no se promete cierre failed para IO incierta, cancel/expiry
general, Flow anidado o graph DSL. Sin bump/commit/publicación. Build/lib se liberan
al padre tras estos recibos; ninguna suite del owner queda ejecutándose.

## Vertical ejecutable de delegación10 — 2026-10-01, implementación y regresión cerradas

Productor/restore10 reutilizan el WIP nativo y sus certificados CAS aceptados.
Runtime real A→B(D)→C completa7 requests/4 tools; mixed sibling+dos asks pausa
quiescente con cinco workers DOWN y reanuda la cola aprobada. VMfresh ejecuta D,
cae antes del wrapper B y, tras recover explícito, otra VM completa B/C sin repetir
A/B/D ni hooks confirmados. Wrapper ya admitido sin control conserva uncertainty.

Default durable nuevo: slot64KiB intersectado con payload/historia originales y
bytes Outcome canónicos. La reserva4×6×1MiB hacía imposible la primera tool dentro
de8MiB;4×6×64KiB mantiene cada proyección y las cotas existentes. No garantiza
cualquier batch/profundidad. Exact/+1 produce resultado/marker-error observable;
restore no amplía el slot persistido. Texto ordinario70KiB conserva el slot1MiB.

Errores confirmados tool/wrapper/retención/accounting/host cierran failed sólo
desde owner después de DOWN. Se conserva raw, marker, subtotal confirmado y fuente
de efecto; no inventar usage, observación, intent ni refund para un IO incierto.
Model/tool sin confirmar requieren recover explícito y quedan uncertain sin replay.
El resultado delegado text/typed grande sólo puede fallar con su preimagen exacta
Model/history/output y límite padre; no cambia los guards NODE/root genéricos.

Evidencia propia en `/tmp/opencode/exagent-v2-codex-t6qgpstl/delegation/`:

- `runtime-mixed-vm-01.log`:4/4,86.1s,exit0. TestVM sólo JSON; adaptador Journal
  de fixture sobre ETS efímero, no persistencia SQL/archivo cualificada.
- `final-matrix.log`:26/26,29excluidos por selección,61.3s,exit0.20casos nuevos
  negativos/delegates/ACK/race/deadline/deny/drain/typed/retención más6defaults/typed.
  Se solapan con los focales previos; no sumar como pruebas independientes.
- `integrated-source.sha256`:17fuentes/tests sellados antes de la suite completa.
  `initial.sha256` conserva el baseline. `integrated-full.log` terminó con
  1543/2093pases,550fallos,28excluidos,2482.5s,exit2.531fallos son fuentes de fixtures
  históricas que generaban10 al probar9;11 son interceptores ACK con shape9,4 son
  oráculos del root nuevo,2 son retry real y2 son oráculos de gates ya implementados.
  El run rojo queda íntegro y no constituye aceptación verde.
- Revisión única en `review.md`:dos P2. `repro-current-slot.log` reproduce por API
  C7 raw delegado8KiB aceptado por el slot persistido64KiB pero envuelto pese a la
  cota actual4096. `current-slot-retry-fix02.log`:6/6,13.6s,exit0; cuatro contadores
  originales direct/composition y dos regresiones de cota (delegado C7 y ordinary
  recover explícito). Se preservan raw/child completed/ledger sin callback/replay;
  retry sólo se fuerza false ante accounting inválido. No nueva revisión.
- Las fuentes legacy son filas9 nuevas creadas por CAS, roundtrip Record y
  `Writer.open(9)` o `Composition.resume` público. No relabel de filas10 ni nueva
  opción de productor. Sus oráculos históricos se conservan. IntentDispatch sigue
  ejecutando10 con el interceptor de su comando real. `legacy9-current10-focal01.log`:
  215pases,261.5s,exit0 (input/tool/evidence y admisión/ACK actual).
- `legacy9-runtime10-affected02.log`:552/565pases,13fallos de instrumentación/root,
  1004.3s,exit2. Toda la matriz runtime10 y demás familias legacy están verdes.
  `legacy-capacity-root-fix03.log`:10/22pases,14.3s,exit2; root10 completo10/10.
  Capacity observaba on_writer/ModelTask como si fueran el caller; la corrección
  transmite el PID real por celda ETS de fixture, observa Scope en IO y limpia la
  celda en after, sin tocar runtime ni los oráculos DOWN/±1/CAS/cleanup.
  `legacy-capacity-fix06.log`:12/12,137.8s,exit0. Rojo03/04/sintaxis05 conservados.
- Regresión acumulada:784casos distintos (215+565+4counters originales); los13rojos
  del segundo lote están corregidos/verificados, no son13casos adicionales. Estos
  lotes cubren las20familias del FULL rojo. No se ejecutó otro FULL ni se afirma que
  el FULL final global sea verde. La integración de otras verticales requiere su
  comprobación global posterior; no repetir este mismo lote rutinariamente.
- `final-source.sha256`:38fuentes/tests, SHA256
  `8718022bde9867a6bc8f88ffff59f0943458746c9b0c25352f43743038665154`;
  formato/check-formatted y diffcheck exit0. Lockc20a0cb9 intacto. Revisión única
  `review.md`, SHA256`2291fb295d07bdcaf8b4f2f29e20785f4b148c85f50761cc4bad075eead4312f`.
  Los dos P2 se corrigieron con evidencia propia, sin re-review. REPORT final y
  comandos/exits en el mismo directorio. Todas las VMs propias han terminado;
  ROOT/_build liberado al padre, sin nuevos procesos de este objetivo.
- Rojo default previo `repro-defaults.log` y rojos de cierre/retención/typed
  conservados; la corrección no aumenta8MiB, cleanup/reservas ni permite replay.

Implementación y regresión de esta vertical cerradas; aceptación acotada a decidir
por el padre con este recibo de la única revisión ya consumida. No aceptación general R6,
router/fan-out/fan-in, cierres Model/root aún sin certificado, SQL/live ni release.

## Base CAS10 recibida antes de la vertical ejecutable — 2026-10-01

Contratos/journal/CAS10, accounting, output/retry, cierre exitoso y call-fatal fueron
verificados/revisados por incrementos internos anteriores. **Agotamiento y su reserva
compuesta quedan aceptados en ese mismo alcance interno**, no productor/VM/R6:

- Owner: `/tmp/opencode/frame10-exhaustion-matrix-60bpPK5e/REPORT.md`, SHA256
  `8631112f44103978a4b31530f67ccb10a4640b4c10e6dbe42e8e7870fa6b6b88`.
- Review independiente favorable: `/tmp/opencode/frame10-exhaustion-capacity-review-f0o9c3vn/REPORT.md`,
  SHA256 `46f134395da2e096a43d83f3ea5ed601e26b9354788f367e2f0052ab33beefa9`.
  Oráculos4, selección17, probes propios3 y legacy6 pasan; compile118WA/formato/diff0.
  Son ejecuciones solapadas, no30 casos nuevos. Fuentes7/7 y artefactos979/979 intactos.
- Padre previo a la pausa: mismos7probes,54.0s,exit0 en
  `/tmp/opencode/exhaustion10-parent-q2xfd2m9/`; no casos nuevos ni otra suite completa.
  Fuente868234: −1rechazo temprano, exact/+1cierre/refund. RecordSHA256
  `8a9f5de562d8adeedec6c91776ebd0a3af0ec634896d6aff489fb27346598227`.
- Originales/rojos intactos; copia autorizada del control roomy cambia sólo dos
  líneas, sin relajar±1/refund ni límites de producción. P1 de composición cerrado.

Estos resultados se reutilizan; no se ejecutaron nuevos tests para este recibo.
Último FULL integrado sigue siendo1845pases/28excluidos anterior a CAS10.
Producer/restore10, workers reales quiescentes, fatal generales y recuperación10
siguen pendientes. Próximo encargo: delegación real hasta pausa/decisiones/VMfresh/
retorno y recuperación explícita, no más review de validadores por sí solos.
El [flujo vigente](execution-flow.md) limita a una revisión por objetivo y elimina
re-review/reruns del padre. Los pendientes de review de las notas fechadas inferiores
describen su momento, no abren nuevas rondas ni alteran sus limitaciones técnicas.

## Fix capacidad final-control/recibos10 —2026-09-29, revisión pendiente

Artefactos: `/tmp/opencode/frame10-fatal-capacity-fix-n87qjASq/REPORT.md`, baseline
CONTENT+hash tracked/untracked anterior a edición, originales del reviewer sellados.
Runtime sólo Record; dos archivos test/support nuevos y docs4. Ningún test antiguo,
ScopeLedger/Budget/Authority/Outcome/Store/Writer/productor/restore modificado.

Original boundary_test copiado intacto: rojo1/2,87.7s,exit2 (source1378383 admite y
fatal settlement necesita1382090); primer crédito control lo vuelve verde2/2,94.7s.
Variante causal child reproduce recibo no gastado: source1402911, sink1408418;
corrección Record lo vuelve verde1/1,85.3s. Diagnósticos se solapan con las mismas
obligaciones, no sumar variantes/reruns como aceptación independiente. Dos selecciones
de línea erróneas excluyeron todos los tests; logs conservados, no pases.

La reserva final separa4116 del allowance16384 existente, acredita sólo el JSON de
control final desde null y conserva frontier/raw/resultados. El receipt de child/host
settled se gasta una vez; effect ya libera raw_or_future. Resolution gasta uno de
sus dos recibos; consumed libera sólo el pool restante. Nuevo test successful source
exact reprodujo tool_resolution sin liberar ese recibo, corregido sin cambiar oráculo.
Tests permanentes derivan límites de TODOS los prefijos reales antes del fatal, no
del sink; source−1 rechaza atómicamente, exact/+1 cierran y roomy usa máximo real.
Returns/raw4096, error4096, IDs recibo512 escapados, texto plain/Unicode/escapado,
dos delegados/nietos completed/cancelled y wrapper sibling ya admitido. Roundtrip cada
ACK, Scope/usage/raw/snapshots conservados y refund59971. Crédito final4092 exacto
entre controles nil/error, sin gastar sibling ni frontier; receipts no negativos.

Gates finales sobre fuente sellada:134 seleccionados (incluyen6 nuevos),384.2s/exit0;
original boundary intacto2/2,91.3s/exit0; legacy4/4,86 excluidos por ubicación,1.5s.
Compile forzado116WA, formato global y diff-check exit0. OTP29/Elixir1.20.0,
offline/test/build ROOT absoluto, compile habilitado, WA/maxcases48/seed37556 y
timeout ExUnit600000. Selección: fatal/drain/closure/source/controls, accounting,
output CAS/capacity, success terminal, Record y cleanup. No sumar reruns ni variantes
a esos134. Runtime/tests hash-verificados antes/después; prosa final posterior a
los gates, artefactos e identidad exacta en REPORT.
No FULL rutinario/SQL/live/VM/hooks reales,
otras fuentes fatal, exhaustion/recovery ni producto Frame10/R6 aceptados. Re-review
independiente y probes del padre requeridos; no publicación ni cambio de versión.

## Fix causal de capacidad output10 —2026-09-29, revisión pendiente

Artefactos nuevos: `/tmp/opencode/frame10-output-capacity-fix-TrWhtkHm/REPORT.md`.
Baseline CONTENT+hash tracked/untracked previo, runner inspeccionado y copia verbatim
de probes_v4 del reviewer; originales/logs/sellos preservados. Cambio runtime sólo
Record, nuevos test/fixture, docs4; no cambios en tests anteriores ni guards. La
reserva distingue copias pendientes de bytes materializados, mantiene los slots tool
y añade un recibo por output pendiente. No cambia Scope2/Budget/retention/Store.

Rojo previo propio: probes originales3/5, retry60000B y resultobject60000B bloqueados
tras ACK; después5/5 con el mismo oráculo derivado del coste real. Los límites fijos
históricos ahora rechazan precisamente output_resolution con fila byte-idéntica;
controles8MiB completan.7 tests permanentes: límites reales±1 de retry/success planos
y escapados, IDs recibo máximos, replay, dos retries históricos sin recobro, siblings
simultáneos, cierre/wrapper y Scope2 idéntico. No sumar gates focales como casos nuevos.
Un experimento inicial omitió cursor finish en la proyección local de sizing y falló
invalid_child_terminal; su log rojo se conserva, no se presenta como gate verde.

Gates propios finales:282 pases seleccionados (incluyen7 nuevos),338.7s/exit0;
5 probes originales aparte,11.5s/exit0; compile forzado114WA/formato global/diff-check
exit0. OTP29/Elixir1.20.0, offline/test/build absoluto, compilación activada,
maxcases48/seed37556. Selección incluye output/closure/accounting/guards10, legacy
Frame9/output restore, Record/cleanup/tree-boundaries. Identidades/comandos/exits
en REPORT. No FULL rutinario, paid/SQL/VM,
hooks vivos, productor10 ni aceptación output10/R6. Owner380 anterior sigue histórico:
precedió formato final y3 tests añadidos, sin sello preformat; no se atribuye a hashes
finales. Reviewer240 sí correspondía a su checkout sellado. Esta corrección entrega
gates propios y requiere revalidación independiente, sin autoaceptación de producto.

## Output tipado/retry CAS10 —2026-09-29, pendiente de review independiente

Artefactos: `/tmp/opencode/frame10-output-cas-2HG3aDNz/REPORT.md`, baseline content+
hash previo de tracked/untracked y missing separado, delta final respecto a ese WIP.
Producción: únicamente Frame/Transition/OutputResolution. Tests y fixture nuevos;
ningún test antiguo actualizado, ningún reemplazo global de negativas. RequestData,
ToolEvidence converter, ScopeLedger, productores y motores legacy no se modifican.

Operaciones CAS con identidad owner/attempt/fence/epoch y fases reales: atestación
trusted, consumo retry sin request, suspensión response/request durante drain,
pausa, dos decisiones públicas, reclaim, request siguiente única, success tipado,
childraw→wrapperY→settlement. Retorno de delegado simple también reduce/consume B.
Model y tool sibling aportan usage; consumo/terminal/wrapper conservan Scope2 exacto.
Se prueban límite cero/permitido, dos ciclos con historia completa, agotamiento
negativo sin borrar atestaciones, opid replay/conflicto, fase/epoch y mutaciones
hash/posición/contador/límite/source/fingerprint/orphan/consumo. Cada ACK hace
encode/decode, incluidas decisiones y replay. Ningún callback de output se ejecuta.

Regresión seleccionada `frame10_*test.exs`, composition_output_retry_restore,
composition_output_success_restore, sequence_active_evidence y output_schema_contract:
380 pases/538.7s/exit0, compile enabled, WA/maxcases48/seed37556/offline. Incluye los
6 primeros casos nuevos; no sumar su gate focal6 como casos adicionales. Dos avisos
runtime Req adapter deprecated conservados en log, sin alterar dependencias. Nuevos
casos suspended-response y mutaciones terminales pasan en gate focal final9/16.8s/
exit0 (son9 casos totales, no9 adicionales a los6 anteriores). Compile forzado113
WA, formato global y diff-check exit0; comandos/logs en REPORT. No se afirma FULL
ni aceptación independiente.

Sin mocks de invariantes: comandos trusted sintéticos, Store ETS real. No prueba
hooks vivos, quiescencia BEAM, VM10, SQL, productor10 ni producto R6. Exhaustion/fatal
sin certificado global, rootterminal/recovery/uncertain/cancel/expire/output omitted
continúan rechazados. No migración, publicación, cambios fuera de allowlist ni gates
externos ejecutados. Accounting recibido no se relabela como nueva verificación VM.

## Accounting CAS10 —2026-09-29, implementación interna pendiente de review

**Gate actualizado tras autorización del oráculo:**
`/tmp/opencode/frame10-accounting-oracle-NGrZ5ydw/REPORT.md`. Sin cambios runtime.
Sólo nombre y primera mitad del caso antiguo170: Model con cero observado confirma
operaciónusage exacta/root+B/counters sin readmisión; wrapper injectedusage y todas
otras negativas intactas. Misma regresión235 pasa55.0s/exit0;2 probes originales
separados pasan0.1s/exit0. Compile forzado112WA, formato global y diff exit0.
Primer rerun235 ejecutó todos pero exit1 por assert estático sobre el expected map;
corregido para comprobar el usage realmente persistido, manteniendo igualdad exacta.
Log rojo conservado. Delta acumulado11rutas y diff exacto del test para review; no
aceptación de producto ni ampliación del subset. El registro anterior sigue abajo.

Artefactos: `/tmp/opencode/frame10-accounting-resume-ak7TN45w/REPORT.md`, baseline
CONTENT+SHA antes de cambios. Conserva intactos el reporte bloqueado previo
`/tmp/opencode/frame10-accounting-xL0zt7od/REPORT.md` y sus rojos. Padre autorizó
ScopeLedger exclusivamente `from_map!`→decoder existente dentro de agregación;
los2 probes contractuales se reprodujeron rojos antes del fix y pasan después.

Scope2/Usage/Outcome/Message/Budget/Store sin cambio de formato/aritmética. Frame y
ToolEvidence validan contribuciones y proyección ancestral; Transition registra uso
Model y observación tool trusted opcional atómicamente con su outcome. Sólo10 usa
availability para complete; legacy conserva regla anterior. Retrospectiva UsageLimits
antes de nuevas admisiones; wrap/settle/consume/recibo/retornoD sin nueva contribución.
Error de accounting/fatal unsupported o capacidad conserva fila/progreso confirmado.

26 nuevos casos: nil/mixed/complete/partial/retained, coste público USD y moneda no
convertible, estimación host, modelos parciales, nested root/B/D con sibling contribuido
y dos approvals, pausa/decisiones/reclaim, hijos extra y D completados, rawX→wrapperY→
B siguiente; sumas/counters exactos y sin repricing. Mutaciones orphan/missing/duplicate/
status/digest/availability/ancestor; replay raw/model/batch, CAS stale, rechazo retenido
con sibling confirmado, límites token/coste independientes±1, tools±1, usage bytes±1,
JSON+closure+receipts y CAS sin cambios parciales cuando usage válido no cabe.
Inputs sintéticos trusted; no callbacks reales, producer10/VM/SQL ni quiescencia viva.

Runner inspeccionado `bash /tmp/opencode/frame10-sources-JCYces/run`, OTP29/Elixir1.20,
offline/test/build absoluto, flags `--warnings-as-errors --max-cases 48 --seed 37556`,
timeout600000 y compilación activada. Regresión final seleccionada235:234 pases,
55.6s,exit2. Único rojo: `frame10_causal_controls_test.exs:170` exige rechazar Model
usage no nulo, ahora autorizado; archivo antiguo intacto fuera de allowlist. Los nuevos
tests aceptan cero observado Model con ledger exacto y mantienen rechazo a usage
inyectado en wrapper/settlement. No presentar como suite enteramente verde. Actualizar
ese oráculo requiere permiso puntual; revisión independiente y recepción pendientes.
Primer focal9 ejecutó todos los casos pero exit1 por aliases unused; matriz31 exit0;
boundaries24 ejecutó todos pero exit1 por comparación estática en tests, corregida con
helper parametrizado. No reinterpretar esos exits como WA verde; logs preservados.

Gates finales y hashes en REPORT externo. Sin FULL rutinario ni nueva aceptación
Frame10/R6. Output resolutions/retry/rootterminal/uncertain/fatal/cancel/expire y
productor10 permanecen cerrados; validación de costes aportados no autoriza estimadores
nuevos ni garantiza cabida de todo payload individual válido en cualquier checkpoint.

## Incremento no aceptado —2026-09-29, checkpoint de operaciones Frame10

Owner artifacts: `/tmp/opencode/frame10-transitions-WNqvHSI8/REPORT.md` y baseline
CONTENT+SHA contemporáneo. Primer handoff sólo probe RequestData1, sin edits; padre
autorizó después RequestData2. Conservado historial, no reconstrucción retrospectiva.

Implementado con Store.ETS real desde create: claim y B input, model intent/outcome,
batch, prepare/prepared, begin_effect/source atómico, raw/observación/outcomes,
wrap/settle, attachD+Scope+authority, childterminal/raw, reducción/consumo, dos asks,
suspend/pause/refund, dos decisiones públicas y reclaim/frontier. Roundtrip cada
ACK. Test no inserta journal final. Fixtures proveen comandos trusted, no workers
vivos ni atestación quiescence/PID. Source/binding/raw/childterminal inmutables;
wrapperfinal puede cambiar X→Y sólo después de wrap. Recibo replay no da permiso IO.

RequestData2 interno10 almacena preimagen exacta de fingerprint y valida inputD con
prompt_arg no-default+distractor; bytes RequestData1 y productores9 intactos.
Scope/Authority/Budget/Store adapters/Writer/Composition/Restore no se modificaron.
No callbacks al decode; schemas se validan con el validador local existente.

Verificación fresca: `focal-resumed.log`,113 pases/5.2s (99 anteriores+14 nuevos),
`legacy-resumed.log`,207 pases/199.1s; ambos warnings-as-errors/max-cases48/seed37556,
OTP29/Elixir1.20 aislados, EXAGENT_OFFLINE=1/MIX_ENV=test/ROOT absoluto. Legacy incluye
Record/Store, structural root, sequence writer/approval/frame9 y evidence producer/
partition. Sin FULL ni SQL/cloud/paid. Gates y hashes finales en REPORT.
Rojo conservado: fence esperado2 ignoraba fencing al pause (real3); un negativo viejo
detectó falta de identidad/state en execution?10, guard reforzado sin tocar el test;
FaultStore del test omitía scan_records, añadido al harness sin cambiar adapters.

**Límite explícito:** no se ha cerrado todo el mandato. Global admite sólo uso
externo nil (no coste cero), sin output resolutions/retry, terminal raíz ni recovery;
fatal/output_failed siguen rechazados. Hook/retention fatal conserva baseline y
nunca fabrica éxito/pausa/not_executed tras fallar CAS. Reservas conservadoras de
retornos y receipts, límite8MiB/checkpoint_limit; no capacidad garantizada. Próximo
incremento debe integrar los pendientes sobre estas operaciones, y luego productor/
quiescencia real. Revisión y aceptación del padre pendientes; no producto/VM10.

## Recepción vigente —2026-09-29, evidencia activa Frame9 aceptada offline

Aceptado el subset de única hoja activa9 con batch final/resuelto, accounting
aceptado y control completo: prefijos propios continuables, texto terminal tras
tools y output retry/success actual atestado, con/sin tools, incluidas approvals
históricamente consumidas. Misma `Composition.resume/3`, recover explícito y referencia
exacta; legacy7/8/single9, completed data-only y C7 primer batch todo-pending conservados.

| Evidencia recibida | Resultado e identidad |
|---|---|
| Owner final | FULL1845pases/28excluidos/1410.3s, exit0; compile forzado109WA/formato global/diff0;306 identidades intactas. `/tmp/opencode/sequence-active-matrix-xzij2ykz/REPORT.md`, SHA256 `5da10174d09a91cf55f4250264cdfc7a7776e95e9b3280a378429775c924c1aa` |
| Review independiente acumulada | Favorable acotada:40casos existentes+4propios; identidad9+306. `/tmp/opencode/sequence-active-review-u4tSrE50/REPORT.md`, SHA256 `ed38ec5b3f67feac192e6af3641d8f1d373bea145dc2e5b472f287a234528153` |
| Padre | 9/9hashes cotejados y copia nueva con roundtrip de rutas; `/tmp/opencode/active-parent-psg836g3/parent.log`: mismos4probes corregidos,4pases/16.7s/exit0, no casos adicionales |

Aceptación sellada en `docs/orchestration/2026-09-28-native-f19085/tasks/sequence-active-evidence.md` (sólo checkout), última sección.
Owner55casos=25+30. FULL pertenece al owner, no a review/padre. Se conservan focal
owner54/55 rojo→4focales correctivos→FULL verde y fallos previos de harness. Review
original3/4 permanece rojo: el oráculo esperaba que current allow superase original
ask. La copia corregida4/4 verifica original∩current y cero IO nuevo, sin source fix;
no convierte retrospectivamente el original en verde. Receipt docs5 posterior a
los bytes revisados, sustituyendo sólo pendientes de aceptación de esta unidad.

**Contrato/fronteras:** Record.validate y Retry.plans globales preceden la vista
privada; calls/reducers usan el Record original. Approval consumida es historia
resuelta, no permiso para una request nueva aunque call ID y args sean iguales.
Contadores host exactos, sin repricing/redebit histórico; uso normalizado/estimado
conserva calidad cualificada. Fatal actual consumible falla operativamente sin C ni
refund final inventado; fatal histórico rechaza. Preparación typed host conserva
prioridad. Retry estructural unsupported; excepción tool deja intent unresolved,
no outcome unknown confirmado. Token parse inflado no prueba CAS válido oversized;
JSON+cleanup, receipts, history y checkpoint son capacidades separadas.
ETS y ficheros entre VMs prueban este alcance offline, no durabilidad SQL certificada.
Callbacks ya iniciados no tienen preempción atómica. No aceptación mixed/control
parcial/raw/uncertain, delegación, router/paralelo, R6 general ni SQL/live/producción.
Siguiente: investigación estructural sólo lectura de delegación+C7 quiescente y
mixed-control, sin implementación activada. Contrato/uso host en diseño8.42.

## Histórico: ampliación de matriz activa —2026-09-29, antes de review independiente

Continuación de la misma unidad anterior:30 casos adicionales (55 acumulados en
`sequence_active_evidence_test.exs`), fixture EffectiveArgs y runtime intacto respecto
del checkpoint. Baseline WIP recuperable, logs rojos/verdes, manifiestos y deltas en
`/tmp/opencode/sequence-active-matrix-xzij2ykz/REPORT.md`.

- Model/tool nuevos después de batch activo resuelto: observability bloqueada por
  barreras, expiración real budget/lease y controles positivos, sin IO posterior a
  expiración ni refund inventado. Conserva6requests/3tools en los positivos.
- Approvals consumidas: refs/policy raíz y hoja rechazan preclaim; schema y binding
  Model real conservan validación postclaim. Args efectivos distintos del original
  sobreviven allow y current-deny predispatch; historia/approvals/effects idénticos.
  Corruptions de ID/run/call/args/schema/revisión/receipt/policy/definition y plan
  huérfano global rechazan antes de callbacks. Retry administrativo estructural
  sigue rechazado por la API; no se fabrica un productor de planes válidos.
- Tres contribuciones tool: tokens parcialmente disponibles, calidad partial y
  coste estimado17. Operaciones/batches históricos exactos una sola vez, sin repricing
  ni redebit; nueva request suma sólo su uso. El coste58 del checkpoint anterior
  demuestra precios Model; estas pruebas añaden evidencia tool separada.
- Owner kill antes/después de intent y durante Model, DOWN Writer/Scope, raw antes
  de finalize_call, unresolved Model y tool exception, recuperación uncertain negativa
  y resultado de Model tardío fenced después de recover. La excepción tool deja
  intent running sin outcome persistido, no se presenta como outcome unknown confirmado.
- JSON válido mediante CAS±1 incluye cleanup; cancel/replay siguen posibles en cota.
  Receipts reales llegan a1017+7reservados=1024, siguiente checkpoint rechaza. History
  append fatal±1 y checkpoint público±1 conservan evidencia. Parser token±1 separado:
  −1/exacto llegan a CAS y dan invalid_command; +1 invalid_checkpoint_token; token
  original confirma/replay sin IO. No se afirma un commit válido sobredimensionado.

Gates finales: compile forzado109 WA, formato global/diff exit0; FULL integrado único
**1845pases/28excluidos/1410.3s, exit0**, offline WA48seed37556.306/306identidades
fuente intactas antes/después. Incluye regresiones legacy7/8/single9/C7 todo-pending,
sin convertir exclusiones en pases. Rojos de harness/oráculos nuevos conservados en
REPORT; focal activo54/55 seguido de4/4 correctivos y FULL final verde, sin atribuir
55pases al focal rojo. Delta actual6rutas, acumulado9 contra baseline funcional inicial;
runtime/VM/dos antiguos casos autorizados idénticos al checkpoint recibido.
Revisión independiente acumulada y aceptación padre
pendientes; no aceptación R6 general, mixed/raw/delegación/router/paralelo o producción.

## Histórico: checkpoint funcional —2026-09-29, antes de aceptación

Mandato sellado posterior a la recepción inferior. Runtime exclusivo:
`lib/exagent/continuation/composition_restore.ex`; ningún cambio de Frame/Writer/
ToolEvidence/Composition/Record/Store/Scope/formatos. Vista privada propia, Record
original para calls/reducer, retry plans globales vacíos y wrappers legacy intactos.
Approvals propias consumidas requieren identidad digest y batch entero final/resuelto
seguro. Conserva approved-pending primero, contadores/control/consumidores existentes.
Contrato y alternativas en diseño8.42.

Checkpoint completo probado: Aeffect→B dos approvals públicas→approve/resume→pérdida
ACK tool_resolution→retry Store-only→recover explícito→VM nueva→output retry atestado→
segunda pérdida ACK/recover→segunda VM nueva→Bfinal→C. Effects y approvals históricas
exactas, A child y operaciones de ledger inmutables, traps de A/B históricos;6requests,
3tools, coste58 (3×7 históricos +1×11 +2×13 nuevos), sin repricing histórico.

25 casos nuevos: orden/reset/increment retry y fatal actual, call-ID reutilizado entre
requests/hojas, selección atestación actual frente a histórica, current-deny/allow con
approvals consumidas, dos claimants, ACK claim/intent tardío sin IO, tokens Store-only
claim/intent/outputB/inputC, final sin resolución negativo, orphans/hash/fatal histórico
negativos globales, host typed antes de fatal, reserva finita abandonada. Cambios de
tests antiguos exclusivamente los casos originales sequence_resume593–630 y632–672:
outputretry B→count7/C diario A,C y terminal B posttools→Boutput/C diario A,B,C,
claim nuevo/loadB/no loadA. `sequence_approval` partialapprovedeffects sin resolución
queda intacto. Negativos restantes conservados.

Artefactos recuperables, baseline completo del WIP anterior, diff exacto y comandos:
`/tmp/opencode/sequence-active-evidence-oe6a6hgv/REPORT.md`. Focal inicial amplio362
pases/648.1s anterior a la ampliación; matriz25/25/92.2s posterior. Checkpoint final:
compile forzado109 WA, focal386pases/731.5s, formato global y diff exit0, WA48seed37556.
Gates registrados en REPORT, sin atribuirlos a FULL. Rojos conservados: oráculo de
attempt_id terminal nil/fence release, callback on_writer sin :ok, y boolean and sobre
token mapa en harness; corregidos sin debilitar invariantes runtime.

**Pendientes exactos para continuar la misma unidad:** matriz activa de observability
delay budget/lease/positivos; refs/policy/schema/Model binding sobre approvals consumidas;
accounting parcial/cualificado y no repricing con herramientas contribuyentes; kill de
owner ready/uncertain y cleanup; JSON+cleanup/receipts/history/checkpoint±1 y parser de
tokens±1 separados de CAS; completar raw/uncertain/approval-history mutation y retry
plans globales negativos nuevos. Hay cobertura baseline de muchas de esas fronteras,
pero no se presenta como certificación de esta nueva combinación. Después, identidad
final y FULL integrado único WA48seed37556 con timeout≥1800000, review independiente
acumulada y aceptación padre. No FULL final ni review en este checkpoint; no cerrar
gate activo, no reiniciar trabajo ni revertir el funcional probado.

## Base recibida —2026-09-29, C7 secuencia todo-pending aceptado offline antes de evidencia activa

Aceptado el primer batch propio totalmente pending de una hoja Frame9: A completed→
B dos approvals→pausa raíz ACK→decisiones host→nuevo claim→resume en VM nueva→C.
Resultado raíz/hoja proyectado paused, output nil y referencia confirmada; B sigue
running persistido y C no empieza durante la pausa. Aprobar no ejecuta ni reclama:
partial approve deja pending, último approve ready y deny administrativo es terminal.
Prefijo histórico sin replay de efectos/callbacks ni repricing; counters host, reserva
durable de batch y refund raíz exactos, separados de uso normalizado/estimado cualificado.

| Evidencia recibida | Resultado e identidad |
|---|---|
| Owner final | FULL1790pases/28excluidos/1121.2s, exit0; focal129, compile108WA/formato global/diff0. `/tmp/opencode/sequence-approvals-matrix-f14f3b0f/REPORT.md`, SHA256 `e8fc58f623fc93c845e8e0e129263759d234f75bd9526e566f7897ce942ad422` |
| Review independiente acumulada | Favorable acotada:271casos existentes+7propios, compile108WA/formato global/diff0; identidad15+303 intacta. `/tmp/opencode/sequence-approvals-review-f14cfe/REPORT.md`, SHA256 `75d0d3213764b5821acc8242babc27126784fc6d30cd59060225f2cd6919bd6f` |
| Padre | 15/15hashes cotejados, helper/runner inspeccionados, copia nueva con roundtrip de rutas. `/tmp/opencode/sequence-approvals-parent-f19085/parent.log`: mismos7probes,7pases/13.2s/exit0; no siete casos adicionales |

Aceptación sellada en `docs/orchestration/2026-09-28-native-f19085/tasks/sequence-approvals.md` (sólo checkout), última sección.
Los57casos owner son43+14; no se suman reruns ni se atribuye el FULL al reviewer/padre.
El padre acepta los dos deltas causales antiguos Frame9 allpending→paused ACK con
no effects/no successor y revisión exacta, contrastados con los originales aceptados;
no se inventa autorización previa. Esta recepción docs5 es posterior a los bytes
revisados; conserva fallos/harness/provenance y sustituye sólo sus pendientes de aceptación.

**Fronteras:** certificación allpending después de recoger resultados async, no
barrera atómica preadmisión. Siblings mixed pueden haber hecho efectos: fail-closed
sin pause/refund. Current permission deny puede producir outcomes denied y continuar
texto/C sin tools B; no es deny administrativo. Refs declaradas/policy rechazan
preclaim; schema/binding Model efectivo se comprueban postclaim, sin IO nuevo.
Token parse inflado bajo/exacto devuelve invalid_command; +1 invalid_checkpoint_token,
no commit sobredimensionado. Capacidad JSON+cleanup/receipts es evidencia separada.
Extensión experimental Record2/Frame9 direccional: lectores antiguos rechazan filas
C7 nuevas; deadlines antiguos intactos. Espera humana no consume active budget pero
sí TTL/deadline lógico; nuevo claim reserva saldo, refund final único. Sin promesa
de preempción de callbacks iniciados ni mixed/raw/delegación/general R6/router/paralelo,
SQL/live/producción o binding MCP endpoint/principal. Siguiente trabajo: investigación
sólo lectura, sin nueva implementación activada. Uso host en diseño8.41.

## Histórico: C7 ampliación de matriz owner —2026-09-29, antes de aceptación

Owner fresco f14f3b0f añade14 casos a `sequence_approval_test.exs`, sin modificar
runtime, fixture/VM ni tests antiguos. Baseline recuperable/manifiesto, logs y delta:
`/tmp/opencode/sequence-approvals-matrix-f14f3b0f/REPORT.md`.

- Dos token parse±1 pause/claim: bajo/en cota llegan a Store CAS real y rechazan
  comando inflado; encima rechaza el parser antes de Store. No son commits válidos
  sobredimensionados ni medición de JSON+cleanup. Control token original commit/replay
  sólo persistencia; la capacidad CAS válida sigue cubierta por matriz anterior.
- Cuatro cambios coherentes refs/policy/schema postapproval y dos binding Model
  actual cambiado/idéntico. Refs/policy preclaim; schema/binding actual postclaim,
  sin efectos nuevos y approvals intactas. Mismo binding completa5requests/3tools.
- Seis barreras approved-tools/next-Model × budget/lease/timely. Ambas tools esperan
  antes de admisión; Model siguiente espera tras intent. Expiración real no hace IO
  nueva ni refund inventado; positivos conservan5requests/3tools y una reserva/refund.
  El redactor es callback confiable, no se promete preempción de callbacks iniciados.

Focal1:5/6 exit2, oracle schema erróneamente exigía preclaim. Causa verificada en
Frame.restore_tools; corregido sólo test. Focal2:4/10 exit3, observability puesto en
step_options no admitido y warnings de comparaciones constantes; harness corregido
al option público raíz y tags ExUnit. Focal3:10/10 exit0; binding:2/2 exit0.
Focal-final:129/129,188.9s,exit0 offline WA48seed37556, incluye regresión root vacía.

Provenance oldtests: extraídos sin modificar el TAR
`sequence-intent-fix-recovery-unique/baseline-wip.tar.gz`; originales/hash/diffs en
`oldtests-provenance.json`, `sequence_run_test.exs.diff` y `sequence_writer_test.exs.diff`.
Delta limitado a las dos expectativas Frame9 all-pending→paused ACK/no effects/
no successor; no se atribuye autorización retrospectiva. Recepción pendiente padre.
Gates finales: FULL integrado único1790pases/28excluidos,1121.2s,exit0; compile
forzado108 WA, formato global y diff exit0. Identidad runtime/tests/config/mix
sin cambios durante FULL (`pre-full.sha256`, `post-full-identity.log`). Delta
acumulado15rutas contra baseline anterior en `delivery-cumulative.diff`, identidad
en `final.sha256`; ampliación sólo test+docs4. Review independiente y aceptación
C7/R6 permanecen pendientes. Los57casos de approvals son43previos+14nuevos, no reruns.

## Base recibida —2026-09-29, recuperación acotada aceptada offline antes de C7

Aceptado `Composition.resume/3` (opciones por defecto en `/2`) sobre Frame9 ready:
empty, between_steps, input confirmado sin operaciones propias, terminal texto
sin tool-history propia y typed-succeeded admitido. Completed sigue data-only.
Recover administrativo es explícito; nuevo claim/attempt y un único Writer/Scope
continúan el mismo lifetime. Prefijo cerrado conserva accounting/precios sin replay
de callbacks, modelos ni estimadores; helper atómico importa el árbol host exacto.
Claim ACK fresco fija el deadline cached común a preparación y ejecución. El guard
post-ACK de intent y observabilidad limita dispatch al tiempo restante sin readmisión:
contadores host exactos, intent unresolved y parcial confirmado permanecen intactos.

| Evidencia recibida | Resultado e identidad |
|---|---|
| Owner final | FULL1733pases/28excluidos/967.8s, exit0. `/tmp/opencode/sequence-intent-fix-recovery-unique/REPORT.md`, SHA256 `e959dc1133b9f430d47b660997e5d602681cdca3cd9613a20dc5e0d21c4d3c7d` |
| Review fresca independiente | Favorable;29(2lateACK+10prior+17dispatch)+113focales+3nuevos observability pasan;392/392fuentes intactas. `/tmp/opencode/sequence-intent-review-fresh-f154c165/REPORT.md`, SHA256 `4e55a3427e2669aa6272e1ab745ed47ae39e58c0368df3b3ba6a5a7175718c4a` |
| Padre | Identidad6/6 cotejada; harness completo copiado con sustitución de ruta y roundtrip. `/tmp/opencode/recovery-parent-3_d5tlzx/parent-final.log`:15/15,12.6s,exit0, mismos2lateACK+10prior+3observability, no15casos adicionales. LateACK requests=[] y revisión6 intacta |

Aceptación sellada en `docs/orchestration/2026-09-28-native-f19085/tasks/sequence-recovery.md` (sólo checkout).
Esta recepción documental es posterior a los bytes verificados; sustituye los
pendientes de aceptación de recovery de los hitos inferiores, no sus resultados.
P1/P2 rojos, fallos de harness (incluido setup observability) y sampling10ms histórico
se conservan con su interpretación original, sin convertirlos en gates verdes.

**Límites:** finito abandonado sigue agotado; positivo ilimitado sujeto a autoridad,
lease/TTL/cuotas. Nuevas filas separan autoridad lógica de lease/budget; deadlines
antiguos persistidos no se amplían. Callbacks iniciados no tienen preempción atómica.
Subsets legacy7/8/single9 conservados. Fuera: batch/output-retry activo multileaf,
tools propias fuera del subset, raw/uncertain, C7 composiciones, delegación,
router/paralelo, R6 general y SQL/live/producción. Uso normalizado/estimado mantiene
su cualificación separada de contadores host. MCP SDK conserva su aceptación
independiente; no cierre R7/A9/G4. Siguiente C7: investigación, no implementación
activada. Sin migración persistida, bump ni publicación.

## Histórico P1 residual: ACK intent tardío —2026-09-29, antes de aceptación

Review `/tmp/opencode/sequence-recovery-fix-review-f15ae7eb/REPORT.md` SHA256
`3face376b61d9d5fac478e2cf1ee932648b20ddd25bb0b3ae135aab4a2cc9555`
demostró dos variantes de IO Model tras expiración real budget/lease. El timeout
se muestreaba antes del journal; el ACK fresco volvía sin revalidación predispatch.
El fix en ExAgent comprueba Scope después del ACK y de observabilidad, antes de
buffered/stream, y reduce timeout al restante del mismo deadline efectivo. No
renueva reserva, cambia admission counters ni escribe outcome/refund compensatorio.
Los probes confirman fila/revisión e intent unresolved preservados sin Model IO.

Worker fresco recuperó la sesión dañada: artefactos originales inmutables en
`/tmp/opencode/sequence-intent-fix-unique/`; baseline actual, delta acumulado respecto
al owner previo y gates nuevos en `/tmp/opencode/sequence-intent-fix-recovery-unique/`.
Rojos originales reviewer2/2 y owner2/2 siguen conservados; el rojo permanente owner
4/12 incluye ocho fallos Model/timeout y cuatro siblings tool que ya pasaban.
Fallos anteriores de preparación del test tampoco se presentan como defectos runtime.

Verificación recuperada: ambos causales pasan con cero requests y revisión6 intacta;
17regresiones permanentes pasan/12.8s,113focales/93.8s y10probes originales/9.1s,
WA48seed37556 offline, exit0. Primera ejecución combinada22/24 tuvo dos fallos
de harness por omitir copiar legacy_producer; log retenido. Copia completa nueva
resuelve el harness sin cambiar assertions ni path del productor histórico.
Timeout-sampling sibling10ms del review no se usa como gate ni se reinterpreta verde.

Siblings: dispatch stream comparte el nuevo guard; tools conservan el límite real
de tarea async_stream ya existente. Seis holds budget/lease run/resume/stream no
entran en callable; tres ACKs puntuales sí lo hacen. No defecto tool adicional
reproducido ni cambio fuera de ExAgent/test nuevo/docs4. La incertidumbre durable
permanece conservadora; no exactamente-una-vez ni preempción atómica. Gates finales
del cierre: **FULL1733pases/28excluidos/967.8s, exit0**, compile forzado107WA,
formato global y diff exit0. Manifiesto pre-FULL420rutas SHA256
`4e89fc5c57fa0d18678948cfd6c182d826ac53b93e5cac3dd3672b923901b727`:
420/420 intactas tras FULL, incluidos295archivos lib/test. Log FULL SHA256
`f89ecb8202971df36a3569fec332be5c8424f2579cc3153fd1350bc49d41c512`.
Estas notas de cierre son posteriores al FULL; runtime/tests no cambian.
Revisión independiente y aceptación padre pendientes.

## Histórico corrección review P1/P2 —2026-09-28, antes de nueva revisión

Reviewer `/tmp/opencode/sequence-recovery-review-unique/REPORT.md` reprodujo tres
fallos en10probes, dos defectos;410focales existentes y FULL1706 histórico no los
invalidan. Worker nuevo preservó WIP baseline/tar/diff y copió probes cambiando
sólo destinos, sin alterar assertions ni históricos. Rojo7/10 y causal0/3
(siete excluidos, los mismos fallos), luego probes10/10 verdes.

- P1: on_writer retenido601ms/reserva600 permitía IO activa por recalcular
  now+reserved_ms. Writer fija deadline una vez al ACK fresco, con origen común
  elapsed/refund; descriptor y activa comparten el valor. Checks entre owner,
  restauración codec, preparación y preflight frenan nuevas fases/IO agotadas.
  Callbacks ya iniciados terminan bajo su contrato; no preempción/rollback.
  Lease/TTL/autoridad siguen bloqueando ACK tardío; espera anterior al ACK no
  consume el presupuesto activo, conforme al origen Writer existente.
- P2: validación estructural de valores root de Scope antes del CAS conserva errores de run y
  deja fila/presupuesto intactos. Sin endurecer reglas válidas, blanket rescue ni
  refund compensatorio. Incluye rechazo existente del estimador aridad1, sin ejecutar
  el callback ni cambiar la validación genérica de scopes ordinarios. Rojo permanente
  por fila mutada→verde; helper estructural interno compartido, sin formato nuevo.
- Diez regresiones permanentes: cinco opciones root, holds owner/codec/preflight
  activo/preflight sucesor y ACK demorado con presupuesto finito. Se conservan casos
  previos de ACK vencido, autoridades antiguas y finito abandonado/ilimitado recuperable.

Artefactos nuevos `/tmp/opencode/sequence-recovery-fix-f159fe36/REPORT.md`.
Focal amplio446pases/576.5s antes del último ajuste estructural; focal final74pases/
68.4s y probes finales10/10/9.1s más causal3/3/2.6s (siete excluidos, mismos tres
fallos originales) exit0. **Cierre worker2026-09-29:** compile forzado107WA,
formato global y diff exit0; FULL único final1716pases/28excluidos/948.9s exit0,
offline WA48seed37556, build absoluto ROOT. Fuente runtime/tests296/296 intacta
tras FULL. Log FULL SHA256
`5b0ef56f399599abf19ae77660595d2313a537cfd92395d79ca13bfb71df709a`;
identidad expandida pre-FULL SHA256
`0e20280d2804d6ef75d573a824bba557d804afe2435c36820626ea9c67bbf925`.
Docs de cierre posteriores registrados separadamente en manifiesto final del REPORT;
memoria del padre no se atribuye al delta worker. Rojo del setup nuevo39/40 y
todos los rojos originales permanecen conservados, no reinterpretados como pases.
Bugfix experimental sin migración persistida ni publicación;
no aceptación recovery/R6/producción. Requiere review independiente posterior.

## Histórico recuperación experimental —implementada2026-09-28, antes de review

Mandato sellado `tasks/sequence-recovery.md` del run nativo2026-09-28. API pública
resume usa referencia completa exacta, opciones run, recover administrativo explícito
y mismo motor/Writer/Scope. Subsets Frame9 empty/between/input y terminal texto seguro
sin tool-history propia o typed-succeeded actual; completed data-only. Prefijos
completed con tools/retries preservan accounting/precios sin codecs ni callbacks.
Claim/output/input ACK preceden avance; token sólo persistencia, presupuesto finito
abandonado no se reinicia. Singleton7/8/9 conserva sus subsets; activo multileaf
output-retry/batch/tools/raw/uncertain/C7/delegación no admitido.

Artefactos nuevos `/tmp/opencode/sequence-recovery-f15f35af/REPORT.md`, baseline,
manifiestos/diff y logs/exits. Owner checkpoint1:56pases/33.6s; checkpoint2 integrado
410pases/659.7s, WA48seed37556 offline. Incluye tres VM reales (A una vez), CAS dos
claimants, token/ACK, helper atómico cerrado y matriz pública±1. Gates finales abajo
se completan sobre identidad integrada; estas cifras no son aceptación independiente.
No cambios ScopeLedger/Budget/Authority/Record/Transition/Store/Frame/OTel/MCP.

Revisión temporal del owner: FULL previo1701pases/28excluidos/923.3s exit0 se
conserva, pero no certifica el delta posterior. Dos probes rojos demostraron que el
deadline raíz actual no alcanzaba el CAS y que un ACK tardío llegaba a callbacks.
Se liga el deadline al claim y se revalida tiempo tras ACK; focal33pases/51.0s
incluye las dos regresiones, lease ACK tardío, kill ModelB con ownedDOWN/uncertain y
refund terminal único al restringir un lifetime antes ilimitado. **FULL integrado
final1706pases/28excluidos/933.0s,exit0**, offline WA48seed37556; compile forzado107
WA y formato8fuentes exit0.33pruebas nuevas. Revisión independiente pendiente; no
aceptación de recovery/R6 general. El reporte conserva rojos, manifiestos y diff
contra baseline aceptado, sin reinterpretar el FULL previo como gate del delta final.

## Base recibida —2026-09-28, secuencia durable aceptada offline

Aceptado `Composition.run/3`: N pasos con un único Scope/Writer/claim/presupuesto,
mapping de outputs confirmados, prefijo inmutable, ACK antes de IO y refund raíz
sólo final. Ejecución e inspección completed comparten proyección portable data-only;
parciales reflejan únicamente records recibidos y accounting cualificado. Nuevas
raíces9, lifetimes7/8 conservadas y subsets single-leaf9 según sus límites.

| Evidencia recibida | Resultado e identidad |
|---|---|
| Owner final | FULL1673pases/28excluidos/885.2s,exit0; offline WA48seed37556. `/tmp/opencode/sequence-fix-unique/REPORT.md`, SHA256 `1903a2f0d7e438c0de7778c7588d06ccfa72b7ff1dcfe7758b8e88aa09f686e1` |
| Review independiente | Favorable62focales+5probes previos corregidos sólo en copia+2nuevos terminal-loss, sin P1/P2 reproducido. `/tmp/opencode/sequence-fix-review-unique/REPORT.md`, SHA256 `8472c7a03544a8e3c206172e16aa5e17c9ea4cf0d88eab197de7cf3f55e83bd0` |
| Padre | 26/26hashes y sustitución única exacta de assertion cotejados; mismos7probes reejecutados7pases/3.3s/exit0 en `/tmp/opencode/sequence-fix-review-unique/parent-final-seven-f19085.log`. No7casos adicionales |

El probe original conserva4/5,exit2: exigía `invalid_composition_input` donde el
contrato requiere `{:usage_limit_exceeded, :request_limit, 1}` y fase prepare.
Sólo la copia autorizada cambia esa expectativa; originales/logs/hashes intactos.
FULL1651/1652,28excluidos,745.2s,exit2 permanece histórico, no convertido en verde.
La recepción sustituye los pendientes de revisión de esta secuencia, no sus datos
históricos ni los gates futuros. Es posterior a los bytes revisados.

**Límites de ese hito, anteriores a resume:** no restore activo multileaf (rechazo por cardinalidad del
binding incluso con una sola hoja presente), C7 de composiciones, raw/uncertain
recovery, delegación estructural, router/paralelo, R6 general ni SQL/live/producción.
Token8MiB que llega a CAS y recibe record_limit no es commit; receipt+1 inadmisible
rechaza antes del cierre reservado exacto. Completed inspection no reanuda trabajo.
La aceptación SDK MCP es independiente, con perfiles/evidencia en el
[roadmap](roadmap.md); no cualifica composición con MCP ni integra su harness.

## Frame9 corrección causal de dos P2 —2026-09-28, aceptada offline

Writer separa check Scope/cuota/journal/deadline del callback y su input retenido.
Quota1 tras A devuelve `{:usage_limit_exceeded, :request_limit, 1}` con fase prepare,
sin callback/IO B. Deadline antes/después mapping devuelve deadline_exceeded/prepare;
capacidad journal conocida devuelve record_limit. Fallos reales de mapping (incluidos
raise, respuesta inválida y error grande) conservan invalid_composition_input/mapping.

Composition comprueba ambas respuestas Writer y conserva únicamente records ya
recibidos: pérdida durante B puede devolver Acompleted/Bnot_started aunque Store
tenga intentB, con usage partial y sin token. Pending perdido después de recibir el
record conserva ese record; confirmed_record perdido conserva el anterior. Apertura
perdida sin ACK no inventa raíz/prefijo/token. No Store-only reads, refund/cancel/replay
ni excepción global nueva. Caller enlazado normal y cleanup siguen vigentes.

9tests nuevos: deadline previo al mapping, tres fallos callback acotados, muerte
en apertura, mapping/Model B y cada lectura. Barriers reales de Store/Model y debug
sys observador (sin reemplazar respuestas/invariantes), monitores y temporizador de
deadline real. Focal62 pasa; matriz12 real pasó en la ejecución amplia con un fallo
inicial del nuevo hook pending (interceptaba la lectura hoja anterior), corregido
armándolo después de confirmed_record. Histórico fixture de capacidad Writer con
record sintético sigue identificado como tal; no sustituye la matriz CAS real.

Informe recuperable `/tmp/opencode/sequence-fix-unique/REPORT.md` guarda baseline,
causas, comandos, exits y manifiestos. Originales sellados: antes3/5, después4/5.
Único rojo después: assertion línea200 exige invalid_composition_input, incompatible
con el mandato de preservar razón quota exacta; no se alteró el probe. Regresión
permanente exige razón exacta y prepare. Review independiente y probes padre
recibidos según cabecera; R6 general sigue pendiente. FULL final en REPORT.
Gate final integrado:1673pases/28excluidos,885.2s suite/886.3s comando, exit0,
offline WA48seed37556. Compile-forzado107 WA, formato y diff exit0. Evidencia
owner de corrección, separada del FULL1664 histórico y de la review recibida.

## Frame9 cierre de matriz —2026-09-28, incluido en la aceptación acotada

`sequence_capacity_test.exs` añade12casos: tres fronteras × cuatro oráculos.
Cada base viene de Composition.run con un Writer/Scope y Store ETS real. Se
interrumpe antes del commit elegido; el token exacto sigue siendo sólo Store.
La matriz CAS modifica únicamente metadata inerte permitida, conservando binding,
hojas, efectos, autoridad y presupuesto. IntentB confirma esa metadata previamente
por node_checkpoint; no se fabrica evidencia de secuencia. Prefijos auténticos
se reinstalan byte-validados para comparar ramas; no se atribuye restore ejecutable.

| Frontera | Writer límite mínimo / token despachado | JSON exacto + reserva cleanup | Receipts + reserva en bytes exactos |
|---|---:|---:|---:|
| outputA | 70285 / 70285 B | 8361480 + 27128 B | 6 + 4 |
| inputB | 273029 / 273029 B | 8341134 + 47474 B | 7 + 7 |
| intentB | 131102 / 76233 B | 8334352 + 54256 B | 9 + 8 |

Writer exact−1 bloquea output completo/input/intent antes del comando objetivo;
exacto/+1 llegan al Store, sin IO B. OutputA a −1 puede guardar omisión legítima,
que no cuenta como output completo. IntentB está dominado por reserva de outcome,
no por tamaño del token de intent. JSON+cleanup 8388607/8388608B confirma CAS;
8388609B rechaza sin mutación. Token EFT8388607/8388608B atraviesa el gate público
pero CAS rechaza record_limit; EFT8388609B rechaza invalid_checkpoint_token.
El token original confirma y replay no genera IO.

Receipts adicionales son comandos node_checkpoint reales hasta horizontes
1023/1024/1025 incluyendo reservas. InputB los acumula antes de outputA y luego
cierra A legítimamente; no modifica una hoja completed. OutputA consume una
reserva y su +1 predecesor ya es inadmisible: CAS rechaza el checkpoint adicional
y todavía permite el cierre exacto. Cleanup usa actor/operation IDs escapados
máximos512B, conserva presupuesto y replay. Sin intent pendiente termina cancelled;
intentB permanece uncertain con efecto intacto y reservas, sin resultado inventado.
Writer/Scope DOWN se comprueba por monitores y no se ejecutan B/C ni callbacks en
reintentos administrativos.

La única expectativa antigua cambiada, autorizada por el padre, es export run/3;
resume/2 y demás negativas permanecen. No cambios runtime ni formato persistido.
Gates finales/rojos previos/hashes en
`/tmp/opencode/sequence-frame9-boundaries-f1651f1d/REPORT.md`.
Owner focal112pases/166.5s (incluye12nuevos), compile-forzado107 WA y
FULL1664pases/28excluidos/880.9s, exit0, offline WA48seed37556. Formato/diff se
registran con la identidad final en REPORT. FULL1651/1652 histórico permanece.
Review independiente recibida según cabecera; no aceptación R6 general/SQL/live.

## Histórico Frame9 fase2 — API integrada, matriz/review pendientes en ese hito2026-09-28

`Composition.run/3` requiere configuración continuation Writer y deriva identidad
host. Opciones estrictas root_options/step_options/observability/trace_context;
Scope/Writer únicos, cleanup después de capturar resultado/token. Mapping lee
outputs confirmados. Completed inspection y ejecución usan proyección común sin
modelos vivos; contadores ancestrales sin doble suma, rejected/unconfirmed partial.
Errores RunError conservan prefijo, phase/step y output raíz nil. OTel existente
proyecta raíz/hojas/intento sin modelo raíz ni trace context persistido.

Nuevos oráculos: texto/typed/tools y mapping nil/error/oversize/deadline, opciones
e inyección, fallos ACK y retry Store-only, create/claim cleanup, quotas, rejected
usage, C7 ask/omisión final, VM exacta data-only y árbol OTel. Amplía fase1 con
cross-PID tickets/requester death, owner kill afterA/inputB/ModelB y Scope/Writer/
Model DOWN, recovery sin refund, negación y corrupción de evidencia secuencia real.
Recovery de kill se verifica con Transition real y reloj futuro explícito sobre
el Record Store intacto; no se atribuye a un claim posterior ni a SQL.

Fixture `test/fixtures/continuation/frame8-input-sequence.json`: generada por nueve
fuentes históricas intactas del baseline pre-Frame9 de
`/tmp/opencode/sequence-frame9-f16d8c61/baseline.tar.gz`, cargadas en VM privada.
Writer/Scope/Store reales, input0 confirmado, recuperación Store tras lease real;
no relabel/opción pública version. Fuentes/hash/generador/log en el artefacto fase2.
El Writer actual completa esa lifetime conservando8.

Gates owner: compile-forzado107/formato/diff exit0, focal576pases/560.6s (incluye
26API nuevas+4Writer nuevas, no sumarlas otra vez). FULL1651/1652pases,
28excluidos/745.2s,exit2: único fallo `composition_definition_test.exs:40` exige
que `Composition.run/3` no exista. Ese archivo queda fuera de allowlist; se solicita
ampliación causal, sin editarlo ni convertir ese gate en verde. Logs/manifiestos en
`/tmp/opencode/sequence-frame9-phase2-f168b0f9/REPORT.md`. La matriz exacta−1/exacto/+1
de outputA/inputB/intentB/token (incluido espacio cleanup/receipts) sigue pendiente:
los tests ACK/capacidad históricos no se reatribuyen como ese oráculo. Revisión
fresca obligatoria; no cierre Frame9/R6 ni autorización SQL/cloud/live/publicación.

## Histórico Frame9 fase1 — vertical durable integrada2026-09-28

Se ejecuta A→B→C real con <code>ExAgent.run_composition_step/4</code>, un Writer/Scope/claim
y journal CAS. Productor9, Record, transiciones, accounting/reservas y restore
data-only integrados. Tickets PID/revisión/índice, prefijo completado inmutable,
mapping desde resultados confirmados, ACK antes de IO, between_steps sin refund
y cierre final desde claim raíz. Nuevas raíces9; lifetimes7/8 sin relabel.

La matriz nueva incluye texto/tools/typed/retries con callID repetido; ACK before/
after outputA/inputB/intentB y retry token sóloStore; mapping/error/cuota/omisiónA;
ask fail-closed, node_id/corrupción CAS, terminalidad/receipt replay; VM nueva para
intermedio rechazado y completed data-only. Amplía las regresiones previas de los
subsets singleton. Gate/identidad/pendientes exactos recuperables en
`/tmp/opencode/sequence-frame9-f16bf3ff/REPORT.md`. Sin aceptación Frame9/R6 ni FULL;
API pública/proyección/tracing se integran en fase2 arriba.

## Histórico Frame9 fase1 — hito preparatorio parcial2026-09-28

**Fase1 incompleta, sin aceptación del secuenciador.** Runtime modificado sólo
en Frame y OutputResolution. Frame valida9 explícitamente: prefijo exacto del
binding, cursor empty/running/between_steps/completed, refs/índices/input default,
nil portable frente a omisión, nodos/authority exactos y ausencia de IO raíz.
La evidencia tools/output se particiona por hoja, manteniendo graph/coverage
global, request IDs host únicos y call IDs reutilizables. Los lectores históricos
y el productor8 siguen; Record no admite9 todavía. No nuevo modo/API ni migración.

Pruebas nuevas:
- `sequence_frame9_validation_test.exs`:24 casos estructurales con Scope real y
  fixtures nuevas9 construidas para esa frontera; no son records ejecutables ni
  fixtures históricas relabeladas. Prefijos, nil/omitted, corrupción de índices,
  enlaces/input/refs, autoridad/nodos y huérfanos output.
- `sequence_evidence_partition_test.exs`:7 casos con hojas singleton ejecutadas
  realmente mediante Writer/Store/loop, tools y output tipado/textual, efectos
  observados y records originales decode-validados. Proyecta sus diarios para
  comprobar la partición y corrupción/huérfanos; comprueba también que la proyección
  no es un Record válido. No es A→B→C bajo un único Writer/Scope.

Gates owner:31nuevos verdes y focal523pases/537.6s WA48seed37556,exit0, incluyendo
singleleaf/input/text/output-retry/output-success/tool-restore/batch y productor8.
Los rojos previos fueron fixtures de prueba: faltaba codec requerido, límite
tool_return_bytes nil y snapshots con distintas claves al proyectar evidencia.
Se corrigieron los datos de prueba sin cambiar guards ni assertions contractuales.
Logs, baseline/delta/manifiestos y checks finales:
`/tmp/opencode/sequence-frame9-f16d8c61/REPORT.md`. No FULL, SQL ni live.

**Pendiente exacto fase1:** productor/lifetime9 y ramas accounting/reservas,
Record/evidence9 integrado, Transition append-only/node_id/terminalidad,
Writer descriptor/ticket/revisión/attach/finish, mapping de datos confirmados,
budget/lease y refund raíz único, guards C7/delegación, restore singleleaf9,
rechazo activo N>1 por binding y completed multileaf data-only; matriz real
A→B→C, CAS/ACK/tokens, límites exactos, carreras/owner death y VM nueva.
No bloqueo causal ni ampliación de allowlist demostrados. La entrega conserva
este hito probado por límite de ejecución/contexto del worker; no sustituye el
mandato pendiente. Fase2 Composition.run/proyección/cleanup/tracing/full sigue
posterior a completar/revisar fase1, sin cambiar el contrato aprobado.

## Frame8 final/control restore — aceptado offline acotado2026-09-28

Padre acepta single-leaf Frame8 final/control/prefix tras review fresca favorable:
50casos distintos (43focales+3probes independientes+4adyacentes), sin P1/P2
reproducible. Informe `/tmp/opencode/r6-tools-review-fresh-928a/REPORT.md`, SHA
`326c054b6cbd08c7d42db6df699dcad2354f7058519724b1a761ca5e93ae2439`.
Padre cotejó source12/12 y reejecutó3probes intactos WA48seed37556, exit0/9.3s;
`parent-probes.log/.exit` en ese directorio y JSON nuevos timestamped conservan
VM nueva/counters6, primer fatal pese a reset y claim ACK/recovery. Son ejecuciones
separadas de los50 de review y de los gates owner inferiores; no50+3 casos distintos.
Owner `/tmp/opencode/r6-tools-f17600f0/REPORT.md`, SHA
`74024782c03dd74401d9d9f371ee41f8b185a5e2d9d813c193ec2726d2a9c71a`:
FULL1568/28/716.8s, focal261 (99nuevos), compile107 y MCP37 son evidencia owner.
Recepción sólo documental posterior a source12 revisado, sin nueva decisión runtime
ni formato. No restore general/raw/uncertain/no-control/rejected/omitted/legacy7tools,
approval-retryplans/delegación/A→B, R6 completo ni cualificación SQL/cloud/live.

**Gate final owner:** corrección MCP test-only autorizada: oracle admite normal/killed
con PID/ref exactos, dos regresiones deterministas transport-first/guardian-first,
plazos250/2000 intactos y cleanup worker/guardian. Focal MCP+probes originales37pases,
1.9s,formato/diff exit0. FULL nuevo1568pases/28excluidos,716.8s,WA48seed37556,
offline exit0, identidad405archivos
SHAfb4bb3b5cff4ae7691c269655073db61770ab940cfb4ec4fa9c88e08bc0d53b3.
Runtime R6/MCP sin cambios en ese seguimiento test-only. Review y aceptación acotada
recibidas arriba. Reportes y FULL fallidos inferiores preservados como historia;
sus pendientes describen el momento de cada entrega, no el estado vigente.

**Seguimiento anterior de gates:** autorizado por padre el único test obsoleto restante,
actualizado a success data-only con igualdad de historia/parts/usage/Scope, calls1,
requests2,coste6,codec una vez y no_new_io/ningún changeset. Vecinos intactos; focal
4/4,6.3s,formato/diff exit0. Runtime byte-idéntico a la entrega anterior. Nuevo FULL
en manifiesto405/SHA94c1c8a3710146fbf099a127fae468cf4b583869755bff177d5e953b9bc59795:
1565/1566pases,28excluidos,719.8s,exit2 WA48seed37556. Fallo distinto en
MCP `streamable_http_test.exs:643/653`: espera DOWN:killed, recibe normal con socket
cerrado. Fuente MCP intacta. Probe externo2pases con HTTP real fuerza cada orden
de los dos timers: ambos cierran socket, devuelven timeout y rechazan late-success.
El original aislado da2pases/31excluidos; eso no convierte el FULL en verde ni autoriza
editarlo. Se devuelve diagnóstico al padre; sigue pendiente FULL verde/review fresca.
REPORT y ambos FULL fallidos se conservan íntegros. La evidencia inferior es histórica.

Mandato aprobado `next-r6-frame8.md`. Runtime sólo CompositionRestore/ExAgent;
ToolEvidence se reutiliza intacto. Clasifica cursor/request actual antes de output
histórico; consume prefijos continuables y batch final/resuelto. Reproduce únicamente
el reductor puro desde contadores previos, contrasta postcontador y rehidrata
tool_calls del prefijo; añade el actual una vez. No ejecuta maquinaria histórica
de tools, settle/resolution ni contribuciones Scope. Primer fatal portable conserva
precedencia sobre success posterior/settle_error; no crea excepción ni transición
terminal. Selección efímera protege errores de preparación/retención hasta append.
Host binding, codec, schema/fingerprint y Model.validate_resume siguen vigentes;
«sin IO histórico» no significa ausencia de toda reconstrucción host. Fatal tipado
todavía requiere configuración host compatible; un fallo de preflight deja los bytes
confirmados intactos y puede devolver el error de preparación antes del fatal.

Matriz permanente `composition_tool_restore_test.exs`, fixture/VM exclusivas:

| Frontera | Oráculo |
|---|---|
| Consumo | Texto/prefijo, output success/retry, historical output→current batch, siblings output no contados, interrupciones consecutivas |
| Control | Retry→success, success→retry, exhaustion→success, dos fatales, schema/request-local y callID reutilizado, previos+actual sin doble reducción; orden finish inverso con barreras |
| Fatal/settle | Fatal text/typed conserva returns; seam Writer real confirma settle_error y precedencia del primer fatal mediante CAS, separado del loop ordinario |
| Hooks | Dos capabilities antes/después Model nuevo, primera intenta mutar runtime-owned6, segunda observa contadores correctos; cero hooks/callables históricos |
| Accounting | Nil/unknown/zero/partial con enteros/coste; Scope y proyecciones ancestrales exactos, estimadores históricos explosivos, returns sin usage resucitada |
| VM nueva | Cinco OS/BEAM desde JSON: texto/batch/success/retry/fatal, mapping/tool/model históricos trap, partial/coste subtotal conservados |
| Autoridad | 16 floors root/leaf×original/current×singular/plural×deny/ask de NUEVA tool; quota0/1/2 cierre/fatal/drive, original root/leaf agotado, maxsteps y deadline actuales |
| CAS | Dos claimants en barrera con un ganador; obs/op/control/counters/limits/hash/history corruptos rechazan decode y CAS con fila intacta, replay/stale; límite coherentemente reescrito puede decodificar pero CAS impide mutación |
| ACK/crash | Claim/nextintent/step_output before/after, token JSON sólo Store; kill antes/después intent y durante Model nuevo, Writer/Scope/Model DOWN, recovery explícito e incertidumbre |
| Retención | Historia append y payload output exacto±1; token8MiB, receipts y JSON+cleanup exacto±1 derivados de comandos reales; J nuevo intent68250/68249, token14409 |
| Guards | Raw/no control/rejected/legacy7, actual unavailable Model y incertidumbre/omisión antes de callbacks; selección retirada permite stubs de NUEVA response fallida |

`matrix-complete-2`96pases WA48seed37556,203.6s,exit0; tres negativos añadidos
después llevan la matriz a99. Gate final261pases/266.1s exit0, compile forzado107,
formato global y diff-check exit0. FULL nuevo1565/1566pases/28excluidos,717.3s,
WA48seed37556,exit2: sólo expectativa obsoleta output_retry_restore1374/1381, fuera
allowlist y todavía intacta. Los99nuevos pasan en el FULL. El bloqueo productor780/801
anterior fue autorizado y actualizado acotadamente. Manifiesto FULL405archivos
SHA170a594e101565e186926a39d95dd2a2315c7d52ea4f507c4c1b1b525ea5fee1;
producto/tests sin cambios después. FULL/review no aceptados, requiere autorización
del test restante y nuevo gate tras corregirlo; registros/fallos históricos en REPORT.
No migración,
delegación/A→B/SQL/live/publicación ni aceptación R6.

## Productor Frame8 accounting/control — aceptado offline2026-09-28

Review independiente favorable95 casos (55productor+33contrato+7probes), sin P1/P2
en alcance; padre7probes intactos WA48seed37556 exit0,2.5s, sólo destinos JSON nuevos.
Informe `/tmp/opencode/frame8-review-20260928-fresh/REPORT.md`
SHA49eb910f4fe1e749f7c34772b27ca248acd17d4ef3ac86fc7355c6cfa41c7ee0;
source19/19 cotejado. FULL1409/28 inferior pertenece al owner, no al reviewer.
La integración posterior OTel no cambia runtime Frame8; gates combinados en roadmap.

Nuevas raíces escriben8; lifetimes7 mantienen7. Scope recibe input observado antes
de retención, prepara y valida observación+operación y conserva recibos RAM acotados
por identidad; duplicado devuelve el recibo, cambio de input rechaza conflicto.
Writer confirma raw+observación+Scope antes ACK. Negativa de usage no aplica external,
conserva marcador portable y cualifica partial en progreso/RunError/snapshot durable;
Scope2 sólo contiene operaciones aceptadas. Final no vuelve a contribuir.

`tool_resolution` confirma controles ordenados postsettle y contadores derivados
antes de fail/pause/drive. Comparte reductor puro con el loop; ningún efecto adicional.
Frame/Record validan ambas direcciones y transiciones mantienen evidencia inmutable.
Schema histórico liga a límites del batch propio. Reserva antes de tareas considera
calls aún sin intent, resultados concurrentes, observaciones/operaciones/copias,
control/error portable, crecimiento de contadores y receipts/cleanup por codec real.
La reserva valida una pareja current/control futura mediante Transition.apply sin
persistir datos sintéticos. El margen prebatch evita repetir esa proyección antes
del callable: begin mide crecimiento real de argumentos; raw/final/predispatch
revalidan y recalculan margen preservando los siblings pendientes.

Matriz permanente `tool_evidence_producer_test.exs` y regresiones existentes:

| Criterio | Evidencia |
|---|---|
| Accounting cualificado | Writer8 auténtico: nil/unknown/zero/partial con enteros/coste; proyecciones ancestor sin precio aportado ni estimator externo; recibos iguales/conflicto |
| Rechazo previo a aplicación | Invalid/omitted/nonportable/oversized/expansión al cualificar; marker durable, no external op, snapshot partial y rechazo de falsa completitud, sin after-hook del retorno rechazado ni siguiente Model |
| Concurrencia/control | Sibling aceptado retenido, quiescencia; retry-success/success-retry/exhaustion-success con orden de terminación invertido, hookfatal y timeout tras raw succeeded; primer fatal no se borra por success |
| CAS/decode | Borrar obs o obs+op, usage/quality/source/terminal/complete/ancestors/hash/control/counter; límites inmutables por CAS; rechazo conserva fila, comando íntegro/replay y revisión obsoleta |
| Fronteras de ACK | Antes/después raw/final/control/nextintent; cada fila decodifica y no repite efecto, raw ACK perdido no habilita hook |
| Capacidad | Reserva batch rechaza antes de IO concurrente; receipts de calls sin intent+control; JSON+cleanup exacto/-1/+1 y1024 receipts en raw/final/control; token real exacto/-1/+1 vía retry_checkpoint/CAS, replay íntegro |
| Identidad/schema | CallID reutilizado entre requests con schema y max_retries distintos; cada historia usa su propio batch |
| Crash/VM | Owner kill después raw termina Writer/Scope y retiene raw; timeout sin raw no fabrica observación/control; decode de Writer8 en BEAM nueva |
| Compatibilidad/guards | Bytes históricos7 copiados sin modificación, transición legacy y resume textual Writer conserva7; negativos tools tras recovery8; suites input/text/output-chain/VM existentes generan8 auténtico |
| Rojo causal | Desactivar sólo forwarding de input produce nil frente a usage en fixture8 real; restaurado. No es relabel ni cierre de los rojos legacy ambiguos |

El bloqueo inicial del discriminador fue resuelto por autorización explícita del
padre: CompositionRestore sólo cambió7→7/8; guards funcionales intactos. Completed
sigue data-only. No restore tools/prefijos/batch, planes reautorizados, pausa/delegación,
A→B, SQL/live, publicación o aceptación R6. Legacy no adquiere evidencia inventada.

Evidencia recuperable: `/tmp/opencode/tool-evidence-f180bea3/REPORT.md`; baseline331
hashes/status/diff, fuentes/fixtures y comandos/exits. Primer FULL1397/1400/28 exit2
(499.1s): dos expectativas7 de writer actual y un glob de fixtures antiguas que
incluía las copias7 nuevas; corregidos sin alterar originales. Gates finales owner:
matriz55/55, focal combinado88pases, compile forzado102/formato/diff exit0;
FULL1409pases/28excluidos WA48seed37556 exit0 (508.2s), `full-owner.log/exit`.
El FULL previo `full-complete`1408/1409 expuso latencia en test de30ms por recalcular
reservas antes del callable; corregido con margen prebatch, sin ampliar timeout.
Revisión independiente recibida según cabecera; no aceptación R6 completa.

## Contadores runtime-owned entre capabilities Model — aceptados offline2026-09-28

Review fresca124focales+8probes, padre8probes intactos WA48seed37556 exit0; delta
runtime leído, manifiesto15/15 cotejado. Informe
`/tmp/opencode/runtime-counters-review-f1815c1c/REPORT.md`
SHA68b62e7780418bb22870da58dc875ce5a5e27ace75b92369743b1e4ef80a4f1a.
Recepción posterior al manifiesto: sólo productor, no integridad legacy ni R6 completo.

Seis campos observables protegidos después de CADA callback before/after Model:
tool_retries, output_retries_used, run_step, tool_calls, max_steps y
agent.output_retries. Implementación sólo en Capabilities: restaura valores de
entrada Run mediante actualizaciones estrictas de campos existentes, antes del
siguiente hook. No congela agent ni seleccionables, no inventa defaults en retornos
inválidos; mapas genéricos mantienen su comportamiento. Contrato y migración major
pendiente en Capability/ADR8.38/changelog, escritos antes del fix.

| Criterio | Test permanente / evidencia owner |
|---|---|
| before/after×6 campos×módulo/struct | runtime_counters_test:24 casos; segunda capability compara todos los valores confirmados durante retry real, siguiente request y reset success |
| Rojo causal | Cuatro casos `causal`: before/after×reset/contaminación tool_retries, fallan antes del fix porque la segunda capability recibe datos falsos; verdes tras fix |
| Límites agotados | Ocho casos before/after: tool retry, output used/límite, run_step/max_steps, tool_calls; número de requests/efectos e inexistencia de IO extra |
| Compatibilidad/errores | Mapas genéricos sin campos nuevos; módulos/structs; Model/settings/agent/inventory/proyección/respuesta válidos; max_retries seleccionado7; nil/mapa incompleto/agent inválido/campo borrado/excepción rechazan sin siguiente hook ni efecto |
| Persistencia real | runtime_counters_persistence_test:4 casos direct/composition×before/after; Writer/ETS/CAS intactos, intent cargado durante Model IO, snapshots y decode de cada fila, retries/reset/limits y Scope requests/tools exactos, refs/autoridad conservadas |
| Gates owner | Compile forzado101, formato0; focal371pases WA48seed37556 exit0 (254.4s). FULL1354pases/28excluidos,482.0s WA48seed37556 exit0; aceptación independiente según cabecera |

Informe temprano y evidencia `/tmp/opencode/runtime-counters-f182db46/REPORT.md`;
baseline379archivos/hash/status/diff y originales preservados. Matriz44pases antes
del focal integrado; errores de fixture separados de los cuatro rojos causales.
No nueva evidencia durable: el persistido legacy retry sigue ambiguo, usage sigue
sin observación independiente por call. No se afirma cerrado ningún rojo de
manipulación CAS retry/usage. Frame/Writer/Scope/Message/Outcome y guards intactos;
no nueva frontera restore, SQL/live, aceptación R6, versión ni publicación.

## Integridad histórica de batches — aceptada offline2026-09-28

Review independiente141focales+4adversariales, padre4probes intactos WA48seed37556
exit0; manifiesto13/13 y delta cotejados. Informe
`/tmp/opencode/final-tools-review-fresh-20260928/REPORT.md`
SHA54643917143e985b07d8c2ad712890c627a354b48cfb5c456646e73e81b7d301.
Sólo cardinalidad batch: usage y retry siguen rojos conocidos, sin restore habilitado.

Delta acotado sólo Frame: el mapa de batches de hoja debe coincidir exactamente
con requests confirmadas cuyas calls ya se consumieron y el batch actual admitido.
Requests con output_resolution (incluidos siblings virtuales) no admiten batch.
La evidencia usa run/request/posición de historia; callID reutilizado entre requests
y orden de batches del ledger no cambian el resultado. ScopeLedger sigue validando
counts/ancestros y la coherencia root/leaf. Decode y CAS comparten el chequeo.

**Bloqueo usage descubierto al implementar:** ToolReturn.usage es explícitamente
runtime-only (`message.ex`), no aparece en historial ni request_data y no participa
en Outcome.raw_hash/result_hash. La afirmación contraria del diagnóstico anterior
queda refutada por bytes reales y un test permanente de codificación/hash idénticos
para nil y7/11. El snapshot tiene un agregado, no el vínculo por call requerido.
No hay validación exacta de contribuciones contra evidencia independiente disponible
en el formato actual. No se inventa operación/importe ni se introduce otro contrato.
Usage y tool_retries permanecen pendientes por causas distintas; guards intactos.

Matriz `composition_batch_integrity_test.exs` (23 casos en el focal):

| Frontera | Evidencia |
|---|---|
| Drop/reduce histórico coherente | Decode y CAS auténtico outcome Model/step_output/output_resolution; root/leaf counts coordinados, effects intactos |
| Atomicidad/ACK | Rechazo conserva fila; comando intacto confirma; replay de receipt confirma y revisión obsoleta con operation nueva da conflict |
| Multiplicidad/identidad | Dos batches, dos calls, mismo nombre y callIDs reutilizados en requests distintas; usage completo/parcial/nil |
| Positivos | Retry callable, validación predispatch, denied, output virtual sin batch; Record.decode de filas Writer reales |
| Exclusiones | Hash nil/usage idéntico demuestra bloqueo; no promesa de uso inferido, raw/legacy/planes/restore nuevo |

Artefactos `/tmp/opencode/final-tools-fix-f184e84d/`: baseline WIP/hashes/diff,
probes copiados con único cambio de destino (originales/manifiesto intactos),
red-before0/3 exit2; red-after1/3 exit2 (usage/retry pendientes),38probes
observacionales exit0; compile forzado101 y focal357/0 WA48 seed37556 exit0.
FULL1310pases/28excluidos,478.5s WA48 seed37556 exit0; formato/diff exit0.
Red-final1/3 pasa,38excluidos exit2: sólo batch corregido, usage/retry siguen rojos.
Aceptación independiente sólo batch según cabecera; no aceptación funcional de
restore. ROOT liberado; sólo BEAM ajenos3339/2963360/4019033 observados.

## Cadena Model con atestación actual — aceptada offline2026-09-28

Review fresca208focales+7probes independientes, padre7probes intactos WA48seed37556
exit0; delta runtime leído y manifiesto17/17 cotejado. Informe
`/tmp/opencode/output-chain-review-f186a998/REPORT.md`
SHA81fb2bb19acabcde880cbb6912ca4d9dcb45440ff7913bc005e5d500db7981ed.
Sin P1/P2 concreto en alcance. Recepción posterior a los bytes revisados; no R6 general.

Unidad aprobada en ADR8.38 y ficha leaf-restore-next. Runtime únicamente
`CompositionRestore`: después de Record.validate clasifica cadena confirmada Model
y selecciona por `leaf.model_request_id`, sin singleton/última entrada ni límite N.
No duplica la validación histórica ni modifica Frame/Writer/OutputResolution/Scope/
Authority/Record/ExAgent. Success consume datos, retry usa los consumidores ya
aceptados y admite sólo operaciones nuevas; contador incluye Retry sin call.
Los descriptores históricos se ligan a su RequestData, no al host actual.

Matriz permanente ampliada `composition_output_retry_restore_test.exs`:134/0 owner
(58 previos conservados con sólo negativos contradictorios convertidos a oráculos
positivos;76 casos adicionales). Cinco rojos causales antes del runtime; ningún
negativo de ausencia de atestación/incertidumbre ni probe externo se relajó.

| Criterio | Oráculo ejecutado en la matriz |
|---|---|
| N sin cota artificial, historia mixta | Cuatro respuestas reales, tres retries consumidos (uno sin call), tres atestaciones; mismo CallID en requests distintas, siblings inertes, descriptores históricos distintos |
| Selección/consumo | Current retry→request5; current success→mapa sin request/Ecto/reflexión (SchemaTrap); args históricos trap; configuración retry una vez |
| Múltiples interrupciones | Retry4→retry5→success6, recovery explícito y token JSON/replay entre cortes; completed sin codec/IO |
| VM nueva | JSON real en OS/BEAM nuevo para retry4 y success4; callbacks históricos0, reflexión1/0; contadores5/4 y coste parcial conservado con subtotal, nunca convertido a coste completo |
| CAS y callbacks | Barrera de dos resumers en cadena y primera respuesta: un ganador prepara configuración; refs/perfil preclaim, schema/Model binding y validate_resume postclaim; excepción limpia Writer/Scope |
| ACK y crash | Before/after claim, intent, outcome, resolution y step_output también en cadena; token sólo Store. Kill preintent vuelve a atestación sin refund; kill en IO deja uncertain y procesos DOWN |
| Contadores/precedencias | Original/current retry/steps/request requerido−1/exacto/+1; raíz request4/5/6; agotamiento→maxsteps→admisión. Success con límites actuales inferiores consume sin nueva admisión |
| Autoridad/ledger | Pisos root/leaf×singular/plural×current/original niegan tool NUEVA tras cadena; operaciones históricas exactas conservadas, estimadores nuevos sólo para operación nueva; VM conserva calidad parcial |
| Corrupción CAS/decode | Borrado/duplicado/hash/decisión/request de atestación histórica, reorden historia, contador±1, modelo y ledger. Comandos reales rechazan, fila intacta; token original positivo confirma |
| Límites exactos | Consumo historia exacto/−1; payload success exacto±1; token8MiB/+1; receipts y JSON+cleanup exacto/+1 sobre intent nuevo real. J chain82506/82505 con token32244 (base68252/68251, token14481) |
| Omisiones | Resultado validado no portable bloquea preclaim; resultado portable grande con copia terminal omitida conserva atestación y error completed |
| Exclusiones auténticas | Outcome actual sin atestación con entradas históricas; textoN sin atestación; tool batch terminado; raw tool outcome; Model confirmado state_available=false; intent uncertain. Perfil native y refs incompatibles rechazan |
| Base y fronteras restantes | Input0/text1/success1/retry1/completed, evidencia/Scope/retención/legacy y guards de aprobación/delegación/A→B se verifican en focal/FULL separados; no se habilitan |

Artefactos recuperables `/tmp/opencode/output-chain-20260928-f18b65/`: baseline
tar/hashes/status/diff, rojo previo, logs/comandos/exits e informe. Los rojos
posteriores de fixtures se conservan: coste parcial mal supuesto completo; encoder
definido tras consolidación; booleano de tag nil en codec. Corregidos sin cambiar
runtime ni guards. Gates owner: compile forzado101, formato, matriz134/0 (179.8s),
focal578/0 (441.2s) y FULL1287pases/28excluidos (468.9s), todos exit0; offline con
prefijo environment, MIX_BUILD_PATH absoluto, WA48 seed37556. Las advertencias
operacionales de pruebas negativas y deprecación upstream de Req no son fallos de
estos gates. Aceptación independiente según cabecera, sin R6 general/
SQL/live/publicación. Sólo ocho archivos cambian frente al baseline: clasificador,
matriz/fixture/VM y los cuatro documentos de contrato del owner.

## Primera atestación output retry — aceptada offline2026-09-28

Revisión fresca167focales+5probes independientes, padre5probes intactos, WA48
seed37556 exit0; delta leído y hashes11/11 cotejados. Sin P1/P2 concreto en alcance.
Informe `/tmp/opencode/output-retry-review-f18c726f/REPORT.md`
SHA97f98a0148ff5956d7d59699975c9d5e27a778888428057b7a3444b40e087cd7.
Recepción documental posterior al manifiesto revisado, no cierre R6/SQL/live.

2026-09-28, alcance aprobado de ADR8.38 y ficha output-retry. Misma frontera exacta
response1 que success, con decision retry y cero batches/tools/plans previos. El
ganador CAS prepara output HOST una vez, después de codec/binding; compara descriptor
exacto/fingerprint, conserva Model.validate_resume y cachea sólo en Run efímero.
No revalida args1 ni usa módulos seleccionados desde JSON. Las referencias/perfil
se comprueban data-only antes de claim. Callbacks puros pueden repetirse en otro
intento; no se detecta un cambio semántico host que mantenga schema y versiones.

retry_or_fail consume Retry y siblings exactos, usando Retry.content para agotamiento.
append_returns retira la protección fail sólo cuando caben las partes; errores antes
conservan historia confirmada. drive admite un request ID nuevo, sin plan/idempotency
key anterior. Writer existente confirma consumo/contador con begin_effect2; ACK sólo
persiste datos. No checkpoint intermedio ni cambios Frame/Writer/Record/Scope/Authority.

Matriz `test/exagent/composition_output_retry_restore_test.exs`:58 casos, verde owner.

| Criterio | Evidencia causal |
|---|---|
| Retry real→request2→success | Rojo unsupported antes de runtime; Ecto real, args1 trap, vacío una vez, args2 normal |
| VM nueva JSON | `composition_output_retry_vm.exs`, configuración host nueva, requests2/coste8, historical0/reflection1/new_validation1 |
| Siblings | Output extra y función intercalados, partes exactas atestadas, cero efecto sibling |
| CAS/configuración | Barrera de dos claimants; una configuración/codec/IO; schema cambiado postclaim, refs/perfil preclaim |
| Model/codec | Binding host y postcodec, load fallido, validate_resume rechaza; no nuevas admisiones |
| Consumo/futuro | Inyección caller ignorada, hook de response2 genera stubs normales; args2 trap; loop vivo retry2→request3 |
| ACK | Claim/begin_effect2/outcome2/resolution2/step_output before/after, token JSON/replay; resolution1 before/after |
| Crash/restore | Kill real preintent y durante Model2 con intent durable, monitores writer/scope/worker DOWN, recovery administrativo; intent sin outcome uncertain; response2/retry2/success2 rechazados después recovery |
| Límites/autoridad | Original/current retry0/1, steps1/2, requests1/2 raíz/hoja, budget, deadline;8floors root/leaf×singular/plural×current/original niegan tool NUEVA |
| Ledger | Histórico root7/leaf3 intacto, operación nueva root11/leaf5, requests2/coste8 |
| Retención | Historia con partes exacta/-1; J request2 calculado por admisión real68252/68251, token14481; token exacto/+1 real, receipts y JSON+cleanup exactos/+1 sobre proyección request2 |
| Corrupción/limpieza | Rechazo preclaim de identidad/partes/hash/posición/ledger corruptos; schema exception y kill con procesos observados terminados |

Negativos antiguos success/text ahora prueban request_limit1 original, conservando
cero Model adicional; falta atestación auténtica sigue rechazando. Probes externos
y fixtures legacy intactos. Informe temprano, baseline tar/hashes, rojos y gates en
`/tmp/opencode/output-retry-20260928-f18f527a/REPORT.md`. Owner: compile101, focal297/0
(antes de los dos últimos oráculos), matriz final58/0 y FULL1211pases/28excluidos,
363.8s, WA48 seed37556,exit0; formato y diff-check verdes. Evidencia owner separada
de la aceptación independiente de cabecera.
Completed/tokens siguen data-only; no
restore posterior general, A→B, batches previos, SQL/live ni cierre R6.

## Output succeeded portable — aceptado offline2026-09-28

Revisión fresca `ses_f1902e4aaffe6ItlzRTTJ7mWsu`:109focales+5probes exit0,
sin P1/P2 concreto en alcance; padre5probes intactos exit0, delta leído y hashes11/11
cotejados. Informe `/tmp/opencode/output-success-review-astra-20260928/REPORT.md`
SHA5b27e6e620f7e6409d02dca0dfb0244ab25f161a8f78df831a3bde2a2d7aca1b.
Esta recepción documental es posterior a los bytes revisados; no cierra R6.

Unidad acotada sobre la base textual aceptada abajo. Frame7 ready/root+hoja
running/response1, un Model confirmed/succeeded/state_available, una operación,
cero tool effects/batches/retries/approvals/plans y una atestación output1 succeeded
del request actual. Record.validate precede clasificación; binding/output_ref
versionados y perfil tipado/tool preceden claim/callbacks. Siblings misma response
permitidos, partes completas/exactas/en orden atestado, una vez.

ExAgent y CompositionRestore añaden selección efímera interna; OutputResolution
convierte descriptor a params exactos data-only/tools inertes. No módulo desde JSON,
Ecto/reflexión ni output_config en ninguna de las dos preparaciones de consumo.
Se conservan Model.validate_resume/fingerprint después claim, codecs y preparación
tools host sólo ganador. El límite declarativo permanece: mismo versionado no
detecta cambio semántico de código/schema; no nueva API de descriptor.

Consumo por append_returns/succeed/Writer.finish existentes, sin nuevo request,
after_model/mapping/tools/siblings ni output_resolution. Resultado mapa portable,
no struct rehidratado; ejecución viva mantiene tipo. Atestación omitida bloquea
preclaim con composition_output_omitted. Copia terminal omitida conserva marker
medido/error existente y completed no rescata la copia atestada. History exacto-1
reprodujo un throw secundario de fail/2 al fabricar stubs: sólo esta selección
conserva historia confirmada en el error, sin returns contradictorios. Ningún
cambio a Frame/Writer/Authority/Scope/Record, formato, token, ledger o admisión.

Matriz permanente `composition_output_success_restore_test.exs` (28 casos):

| Criterio | Oráculo |
|---|---|
| Validación viva real y consumo sin Ecto | Fixture Ecto con contador changeset; test primero rojo por boundary; consumo mapa, traps separados changeset/schema |
| JSON/VM nueva | `composition_output_success_vm.exs`: proceso OS/BEAM nuevo con bytes reales, recovery explícito, schema/changeset/Model/hook/mapping/tool traps |
| Siblings y partes exactas | Dos outputs + dos funciones intercaladas; primera elegida, cuatro returns exactos, ledger/authority/atestación idénticos |
| Dos resumers | Ambos en barrera CAS; un codec/registro/cierre; perdedor cero callbacks |
| ACKs | Resolución antes/tras commit; ausente rechaza, token exacto sólo persiste. step_output before/after, token JSON y replay sin duplicar returns |
| Binding y corrupción | Todas refs versionadas, text/native; request/run/call/descriptor/parts/hash/posición/duplicados y resultado terminal CAS+decode; retry auténtico rechaza |
| Omisiones | Resultado Ecto real sin encoder bloquea preclaim; portable grande con copia terminal omitida conserva error/marker y consulta completed omitida |
| Contabilidad | root7/leaf3, estimadores nuevos explosivos, requests1/tokens3+2 y Scope idéntico; límites actuales0 no vuelven a debitar historia |
| Retención/tiempo | History con returns/payload exacto y un byte menos; checkpoint estrecho; receipts1019/1020 y JSON+cleanup8MiB/+1; deadline y budget crash |
| Regresiones | Input0/texto/completed/evidencia/retención/record/tree y probes Frame7/floors/codec originales intactos en focal197/0 |

El test textual previo de success sin Jason encoder ahora exige el nuevo error
explícito composition_output_omitted; retry conserva unsupported. No se cambian
probes externos. Los rojos supplemental6→7 históricos no se presentan como verdes.
Resultado arbitrario reescrito junto con toda su evidencia no se autentica por
estos hashes: la integridad del Store y la inmutabilidad CAS siguen siendo el
contrato existente, no se añade firma criptográfica ni evidencia externa.

Logs/freeze/delta en `/tmp/opencode/output-success-20260928-061414/REPORT.md`.
Prefijo aislado environment, EXAGENT_OFFLINE=1 MIX_ENV=test y MIX_BUILD_PATH absoluto.
Owner: focal197/0 WA48 seed37556,114.5s,exit0; compile100/formato0 y FULL recuperado
1153pases/28excluidos,290.2s,exit0. SHA full-recovery.log
8634f8cc3eadaef980f4ddcde9877101b9d9d61d5accaa2ef7f6a49fc9fdd970.
El FULL anterior interrumpido conserva tres fallos boundary de causa no establecida;
boundary-recovery7/7 y FULL verde no demuestran su causa. Sin serializar ni relajar
guards/timeouts. Aceptación independiente según cabecera, no SQL/live/retry/raw/
general/A→B ni cierre R6.

### Histórico de la base paso único —2026-09-28

**Paso único integrado aceptado offline**, incluidos
constructor/binding, raíz estructural, Writer/CAS, evidencia Frame5/6 y reservas.
Restore input0, primera respuesta textual confirmada y completed data-only aceptados
offline; secuencia durable pendiente. Complementa
[ADR8.38](../architecture/design.md), [R6](roadmap.md) y
[A8](production-acceptance.md). No cierra R6.1 completo ni R6.2/R6.3.

Recepción: review independiente final72/0 y siete probes intactos en
`/tmp/opencode/exagent-reserve-acceptance-f1a519/REPORT.md` SHA262a4a2f;
padre35/0 matriz+supplemental WA48 seed37556, hashes/delta cotejados.
Owner FULL1043/0/28 y compile97 corresponden a las mismas fuentes runtime;
esta recepción documental es posterior. Último P2 cardinalidad cerrado.
No SQL/live/A→B/resume general ni R6 completo. Los hitos inferiores conservan su evidencia
y estado histórico; esta cabecera sustituye sus pendientes de review del paso.

## Restore input confirmado — aceptado offline2026-09-28

Review integrada y fix mínimo de floors aceptados:171/171 independientes WA48,
probe original intacto y sin P1/P2 restante en alcance. Padre46/0 matriz input0+
probe WA48 seed37556, hashes cotejados. Informe final
`/tmp/opencode/exagent-restore-floor-recheck-f199cb6f/REPORT.md` SHA0cafcd64.
Owner FULL1088/0/28/compile99/formato corresponden al runtime aceptado. Esta
recepción documental es posterior; los rojos y pendientes inferiores son históricos.
No restore general, response/raw/atestación pendiente, A→B/SQL/live/R6 completo.

**Corrección tras rechazo P1 de review fresca:** la entrega1072 verde no probaba
el floor singular actual atravesando el seam. `Keyword.put(:permission_floor,
floor)` lo reemplazaba después de Authority.intersect; el probe externo ejecutó
la tool prohibida (1/2,exit2). Ahora el floor Frame3 se añade al final de la lista
conjuntiva; conserva slot singular actual, políticas plurales y orden interno.
Root pasa directamente de Authority.intersect a Scope y no tenía ese overwrite;
Scope ya evalúa singular y plural como conjunciones. No refactor ni nuevo formato.

16casos permanentes nuevos en composition_input_restore_test atraviesan claim,
rehidratación y loop: raíz/hoja, singular/plural, deny/ask y restricción actual u
original. Usan catch-all allow antes de la regla específica (last-match-wins),
observan actividad Model pero cero tool prohibida y autoridad persistida intacta.
Probe original intacto, equivalentes Frame7 y codec pasan en focal171/0,46.4s.
Compile99/formato0; FULL1088/0/28excluidos WA48 seed37556,214.0s,exit0.
Logs y delta mínimo en `/tmp/opencode/exagent-restore-floor-f19bf814/`;
revalidación fresca aceptada según cabecera. Los resultados1072 siguientes son históricos de la
entrega rechazada, no aceptación ni evidencia de este fix.

Se recuperó el parcial interrumpido sin reiniciar la base. Congelado previo en
`/tmp/opencode/exagent-restore-recovered-f19bf814/partial.tar`, ocho hashes de
RECOVERY comprobados. El parcial compilaba pero no abría raíces: Authority.usage
emitía claves átomo donde el validador exigía JSON string. El focal reprodujo29
fallos de apertura; corregido en la fuente de captura. La compilación sola no era
evidencia de restore.

API interna: `ExAgent.resume_composition_step(definition, reference, opts)`;
reference `%{id: id, record_id: lifetime, revision: revision}` y `:continuation`
con la configuración estructural habitual. `:root_options` aporta UsageLimits,
permisos/floor/concurrencia/deadline/estimador actuales de la raíz; el agente de
la definición aporta los UsageLimits actuales de la hoja, y las demás opciones
son las del run hoja. No se acepta sustituir ancestry mediante opciones.
Callbacks de codec son reconstrucción pura bajo contrato host, no efectos con
exactly-once. Sólo un claim CAS fresco admite codecs, registro y loop; el perdedor
y los receipts reproducidos no activan nada. Recuperación tras owner death es
administrativa explícita: no renueva automáticamente lease ni presupuesto gastado.

Frame7 único contenedor nuevo persiste autoridad efectiva raíz/create y
hoja/step_input. Los límites originales no se reescriben con la intersección
actual; Scope aplica ambas restricciones. Deadlines lógicos UTC no son el lease
ni la reserva activa. Root captura el deadline realmente aplicado aunque reciba
un hint interno de hoja. Frame4–6 auténticos siguen legibles, no ejecutables sin
piso; no migración. Hoja3, Record2, Scope2 e identidad snapshot1 permanecen.

Fronteras habilitadas: una hoja input confirmado/request0, cero operaciones e
intents; completed devuelve datos portables o error de omisión, sin codecs,
claim, mapping ni registro. No empty, response/raw/atestación pendiente/approval,
reconcile/model recovery, A→B, delegado, router o paralelo. Errores de preflight:
`composition_authority_missing`, `composition_not_ready`,
`unsupported_composition_boundary`, conflictos/validación/retención originales;
deadline lógico vencido devuelve `deadline_exceeded`. Output omitido completed:
`{:error, {:composition_output_omitted, marker}}`. Fallos del loop siguen RunError.

### Matriz actual criterio → prueba permanente

| Criterio | Evidencia |
|---|---|
| Bytes/VM nueva hasta completed, sin mapping/PIDs/captures anteriores | `composition_input_restore_test`: portable bytes + `support/composition_restore_vm.exs`, proceso OS/BEAM nuevo y IO1 |
| Dos resumers alcanzan CAS antes de liberar barrera; codec/IO únicos | input_restore: two resumers, barreras en Store ante ambos claims |
| Completed cero callbacks, incluyendo omisión noportable/capacidad | input_restore: completed; evidence_contract: nonportable + terminal capacity, codecs/Model/registro que fallarían si se invocasen |
| Owner muerto, no efectos, recovery explícito | input_restore: owner killed after claim commit, monitores owner/Writer; continuación sólo tras recover |
| ACK/receipt no autoriza ejecución, presupuesto crash no recarga | input_restore: replayed claim, confirmed input receipt, crashed active reservation |
| Root y leaf deny/ask originales contra allow actual; current deny | input_restore: matriz root/leaf×deny/ask + current deny; floor root conjuntivo |
| Límites root/leaf0 y exacto1, original y actual; strict | input_restore: cero original/actual raíz/hoja, exact one request, strict cost accounting |
| Todos UsageLimits, concurrencia min, orden y conjunción de floors | input_restore: all numeric limits, captura e intersección en Scope real; no promesa de concurrencia distribuida |
| Deadline lógico≠lease, original vencido/current vencido, captura efectiva | input_restore: completed tras lease original, logical UTC, current deadline, root effective deadline hint |
| Binding/ref/autoridad ausente o corrupta, antes de callbacks | input_restore: binding/reference/authority corruption; validación original Record/Frame y transición inmutable |
| Otros intents/response, raw/final/atestación/ask pre-callback | input_restore: begin_effect/outcome + ask; evidence_contract: ACK output_resolution, tool_outcome/finalize_call y helper restore_without_callbacks |
| J/JSON/receipts/cleanup exacto/+1 y evidencia output Retry | evidence_contract: Frame7 receipts1019+reserva5, JSON+cleanup exacto/+1, Frame7 tools before/after Retry; retention/tree_boundaries |
| Legacy auténtico y lectores agent anteriores | siete JSON byte-idénticos en `fixtures/continuation/composition_legacy`; input_restore legacy + suites continuation existentes |

No se importa usage desde snapshots sobre el ledger. Esta frontera no tiene
operaciones históricas: no se presenta como gate de repricing de una respuesta
histórica ni como recuperación de incertidumbre. Los gates previos de Scope/ledger
permanecen en FULL, pero no amplían la frontera input0.

### Comprobación owner y rojos conservados

Prefijo aislado de environment.md, `EXAGENT_OFFLINE=1 MIX_ENV=test`
y `MIX_BUILD_PATH=/home/kukapu/dev/projects/exAgent/_build/test` en todos los comandos.
`mix compile --force --warnings-as-errors`:99fuentes, exit0; `mix format
--check-formatted`:exit0. Focal integrado siete archivos:123/0 WA48 seed37556
(37.8s). FULL final:1072/0/28excluidos WA48 seed37556 (205.0s), exit0.
Logs, comandos, hashes y delta contra parcial/baseline en el directorio recuperado.

Siete probes externos originales ejecutados sin editar junto con tres suites
legacy:38/40. Los dos rojos son supuestos Frame6 del supplemental: assert6 frente
a7 y proyección aFrame5 sin retirar authority (campo desconocido). No se alteraron
los probes. Equivalentes permanentes Frame7 mantienen sus oráculos de reservas y
proveniencia mixed tool/Retry, verdes en focal/FULL. Los siete fixtures legacy no
se regeneraron con writer7. FULL preliminar1039/1047 y otros rojos de fixture
(config expires_at/authorize, contador usage inexistente, representación Regex.opts)
se conservan en logs; no se ocultaron como éxitos.

Lo anterior conserva la evidencia owner previa; aceptación independiente posterior
según cabecera. Sin paid/SQL/infra/consumer/publicación/bump.

## API propuesta

`new/1`, `binding/1` y `validate_binding/2` están implementados experimentalmente.
`new/1` recibe keyword sin duplicados; pasos son mapas de claves átomo exactas.
Además de refs siguientes exige `output_ref` versionada y `model_codec` con dump/1
y load/2. `model_ref` versiona configuración/codec host; cambios de código con la
misma versión no son detectables por este binding declarativo. `binding/1` devuelve
datos JSON con `composition_definition_version:1`, kind sequence y fingerprint;
`validate_binding/2` sólo compara contra una definición host validada. Nunca
reconstruye agentes desde datos ni ejecuta callbacks para calcular identidad.
Malformed/future → invalid_composition_binding; cambio válido →
composition_definition_changed. No run/resume públicos de Composition; el seam
interno reducido de ExAgent se describe arriba.

- `ExAgent.Coordination.Composition.new(opts)` → `{:ok, definition}` o error de
  validación. `opts` contiene `id`, `version`, `steps` ordenados, no vacíos; IDs de
  pasos únicos. Primera vertical sólo secuencia/fail-fast. Router, paralelo y
  collect se rechazan como no soportados, no se ejecutan como secuencias.
- Cada paso contiene `id`, `agent`, referencias versionadas `definition`, `policy`,
  `model_ref`, codec de modelo host y mapping opcional `input` con `input_version`.
  Sin mapping, A recibe input inicial y cada sucesor recibe output anterior.
  El callback puro recibe input inicial y outputs confirmados por ID; devuelve
  `{:ok, input}` o `{:error, reason}`. Función y deps viven sólo en memoria host.
- `run(definition, input, opts)` y `resume(definition, opts)` usan configuración
  continuation con Store scoped/id/durability/lease/expiry y límites existentes.
  Configuración raíz no exige modelo/codec; cada hoja sí los requiere.
- Resultado común completed/paused o RunError parcial. `model:nil`, historia raíz
  vacía, `steps` ordenados con input/output/status e historia por hoja. El total
  procede sólo del Scope; los subtotales de hojas no son contribuciones nuevas.
- Consultar/decidir/reintentar persistencia mediante las APIs Continuation actuales,
  sin una API de aprobación paralela ni un segundo token de checkpoint.

Las firmas run/resume y resultado anteriores siguen **propuestas**, no ejemplos
ejecutables. Constructor y binding no constituyen admisión de ejecución.

## Formato y seams mínimos

0. Implementado: binding definition1 independiente del frame,≤65536 JSON bytes
   incluyendo fingerprint,1..255 pasos, componentes de refs/IDs/versiones≤512 bytes
   UTF-8. Esta cota no reserva journal/cleanup ni limita RAM upstream. Los cambios
   de formato ejecutable siguientes son propuestas salvo el subset vacío descrito
   al final; ningún writer legacy cambia de formato.
1. Record2: discriminante explícito de ejecución; agente y composición comparten
   llave física/CAS/journal/receipts. Lectura Record1 sin reinterpretación. Snapshot
   composition1 contiene identidad, revisión y resultados propios, sin Model.
2. Frame4 sequence: raíz estructural, definición/fingerprint, cursor, input,
   confirmaciones, enlaces y Scope. Hojas Frame3 con sus snapshots existentes.
   Enlaces `step` y `delegation` son variantes exactas, no campos opcionales que
   permitan sustituir una call real por un paso. Rechazar variantes desconocidas.
3. Writer: apertura estructural, attach de hoja por step y confirmación de output/
   input mapeado. Mismo proceso serializa admisión y checkpoints de hojas/delegados.
   La transición de paso nunca añade un intent Model/Tool ficticio.
4. ExAgent: seam interno para entrar/restaurar una hoja usando Writer y Scope host,
   sin exponer al caller una bandera que desactive validación de árbol.
5. ExecutionScope/ScopeLedger: raíz sin operaciones propias; los ancestros siguen
   limitando todas las hojas. Este seam interno está implementado: start_structural/2
   no recibe Model y rechaza admisión/contribución propia. Scope2 restaura únicamente
   operaciones de hojas en ese host, sin repricing. Falta conectarlo al Writer y
   restaurar el árbol de composición antes de activar hojas.
6. Frame/Record/Transition: validación estricta del formato, monotonía de pasos
   confirmados y grafo↔journal. Aprobar no convierte datos en definiciones host.

El snapshot raíz no puede reutilizar Server.Snapshot con Model inventado. Antes
de implementar hay que contrastar todos los consumidores de Record.snapshot:
rechazar composition en caminos Server/Session sin modificar preventivamente sus
contratos. No introducir un nuevo kind Store que obligue a otro backend/tabla.

## Protocolo secuencial

| Frontera | Condición y efecto permitido tras ACK |
|---|---|
| create/claim | Validar definición, input, límites y Scope; sólo después activar A |
| input confirmado | Input portable del paso y enlace guardados; se permite comenzar su loop |
| hoja terminada | Output e historia confirmados, Scope actualizado; no repetir esa hoja |
| mapping siguiente | Callback puro una vez en este intento; persistir resultado antes de B |
| checkpoint fallido | Retener comando data-only; bloquear cualquier nuevo callback/IO |
| B/delegado pending | Journal y approvals íntegros; pausa raíz sólo después de ACK/quiescencia |
| resume | Validar todo el grafo y refs host; reclamar una revisión; restaurar únicamente cursor activo |
| finish | Conservar parciales/uso, terminal confirmado, cleanup del owner y Writer |

ACK perdido no significa que el callback pueda repetirse: retry_checkpoint sólo
reenvía el comando original. Tras crash antes del commit, un mapping puro no
confirmado puede volver a calcularse; este caso es distinto del mapping confirmado
que nunca se repite. Si el host necesita efectos en el mapping debe expresarlos
como una tool del loop, no esconderlos en una función supuestamente pura.

## Identidad, límites y recuperación

Fingerprint canónico de datos host: ID/version, orden/IDs de pasos, referencias
versionadas de agentes/policies/modelos/output y mapping. No serializar funciones,
PIDs, handles, OTel ni deps. El host debe actualizar versiones al cambiar código;
no se promete detectar cambios semánticos de closures con la misma versión.
Comparación previa a load codec/mapping/claim/IO. No migración implícita por igualdad
de nombres. Permisos y deadlines actuales sólo estrechan restricciones originales.

Los outputs de pasos y inputs mapeados son JSON normalizado acotado. Contar todas
sus copias, snapshots por hoja y tokens bajo J/JSON existentes; reservar salida y
cleanup antes del siguiente efecto. Historial/modelo de hoja se conservan con codec
existente, no con serialización del struct vivo. Mantener nodos/efectos/receipts
finitos. Constructor admite hasta255 pasos; la ejecución deberá contar además raíz
y delegados contra la cota total de nodos, sin prometer255 delegados adicionales.

Restore valida también journal→hoja, no sólo hoja→journal. Eliminar A y su ledger
pero conservar sus efectos debe rechazar preIO. Resultados confirmados no cambian
por un nuevo estimador; requests nuevas sí usan la configuración vigente. Errores
con parciales nunca convierten usage desconocida en cero observado.

## Gates pendientes (sin resultados todavía)

1. Público A→B completed, output tipado y dos historias independientes.
2. A confirma; B delega; ask devuelve paused sólo tras persistencia y quiescencia;
   cero efectos de la tool pendiente y evidencia de cleanup.
3. Guardar bytes y ejecutar otra VM con definiciones confiables; approve/resume:
   A/mapping/request/tool confirmados una sola vez; mismo ledger sin repricing.
4. ID/version/fingerprint/policy/model binding cambiados: cero IO nuevo.
5. Autoridad ancestral, deadline y dos hojas compitiendo por admisión compartida
   mediante primitives existentes, sin implementar fan-out público.
6. Dos resumers simultáneos con barreras: un claim/efecto; perdedor sin callback.
7. ACK perdido antes/después del commit de output/input/pausa: retry sólo datos.
8. Owner kill e incertidumbre real: no replay automático ni éxito ficticio.
9. Corrupciones de enlaces, cursor, outputs, ledger y journal en ambas direcciones;
   lectores Record1/Frame1/2/3 y fixtures legacy auténticas siguen pasando.
10. J/JSON/cardinalidades exacto y +1, reserva cleanup y output no portable.
11. Focales frecuentes, compile/suite warnings-as-errors al cerrar runtime, format,
    diff/documentación y review independiente. EXAGENT_OFFLINE=1 y prefijo aislado.

SQL A8 y proveedores reales no se aceptan con ETS ni mediante esta propuesta.

## Evidencia del hito constructor (2026-09-27)

Prefijo aislado de environment.md, EXAGENT_OFFLINE=1 MIX_ENV=test, seed37556.
Evidencia local: `/tmp/opencode/exagent-r6-definition-f1ac7/`.

- `mix test test/exagent/composition_definition_test.exs --seed 37556`: rojo previo,
  0/11 pases,11 fallos por API ausente, exit2 (`red.log`).
- Primer compile: conflicto local binding/1 con import Kernel.binding/1, exit1;
  corregido con exclusión explícita del import (`green-attempt1.log`).
- Primer runtime:10/11, exit2; fixture de80 pasos no excedía JSON. Se corrigió la
  fixture y añadieron oráculos exactos65536/+1 y255/256 (`green-attempt2.log`).
- Constructor inicial13/13 exit0 (`green.log`); ampliado a15 casos de corrupción.
- `mix test test/exagent/composition_definition_test.exs
  test/exagent/coordination_test.exs test/exagent/continuation_record_test.exs
  test/exagent/continuation_tree_test.exs
  test/exagent/continuation_scope_ledger_test.exs --seed 37556 --warnings-as-errors`:
  **49 pases/0 fallos/0 excluidos**, exit0 (`focal-adjacent.log`).

No suite integrada ni restart/SQL nuevos: no se ha conectado el constructor al
runtime. Faltan exactamente snapshot/Frame discriminados, transiciones de input/
output confirmado, apertura Writer sin modelo, Scope estructural, seam de hojas y
restore de pasos (ExAgent.execute_scoped/restore_children hoy asumen agente/call).
Después, tests públicos A→B/delegado y gates1–11 de arriba. Sin bloqueo técnico
demostrado; este hito no justifica relajar validadores ni simular efectos raíz.

## Hito parcial Scope estructural (2026-09-28)

`ExecutionScope.start_structural/2` inicia el mismo proceso de admisión/contabilidad
sin invocar Model.system/model_name. El marcador estructural sólo vive en estado
host, no es una opción caller ni una bandera de JSON. Rechaza requests, batches,
retry batches y contribuciones propias antes de estimadores/efectos. Permite hojas
con el loop original y contabiliza sus operaciones una vez en cada ancestro.
Un estimador raíz debe ser nil o aridad2 (modelo, uso); aridad1 exige identidad de
modelo y se rechaza, no se inventa una identidad. Hojas conservan aridad1 ligada a
su propio modelo y las restricciones ancestrales originales.

Scope2 no cambia de formato: sigue siendo contabilidad, no autoridad de ejecución.
El rehidratador confiable elige la raíz estructural; importar operaciones propias
de raíz legacy en ella falla atómicamente. El lector genérico Scope2 sigue aceptando
raíces agente legítimas. Export/restore root-only Scope1 no son un fallback para
la raíz estructural. No se han cambiado Frame/Record/Writer ni añadido run/resume.

Evidencia `/tmp/opencode/exagent-r6-structural-f1aae/REPORT.md`: rojo6/6 por seam
ausente tras corregir una fixture Usage incompleta; focal ampliada54/0, compile94
y suite971/0/28, seed37556, warnings-as-errors, exit0. La primera suite se interrumpió
por timeout120s; la segunda970/1/28 expuso el requisito existente MIX_BUILD_PATH del
test de nueva VM. Con path absoluto `_build/test`, probe1/0/13 y suite final verdes.
La suite mantiene logs de warnings operacionales/dependencias esperados.

Los ocho tests nuevos prueban dos loops hoja reales, límite ancestral, carreras con
barrera, JSON/reconstrucción del Scope y precios históricos, rechazo de operaciones
raíz y autoridad/deadline. **No prueban A→B durable**, checkpoint de output/input,
pausa con delegado, ACK perdido, dos resumers ni otra VM de composición. Entrega
parcial por alcance de contexto, sin bloqueo técnico demostrado. Siguiente trabajo:
snapshot/Frame discriminados y enlaces step reales, Writer estructural compartido,
seam de hoja/restauración y secuenciador integrado; después gates1–11. No sustituir
esa integración por usar run_child efímero en la API pública Composition.

## Hito apertura/claim/roundtrip de raíz vacía (2026-09-28)

Implementado exclusivamente el seam interno `Writer.open/3` con configuración
`kind: :composition`, `composition: definition` confiable, definition/policy refs
y Store/id/durability/lease/expiry/límites existentes. No admite model_ref,
model_codec ni request_id raíz. El estado mínimo contiene run_id, input portable
y execution_scope creado por start_structural. Owner registration ocurre después
de validar configuración, binding, input, Scope vacío y capacidad create/claim.

Record2/execution2 kind composition comparten el mismo kind agent/tabla/CAS/
journal. Snapshot composition1 sólo contiene composition_id/run_id/binding/revision0.
Frame4 exacto contiene kind sequence, cursor empty, run_id, binding, input y Scope2.
IDs/binding/referencias se contrastan entre snapshot, ejecución y frame; no se
construyen agentes a partir de JSON. Un nuevo claimant aporta de nuevo definición,
input y Scope host, no obtiene autoridad del record. Root0operations obligatorio.
Record1 y Frame1–3 mantienen sus writers/lectores; snapshot/restore de agente
rechazan composición. No se tocó Checkpoint ni Store: sus primitivas se reutilizan.

Reservados/rechazados: hojas, children/step links, resultados/outputs, inputs
mapeados, approvals, cursor distinto de empty, efectos Model/tool, snapshot
revision distinta de0 y completion. Sólo create y claim/recover/cancel/expire/delete
están disponibles mediante Transition. No hay Composition.run/resume, secuenciador,
rehidratación de permisos/límites persistidos ni capacidad de activar hojas con
este formato. Los formatos de pasos futuros siguen pendientes de diseño integrado.

Evidencia nueva `/tmp/opencode/exagent-r6-root-f1a965/REPORT.md`, seed37556:
rojo producto0/1 por configuración sin Model;8 tests nuevos; focal92/0/0,
compile forzado95fuentes y suite979/0/28 en180.5s, todos warnings-as-errors exit0;
formato y diffcheck exit0. Prefijo aislado y MIX_BUILD_PATH absoluto de environment.
Incluye JSON/load/get/IDs/revisión, conflicto segundo claimant, fencing/recovery
con reloj explícito, cancel/replay Checkpoint, ACK de create perdido con token
JSON sólo-datos, corrupción/mismatch y límites J exacto/+1 con reserva cleanup.
Fixtures corregidas antes de gates: Test.new/0 inexistente y fault Store sin
scan_records/3. La suite conserva logs operacionales/dependencias esperados.

Esto no demuestra A→B, pausa de hoja/delegado, restart de VM de composición,
SQL A8, proveedores reales ni C7 composición completa. No hay bloqueo técnico
demostrado para esta unidad; review independiente aún corresponde al principal.

## Hito paso→hoja real único (2026-09-28, entrega parcial)

Base: raíz vacía aceptada tras review fresca y fix **del padre**, no la entrega
original idéntica. Se conserva structural_claim_capacity(record || projected,
config) y sus regresiones receipt_limit/expired/segundo claimant pre-callback.
Baseline copiado/hashes antes de editar en `/tmp/opencode/exagent-r6-step-f1a965/`.

Implementado <code>ExAgent.run_composition_step/4</code> interno (doc false), con Writer vivo,
definición host y step_id. Sólo una definición de un paso. Writer compara todo el
binding antes de codec/mapping, mapea input puro una vez en el intento y emite un
ticket efímero host, no un token de continuación nuevo. Adjunta la hoja al mismo
Scope y guarda enlace/input/snapshot antes de permitir entrar al loop retenido.
Requests/outcomes y cierre usan el mismo journal/Checkpoint/Transition/CAS/fila.
No parent_request_id/call inventados, Model raíz ni Store de hoja.

Frame5 mantiene identidad/input inicial/binding/Scope del root y añade children y
cursor running/completed. El child lleva enlace exacto kind step, step_id, index0 e
input; refs definition/policy/model_ref/output_ref, Frame3, ServerSnapshot, estado,
resultado y marcador de omisión existentes. Frame4 sigue exactamente vacío; los
datos viejos no se reinterpretan ni se hacen ejecutables por aceptar bytes. Un
segundo paso, delegation y tipos desconocidos aún rechazan. La evolución de schema
es explícita por esa incompatibilidad con Frame4; Record2/snapshot raíz1 no cambian.

Input/output sólo avanzan tras CAS; las mutaciones ordinarias no pueden cambiar
binding, input ni link, ni hacer finish sin request confirmado. Graph evidence
valida operaciones↔journal y snapshots/hashes de respuestas/modelo; root0operations.
Límites/lease/deadline ancestrales y budget existente se conservan; snapshots hoja
no se vuelven a contribuir al total. Reserva antes de IO y omisión acotada del
resultado mantienen J/JSON y retry de comandos exactos tras ACK incierto.

`Writer.step_status/3` es inspección/reconstrucción **data-only**, no ejecución:
valida config/binding y distingue empty/input_confirmed/running/completed, conservando
input/output, frame/model_data y snapshot. Reconsultar completado en el mismo Writer
devuelve datos, nunca otro request. Repetir un intento con checkpoint pendiente se
rechaza; retry_checkpoint sólo IO Store. **No se ha implementado reanudar una hoja
interrumpida ni reabrir Frame5 como raíz vacía.** La dependencia mínima restante es
persistir/restaurar el piso de restricciones/autoridad de raíz y reconstruir los
Scopes/frames hoja bajo ese piso, no confiar en ScopeLedger como autoridad. También
quedan A→B, delegado ask/resume, mapeos entre pasos, restart VM y API pública completa.

Oráculos nuevos: Model.Test real, link/input ya guardados dentro del callback de
request; snapshots/cursor/model index y JSON; input ACK antes/después con0requests;
output ACK antes/después con1request y retry sólo datos; refs/mapping/output cambiados
pre-callback; corrupción bidireccional/link/hash/Scope; límite ancestral, lease,
refund, J exacto/+1/no portable y respuesta sobredimensionada sin segundo request.
Comandos, rojos, cuentas, freeze y límites verificados constan en
`/tmp/opencode/exagent-r6-step-f1a965/REPORT.md`. Esta entrega funcional parcial no
acepta R6.2–3/A8/C7 composición ni atribuye al delta los gates del WIP previo.

Verificación del delta:13tests nuevos, focal107/0/0 WA seed37556 exit0; compile
forzado95fuentes y formato exit0. Suite completa **994/0/28 con --max-cases1**,
195.3s, WA exit0. La suite por defecto max_cases48 **NO quedó verde**: dos
ejecuciones993/1/28 (183.4/185.1s), mismo timeout en MCP.ClientTest línea140,
fixture con timeout50ms para handshake/request. Ese test aislado pasó3/3 (cada
ejecución1pase30excluidos por selección). No se modificó MCP ni se aumentó su
timeout: causa última no demostrada, incidencia de concurrencia devuelta al padre.
El verde serial cubre todos los tests sin exclusiones adicionales, pero no sustituye
un gate verde con la concurrencia habitual. Todos los logs, incluidos rojos, se
conservan en el informe. Pendientes: revisión independiente del delta y ese gate.

### Residuales paso→hoja — 2026-09-28, entrega owner sin aceptación independiente

La evidencia anterior es histórica. Tras fixes recuperados por el padre, el review
residual encontró ToolReturn inventado/mutado aceptado y adhesión vacía huérfana tras
codec fallido. Los tres rojos se reprodujeron con probes originales intactos antes
de editar. Frame verifica ahora historia y outcomes por request/call contra journal
en ambas direcciones; reserva capacity usa evidencia sintética autoconsistente.
Writer limpia sólo la adhesión pre-write exacta sin operaciones/descendientes; nunca
input confirmado o pending/dirty. ADR8.38 registra impacto y alternativas.

Regresiones permanentes cubren falsificación CAS, mutación/borrado/duplicación de
returns al decode, codec/capacidad fallidos y retry, owner death durante capture,
denegación sin IO, errores y omisión de resultados, además de guards del Scope.
Focal ampliado272/0 WA seed37556 incluye probes antiguos/nuevos intactos y todas las
familias continuation, structural, composition y execution_scope. No demuestra
proveedores pagos, SQL real, run/resume, A→B ni aceptación independiente.
Logs y comandos: `/tmp/opencode/exagent-residual-f1a381/`.

Gates finales owner: compile forzado95 y formato global exit0; probes originales y
residuales intactos + focal de paso/Scope45/0 WA exit0 tras exigir phase final en
returns históricos (raw sigue válido en outcomes intermedios). Suite completa
**1010/0/28, --max-cases48 --seed37556 --warnings-as-errors**,187.6s, exit0.
Sin serializar, excluir tests adicionales ni modificar MCP. Los warnings runtime
upstream de Req y logs operacionales esperados permanecen; no son fallos del gate.
Esta evidencia sustituye el gate concurrente histórico, no la revisión independiente.

### Unidad contractual de evidencia — 2026-09-28, nueva revisión pendiente

La revisión posterior **no aceptó** el hito1010: dos tools running exponían un
current sintético inconsistente, y un output CountOutput válido se confundía con
dispatch. Researcher/padre acotaron una unidad contractual, sin A→B/resume. Antes
de corregir se reprodujeron ambos probes intactos y un tercer rojo nuevo: Retry
con call_id fabricado podía cerrar una función no ejecutada.

Se mantienen loop, Writer, CAS y Scope. `OutputResolution` verifica datos, no llama
a Ecto ni hooks/codecs. El loop emite evidencia sólo tras validar output; no trata
final_result como nombre privilegiado (una función real homónima sigue dispatch).

| Formato/estado | Contrato |
|---|---|
| Frame1–3, Record1, Frame4 | Lectores/esquemas intactos |
| Frame5 | Paso sin atestaciones; sin campos opcionales nuevos ni migración inventada |
| Frame6 | Frame5 + output_resolutions por request, promovido sólo por output_resolution |
| output_resolution_version1 | run_id/request_id, descriptor, call_id, decision, parts/parts_hash, result/result_omitted |
| Descriptor | Preimagen exacta del fingerprint del RequestData correspondiente; ≤65536 JSON bytes antes de admitir Model |
| Respuesta con atestación | Único intermedio: cursor response, snapshot todavía sin returns, child running; evidencia ya confirmada e inmutable |
| Siguiente request/finish | Snapshot contiene exactamente las partes atestadas; retry/success y resultado coinciden con posición/contadores |
| Output siblings | Primera output seleccionada; extras output antes de siblings de función, orden exacto del loop; cero callbacks siblings |
| Resultado omitido | Marker verificable sin ejecutabilidad; si sólo se omite copia terminal, bytes se miden sobre el resultado portable atestado |

CAS sólo añade una resolución al request activo; no modifica las anteriores ni
snapshot/frame/journal en esa transición. Record.decode comprueba preimagen,
selección, hashes, partes, estado y resultado sin ejecutar validadores. ToolReturn
y Retry con call_id necesitan evidencia; Retry sin call no cierra tools. Función
raw→final y resolve_call pre_dispatch conservan status/procedencia, no se consideran
equivalentes por devolver validation_error. La reserva simula siblings confirmed
junto con sus outcomes en current, manteniendo target running sin resultado futuro.
No modifica el Store ni Scope vivo y no elimina current_valid o guards previos.

Matriz permanente: `composition_evidence_contract_test.exs` cubre dos barreras y
ambos órdenes con journal running real y mezcla raw/final; output directo/paso,
siblings/múltiples outputs, inválido→válido/agotado, función homónima/colisión,
veto/error/retry/timeout/hook transform, ACK antes/después de raw/final/atestación/
cierre, corrupción CAS+decode, malformed CAS sin crash, descriptor preIO, resultado
no portable y copia terminal omitida. `composition_step_persistence_test.exs`
añade Retry fabricado antes del fix y lo comprueba también al decode; conserva
cleanup/ACK/evidencia anteriores. Reutilizar call_id, args inválidos/unknown,
request/nodo/schema mezclados, raw-only history y Retry sin call también tienen
regresiones permanentes nuevas, además de los probes independientes intactos.
El fixture Jason/Ecto nuevo vive en test/support para compilar antes de consolidar
el protocolo; no cambia fixtures MCP ni la fixture native anterior.

Evidencia y matriz→tests detalladas: `/tmp/opencode/exagent-contract-f1a381/`.
Sin aceptación independiente, SQL/live, run/resume ni expansión R6.

Gates owner finales: **73/0** matriz/paso y seis archivos probes intactos, WA48
seed37556,15.8s; focal integrado final318/0 WA48,170.1s; compile forzado97 y
formato global exit0. **FULL1041/0/28**, WA48 seed37556,193.2s, exit0; ninguna
exclusión adicional ni serialización.30 tests en la matriz nueva más el negativo
Retry previo al fix (31 tests nuevos frente a1010). Todos los rojos intermedios
de producto/fixtures/formato se conservan explicados en el informe, no se ocultan
con el gate final. Los warnings runtime upstream/logs esperados permanecen.

### P2 de cardinalidad Frame6 — 2026-09-28, entrega owner pendiente de review

La revisión integrada posterior dejó un P2 reproducible: <code>Record.tree_children/1</code>
enumeraba2/3/5, omitiendo6. Con atestación confirmada y hoja aún running, la reserva
caía5→2receipts y33800→13070bytes;1020receipts se admitían invadiendo la reserva.
No se demostró pérdida irreversible. El supplemental intacto reprodujo2/3 antes
de editar. Corrección runtime de una línea: incluir6 en ese helper compartido por
tree_receipts, runtime_resolution_pending, cleanup_reserve_bytes y tree_slots.
No nuevo formato, refactor, relajación de guards ni cambio al cleanup de Scope.

Se inspeccionaron los switches equivalentes en lib: Record.execution?, Frame
validate/step_transition/child binding, Transition estructural y Writer.step_status
ya incluyen5/6. Las ramas que crean/promueven Frame5, Frame4 vacío y formatos
legacy siguen siendo deliberadas, no consumidores de cardinalidad pendientes.

Dos regresiones permanentes en composition_evidence_contract_test cubren la hoja
Frame6 real tras ACK perdido: comparación exacta con Frame5 equivalente, reserva5,
umbral1019receipts válido/1020inválido y JSON+cleanup exactamente8MiB/+1 rechazado.
Focal158/0 WA48 seed37556 (53.2s) incluye supplemental intacto, seis probes previos,
matriz y record/retención/boundaries. Compile97 y formato global exit0; FULL1043/0/28
WA48 seed37556 (195.1s), exit0. No serialización/exclusiones nuevas. Informe, hashes,
delta mínimo y auditoría de switches en `/tmp/opencode/exagent-frame6-reserve-f1a381/`.
Esto es evidencia owner, no aceptación independiente ni cierre de R6/SQL/live.
# C7 secuencia todo-pending — implementación owner2026-09-29

Mandato sellado en tasks/sequence-approvals, sin delegación. Runtime limitado a
Writer/Record/Transition/Frame/CompositionRestore/Composition. Diseño8.41 explica
contrato y compatibilidad direccional Record2; Frame9 y Approval1 conservados.
Primer checkpoint real `checkpoint6.log`: VM nueva consume dos approvals B tras
A tool una vez y decisiones públicas, termina C; contadores3tools/5requests exactos.

Informe recuperable `/tmp/opencode/sequence-approvals-f153afda/REPORT.md`; baseline
WIP y fuentes en baseline.tar/sha256. Nuevos tests/fixture/VM `sequence_approval*`.
Dos negativas antiguas exactas all-pending se reprodujeron juntas antes de editarlas:
focal2 146/148, SequenceRun y SequenceWriter; convertidas en oráculos paused ACK
manteniendo ausencia de efectos/sucesor. Empty-root unsupported y regresiones7/8,
mixtos/raw/delegación permanecen intactos.

Matriz nueva: VM, dos decisiones/deny/actor/hash/CAS, dos claimants; ACK before/after
pause/decide/claim/tool intent/outcome/outputB/inputC con tokens sólo persistencia;
espera humana mayorlease/budget original con saldo, late ACK y expiración lógica,
claim finito abandonado; args efectivos, current deny, mixed con efecto real,
sibling muerto/accounting rechazado; corrupción global/receipt/revisión, mutaciones
snapshot/scope/authority; historial aprobado/sufijo recuperado/completed data-only.
Límite Writer público±1 para pause/claim/intent/outcome/output/input, horizonte1024
receipts reales±1 y JSON+cleanup8MiB±1, dos decisiones de actor escapado máximo y
cancelación reservada. Los límites de admisión pueden ser mayores que el token por
la reserva de outcomes/control; no se equiparan ambas cotas.

Evidencia previa al gate final: matrix3 30/30, focal3 490/491 (fallo de harness:
callback on_writer llamó síncronamente al propio GenServer; corregido usando barrera
y cota temporal observada). Capacity receipt1/1 y JSON1/1 verdes separados; logs
históricos conservados. Focal final105/105,168.5s exit0 incluye43nuevos y las dos
suites antiguas ajustadas. FULL final único1776pases/28excluidos,1098.2s exit0,
offline WA48seed37556; compile forzado108WA, formato global y diff exit0. Manifiesto
pre-FULL303/303 runtime/tests/config/mix intacto tras gate. Docs de entrega actualizados
después; identidad/delta finales en REPORT. Sólo quedan los tres BEAM ajenos originales;
ningún build activo. No autoaceptación de C7/R6, SQL/live/producción ni publicación;
review independiente y decisión del padre siguen requeridas. Capacidad nueva prueba
admisión pública±1 (incluye reservas y lectura) y JSON/receipts exactos: no se atribuye
a cada umbral un límite aislado de token ni se promete concurrencia global sin efectos.
Matriz sellada aún no cerrada exhaustivamente: faltan oráculos nuevos aislados de
codec token±1, cambios model-binding/schema/policy tras approvals y delay específico
de observabilidad del batch aprobado. FULL verde no sustituye esos oráculos ni review.

# Slice response textual confirmada — 2026-09-28

**Aceptado offline tras review fresca:**169/0 WA48, matriz final37 incluida;
padre37/0 WA48 seed37556,47.8s. Informe
`/tmp/opencode/exagent-text-review-f19634a3/REPORT.md` SHAe33afbaf.
Manifiesto11/11 cotejado; owner FULL1125/0/28/compile99 no se atribuye al reviewer.
El probe suplementario reviewer no llegó a ejecutarse por herramienta ausente:
no se cuenta como evidencia. No atestaciones/general/A→B/SQL/live.
Amplía sólo el
restore input0 aceptado a una primera response textual confirmada: Frame7 ready,
única hoja running/response/run_step1, un Model succeeded/state_available y una
operación Scope2. Perfil host text/tool, fingerprint textual y texto no vacío,
finish nil/stop/end_turn; sin calls/returns/Retry/tools/batches/planes/atestaciones.
Record valida los enlaces journal/ledger/history/model_data antes de claim.
`continuation_frame` queda asignado antes del preflight Model y se cierra por
prepare_run/handle_response/succeed/Writer.finish, no por otro motor.

Matriz owner en `test/exagent/composition_text_restore_test.exs` (37 casos):

| Criterio | Oráculo |
|---|---|
| Restart real | `portable confirmed response` inicia otro OS/BEAM con JSON capturado, recovery explícito y `composition_text_restore_vm.exs`; cierre sin Model/mapping/after_model y ledger idéntico |
| Uso histórico | Primera confirmación y `normalized historical quality`: precios hoja3/raíz7, calidad/details/contribuciones iguales, estimadores nuevos que fallan si llamados, resultado3/2 tokens sin doble suma |
| CAS | Dos resumers bloqueados antes de claim; sólo uno completa, un codec/registro, perdedor cero |
| ACK | Response antes→uncertain rechaza; después→recovery ejecutable. Claim/output before/after, token exacto y receipts viejos sólo persistencia; completed consulta sin callbacks |
| Preflight | Corrupción de refs/fingerprint/historia/model_data/nodo/ledger; typed/native con schema trap; codec no determinista no relaja evidencia |
| Tiempo/autoridad | Presupuesto reservado consumido tras crash, deadline actual, límites actuales conservados; suite input0/floor probes reejecutada sin cambiar sus fuentes |
| Retención | History/output payload exactos y un byte menos; checkpoint estrecho; omisión verificada no ejecuta; receipts1019/1020 y JSON+cleanup8MiB/+1 |
| Exclusiones | Vacío, length/filter/unknown/incomplete/error/tool_calls, tool response real, atestaciones success/retry reales; mutaciones batch/step2 y gates de evidencia existentes |
| Regresiones | Input0/completed, evidencia/retención/record/tree, siete fixtures legacy y probes reviewer Frame7/floors/codec intactos |

No nuevo débito de admisión al consumir respuesta histórica: request_limit1 ya
usado permite cierre; límites de nuevos efectos más estrechos no invalidan gasto
pasado ni lo recalculan. Esto conserva Scope, no introduce bypass de admisión.
La fixture anterior tenía lease50ms y falló antes de IO con lease_expired:
diagnóstico guardado, corregida a1000ms y espera de expiry observado para recovery,
sin relajar guard runtime ni timeout de aserción. Informe conserva rojos de fixture
y comandos/exits/hash/delta contra baseline, separado de aceptación independiente.

Gates owner finales con prefijo aislado de environment y MIX_BUILD_PATH absoluto:
compile forzado99 fuentes WA, formato global y diff-check exit0; focal165/0 con
probes reviewer intactos; matriz final37/0; FULL1125/0/28, seed37556, WA48,258.8s.
Los cuatro casos finales añadidos tras focal165 también pasan en la FULL final.
Los28excluidos no son aceptación SQL/proveedores. Los dos supplemental antiguos
con supuestos Frame6 permanecen históricos; equivalentes Frame7 pasan en focal165.
# Correcciones causales CAS10 — 2026-09-29, revisión independiente pendiente

Review bloqueante original `/tmp/opencode/frame10-cas-review-8Dfp1CQa/REPORT.md`,
SHA256 `03a7694c79d4bb9bd9a054c1bd81034b82dada83a4fcaaa565b11337c9d61366`.
Baseline contemporáneo de tracked/untracked y20/20 sellos owner verificados antes
de editar; fuentes/logs originales conservados. Informe de esta corrección:
`/tmp/opencode/frame10-cas-fix-42rWnXLi/REPORT.md` y logs/exits bajo ese directorio.

Cuatro causas: Transition/Frame rechazan Model sobre history no ejecutable;
Transition/ToolEvidence rechazan final unknown también sin effect child;
Record descuenta sólo slots de resultado JSON materializados conservando futuro/
metadata/cleanup/receipts; host_reason10 certifica motivos observados post-hook con
descriptor e identidad original, no revalida args originales. Diseño describe prueba
de reserva y compatibilidad interna direccional. Sin modificar Budget ni productor9.

Repro originales copiados9/13 exit2; cuatro fallos, más diagnostics que afirmaban el
bug y por eso pasaban. Nuevas copias contractuales4/10 exit2 muestran las cuatro
causas; negativas unsafeaccept ahora esperan rechazo y fila intacta. Tras guards,
7/10 exit2: capacidad aún roja y dos códigos exactos de error de test corregidos
de invalid_record a invalid_frame10_transition (guard de fase), no relajados.
Primera focal123pases=113existentes+10adaptados; matriz extendida12/12 con JSON
escaped/reserva±1, retorno65536±1/cierre completo/failure atomic, unknown coherente
mutado y host hash/identity/retry/binding negativos. Reruns no son nuevos casos.
Gate final offline WA48 seed37556, compilación habilitada:333pases/214.4s exit0
(320existentes+13nuevos/adaptados). Copia externa contractual final13/13/9.9s exit0
son los mismos13, no casos adicionales. Compile forzado112WA, formato global y
diff-check exit0. Baseline440:432rutas intactas, sólo8modificadas autorizadas y2tests
nuevos;20/20sellos previos owner verificados. Comandos/hashes exactos en REPORT;
no FULL rutinaria sin productor. ROOT/build/docs4 liberados, sin checks propios activos.

Inputs trusted sintéticos, no hooks/workers vivos ni quiescencia/VM/SQL. No aceptación
subset o producto10: revisión independiente requerida; nonnil usage (nil≠zero),
outputretry/globalterminal/recoveruncertain/fatal siguen fuera. No borrar historia,
inventar settlement/refund, ampliar capacidades, bump ni publicación.

## Cierre exitoso estructural CAS10 — 2026-09-29 (review pendiente)

Incremento interno sobre output/retry y fix capacidad revisados, no aceptación R6.
Allowlist efectiva: Frame/Record/Transition/ToolEvidence, dos nuevos archivos de
tests/support y docs4. Budget/Continuation y productores/restores no se modifican.
`step_output` sólo toma node_id/elapsed_ms más ownership/fence/epoch: deriva result
de respuesta confirmada o atestación typed, consume history si corresponde y avanza
cursor. Último step confirma completed y refund del claim actual una sola CAS.
Certificado allnodes exige batches consumidos y descendientes terminales, manteniendo
source/control/usage y root input/prefix. No reprice, redebit ni nuevo Scope close.

La reserva typed previa permanece; plain response añade result/raw residual y recibo
pendiente antes de ACK. Tests de frontera derivados del tamaño real cubren ±1,
plain/escaped, typed/plain, step intermedio y raíz, replay y cierre sin nuevo IO.
El escenario integrado usa límites tool_return_bytes4096 para cinco nodos y seis
calls: con65536 el cleanup reserve de pause excedía8MiB; no se aumentó límite ni
rebajó reserva en producto. Techos no prometen capacidad universal. Otros tests
mantienen65536 y el fix capacity original intactos.

Inspección Record/get completed data-only verificada en pruebas; Composition.resume
rechaza10 y no reclama/modifica fila. Su proyección terminal pública con definition
binding es seam pendiente en CompositionRestore (fuera de este frente). No afirmar
fachada completed10 disponible. Mapping host se conserva como input trusted/version
binding; no se ejecutan funciones al decode ni se prueba su semántica. No snapshots
finales insertados: create/claim y cada ACK mediante Store.ETS/CAS+encode/decode.
Fatal/exhaustion/outputfailed/cancel/expire/uncertain/recovery y productor10 cerrados.

Artefactos recuperables: `/tmp/opencode/frame10-success-terminal-8v_93fvc/REPORT.md`,
baseline contenido+hashes de tracked/untracked previos, missing/deleted separados,
logs de desarrollo y delta final. Fallos de harness/bindings y guards terminales
durante implementación se conservan sin relabel.

Gates finales sobre seis fuentes propias selladas antes/después: **316 pases**
seleccionados,471.4s/exit0 (incluye12 nuevos; todos los frame10 y legacy pertinente
Record/cleanup/tree, Frame9, completed output restore y active evidence). Los
**7 probes** previos del reviewer (5+2), copias byte-idénticas, pasan15.2s/exit0;
no son nuevos casos ni nueva revisión independiente. Compile forzado115WA, formato
global y diff-check exit0. OTP29/Elixir1.20/offline/test, build absoluto ROOT/_build,
maxcases48/seed37556, compilación habilitada; timeout600000ms. No FULL rutinario.
Los12 casos nuevos son8 combinaciones capacidad root/step×typed/plain×escaped/plain,
flujo ABC mixed+pause2/reclaim, terminal/refund/replay/mutación, rechazo root sobre
child/raw/wrapping/unconsumed y mapping host data-only. Los tests legacy quedan
byte-idénticos: ninguna expectativa negativa antigua necesitó cambio.

Quedan producer10/VM/hooks vivos/quiescencia/fatal/recovery/SQL y consumer seam
CompositionRestore terminal. Revisión independiente y probes padre aún requeridos.
No se autoacepta Frame10 producto ni R6. ROOT/build/docs4 y procesos propios liberados
al terminar el REPORT; no comandos background ni infraestructura modificada.
## Incremento interno fatal-control10 parcial —2026-09-29

Artefactos: `/tmp/opencode/frame10-fatal-cas-xclmgyda/REPORT.md`, baseline de contenido
y hashes previo a cambios, manifiestos finales y delta. Owner no acepta producto10.

Implementado: call_settle confirma final/control y frontier fatal juntos; certificado
global exige fuente final confirmada, request actual y batch no consumido/resuelto.
Selección por step/delegate path/request step/call position, independiente de llegada.
No nuevos permisos tras fatal; sólo outcomes existentes y wrapping ya iniciado pueden
confirmarse. Conserva source/raw/observaciones, child completed y usage calificado.
Reserva independiente de la copia frontier, con crédito de materialización exacto.

Matriz nueva: dos órdenes de llegada siblings; dos órdenes entre nieto y segundo
delegado; approval-drain sustituido sin ACK público/refund; raw admitido posterior
al cierre sin nuevo wrapper; completed child raw X/final Y; Model admitido con usage
partial/estimated sin nueva request/batch; unknown/fence/epoch/replay/opconflict y
mutaciones de selección/frontier; dispatch byte-boundary±1→raw/wrap/fatal sin IO
adicional, error JSON4096 escapado. Entradas trusted sintéticas, Store/CAS real y
roundtrip cada ACK, no prueba de hooks/PIDs/VM/quiescencia viva.

Focales de desarrollo: final10/10 (`focal-7.log`, exit0); históricos focal-3 (8/9,
oráculo nuevo incorrecto: accounting string-key/partial≠full), focal-4 (9/10, captura
de leaf input sin scope proyectado), focal-5 y focal-6 (9/10, boundary escogido antes
de la mayor reserva de dispatch) permanecen rojos. El test final mide **dispatch**
±1; no relabela esos intentos como prueba batch-minimum→cierre universal. El límite
mínimo del batch puede no admitir preparar/dispatch posterior: garantía más amplia
pendiente, no corregida por esta unidad. Gates finales e identidades en REPORT.

Pendiente obligatorio: raw/host fatal, origen root/node, output_failed/exhaustion,
resolución fatal operativa, blocked con fuente intacta/cancel sólo no terminal,
failed terminal legítimo+refund único/fachada/delete/reset y capacidad/counters de
esos cierres. Guards correspondientes cerrados; no general cancel/expire/recovery.
No cambios Writer/ExAgent/Composition/Restore/Scope/Store, ni productor10 habilitado.

Gate seleccionado final: **114/115, exit2**, incluyendo los10 nuevos verdes. Único
fallo: `frame10_closure_control_test.exs:320` usa checkpoint_limit fijo1_714_951 y la
nueva reserva frontier provoca rechazo anterior al dispatch. No se modificó el
oráculo antiguo ni se trata como pase/exclusión. Se devuelve al principal para
autorizar el ajuste causal de ese límite/oráculo o indicar otra integración; no
aceptación del incremento mientras siga rojo. Compile force115WA exit0. Formato,
diff, hashes y liberación en REPORT; documentos actualizados después del test sin
cambio posterior de fuentes runtime.

### Follow-up autorizado del oráculo raw-boundary10 —2026-09-29

Artefactos nuevos: `/tmp/opencode/frame10-fatal-oracle-xlzx8r23/REPORT.md`.
El informe anterior SHA886558db4b3e89bb69c86ced301f4131347368de0d9aa1dc47b6979f5b8aaa0c
y su114/115exit2 permanecen intactos. Autorización puntual en structural-delegation,
sección «Fatal drain parcial recibido; oráculo capacidad autorizado».

Sólo se adapta `frame10_closure_control_test.exs` en el caso raw-byte-boundary, con
helper causal y un caso negativo nuevo. El flujo de referencia crea/claim/step/Model/
batch/prepare/dispatch mediante Store CAS y mide cada prefijo real: JSON+reserva
actual. Se usa el máximo como umbral, ajustando únicamente la longitud decimal del
límite; recibos de anchura fija y namespaces de igual tamaño. No se mutan filas
persistidas para fingir admisión ni se aumenta el límite de producción. Se conservan
encodedraw65536±1, overbound invalid_record/fila intacta y cierre completo de los
aceptados vía wrap/settle/resolve/consume. El límite ORIGINAL1_714_951 confirma
exactamente `record_limit` en begin_effect tool, con call prepared/sin source/raw,
sólo efecto Model confirmado y fila/recibos sin cambios.

Verificación de los bytes sellados: focal18/18 (incluye10 fatal-drain), selected116/116
(mismos115 anteriores más1 caso), ambos exit0; legacy7/8 cuatro pases y86 excluidos
por selector de líneas, exit0. Compile force115WA exit0; formato global/diff y hashes
en REPORT. Ningún archivo runtime ni otro test antiguo cambió; exact-old-test.diff
permite revisar el ajuste aislado. Docs de evidencia posteriores a gates.

Entrega sigue siendo **partial call-fatal drain ONLY**, no cierre de fatal10/R6:
raw/host/root/node, output_failed/exhaustion, blocked/cancel estructural, failed root
legítimo/refund/fachada y su matriz de capacidad permanecen pendientes y cerrados.
Sin productor10/VM/quiescencia viva, FULL rutinario, SQL ni aceptación automática.
## Call-fatal failed closure CAS10 — 2026-09-29, owner; review pendiente

Artifact: `/tmp/opencode/frame10-failed-close-5pbswx2_/REPORT.md`. Baseline de todos
los tracked/untracked no ignorados con contenido/hash antes de editar; missing
registrados. Delta sobre fatal-oracle verde, no sobre Git HEAD ni sustitución del
histórico114/115. Allowlist usada: Frame/Record/Transition/ToolEvidence/
OutputResolution/Continuation, test nuevo y un negativo antiguo causal; docs4.
Budget/Scope/Writer/Store/Composition/Restore/Productor intactos.

Finish CAS10 conserva fatal estructural seleccionado e historia, espera los efectos
admitidos y callbacks wrapping, rechaza preparing/unknown/running y no inicia nuevo
IO. Blocked retiene raw/binding/source/outcomes/observaciones sin fake returns;
cancelled sólo no terminal, completed inmutable, raíz failed con partial confirmado
en nodos existentes. Refund único del claim, incluida pausa/reclaim previa. Get
data-only, delete con cutoff y reset estructural rechazado, sin activar resume10.
Entradas trusted sintéticas: **no certifica PIDs/worker-drain/VM/SQL ni R6**.

Ocho tests nuevos: CAS+roundtrip cada ACK; terminal/get/delete/reset/replay/conflicto/
mutaciones; efecto raw drenado y bloqueado; callbacks ambiguas vs settlement en dos
órdenes; child completed/raw y child sin empezar; pausa/reclaim/prefijo/typed retry/
qualified accounting; Model admitido drenado sin batch/output callback; nested dos
fatales+grandchild; capacidad real máximo de todos los prefijos, ±1 antes dispatch,
error portable JSON4096 escapado y receipt IDs512 escapados. Un test agrupa orden y
preparing; conteo ocho, no sumar reruns. El antiguo rechazo universal finish en
fatal_drain ahora confirma cierre+raw inmutable y rechaza borrar raw. Los demás
negativos fatal/recovery/unknown siguen intactos.

Primer selected117/122 fue rojo: cuatro reservas aditivas de destinos mutuamente
excluyentes excedían cotas y un viejo rechazo finish ya no aplicaba. Corrección:
max(success projections, cancellation copies), recibos/frontier independientes y
datos reales siempre cobrados. No límites ampliados ni fixtures reducidas. Logs
conservan también error de campo de test Text y expected-revision de create; no
errores de producto escondidos. Focal posterior33/33 y nuevos8/8. Gate final150/150
(116 subset previo+8 nuevos+26 source/causal controls),106.8s,exit0; legacy4/4 con
86 excluidos por ubicación,1.5s,exit0. Compile force115 módulos WA, formato global
y git diff --check exit0. Sello8 fuentes/tests pre-gates cotejado después. Comandos
exactos/logs en REPORT; no FULL rutinario. Las repeticiones no son casos adicionales.

Pendientes explícitos: review independiente acumulada fatal drain+closure y probes
padre; raw/host/root/node fatal, exhaustion/output_failed/retention-fatal,
uncertain/recovery/general cancel/expire, public Composition.resume10, productor10
y VM. No aceptación automática fatal10 completo/producto/R6.

## Output exhaustion CAS10 — 2026-09-29, revisión pendiente

Frente acotado sobre callfatal/failed closure recibido. OutputResolution1 conserva
claves/decision retry: agotamiento actual certificado añade el Retry terminal una
vez sin used++, falla nodo y selecciona frontier atómicamente; delegado conserva raw
canónico sin wrapper nuevo. No salida de callbacks ni efectos se reconstruye al decode.
Sólo ese último intento se excluye de permisos consumidos; antes del límite mantiene
retry normal, >límite/corrupción/fallo genérico rechazan. Orden estructural CALL/NODE;
root finish/refund y fachada get reutilizados sin matemática/ledger nuevos.

Capacidad: alternativa failed incluye diagnóstico/historia/atestación pendiente y raw
delegado residual; source se mide antes del fatal, no tras el sink. Descriptor65536
o preimagen histórica exacta, reason4096 con codificación/escape previo, IDs/stubs
conocidos. Frontier y control final siguen reservados separadamente. Childfailed
retira sólo slots parentales que no pueden materializarse; raw/partials permanecen.
Recibo terminal propio gastado una vez; no préstamo entre siblings o doble crédito.

Artefactos nuevos `/tmp/opencode/frame10-output-exhaustion-resume-ccw8mexa/`:
baseline contenido+hash antes de cambios, REPORT por hitos, logs rojos y verdes,
delta exacto y sellos finales. Original informe/probe negativo g7ghhz5t intacto;
sus3 pases históricos verificaban guards cerrados, **no la feature nueva**.
Cambios causales de tests antiguos sólo dos negativos de agotamiento en
frame10_output_cas_test.exs, ahora positivos con contrapruebas y success independiente;
resto legacy/unsupported intacto.

Gates finales sobre8 fuentes runtime/tests selladas: compile forzado117WA exit0;
164 seleccionados/438.9s exit0 (incluyen9 nuevos),166 legacy/209.8s exit0 con86
excluidos por ubicación; formato global y diff-check exit0. WA/maxcases48/seed37556,
timeout ExUnit600000, shell1200000/600000, OTP29/Elixir1.20 offline/test y ROOT/_build.
Legacy:4 localizaciones previas más archivos completos de output retry/success
restore; no repetir ni sumar focales como casos adicionales. Runtime/tests hashes
idénticos después de todos los gates; esta prosa de evidencia se añadió después.

Umbrales fuente finales: mixed1213099 outcome y step-only234759 outcome (el segundo
normaliza anchura decimal del límite usando otro prefijo CAS real). Exact/+1 cierran,
−1 rechaza en esa fuente antes de atestación, con fila intacta. Callfatal anterior
conserva1378383/±1 y child1402911/±1, incluidos en164. Históricos rojos: reserva
inicial sumaba alternativas excluyentes; descriptor reuse solo no lo corregía;
primer oráculo source−1 mezclaba longitudes de namespace; grammar running-prefix
necesitaba admitir step failed únicamente durante fatal-drain. Logs preservados.

Entradas trusted sintéticas con Store ETS/CAS y Record encode/decode por ACK, no hooks
vivos, VM/productor10, SQL ni aceptación de R6. Requiere review independiente y probes
padre; raw/host/root fatal generales, retention-fatal y recovery siguen fuera.
# P1 exhaustion capacity: matriz ampliada entregada (2026-09-29, review pendiente)

Informe nuevo `/tmp/opencode/frame10-exhaustion-matrix-60bpPK5e/REPORT.md`, baseline
CONTENT455 al retomar; informe anterior d5f3a5bb… y todos originales/rojos intactos.
Record no cambió desde candidata refinada. Añadidos test/support fixture y test nuevo
con10casos: ocho variantes de fuente realCAS±1 y dos negativos. Límites tool256,
4096,65536; descriptores small/max65536 con/sin preimagen;0/1/3retries y1/2/3nodes,
0/1/3/6plainsiblings, successplain/typedcompleted, settled materializado, Unicode/
control JSON anidado, output stubs y512IDs/receipts. Todas las fases terminales
comprueban coste JSON+reserva no creciente y crédito propio sin mutar siblings;
used=N y N+1Retry, scope/effects/nilusage preservados.

Fuentes ocho variantes:365872,868259,863377,1895531,1681593,1790542,878025,5149730,
siempre antesfatal, no sinkthreshold. Fuente original868234 exact/+1 cierran;
−1 rechaza outcome antes ACK; sink866148 sólo diagnóstico. Ajuste oracle autorizado
exclusivamente en COPIA línea87 roomy Record.max_bytes() y etiqueta92; oracle.diff
documenta dos líneas, assertions intactas. Copia2/2verde, original histórico rojo.
La primera edición de esa copia fue autoformateada por tooling; se preserva como
diagnóstico, no como diff autorizado. Copia final reconstruida byte-exacta desde
original con sólo dos sustituciones, auditada y reejecutada2/2/4.0s exit0. Esa última
ejecución se solapa con oracle/legacy, no añade casos independientes.

Gates finales disjuntos10matrix/171.3s +69selected/323.0s +10oracle/legacy/10.6s,
246location-excluded; todos exit0. Los dos probes repiten el negativo heredado:
89 ejecuciones no son89 obligaciones independientes nuevas. Compile118WA, formato
global/diff0. Selected preserva callfatal1378383 y child1402911 ±1, typed/plain,
control4116/receipt, accountingnil≠0; legacy location seleccionados6, no FULL164.

Rojos nuevos preservados: primer fixture omitía la copia parental propia al afirmar
inmutabilidad y usaba success content distinto del canónico `ok`; corregido fixture,
sin runtime. Prueba toolbound0 rechazada (contrato positivo); toolbound1 admitía fuente
pero rechazaba raw terminal por guard de tamaño Frame.batch_bindings10?, no capacidad.
Se conserva negativo explícito1, y variante positiva256 con raw<=bound verificado.
Último selected preliminar51/52 rojo conserva ese fallo; no se relabela como verde.

Sin cambio adicional runtime/oldtests/guards ni límite de producción; no nuevos
orígenes fatal, recovery o productor10. Real Store ETS/CAS/roundtrip con inputs trusted,
no callback/worker/VM/SQL/proveedor/aceptación R6. Reviewer original y padre revalidarán.

## Hito anterior: candidata bloqueada (2026-09-29, histórico)

Evidencia de esta unidad:
`/tmp/opencode/frame10-exhaustion-capacity-fix-slV6LFp7/REPORT.md`.
Baseline CONTENT455 archivos antes de cambios; único runtime modificado Record.
Original boundary byte-idéntico: baseline1/2 exit2 por P1; candidata refinada1/2
exit2 ahora en su control roomy, **no verde reinterpretado**. Fuente868234:
−1 rechaza outcome sin mutar revisión10, exact/+1 terminan failed. Sink866148
menor que la fuente: no financia otra admisión. Ajuste exclusivo solicitado al
principal; no se modificó ese test ni otros tests antiguos.

Primera candidata sumaba toda exhaustion independientemente: probe±1 corregido,
pero pause/reclaim existente rechazado por8MiB. Rojo preservado. Refinada calcula
`max(S + sum(max(E_i-s_i,0)), F + sum(max(E_i-f_i,0)))`, cubriendo todos los
subconjuntos con slots propios exclusivamente. Focal refinado10/11: nueve tests
exhaustion existentes y negativo del probe pasan; falla sólo control roomy original.
No matriz permanente nueva todavía, no FULL/VM/productor/SQL/live/R6 ni aceptación.
