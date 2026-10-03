# ExAgent v2 — continuación nativa EL LISTO

## Relevo solicitado
- Usuario pidió prompt para otro orquestador. Preparado
  `docs/prompts/continue-native-2026-09-28.md`; este padre no despacha otro frente.
- Worker terminó ERROR `Agent not found: "worker"`; ya NO activo. Padre verificó
  hashes11/11 intactos y sóloBEAM3ajenos. Producto/build ROOT liberado para relevo,
  sin nuevo dispatch. Prompt actualizado con full-recovery1153/0/28 exit0 recuperado.
  Nuevo padre lee artefactos más recientes; revisión independiente sigue pendiente.

## Objetivo, proyecto y autoridad
- Proyecto `/home/kukapu/dev/projects/exAgent`, padre `ses_f1ace1c64ffeH58YvL9GT86SNi`.
- Usuario levantó pausa y sustituyó Orca por subagentes nativos. Procedencia
  histórica `run_37f56dd0d992`; NO invocar Orca ni crear/reactivar su Run.
- Handoff27sep leído entero, cabecera ORCA_CHECKPOINT gen4 leída. Dos dispatches
  históricos sin grant ctx_fe353eab3eb1/ctx_4464a7a5a05c no se consultan/reabren:
  estado actual incierto, no afirmar cierre. Nuevos hijos son nativos de este padre.
- Modelos: Astra low habitual; GLM coding plan/Muse Go opcionales sencillos;
  Opus5.5 high comodín autorizado pero OAuth bloqueado (ver tasks/r6-persistence.md).
- Preservar WIP. No reset/stash/clean/config global/consumer apps. ReqLLM stock,
  sin fork/patch/Jido. Permisos G2/G3/G4/G5 y R9.4 heredados condicionados a gates;
  no publicación/bump/commit prematuros. Secretos sólo entorno/programáticamente.

## Baseline y resultados aceptados
- HEAD7f25b336. Preflight fuente324/324 ef308, manifest c9a5, TAR2fbf y lockc20a
  verificados. Freeze27sep NO incluye cambios R6 posteriores. R0–R5 no reauditar.
- Smoke live freeze GPT4omini3/3,4admisiones/1efecto/USD0.10reserva, sin retries;
  factura desconocida. REPORT /tmp/opencode/native-smoke-live-f1ace1 SHAd30ba225,
  hashes/resultados/ledger verificados. No Luna ni deltaR6. Detalle tasks/smoke.md.
- Constructor/binding Composition aceptado offline tras fix P2 struct truncada:
  padre50focal, reviewer16+119probes. Detalle tasks/r6-design.md.
- Scope estructural aceptado: owner971pases28excluidos WA; reviewer54/probes.
- Raíz persistida vacía aceptada tras fix P2 preflight reapertura: owner979pases
  28excluidos WA ANTES fix; padre94focal/reviewer28 después, sin hallazgos pendientes.
  Record2/execution2/Frame4 empty/StructuralSnapshot1; mismo Writer/CAS/Store.
   Ese hito no incluía hojas/step links; el paso posterior se acepta abajo.
  Detalle/evidencia: tasks/r6-persistence.md; roadmap§5 es tablero único.

## Propiedad y sesiones
- Padre: único escritor docs/orchestration; producto/builds del owner activo abajo.
- Researcher diseño `ses_f1acc9c45ffeqirznUvkmBkcUk` terminado.
- Smoke `ses_f1acc477fffewdyxlH14kuQ9ZK` terminado, cero procesos/paid pendientes.
- Constructor owner `ses_f1ac7ec83ffe3E25IFjI5zoxzs` terminado.
- Reviewer constructor/Scope `ses_f1ab57621fferW3f2jLhglzBYS` terminado.
- Scope owner `ses_f1aaecc76ffeDNHivDh90V4NXA` terminado.
- Raíz owner `ses_f1a965a98ffe5XQfyn4I9v2lin` entregó paso→hoja durable parcial;
  reviewer fresco `ses_f1a84411fffeuRRhT4st6rtPc0` terminó revalidación/cero procesos.
