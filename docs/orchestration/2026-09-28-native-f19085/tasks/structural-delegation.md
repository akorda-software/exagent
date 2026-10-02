# Delegación estructural + C7 mixed/quiescente — diseño previo

**Historial, no dispatch activo (2026-10-01).** Los contratos/amendments sellados se
conservan; las cadenas worker→re-review→padre inferiores quedan sustituidas por
`docs/development/execution-flow.md`. Encargo vigente: `delegation-runtime.md`.
CAS10 agotamiento/reserva tiene evidencia favorable; producer/restore10 aún faltan.

Researcher ses_f145c1988ffes6uJzDi6LT6lZG entregó análisis estático sinpruebas.
Base activeevidence aceptada ownerFULL1845/28 review40+4 parent4; docsreceipt en curso.
No implementación nueva autorizada aún. Objetivo siguienteOBLIGACIÓN R6/A8/A10, no
otra colección de microsubsets sustituyendo delegación/routing/paralelo.

## Dirección aprobada por padre

Unidad funcional Aeffect→B sibling+delegadoD→Dmixed2approvals/controlotrosibling→
raízquiescente pauseACK→hostdecisiones→VMrestoreD→retornoB→Bfinal→C. Matriz incluye
variosdelegados/profundidadextra/controlmixed antesaceptar, no quedarsóloDallpending.
Mismo Record/Writer/claim/Scope/ledger/motor, mapa plano con ENLACES TIPADOS step vs
delegate; sólo step índicesprefijo. No fakeeffecttool externo para delegación.
Cerrar NUEVASadmisiones model/batch cuando suspender, drenar yaadmitido hasta fronteras
persistibles acotadasdeadline. No atomicbatchpreadmissionpromise. Rootpause sólo
sin callbacks/IO/tasks propias activas, nodosclosed/suspended comprobables y no
externaluncertainty. Unknown/timeout/kill→incertidumbre/cleanup NOpausaexitosa.
Controles porcall persistidos antesfronterarecoverable; no inferir retry/fataldesde
status ni reejecutarhooks. Batchreduceordenoriginal EXACTAMENTEuna vez; pendingnoreset.
Fatalconocido no nuevos efectos pendientes/C; política exacta conflictofatal/ask
pendiente diseño. ResultD/controlwrapperB diferenciados para no duplicarefectos/hooks.
Budgetraíz único sinrefundD, pausequiescente/finalrefund; original∩currentroot/B/D,
deadlinesviejos noampliados. Accountingancestral exacto noreprice/redoblecontribución.
Hostresolver portable de definitions activas si necesario, no registryglobal ni
callbacks elegidos por datos ni buildershistorical. Agente/builderordinario conservar.

## Bloqueos causales informados

Writerattach767–768guardstructural/1344–1407producerdelegado; Frame9 todoschildren
sonstepdirectos/prefix y selection1running; ExecutionScope.restore864–915 igualplano.
ToolEvidence sólofullresolution ytoolcanonicaleffects; delegado usa childlinksinintent
ordinario. Writerpauseallpendingnondel yTransition no delegation_outcome; Record
no_runningexternal≠tasksquiescent. Retornodelegado sólochildcompleted+succeeded hoy.
ExAgent tiene tasks/guardians/restoretopológico reutilizables, no nuevomotor/scheduler.

## Esquema/version pendientes antes despacho

Faltan dato parcialcontrol/resultsourceeffect|child, estadocallapproval|waitingchild|
undispatched y consumocontrol/history; enlaces typed y suspensiónporcada nodo;
approvalbindingrutaancestral/quiescencecertificate con ownership comprobado.
Nueva versiónFrame preferible SI gramáticalinks/status/control cambia conjuntamente;
no decisión automáticaFrame10 niRecord3/Scope3/Approval2. Congelarsemántica7/8/9,
no reinterpretarmixed9sincontrol ni automigrarlifetimes. Oldreadersfuture reject.
Contratoexperimentalenmajor2 sinbump/publicación. Need exactschema/cursors/transitions/
hostresolver/fatalpolicy antes autorizarruntime.

## Allowlist prevista, NO permiso activo de edición

Necesarios ExAgent/Writer/Frame/Record/Transition/ToolEvidence/CompositionRestore/
ExecutionScope/Composition. Delegation/Coordination condicionalresolvercausal.
Authority/ScopeLedger/OTel sólo carenciademostrada; Budgetsemántica intacta; no Store/
SQLadapter/ReqLLM. TestsVMintegrados+regresióncausal, docs4despuésreceipt; padrestatus.

## Matriz y ruta producto

VMpause/decisionpartial/resultD/controlB/preC, CAS2resumers0losercallback, ACKattach/
control/pause/claim/resultD/returnB conStoreonlyretry; decisionsidempotence/denyconflict;
rootbudget/quotaancestors/deadlines/lateACKobs;authorityschemaargsrefsModelpath;
DOWNownertasksproducersdescendants/quiescence; costqualified/noreprice/nodoublecount;
2delegadospending+completed+grandchild; success/deny/retry/fatal/raw/hookfail/timeout+
ask preservandocontrolorden/no replay; ±1nodesdepth/checkpointJSONcleanupreceipts/
controlapprovals/tokenparse; old7/8/9/mixedambiguityguards/completeddataonly; OTel
ancestryattemptcorrelation sinprivatepayload. Después router+fanoutfanin conruta/
inputs/mergepersistidos, failed+pauseddelegated+completed branches yA8/A10 SQLbackend.

## Mandato de implementación sellado

Reviewer independiente ses_f1451a03affe1LB0QiPylcgij0 relectura TERMINADA: listo para
implementar, ocho bloqueos resueltos por sección final de delegation-schema-proposal.md.
Es conformidad estática, NO evidencia runtime. Padre autoriza unidad integrada con
ese esquema y sus reemplazos finales PREVALENTES. Frame10 + failed condicionado10,
raw/control y admisión atómicos, hooks ambiguos no autoreplay, rehidratación repetible,
quiescencia real y resolver host exacto. Legacy7/8/9 sin migración/downgrade automático.

Owner único ROOT/build y docs4 design/changelog/roadmap/r6-implementation; padre
status/memoria. Allowlist13: lib/exagent.ex; continuation/{writer,frame,record,
transition,tool_evidence,composition_restore,delegation,budget}.ex;
execution_scope.ex; coordination/composition.ex; coordination.ex; continuation.ex.
Retry sólo integración de callback uncertainty/failed, sin habilitar retry administrativo
nuevo. Outcome/Authority/ScopeLedger/Retention/OTel requieren bloqueo causal presentado
al padre antes editar. Store/adapters/ReqLLM fuera. Budget aritmética intacta.
Tests nuevos integrados/supportVM; oldtests sólo cambios causales identificados y
agrupados para aprobación padre. No reemplazo global9→10 de fixtures/expectativas;
preservar fixtures auténticas lifetimes anteriores y sus negativas.

Primer checkpoint funcional según schema: mixed nested/two approvals/rootpause con
workersDOWN/hostdecide/freshVM/Dcomplete/crashanteswrapper/recover/Bfinal/C. No entrega
de sólo formato sin consumidor ni aceptar helpers por separado. Mismo owner continúa
matriz integrada si contexto permite; si precisa handoff, preservar checkpoint probado,
registrar huecos y liberar procesos/build explícitamente. No rollback trabajo válido.
Baseline actual WIP y REPORT temprano recuperable en /tmp/opencode único; manifest/diff/
commands/exits por hitos, originales sellados intactos. Focales discriminantes durante
desarrollo, compileforceWA/globalformat/diff y FULL final integrado sólo cuando matriz
lista; review independiente y probes padre antes aceptación. Offline OTP/tooling según
environment.md, build absoluto ROOT/_build, WA48seed37556, timeout FULL>=1800000.
No paid/SQL/cloud/install/globalconfig/infra/commit/push/versionbump/publicación/consumidores.
Cambios de diseño imprescindibles: informar contradicción y reproducción antes ampliar,
no decidir silenciosamente otro esquema/motor/semántica. Ninguna promesa exactly-once
externo, callbackpreemption ni producción/SQL por pruebas VM offline.

