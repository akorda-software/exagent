# Corrección contractual acotada — paso único

Researcher `ses_f1a1fd00affeUOX23OD7fFX7VM` terminó sólo lectura, sin pruebas.
Padre acepta dirección interna bajo mandato existente, NO aceptación runtime.
Mantener loop/Writer/CAS/journal/Scope; no nuevo motor ni A→B/resume.

## Causas y decisión

1. reserve_outcome confirma hermanos en current sintético sin sus outcomes;
   Transition.apply valida current antes del payload. Rechazo correcto.
2. Frame confunde todo ToolReturn con dispatch. Output válido genera ok/stubs,
   output inválido Retry/stubs sin función. Retry con call_id también necesita
   evidencia: bypass inferido por researcher, aún no reproducido.

Implementar una unidad coherente, no excepción por nombre/status:
- Pareja current/comando sintéticos válida: hermanos confirmados y outcomes
  correspondientes en current; target todavía running SIN resultado futuro;
  payload aplica outcome target. No copiar todo frame futuro al current.
  No mutar Store, Scope vivo ni journal real. Validar current y transición,
  conservar reservas conservadoras/token/cleanup/omisión antes del IO.
- Atestación output portable, acotada, discriminada/versionada en contenedor
  estructural, no campos silenciosos en Frame3 ni dispatch ficticio.
  Liga nodo/request/call seleccionada, descriptor output portable cuya preimagen
  coincida con output_fingerprint de ESA request, decisión éxito/retry, hashes
  de partes producidas/siblings y resultado portable/omisión cuando completa.
  Emisión sólo desde validación output host; primera output call y conjunto
  exacto siblings, resoluciones previas inmutables. CAS/decode validan evidencia
  sin ejecutar Ecto/codecs/hooks. Bytes y atestación confirmados coordinadamente;
  si intermedio explícito, acotarlo. ACK perdido reintenta sólo datos.
- ToolReturn Y Retry que resuelven call deben tener procedencia acreditada.
  Dispatch raw→final, resolve_call pre_dispatch, output y siblings se distinguen.
  Retry texto/native sin call no resuelve una tool. Retención valida bytes/marker
  sin habilitar replay. Status validation_error no prueba ausencia de dispatch.

## Compatibilidad y límites

Conservar Record1/Frame1–3, Frame4 vacío, mensajes y output directo. Frame5 válidos
sin output deben seguir legibles; no inventar evidencia para bytes incompletos,
no eliminar datos ni asumir que no existen consumidores experimentales.
Sin cambio publicado/bump/global/paid/consumer; guards intactos. Cambios del
descriptor/formatos deben quedar en diseño8.38/changelog antes de estabilizar.

## Matriz de cierre

- Dos tools con barrera y ambos órdenes: ambas entran, cada callback una vez,
  journal real running sin outcomes sintéticos. Mezcla running/raw/final.
- Output CountOutput directo vs paso, siblings/múltiples outputs: tipado igual,
  cero callbacks siblings; alterar ok/selección/stub rechaza CAS Y decode.
- Output inválido→válido y agotado/siblings: retries exactos; Retry fabricado
  para función no puede cerrar call. Reproducir negativo antes de corregir.
- Función real final_result con output texto exige dispatch; colisión output
  tipado+función homónima rechaza preIO conforme contrato existente.
- Args inválidos/unknown/denied/veto, errores dispatch/retry/timeout/hooks:
  conservar procedencia/status/raw_hash y efectos, no universalizar succeeded.
- Reutilizar call_id entre requests válido; mezclar request/nodo/call/schema,
  duplicar resolución o historia raw-only rechaza. Retención/omisión y límites.
- ACK antes/después outcome/final/evidencia output/step_output, retry data-only;
  capacidad predispatch cero IO. Originales y cleanup permanecen gates.

Oráculos intactos: /tmp/opencode/exagent-review-f1a519/{probes_test,tools_test}.exs,
/tmp/opencode/exagent-rereview-f1a519/{edges_test,history_test}.exs y
/tmp/opencode/exagent-finalreview-f1a519/{matrix_test,output_test}.exs.
Owner ejecuta focal/matriz/compile/formato/full habitual48 WA; review independiente
sobre fuentes finales antes de aceptar. No inferir aceptación de suite1010 previa.

## Propiedad

