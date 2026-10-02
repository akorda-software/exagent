# Especificación propuesta Frame10 — revisión independiente antes de implementar

**Contrato ya decidido/revisado antes de 2026-10-01.** Este archivo conserva las
enmiendas técnicas vigentes; su título y mandatos preliminares no piden otra revisión
de propuesta. Ejecutar con `delegation-runtime.md` y el flujo simplificado.

Fuente researcher ses_f145c1988ffes6uJzDi6LT6lZG; sólolectura. Padre acepta justificación
de cambio combinado links/control/frontera y DIRECCIÓN3decisiones abajo, no autoriza
escriturasproducto hasta revisióncontradicciones. Contrastar runtime actual, no asumir
viabilidad por propuesta. Complementa structural-delegation.md.

## Dirección recomendada

Frame10/Record2/Execution2/ScopeLedger2/Approval1. Nuevos Composition.run producen10
una vez unidadautorizada; resume conserva lifetime7/8/9/10, sin opciónmodo permanente,
sin automigración ni mixed9reinterpretado. Oldreaders rechazan10. LeafFrame3 se conserva.
Terminalexecution failed SÓLO10 y operaciónfail conrefundmismaaritmética Budget.
NoRecord3/Approval2/Scope3/Storechange a menos impedimentodemostrado.
Approvaldrain yaadmitido, fatalblockpendiente, uncertain impidepause/failconfirmado.
Hostresolver explícitoboundedref para durabledelegate; ordinarioagent/buildercompatible,
cero callbacks preclaim, closedhistórico noresolver/codec/build.

## Esquema exactkeys propuesto (opcionales presentes null)

Frame10 conserva kindsequence/run_id/binding/input/scope/children/output_resolutions/
tool_batches/authority. cursor empty|running|between_steps|completed|failed. Añade
frontier={epoch>=0,state open|draining|quiescent,reason null|approval|fatal,
fatal:null|{run_id,request_id,call_id,error}}. Inicial0/open/null/null. Primera
suspensión incrementaepoch; fatal puede sustituirapproval no alrevés. Pending/ready
postpause quiescent hasta nuevoclaim/import/frontier_open.

Node exact={parent_run_id,link,definition,policy,model_ref,output_ref,frame,snapshot,
status,result,result_omitted,error}. status running|suspended|completed|failed|cancelled.
StepLink={kind:step,step_id,index>=0,inputJSON}; parentraíz, únicosprefixA/B/C.
DelegateLink={kind:delegate,parent_request_id,call_id,tool_name,call_hash,schema_hash,
argsJSONobjeto}; parentcallconfirmada única(run,request,call). Delegadooutput_refnull
usa output_fingerprintdescriptoractual; pasosoutputrefobligatoria según contratoactual.
Todosrefs existing{id,version}, IDsRecord.text?, hashdigestactual. NingúnPID/module/
función/secretpersistido. Exactchildren+root=ScopeLedgernodes=authoritynodes; parent
chainconectada/acyclic/noorphan. Completedchild NOimplica wrapperparentliquidado.
Suspendedconserva cursorleafreal, nofinishfalso. Failed/cancelled sinoutputinventado.

Batch10 exact={run_id,request_id,limits,observations,calls,resolution,consumption}.
Calls mapCallID→Call10; orden ORIGINALmodelresponse noarrayduplicado.
resolution null|{tool_retries:map,error}; consumption null|{history_index,returns_hash}.
Call10 exact={state,binding,source,result,control,blocked_by}.
state queued|preparing|prepared|approval|dispatching|child|wrapping|settled|blocked.
binding null|{tool_name,args,schema_hash,call_hash}; source null|{kind:effect,id}|
{kind:child,id}|{kind:host,reason:HostReasonenumexistentespredispatchreales}.
result EncodedToolReturn|null; control null|{retry:boolean,error}; blocked_by null|fatal.
Queuednada; preparingcallbackiniciadoambiguo; preparedbindingACKnorepeatbeforehooks;
approvalbinding/nodispatch; dispatchingcanonicalintent; childlink/noparentwrapperresult;
wrappingrawsourceconfirmado/callbackiniciado; settledresult+control/accountingconfirmados;
blocked fatalANTESsiguienteacción noresult/controlinventado, puedeguardarchildsource
conefectosprevios. Noafirmarblocked=tooleffectnever.

