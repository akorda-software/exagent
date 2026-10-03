# Output retry confirmado: diseño acotado previo

Base output succeeded aceptada: informe review y recepción en CURRENT.
Objetivo siguiente: consumir primera atestación retry confirmada sin repetir la
validación que la produjo, preservar returns/contador/ledger y admitir la siguiente
request por el loop existente. No equivale a cerrar con datos: un request nuevo
necesita configuración host actual, autoridad y admisión verificadas.

Intención: análisis de fuentes sólo lectura por general, sin editar ni shell/build.
Debe proponer frontera exacta, seams, binding/output_config/descriptor, contador y
ACKs, presupuesto/permisos y matriz causal; indicar ampliaciones mínimas inevitables.
Sin formatos/tokens/motor nuevos por comodidad, sin batches/tools previas/A→B ni
restore indiscriminado. No repetir aceptación input0/text/success. Padre decide
contrato antes de entregar ownership de implementación.

Researcher mediante perfil general: `ses_f18fa5e10ffez2nmV0zA7clKvo`, background.
Terminado sólo lectura, sin builds ni edits. Padre contrastó retry_or_fail/4,
prepare_run/1 y OutputResolution.position?/4 y acepta la dirección siguiente.

## Decisión aprobada para implementar

1. Sólo Frame7 ready/root+hoja running/response1, un Model confirmado portable y
   una operación, cero tools/batches/retry_batches/approvals/plans, Request+Response
   sin returns previos, output_retries_used0 y una atestación retry exacta. Record
   valida antes de clasificar. Perfil host typed/tool y refs completas preclaim.
2. A diferencia de success data-only, retry necesita configuración ejecutable HOST
   para requests futuras. Reflexión/changeset vacío permitidos DESPUÉS de claim,
   sólo ganador; NO validar args históricos otra vez. Preparar configuración una
   vez por intento, cache efímero interno, comparar descriptor exacto normalizado
   y fingerprint y conservar Model.validate_resume/binding antes/después codec.
   JSON nunca selecciona módulo. No prometer detectar cambios semánticos que
   mantienen schema/refs, ni exactly-once de callbacks puros entre intentos.
3. Consumir partes exactas atestadas por retry_or_fail/append_returns y drive;
   no handle_response histórico ni nueva output_resolution. Agotamiento conserva
   envoltura output_retries_exhausted con Retry.content portable como diagnóstico,
   no reconstrucción de errors Ecto que no están persistidos.
4. Protección fail contra stubs contradictorios mientras retry está no consumido;
   retirarla tras append exitoso, antes de futuras respuestas. Selección privada,
   no opción caller y no arrastre a response2. Success aceptado permanece intacto.
5. Consumo/contador se persisten juntos en begin_effect de request NUEVA por Writer
   existente. Nada de checkpoint intermedio: position? exige request_id distinto
   cuando partes retry están en historia. Otro ID y sin plan/idempotency key viejo.
6. Scope restaurado una vez; actual∩original/floors intactos. No repricing histórico;
   estimadores actuales sí valoran operaciones NUEVAS. Límite requests1 usado no
   admite request2; output retry0/1, maxsteps1/2, presupuesto/tiempo/retención reales.
7. ACK exacto sólo datos. Antes begin_effect no hay Model; tras intent durable sin
   outcome, recuperación uncertain, nunca replay automático. Crash preintent puede
   recuperar frontera original administrativamente sin refund de budget abandonado.
8. Continuación viva normal permitida; restore de request2/response2/retry2/success2
   pendiente/batches/planes/uncertain permanece bloqueado preclaim. Completed sigue
   data-only; step_output token existente puede confirmar sin loop. Esta unidad NO
   garantiza cerrar desde bytes tras perder owner en la segunda respuesta.

## Implementación y verificación asignables

Runtime preferente ExAgent/CompositionRestore y helper OutputResolution si necesario;
no Frame/Writer/Scope/Authority/Record salvo necesidad causal documentada al padre.
Nuevo test composition_output_retry_restore_test y support portable/VM según necesidad.
Actualizar negativos success/text que contradigan frontera nueva, conservando nuevos
rechazos auténticos fuera de alcance. No editar probes externos ni fixtures legacy.
Docs contrato diseño/changelog/roadmap/r6-implementation del owner; status sólo padre.

Matriz: retry real→respuesta2 válida; siblings exactos sin efectos; traps distintos
changeset vacío/args1/args2; schema cambiado postclaim, refs cambiadas preclaim;
CAS dos ganadores imposibles y VM nueva JSON; codec/binding/validate_resume y hooks;
inyección caller/no arrastre; retry/maxsteps/request límites original y actual;
precios raíz/hoja históricos versus nuevos, contadores; ACK before/after claim,
resolution, begin_effect2, outcome2, step_output; crash preintent/uncertain;
restore posterior bloqueado; historia exacto/-1, token/checkpoint/receipts y JSON+
cleanup exacto/+1 calculados sobre proyecciones reales (no copiar1019 de success);
excepciones/reflexión/hooks/deadline/ACK con cleanup observado.

Guardar baseline tar/hashes/delta e informe temprano bajo /tmp/opencode nuevo.
Rojo causal antes del cambio, focal por iteración, compile/formato/FULL WA48
seed37556 offline con prefijo environment y MIX_BUILD_PATH absoluto. Sin paid/SQL,
serialización, timeouts relajados, config global, commits ni delegación. Entrega
recuperable y review FRESCA posterior obligatoria antes de aceptar.

Owner implementador general `ses_f18f527adffe74IppkRIHBgR7N` terminado, ROOT libre.
REPORT leído `/tmp/opencode/output-retry-20260928-f18f527a/REPORT.md`, SHA6270e9da34cd9ecededa9a8525c370882ad4c6ecdc1fb3a9f0a29560f7ffee08.
Padre coteja manifiesto11/11, delta SHA79e5de86, FULL1211/28excluidos/363.8s exit0.
Owner matriz58/0/focal297/0(antes2tests finales)/compile101/formato0. Sin edición
Frame/Writer/OutputResolution/Scope/Authority/Record. Review fresca pendiente.
Intención general revisor: sólo lectura producto, build ROOT exclusivo, probes e
informe en /tmp/opencode. Examinar especialmente cache/reflexión después claim,
limpieza selección/fail, consumo durable, admisión nueva y guards posteriores.
Revisor general fresco `ses_f18c726f8ffeuvM1XyJy8AIvWZ` terminado, aceptación acotada,
167focales+5probes exit0. Informe `/tmp/opencode/output-retry-review-f18c726f/REPORT.md`
SHA97f98a0148ff5956d7d59699975c9d5e27a778888428057b7a3444b40e087cd7.
Padre leyó informe/deltas runtime, cotejó11/11hashes y ejecutó5probes intactos WA48
seed37556 exit0,5.9s (parent-probes en mismo directorio). ROOT liberado/BEAM3ajenos.
Unidad ACEPTADA offline; docs diseño/changelog/roadmap/status/r6-implementation
recibidas posteriormente al manifiesto. No FULL repetido ni cierre R6/SQL/live.
