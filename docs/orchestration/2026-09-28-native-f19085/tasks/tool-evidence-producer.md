# Frame8: productor de evidencia accounting/control (mandato aprobado)

Researcher fresco ses_f1812b471ffelGxW9UIiIn2TdQ terminado sólo lectura. Padre
contrastó Frame77–126, Scope contribute543–559/ScopeLedger223–234 y max_retries(nil)0.
Base counters productor/batch aceptados; contexto causal retry-control-contract.md.
Objetivo IMPLEMENTAR productor/validator, NO abrir restore tools/prefijos/batch ni
reconcile/pausa/delegación/A→B. No otro motor ni nuevas opciones públicas.

## Decisión explícita de omisión (padre)

Para Frame8, Usage inválido/omitido/noportable se rechaza ANTES de aplicar operación
external. Persistir observación negativa y outcome raw conocido juntos antes ACK;
ACK de error impide after-hook y posterior trabajo. No perder respuestas de efectos
ya admitidos; cerrar/quiescencia del batch y conservar accounting aceptado de siblings.
Scope2 contiene sólo contribuciones aceptadas, sin borrar markers ni inventar nil/
unknown/cero. Observación negativa declara total incompleto: progreso/RunError y
datos persistidos pertinentes exponen usage_status partial aun tras refresh_scope.
No presentar subtotal como coste/uso completo; registro negativo diagnóstico y
NO ejecutable. Reservar evidencia negativa/error/cleanup antes de IO. No Scope3 ni
relajación de decode_usage. Si este contrato es imposible con forma actual, bloquear
con evidencia antes de extender formatos/proyecciones silenciosamente.

## Forma y compatibilidad

Nuevas raíces estructurales escriben Frame8, campos exactos Frame7 + tool_batches.
Record2/Outcome1/Message/RequestData1/Scope2 mantienen esquemas/semántica previa.
Frame8 sin tools conserva fronteras aceptadas input0/text1/output-chain/completed;
Frame8 CON tools continúa rechazado por CompositionRestore aunque evidencia sea válida.
Legacy Frame7 existente mantiene7 durante su lifetime (incluidos writes tras resume),
sin fabricar observaciones ni relabel. Reads4–7 y aceptación Frame7 previa intactos;
writer legacy sólo para lifetimes existentes, retiro tras expiración/retención de
éstos, no modo público permanente. Tests/fixtures auténticos preservados; tests
generados por writer nuevo pueden exigir8, sin relabelar probes históricos.

tool_batches: mapa digest([run_id,request_id]) → batch con claves exactas:
run_id, request_id, limits, observations, resolution.
limits: nombre de tool→{schema_hash:hash64|null,max_retries:entero>=0}, exactamente
nombres de calls de response, desde tools efectivas del batch antes tareas; desconocida
null/0. Orden/IDs/calls provienen de response confirmada, no copia redundante.
observations: effect_id real journal → observación. resolution:null|resolución.
Estructuras subordinadas pertenecen al contrato8, sin versiones redundantes.

Identidad journal base tool-digest([run,request,"tool",call]); intento usa active_id
real, NO execution.attempt_id del claimant. Operación Scope se deriva primer intento
[tool,request,call] o reautorizado [tool,request,call,effect_id], no por toolname.
Planes reautorizados aún fuera de productor estructural/restores, no inventar origen
uncertain como retorno. No perder evidencias retiradas si formato soporta identidad.

## Observación y accounting

Claves exactas: origin (tool_return|pre_dispatch), presence(nil|usage|omitted), usage,
application. usage null o UsageMap cualificado portable según variante.
application exacta: {status:none}; {status:contributed,complete:boolean,ancestors:map};
o {status:rejected,error:PortableError}. nil/null→none; usage sin omission→contributed;
omitted→rejected con marker/cause explícito y Usage retenido portable o null.
pre_dispatch sólo nil/none + journal pre_dispatch; observación AUSENTE significa no
recibida, nunca nil. Unknown es Usage observado con sus availability, distinto de nil.
Marker de omisión debe conservarse en usage o error.omitted cuando usage sea null.

Capturar presencia/input ANTES de Retention.tool_outcome que puede sustituir invalid;
transportar interno task→owner, sin incluirlo en Message serializado. Helper interno
Scope construye op+recibo desde input observado/identidad, valida ambos ANTES mutar,
aplica una vez y devuelve observación; NO export ledger→autoatestación.
Proyecciones ancestors producidas con misma normalización/pricing external actual:
coste unknown/no estimator padre, complete predicado enteros actual (no availability).
Usage y terminal_usage op iguales al uso retenido observado; ancestors con proyección
aplicada, no igualdad ingenua con coste aportado. No repricing al restaurar/validar.
Mismoid+misma observación idempotente incluso nil/rejected; distinto contenido conflicto
tool_accounting_conflict sin reemplazar op. Reutilizar recibo RAM interno, no nuevo motor.
Raw CAS outcome+observación+Scope juntos; sólo luego ACK/after-hook. Final inmutable,
sin contribute otra vez. API legacy Scope.contribute no cambia indiscriminadamente.