## Approvals/transiciones/consumo

Durante drain Callapproval+binding solicitudstaged, NOApproval1revisionprovisional.
Pause creaApproval1 allstaged requested_revision=pauseactual, existingIDrunrequestcall;
refs nodoexacto, ancestryinmutable validada journal (no añadirancestryhashApproval1).

Opsnuevas estrechas:
node_attach prepared→child añade1delegado/scope/authoritycorrelacionados;
call_prepare queued→preparingACKANTESbeforehook;
call_prepared preparing→preparedbindingACK;
call_wait prepared→approval/iniciadrain;
call_wrap rawconfirmed→wrappingACKANTESafterhook;
call_settle resultadofinal/control/evidenceCONFIRMAJUNTOS;
frontier_close fatal/suspensión, node_suspend running→suspendedpostworkers;
frontier_open nuevoclaim/import/reactivación; batch_consume appendreturns exactuna vez;
fail knownfatalquiescent. Ops workerowner/attempt/fence/epoch/targetphaseexactkeys;
NOgenericpatchnode. tool_resolution finalreducer actual y delegation_outcome evidencia
retornodelegado reutilizados internamente, sin doblecaminoequivalente.
Preparedapproval→prepared tras nuevoclaim/aprobación/currentpermissionchecks; ordinary
begin_effect→dispatching→raw→wrapping→settled; delegateattach→childterminal→wrapping→
settled; hostdeny→settled sóloresultadoobservado. Recheck justoantesIOdespuésACK.

Controlacumulado sin mutartool_retries cadaresultado; todossettled→reduceordenoriginal→
tool_resolutionACK→batch_consumeACK índice/hashreturns→nuevorequestModel. Fatalpartial
blocked no reset/successfalso ni fakeToolReturns alModel; errorpartialknownreturns.
CrashDcompleted/callchild permite wrapper sólo tras newclaim/call_wrapACK (noDreplay).
Crashwrapping/preparing inciertocallback NOautorepeat. settledsinresolution puroreduce;
resolution/noconsumption appendúnico; consumedcontinúa. Record.unresolved?10 incluye
callbackmarkers además externalintents; querydistingueeffectuncertain/controluncertain.
No adminautomaticresolve de nuevos estadosambiguos en estaunidad.

## Fatal / quiescencia

Askdrain, fataldomina, nonewcallbacks/effects pendientes trasfatal. Yaempezados drenan
hasta límites; unkilledcallbacks no declararnoeffect. Retry-limitfatal sólo reduction
ordenada demostrada, no saltarpending quepuedereset. Variosfatales ordenestable
stepindex→delegationcallpositionspath→requeststep→callposition, noarrivaltime/PID/runID.
Otroscontrolespreservados. Allknownclosed→fail/RunError/noc; ambiguous→uncertain no
pausa/failfalso. Stagedapprovals no publicar sifatalgana; historyapproved noborrar.

Writer único serializedadmission/epoch/startpermissions. Alcerrar noModel/nuevobatch;
approvaldrain permitecallsqueued debatchyaadmitido; nuevodelegado puedeattach/inputsin
primeraModelrequest. Fatal tampocoqueuedcalls. Revalidarpermiso inmediatamente
antescallback/IO, no prometer atomicpreemption. Scope registraproductor/tasks/descendant
workers ANTESpermiso, PID/refexactos node/attempt; taskfin sóloposthook/obs/ACK y
coordinador esperaresult+DOWN, done-message no prueba. Rootclose bloquealate-registration.
Writer/coordinador noIObut realcallbackworkers síinventory. Node_suspend exige noown
tasks/operationsactivas y descendantsclosed/suspended/terminalcompatible.
Rootpause exige frontierdrainingapproval, activessuspended, liveworkers0,
no durableuncertainty, allcallsclassified/allknowncontrolpersisted, stagedapproval>=1,
Scopeexportexact y capacityreserves. Store valida datos/certificado, NOconsultaPID;
liveguarantee Writertrusted, crashfence+recordproof nuevoowner noACKinventado.

