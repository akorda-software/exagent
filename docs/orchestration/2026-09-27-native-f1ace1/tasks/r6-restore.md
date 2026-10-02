# Siguiente unidad: restauración ejecutable del paso único

Precondición: paso único aceptado offline por reviewer y padre2026-09-28;
tasks/r6-evidence-contract.md conserva evidencia final y defectos históricos.

Objetivo de investigación: definir el menor seam completo de restore desde bytes
para una hoja bajo raíz estructural, con piso de autoridad original persistido y
restricciones actuales intersectadas, mismo Writer/CAS/Scope/ledger sin repricing.
No asumir que Frame5/6 actuales contienen autoridad suficiente ni migrarla por
inferencia. Record1/Frame1–4 y Frame5/6 de inspección siguen legibles; datos sin
piso no deben convertirse en permiso para ejecutar.

Preparar fronteras restaurables y no restaurables: input confirmado, request
intent incierto, response/outcomes/atestación confirmados, output completado,
ACK/token data-only, owner muerto/lease/claim. No replay de Model/tools/mapping
confirmados ni resolver incertidumbre automáticamente. Incluir VM nueva, carreras
de dos resumers, binding/autoridad/deadline/retención y tests legacy.

Investigación sólo lectura por researcher; sin shell/edits ni reauditar R0/Jido.
Entregar plan causal con referencias a seams C7 existentes, formato/migración,
API interna mínima y matriz finita. A→B/delegado/router/paralelo se mantienen
siguientes, no implementarlos en esta investigación. Padre conserva build/docs.
Despachado researcher `ses_f19d56de2ffeyrhpzG6gpTRkAq` en background, plan pendiente.

## Plan recibido y decisiones del padre

Researcher terminó sólo lectura. Arquitectura válida; falta autoridad durable,
no ledger. Padre contrastó Budget.claim/abandon y Writer.step_deadline: reserva
activa no se devuelve tras crash y lease no puede convertirse en deadline lógico
permanente. Se autoriza UNA vertical integrada, no formatos parciales sucesivos.

### Formato y autoridad

- Nuevo Frame7 estructural desde empty→running→completed, children0/1,
  output_resolutions existente output1 y autoridad por run_id raíz/hoja.
  Record2/snapshot composition1/hojaFrame3/Scope2 se conservan. No migrar ni inferir
  autoridad de Frame4–6: lectores/inspección válidos siguen, ejecución rechaza
  explícitamente ausencia de piso. Congelar fixtures de bytes legacy reales.
- Capturar restricciones EFECTIVAS del Scope: UsageLimits todos campos,
  permissions y floor como políticas conjuntivas (no concatenar reglas),
  max_concurrent_requests, deadline lógico UTC. Raíz también checkpoint_limit.
  Hoja reutiliza límites locales Frame3, sin duplicación divergente.
- Autoridad raíz confirmada en create, hoja con step_input. Originales inmutables;
  restore intersecta restricciones actuales, min numérico/strict si cualquiera
  exige strict, sin ampliar ni sumar contabilidad. No callbacks en decode.
- Separar deadline lógico de lease y presupuesto activo del intento. No duplicar
  execution.deadline_at/expires_at ni progress.active_budget. Conservar semántica
  Budget: tras crash abandon puede dejar0 y claim debe rechazar, no recarga.

### Seam integrado y fronteras

API interna propuesta resume_composition_step(definition, reference, opts), una
hoja, lifecycle raíz/Writer. Firma exacta a documentar por owner antes de estabilizar.
Preflight data-only binding/ref/key/formatos/evidencia/autoridad/retención y clasificar
antes de callbacks. Completed devuelve datos/omisión sin codec/mapping/claim/IO.
Claim CAS fresco, owner vivo/conflicto rechaza; recovery explícito tras lease,
no receipt viejo autoriza ejecución. Sólo ganador hace codecs/rehidratación/registro.
Crear raíz y hoja host, restore_tree una vez, mismo Writer y loop retenido. No
disfrazar Record2 como1 ni quitar guard Frame.restore agente; seam de nodo validado.

