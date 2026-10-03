# Recuperación de secuencias — diseño acotado, implementación no despachada

Research ses_f15faf5beffezbXpL2ireiG0tP entregó propuesta sólo lectura. Padre contrastó
Budget.claim21–31/abandon87–90 y CompositionRestore.preflight/boundary1–98.
Base aceptada Composition.run Frame9; no reabrir productor/ledger/formato.

## Dirección aprobada por padre, falta precisar contrato de entrada

Entrada experimental Composition.resume(definition, reference, opts), mismo lifetime,
nuevo claim/attempt/fence, único Writer/Scope durante restauración y sufijo. NO nuevo
Composition.run ni relabel singleton ni suprimir prefijo contable.
Subsets Frame9 ready: empty, between_steps prefijo completed con outputs íntegros;
running input confirmado sin operaciones propias; running respuesta terminal texto/
typed-succeeded del subset seguro ya admitido. Completed sigue data-only.
No output-retry/batch activo multileaf, raw/uncertain/intent/approval/delegación/C7.
Singleton7/8/9 mantiene sus subsets completos existentes. Prefijo completed puede
contener tools/retries/usage parcial; no ejecutar/repreciar/deserializar modelos
históricos. Global Record validation y huérfanos permanecen antes del claim.

## Restricciones causales

ScopeLedger.restore exige nodos host exactos. ExecutionScope.join invoca Model;
propuesta helper interno estrecho para nodos históricos cerrados sin modelos/codecs/
estimadores ni handles ejecutables. Padre autoriza diseñar este seam, no cambiar
ScopeLedger exactness/structural flags ni ledger paralelo. Nodos cerrados nunca efectos.
Bindings/index eligen prefijo y activa; no glob effects como si sólo existiera un leaf.
Deadlines: root y activa originales∩actuales; expiración local de completed no cancela
el sufijo. Completed nunca recupera permiso ejecución. Sucesor se limita por raíz.
Budget finito abandonado: active_budget_exhausted sin callback/IO/refund/reset. Positivo
tras crash ilimitado sólo, con lease/deadline/TTL/cuotas vigentes. No cambio Budget.
Input confirmado no remapping; mapping no confirmado puede reevaluarse (puro), no
prometer exactly-once del callback. ACK antes avanzar/IO; token sólo persistencia.

## Seams y alcance esperado

CompositionRestore restore_step44–46 y boundary78 guardan singleton; classifiers
106–139/259–357 deben seleccionar evidencia local sin esconder orphans globales.
ExAgent449–509 crea root+leaf,518–527 cierra Scope; necesita lifetime común de secuencia.
Writer.restore_step503–513 liga activa; empty/between requiere ligar Scope sin activa.
ScopeLedger267–362 conserva árbol/accounting/precios; NO relajar ni cambiar formato.
Allowlist propuesta Composition, ExAgent, CompositionRestore, Writer, ExecutionScope
únicamente helper cerrado; Frame sólo impedimento causal demostrado. No Store/Budget/
ScopeLedger/Authority/Transition. Tests nuevos VM/secuencia +negativasN>1 causales exactas.

## Matriz mínima para futura implementación

VM real betweenA/inputB/terminalB con efectoA una vez y sólo sufijo; prefijo tools+
retries/IDproveedor reutilizado, calidad/costes idénticos sin callbacksA; CAS2claimants
1winner/fence antiguo; ACK claim/outputB/inputC/intentC y replaytoken sinIO; kills mapping/
input/intent/Model/tool con ready vs uncertain/ownedDOWN; budget finito negativo y
ilimitado positivo/terminalrefund; autoridad/cuota histórica/deadlinesTTL; ±1 tamaños
claim/primer checkpoint/sucesor/intent/token con prefijo/reservas; omitted/orphans/
mutation/bindingchanged/retryrawapprovalbatch negativos; fixtures7/8/single9/completed.

Pendiente: especificar reference/opts/result/error phases, rol recover vs resume,
seam helper seguro y descomposición ejecutable antes despacho. Receipt docs previo
sigue con owner independiente; no iniciar escrituras runtime/docs hasta su liberación.

## Contrato sellado tras aclaración y liberación documental

Researcher misma sesión entregó aclaración final sólo lectura; receipt docs5 aceptado
y liberado por padre. Se APRUEBA implementación siguiente bajo estas precisiones:

### API y referencia

