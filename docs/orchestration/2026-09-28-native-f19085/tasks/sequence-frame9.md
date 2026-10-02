# Mandato aprobado: secuenciador durable Frame9

Researcher ses_f16ebe088ffeZilejsB5AdssPR terminó contrato sólo lectura. Padre
contrastó constructor, Writer singleton, Transition step_output terminal incondicional
y OutputResolution.evidence106–123 global. Se AUTORIZA unidad siguiente, sin cierreR6.
N pasos mismo intento (oráculo A→B→C), un único ejecutor durable reutilizando loop,
Scope/Writer/CAS. Sin resume activo multileaf, raw/uncertain/approval/delegación/router/
paralelo/SQL/live. No modo efímero alternativo ni nuevo motor/ledger/token/Store.

## Frame9 exacto / compatibilidad
Nuevas raíces frame_version9. Mismas claves raíz8: frame_version,kind,cursor,run_id,
binding,input,scope,children,output_resolutions,tool_batches,authority. kind sequence.
Sin next_index/active_step/outputs duplicados. Child igual: parent_run_id, link
{kind:step,step_id,index,input}, definition,policy,model_ref,output_ref,frame,snapshot,
status,result,result_omitted. Hoja Frame3 sin hijos; status running/completed.
Children ordenados link.index forman prefijo exacto0..k-1 del binding N, k<=N;
IDs hoja/step únicos y enlaces/refs corresponden binding.steps[index].
- empty: k0, sin operaciones/evidencia hoja.
- running:1<=k<=N, anteriores completed y última running.
- between_steps:1<=k<N,todas presentes completed.
- completed:k=N,todas completed; execution completed iff cursor completed en9.
Cancelled/expired/uncertain pueden conservar cursor no terminal. Siguiente k sólo
empty/between; activa k-1 sólo running. Child omitted puede completed, pero NINGUNA
sucesora si predecesora omitida; nil sin marker sí JSON legítimo.
First input sin mapping=root.input; siguiente=resultado portable confirmado anterior.
Mapping normalizado ligado snapshot inicial; no ejecutar mapping desde decoder.
scope.nodes/authority exactos raíz+hojas presentes, todas parentroot, raíz sin IO propio.
Counters locales por hoja, raíz acumulados ledger ancestral; sin doble suma snapshots.

Frame9 validador explícito, no degradar íntegro a singleton7/5. Particionar evidencia
Model/tool/output por leaf PERO cobertura global contra huérfanos run desconocido.
OutputResolution keys siguen requestID host GLOBALMENTE único; callID proveedor puede
repetirse entre hojas/requests. Mantener graph/ToolEvidence relaciones bidireccionales.
Reconocer9 explícito en TODAS ramas productor accounting/partial/reservas/validators,
no reemplazar ==8 por >=8. Captura nuevas9; structural_lifetime conserva7 Y8 previos.
Lectores/lifetimes7/8 intactos, fixtures auténticas sin relabel ni opción pública version.
Retirar lectores sólo tras expiración/eliminación lifetimes + decisión futura explícita.
Singleleaf9 conserva TODOS subsets accepted7/8. N>1 rechaza restore activo ANTES claim/
codecs/callbacks aun sólo A presente: cardinalidad binding, no children presentes.
Completed multi requiere Record.validate+binding/policy exactos, proyección data-only
sin Scope host/codecs/estimadores; omitted conserva error.

## Comandos/transiciones
Sin nuevas operaciones ni envolventes. payload step_input/output/output_resolution/
tool_resolution conserva owner_id,attempt_id,fence,node_id,snapshot,progress.
Worker/claimed/lease/deadline/expiry/CAS/operation digest invariantes actuales.
node_id identifica LA hoja mutante; no basta cualquier child/una hoja cambió.
Raíz snapshot idéntico y resto execution/progress/effects/hojas inmutable salvo delta
autorizado. Version lifetime inmutable; sólo hoja activa para IO/checkpoints/resoluciones.
- step_input sólo empty/between: añadir UNA hoja k request0/running, nodoScope vacío,
  autoridad capturada. Preservar prefijo/resultados/evidencia/ops/batches/retries/floors;
  rootrunning, presupuesto/lease/owner/attempt/fence idénticos. Sin unresolved/omitted.