## Hostresolver / scope / budget

Nuevaopcióndurablecomposition delegate_definitions:[{definitionRef,policyRef,model_refRef,
load:fun(context,effective_args)->{:ok,agent,child_options,codec_config}}]. Hosttrusted
callbacks directos, noJSONmodulelookup/globalregistry. ≤nodecap/refs únicasnoambiguas.
Descriptor continuation actualdelega seleccionarefs exactas, mismoresolverdurable run/
restore (no dosbuilders). OrdinarioCoordination.delegation_tool agent|builder intacto.
Preclaim purorecord/boundary/compositionbinding/catalogarity/refs/capacity/activenodes
presence; closed nodes noentrada requerida. PostfreshACK deadlinecheck→resolveactive
topológico/authorityintersection→activecodec/modelinventoryschemaoutputlink→importtree
once→recheck→frontier_open→execute. LosingCAS0loaderbuildercodec. Invalidreturnedhost
binding puedeconsumirclaim pero noIO. Referenciaversiónnoequivalenciacódigogarantizada.

Scopeimport topológico raíz→B→D, closedinertes/activehostconfig y ledger2exactuna vez,
no batchreadmit/noreprice; delegate returnusage=nil nodedebit. Budget sólo raíz,
norefundD/noplazorenewperchild, pausequiescent/finalfail refundsharedarithmetic;
finiteabandonedagotado. Original∩currentroot/B/D floorssingularplural ylogicaldeadline
viejosnobroaden. Approvals request/ruta exactas no currentdenyoverride.

## Capacidad / compatibilidad / alcance

Preservar8MiB/256effects/1024receipts; nuevoslimits255nonrootnodes/depth16 (propuesta).
Antesbatchcallbacks reservarcallphases/dispatchattach/wrapsettle/resolutionconsume/
boundedresultcontrol/pausedecisions/terminaluncertaincleanup; attachnode/snapshot/
authority+closure. Caminomáscostoso nofeliz, nohistoryeviction. Verificar viabilidad
realexistingquota/receiptids/maxid/errorbounds antesprometerreserves.
Terminal10 completed/failed/denied/cancelled/expired inspeccióndataonly sincatalog/codec;
failed error+partial nunca niloutputsucedido. Condicional failed terminalguards
Retention/Record/Transition/Budget y façadequery; StoreSQLenvelopeenum validar supuesto
sin tocaradapter si nonecesario. R6general/SQL/backend/publicación fuera de gateoffline.

Allowlistprevista12core: ExAgent,Writer,Frame,Record,Transition,ToolEvidence,
CompositionRestore,ExecutionScope,Composition,Delegation,Coordination,Budget failrefund
únicamente. Condicional Authority/ScopeLedger/Outcome/Retry/OTel/Continuation sólocausa;
Store/SQL/ReqLLM fuera. Aún NO permiso ejecución/ediciónproducto.

## Checkpoint/matriz

Checkpoint completo Aeffect→Bsiblingsettled+delegateD→Dmixedsiblingsettled+2asks→
allDOWN/rootpause→partialdecision→finalready→freshVM→Dfinal→CRASHanteswrapperB→
recover→wrapperB/control→Bfinal→C sinDreplay. No format-onlyentrega.
Cerrar mismaunidad variosdelegados/nieto, VMcutsenprepare/wrapping/settle/resolution/
consume (uncertain no replay dondeambiguo),2claimants0losercallback/fencestale,
ACKtodasphases/tokensStoreonly, deny/CASdecisions, fatalaskrunning/deterministicfatal,
retryreset/hooks transforms, authorityrefsargs/schema, ancestralbudgetcostonce,
±1nodesdepthreceiptsJSONcleanupcontrolapprovalstokenparse, legacy7/8/9 yterminaldataonly,
OTelancestryintentospausepartial sinsecret/doublecount. Después routingfanoutfanin,
no añadir schedulerahora. Reviewindependiente diseño decidirá contradicciones antes
sellar implementación y archivosprecisos.