Composition.resume(definition, reference, opts \\ []) sin input ni paso manual.
Referencia pública mapa plano exclusivamente version/id/record_id/revision/run_id/
attempt_id(opcional). version===1, revisión entera positiva, IDs válidos; attempt_id
tipo válido o nil, correlación NO permiso/fence. Comparar id/config y record_id/
revision/run_id con record; no actualizar revision silenciosamente. Forma inválida
invalid_composition_restore; identidad vieja/contradictoria continuation_conflict.
No checkpointtoken como referencia. Seam interno ExAgent.resume_composition_step
conserva terna id/record_id/revision y subsets existentes, no endurecimiento incidental.
Opts EXACTAMENTE run: continuation/root_options/step_options/observability/trace_context.
Config obligatoria y contradicciones rechazadas por lógica run_config, no Map.merge
permisivo. expires_at obligatorio nullable, lease positivo, policy/binding exactos;
límites actuales sólo restringen persistidos. IDs step_options conocidos incluidos
completed, pero sus opciones/callbacks no se aplican a hojas históricas. on_writer
una vez ganador tras claimACK, nunca completed. Sin inyecciónIDs/frames/Scope/history.

Completed: referencia+record+binding/policy+límite lectura válidos, projection actual
sin Scope/claim/writes/codecs/mapping/Model/estimadores/observabilitycallbacks nuevos.
Deadline/TTL pasados no impiden inspección si Store aún tiene record; config válida.
Output omitido→RunError checkpoint/proyecciónconfirmada, no success.
Active: sólo ready y frontera admitida; claimed aunleasevencido→composition_not_ready.
Uncertain/paused/approval/cancelled/expired no ejecutan. Ready fuera subset→unsupported.
Tiempo/admisión conocidas antescallbacks y claimCAS temporal definitivo. No resetbudget.

### Recuperación administrativa y resultados

NO autorecover. Host usa Continuation.get y Continuation.recover/3 explícitos con
record_id/revision/operationID/actor/authorize; sólo claimvencido admite recover y puede
producir ready/expired/uncertain. Host construye referencia nueva de record devuelto.
Resume no otorga autorización administrativa ni cambia Store por leasevencida sola.
Mismo result/RunError/project que run, sin nuevas fases. Open: opts/ref/preflight/
claim/import/owner. Prepare: codec/validate_resume/outputconfig/retención activa o
admisión sucesor. Mapping: callback sucesor. Execute: loop/losswriter. Checkpoint:
tokenreal pendiente incluso claim, outputomitido. Razones acotadas originales.
No proyectar record inválido/ajeno/bindingincompatible. Preclaim record válidoreference
es baseline; trasclaim sólo ACKs recibidos, sin rereadStore para fingir progreso.
ClaimACKincierto→baselinepreclaim+tokenexacto+partial, no intento inventado.

### Helper cerrado / orden / allowlist

ExecutionScope.restore_composition_tree(root, frame) interno estrecho (nombre ajustable)
una llamadaGenServer atómica sobre estado candidato; caller owner, tokenrootstructural
activo, runIDs coincidentes, sin operaciones/batches/retries previos. Host nodes sólo
root+activa preparada si existe; agregar exclusivamente prefijocompleted validado,
IDs exactos sincolisiones; active:false, NO structural:true, nohandles/guardians vivos
ni callbacks históricos/approve ejecutable. Importar mediante ScopeLedger.restore
exacto, sin sumar snapshots ni repricing. Fallo no instala árbolparcial. Duplicatedjoin
no reactiva completed; effect_node/active_node rechaza closed. Autoridad persistida
intacta, hostroot/activa current∩original; deadlineclosed sólo historia.
Orden: purepreflight→claimCAS→ACKfresco→Scope restringido/bindWriter/ownerúnico→
prepararactiva codec/join sinloop→importtree atómico→restorestateWriter→loop/sufijo.
Replay/conflicto/errorclaim no codecs/mapping/on_writer/IO. AdaptadorStore sí puede
ser invocado por preflight/CAS; no prometer ausencia absoluta callbacks del Store.
Cleanup único ante todos errores. Separar bindScope/owner de restore_step sin doblar
on_writer. Frame sólo seam causal necesario; sin nuevo formato ni ledger paralelo.
Allowlist runtime APROBADA: Composition, ExAgent, CompositionRestore, Writer,
ExecutionScope exclusivamente helper/soporte cerrado. Frame si impedimento concreto
reportado antes ampliar. NO ScopeLedger/Budget/Authority/Record/Transition/Store/OTel/MCP.
Tests nuevos sequence_resume/supportVM. Actualización causal específica autorizada:
composition_definition_test refute resume/2→assert ahora APIdefault aprobada; negativos
N>1 en sequence_writer_test hoy globales sólo para fronteras recién admitidas (mantener
negativas fuera subset). Otros oldtests requieren evidencia causal al padre agrupada.