## Ampliación causal OutputResolution autorizada

Owner ses_f144a5659ffecDQIhVqtWHjaPi entregó bloqueo antes de editar producto;
ROOT/build/docs4 liberados. Padre leyó REPORT /tmp/opencode/structural-delegation-dfTqOja9/
REPORT.md SHAa1180bab1a699898e9b9e96ccd48886d781f7e87b19e5bc4309486b569d03016
cotejado y código output_resolution.ex231–252: current-response requiere running,
retry appended requiere request distinta. Probe1pass confirma rechazo actual, NO
Frame10 integrado ni defecto legacy. Owner430/430 intactos; checkpoint no implementado.

AUTORIZADO añadir lib/exagent/continuation/output_resolution.ex a allowlist: validación
de posición de atestaciones consciente de versión10 para fronteras suspended/failed
con cursor/history/request/retry counters/evidencia fatal exactos. Contexto de versión
proviene del frame validado, no status-coercion ni un booleano libre que evada guards.
No aceptar suspended/failed indiscriminadamente, no convertir retry en fatal sin
evidencia, no request sucesora ficticia ni borrar atestación. Sin nuevo formato de
OutputResolution. Legacy7/8/9 conserva posiciones y rechazos actuales.
Probar integrado delegado ya admitido recibe output inválido durante approval-drain:
no nueva request, pausa conserva atestación y resume consume exactamente una vez;
agotamiento real/fatal y corrupción de cursor/counters como contrapruebas. No activar
extensión sola como entrega. Mismo owner retoma mandato completo y checkpoint funcional,
baseline existente conservado; report por hitos, sin reiniciar investigación general.

## Cambio de ejecución por agotamiento de contexto sin implementación

ses_f144a5659ffecDQIhVqtWHjaPi TERMINADO/liberado otra vez, producto sin cambios.
Padre leyó RESUMPTION.md SHA
f944e4f1634a44703cf35528d029098499c6ddb34801c52dd45877c9bb2c32e3 cotejado en
/tmp/opencode/structural-delegation-dfTqOja9/. No bloqueo técnico nuevo, sólo contexto;
305rutas intactas según owner, sin tests/builds nuevos. No reabrir diseño/OutputResolution.

Padre REEMPLAZA restricción de primer handoff obligatoriamente vertical completa:
se permiten incrementos internos probados e INACTIVOS hasta integración, para evitar
otra sesión consumida sin código. No son capacidades aceptadas ni entregas de producto.
Primer frente fresco: gramática/validación Frame10 tipada y sus invariantes puras,
tests focales y fixtures estructurales sintéticas claramente identificadas. NO activar
productor10, NO cambiar comportamiento7/8/9 ni relajar validadores para hacer fixtures
válidas; runtime activo9 sigue intacto. Implementar dentro módulos existentes con
helpers privados; si dependencia excede frente dejar seam cerrado, no API pública
provisional ni esquema distinto. Alcance de esta fase Frame/ToolEvidence/OutputResolution,
Record sólo dispatch/validación10 necesaria, sin habilitar transiciones aún. Budget/
Writer/ExAgent/Scope/Composition productores no editar en este frente.
Al entregar enumerar reglas implementadas/pedientes y pasos concretos de integración;
focales nuevos+regresión pertinente/compile/formato/diff, no FULL rutinario previo a
vertical. Padre revisará antes siguiente frente de transiciones/productor; un escritor
por archivo, conservar incrementos probados. Esquema final y objetivo integrado/
matriz/review siguen obligatorios; no aceptar Frame10 por fixtures sintéticas.

## Base interna recibida

ses_f1440e432ffeAVZKAr8AaZ4Nw2 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/delegation-frame10-base-bB06qm3T/REPORT.md SHA
29b20b91dd6703e7b0a6e0f9c2095ee87093469cd950dfa16d10fe12b4aa753d cotejado;
final-owned.sha2565/5 padreOK. Frame/Record/ToolEvidence +35grammarcases+roadmap.
Owner35final/349regresión incl33previos (no384casosdistintos), compile109WA/globalformat/
diff0. Record.execution y ToolEvidence.evidence/transition siguen rechazando10;
productores9 intactos. OutputResolution aún sin cambio. NOFULL/VM/aceptaciónFrame10.
Baselineinicial tracked-only insuficiente declarado; tresoriginales reconstruidos
conhashesiguales baseline430 previo, reviewer contrastará sin atribuirlo a freshcapture.
Intención revisión breve independiente delta+guardsinactivos/legacy/fixtures, antes
siguiente incremento journal/coverage/hash/accounting/OutputResolution. No repetir
diseño general; foco aislamiento y coherencia de base. ROOT/build exclusivo reviewer.

## Base revisada; siguiente incremento de evidencia inactivo

Reviewer ses_f142bfc4effexSSIvBwPKu6RZt TERMINADO/liberado favorable interno.
Padre leyó REPORT /tmp/opencode/frame10-base-review-wBAfefda/REPORT.md SHA
a1eb97a3dfbaac9057b85e487abb03f11fe275cfdf0803e0caa96e53a37a3a46 cotejado y5/5fuentes.
Review72+3tests distintos y5gruposprobes sintéticos, no sumar reruns ni ocultar warning
harness unusedalias. Reconstrucción3hashes/diffexacto confirmada; guards10cerrados.
Se conserva incremento, NO aceptaciónruntime/VM/Frame10producto.

Siguiente worker exclusivo: evidencia journal10 y OutputResolution10 en Frame/
ToolEvidence/OutputResolution, tests nuevos y nota roadmap. Record sólo si integración
de helpervalidación interna imprescindible, manteniendo execution10 RECHAZADO.
Se permite enrutar validación ToolEvidence.evidence? a10 cuando sus invariantes estén
demostradas; esto NO autoriza transiciones10, Record válido10 ni productor/restore10.
Si evidencia parcial aún incompleta, entry global debe seguir failclosed; helpers
comprobados pueden entregarse sin esa activación. No mecanismo público provisional.
Objetivo cobertura model-response/call order y links exactos, effectraw/final/control
hashes/accounting/purechildconversion, resolution/consumption/retry orden exacto,
atestaciones output10 suspended/failed con contexto real. Host predipatch reason enum
únicamente razones actuales demostradas, no inventar éxito/fakeeffect. Fixtures con
journal coherente explícitamente sintéticas, no proclamar productor/VMreal. Reutilizar
fuentes originales/helpers y preservar legacy. AtomicidadCAS se prueba en siguiente
fase de transiciones, no atribuirla a validadores estáticos. Sin Writer/Transition/
ExAgent/Scope/Composition/Budget edits aquí; esquema aprobado inmutable salvo bloqueo.
Focales discriminantes+regresión pertinente/compile/formato/diff, no FULL rutinario.
Baseline completo existente tracked+untracked con hashes ANTES editar, no repetir
caveat de intake previo. REPORT recuperable/delta/hashes/pendientes precisos.

## Reemplazo journal por error de sesión

ses_f1425d5eeffemOwTwPQXMwdeZ8 ERROR invalid_encrypted_content: NO reanudar.
Padre lee /tmp/opencode/frame10-journal-jya6y4hV/REPORT.md mínimo baseline/WIP;
verifica manifest-before431/431 byteidénticos y files-before.zlist contra gitlsfiles
sin rutas nuevas/eliminadas. ps sólo tres BEAM ajenos, ningún build propio.
No implementación journal ni gate nuevo observado. Base10 anterior intacta. Worker
fresco continúa MISMO incremento acotado, directorio artefactos nuevo sin sobrescribir
baseline anterior; no reabrir diseño ni repetir aprobación OutputResolution.

## Journal parcial recibido; cerrar certificado antes review acumulada