- step_output intermedio k<N: cierre legítimo hoja actual, sin unresolved, conserva
  model_data/request/step coherentes. Actualiza únicamente su frame/snapshot/status/
  result/omisión y Scope proyección legítima. Rootbetween, executionclaimed.
  active_budget IDÉNTICO, SIN refund/release/reclaim/renovar lease.
- step_output final k=N: rootcompleted, Writer refund desde CLAIM RAÍZ (no pasoB),
  Transition confirm_refund+release completed una vez. Replay receipt sin nuevo refund.
  Condicionar Writer, Transition y chequeo presupuesto; Budget module no requiere cambio.

## Writer/ticket/mapping
Generalizar descriptor derivando paso desde record confirmado; binding antes callbacks.
Ticket único ligado PID/revisión/stepID/index. Ticket o checkpoint pending bloquea
segundo mapping/attach/avance. Attach verifica ticket/PID/rev/agente/input/frontera,
Map.put preserva children, consume ticket ANTES CAS; ACK perdido no reutiliza ticket.
Sólo ACK fresco autoriza loop, receipt replay NO IO. Prewrite failure retirar sólo
nodoScope vacío no comprometido; tras write incierto conservar pending command/token.
Muerte solicitante limpia ticket; owner termina Writer/Scope por monitores existentes.
Secuenciador lee record Writer confirmado después cierre, NO output vivo de run_step.
Mapping puro aridad2 recibe initial y outputs PORTABLES confirmados por stepID;
retorna {:ok,input}|{:error,reason}; excepción/invalid bounded error.
Orden: ACK outputA -> capacidad conocida/deadline -> mappingB -> normalizar/retención/
capacidad exacta -> preparar attachB -> ACK inputB -> admisión+intent -> IO.
Rechequear deadline tras mapping no preemptible. No prometer cero callbacks cuando
inputsize sólo se conoce después mapping. Fatal/omitted/savepending no mapping siguiente.

## API experimental / resultado
Composition.run(definition,input,opts\\[]) durable obligatorio, reusa
ExAgent.run_composition_step/4. Opciones: continuation configWriter obligatoria (kind/
definition derivados host, contradicción rechaza), root_options, step_options mapa
stepID→keyword, observability,trace_context efímeros. IDs/options duplicados/desconocidos
rechazan. step_options NO inyección run_id/execution_scope/parent_context/continuation/
continuation_record/message_history/frames/selections/internal observability operations.
Opciones ordinarias siguen validación loop. Cada hoja historia nueva. Sin resume API nueva.
Proyección ÚNICA ejecución/completed data-only sin modelos vivos:
status completed|failed|cancelled, output portable|null, model:nil,messages:[],new_messages:[],
run_id=rootid|null,root_run_id=rootid|null,parent_run_id:nil,steps ordenados,
usage cualificado,usage_status complete|partial,request_count,tool_calls,cost_cents|null,
cost_status known|unknown,continuation ref|null,continuation_checkpoint token|null,
error_step_id|null,error_phase open|mapping|prepare|execute|checkpoint|null.
Cada step: id,index,run_id|null,status not_started|running|completed,input confirmado|null,
output confirmado|null,output_omitted marker|null,messages historia confirmada decoded.
Success {:ok,result} output últimochild; error operacional {:error,RunError{reason bounded,
partial:result}} output raíznil. Statussteps progreso CONFIRMADO no relabel failed ficticio.
Token/retention metadata existente conservado. Totales ledger CONFIRMADO sin sumar hojas;
observado no confirmado => partial (subtotal NO actividad completa), rejected usage
ToolEvidence conservado (ScopeLedger.usage solo no expresa rechazo). Retención público
usa mecanismos existentes sin exportar modelos/credenciales ni payload ilimitado nuevo.