### Ejecución en dos checkpoints, mismo owner / API / motor

1. Vertical utilizable prefijo+input desde inicio API/error/options/completed, helper,
lifecycle, VM efectoAuna vez, claimCAS/ACK/recover explícito, budgetfinito negativo,
TTL/deadline/cuota/prefixcallbacksnegativos. Terminalmultileaf sigue failclosed hasta2.
2. Texto terminal seguro SIN tool-history propia; typed-succeeded actual con cadena
Model/output admitida. Tools/retries sólo hojascompleted no bloquean. NO tool_boundary
activa accidental ni outputretry/batch/raw/approval. TerminalACKkills+±1matrix y
regresiones7/8/single9, FULL final identidadintegrada. No FULL por helper/checkpoint.
Mandato es completar ambos salvo bloqueo real/contexto; primercheckpoint probado
preservado si interrupción, no rollback ni entregar sólo infraestructura inútil.
Docs4design/changelog/roadmap/r6-implementation del owner al hito; padre status/memoria.
Nuevo baseline/report/manifest temprano en /tmp/opencode; no tocar sellos anteriores.
Sin paid/SQL/cloud/infra/globalconfig/install/commit/push/bump/publicación/consumidores.

## Entrega implementación / review pendiente

Owner ses_f15f35afcffefZ5e1rROp5cvLV TERMINADO/liberado. Padre leyó REPORT
/tmp/opencode/sequence-recovery-f15f35af/REPORT.md SHA
4962b65b440f0aeaf1e7188949a1b539a904acc6a86280bae013390bea858090 cotejado;
12/12sourcehashes y FULLfinal log/exit0 cotejados1706/28/933.0s.33tests nuevos,
runtime5/tests3/docs4; compile107WA/formato/diff0 owner. Sin aceptación todavía.
Owner separó autoridad lógica root de lease/budget al producir nuevas filas enrun;
antiguas filas con lease capturado como deadline NO se amplían, siguenlimitadas.
Fix temporal adicional conserva actualrootdeadline enclaimCAS y recheckpostACK
root/activa/lease/deadline/TTL antesonwriter/codec. FULL1701 es pretemporal histórico,
NO gate final. Reviewer debe auditar semántica cambio productor y efectos/checkpoints
para comprobar no pérdida de enforcement de lease/budget ni autoridad ampliada.
Matriz±1 primeras3admisiones limitada por baseline/reservaclaim, no necesariamente
payloadtoken; token8MiB CASrecordlimit no commit. Mantener esas calificaciones.
Intención review fresca acumulado12 y contratos anteriores, probespropios+focales,
sin editar fuentes/FULLrutina; ROOT/build exclusivo reviewer, padrestatus/memoria.

## Review bloqueante P1/P2 y corrección autorizada

Reviewer ses_f15ae7eb3ffejXlv2w6V3C6nyW TERMINADO/liberado. Padre leyó REPORT
/tmp/opencode/sequence-recovery-review-unique/REPORT.md SHA
55ffa3b3c17abd7eda209d0c8be66a12fa0d18f59297d68c82608027a3092ad9 cotejado.
410existingfocalpass;10probes propios7pass3fail reproducen2defectos, causal0/3 repite
los mismos fallos. Owner1706FULL histórico no invalida hallazgos.12/12+359/359 intactos.
P1: active input tras on_writer lento calcula now+reserved_ms nuevo mientras Writer
started_at ya comenzó enACK.600ms/hold601 permite efectoA fuera presupuesto. Debe
compartir deadline monotónico único desde ACK, carry por owner/preparación/loop y
recheck antescallback/IO. No confiar CAS lease como sustituto presupuestoelapsed.
P2: usage_limits:invalid / permission_floors:invalid pasan keyschecks, claim consume
600reservation, Authority.intersect luego raises sinRunError. Validar valores root
aplicables ANTES CAS; no refund/reset para ocultar consumo ni blanketrescue postclaim.
Worker fixes autorizado mismo allowlist5, tests permanentes sequence_resume, docs4;
probes independientes copiar nuevo directorio y sólo sustituir rutas documentadas,
originales/assertions/históricos intactos. Repro rojo→fixcausal→verde, FULL final tras
fixes. Auditar siblings delayedcodec/preflight/claimACK y opts sin ampliar a redesign.
No tocar Budget/Authority/ScopeLedger/Transition/Store/format sin bloqueo causal alpadre.
Nueva revisión independiente y parentprobes antes aceptación; recuperación BLOQUEADA.