ses_f142303bcffebckNaV0iDmCaOz TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-journal-fresh-iVQZzt8g/REPORT.md SHA
4135ceb09b4dc0a4020418395a92ba18df9e9d1b242eab032b51fa6dafd2d354 cotejado,
6/6final-owned padreOK. Runtime ToolEvidence/OutputResolution,30new+fixture+roadmap;
65focal(30+35base),279legacy/527.4s,compile110WA/formato/diff0 owner. Timeoutlegacy120s
histórico no resultado, rerun separado. Baseline hashesantes, contenidooriginal
reconstruido hashverificado declarado, no fingir backup previo.
Partial effect-backed certificate/reducer/consumption y suspendedresponse/consumedretry
Output10, NO global certificado/evidence10/Record10/transitions10. Fixtures fragmentos
sintéticos, no fullRecord/VM. Padre recibe y conserva incremento NOaceptaciónruntime.
Próximo worker MISMO alcance termina tabla REPORT23–31/43–46: toolorphans/operation/
outcome partition global, fasesrawparcial, purechildterminal→raw, enumhostpredispatch
demostrado, crossbatchretry/consumption y fatal/outputfailedexact. No reimplementar
helpers ya probados ni nuevo diseño. Review independiente acumulada tras certificado,
no revisión por microhelper. Entry evidence10 sólo si completa; Record/transitions/
productor siempre cerrado en esta fase. Baseline CONTENT+hashes anteseditar requerido,
no reconstrucción tardía innecesaria. Gates focales/legacy selectiva, sinFULL.

## Handoff journal y decisión de error portable

ses_f140becd5ffeMhrOYb50B0EJSD TERMINADO/liberado. REPORT
/tmp/opencode/frame10-journal-complete-FXHNF6xU/REPORT.md SHA
e20d56551b6f5fdabc9342989334bad0dd4ce457131b4a227b0ec441139bb0f5 leído/hashOK,
padre6/6fuentes.14new/79focal+62legacy/compile110WA/formato0 owner, globalcert aúnno.
Partición effect-backed/raw/running/blocked y historyretry reforzados, registros10
cerrados. Rojo assumptionstates corregido a effect running/confirmed preservado.
Bloqueo portablefailedchild resuelto por decisión final schema-proposal: proyección
canónica10 lossy messageportable/controlerror, legacyintacto, sin dobleautoridad.
Siguiente frente fresco CONCRETO child/hostsource certificates y pureconverters;
no volver encargar cierre total más global/model/fatal en una sesión. Conserva actual
effect/history helpers, entryglobal10 cerrado. Restantes authority/requestdata/fatal/
outputfailed se abordarán sobre ese incremento; permisos no cambian salvo documentación
design/changelog de decisión autorizada. No productor/transition edits en este frente.

## Sources recibidas; cierre de contrato antes transiciones

ses_f13fd738effe0Wup43A8pM50ug TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-sources-JCYces/REPORT.md SHA
a7ea3ceb3f459bb0a6886d3e157316084ed4b9062e9d41bf0ac16ec8de2e7c42 cotejado,
10/10hashesacumulados padreOK.20new/99focal+62legacy/compile111WA owner. Childraw
canónico y SOURCE child/hostpermissiondenied implementados; wrapperfinal aúncerrado.
No globalcertificate10/runtime/VM. Hostunknown/malformedargs carecen binding/schema
válido; no aprobar bindingfalso para satisfacer settledgrammar. Cancelledconraw
requiere procedenciaprevia y wrapperfinal requiere atestación propia, no childresult
asparentfinal. Intención investigación acotada exactschema/transitionproof para esos
casos y decisión de entrar transiciones/productor en vez bucle de validators sin
consumidor. No autoridad a researcher paraeditar ni rediseñar todo; globalsiguecerrado.

## Frente transiciones/admisión autorizado

Research ses_f13f3f1b0ffetOYnR0wFenpfeV TERMINADO sólolectura. Padre sella decisions
hostunprepared/wrappertrustedsettlement/terminalchildimmutable en schema-proposal final.
Se AUTORIZA próximo incremento: Record10 construido desde create mediante operaciones
Store/CAS reales, roundtripvaliddespuéscadaACK; nestedmixed B→D siblingsettled+2approval
pause→partialdecide→ready→claim/frontier. NOfixturejournalfinal insertado como sustituto.
No productor/VM ni livequiescence acceptance en esta fase: worker certificate inputs
synthetictrusted, Store sólo demuestra atomicidad/invariantes, nunca PIDs.

Allowlist fase Transition/Record/Frame/ToolEvidence/OutputResolution integración,
tests nuevos operations/CAS y docs4; padrestatus/memoria. NO ExAgent/Writer/Composition/
Restore/Scope ni Storeadapters. Authority/ScopeLedger/RequestData sólo impedimento
demostrado y autorizado padre. Budget adaptación necesaria informar anteseditar,
aritmética legacy intacta. Productor9 queda igual; no afirmar runtime10 habilitado.
Orden: create/claim10→step_input/modelintentoutcome/batch/callprepareprepared→atomic
begin_effect+callsource y nodeattach+childScopeauthority→raw/wrap/settle→resolution/
consume/drain/suspend/pause/decide/reclaim. Cerrar evidenceglobal10/structural authority/
requestdata/parentinputdelegado para cadaestado queadmite, nunca fallback9permisivo.
Guards globalfatal/outputfailed/failrefund pueden permanecer negativos explícitos
en este checkpoint, siguiente gate obligatorio antesproductor completo. No permitir
fatalparcial convertirse éxito/pausa. Outputretry suspend seguro según certificado.
Pruebas hostunknown/decode/hooks/retention sinbinding; childrawX finalY y saltowrap
negativo; completed/failed→cancelled negativo;2claimants/fencestale/epoch/replayid;
CASattach/raw/settle/pause sin parcial; decisions2 y Recordencode/decodecadacommit;
reservas antesadmisión/legacy7/8/9. Focales y compile/formato/diff, FULL alintegrar
productor real no cadahelper. Baseline completoCONTENT+hashantesedits, artifactsúnicos,
REPORTtemprano/hitos, sin volver auditoríageneral ni diseño. NoautaceptaciónFrame10.

## Ampliación causal RequestData autorizada

ses_f13f0613dffegVAIyKiJQiAnFS terminó/liberó antesedits. Padre leyó REPORT
/tmp/opencode/frame10-transitions-WNqvHSI8/REPORT.md SHA
ab0a5f9ef52413df72855d5e4a0c9d077340ea5b418316fd4f682cbbc66b6da5 cotejado y fuentes
RequestData1/Frame.fingerprint. Owner436/436intactos/99focal/compile111WA, sóloprobe
descriptorloss no implementaciónCAS. Se AÑADE RequestData a allowlist fase para
request_version2/preimagenfingerprintexacta10 según sello finalschema, legacy1intacto.
Mismo owner retoma checkpoint completo create→nestedpause→decide→reclaim con esa
evidencia integrada; no entrega sóloRequestData2 ni nueva investigación general.

## Checkpoint CAS recibido — review acumulada antes ampliar

ses_f13f0613dffegVAIyKiJQiAnFS TERMINADO/liberado. REPORT actualizado
/tmp/opencode/frame10-transitions-WNqvHSI8/REPORT.md SHA
efb254bb96faf38c1334223d822663b10c967a0f966cc480a39a0b1a15c82d93 leído/hashOK;
padre final-cumulative20/20OK. Own13rutas,5runtime/4newtests/docs4. Flujo realETS/CAS
create→nestedmixed→pause2→decide→claim/frontier y childrawX→wrap→finalY→consume,
roundtripcadaACK. Inputscomandos sintéticos/trusted, NOworkers/VM/quiescence runtime.
Owner113focal+62legacy175final/207legacyampliada/compile112WA/globalformat/diff0.
Globaladmisión10 ahora subset sólo absentexternalusage(nil NOcostezero), sin output
resolutions/retry/rootterminal/recoveruncertain/fatal/outputfailed/cancel/expire.
Unsupported rechaza, productor9 sigue9/restore10 cerrado; Budgetsin cambios.
Intención reviewerfresco ACUMULADO20 gramática+journal+CAS, especial atomicidad/
authority/closures/childhostproof/RequestData2 y nonnilusagefailclosed. No FULLrutina;
probespropios/actualops/focallegacy. No aceptación productoFrame10 ni delegaciónVM.