Intención: continuar worker de corrección residual, único escritor producto/docs
de contrato y único build ROOT. Padre sólo docs/orchestration. Researcher cerrado.
Entrega debe identificar causas, formatos elegidos, matriz→tests, hashes y límites.
Continuado `ses_f1a3818c8ffe07VdmX6maQDqnH` en background; implementación en curso.

## Entrega owner recibida

Worker finalizó; informe leído por padre:
`/tmp/opencode/exagent-contract-f1a381/REPORT.md`.
Manifest13/13, probes6/6 y cleanup intacto2/2 cotejados; delta36dd8b4f.
Frame6 añade output_resolutions version1, descriptor≤64KiB ligado a fingerprint
de request antes IO, transición output_resolution intermedia explícita data-only,
ToolReturn/Retry con procedencia y reserva current/comando coherente.
31regresiones nuevas; falso Retry reproducido rojo antes fix. Matriz73/0,
focal318/0, compile97/formato0, FULL1041/0/28 WA48 seed37556,193.2s, exit0.
Owner sin procesos activos; límites A→B/resume/SQL/live conservados.
Intención siguiente: revisor original verifica contrato integrado y seis probes
intactos sobre fuentes finales, exclusivo build ROOT/sin edits. No aceptar por suite.
Revisor `ses_f1a5196d4ffeREE6ykHAt2c46S` continuado background; dictamen pendiente.

## Revisión integrada: P2 de cardinalidad restante

Informe `/tmp/opencode/exagent-contract-review-f1a519/REPORT.md` leído y SHA
cd9a01251104293cc2c6d5d29ca23af491fb14619f389e08c0de381c12ef164e cotejado.
153focal/six-probes verdes,15legacy verdes, dos positivos nuevos; P2 reproducido
dos seeds: Record.tree_children sólo [2,3,5], Frame6 hoja running invisible para
receipt_reserve/cleanup/tree_slots. Receipts5→2,bytes33800→13070,1020receipts
admitidos invaden reserva anterior. No pérdida irreversible demostrada.
Contrato integrado sin otro defecto reproducido; paso NO aceptado todavía.
Reviewer cero procesos; siguiente unidad worker acotada Record/helper y regresión
cardinalidad, sin nuevo contrato ni debilitar guards. Probes intactos incluyendo
supplemental_test.exs de esa revisión. Padre exclusivo orchestration.
Worker `ses_f1a3818c8ffe07VdmX6maQDqnH` continuado background para fix acotado.

## Fix mínimo de cardinalidad recibido

`/tmp/opencode/exagent-frame6-reserve-f1a381/REPORT.md` y DELTA.patch leídos por
padre; SHA delta be6fc310, fuentes4/4+restantes9/9+probes7/7 verificados.
Una línea runtime incluye6 en tree_children. Dos regresiones comprueban reserva5,
1019receipts admitido/1020rechazado y JSON+cleanup8MiB exactos/+1; roja previa intacta.
Owner158focal/compile97/formato0/FULL1043/0/28 WA48 seed37556,195.1s, exit0.
Sin procesos propios; intención revalidar con reviewer original, build exclusivo,
sin edits ni full rutinaria. Aceptación pendiente.
Continuado reviewer `ses_f1a5196d4ffeREE6ykHAt2c46S` background; dictamen pendiente.

## Aceptación integrada — 2026-09-28

Reviewer acepta PASO ÚNICO offline, sin P1/P2 abierto en alcance. Informe leído:
`/tmp/opencode/exagent-reserve-acceptance-f1a519/REPORT.md`, SHA
262a4a2fa5649e73a5187ff54667aadbc4912d385320da875ccdf94285f74841 cotejado.
Independiente72/0 exit0 con siete probes intactos y límites1019/1020 y8MiB/+1;
manifiestos4+9+7+2 OK. Resto runtime byte-idéntico al contrato revisado.
Padre revalidó35/0 WA48 seed37556 (matriz+supplemental),8.6s, exit0:
`/tmp/opencode/exagent-reserve-acceptance-f1a519/parent-focal.log`.
Owner FULL1043/0/28 WA48,compile97/formato sigue evidencia owner, no suite reviewer.
Padre acepta esta unidad offline; rojos históricos intactos. No A→B, resume,
SQL/live ni R6 completo. Todos los builds liberados al padre, cero procesos propios.
Siguiente diseño acotado: tasks/r6-restore.md, investigador sólo lectura.