## Fallos/ownership/C7/tracing
Sin nuevo failed cursor/command: persistir último checkpoint, no excepción mapping.
Mapping/prepB falla: Acompleted/rootbetween/executionclaimed. B postinput falla:
rootrunning/Brunning+evidencia. ACK incierto: row posible nueva +token exacto.
Intent sin outcome uncertain real; intermedio omitted between y bloquea sucesor;
final omitted completed pero público error. No cancel/refund automático para fingir final.
Recover tras lease existente: unresolved→uncertain, resto ready/expired, reserva
abandonada SIN refund. Ready NO ejecutable multileaf. Retrycheckpoint sólo Store sin mapping.
Composition Writer.pause rechaza explícito ANTES falsa pausa, sin resultado paused;
ask no callable/sucesor, siblings ya observados conservados. Delegated attach bloqueado.
Root authority inmutable, add leaf bajo root; B no hereda counters/floors particularesA.
Deadline min raíz/hoja/TTL/lease/budget intento, sin reset por paso. Root estimator nil/2,
no Model raíz ficticio. Scope+Writer único claim; resultado/token antes cleanup en after,
errores open/claim incluidos; workers propios DOWN. Span root run sin Model ficticio,
hojas contexto efímero, IDs root/attempt del claim, no persistir trace context/sumar métricas.

## Reservas y gates
Proyectar record COMPLETO antes attach/effect con prefijo/copias/autoridad/receipt/
cleanup, command_capacity Transition real. Mantener reservas8 también9.255steps/binding
65536B,256effects incluye hojas sinModel/retry slots,1024receipts/reservas,J8MiB+
cleanup/token. NO reducir reservas completed para hacer caber255: constructor no promete
completar255 bajo todo journal. Medir−1/exacto/+1 comandos outputA/inputB/intentB/token.
Matriz A→B→C texto/typed/tools/retries/callID repetido; outputresolution partición+huérfanos;
mapping IDs/default/nil/omitted; intermediate owner/fence/lease/budget invariantes y
terminal refund replay; ACKbefore/after output/input/intent, token sóloStore; ticket
race1ganador/no doble mapping; corrupción prefijo/índices/authority/input/effects/attests/
terminal precoz decode+CAS; VM intermedios/completed data-only y N>1 aunA solo reject;
kill mapping/afterA/inputB/ModelB ownedDOWN/recovery sin replay/refund; cuotasA bloqueaB,
deny/ask/deadline/counters/accounting parcial; mapping error/oversize; legacy7/8 lifetime
y singleton9 accepted-subsets íntegros, raws/uncertain/approval/delegación negativos.

## Allowlist y entrega
ROOT/build owner exclusivo, padre status/memoria. Runtime: coordination/composition.ex,
lib/exagent.ex, continuation/{writer,frame,transition,record,tool_evidence,
composition_restore,output_resolution}.ex. OutputResolution sólo partición+coverage.
NO Authority/ScopeLedger/ExecutionScope/Budget/Store/StructuralSnapshot/MCP/OTel cambios
sin bloqueo causal al padre. Tests secuencia nuevos+supportVM, y expectativas causales
version/terminalidad en structural_root_persistence,composition_step_persistence,
tool_evidence_producer,composition_evidence_contract; otros tests sólo tras caso causal.
Docs4 design/changelog/roadmap/r6-implementation contrato antes estabilizar.
Baseline/REPORT temprano recuperable único /tmp/opencode, hash/delta/logs/exits/fallos
preservados; WIP no reset. Focales/compileforceWA/formato/diff/FULLofflineWA48seed37556,
environment.md buildROOT absoluto timeout>=1200000. No paid/SQL/cloud/infra/global/
commits/bump/publicar. No fresh acceptance hasta review y padre; liberar procesos/ROOT
explícitamente al entregar, no completed con FULL activo. Ante seam imposible bloquear,
no inventar datos/relajar formato/expandir allowlist silenciosamente.

## Cambio de ejecución tras intento sin entrega

Owner ses_f16e08477ffev68BeeJBJvUqnS TERMINADO sin implementación/gates ni bloqueo
causal demostrado. REPORT /tmp/opencode/sequence-frame9-f16e0847/REPORT.md SHA
b183f5c942538dd612847199f67497f11a3edde0299661b25322c881996dd8b4 cotejado padre;
380archivos producto baseline intactos (memoria excluida), draft externo NO candidato.
ROOT/build libre. No repetir investigación ni reutilizar draft sin revisión.