## Handoff intermedio con build ocupado

ses_f159fe367ffeYG4Cyd6O3xpAfh notificó completed pero explícitamente NO liberó
ROOT/build: focal activo, ningún FULL. Padre leyó REPORT WIP en
/tmp/opencode/sequence-recovery-fix-f159fe36/REPORT.md;10probes originales verdes
owner y42resume casos preparados, no gate final ni identidad sellada.
Mismo owner continúa: esperar su gate sin polling/solape, reproducir y adelantar
validación estructural arity1 estimate_cost antesclaim (ExecutionScope.start_structural
ya rechaza structural_scope_requires_model_aware_estimator). Es mismo P2 causal:
reutilizar exact validator existente sin nuevas restricciones ni blanketrescue.
Luego focales/probes/compile/formato/diff/FULL final y liberación explícita. Padre
no ejecuta builds ni reasigna runtime mientras gate previo activo. No aceptación.

## Fixes finales recibidos, 2026-09-29

Owner ses_f159fe367ffeYG4Cyd6O3xpAfh TERMINADO y ahora sí ROOT/build/docs4 libres.
Padre lee REPORT /tmp/opencode/sequence-recovery-fix-f159fe36/REPORT.md SHA
84489d3b43f3eb1a572deeeb1e6e956386b601c04985234eb5002c678f4328bc cotejado;
deliverydelta10/10hashes y FULLlog/exit0 cotejados1716/28/948.9s. Runtime5/test1/docs4.
Owner10probes intactos verdes y3causales mismoscasos verdes;74focalfinal,compile107WA/
globalformat/diff0.446broadfocal es preúltimaextracción, no identidadfinal por sísolo.
Validación structural estimadorarity1 antesCAS reutiliza aceptaciónexistente, ordinary
scope conservaarity1; plazoACK único cachedWriter por owner/codec/preflight/loop.
Intención mismo reviewer independiente revalida delta10+probesrutasnuevas/siblings;
NOaceptación recuperación aún. Preservar failurehistory y no sumar reruns.

## Review fixes: P1 residual ACK intent tardío

Reviewer ses_f15ae7eb3ffejXlv2w6V3C6nyW TERMINADO/liberado, REPORT
/tmp/opencode/sequence-recovery-fix-review-f15ae7eb/REPORT.md SHA
3face376b61d9d5fac478e2cf1ee932648b20ddd25bb0b3ae135aab4a2cc9555 leído/cotejado.
OriginalP1/P2 corregidos:74focal+10originales pasan. Dos nuevosprobes causales rojos
budget/lease: request_model calcula timeout ANTES model_begin; ACK begin_effect
retenido hasta expirar vuelve:ok y Model.request entra con timeoutviejo. Postresponse
expiry demasiado tarde. Intención worker fix boundary postACK/preIO en ExAgent/Writer
allowlist, renovar timeout RESTANTE no plazo; preservar intentcommitted unresolved/
partial/uncertainty, no refund/cancel/outcome/replay inventado. Auditar tool/stream
análogos con evidencia, si módulosfueraallowlist causal pedir autorización específica.
No afirmar este hueco introducido por fixes. Sibling sampling10ms rojo no cuenta
defecto extra ni pase: originales intactos, prueba deterministaexpiry manda.
Worker fresco: reproducción en rutas nuevas; mínimofix+regresiones permanentes;
revisar conjunto fronteras una vez, no patchsintomático que deje dispatchanálogo.
FULL final tras identidadlista/reviewposterior. No aceptación recuperación.

## Recuperación tras sesión dañada intentfix

ses_f156f2e15ffeyvcuFkfInGGySp ERROR invalid_encrypted_content: NO reanudar.
Padre inspecciona /tmp/opencode/sequence-intent-fix-unique/REPORT.md (sólo baseline),
baseline-manifest: único archivo existente producto cambiado lib/exagent.ex; nuevo
test/exagent/sequence_intent_dispatch_test.exs observado en status, fuera inventario
baseline. green-causal.log14pass/11.5s y exit0 cotejados, no FULL/compilefinal/review.
ps sólo3BEAMajenos, ningún buildpropio activo. Preservar delta y nuevos tests; no
tomar gate parcial como entrega. Worker fresco capturará baseline ACTUAL+comparación
con baseline previo, leerá redlogs/commandrunner y verificará test nuevo/source.
Mismo mandato intentfix+audittoolstream+gatesfinales, no reiniciar/rollback/reusar
sesióndañada. Artefactos originales inmutables; report nuevo recuperable temprano.

