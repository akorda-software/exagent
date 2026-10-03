# Paso→hoja: entrega NO aceptada

Owner `ses_f1a965a98ffe5XQfyn4I9v2lin`: /tmp/opencode/exagent-r6-step-f1a965/
REPORT.md, base/freeze/delta.patch562b23ae. Padre hashes11/11. Frame5/step real,
input antes Model IO, output después; restore sólo inspección, no ejecución.
Owner107focal/compile95/serial994pases28excluidos; suite48dos veces993/994 MCP140.

Review `ses_f1a5196d4ffeREE6ykHAt2c46S`:107focal,4probes fallan y tool real1verde.
Probe /tmp/opencode/exagent-review-f1a519/probes_test.exs SHA
562c3846a51bd2b32f68c93497f064dc9c1545450db4275a8baf9fdb4d616fd5 cotejado.

## P1

Frame.step_transition/structural_evidence/step_model_evidence comprueban existencia
de efectos pero no ligan posición hoja a evidencia de request. Step_input seguido
node_checkpoint run_step/snapshot.revision1 y step_output finish/result inventado
aceptan completed con effects{} y0Model IO. Writer.step_status lo devuelve éxito.
Otros probes: cambiar model_request_id permite eludir hash model_data; run_step y
revision0 aceptan completed con request contabilizada. Afecta runtime implementado.

## P2

run_composition_step obtiene/reserva step_ticket antes retention/model preflight.
Rechazo max_history_bytes:-1 deja ticket retenido: segunda llamada válida obtiene
composition_step_unavailable pese a0IO/0pending. Liberación debe ligarse al ticket,
no borrar otro intento ni liberar input confirmado o checkpoint dirty.

## Acción

Nueva expansión detenida. Owner fresco corrige con regresiones reales Store/CAS y
probes originales intactos, revalida focal+suite habitual48 y review independiente.
Padre aplicó propuesta MCP test-only tras cesión reviewer (tasks/mcp-timeout.md),
sin tocar runtime MCP ni subir50ms. Rojo concurrente no resuelto hasta nueva suite.

## Recuperación y revalidación en curso — 2026-09-28

Worker `ses_f1a4bc744ffeQ8U3i5GXlzzAaS` falló por contenido cifrado del proveedor
tras dejar cambios parciales. Padre conservó y probó esos cambios, sin reiniciar
desde el baseline: Frame liga posición/identidad/hash a journal/ledger/historia;
Writer liga ticket a owner/monitor; ExAgent libera la reserva exacta en try/after.
Informe de recuperación y hashes en `/tmp/opencode/exagent-blockers-f1a4bc/`.

Padre:56 focales, incluidos probes originales intactos y tool positivo, exit0;
compile forzado95/formato exit0; suite habitual max_cases48, seed37556,
warnings-as-errors:1001/0/28 en184.8s, exit0. Esto sustituye el bloqueo del gate
concurrente, no borra los rojos originales ni acepta por sí solo P1/P2.

Revisor original `ses_f1a5196d4ffeREE6ykHAt2c46S` continuado en background tras
compactación del mismo padre, con propiedad exclusiva de builds ROOT, sin edits.
Debe revalidar probes intactos, ciclo del ticket y evidencia de Frame antes de
aceptar el paso o ampliar R6. Dictamen pendiente.

## Dictamen independiente residual

Revisor terminó: originales corregidos,119focales verdes; nuevos edges2rojos y
edges+history+MCP31verdes/3rojos. No aceptar. Artefactos intactos en
`/tmp/opencode/exagent-rereview-f1a519/`; padre leyó ambos probes y codepaths,
contrastó SHA edges bd5f57cd / history f16c7cdb. Cero procesos propios del reviewer.

- P1 residual: tras ACK perdido de outcome Model que pide tool, step_output acepta
  ToolReturn inventado sin efecto tool y devuelve completed. Mutar contenido de
  ToolReturn confirmado también pasa Record.decode. open_calls sólo empareja;
  falta vínculo de evidencia de resultados de tools con journal.
- P2 residual: join_for añade hoja antes de Frame.capture; codec que falla una vez
  deja nodo huérfano aunque ticket se libera. Siguiente attach falla
  invalid_step_transition. No borrar nodos con IO/pending/input confirmado.

Intención siguiente: worker fresco dueño exclusivo producto/build ROOT para ambas
correcciones relacionadas, regresiones permanentes y suite habitual. Sin expansión
R6; padre único escritor de docs/orchestration. Revalidación independiente posterior.
Despachado worker `ses_f1a3818c8ffe07VdmX6maQDqnH` en background, con ambos probes
intactos como oráculo, contrato/evidencia documental y suite habitual como entrega.

## Entrega residual pendiente de revisión

Worker terminó sin procesos propios: `/tmp/opencode/exagent-residual-f1a381/REPORT.md`.
Padre leyó informe y validó SHA256SUMS9/9 y PROBES-SHA256SUMS4/4.
Frame liga ToolReturn/outcomes al journal, también decode y phase final histórica;
reserva sintética conserva coherencia sin confirmar journal real. Writer/Scope
retiran sólo adhesión vacía pre-write validada, no efectos/pending/input confirmado.
Nueve regresiones; rojo original3/3 antes edits;45probes finales verdes;
compile95/formato0, suite1010/0/28 WA max_cases48 seed37556,187.6s, exit0.
272focales son anteriores al guard phase-final; no atribuirlos a fuentes finales.
Intención: revisor original revalida variantes intactas, cleanup y fronteras
tool/retención/reserva sobre la entrega; propiedad exclusiva de builds, sin edits.
Continuado en background `ses_f1a5196d4ffeREE6ykHAt2c46S`; dictamen pendiente.

## Regresiones nuevas y cambio de estrategia

Revisor finalizó118focales verdes, originales corregidos, pero matriz4/6:
P1 segunda tool concurrente rechaza current sintético porque reserve_outcome
confirma otros tools sin ligar su evidencia al progress CURRENT antes de
Transition.apply. P2 output_type/final_result legítimo no despacha tool y ahora
exige efecto journal inexistente. Ambos regresiones de la corrección residual.
Informe `/tmp/opencode/exagent-finalreview-f1a519/REPORT.md` leído por padre,
SHAb84d0348de9d71b7beac7c488c6d6275380de84a91ec466cbf1e25c3277ef046 cotejado.
Cero procesos propios reviewer; producto no aceptado pese suite1010verde.

Antes de otro fix, encargar researcher fresco sólo lectura: revisar conjuntamente
clases de ToolReturn/outputs, fronteras current/payload/reservas y arquitectura
del invariante. Entregar plan causal/matriz finita sin editar ni ejecutar shell.
No expansión R6, no retirar guards ni excepción insegura basada sólo en nombre.
Researcher `ses_f1a1fd00affeUOX23OD7fFX7VM` despachado background, plan pendiente.