## Resolución y reductor

resolution exacta: calls (lista ordenada de {effect_id,result_hash,retry:boolean,
error:PortableError|null}) y settle_error:PortableError|null. Orden de calls Model;
hash part final realmente retenido. No duplicar parts/mapas before-after/decision/fatal:
reductor puro compartido deriva estado y decisión, no segundo loop.
Inicial retries{}; aplicar resoluciones históricas en orden request/calls. retry true
incrementa y exceder límite capturado produce exhaustion; si no excede consume error
retry. false+succeeded borra contador incluso si fatal. Primer fatal en orden calls
persistente aunque success posterior borre contador; error_global=fatal||settle_error.
Tareas mismo batch ven contador inicial; no serializar IO ni cambiar order al finish.
Capturar controles después hooks/normalización exits y retención; settle confirma
parts finales; preservar precedencia error||checkpoint_error; tool_resolution CAS
DESPUÉS settle y ANTES fail/pause/drive. Sin finals completos no resolución completa.

PortableError exacto code,message,details,omitted. Códigos tool_hook_failed,
tool_execution_failed,invalid_tool_result,retention_limit_exceeded,checkpoint_failed,
runtime_error; message UTF8<=512bytes, objeto JSON<=4096bytes. Normalización segura
existente (Retention/ErrorProjection) y mensajes fijos para términos noportables;
no inspect de configuración/model/auth ni serializar callbacks/excepciones/módulos.
details JSON|null y marker para omisión. Error BEAM vivo conserva contrato; futuro
restore error portable no reconstruye excepción. Exhaustion derivado, no duplicación.

## Invariantes y transiciones

Validación común Record→Frame: batch↔admisión exacta; outcome tool confirmado exige
observación; ésta sólo se añade junto raw/resolve_call. Contributed exige op exacta
identity/usage/terminal/complete/ancestors, ausencia/rechazo no op; op exige observación.
Borrar obs+op dejando outcome rechaza. Resolución exige finals/orden/hashes/observaciones;
request histórica consumida exige control continue. Counters derivan resoluciones;
durante settle batch actual conservan previous, CAS resolución los actualiza.
Evidence append-only/inmutable también en otros comandos, no sólo tool_resolution.
OutputResolution/stubs no son function effects ni accounting/batches ficticios.
Schema histórico Frame8 se liga a limits de batch propio, no selected_tools actual
de otra request; legacy conserva contrato. Límites capturados no se deducen del hash.

tool_resolution payload owner/attempt/fence/snapshot/progress existentes: sólo añade
UNA resolución y actualiza counters derivados necesarios, no scope/outcomes/history/
snapshot/model ajenos. Validar owner/fence/revision/cmd idempotencia existentes.

## Capacidad y límites

Antes tareas (incluido íntegro predispatch), reservar batch/evidencia mínima negativa/
control por call/settle_error/receipts/cleanup. Proyecciones reserve_outcome incluyen
todos efectos concurrentes, copias ancestor/hoja, raw/final omitidos y control. Medir
con codec real bytes/escapes/identidades/counters, no multiplicador optimista.
Record.receipt_reserve cuenta resolución pendiente por batch aun sin tool intent;
la consume al commit sin quitar cleanup de raw/finals. Token/record+cleanup límites
exacto/-1/+1; no eviction de evidencia/receipts para hacerlo caber.

## Alcance archivos y entrega

Owner producto/build ROOT/docs4 exclusivo. Seams ExAgent, ExecutionScope helper,
Writer, Frame, Transition, Record y helper puro pequeño ToolEvidence si aporta.
ScopeLedger cambios sólo helpers/contraste no semántica formato2. Capability aceptado
intacto salvo necesidad causal, no refactor general. Padre memoria/status.
Documentar contrato/impacto/migración en design/changelog ANTES de estabilizar; roadmap
unidad iniciada y gates final; r6 matriz. No bump/publicación/commits/consumidores.