Se divide EJECUCIÓN del mismo contrato, no producto/modos ni alcance final:
1. Worker fresco vertical persistencia/transiciones/productor9, Writer descriptor/
   attach/finish/tickets, evidencia leaf/global y compatibilidad. Pruebas reales
   A→B→C por seams existentes bajo un Writer/Scope, guards activos multileaf y
   completed data-only. API pública Composition.run/proyección global se entrega
   en fase2; si completed projection común requiere helper, implementar interno mínimo
   sin fingir API lista. Docs explican parcial, sin aceptación secuenciador.
2. Tras revisión padre, worker implementa Composition.run/resultado/cleanup/tracing y
   completa matriz/end-to-end/full final integrado. No nuevo motor ni duplicación.
Fase1 gates focales/compile/formato/diff, NO FULL hasta integrar API fase2 salvo causa.
Baseline temprano propio referencia anterior; conservar cambios probados al entregar,
no deshacer todo por un patch context mismatch. Si tamaño/contexto limita entregar
hito parcial verificado con pending exactos, no restaurar baseline sin necesidad.
Toda fase respeta schema/allowlist/autoridad/compatibilidad del mandato anterior.

## Hito preparatorio retenido y continuación fresca

Worker ses_f16d8c612ffexlyE34pl0m2iC1 TERMINADO parcial por presupuesto/contexto,
sin bloqueo causal. Padre leyó /tmp/opencode/sequence-frame9-f16d8c61/REPORT.md SHA
728ddedb255d4d701d50bffeff59fe79f879f84ce8ee64faad8b6914896300d2 cotejado,
worker-manifest8/8 intacto. Runtime Frame validador9+OutputResolution leaf/global;
2tests nuevos31casos+docs4. Owner523focales incluye31,compile107/formato/diff0.
ROOT/build libres; NO fase1 completada ni aceptación, producer aún8 y Record no9.
Preservar delta8 probado, no rollback/repetir investigación. Proyección combinada test
evidence NO Record válido ni A→B→C; no atribuir autenticidad secuencia a esa fixture.
Worker fresco debe completar Writer/Transition/Record/ToolEvidence/discriminantes/
restore +seams realesA→B→C. Leer pendientes REPORT118–139 y mandato.
Economía: primero vertical mínima real con tests focales discriminantes (no repetir
523 en cada subhito); después matriz fase1 y compile/formato/diff. FULL queda fase2.
Artefactos nuevo directorio con baseline parcial actual y referencia al original,
delta acumulado recuperable; docs prosa breve al hito, no gastar entrega sólo en docs.
No descartar objetivo por patchcontext: patches pequeños/releer contexto y seguir.

## Vertical real recibida; integración API y matriz pendiente

Worker ses_f16bf3ff7ffeayJNWPOMncd55d TERMINADO, ROOT/build liberados. Padre leyó
/tmp/opencode/sequence-frame9-f16bf3ff/REPORT.md SHA
a8127711b609cf0460fc574094a427c6c42882d72a4c821650c048facb55c1cd cotejado,
cumulative-manifest19/19 intacto. Delta16 sobre parcial y19acumulado. RealA→B→C
con mismoWriter/Scope/CAS, producer9, between/refund terminal, tickets/mapping,
guards/compatibilidad;23tests nuevos+31retenidos incluidos546focales/549.1s owner,
compile107/formato/diff0. No FULL/aceptación ni matriz completa.
Se continúa FASE2 API/proyección/cleanup/tracing integrando también pendientesfase1,
sin aceptación separada artificial. Leer REPORT61–77: exact±1 outputA/inputB/intentB/
token, ticket crossPID/requesterdeath mapping, kills afterA/inputB/ModelB ownedDOWN/
recovery budget sinrefund, mapping oversize/deadline/nil, denied/partialusage/orphans
en secuencia REAL y writer lifetime8 auténtico (no relabel fixture). Tests actuales
estructurales proyectados no sustituyen estos oráculos reales.
Mandato API/resultados arriba SIN cambios. Un worker fresco exclusiveROOT implementa
Composition.run/proyección común completed/result parcial/tracing y completa pruebas
pendientes; focales pequeñas por hito, gate amplio+FULL sólo identidad integrada final.
No repetir546antes cada feature ni rehacer productor9 que ya corre. Baseline nuevo
referencia acumulado19 y original; conservar historia/contrato/WIP. Si bloqueo causal
allowlist/projection/host API, evidencia al padre antes ampliar. Fresh review total luego.

## Corte de cuota fase2 y reanudación solicitada