## Revisión independiente y reemplazos obligatorios (prevalecen sobre propuesta)

Reviewer ses_f1451a03affe1LB0QiPylcgij0 dictamen estático: direcciónviable pero bloqueado
hasta concretar8huecos. Padre ADOPTA correcciones siguientes; no dejar alimplementador
elegir semánticas. Última relectura reviewer comprobará consistencia, no nuevainvestigación.

### Raw y admisiones atómicas

Call10 añade clave EXACTA raw:null|{result:EncodedToolReturn,control:{retry,error}}.
Resultado/controlfinales siguen null antescall_settle. Raw+observación/accounting+
effectreference se confirman en MISMAtransición (operaciónraw existente adaptada10),
antescall_wrap. Hasheseffect/Callraw/LeafFrameoutcomes consistentestienenúnicoorigen;
no copias como autoridades alternativas. Call_settle final+control+atestaciónfinal
enMISMACAS. Childterminal→raw mediante conversiónPURA output/error, noD/hosthookreplay.
Begin_effect10 ES prepared→dispatching+sourcecanonicaleffect+intent enMISMACAS,
binding/epoch/fence exactos. Node_attach preparado→childsource+Node+Scopeauthority
enMISMACAS. No nueva fakeexternalintent para hooks/delegados. ACKfresh+time/fencecheck
antesIO, lostACKreceipt no concede ejecución. Crucesphase/effect inválidosrechazados.

### Callbacks y rehidratación

Hookstool before/after son invocacionesautorizadas marcadas preparing/wrapping; crash
sinconfirmación conserva uncertain, NOautoreplay (no exactlyonce de todoscallbacks).
Resolverload/codec son REHIDRATACIÓNREPETIBLE sin efectosdenegocio por contrato host:
pueden repetirse entreintentosganadores/VMs, nunca garantizar atmostoncegeneral.
Buildersconefectos noadmitidosdurable10; ordinario siguecontratoanterior. Dump también
puedeejecutarse al capturar, no prometer unicidad. Registro de todo callbackbloqueante
incluyendo loader/codec y observability, scopesmonitores antes trabajo; closednodos
nunca carga/model/build. Si una fuenteefecto síestáincierta, purerehydration noautoriza
repetirla. Markerscallbacks requieren Record.unresolved10 además intents externos.

### Protocolo vivo de drenaje

Cerrar NUEVOSPERMISOS no toda inscripción. Permitido registrar workersdecallsyabatch
admitidas durante approvaldrain; no Modelnuevo/batchnuevo. Permisoconcedidopreclose
que entra después cuenta trabajoYAadmitido que DEBE drenar: recheck reduce ventana
pero NOprueba atomicpreemption. Workeridentity={attempt,node,batch/call,role}, PID/ref
exactos vivos sólomemoria. ResultadoACK+DOWN necesarios para retirar inventory,
donemessage solo insuficiente. Node_suspend no finish_run (éste canceldescendants).
Childattachedsinrequest→suspended/cursorrequest. PauseCAS FINAL publicaapprovals+
frontierquiescent+refund juntas; no certquiescentprematuroenrecord. Decision/claim
runtimeintacto; sólofrontier_open trasclaim/import reactiva. Store nunca validaPIDs.

### Fatal y terminalidad