## Revisión CAS bloqueante: cuatro defectos dentro del subset

Reviewer ses_f13c08d72ffe8F20va45RMfi4K TERMINADO/liberado. Padre leyó REPORT
/tmp/opencode/frame10-cas-review-8Dfp1CQa/REPORT.md SHA
03a7694c79d4bb9bd9a054c1bd81034b82dada83a4fcaaa565b11337c9d61366 cotejado.
320existingtests distintos pasan, probespropios reproducen4defectos (2P1/2P2),
no aprobaciónsubset.20/20fuentesintactas reviewer; compile112WA/formato/diff0.
P1 historialpayload_omitted puedeadmitir nuevoModel: executablehistory gate falta.
P1 childfinalunknown settled/unresolvedfalse→consume→nuevoModel, a diferenciaeffect.
P2 closure reserve íntegra recobrada despuésraw impide usar bytesyareservados:
60194bytesreturn<65536admitido pero record_limit trasdispatch límite1714951.
P2 hostunprepared malformed/schema se valida contra originalargs aunque beforehook
puede cambiarlos; rechazaobservacióncorrecta y deja preparingincierto.

Corrección causal autorizada mismafase Transition/Record/ToolEvidence/Frame si causal,
RequestData/OutputResolution sólo si necesario dentroallowlist; testspermanentes+docs4.
Rechazar admisión conhistoryinexecutable y unknownchild fuera subset sin fakeoutcome/
refund/replay. Reserva debe medir closurePENDIENTE más bytesmaterializados, demostrar
que bytesreservados sirven sin reducirprotecciónfuturacierre/receiptcleanup. No aumentar
límites ni tratar nilusage comozero. Host motivos observados posthook se atestan por
transicióntrusted, NOrecalcular desde argsoriginales ni inventar binding; conservar
identity/hashoriginal y motivos/status/control exactos. No ampliarproducer/uncertain.
Repro rojo→fix→regresionesverde; testsdiagnósticosqueafirmabanbug NOdeben venderse
verdes: nuevascopias contractuales con cambio explícitooráculo, originalesintactos.
Matriz siblings/data-onlymutations/lateCAS y legacy, reviewindependiente después.

## Fixes CAS recibidos, revalidación pendiente

ses_f13ac4b46ffek90Kdhnm5v5954 TERMINADO/liberado. Padre leyó REPORT
/tmp/opencode/frame10-cas-fix-42rWnXLi/REPORT.md SHA
3eb59edbeca476342eb054ad5d09c19beb939625e1ef80e48310576b693f6226 cotejado,
final-owned10/10 padreOK. Runtime Frame/Record/ToolEvidence/Transition+2newtests+docs4.
Owner333regresión=320+13/214.4s; external13 mismoscasos, compile112WA/formatdiff0.
Historyexecutable checked enadmisión/globalcontext; unknownchildrechaza dejando
wrappingunresolved; host observedreasons no originalargsrevalidation; reserva crédito
sóloresultstrings materializados capped6*limitcadauno/futureslot+fixed16384 intactos.
Rojos originales/contractadaptations preservados, no afirmar bugdiagnosticsverde.
Intención mismo reviewerindependiente revalida delta10+causas/siblings/capacidad,
sin FULLrutina; globalsunsupported/productor10off intactos. Noaceptación todavía.

## Cuatro fixes recibidos; próximo frente accounting10

Reviewer ses_f13c08d72ffe8F20va45RMfi4K TERMINADO/liberado favorableinterno. Padre leyó
REPORT /tmp/opencode/frame10-cas-fix-review-7XH8yUvc/REPORT.md SHA
38b14cab89458145c429390ad231baeae5a37789c16a867dfc6644174dddc0e3 cotejado,
10/10currenthashes y copia3probes conroundtripsustituciónrutaúnica a NUEVO
/tmp/opencode/cas10-parent-5rn_0jdr/: parent.log13pass/13.0s/exit0, mismos13review
no13casosadicionales. Review89selected+13overlap/compile112WA/identity10+83+442 intacta.
Se reciben cuatrofixes y subsetCAS INTERNOS revisados, NOproducto10/VM/quiescence.

Próximo incremento autorizado ACOTADO accounting10: admitir contribuciones reales
Model/tool no-nil en operacionesCAS existentes, disponibilidad/calidad/procedencia/
unidades/costes calificados conservados y acumulación root/B/D exacta, sin redebit
ni repricing/replay. Nilusage NOzero. Reutilizar ledger/Outcome/usagecontratos actuales,
no nuevoledger/schemausage. Authoritycuotas/gastos originales∩actuales preservados.
Allowlist fase Frame/ToolEvidence/Transition/Record validación/accounting y tests/
docs4. RequestData sólo dependencia causal existente; ScopeLedger/Budget/Authority/
Outcome/Scope/Writer/ExAgent/Store requieren impedimento específico padre anteseditar.
No producer10 ni abrir outputretry/rootterminal/recovery/fatal/cancel/expire aquí.
Fixtures operacionesREALES create→nested outcomescontribuidos→pause/decide/reclaim/
continuación dentro subset; roundtripcadacommit y controles mutación/noreprice/double
application/ancestrysums/limits/unknownretention. Reservas materialización fixes intactos.
Focales/legacy pertinentes compileformatdiff, sinFULLrutina; baselinecontenthash
previo/reporttemprano/artefactosúnicos y releaseprocesos. Review posterior según delta.

## ScopeLedger nil decoder: ampliación causal autorizada

ses_f1392aa76ffe1RDtPOg2rUA42L TERMINADO/liberado, restauró sólo experimento propio;
442/442baselineidéntico declarado, guardnonnil cerrado. Padre leyó REPORT
/tmp/opencode/frame10-accounting-xL0zt7od/REPORT.md SHA
6a8fd3f8dcd5af257957484ba8f1842ad741f4346a9400cc568860820c55a779 cotejado y
ScopeLedger.usage133–144: from_map!(nil) falla aunque decoder/validator admiten nil.
Probe2rojos contractuales enbaseline; experimento1CASpositivo no entregaimplementada.
Padre AUTORIZA scope_ledger.ex exclusivamente reemplazar agregación decode por
decode_usage existente; Usage.sum/Retention/semántica nil≠zero/ledger2 inmutables.
Regresiones allnil/mixed/complete/partial/retained y legacyobligatorias, sin cambiar
aritmética ni sumar contribución dos veces. Mismo owner retoma accountingmandato;
experimental/patch conserva avance pero revisar antes aplicar (helpercompleteness
compartido legacy debe aislarse10 o demostrar compatibilidad, no ampliarsemántica).
Tool outcome uso optionaltrustedinput permitido para persistir observación/Scope
existente dado codecToolReturnomitsusage; no cambiar Outcome/history/schemaUsage.
Mantener unsupportedgates restantes. No nuevaauditoría ni pérdida de checkpointprevio.

## Accounting entregado; oráculo causal autorizado

ses_f1392aa76ffe1RDtPOg2rUA42L TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-accounting-resume-ak7TN45w/REPORT.md SHA
09945e9b4c221704be55478a92c5e9949e8c349015776ce12530f2c895a2b6e4 cotejado,
10/10sourcehashesOK.26new+2repros verdes; regresión234/235 rojaúnica expectativa vieja
usageModelnonnil. Compile112WA/formatdiff0owner, NOaceptación todavía.
Padre inspeccionó frame10_causal_controls_test.exs170–220 y AUTORIZA únicamente
renombrar caso y reemplazar rechazoModel175–189 por commit+assertcontribuciónobservada
exacta (zeroobserved≠nil), sin tocar wrapperinjectedusage rechazo191–220. Ninguna otra
negativa relajada. Mantener guard doblecontribución delegado. Mismoowner actualiza
oráculo, rerun235+2probes/compileformatdiff y entrega identidadactualizada. Históricos
234/235/232/233 intactos, no inferirverdeporrestar. Luego reviewindependienteaccounting.

## Accounting gates verdes; revisión acumulada pendiente

