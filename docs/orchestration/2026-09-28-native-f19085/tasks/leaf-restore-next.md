# Siguiente unidad de restore de una hoja

Base aceptada: input0/completed, response1 textual, output success y output retry1.
Resta convertir esa base en restore útil sin micro-unidades por cada número de
respuesta y sin habilitar indiscriminadamente batches/efectos inciertos/delegación.

Intención: general sólo lectura, sin shell/build/edits ni delegación. Inspeccionar
seams actuales y proponer unidad coherente mínima siguiente y orden hacia A→B.
Comparar consumo confirmado tras N respuestas/retries con batch tool confirmado,
raw/in-flight/uncertain/reconcile y ramas pausadas. Reutilizar evidencias Frame,
Writer y loop existentes; no otro motor/formato ni relajar guards por comodidad.

Entregar tabla frontera→evidencia/estado ejecutable→seam→gates, propuesta concreta
con límites generales ya existentes, impactos observables/migración y alternativas.
Separar necesidades causales de especulación y análisis de implementación; padre
decide qué habilitar antes de despachar owner. No repetir auditoría R0/Jido/ReqLLM.

General researcher `ses_f18bbb945ffe8wNXFyumd6YVWm` terminado sólo lectura.
Padre contrastó CompositionRestore106–147, Frame455–495 y OutputResolution106–123.

## Unidad aprobada: cadena Model confirmada con atestación actual

Generalizar output_boundary a N≥1 respuestas Model confirmadas sin dispatch previo,
seleccionando atestación por leaf.model_request_id. No nuevas cotas N: límites
existentes J/JSON/efectos/receipts/retries/maxsteps/usage acotan la cadena.
Record.validate conserva validación única de posición/hash/historia/modelo/ledger;
clasificador restringe ejecutabilidad, no duplica validator ni infiere autoridad.

Frontera: Frame7 ready/root running/una hoja running response; todos los efectos
Model confirmed/succeeded/state_available; operaciones Model ligadas por evidencia;
cero efectos tool/batches/retry_batches/outcomes/tool_retries/approvals/plans.
Historia completa ejecutable y última Response ligada al request actual; entrada
actual success/retry con descriptor válido y finish nil/stop/end_turn/tool_calls.
Perfil host typed/tool y binding completo antes claim. Omisión actual error preclaim.

Permitir retries atestados anteriores, sus stubs siblings no ejecutados y retries
sin call históricos. No exigir una atestación por respuesta ni elegir última del
mapa. Call ID puede repetirse en requests distintos. No comparar descriptores
históricos con host actual: cada uno ligado a su RequestData. Success histórico
seguido de ejecución sigue inválido según posición existente.

Reusar selecciones/consumidores ExAgent aceptados: success data-only sin Ecto ni
Model; retry configuración HOST postclaim una vez, descriptor ACTUAL exacto y
fingerprint, no args históricos, retry_or_fail→drive y consumo+contador con intent
nuevo. Contador restaurado incluye Retry sin call; no inferirlo de N/entries ni
reiniciarlo. Preservar precedencias agotamiento→maxsteps→admisión y protección fail.
Host Model binding/validate_resume/codecs, original∩actual/floors, ledger sin sumar
snapshots ni repricing. Nuevos efectos sí se admiten/estiman. Callback reconstrucción
puro puede repetirse entre intentos, no promesa exactly-once ni detección semántica
de schema/código que conserva refs.

ACK sólo Store con token existente; claim replay no ejecuta. Crash preintent vuelve
a atestación tras recovery explícito sin refund de budget; intent sin outcome es
uncertain sin replay. Outcome sin atestación actual continúa bloqueado. Atestación
posterior confirmada AHORA sí puede restaurarse; completed y step_output sólo datos.

EXCLUYE: textoN sin atestaciones (evidence? no comprueba contador con entries vacío,
no defecto ejecutable demostrado hoy); batch anterior aun finalizado, batch activo,
raw/parcial/inflight/uncertain/reconcile/approval/delegación/A→B. Mantener text1/input0.
Ampliación aditiva interna Frame7 sin migración/formato/token/motor nuevo.

## Cambios y matriz

Runtime previsto sólo CompositionRestore; ExAgent/helper únicamente si necesidad
causal. No Writer/Frame/OutputResolution/Scope/Authority/Record por comodidad.
Rojo causal auténtico disponible en output_retry_restore_test segunda atestación
rechazada; nuevas expectativas positivas sólo cuando hay atestación confirmada.
No cambiar negativos incertidumbre/ausencia de atestación para hacer verde.

Matriz permanente: success/retry tras varios retries; cadena mixta retry sin call;
múltiples interrupciones/restores; callID repetido/request distinto, siblings y
selección actual; traps args históricos y success sin reflexión/retry una vez;
contador/precedencias original/current debajo/igual/encima; success sin request nuevo;
mutación/borrado/duplicado/reorden de atestaciones/historia/contador/ledger/model en
decode y CAS; VM nueva JSON real; dos resumers barrera; ACK before/after claim/intent/
outcome/resolution/step_output; kill preintent/duranteIO; autoridad root/leaf/floors;
precios/calidad históricos vs nuevos; retención history/payload/J/token/receipts/
JSON+cleanup exacto±1 real, ambas omisiones; exclusiones AUTÉNTICAS batches raw/final,
running/plans/state_available false/falta atestación/native/legacy sin autoridad;
regresión input0/text1/success1/retry1/completed/evidencia/Scope/retención/legacy.

Owner guarda baseline/delta/hashes/informe temprano /tmp/opencode nuevo; rojo antes
runtime, matriz/focal/compile/formato/FULL WA48seed37556 offline prefijo environment
y MIX_BUILD_PATH absoluto, timeout>=600000. Sin paid/SQL/serializar/relajar guards/
timeouts/global/commits/consumidores ni delegación. Review fresca posterior obligatoria.
Docs contrato design/changelog/roadmap/r6-implementation del owner, status/memoria padre.

Owner general `ses_f18b65f77ffemaP845r5lDWS4X` terminado, producto/build ROOT libre.
REPORT `/tmp/opencode/output-chain-20260928-f18b65/REPORT.md` leído por padre,
SHAbde38203eafe548241f7883837938078bcbb421c7d9005cec05d5cd49a421f88;
delta15820043/final.sha25617/17 cotejados. Runtime sólo CompositionRestore;
owner matriz134/focal578/FULL1287pases28excluidos468.9s exit0, compile101/formato0.
Intención review general fresca sin edición producto, ROOT build exclusivo; no
aceptación ni FULL redundante. Probes e informe externos /tmp/opencode.
Revisor general fresco `ses_f186a9983ffeqUTT3MmKG5Uvnz` terminado favorable:
208focales+7probes exit0; informe `/tmp/opencode/output-chain-review-f186a998/REPORT.md`
SHA81fb2bb19acabcde880cbb6912ca4d9dcb45440ff7913bc005e5d500db7981ed.
Padre leyó informe/delta runtime, cotejó17/17 y reejecutó7probes intactos WA48seed37556
8.6s exit0. Cadena ACEPTADA offline; docs5 consolidadas después del manifiesto.
ROOT/build libre. No FULL repetido ni cierre general R6/SQL/live.

## Dependencias siguientes (propuestas, NO permiso para ampliar owner)

Prefijos/batches completamente finalizados; después recuperación incompleta C7
(raw≠final, hooks no son replay gratis); secuencia A→B/delegación requiere contrato
estructural: Record2 no admite pause/reconcile/decide, Writer rechaza attach delegado
y finish_child termina raíz, Frame aún un paso/un hijo. No quitar guards globales.