Frontier.fatal reemplaza shape anterior por discriminado null|
{kind:call,run_id,request_id,call_id,error}|
{kind:node,run_id,error}|{kind:root,error} con exactkeys porvariante.
Cierraadmisiones alfatalDEFINITIVO confirmado, errorpúblico determinista entre los
confirmados alfindrain. Ordenestable rootantesnodos, nodosporstepindex+delegatecallpath,
nodeantescallspropias y callsrequeststep/posición; sin PID/randomrun/arrivaltime.
Retrylimit no inferir conpredecessorpendingreset. Blockedconserva source/raw/obs
existentes, no finalresult/controlinventado ni wrappersNUEVOS despuésfatal; yaadmitidos
drain o uncertain. Failknownquiescent permiteblocked/sinbatchconsumption, no history
fabricada. Si control/effectambiguous→uncertain, nofailpause falsos.
Terminalfailed10 integrar OBLIGATORIAMENTE Recordreceipts/status/terminal/delete/reset,
Transition/failrefund, Continuation.getprojection; no statusnil. BudgetfailusaMISMO
refund/confirm_refund sólo10. Record.unresolved distingue callback/effect; consulta
puede exponer clases conerrores acotados NOdatosprivados. retry_effect/reconcileeffect
jamás borracallbackuncertainty; no nuevaAPIreconciliacióncallbackautorizada.
Retry helpers integrar checks si necesario, guardsglobales anteslocal.

### Resolver API sellada

Top-level opts Composition.run/resume añade delegate_definitions (efímera, NO rootopts
ni WriterconfigJSON). Lista bounded≤255 exactentries atomkeysdefinition/policy/model_ref/
load; refs mapasstringkeys{id,version}formatoportableactual, únicotripleexacto.
load/2(context,effective_args)->{:ok,agent,child_options,%{model_codec:%{dump:fun,load:fun}}}.
Context hosttrustedopaco como descriptoractual, nunca módulosresueltos porJSON.
Durable10 usa EXCLUSIVAMENTE load, nunca llama despuésbuilderoriginal. Promptarg del
descriptorvalidado es única fuenteinput. Ordinary agent/builder permanece intacto.
child_options keyword exactallowlist misma leaf_options Composition actual:
deps/model_settings/prepend_instructions/max_payload_bytes/max_history_bytes/on_event/
on_progress/permissions/approve/estimate_cost/deadline/max_concurrent_requests/
permission_floor/permission_floors. Sin IDs/scope/writer/continuation/injectedframes.
Valores estructurales validados antesusar; retornomodelcodec aridadesactuales.
Restricciones descriptoractual+loader se INTERSECTAN authority/cotas, no permissive
overwrite; persistedoriginal tambiénintersección. Valores noautoridad descriptor
prompt/input y loaderconfig separados sin doblesfuentes. Host agenttypedoutput es
actual fuenteoutput fingerprint, sin delegateoutput_refnuevo. Preclaimrefs/aridad/
catálogoactiveancestorsnecesarios, closed noentry. Postclaimloaderbindingverification
antesIO, losers0callbacks. Noequivalenciacódigo garantizada porrefnominal.

### Inspección y límites

Terminal10 clasificación tras load/Record/reference/portablecompositionbinding y
validaciónformasopts, ANTEScatalogpresence/activeresolvers/deadlinesdeejecución/claim.
Definitionhost composición sigue requerida para binding; sincatalogdelegate≠sindefinition.
failed→RunError+partialconfirmed, no okoutputnil. get siguedataonly; otros terminales
segúncontratopropuesto explícito no activeadmission. Índices/projection/cursor sólo
linkstep, delegates nunca prefijo; rootinputinmutable nunca reemplazadoargsD.
Import closedfailed/cancelled inertes ancestrycompleta mediante ScopeLedger2exacto.
Depth raíz=0, nodosno-raíz≤255/depth≤16 son TECHOS no capacidad garantizada; reserves
worstclosure bytes/receipts/effectsnodephasesantescallbacks. Existing256effects/1024
receipts/8MiB mandan; earlylimit si nocabe, no amortizaciónevidencia/eviction.
No causalSQLenum externo (Postgres envelopebytes transacción), verificar sin certG3.

### Allowlist revisada y gate de diseño