Fronteras positivas: empty (mapping puro no confirmado puede recalcularse),
input confirmado step0 (no mapping), response texto confirmado (no Model ni
after_model), batch con outcomes finales (reusar, sólo ejecutar no despachadas),
atestación output success/retry (consumo exacto sin Ecto/hooks/siblings), completed.
Tipos vivos no se reconstruyen invocando callback desde resultado portable;
documentar representación restaurada explícitamente.

Negativos obligatorios: intent Model/tool running/unknown exige recovery host,
no replay. Raw confirmado pero final incierto bloquea (reconcile actual no lo
resuelve). Output tipado/native sin decisión persistida: validación opaca pudo
haber corrido; no reejecutar silenciosamente, error diagnosticado. Payload/model/
history/output requerido omitido bloquea ejecución. Cancel/expire/deny/approval
no ejecutan. No ampliar aprobación/delegación en esta unidad.

Reusar reconcile/reconcile_model sólo con integración explícita y evidencia
suficiente; ModelRecovery.refresh_usage no debe escribir usage en snapshot raíz
composition1. No fingir compatibilidad abriendo allowlist sin adaptar invariantes.
Si esos caminos no pueden integrarse con seguridad, reportar limitación/bloqueo
concreto; no afirmar que raw confirmado ya es reconciliable. Sin retry automático.
Pre-hooks anteriores al intent no tienen exactly-once; codecs/mapping/rehidratación
son reconstrucción pura según contrato host, no permiso de repetir efectos ocultos.
ACK/token pendiente sólo retry_checkpoint exacto data-only, luego releer.

### Gates de entrega

- VM nueva desde bytes reales: input/response texto/batch final parcial y completo/
  atestación success+retry/completed, sin PIDs/captures del proceso anterior.
- Dos resumers con barreras: único claim/IO, perdedor cero codec/mapping/callback;
  receipt reproducido no activa. Owner death/lease/presupuesto agotado/refund.
- Autoridad root y leaf original deny/ask→actual allow y actual más restrictiva;
  límites0/exacto, strict/estimated, concurrencia, deadline lógico≠lease.
- Estimador cambiado: historia sin repricing, nuevas operaciones precio vigente.
- Binding/corrupción IDs/refs/policy/output/mapping/autoridad y journal↔ledger;
  reservas Frame7 JSON/J/token/receipts/cleanup exacto/+1.
- ACK antes/después claim/input/response/raw/final/atestación/output; no replay.
  Negativos de todas fronteras inciertas con efectos/callbacks contados.
- Legacy reales Record1/Frame1–6 legibles,4–6 ejecución rechazada por piso ausente.
- Focal integrado, compile/formato/full WA48 offline, review fresca independiente.

Owner único nuevo para implementación, producto/build ROOT+docs contrato asignados;
padre sólo orchestration. Sin A→B/router/paralelo/consumer/paid/global/commit/bump.
Despachado worker fresco `ses_f19d07621ffeMI70P3ynCPcJ4p` background para esta
vertical integrada; producto/build/docs contrato exclusivos. Entrega pendiente.

## Entrega incompleta y cambio de estrategia

Worker ses_f19d07621ffeMI70P3ynCPcJ4p terminó sin producto ni bloqueo demostrado.
Informe leído `/tmp/opencode/exagent-restore-f19d076/REPORT.md`; padre verificó
LEGACY-SHA256SUMS7/7 y baseline/sources.sha256 completo sin cambios lib/test.
Siete records reales Frame4–6 capturados/validados sirven como fixtures; no son
restore implementado ni nuevo gate funcional. Worker devuelve builds sin procesos.