## Intentfix recuperado entregado

ses_f15689208ffek6qoTSmtVUmGN1 TERMINADO/liberado. Padre lee REPORT
/tmp/opencode/sequence-intent-fix-recovery-unique/REPORT.md SHA
e959dc1133b9f430d47b660997e5d602681cdca3cd9613a20dc5e0d21c4d3c7d cotejado;
6/6sourcehashes y FULLlogexit0:1733/28/967.8s. Runtime1ExAgent+testnuevo+docs4.
Guard Scope postACK/observability/preModeldispatch y timeoutrestante mismo bound,
intentunresolved intacto. Owner17dispatch/113focal/10original/2causales pasan;
toolheldACK6variantes+3positivos sin bugtool reproducido, no toolruntimeedit.
Primer rerun22/24 falló harnesslegacyproducer ausente, copiacompleta nueva10verde;
no assertions modificadas ni históricos sobrescritos. Review final residualP1
pendiente, mismo reviewer independiente conoce contratos; no aceptación aún.

## Reviewer dañado: reemplazo fresco

ses_f15ae7eb3ffejXlv2w6V3C6nyW ERROR invalid_encrypted_content; NO reanudar.
Padre leyó /tmp/opencode/sequence-intent-final-review-f15ae7eb/REPORT.md parcial19líneas:
identidades/copias cotejadas, audit/probes/gates pendientes. No dictamen favorable.
Padre ps sólo3BEAMajenos,0builds propios. Reviewer fresco completará revisión residual
P1 y compatibilidad fixes desde artefactos, sin editarproducto ni originales sellados.
Nuevo directorio/report para pruebas, conservar parcialdañado. OwnerFULL1733 evidencia
vigente pero aceptación continúa bloqueada hasta review+probespadre.

## Aceptación recuperación acotada, 2026-09-29

Reviewer fresco ses_f154c1659ffet0cQp28plp7Y7B TERMINADO/liberado favorable:
/tmp/opencode/sequence-intent-review-fresh-f154c165/REPORT.md SHA
4e55a3427e2669aa6272e1ab745ed47ae39e58c0368df3b3ba6a5a7175718c4a leído/cotejado.
29(2causal+10prior+17dispatch)+113focal+3nuevosobs pasan,392/392fuentes intactas.
Padre6/6sourcehashes actuales cotejados y copió harness completo a NUEVO
/tmp/opencode/recovery-parent-3_d5tlzx/ con sustituciónrutaúnica roundtrip manifest;
runner inspeccionado. parent-final.log15pass/12.6s exit0: mismos2lateACK+10prior+
3obs, no15casos nuevos. Latebudget/lease requests=[] revision6intacta verificado.
OwnerFULL1733/28/967.8s identidadverificada separado de review/parent, históricos
fallos intactos. Se ACEPTA Composition.resume offline ready9 empty/between/input/
textterminal seguro/typedsucceeded según contrato; explicitrecover, oneclaimScope,
prefixaccounting y autoridad sinreplay. Legacy7/8/single9 subssets conservados.
No activebatch/outputretry multileaf/rawuncertain/C7compositions/delegación/router/
parallel/generalR6/SQL/live/producción. Finitoabandonado sigueagota; oldpersisted
leasedeadline no ampliado. Callbackyaempezado no preemptible/atomiccancel promise.
Intención receipt docs5 aceptación/limites/históricos; researcher siguienteC7composición
sólolectura delimita vertical viable sobre baseaceptada sin activar implementación.

Receipt docs5 aceptado padre: /tmp/opencode/receipt-recovery-unique/REPORT.md SHA
d05e1be25256953480497a643c2b100cf04e5b14fdc7fc3685abdf5bf83d64ba cotejado;
diff274líneas leído completo SHA15cd97a31a46d522106021981d6e554660572bf3f1428606f0886e28fc8504f2.
Padre sha256sumfinal5/5OK+gitdiffcheck0; sólo prosa, sin atribuir gates nuevos.
Históricos/limitaciones intactos, C7antiguostatus etiquetado histórico; docs5libres.