13obligatorios anteriores12+Continuationfacade. Retry permitido sólo integrar
uncertaintycontrol/terminalfailed sin APIadministrativa nueva ni capacidadesretry10
no diseñadas. Outcome/Authority/ScopeLedger/Retention/OTel condicional blockerpadre;
Store/SQL/ReqLLM intactos salvo causaautorizada. No cambiamatemáticaBudget.
Revisión corta independiente de estas correcciones requerida antes permisoedición.
Si quedancontradicciones, bloquearconcaso concreto no resolverporintuiciónworker.

## Decisión posterior: proyección canónica del delegado fallido10

Probe estático owner journal-complete demuestra dos razones distintas con mismo
ToolEvidence.error portable pero ToolReturn legacy diferentes. Padre contrastó
ToolEvidence.error92–120 y ExAgent.delegated_outcome2556–2557. No reconstrucción
inyectiva posible con información descartada. Se ELIGE proyección explícitamente
normalizada/lossy SÓLO10, sin cambiar error/1 legacy ni añadir segunda fuente raw.
Para child.status failed con error portable válido no nil: raw.result ToolReturn
de identidad EXACTA call del padre, status failed, content=child.error.message,
usage=nil, sin payload_omitted inventado; raw.control={retry:false,error:child.error}.
Hash/encodedreturn usa encoder canónico actual. Producer10 futuro y converter puro
DEBEN compartir esta función, nunca productor reason_msg(reasonoriginal) y restore
messageportable distinto. Misma entrada portable produce mismos bytes; no se promete
recuperar razón privada/original. Code/details/omitted permanecen en error/control.
Sin Retention.reason ni callbacks durante conversión; datos ya acotados y validados.
Legacy7/8/9 y delegación ordinaria intactos. Documentar cambio observable/beneficio/
alternativas/migración direccional de10 en diseño/changelog al integrar productor.
Child cancelled por fatal NO se convierte en ToolReturn failed/success inventado:
parentcall blocked conserva source/raw que exista, sin resultado/control nuevo.
Output omitted no se convierte en éxito íntegro; conservar marcador y rechazo seguro
hasta la frontera fatal de retención ya especificada, sin inventar payload perdido.
Success puro conserva output exacto; validación schema/afterhook parentwrapper sigue
su fase marcada, no confundir rawsource con resultado final validado por padre.

## Sello posterior sources/settlement/terminalidad

Research ses_f13f3f1b0ffetOYnR0wFenpfeV sólolectura, decisiones padre aprobadas:
Call10 conserva claves. Variante host UNPREPARED: binding=null, source exacto
{kind:host,phase:unprepared,reason,tool_name,call_hash}; identidadrun/request/call
del batch, nombre/hash ORIGINALresponseconfirmada. Sin args/schema inventados.
Reasons: before_hook_error(not_executed/retryfalse), unknown_tool/malformed_args/
args_validation_error(validation_error/retrytrue), preparation_retention
(not_executed/retryfalse). Cada motivo se captura en punto REAL de fallo, no desde
portableerror colapsado. Host PREPARED mantiene binding válido/source{kind:host,reason},
reasons permission_denied|admission_error. Admissionretention pertenece admissionerror.
Raw autoridadúnica, result/control iguales raw para rechazo sinwrapper. Para errores
10 portablemessage canónico compartido producer/converter, errorportable completo y
status/retryobservados; permissiondeny existente conserva su proyección exacta.
Capacidad antesconfirmarprepare/cierre→rechazar operación, NOsettledfabricado.
CASconflict/lostACK/admissionambiguo NO prueba notexecuted; conservar baseline.

Childwrapperfinal es atestación TRUSTEDPRODUCER vía transición restringida, NO prueba
criptográfica snapshot ni reejecuciónhook. Childterminal→raw+outcomes/obs unaCAS;
call_wrap rawcert→wrappingACK; call_settle exige owner/attempt/fence/epoch/phase,
preserva source/binding/raw/childterminal, final/control+Leafoutcomes unaCAS. Final
puede diferir childresult. Globalcert identity/encoding/control/accounting/history,
no callbacks para recalcular final. Receipt genérico call_settle no certifica call
particular por sísolo. Final/controlconfirmados inmutables.