Baseline completo/hash/delta/informe TEMPRANO /tmp/opencode nuevo. Originals anteriores
inmutables (probes generan JSON fijo, copiar/parametrizar para repetir). Rojo causal
de nuevo productor antes fix y negativos CAS/decode. No fingir que rojos legacy usage/
retry se cierran reinterpretando datos incompletos; nuevas fixtures auténticas Frame8.
Positivos nil/unknown/zero/partial tokens y availability/ancestors/costs; IDs reutilizados;
corrupt obs/op/quality/source/complete/terminal/ancestors/hash/control/counter/limit;
retry-success/success-retry/exhaustion-success/hookfatal/final/timeout/orden invertido;
atomicidad/CAS/revision/ACK por todas fronteras raw/final/control/nextintent; kill;
omisión/noportable/oversized/marcador/partial visible/no continuación/siblings retenidos;
capacidad batch/raw/final/control/cleanup±1/receipts1024/concurrencia; legacy auténtico/
accepted subset nuevo8, restore tools bloqueado. No paid/SQL/Orca/global/infra.
Focal por hitos, compileforceWA/formato/diff/FULLofflineWA48seed37556 timeout>=600000
con prefijo environment/build absoluto. No --no-compile/serializar/relajar guards/timeouts.
Owner final no termina con FULL activo: resultado/exit/identidad y ROOT/procesos liberados;
review fresca obligatoria. Si contrato no implementable, evidencia y propuesta al padre
ANTES de inventar datos/relajar semántica o expandir scope silenciosamente.

Owner general `ses_f180bea31ffeoAtIjHAo2VyiO2` background ACTIVO, único producto/
build ROOT/docs4. Padre memoria/status. Entrega y review fresca pendientes.

## Aclaración acotada de alcance (tras entrega bloqueada)

Owner terminó sin implementar Frame8, ROOT libre. REPORT leído/cotejado
`/tmp/opencode/tool-evidence-f180bea3/REPORT.md`
SHAcd2dad4c5bf2c5ce6792f80e0b2e4d4fa93b4620940c982c757dda43bd568944.
source6/6 OK padre; delta sólo docs4, runtime/tests intactos. Probe aislado mínimo
2/3 (1rojo versión), NO Record8 auténtico ni aceptación. Sólo BEAM3ajenos.

Padre contrastó CompositionRestore.preflight15–16/boundary68: excluye !=7. Se
AUTORIZA añadir `lib/exagent/continuation/composition_restore.ex` al ownership sólo
para discriminación Frame7/8 (en vez de sólo7), después Record.validate y conservando
TODOS los guards ejecutables, perfil/batches/effects/plans/autoridad. Es seam necesario
para subset Frame8 sin tools ya aprobado, no ampliación funcional de restore.
Completed data-only previamente aceptado no ejecuta tools. Nuevos records8 auténticos
deben probar subset/negativos; probe mínimo no sustituye esos gates.
Intención continuar MISMO owner desde baseline/artefactos sin reiniciar trabajo ni
repetir diagnóstico. Completar mandato original y documentación que quedó bloqueada.
Continuado `ses_f180bea31ffeoAtIjHAo2VyiO2` background ACTIVO, ownership exclusivo.

## Entrega final owner y despacho review

Owner TERMINADO, ROOT/producto/build/docs4 liberados; padre confirma sólo BEAM
ajenos3339/2963360/4019033. REPORT leído SHA
6413ccab342ed0446f787604a447bc9111929a11ed3760c408cea38ac9fc2d25 cotejado.
source.sha25619/19 verificados desde ROOT; primer comando desde artifacts falló
por rutas relativas inexistentes, repetición cwd correcto OK (no corrupción).
Delta14modificados+5nuevos, ninguno perdido. FULL final1409pases28excluidos/508.2s
exit0 verificado en log/exit; compile102/formato/focal88/diff exit0 owner. Gates
anteriores no sustituyen final tras refinamiento reservas. No aceptación todavía.
Intención reviewer fresco exclusivo build ROOT sin corregir, con probes independientes
reservas/invariantes/accounting/control/legacy y guards, NO FULL repetido por rutina.
Padre sólo memoria/status; pospone integración R7 observabilidad (privada aceptada)
para preservar identidad exacta Frame8 durante review. MCP review en copia independiente.

## Aceptación offline acotada

Review ses_f1798e084ffeSdf4vdZdgPyvjA TERMINADO favorable sin P1/P2,95casos distintos
(55producer+33contrato+7probes). Padre leyó REPORT en
/tmp/opencode/frame8-review-20260928-fresh/, SHA
49eb910f4fe1e749f7c34772b27ca248acd17d4ef3ac86fc7355c6cfa41c7ee0 cotejado;
source19/19 cotejado de nuevo. Padre reejecutó7probes con assertions intactas,
sólo destinos JSON nuevos bajo parent/, exit0/2.5s WA48seed37556. Logs/command/exit
en parent/probes.*. Productor/validator Frame8 ACEPTADO offline; FULL1409/28 sigue
evidencia owner. Rojos legacy usage/retry no reinterpretados ni restore tools abierto.
ROOT/build libre. Siguiente integración observabilidad privada aceptada+docs de ambas
unidades, sin reabrir implementación Frame8; posterior verificación ROOT combinada.