ses_f1392aa76ffe1RDtPOg2rUA42L TERMINADO/liberado. Padre leyó REPORT
/tmp/opencode/frame10-accounting-oracle-NGrZ5ydw/REPORT.md SHA
becc78014f97a3c24a0d7c027a0a7ba724528872248cfa0d9f348b785f8971f2 cotejado,
final-owned11/11 padreOK. Owner235/55.0s exit0+2reprosseparados/compile112WA/formatdiff0.
Runtime followupintacto; oráculoModelcommit autorizado conexactop/zeroobserved y wrapper
suffixbyteidéntico segúnowner; reviewer contrastará exact-old-test.diff. Histórico primer
235executados exit1warning no se cuenta gateWA; rerunverde separado.
Intención reviewerFRESCO acumulado11accounting vsbaselineCASaceptado interno, revisión
ScopeLedgerseam/semántica nil/qualification/ancestry/quota/closure/probes propios.
No FULLrutina/producer10 ni autoaceptación; ROOT/build exclusivo reviewerchecks.

## Accounting recibido; siguiente incremento output tipado/retry

Reviewer ses_f136d379effehWXsQ5N1KGwAtP TERMINADO/liberado favorable interno.
REPORT /tmp/opencode/frame10-accounting-review-I4iS1zD8/REPORT.md SHA
641f043681feb996741868a67d1624ed7aded7f5a1957f48d45a0e7eb9630929 cotejado.
Review134existing+4propios; padre copia3scripts con sustitución reversible ruta a
/tmp/opencode/accounting10-parent-8zlndpu_/:4/4pass,4.6s,exit0, mismos4 no adicionales.
Padre11/11hashes entrega comprobados. Accounting subset INTERNO recibido, no universal
closure-capacity ni providerbilling/VM/live-loader/producer10. Contribuciones grandes
siguen límite documentado; nil no equivale coste0.

Siguiente incremento autorizado: integrar output resolutions tipadas y retries10
mediante operaciones CAS reales existentes y validación global coherente; terminal
de CHILD completado tipado y raw delegado canónico, preservando controles/usage.
Incluir retry confirmado→consume→suspensión durante approval-drain sin request nueva→
decide/reclaim→siguiente request exactamente una vez; success tipado tras retry.
No fake successorrequest para validar posición. Separar callbacks validación/hook
de atestación persistida trusted-producer, sin ejecutar callbacks en Record.decode.
Agotamiento/fatal que aún no tenga certificado global sigue explícitamente rechazado;
no convertirlo en éxito/pausa ni perder evidencia previamente confirmada. Rootterminal,
recovery/uncertain, fatal/cancel/expire y productor10 permanecen fuera de esta fase.
Allowlist Frame/Record/Transition/ToolEvidence/OutputResolution, tests/fixtures10 y
docs4. RequestData sólo integración causal de fingerprint actual; no nuevo formato.
Writer/ExAgent/Composition/Restore/Scope/ScopeLedger/Budget/Authority/Outcome/Store/
Retention/OTel fuera salvo impedimento preciso presentado al padre antes editar.
Legacy7/8/9 y accounting recién aceptado intactos. Tests reales Store/CAS+roundtrip
cadacommit, atestación mutada/orphan/historial/counters/consumption/replay/stalephase
negativos; positivos límites retry y siblings aprobaciones sin repetir callbacks.
No atribuir pruebas CAS a quiescencia worker viva ni VM. Baseline content+hash antes
edits/report temprano y delta; focal/legacy pertinente/compileWA/formato/diff, sin
FULL rutinario previo a productor integrado. Review independiente antes aceptar.

## Output CAS recibido, revisión pendiente

Worker ses_f13620c40ffe6R4K9SEXFyO7tZ TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-output-cas-2HG3aDNz/REPORT.md SHA
243efed054f1690b553f73972786e76fb2fbdc65bfedc29b91757bf0effe3ff4 cotejado y9/9hashes.
Frame/Transition/OutputResolution+2newtestfixture+docs4, sin oldtestchanges.
Owner380regresión incluye6new; final9focal incluye esos6 (no389distintos), compile113WA,
formatglobal/diff0. Regresión previa a formato y3tests adicionales; sin edición semántica
posterior segúnowner. CASoutput_resolution/output_consume/typedchildcomplete atómico,
pausa/reclaim/retries/accounting; entradastrusted sintéticas, no callback/VMproducer.
Unsupported fatal/exhaustion/rootterminal/recovery/outputomission/cancel/expire cerrados.
Intención reviewerfresco delta9+certificadoglobal/posiciones/retryguards/atomicidad y
probesadversariales independientes, ROOT/build exclusivo checks. Noaceptación aún.

## Review output bloqueante: reserva de copias pendientes

Reviewer ses_f134b0f45ffeUzBUIXI60v3Ra2 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-output-review-lOMWDLo0/REPORT.md SHA
0fbc85740bdc3e40b8290c7a3ca96e8196ce77486036dfe3ae107447a51b102a cotejado.
240selected pasan;5probesfinales=3pass/2fail MISMO P2.445/445fuentesintactas,
compile113WA/formato/diff0. Owner380 no atribuible a bytesfinales exactos sin sello
preformat; evidencia exacta reviewer240. Historialharnessprobesv1–v4 preservado.
P2 output_resolutionACK admite payload<65536 pero no reserva copiahistory/result:
retry60000B limit1788510→consume record_limit; successobject60000B limit1788564→
node_complete record_limit. Filasprevias intactas, no corrupción, progreso bloqueado.
Mismosflujos cierran a8MiB. No es petición garantíauniversal: son copias obligatorias
de la nueva operaciónadmitida, sin IO intermedio. Recordreserve149–178 ignoraoutput.

Fix autorizado acotado Record/Transition/OutputResolution/Frame si causal, tests
permanentes ydocs4. Reservar copias PENDIENTES output al aceptar atestación y consumir
crédito al materializar, con byteJSON/escape/counters/receipts/futureslot exactos o
cota segura demostrada. Puede rechazar atestación antesACK si no cabe cierre; no
rechazar todo output ni bajar tamaño soportado arbitrariamente. Mantener reserva
tool/delegate vigente sin doblecrédito, sin subircheckpointlimit, sin modificar
ScopeLedger/Budgetmath/Retention/Store. Payload original no truncar/borrar.
Repros contractuales independientes rojo→verde con2rutas permitidas: rechazo temprano
atómico explícito+control con espacio suficiente, o ACKseguido de cierre sinnuevoIO.
No verde por aceptar rechazo en cualquier fase; comprobar boundary real±1 y que
ackadmitido cierra, variasatestaciones/siblings/escapeJSON/replay no comen reserva.
Reviewmisma sesión despuésfix y probespadre; producer/fatal/root/recovery aúncerrados.

## Fix reserva output recibido; re-review pendiente

Worker ses_f133e3f53ffeEFZ6KOE3dCCN8Y TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-output-capacity-fix-TrWhtkHm/REPORT.md SHA
78e88cd194d793863091774d11cc971dfe30465b128be5835f83ca81d76dfa98 cotejado,
final-owned7/7OK. Runtime sólo Record +newtestfixture+docs4. Reserva pendinghistory/
typedresult/rawobservación residual sin dobletoolcredit +receipt, libera almaterializar.
Owner probesv4idénticos3/5rojo→5/5verde, selected282/338.7s y sealed12mismos7+5,
compile114WA/globalformat/diff0. Permanenttests fixedlimitsrechazaatestation atómica,
capacitypositive yboundary±1/plainescaped/maxreceipt/siblings/historycreditrelease.
Owner380 continúa noatribuido a bytesexactos; fix282 source sellada sí reportado.
Intención mismo reviewer revalida cota/metadata/receipt y globalsafeguards con probes
independientes, no aceptación antesdictamen+padre. ROOT/build exclusivo reviewerchecks.

## Output/retry CAS recibido; siguiente cierre exitoso estructural

