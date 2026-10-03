# C7 en secuencia — dirección aprobada, contrato final pendiente

Researcher ses_f1543ed1fffeoUXKt6gtEqUyjR sólolectura propone vertical útil
Acompleted→Bbatch totalmente ask→pausaraíz durable→decisioneshost→resumeB→C.
Padre contrastó Transition.reduce_command135–169 y Writer.pause1100–1153: no basta
quitar guard; reduce_commandRecord2 oculta dispatch especialdecide y padreleaf no
equivale delegación. Aprobar dirección no habilita implementación hasta detalles.

## Decisiones padre

Primer subset todo-pending incluyendo múltiples approvals, sin efectos/observaciones/
contribuciones/resolution del batch actual, correspondencia exacta calls↔approvals.
Prefijo completed puede tener tools/retries aceptados; propia activa sin mixedcontrol/
raw/retryplan/delegación/outputtoolmezclado ni historia propia insegura. No activebatch
general como prerequisito falso. No reconstruir control retry/error desde status.
Mantener Frame9/rootcursor running/step running; execution pending representa pausa.
Extensión EXPLÍCITA experimental Record2 estados/claves/validacióncrossapproval;
viejos lectores rechazan nuevasfilasC7, compatibilidaddireccional documentada.
Resultado paused/halt sinC; denyterminal, approve no claim/IO; explícito decidehost
y nuevo resumeclaim, recoveradmin sólo claimvencido. MCPprincipalbinding separado.
Pausa raíz refundúnico desde iniciointentocompleto; humanwait sin activebudget pero
TTL/deadline no se extienden; claim reserva saldo, finalCrefund. Crashfinitoagotado.
No paused persistido child ni ledger duplicado ni ApprovalWriter paralelo.

## Seams causales / allowlist propuesta

Writer.tool_resolution1190–1240 bloquea antespause porque pending carece de effect;
resolver control pendiente sin fabricar resoluciónfinal. Writer.pause raíz approvals
y snapshotestructural/budget; Record2 actualmente rechaza pending/denied/approvals.
TransitionRecord2 pause/decide dispatch correcto +inmutabilidad estructura/accounting.
Composition haltpaused/projection; CompositionRestore approvedpending boundary
selecciónactiva tras validaciónGLOBAL. HelperScope cerrado ya compatible con running.
Runtime principales propuestos Writer/Record/Transition/CompositionRestore/Composition;
Frame/ExAgent/ToolEvidence sólo seam causal justificado. NO Budget/ScopeLedger/Authority/
ExecutionScope/Store/Approval ni nuevo formato sin demostrar necesidad alpadre.

## Matriz para mandato posterior

VMreal pausa B con Aeffectsuna vez;2decisions partialpending→ready/deny yCASopactor
binding exact;2resumers1claim callbacksóloganador;ACK pause/decide/claim/intentB/
outputB/inputC conreplaytokensStoreonly;TTL/lease/lateACKexpiry noIO; política/defs/
schema/effectiveargs/modelbinding/currentdeny;prefixhistoricalcallbacks explosivos;
counts/batchreserves no readmisión; mixed/rejected/raw/retry/delegation negatives;
finitebudgetpauserefundo/espera/nuevoclaim/final único/crashabandonado;uncertain sinreplay;
±1pause/decidemaxactor/claim/intent/outcome/inputC/token+cancelreservas;orphan/mutation/
requestedrevisionfalse/prefixauthorityaccounting/globalhistory;regresión7/8/single9/
completeddataonly. Pruebas existentes son antecedentes, no aceptación nueva.

## Aclaraciones pendientes antes despacho

Sellar validación/evolución estados exacta y API resultado paused: paused_root/steps,
output/token/approvalref, denied inspection, pending resume rechazo antescallbacks.
Resolver authority lógica ACTIVA vs attemptdeadline persistido a través de humanwait;
no eludir deadlinesantiguos ni conservar accidentallease como logicalbudget.
Definir tool_resolution pending no-op seguro y criterios allpending antesefectos,
fuentesrequestedrevision y freshbatch/noinventarcontrol; detallar allowlistconditional.
Researcher continúa sólolectura, docsreceipt terminado pendiente recepciónpadre.

## Mandato sellado e implementación autorizada 2026-09-29