ses_f168b0f9bffeT4znovKZuzKdLT ERROR usage limit reached. Usuario explícitamente
pide continuar. Padre verifica ningún BEAM propio/build/FULL activo, sólo3ajenos;
384archivos producto coinciden con final-manifest fase1, sin cambios fase2 observados.
No directorio artefactos fase2 identificado por patrones de sesión/fase2/API.
Se intenta reanudar MISMA sesión una vez, sin cambiar modelo ni eludir cuota; si
límite persiste, informar bloqueo real y no multiplicar agentes/reintentos.
Mandato fase2/API y matriz pendiente intacto, baseline fase1 preservado, no reiniciar.

## API recibida y cierre de matriz autorizado

Worker ses_f168b0f9bffeT4znovKZuzKdLT TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-frame9-phase2-f168b0f9/REPORT.md SHA
ecf6ace5c471aa9779c8163d88ead04d0839bf28a3282596c40c7760ad42cd9c cotejado,
cumulative24/24 fuentes intactas. API/proyección/cleanup/tracing implementados;
owner576focales/compile107/formato/diff0. FULL1651/1652,28excluidos,745.2s exit2
con único fallo expectation de ausencia Composition.run. FULL fallido permanece.
Padre inspecciona test/exagent/composition_definition_test.exs:40–41 y AUTORIZA
únicamente cambiar refute function_exported?(Composition,:run,3) por assert;
NO cambiar refute resume/2 ni otras negativas. Beneficio causal: API ya aprobada.
Worker fresco cierre: matriz REAL exact−1/exact/+1 outputA/inputB/intentB/token,
cleanup+receipt reserves, preservando oráculos auténticos y sin relajaciones.
No repetir investigación/API completa ni576por cada caso. Focales primero; FULL
final integrado tras resolver expectativa y matriz, luego revisión fresca acumulada.
Baseline nuevo propio, historial inmutable, propiedad ROOT/build/docs4 exclusiva;
padre memoria/status. No aceptación de secuenciador ni R6 hasta review y probes.

## Matriz recibida, revisión acumulada pendiente

ses_f1651f1d0ffeNsrcyqLTsMLi7U TERMINADO/liberado. REPORT
/tmp/opencode/sequence-frame9-boundaries-f1651f1d/REPORT.md SHA
5da2073b3b4be4f77702dc24e754ee5586bf612723c954134b78744ae34374c6 leído/cotejado;
padre26/26hashes y colaFULL+exit0 cotejados:1664passed/28excluded/880.9s.
Owner112focales/compile107/formato/diff0; delta6 sólo docs4+oldassert+12tests matriz,
runtime intacto. Tokens exact8MiB llegan a CAS record_limit: NO commit sobredimensionado.
Receipt+1 predecessor inadmisible rechaza antes, cierre reservado exacto sí funciona.
FULLfallido previo intacto. Intención reviewer fresco acumulado26, source-only edits
prohibidos; ROOT/build exclusivo review, padre memoria/status/lectura. Revisar contrato
total y oráculos propios más focales discriminantes, no FULL repetido sin causa.
Especial atención a multi-leaf huérfanos/contadores, lifetime7/8, terminal-only refund,
claims/tickets/ACK-beforeIO, opciones API/errores/proyección, cleanup/capacity/VM.
No aceptación secuenciador hasta revisión fresca y verificación focal padre.

## Revisión: dos P2, aceptación retenida

Reviewer ses_f162c6b48ffeNAxPaQ5CaaH7MN TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-review-unique/REPORT.md SHA
9b0ac3bc715ba4861055a403f604c3ad0ea14fa1306165d25f827c8b381a0540 cotejado;
probe adversarial_test.exs SHA c34b1227c8acde262df702b36af9c78114937826e6dc9218f0dc794cb47518dc.
243focales existentes pasan;5propios3pasan2reproducen P2.26fuentes intactas reviewer.
P2a Writer descriptor colapsa admisión Scope/quota/capacidad/deadline a invalidinput;
API devuelve mapping en vez prepare y oculta razón original. Mapping real fallido
debe seguir mapping; no invocar B callback/IO ante admisión rechazada.
P2b caller trap_exit true +Writer DOWN duranteModelB: confirmed_record/pending
devuelven error tuple tratado como map, Access.get FunctionClauseError en error_phase.
Debe devolver RunError operativo sin inventar checkpoint/token ni refund/cancel/replay.
Preservar muerte enlazada/cleanup del caller normal y Store intacto/noCIO.
Intención worker corrección causal acotada Writer/Composition (+ExAgent sólo causal),
tests permanentes secuencia+docs4. Repro rojo antes/parches mínimos/verde después;
reusar5probes originales sin editarlos en labelnuevo. FULL final tras fixes runtime.
No nuevas modalidades/restore/format ni tocar scopes/ledger/store/OTel. Revisión
independiente posterior de fixes y probes padre antes aceptación.