- Intentos fallidos/sin avance y modelos en tasks/r6-persistence.md/DECISIONS.md;
  no duplicar ni contar sus entregas como aceptación.

## Unidad entregada y frentes siguientes
- PASO ÚNICO aceptado offline2026-09-28 por reviewer y padre: input/link antes IO,
  output después; Frame5/6 evidencia Model/tool/Retry/output, ticket/cleanup y reservas.
  Reviewer ses_f1a5196d4ffeREE6ykHAt2c46S terminó72/0 con siete probes intactos,
  sin P1/P2 abierto; /tmp/opencode/exagent-reserve-acceptance-f1a519/REPORT.md
  SHA262a4a2f cotejado/leído. Padre35/0 WA48 matriz+supplemental,8.6s, exit0.
  Owner ses_f1a3818c8ffe07VdmX6maQDqnH FULL1043/0/28 WA48/compile97/formato0.
  Último fix una línea Record.tree_children6; delta be6fc310 leído, hashes4+9+7+2 OK.
  Receipts5/33800bytes;1019/1020 y JSON+cleanup8MiB/+1. Builds liberados al padre.
- Historial causal/rojos/recuperación worker fallido en tasks/r6-step-review.md y
  tasks/r6-evidence-contract.md. Cambio conceptual researcher ses_f1a1fd00affeUOX23OD7fFX7VM
  cerrado: atestación output explícita y reserva current/comando coherente.
- MCP test-only separa handshake5000+ready/request50 real; runtime intacto.
  tasks/mcp-timeout.md; suite habitual verde posterior, no diagnóstico scheduler inventado.
- Padre consolidó aceptación en roadmap/diseño/changelog/status/r6-implementation;
  recepción documental posterior a hashes runtime aceptados, no nuevo freeze.