No repetir despacho de toda la matriz. Próxima unidad reduce FRONTERAS, no guards:
restore ejecutable desde bytes únicamente input_confirmed/request step0 sin
intent/operaciones, y consulta completed data-only. VM nueva y dos resumers deben
demostrar ejecución real exactamente por claimant ganador. Introducir Frame7 con
autoridad efectiva root/leaf como diseño anterior, sin otros formatos intermedios.
Otros cursores/intents/raw/response/atestación/approval se clasifican y rechazan
explícitamente pre-callback; su implementación continúa pendiente en siguiente
unidad. No integrar reconcile/reconcile_model ahora ni prometer restore general.
Si vacío se incluye, no relajar mapping ni capacidad; no es requisito para cerrar
esta subunidad. Captura/read/binding/authority/preflight/claim/cleanup y límites
actual∩original siguen obligatorios, incluyendo lease lógico separado y budget.

Se reusa owner que implementó contrato evidencia por conocimiento concreto de
Frame/Writer y gates; encargo acotado funcional, no sólo abstracciones. Padre
mantiene memoria, owner producto/build+docs contrato. No aceptar sin review nueva.
Continuado `ses_f1a3818c8ffe07VdmX6maQDqnH` background para input_confirmed;
propiedad exclusiva producto/build ROOT. Entrega pendiente.

## Interrupción proveedor y recuperación parcial

Worker ses_f1a3818c8ffe07VdmX6maQDqnH terminó invalid_encrypted_content.
No continuar conversación dañada. Padre leyó informe temprano en
`/tmp/opencode/exagent-restore-input-f1a381/REPORT.md`, comparó contra before.tar:
seis fuentes modificadas (ExAgent/Writer/Frame/Record/Transition/ExecutionScope),
Authority nuevo y test smoke inicial nuevo. No docs modificados por ese intento.
Padre compile WA7archivos exit0, log parent-recovery-compile.log; no tests verdes
ni seam resume público/interno completo demostrado. Sin BEAM nuevo conocido.
RECOVERY.md y RECOVERY-SHA256SUMS en ese directorio preservan estado.
Intención siguiente: owner fresco completa parcial bajo MISMO alcance reducido,
no repetir preparación ni sobrescribir baseline. Review posterior sigue requerida.
Despachado fresco `ses_f19bf814affe9u8uJJAQrtTGI7` background, ownership exclusivo
producto/build ROOT+docs contrato. Padre sólo orchestration; entrega pendiente.

## Entrega recuperada para revisión fresca

Owner ses_f19bf814affe9u8uJJAQrtTGI7 finalizó sin procesos. Padre leyó REPORT y
COMMANDS en `/tmp/opencode/exagent-restore-recovered-f19bf814/`, verificó24/24
SOURCE-SHA256SUMS y delta-baseline c8976dbc5805e2d2598d02240273438c27bd744e35b9c1f4aaa16c601451b5ab.
Restore input0 real, completed portable data-only; Frame7 authority y claim ganador.
Owner compile99/formato0/focal123/0/FULL1072/0/28 WA48 seed37556,205s, exit0.
VM nueva y carrera CAS dentro de gates. Siete fixtures legacy copiadas auténticas.
Siete probes históricos intactos + suites38/40 exit2: supplemental espera6 en vez7
y downgrade a5 conserva authority; owner ofrece equivalentes Frame7 verdes.
NO relabelar esos rojos: reviewer debe verificar incompatibilidad vs regresión.
Ningún restore general/response/raw/atestación pending/approval/SQL/A→B aceptado.
Intención: reviewer fresco independiente, exclusivo build ROOT sin edits, revisar
autoridad/captura efectiva/intersección/deadline-lease y claim/callback/compatibilidad.
Despachado reviewer fresco `ses_f199cb6f4ffedOJYBETLL82XLz` background, builds
ROOT exclusivos/sin edits; dictamen independiente pendiente.

## P1 de revisión fresca — no aceptar restore