Reviewer ses_f134b0f45ffeUzBUIXI60v3Ra2 TERMINADO/liberado, favorablefixsinnewfindings.
REPORT /tmp/opencode/frame10-output-capacity-review-BrK16jIH/REPORT.md SHA
5d9a70d3f4fbedf5f82c7b01ed56ac357fa067c90686c67fda6b5a31638e0c04 leído/cotejado;
padre7/7fuentes y copiasrunner/probes con sustituciónruta reversible. Rerunpadre
/tmp/opencode/output-capacity-parent-hwynv_an/:7pass/14.9s/exit0, mismos5+2review,
no7nuevos. Reviewer12(7permanentes+5originales)+92selected+2new/compile114WA.
Se acepta incremento INTERNO output/retry CAS yfixcapacidad acotada; no producer10/
VM/hooksreales/quiescenciaviva/SQL/R6. Original380 no relabel como exactfinal.

Siguiente frente autorizado: cierre EXITOSO de steps y raíz10 con operaciones CAS
reales, stepadvance/input confirmados y conservación prefijos/inputroot/typedlinks.
Completar A→B(delegadoD mixed/pause2/reclaim/outputretry)→C→rootcompleted portable;
sin recomputar mapping/callback en decode ni dar por probado hostmappingruntime.
Uso/counters/authorityledger originales, refund terminal exactamente una vez usando
matemática existente, completed data-only inspection terminal sin hostcatalog/callback.
Allowlist Frame/Record/Transition/ToolEvidence/OutputResolution; Budget/Continuation
sólo integración necesaria de success terminal10 con aritmética y facade existentes
intactas. Tests/support10/docs4 autorizados. No ExAgent/Writer/Composition productors/
Restore/Scope/Store/Authority/ScopeLedger/RequestData cambios salvo causa y permiso
padre previo. Si facade requiere activar restore10, bloquear ese path en vez habilitar
runtime parcial. Fatal/failed/outputexhaustion/cancel/expire/uncertain/recovery siguen
rechazados explícitos; no deshabilitar rawsource/pauselimits/closure ni legacy7/8/9.
Tests roundtripcadacommit/terminalinspection/replayfence/countersrefundexactos,
no rootcomplete mientrasdescendantactivo/paused/pendingwrap/outcomeunconsumed, no
completed→cancelled/overwrite, capacityreceipt+copiasmandatory y límites±1. Reserva
output aceptada no crédito doble; nil≠zero/ancestryusage no doblecontribución.
BaselineCONTENT+hash antesedits/reporttemprano; focal/legacy/compileWA/formatdiff,
no FULL rutinario antesproductor integrado. No claim VM/liveauthority recheck.

## Success terminal CAS recibido; revisión pendiente

Worker ses_f1323348cffepePO0g3y65fYJT TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-success-terminal-8v_93fvc/REPORT.md SHA
dca60821a352beddb2d0e91b24ef58b98125fecffa119ac393c761f6cf3c83aa cotejado y10/10hashes.
Runtime Frame/Record/Transition/ToolEvidence+2newtestfixture+docs4; oldtestsintactos.
Owner316incl12new/471.4s y7probespreviosmismos5+2/compile115WA/formatdiff0; fuentes
selladas antesgates, verificadas después. step_output narrow deriva resultado de
Modelconfirmado/plain o typedatestación; step/rootcomplete+refundatomic sinmathnuevo.
PlainresponseACK reserva copias/receipt además typedreserve. ABCnestedmixed2delegates
pause2/decide/reclaim/Dtypedretry/wrappers/Bfinal/Crootclosed realCAS roundtrip.
Fixtureintegrada usa tool_return_bytes4096 por reserva8MiB, capacidadseparada65536;
no reducción de límitesproducto ni promesa255nodoscapacidad. Record/getcompleted
data-only sí; Composition.resume10 incluso terminal sigue CERRADO guardRestore.
Intención reviewerfresco delta10+globalclosure/refund/prefix/capacity/adversarial
probes; no aceptaciónproductor10/VM/fatal/recovery. ROOT/build exclusivo checks.

## Success terminal recibido; siguiente cierre fatal10

Reviewer ses_f1301d42affePuJercSlnt6L7x TERMINADO/liberado favorable interno.
REPORT /tmp/opencode/frame10-success-review-YjmLU4Mf/REPORT.md SHA
4e861ad95edb21d7000388e2ac05ae258ee03762c0d32f347f7c0e7755ae684c leído/hashOK.
Padre10/10fuentes, copia reversible runner+2probes a
/tmp/opencode/success10-parent-mi886fkc/:4pass/33.5s/exit0, mismos4review no adicionales.
Review75selected+4independientes/compile115WA/identity295+seals6/10. Cierre exitoso
steps/root CAS recibido INTERNO; no publicresume10/producer/VM/livequiescence/R6.

Próximo frente autorizado fatal/output_failed/exhaustion10 vía operaciones CAS reales
con globalcert para cadaestado admitido. Aplicar esquema sellado fatalorigin root/
node/call y selección determinista entre errores CONFIRMADOS; pendingambiguity nunca
borrada para fabricarfailed. Cierre permisos nuevoIO; trabajo yaadmitido puede drenar,
sin prometer preempciónatómica. Callblocked conserva source/raw/observación previa,
sin ToolReturn fabricado; completed/failedchild no cambia a cancelled. Cancelled
descendant sólo rama aúnno terminal y sin reinterpretar efecto externo como nohecho.
Rootfailed sólo tras fronteracierre legítima/sin activowork incierto; refundúnico
matemática existente, failedRecord/get/Continuationstatus integrados sin activar
Composition.restore10 ni reintentos/reconciliación administrativa nueva.
Outputretryexhaustion/fatal certificado con request/history/counts exactos, nunca
inferir de statusunknown o textoportable. Legacy7/8/9 sinnuevofailedstatus permitido.
Allowlist Frame/Record/Transition/ToolEvidence/OutputResolution/Continuation +Budget
sólo integraciónfailed10 sinmathcambio, tests/support/docs4. Retry sólo guard si
failedstatus o callbackuncertainty exige mantenerbloqueo (NOretryadminnuevo). No
Writer/ExAgent/Composition/Restore/Scope/Store/Authority/ScopeLedger/RequestData/
Outcome/Retention/OTel cambios sin causalidad y autorizaciónprevia. Producer10,
recovery/uncertainreconciliation y cancel/expireAPI generales quedan fuera.
Tests realStoreCAS mixedsiblings/delegatenested/concurrentconfirmederrors ordered,
retención/controlerror/outputexhaustion, rawpreserved/cancelledwithoutfakeoutcome,
noIOafterfatal/deferredadmittedresult beforeclose/refund/replay/mutation/earlyclose,
closurecapacitymandatorycopies/receipts y legacy. Entradasworkertrusted sintéticas:
no real workerdrain/VMclaim. Baselinecontenthash/reporttemprano/focal/gatesfinales;
no FULL rutinario previo a producer integrado. Review y probespadre antesaceptación.

## Fatal drain parcial recibido; oráculo capacidad autorizado

Worker ses_f12f6024effeuv8S0Q5zgHasOW TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-fatal-cas-xclmgyda/REPORT.md SHA
886558db4b3e89bb69c86ced301f4131347368de0d9aa1dc47b6979f5b8aaa0c cotejado y9/9hashes.
Sólo fatalcallsettle confirmado/frontierdeterminista/nuevasadmisionescerradas/drain
outcome+settle/reservafrontier implementados; raw/host/node/rootfatal/failedterminal/
exhaustion/blocked/cancelled aúncerrados.10newgreen, selected114/115exit2, legacy4,
compile115WAformatdiff0; NOgateverde ni aceptaciónsubset por esosdatos.
Padre inspecciona frame10_closure_control_test.exs320–350: constant1714951 impide
through_dispatch por nuevareservafrontier, no alcanza prueba raw65536±1. AUTORIZADO
adaptar ÚNICAMENTE ese test y helpercausal de cálculo threshold si necesario:
derive admisión suficiente a partir reserva actual/flujo real, no número inflado ni
recordedit para simular admisión. Mantener exactraw65536±1/overboundinvalidrecord/
rowunchanged y cierrecompleto del rawaceptado. Añadir original1714951 como negativa
temprana explícita antesdispatch/noeffect, fila anteriorintacta. No borrar viejo caso,
subir productionlimits/quitarreservafatal ni aceptar error en cualquier fase.
Mismoowner cierra oráculo yregresiónverde, entrega deltaexactoldtest/logs/hashes;
sin ampliar ahora todo fatal en contexto gastado. Próximo frente restantes cierre
fatal se despachará sobre baseprobada; mantenerREPORTlista49–60 yreviewpendiente.