## Fixes entregados; oráculo contradictorio identificado

Worker ses_f161dcf80ffe8GfWNzvLC0VVj1 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-fix-unique/REPORT.md SHA
1903a2f0d7e438c0de7778c7588d06ccfa72b7ff1dcfe7758b8e88aa09f686e1 cotejado;
26/26fuentes actuales y FULLlog/exit0 verificados1673/28/885.2s. Delta8runtime2+
tests2+docs4. Owner62focales,compile107/formato/diff0;9regresiones permanentes.
Original5probes antes3/5 después4/5. Padre inspecciona original línea200: exige
invalid_composition_input, contradice conservar usage_limit_exceeded/request_limit/1;
línea203 sí espera prepare. AUTORIZADO reviewer crear COPIA en directorio NUEVO
con ÚNICO cambio de esa expectativa al motivo exacto. Original/logs/hash intactos,
diff prueba explícito, no reportar original5verde. Revalidar5copia y fixes fuentes
incluyendo open/confirmed/pending-loss, admisión pre/postmapping y cleanup.
Reviewer original independiente puede continuar sólo review fixes; ROOT/build
exclusivo sin editar producto. Aceptación aún retenida hasta review y probes padre.

## Aceptación acotada secuencia durable

Reviewer fixes TERMINADO favorable: REPORT
/tmp/opencode/sequence-fix-review-unique/REPORT.md SHA
8472c7a03544a8e3c206172e16aa5e17c9ea4cf0d88eab197de7cf3f55e83bd0 cotejado padre.
62focales+5probes copia corregida+2nuevos terminal-loss pasan; no P1/P2 reproducidos.
Padre26/26sourcehashes y sustitución única exacta del probe cotejados. Rerun padre
parent-final-seven-f19085 con runner inspeccionado: mismos7probes,7pass/3.3s/exit0,
sin contar como7casos distintos adicionales. OwnerFULL1673/28/885.2s identidad sellada.
Se ACEPTA vertical offline Composition.run secuencia durable Npasos con único Scope/
Writer/claim/budget, mapping confirmado y proyección data-only completed, lifetime7/8
y singleleaf9 según límites contractuales. No active multileaf restore, C7compositions,
rawuncertain/delegación/router/parallels/R6general/producción ni publicación.
Histórico originalprobes4/5 y FULL1651/1652 intactos; no reinterpretados como verdes.
Intención receipt docs5 (design/changelog/roadmap/r6-implementation/status) únicamente
incluyendo evidencia MCPSDK aceptada en task separada; no integrar harness ni runtime.
Research siguiente R6 sólo lectura propone unidad recuperación dependiente/contrato
sin activar implementación ni repetir auditoría R0. Ownership separado de docs writer.

Receipt documental aceptado: ses_f15fb2c8dffeWPZ3fuvPBklQd1 terminó/liberó docs5.
Padre leyó REPORT /tmp/opencode/receipt-sequence-unique/REPORT.md SHA
90fc409efedcdbc1c86e815a7a8f7b8bf97f7bdc92d20f098ec67ddefbcaa59e y diff completo
441líneas SHA9975d5f597e4cd81da4ad9ee98e79cf8433e84021b3cf732fedbc92b1083aa37;
cotejó5hashes y git diff --check exit0. Prosa únicamente sin nuevos gatesruntime.
Secuencia+SDKinterop consolidada con históricos/exclusiones intactos. Observación
pendiente limpieza histórica status: frases antiguas C7pendiente no deben confundirse
con recepción frameworkR5 superior; no reabrir ni fingir C7composiciones aceptado.