Aclaración researcher TERMINADA. Receipt recuperación docs5 aceptado/liberado padre.
Se APRUEBA siguiente contrato sin nueva versión Frame ni formato Approval:

### Resultado / administración

run/resume pausaACK→{:ok,result}: rootstatus paused/outputnil/runIDsraízoriginal/
attemptúltimoconfirmado, Acompleted/Bproyectadopaused/Cnotstarted, continuationref
revisiónpauseACK, continuation_checkpointnil, error_step_id/error_phase nil. Usage/
counters/cost exactamente projectionledger. Persistido B sigue running; noapproval_ref
ni duplicar approvals en resultado. Continuation.get descubre IDs/hash/revisión,
Continuation.decide persiste decisión; aprobar NOclaim/IO. Últimoapprove ready;
partialapprove pending; denyterminal. Resume pending/denied→composition_not_ready/open
sinclaim/Scope/codec/on_writer/observabilityejecución; partialrootfailed y B puede
proyectarpaused desde baselinepending. Denied lectura sóloContinuation.get, no nuevo
successinspection. Completed conserva dataonly. Pausa sinACK→RunError checkpointB,
últimoconfirmado+tokenREAL si existe, nunca pausedanticipado/revisiónfutura. Token
retry sólo Store, no autoreanudación. execute_steps haltpaused antes successgeneral.

### Frontera y evidencia

Record2/Frame9/rootrunning/últimaB running cursorbatch con Modelresponseconfirmada;
primerbatchpropio sin historia toolprevia/retryplan/outputresolution/delegación.
Calls normales funcionales IDs únicos, reservedbatch exactcalls. Cero toolintents/
outcomes/observations/contributions para batchactual, resolutionnil, controles todos
{false,nil}, settle_errornil. Biyectivo callsactuales↔bindings nuevos s.pending;
ningún efectoGLOBAL unresolved; prefijo íntegro. Args approval EFECTIVOS posthook,
no igualar argsoriginalModel: approval_matches? valida reproducción antesintent.
ToolEvidence formato existente suficiente; no inventar resoluciónfinal del pending.
Writer.tool_resolution no-op:ok SINwrite sólo frontera exacta antes hashes/control;
significa controlfinal inexistente, no resuelto. Writer.pause REVALIDA otra vez.

CONCURRENCIA EXPLÍCITA: async_stream admite/ejecuta cada tool independientemente.
Certificar allpending DESPUÉSrecoger resultados y ANTESpause. Si siblingallow ejecutó,
mixedfuera subset, failclosed conserva efectos/control/errors, NOpause/refund. No
prometer barrera preadmisiónatómica ni noIOsiblings para batchmixto. Siblinguncertain/
muerto/rejectedaccounting jamás pausaquiescente ni inventar outcomes.

### Persistencia/transiciones

Pause usa runtime/snapshotRAÍZ/effects EXACTAMENTE checkpointbatch confirmado; no
recaptureleaf/frame/statuspaused, no snapshotB en raíz (StructuralSnapshotrev0).
Sólo añade approvals+Budget.refund(elapsedintentocompleto), reducer claimed→pending,
releaseowner/lease/fence. Decide modifica SÓLO1decision/estado pending→pending/ready/
denied, runtime/snapshot/budget/restoapprovals idénticos. Claim ownership/reservasaldo,
runtime/approvals intactos; toolintent/outcome/resolution normales; outputBintermedio
sinrefund y finalCrefundraíz. Approval.new/hash reutilizados, requested_revision
oldrevision+1, anterioresbyteidénticos; sólodecide cambiadécision, identidadbindinghash
inmutables. Requestedrevision nofutura y respaldada receiptpause misma revisión/lifetime
(commit añade receipt antesencode). Coverage toolseleccionado/schema/run/request/call
exacta global; no basta requestexistente. Globalvalidity≠restoreadmissibility: filas
postclaim/efectosparciales/recover conapprovals pueden ser válidas pero norestaurables.
Record2 approvals opcional exactkeys, pending/denied sólo9, reutilizar approvals?/1.
Mantener evidence/ledger/prefix/authority exactos. TransitionRecord2 enruta pause al
reducerexistente y decide alMISMOdecide/4 (no reduce4), luego guardsstructuralesruntime/
snapshot exactos +budget/approvalsmonotonic/globalvalidation/fence existentes.
Compatibilidad experimental DIRECCIONAL: lectores viejos rechazan filas nuevasC7,
sin migración ni ampliar antiguosdeadlines. Documentar beneficio/alternativas/impacto.

