# Consumo de output succeeded confirmado

Researcher ses_f19d56de2ffeyrhpzG6gpTRkAq terminó plan sólo lectura, sin tests.
Padre aprueba unidad acotada sobre input0/texto/completed aceptados offline.
No retry, batches, historia previa tools, reconciliación, A→B ni formato/token nuevo.

## Frontera exacta y binding

Frame7 ready/root+hoja running response1; un Model confirmed/succeeded con estado
portable y una operación Model ligada. Cero tool effects/batches/retry_batches/
outcomes/retries/approvals/plans. Historia ejecutable Request+Response sin returns.
Exactamente una atestación output1 succeeded del request/run actuales, descriptor
output-tool, finish no fallido; resultado portable y result_omitted nil.
Siblings de la MISMA response permitidos: primera output elegida, otros outputs
y funciones no ejecutados, partes atestadas completas/exactas/en orden.

Clasificar DESPUÉS Record.validate; reusar Frame/OutputResolution que ligan
request/modelstate/posición/descriptor a fingerprint, selección/siblings/hashes.
No conceder autoridad por etiqueta decision:succeeded.

Preclaim binding completo versionado definition/model_ref/output_ref y perfil
tipado/tool sin callbacks; descriptor persistido coherente con request y atestación.
No output_config ni OutputSchema.json_schema: ejecutan changeset vacío.
Padre acepta límite declarativo existente: cambiar código/schema conservando
referencias versionadas no es detectable, NO afirmar identidad semántica del código.
No nueva API de descriptor host; persistido sólo describe salida YA validada,
nunca selecciona módulos/código ni autoriza nueva validación/request.

## Seams

- CompositionRestore añade confirmed_output_success preflight data-only,
  selección interna validada por request, no opción caller que inyecte evidencia.
- Reusar claim→Authority.intersect→restore nodo→join→restore_tree→restore_step.
  Floors y continuation_frame temprano intactos; sólo ganador codec/registro.
- Preflight y prepare_run deben evitar output_config EN AMBOS caminos. Preparar
  params descriptivos desde descriptor atestado con conversión exacta/data-only y
  tools output inertes; no resolver módulos/callbacks desde JSON. Reusar fingerprint
  y Model.validate_resume. Preparación de tools host permitida después claim.
- Selección efímera interna de consumo success, no bandera pública bypass ni campo
  persistido nuevo. Consumir antes de rama ordinaria handle_output_call.
- Decodificar partes exactas entry.parts, append_returns una vez (historia acotada),
  finalizar con entry.result mediante succeed/Writer.finish/step_output existentes.
  Nunca Writer.output_resolution nuevo, Ecto, Model, after_model ni siblings.
  Timestamp del Request envolvente puede ser nuevo, bytes/hashes de partes no.
- Mismos request/runstep/model_data, journal/atestación/autoridad inmutables;
  Scope restore una vez, ledger/precios/uso sin repricing ni suma de snapshot.
  Codec dump no determinista rechaza sin relajar evidencia.

## Resultado y omisión

Resultado restaurado JSON normalizado (mapa, no struct Ecto); recorrido vivo conserva
su tipo previo. No rehidratar tipos/atoms/fechas invocando validadores.
result_omitted en atestación: error explícito preclaim/callbacks usando familia
composition_output_omitted; no completar con nil ni fabricar resultado/marker.
Valor portable presente pero copia terminal excede capacidad: mantener finish_child
existente, marker medido/atestación intacta y error de retención; consulta completed
sigue omisión, no rescatar otra copia alterando contrato. ACK retry sólo datos.

## Matriz finita

- VM nueva desde JSON real success durable, recovery explícito, completed mapa.
- Trampas separadas changeset/reflexiónschema/Model/after_model/mapping/tools/
  siblings0; codec/preparación/registro sólo ganador.