Child completed/failed NUNCA→cancelled. Rawparent sólo nace de terminalcompleted/failed;
fatalposterior bloqueaparentcall conserva rawsource y terminalchild intactos.
Cancelledchild no produce rawparent; puede conservar raw de sus propias llamadas.
Parentraw+sourcechildcancelled rechaza inalcanzable, no sanear borrando datos.

## Evidencia RequestData2 para10 autorizada

Probe ownertransitions demuestra que RequestData1 sólo conserva tools name→hash y
DelegateLink no persiste prompt_arg; inputdelegado exacto no recuperable del digest.
Padre contrastó RequestData.capture/restore y Frame.fingerprint2034–2044. Se autoriza
request_version2 EXCLUSIVAMENTE contextoFrame10, sin modificar DelegateLink ni Frame
rootexactkeys. Mismos camposrequest1 + tool_descriptors{name→preimagenportableexacta}.
Preimagen EXACTA algoritmo fingerprintactual: definition/kind/takes_ctx/max_retries,
delegation presente sólo cuando existe (NO añadir null si algoritmoactual laomite).
Descriptor delegado versión1 existente refs/prompt_arg portable; sin builder/functions/
modules/credentials. Keysets descriptors/tools idénticos y digestcadauno==tools[name],
no dos autoridades independientes. Validación exactshape/normalización/capacidad y
schema/refs/callbinding antes usar args[descriptor.prompt_arg] como inputD. Hashválido
no da permiso ejecutar módulos/callbacks, catálogo host sigue separado y autorizado.
Captura/restauración2 seleccionadas por versión interna real, no opciónpública de
modo. RequestData1/captureproductor9/restoreslegacy mantienen bytes/contratoactuales.
No automaticupgrade de registros viejos, no descriptor inferido de host aldecode.
Reservas incluyen preimagen desdeadmisión, 8MiB/limitsintactos; no truncar evidencia.
Pruebas prompt_arg no-default con distractor, mutacioneshash/descriptor/refs/schema,
roundtrip y legacy1 exactos. RequestData2 sólo valida estados10 admitidos, productor10
permanece fuera de este checkpoint. Documentar compatibilidaddireccional sinpublicar.

## Output exhaustion10: atestación terminal sin permiso retry

Padre decide tras probe g7ghhz5t y contraste ExAgent.retry_or_fail2697–2713:
mantener OutputResolution1 exactkeys/decision=retry, SIN nuevoenum/campo/versión.
En contexto REAL10 exclusivamente, entryretry currentrequest con fuente Model
confirmada/descriptorfingerprint exactos/used==limit==N y N retries anteriores
consumidos puede certificar agotamiento. Append final attestedparts UNAvez sin
incrementar used. Ese Retry final es evidencia diagnóstica terminal, NOpermisoIO.
Atomicidad: entry+terminalhistory+nodefailed/error+frontierfatal correlacionados,
y raw canónico parent si el nodo delegado lo exige según contratochildterminal.
Nodo fallido/error conserva clase agotamiento certificada, no genérico failed.
Contador cuenta N permisosretry históricamente consumidos, excluyendo ÚNICAMENTE
último intento fallido terminal certificado. Sin offsetglobal −1 ni ignorar cualquier
Retryhistórico. Lastentry única/posiciónfinal/sourceexacto, no successorrequest;
output_consume posterior/newIO denegados, opreplay mismasbytes no appenddoble.
Anteslimit mantiene contrato normal, >limit corrupciónrechazada. Legacy7/8/9 sin
cambios; no reinterpretar históricos. Capacity mandatorycopias/error/raw/frontier
se reservan antes admitir operación/callback pertinente, no reclamar garantía de
payload que excede límites. Mixedcall/nodefatal selecciónconfirmada sellada; parent
failedraw puede quedar blocked por fatal sin inventar wrapperfinal. Refundyambiguity
guard intactos. Documentar problema/alternativas/semántica yregresiones en docs4.