### Restore / tiempo / autoridad

Readyaprobado clasifica por evidencia, no approvals vacías. Sóloactiva primerbatch
todoaprobado sin efectos propios, mismo loop batch sin controlrestore resueltoficticio.
Approvals históricas siguen inmutables y NO bloquean sufijobetween/input/terminal seguro;
globalvalidator delante de selecciónlocal. No readmitir/reservar batch: check_reserved
ya existente. Currentdeny prevalece sobreapprove, binding/policy/model/schema exactos.
Pausaraízrefund desdeinicioACKintentocompleto incluyeA/B/preparación; espera humana
no consume activebudget, sí TTL/logicaldeadline. Nuevoclaim reserva saldo NOlímiteoriginal.
ACKpause perdido token sólopersistencia, delay refund descontado porStore; crashfinito
abandonado agotado. Root/leaflogicalauthority actuales ya separan lease/budget (ExAgent
580–594/Scope1342–1356/Authoritycapture); no modificar esosmódulos ni reinterpretar
filasviejas. Prueba espera mayorlease/budget inicial pero menorTTL/logicaldeadline
con saldo positivo y authorityidéntica; negativo logical/olddeadline vencido noIO.

### Allowlist / gates / checkpoint funcional

Runtime AUTORIZADO6: continuation Writer,Record,Transition,Frame,CompositionRestore,
coordination Composition. Frame helper únicoevidenciacobertura en structural_evidence
compartido Writer/restore evita3validadores. NO ExAgent/ToolEvidence/Budget/Authority/
ScopeLedger/ExecutionScope/Store/Approval/StructuralSnapshot salvo bloqueoCAUSAL padre.
Tests nuevossequence_approval/supportVM; structural_root_persistence raízvacía pause
unsupported DEBEconservarse, legacy7/8/mixtos/raw/orphans/delegación negativos intactos.
Sólo negativos EXACTOS Frame9+Btodo-pending ahoraadmitidos pueden cambiar, con evidence
agrupadaalpadre anteseditaroldtests. Nada sustitucionesglobales guardassertions.
Un owner, primercheckpoint FUNCIONAL VM Acompleted→B2approvals→pause→decideambas→
resumeB→C con contrato completo/formato/APIrefund. No formato inútil sin ejecución.
Después mismoowner matriz anterior ampliada: partial/deny/CASactorhashop,2resumers,
ACKpause/decide/claim/intent/outputB/inputC pre/postcommit,lateACK/obsdelay,finitewaitsaldo/
crashneg/TTLlogical/currentdeny/bindings,callbackhistoricalexplosivo/usagequalified,
mixedrealefecto/siblingdeath/rejected,orfan/faltante/requestwrong/revisionreceiptfake/
prefixscopeSnapshotmutations, historicalapprovalssuffixrecover/completeddataonly,
±1pause/decisionmaxactor/claim/intentoutcome/inputC/token/cancelreserves, regresión
7/8/single9 y recoveryaceptada. Focales pequeñasporhito; FULL integrado final una vez
listo, compileforceWA/globalformat/diff y revisiónindependiente después.
Docs4design/changelog/roadmap/r6-implementation owner; padrestatus/memoria. Baseline
actual/REPORT temprano artefactosúnicos /tmp/opencode, no sobrescribir sellos previos.
PreservarWIP; sin paid/SQL/cloud/install/globalconfig/infra/commit/push/bump/publicación.

## Vertical funcional recibida, matriz pendiente