Reviewer terminado, informe leído
`/tmp/opencode/exagent-restore-review-f199cb6f/REPORT.md` SHA71eaf56aef75ee14d4a5b66b08f9a9ae5663cd37f67f91a1fb3f9c38ede36590.
ExAgent488 Keyword.put permission_floor sobrescribe floor actual conservado por
Authority.intersect: original allow/actual deny ejecuta tool. Probe real input0
floor_probe_test.exs SHA15fb12a2f034797799bd0b761b9705ce1cebd55928f2ff560be5fa5e711904fd,
1/2 pasa, control permission_floors plural bloquea. Padre leyó codepath485–489.
Corregir conjunción original+actual sin perder orden/floors, regresión integrada
deny/ask y contraparte original restrictive/currentallow. No broad refactor.

Focal123verde, legacy7intactas, sources24/probes7 OK. Reviewer verificó dos rojos
históricos como incompatibilidades de fixture (6vs7/downgrade5 conserva authority),
NO pases originales:38/40. Equivalentes7 3/3 + codec failure1/1 verdes.
Reviewer cero procesos, ROOT libre; intención devolver fix acotado al owner.
Continuado owner `ses_f19bf814affe9u8uJJAQrtTGI7` background, exclusivo producto/
build ROOT para P1 floors; entrega/revalidación pendientes.

## Recuperación de entrega floors tras error del proveedor

Owner ses_f19bf814affe9u8uJJAQrtTGI7 terminó invalid_encrypted_content, pero
artefactos finales estaban guardados. No continuar conversación dañada.
Padre leyó REPORT y delta en `/tmp/opencode/exagent-restore-floor-f19bf814/`,
verificó SOURCE5/5+PROBES3/3, ps sólo tres BEAM previos, tail full.log1088/0/28.
REPORT SHAf9dc24f2b24eb1dfa28311bf9c67ce47c037cf47c5609c8a3d5492849559c98e;
delta25bfaaa8a93f985be6847f955cb48e3fe6288e2d9c98dad097f76c4c8788428b.
Único runtime delta añade floor persistido a plural sin pisar singular;16tests
integrados root/leaf×singular/plural×deny/ask×current/original. Owner171focal,
compile99/formato0/FULL1088/0/28 WA48 seed37556,214s,exit0 según informe/logs.
Rojo original conservado; fixture orden reglas rojo también documentado.
Intención revalidación reviewer original exclusivo build ROOT, sin edits.
Continuado `ses_f199cb6f4ffedOJYBETLL82XLz` background para revalidación P1/dictamen.

## Aceptación input0 — 2026-09-28

Reviewer cierra P1 y acepta input0/completed data-only offline:171/171 WA48,
probe original intacto2/2, sin nuevos hallazgos. Informe leído y SHA cotejado:
`/tmp/opencode/exagent-restore-floor-recheck-f199cb6f/REPORT.md`
0cafcd64b571ab37b2b88f6bdf6eeffaef00670921a15e5f71701ce5a2f88a3d.
Padre verificó SOURCE5/5 y reejecutó floor_probe intacto+input_restore:46/0 WA48
seed37556,18.6s,exit0 (parent-focal.log en mismo directorio). Owner FULL1088/0/28
WA48/compile99/formato son resultados anteriores del mismo runtime, no full reviewer.
Se acepta sólo input0 y completed, no otras fronteras/A→B/SQL/live/R6 completo.
Reviewer devuelve ROOT sin procesos. Hijos workers dañados no se continúan.

Siguiente intención: researcher sólo lectura define slice siguiente de response
texto confirmado y/o atestación output confirmada, sin repetir Model/Ecto/hooks,
VM nueva y contabilidad histórica. Scope permisos preservado. No otro formato
preventivo ni batches/raw/recovery general ahora. Comparar opciones y recomendar
unidad funcional finita con seams/test matrix antes de dispatch implementación.
Researcher `ses_f19d56de2ffeyrhpzG6gpTRkAq` continuado background sólo lectura;
padre conserva builds/documentación mientras prepara aceptación.