## Fatal oráculo verde; siguiente failed closure de callfatal

Worker ses_f12f6024effeuv8S0Q5zgHasOW TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-fatal-oracle-xlzx8r23/REPORT.md SHA
91a344f54bfe75b7953dfd50e2de4a2b79ca7708739e86f2d06963f588ecc103 cotejado,
final-cumulative10/10OK. Runtimefollowupintacto; oldtestthreshold deriva máximoCAS
prefix+reserve ynegativo1714951 rechazaexactbegin_effect sin toolintent.116selected/
18focaloverlap/legacy4/compile115WAformatdiff0. No reviewindependiente fatal todavía.
Siguiente workerfresco acotado sobrecallfatalactual: blockedpreservando source/raw,
cancelledstructural elegibles y failed-rootclosure/refund/facade. Prioridad flujo
callfatal→drain yaadmitido→cierre realCAS, no otraentrega helperssólos ni misión todos
orígenes a lavez. Rawfatal/hostfatal/rootnodeorigins/outputexhaustion quedan explícitos
pendientes ycerrados, no retiradosdelobjetivo. Mismaallowlist fatal previa; worker
puede ampliar certificados para blocked/cancelled sin fabricatedreturns ni reinterpretar
externalintent incierto. Hooks ambiguous siguen bloquear failed, no reconciliación.
Review acumulada fataldrain+closure después; fuentes/docs/testdelta ycapacitymath
trazables, noafirmar116 como aceptación independiente. No productor10/VM.

## Failed closure recibido; revisión acumulada fatal

Worker ses_f12d948bbffeB5XuLp6DFtYCSA TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-failed-close-5pbswx2_/REPORT.md SHA
95a24abf254b6f6ac54660b899d00076fd6088adfba5e85b2873b6ca14ac245f cotejado,
final-cumulative13/13OK. Runtime6 Frame/Record/Transition/ToolEvidence/OutputResolution/
Continuation,8newcases+causaloldfatalfinishnegative+docs4; Budgetmathunchanged.
Owner150selectedincl8new+legacy4/compile115WA/globalformatdiff0. Históricos capacity
sumalternativessuccesscancelrojos preservados; fixmaxalternativasconreserveindependiente.
Confirmedcallfatal→admitteddrain→blockedrawpreserved/cancelledeligibles→failedroot,
refundúnico/get:failed/deletecutoff; structuralreset/publicresume10 cerrados.
Intención reviewerFRESCO acumulado13desde prefatalbaseline (NOsólofailedclose12),
causaloldoracles/frontierselection/ambiguity/closurecapacity/globalcert/statusaudit.
Raw/host/root/nodefatal/outputexhaustion/recovery/liveproducer aúnpendientes explícitos.
ROOT/build exclusivo reviewerchecks, no aceptaciónfatal ni VM/R6.

## Revisión fatal bloqueante P1: control final sin crédito materializado

Reviewer ses_f12bae14bffePHw4aMUpM2Eqs5 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-failed-review-HMGSMUOe/REPORT.md SHA
3ae72d2095bd1ab1906872abd3fd1964c3f7b7f564d0edaba1b28fd2276b5bac cotejado.
52selected+4legacygreen; boundaryfinal1/2 exit2 MISMO P1 real,13/13+469intactos.
SourceMAXantesfatal1378383 (call_wrap rev50) admitecallback; fatal4096JSON settlement
requiere1382090 (+3707), exact/+1 rechazan record_limit, wrapping queda incierto y
finishrefund bloqueado. Source−1 rechazo temprano correcto; roomy1382090 cierra.
TodosreceiptIDs512escaped/returnbound4096/nestedsuccess+cancel/rawretained. Sin nuevoIO
entrewrapperACK/fatalsettlement. No imputar riesgo max(success,cancel) no demostrado:
hallazgo es composedreserve finalcontrol +fixed16384 siguecobrada almaterializar.

Fix autorizado Record como primeralcance; Frame/Transition/ToolEvidence sólo causal
necesario, tests/support+docs4. Reservar/cargar correctamente cada copia obligatoria
bounded finalcontrol/receipt ANTEScall_wrap y crédito exacto almaterializar, conservar
frontier/cancellation independientes. No subirlimit, bajarpayloadsoportado, borrarraw,
relajarguards ni medir threshold sólo sinks. Repro boundary_test.exs+fixture.exs en
copiasnuevas con __DIR__, originals intactos, testtimeout600000 explícito ademásshell.
Rojo→verde contractual sin cambiar expectativasoriginales; permanente source±1/
roomy/mixedsiblings/escape4096/controlnil/success/nonfatalcredits y no doblecrédito.
Mantener unsupportedorígenes/recovery/productor10 cerrados y legacysemantics.
Re-reviewmismo reviewer luego probespadre; todo fatal aúnnoaceptado.

## Fix control/recibos recibido, re-review pendiente

Worker ses_f12adf349ffeI89QmVkTF8DGW0 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-fatal-capacity-fix-n87qjASq/REPORT.md SHA
1f1423f27ef2bf360451a8eca7b2038af853f467a1bf622b202e85eea81c987b cotejado,
final-cumulative15/15OK. RuntimeRecordonly+2newtestfixture+docs4. Separa4116finalcontrol
delallowance16384 fuera maxalternativas y acredita sólo growthmaterializado. Child/host
settled consume1receiptpropio; effect ya lo consume(raw_or_future), no doblecrédito;
resolution consume1de2 yconsumedpool0. Owneroriginal2probes idénticos1/2rojo→2/2verde,
134incl6new+legacy4/compile116WAformatdiff0. Diagnósticoschildreceipt/successresolution
rojos preservados; no afirmar tests6 baseline todosrojos. Source1378383exact/+1 ahora
cierra, −1 rejectearly. Intención reviewer original delta7 y acumuladofatal15/proof
reservacontrolreceipt/siblings/calltypes; no aceptaciónhasta review+probespadre.

## Callfatal/failed closure recibido; siguiente output exhaustion

Reviewer ses_f12bae14bffePHw4aMUpM2Eqs5 TERMINADO/liberado favorable internoacumulado.
REPORT /tmp/opencode/frame10-fatal-capacity-review-cnp7csqf/REPORT.md SHA
ac8c5370baafb7f83b1d13551c0a8301ab0cb818e6b78e24ca649dc2dd0ada46 leído/hashOK;
padre15/15fuentes y copia reversible runner/fixture/boundary/conservation-final a
/tmp/opencode/fatal10-parent-b0aqy4er/:4pass/95.2s/exit0 (mismos2original+2review).
Reviewer23selected+2original+2new+4legacy/compile116WA/identity471intacta.
Callfatalconfirmado/drain/failedclosure yfixcapacidad recibidos INTERNO; no VM/live/
producer10/otrosfatal/recovery/R6. Límite1378383exact/+1cierra;−1earlyreject.

Próximo frente acotado: output retry EXHAUSTION certificado y fatalorigen NODE10
asociado únicamente a ese hecho confirmado. Derivar límite/counter/history/source
desde RequestData/outputresolution/evidencia exacta; sinfake nextrequest ni callbacks
en decode, sin convertirunknown/stringportable en prueba. Atomicidad atestación+
nodefatal/frontier y cierre rootfailed reutiliza drain/blocked/terminalrefund existente.
No migrar OutputResolution legacy, preservar bytecontratos7/8/9; errorportable esquema
actual. Definir selección determinista call/node conforme esquema sellado, no arrival.
Ambigüedad callbacks/efectos prima sobre terminalclosure; trabajosyaadmitidos drenan,
nuevasrequests denegadas. Paused/reclaim/finitebudget/ancestryaccounting intactos.
Root-origin fatal genérico/raw/host/retention otrosorígenes/recovery/producer10 siguen
cerrados en este frente. Si agotamiento no puede expresarse sin ampliar contrato
persistido, traer contradicción/decisión mínima antes inventar campos/versiones.
Allowlist Frame/Record/Transition/ToolEvidence/OutputResolution; Continuation sólo
integraciónestado certificado existente; tests/support/docs4. Budget/ScopeLedger/
Authority/RequestData/Outcome/Retention/Store/Writer/ExAgent/Scope/Composition/Restore
fuera salvo bloqueo causal autorizado previo. No nueva refundmath ni adminretry.
Tests realCAS límite0/1/N ymutacionescounter/source/fingerprint/orphan/position,
currentvsconsumedhistórico, mixednode/callfatalarrivalorder, declineIO/replay/fence,
refundúnico/unchangedusage/capacitysource±1/error4096/escapedreceipts, legacy.
Focales/gates pertinentes baselinecontenthash/reporttemprano; reviewantesaceptar.