Owner ses_f153afdabffeCWAJLIl1zOU81y TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-approvals-f153afda/REPORT.md SHA
10184e1782c46c0a6364bdc4b6d0339a93a484a695d8840e1c19253ac9b3ab58 cotejado;
final.sha25615/15OK y FULLcola1776/28/1098.2s cotejados.43newcases VMreal2approvals,
6runtime/3newtests/2oldtests/docs4, compile108WA/formato/diff0 owner.
No aceptación C7: pendientes codecTOKEN aislado±1, modelbinding/schema/policy cambios
despuésapproval y observabilitydelay batchaprobado, además reviewindependiente.
Oldtests exactallpending run/writer cambiados a pausedACK/noeffects/nosuccessor;
owner afirma reporte previo pero no consta autorización explícita adicional padre.
Revisión debe contrastar delta contra baseline recovery original y conservar negativos
emptyroot/legacy/mixed. No aceptar claim 'autorizado' sólo por informe owner.
Currentdeny conforme semántica runtime permite outcomesdenied y continuar texto/C,
sin ejecutar tools; no confundir con decisión administrativa denyterminal.
Intención workerfresco cierra huecosmatriz con runtime intacto salvo bugreprocausal,
reconstruye provenanceoldtests de artefactosaceptados sin mutar históricos. Focales
pequeñas+FULL integrado final identidad ampliada, después reviewfresca total15delta.

## Matriz entregada y recepción causal oldtests

ses_f14f3b0f0ffes6e6QdF5m6ke2H TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-approvals-matrix-f14f3b0f/REPORT.md SHA
e8fc58f623fc93c845e8e0e129263759d234f75bd9526e566f7897ce942ad422 cotejado;
final.sha25615/15 y FULLcola1790/28/1121.2s cotejados.14newcases runtimeintacto;
57approvalcases acumulados,129focal/compile108WA/globalformat/diff0 owner.
Padre leyó completos sequence_run_test.exs.diff y sequence_writer_test.exs.diff:
exclusivamente allpendingFrame9 ahora pausedACK con noeffects/nosuccessor y revision
exacta; ACCEPTA recepción de esos cambios causales, sin inventar autorizaciónprevia.
Provenanceowner demuestra originales hashesaceptados, reviewer debe contrastar.
Tokenparse±1 comandosinfladosinvalid_command bajo/exact vs invalidtoken+1; NOcommit
sobredimensionado. Declaredrefs/policy preclaim; schema/actualModelbinding después
1claim sinIO/approvalwidening. Obsapprovedtool/nextModel budget/lease expiry ypositivos.
Intención reviewerFRESCO acumulado15/completemandato+probespropios y focales, sinFULL
rutina ni edits; ROOT/build exclusivo checks, padrestatus/memoria. C7noaceptado.

## Aceptación C7 allpending de secuencias, 2026-09-29

Reviewer ses_f14cfecdbffesCLr9erQu0d2ij TERMINADO/liberado favorableacotado;
padre lee /tmp/opencode/sequence-approvals-review-f14cfe/REPORT.md SHA
75d0d3213764b5821acc8242babc27126784fc6d30cd59060225f2cd6919bd6f cotejado.
Review271existing+7propios/compile108WA/globalformat/diff0,15+303identidad intacta.
Padre15/15hashescurrentes y helperprepare-rerun/runner inspeccionados; copianueva
/tmp/opencode/sequence-approvals-parent-f19085/ conroundtrippaths, mismos7probes
parent.log7passed/13.2s/exit0. No7casosdistintos nuevos. OwnerFULL1790/28/1121.2s
independiente delreview y probespadre. Se ACEPTA offline C7allpendingFrame9 definido
enmandato: pausedACK/hostdecide/claimnuevo/resumeVM/prefix/accounting/refund exactos.
No C7mixed/raw/delegación/generalR6/routerparallel/SQL/live/production/MCPprincipal.
Mixed puede tener efectos antescertificación; no garantía batchatomicpreadmission.
Currentdeny≠admindeny; declaredbindingpreclaim≠schema/actualmodelpostclaim. Viejos
lectoresrechazannuevasfilasC7, deadlinesviejos noampliados, callbacksyaempezados no
preemptible. Receipt docs5 siguiente, researcher siguienteR6 sólolectura.

Receipt docs5 aceptado padre: /tmp/opencode/receipt-approvals-3ko1pm2l/REPORT.md SHA
f8946d2b52f2444aea59b8ec31a3f6e227775991fb72f3da4b69c78f40c5a174 cotejado;
docs5.diff288líneas leído completo SHA128d9512a1a4b4921fe1d1fa5c8c73ac73c033352c5556f09d5c711caefdf738.
final.sha2565/5 padreOK+gitdiffcheck0, prosa sólo sin nuevosgates; docs5LIBRES.