- Siguiente: restore ejecutable UNA hoja con piso autoridad raíz persistido,
  actual∩original, mismo ledger sin repricing. tasks/r6-restore.md fija intención.
  Researcher ses_f19d56de2ffeyrhpzG6gpTRkAq terminó sólo lectura; plan recibido
  en ficha, padre acepta Frame7/piso original y fronteras conservadoras (raw y
  validación opaca sin decisión bloquean, crash no recarga budget).
  Worker ses_f19d07621ffeMI70P3ynCPcJ4p terminó SIN implementar/sin bloqueo;
  sólo7fixtures legacy auténticas. REPORT leído, hashes7/7+lib/test intactos.
  Cambio estrategia: restore sólo input_confirmed step0/cero intents, más completed
  data-only; resto fronteras rechaza explícitamente. Frame7/piso y VM nueva/carrera
  siguen obligatorios. Owner ses_f1a3818c8ffe07VdmX6maQDqnH falló encrypted_content;
  NO continuar conversación. Dejó8archivos parciales (Authority/Frame7/Scope/Writer),
  padre comparó before.tar y compile7 WA exit0; no restore ejecutable demostrado.
  /tmp/opencode/exagent-restore-input-f1a381/RECOVERY.md y hashes preservados.
  Owner fresco ses_f19bf814affe9u8uJJAQrtTGI7 terminó input0 real/completed data-only.
  REPORT/COMMANDS leídos en /tmp/opencode/exagent-restore-recovered-f19bf814;
  hashes24/24 OK, delta-baseline c8976dbc. Compile99/formato/focal123/FULL1072/0/28
  WA48 owner. Probes intactos38/40:2rojos supuestosFrame6, explicación por verificar.
  VM nueva/carrera CAS/autoridad probadas owner; review independiente pendiente.
  Reviewer ses_f199cb6f4ffedOJYBETLL82XLz terminó RECHAZO P1: ExAgent488
  pisa permission_floor actual hoja con floor persistido; allow antiguo/deny actual
  ejecuta tool. Focal123verde, probe1/2rojo. Informe leído SHA71eaf56a.
  Dos rojos Frame6 verificados incompatibilidad fixture; equivalentes7+codec4/4.
  Owner ses_f19bf814affe9u8uJJAQrtTGI7 falló encrypted_content DESPUÉS de
  guardar entrega: /tmp/opencode/exagent-restore-floor-f19bf814/REPORT.md leído
  SHAf9dc24f2/delta25bfaaa8 leído; hashes5+3 OK, full.log1088/0/28 WA48.
  Fix mínimo conserva floor singular y añade persistido a plural;16regresiones,
  focal171/compile99/formato owner. Sin BEAM nuevo. No continuar hijo dañado.
  Reviewer ses_f199cb6f4ffedOJYBETLL82XLz terminó171/171 WA48: P1 cerrado,
  ACEPTADO input0/completed data-only. Informe recheck SHA0cafcd64 leído/cotejado,
  padre46/0 WA48 input_restore+probe intacto (18.6s). Owner FULL1088/0/28 separado.
  Docs roadmap/diseño/changelog/status/r6 consolidadas; recepción posterior al freeze.
  Build ROOT libre padre; workers cifrados NO continuables. tasks/r6-restore.md detalle.
   Researcher ses_f19d56de2ffeyrhpzG6gpTRkAq terminó: sólo primera response TEXTO
   confirmada→cierre, sin requests nuevos/repricing; atestaciones se aplazan.
   Owner ses_f1984baeaffeKikLuWkr7x1DEh ERROR encrypted_content. Padre comparó
   baseline.tar.gz: runtime intacto, docs design/changelog+test4casos parciales.
   /tmp/opencode/exagent-text-restore-f1984bae/RECOVERY.md registra rojo2/4:
   frontera no soportada y fallo setup model_io con lease50 aún sin diagnosticar.
   Owner ses_f197e7e82ffexa1OUFF3kjc4hR terminó slice textual: REPORT leído
   /tmp/opencode/exagent-text-restore-recovery-new SHA0de8defe, manifest completo OK,
   delta8files(runtime sóloExAgent/CompositionRestore).37matriz/165focal(owner antes
   4tests finales)/FULL1125/0/28 WA48/compile99/formato0. No procesos propios.
   Reviewer ses_f19634a38ffeh58LMSXD7Avs3l terminó169/0 WA48: ACEPTADO TEXTO
   confirmado1→cierre. REPORT SHAe33afbaf leído/cotejado, manifest11/11 OK,
   padre37/0 matriz47.8s exit0; ownerFULL1125 separado. Probe extra no ejecutado
   no cuenta como evidencia. Docs aceptación consolidadas, ROOT libre padre.
   Researcher ses_f19d56de2ffeyrhpzG6gpTRkAq terminó plan output success portable;
   padre acepta tasks/r6-output-success.md, binding declarativo output_ref versionado,
   sin Ecto/reflexiónschema/Model/siblings repetidos. No retry/resultado omitido.
    Reinicio servidor: owner ses_f1959c317ffe2HZ2l1PTh1sIXm CANCELLED, no cifrado.
    Mismo padre/repo/HEAD comprobados. /tmp/opencode/output-success-20260928-061414
    REPORT leído: implementación guardada, focal197/compile100/formato owner verdes.
    FULL sin cierre,3fallos boundary antes SIGTERM; no atribuir causa ni aceptación.
    Padre comparó baseline/preservó RESTART-RECOVERY y hashes11, sin BEAM nuevo.
     Continuación terminó ERROR Agent not found:worker. Padre recuperó logs
     boundary-recovery7/7 exit0 y full-recovery1153/0/28 exit0,290.2s; hashes11/11
     aún intactos, sóloBEAM3ajenos. Full SHA8634f8cc. REPORT aún no consolidado.
     Producto/build liberado para nuevo orquestador; NO review/aceptación output aún.
  A→B/delegado/router/paralelo siguen pendientes; Frame5/6 actuales sólo inspección.
- Usar prefijo environment + EXAGENT_OFFLINE=1 MIX_ENV=test y MIX_BUILD_PATH absoluto
  /home/kukapu/dev/projects/exAgent/_build/test. Suite≈180s: timeout≥600000.
- Build copiado debe conservar profundidad _build/test y links deps (incidente smoke).
- R6 completo, R7, R8–R9/G4 UI/exporter/CI exacta siguen abiertos. Luna length_stream
  sigue no cualificado. No nuevas llamadas pagadas programadas por este hito.