- Múltiples output calls+funciones, selección/orden/partes idénticas y callbacks0.
- Dos claimants CAS barrera un cierre, perdedor codec/registro/schema0.
- ACK resolution antes: ausente bloquea salvo token exacto aplicado; después
  consume sin nueva resolución. ACK step_output before/after data-only; returns
  no duplicados y completed no callbacks.
- Binding/ref cambiado y perfil text/native rechazan preclaim; código no versionado
  es límite host documentado. Corrupción request/run/call/descriptor/parts/hash/
  resultado/posición, absent/duplicate/retry rechazan con evidencia.
- Ambas omisiones y retención payload/history/checkpoint/receipts/JSON+cleanup/
  token exacto/+1. Límites actuales más estrechos y floor/tiempo/budget intactos.
- Precios históricos root≠leaf, estimadores nuevos explotan; ledger idéntico sin
  doble suma. Request_limit1 usado cierra sin nuevo request ficticio.
- Input0/texto/completed/floors/legacy y rechazo raw/batch/incertidumbre/approval.

## Propiedad y entrega

Intención owner fresco único producto/build ROOT+docs contrato, padre orchestration.
Fuentes ExAgent/CompositionRestore; helper OutputResolution pequeño si evita
duplicación. Frame/Writer sólo necesidad causal demostrada. Fixture real+contador
Ecto desde primer test. Informe recuperable temprano, baseline/deltas/hashes,
matriz/focal/compile/formato/full WA48 y review fresca antes de aceptar.
Despachado fresco `ses_f1959c317ffe2HZ2l1PTh1sIXm` background; producto/build ROOT
y docs contrato exclusivos, padre orchestration. Entrega pendiente.

## Reinicio servidor — recuperación, no nueva aceptación

Usuario pide continuar sin repetir completado; worker anterior notificado cancelled.
Padre confirmó mismo repo/HEAD/sesión, leyó REPORT hasta Milestone3 en
`/tmp/opencode/output-success-20260928-061414/` y comparó baseline-sources.tar.
11archivos cambiados/nuevos:3runtime, testtexto+outputtest+2support,4docs.
Focal197/197, compile100/formato owner registrados. FULL sin exit/resumen:3fallos
tree boundaries y SIGTERM, causalidad no diagnosticada. Nada se acepta por ello.
RESTART-RECOVERY.md y RESTART-SHA256SUMS preservados; sólo3BEAM ajenos previos.
Intención continuar mismo worker (cancelado por restart, no cifrado) con propiedad
exclusiva producto/build para diagnosticar/terminar verificación, luego review fresca.
Continuado `ses_f1959c317ffe2HZ2l1PTh1sIXm` background tras restart confirmado;
no dispatch duplicado, conserva propiedad exclusiva. Entrega final pendiente.

## Cierre operativo para relevo tras segundo reinicio

Notificación terminal del hijo: ERROR `Agent not found: "worker"`. Ya no activo;
no seguir intentando ese perfil/sesión ni cambiar configuración global por ello.
Padre verificó repo/HEAD, RESTART-SHA256SUMS11/11 intactos y sólo3BEAM ajenos.
REPORT nuevo describe focal boundary7/7,11.4s,exit0; causa de precursor
ready-vs-uncertain del full viejo NO establecida, no guards/timeout cambiados.

Artefacto adicional hallado y cotejado: full-recovery.log termina1153pases,
28excluidos,290.2s y full-recovery.exit=0. SHA log:
8634f8cc3eadaef980f4ddcde9877101b9d9d61d5accaa2ef7f6a49fc9fdd970.
REPORT todavía dice full pendiente: quedó anterior a su finalización, no es prueba
de fallo de la nueva suite. Fuente sigue siendo la misma11archivos del checkpoint.
No atribuir al verde causalidad histórica ni review independiente. Resta consolidar
entrega/delta/matriz y encargar revisión fresca, no repetir implementación/gates
por ignorar el log nuevo. Padre libera producto/build ROOT para otro orquestador,
sin nuevos hijos. Prompt docs/prompts/continue-native-2026-09-28.md actualizado.