## Decisión terminal retry autorizada

Worker ses_f127f60b3ffe6h5Dzhy2jnqm8P TERMINADO/liberado antesedits. Padre lee REPORT
/tmp/opencode/frame10-output-exhaustion-g7ghhz5t/REPORT.md SHA
56fdef60516363f7ef5a69eac47cd275bd07fcf649c511f346146c0bb2078cc4 cotejado y código
ExAgent2697–2713: finalRetryappended sin usedincrement ordinaryexhausted. Probe3
negativos y25existingpass NOimplementación;453existingintactos/18ausentessegúnowner.
Padre AUTORIZA propuesta semántica acotada finalschema: decisionretry diagnóstico
terminal10 único/current/exactused==limit; appendunaveznocounterincrement y nodo
failed/fatal atomicamente. No nuevoskeys/enum/version, legacyigual. ExcluirSOLO
atestaciónterminal certificada del conteo permisosconsumidos, no restageneralhistoria.
Mismo worker retoma implementación0/1/N+mixedfatal+failedclosure+capacity; sin reabrir
aprobación ni entregar sólodiagnóstico. Nuevo blocker concreto antes ampliar esquema.

## Output exhaustion recibido; revisión independiente pendiente

Worker ses_f127f60b3ffe6h5Dzhy2jnqm8P TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-output-exhaustion-resume-ccw8mexa/REPORT.md SHA
42355950e4374bd477ee4c6686729818dd052d2bb31573d456c84fbbbf8d98a7 cotejado,12/12hashes.
Runtime5 Frame/OutputResolution/Record/ToolEvidence/Transition+newtestfixture+old2
casos causales+docs4. OutputResolution1retry terminal único/no usedincrement,
nodefailed/history/raw/frontieratomic ymixedcallnodeorder. Owner164incl9new+166legacy
(86locationexcluded)/compile117WAformatdiff0. Sourceboundsmixed1213099/step234759
reportados beforefatal, previouscallfatalbounds siguen verdes. Reserva failedalternative
diagnosticcopies/descriptor ytree receipt3→2, retira wrapper/history slots sólochild
failed certificado. Fuentes8selladasbeforegates; docs4proseafter. No aceptaciónaún.
Intención reviewerFRESCO delta12 semánticaexhaustion/selection/capacity/preimagebounds/
legacy/oldoracles yprobesindependientes; ROOT/build exclusivo checks. Generalrawhostroot/
retentionfatal/recovery/producer10 quedan pendientes, no aceptar por pruebaslegacyVM.

## Review exhaustion bloqueante: reserva compuesta con siblings

Reviewer ses_f125440e9ffe8uprKa6ZWiUb7R TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-exhaustion-review-b9k4uBqI/REPORT.md SHA
2bbfa230b41ff67e2f89d57a7de65864ecd04d13ea5168a8cbb62b197aca6e58 cotejado.
P1 Record159–163: max(success+output,failed+exhaustion) insuficiente si reservas
success de siblings siguen dominando después de materializar copias exhaustion.
RealCAS BdelegateD+3plainsiblings/toolbound4096/descriptorJSON65536/diagnostic4000
controlbytes dentro Retentionbound4096, maxescapedreceipts. Source837930outcome
exact/+1 admite luego output_resolution record_limit;−1earlyreject;866148 cierra
refund59983. No rowsforged ni oversizedtrustedpayload.24selected+legacy4green,
boundary1/2exit2,455sources/982artifactfiles intactos; noaceptaciónexhaustion.
Fix autorizado Record primero, demás Frame/OutputResolution/ToolEvidence/Transition
sólo causal; tests/support/docs4. Calcular mandatorycopias+reservasSIBLINGSremanentes
antesadmisión sin préstamo cruzado ni sinkthreshold. No subirlimit/recortardiagnóstico/
quitarguards. Originalboundaryoráculo conserva source−1early yexact/+1closure;
permanentes descriptor65536/multiplesiblings/JSONescape/counts/receipt y crédito
materializado independiente. Probar cota por composición de fases, no sólo ese caso.
Reviewmismo hijo despuésfix, producer/recovery/off ysemántica terminalretry intactos.

## Oráculo roomy externo: corrección puntual autorizada

Worker ses_f12481a56ffeWKiq35fMDNikl3 TERMINADO/liberado, candidataRecord+docs4
conservada. Padre lee REPORT /tmp/opencode/frame10-exhaustion-capacity-fix-slV6LFp7/
REPORT.md SHAd5f3a5bb6dfaa9a3cad56d2929243c3369908760cf3e934a5d0d7d2ea4813e3a,
hash5/5OK. Candidata fuente868234→sink866148;source−1early/exact+1close ya pasan,
originalboundary1/2rojo enroomy fuenteconpresupuestoSINK. Padreinspecciona original
boundary_test.exs57–94: línea87 source(s,sink) no demuestra controlholgado cuando
sink<source. AUTORIZADO únicamente COPIA nueva línea87 source(s,Record.max_bytes())
y etiqueta92 correspondiente. Mantener sinkdiagnóstico66, todasassertionsboundary93/
refund90–91/sourceprefix derivation intactas. Originalarchivo/logsredinmutables.
No aumentar productionlimit ni sourcebudget±1, no declarar originalverde. Documentar
diffexacto/oráculo corregido separado ycasual explicación. Mismoowner continúa matriz
permanenteampliada/proofcomposición/gates; no aceptación por9tests existentes.

## Matriz exhaustion capacity recibida; re-review

Worker ses_f12481a56ffeWKiq35fMDNikl3 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/frame10-exhaustion-matrix-60bpPK5e/REPORT.md SHA
8631112f44103978a4b31530f67ccb10a4640b4c10e6dbe42e8e7870fa6b6b88 cotejado,7/7hashesOK.
Recordcandidata8a9f5de5 intacta desdehandoff;newcapacitytestfixture+docs4. Owner10new/
69selected/10oraclelegacyoverlap, compile118WAformatdiff0. Oráculocopia autorizado
exact2líneas final2/2verde; autoformat inicial detectado/preservado y copiaexacta
reconstruida/rerun, originalredinmutable. Source868234/sink866148,−1early/exact+1close.
Matriz8variantes preimagesmall/max/history/siblings0–6/multiplenodes/escaping/bounds
256/4096/65536 y2mutations/rawsizeguard. Fórmula S+sumpositive(Ei-ownsi) vs
F+sumpositive(Ei-ownfi) propuesta probar review, no compartir crédito de siblings.
Intención mismo reviewer delta7+exhaustion previo/proof/oráculo2líneas/newprobes;
ROOT/build exclusivo checks, noaceptaciónP1/Frame10producto aún.

## Revisión composicional: handoff incompleto, propiedad retenida

Reviewer ses_f125440e9ffe8uprKa6ZWiUb7R notificó4/4repro+boundary autorizado verdes,
pero selección aúnactiva/3probespropios pendientes, explícitamente NOdictamen ni
ROOT/buildrelease. Padre continúa MISMA sesión para concluir gates/probes y reporte;
no nuevo worker ni build concurrente. Mensajecompleted delruntime no demuestra
proceso terminado; evidencia parcial no aceptada. Propiedad exclusiva sigue reviewer.
