# Relevo de orquestación — continuar ExAgent v2.0.0

Este es el prompt de transferencia preparado por petición del usuario el
2026-09-26. La implementación sigue autorizada. La pausa es exclusivamente de
transferencia: al recibir este mandato, recupera el **mismo Run**, confirma
ownership y reanuda la Task incompleta. Sigue coordinando hasta completar las
unidades ejecutables o encontrar un bloqueo real. No termines sólo diciendo que
hay workers trabajando. La cabecera de `ORCA_CHECKPOINT.md` y el checkpoint del
owner prevalecen sobre los relatos históricos inferiores.

**Pausa confirmada a las22:00UTC** por `msg_65aee9b58627`, leída y ACK. Owner sin
comandos Mix/test propios activos, sin worker_done, ownership retenido. Fuente durable
exacta: `docs/archive/2026-09-26-r5-tree-progress.md`. Recibo
`/tmp/opencode/exagent-r53-pause-RECEIPT.md`; inventario295 archivos
`/tmp/opencode/exagent-r53-pause-inventory.json`, SHA256
`925e37de480ed05e4ef92beb176571613a2d9ee2d8d4d3ba85a678c4568ce6cb`;
delta `/tmp/opencode/exagent-r53-pause-from-f8b5.diff`, SHA256
`6b10a6240f50c306144376f4570c50094d2bd97ad68bd06432a3bd914c70d38f`.
Ambos hashes y lock comprobados por coordinador después de la pausa. No son un
freeze aceptado ni un TAR; son inventario recuperable del WIP. Cero archivos base
borrados,16 deltas respecto f8b5:15 tocados por owner actual más root-progress de
recepción previa. Archivos del coordinador excluidos de ese inventario atribuido.

## 1. Mandato, modelos y restricciones

- Proyecto `/home/kukapu/dev/projects/exAgent`, framework Elixir extensible propio,
  roadmap R0–R9, objetivo v2.0.0. Nominal actual **1.3.0**, sin bump.
- **Todos los workers nuevos: `openai/gpt-6-astra`, razonamiento `low`.** Contexto
  fresco para Tasks nuevas. Reusar las dos Tasks abiertas de abajo está justificado
  por continuidad de implementación/review. No GLM/Grok ni otra red de subagentes.
- Carga `orca-orchestration`; usa exclusivamente Tasks/workers de Orca. Un owner
  fuentes/builds por área; reviewers readonly con copias/builds físicos privados.
- ReqLLM oficial stock; sin fork/vendor/patch/monkeypatch/parser wire privado/Jido.
- C7 sigue incluido: aprobación humana persistida y continuación segura tras reinicio.
  No sustituir por callback bloqueado ni cerrar una garantía requerida como limitación.
- Sin commits/push/PR/bump/publicación, instalaciones/resoluciones nuevas, cambios
  globales/reinicios ni modificaciones de consumidores reales sin autorización.
- Sin LLM pagado de pruebas, Postgres real u Opik real sin destino/alcance/presupuesto.
  Credenciales disponibles no conceden permiso. No imprimir secretos/capabilities.
- Preservar WIP completo. Nada de reset/stash/clean ni sobrescribir checkout.
  Ediciones manuales con `apply_patch`, incluidas importaciones de deltas.
- Sigue AGENTS y normas globales; no confundir archivos legacy retirados con pérdidas
  accidentales. No atribuir todo el diff contra HEAD a la última Task.

## 2. Estado real: R4 ya aceptada, R5 raíz parcial aceptada

| Área | Estado al relevo |
|---|---|
| R0 | Verificada históricamente |
| R1 | Perfil mínimo aceptado offline; backend stock/retirada legacy; G2 pendiente |
| R2 | Aceptada offline, incluido native cualificado |
| R3 | Aceptada offline tras cierre de cuatro P2 de retención |
| R4 | **Integrada y aceptada offline**, review independiente final recibida |
| R5/C7 raíz | **Unidad parcial aceptada offline** tras cerrar cuatro P2 propios |
| R5/C7 restante | Owner fresco implementa árbol/Scope y Server; pausa de transferencia |
| R6–R9 | Pendientes según dependencias/gates externos |

Tabla única: `docs/development/roadmap.md` §5. No reiniciar R0, investigar Jido,
rehacer R1–R4 ni repetir la importación R4. La primera acción útil es recuperar el
owner R5 actual y su WIP, resolver las decisiones pendientes y continuar C7.
R5 raíz, R5 completo, C7 aceptado externamente y publicación son estados distintos.

## 3. Recuperación de Orca y ownership

Identidades observadas; volver a consultar, no inventar handles si cambió el runtime:

- Run `run_37f56dd0d992`, generación saliente **3**.
- Coordinador saliente `term_f5881fea-4d1f-47be-b87f-3aeb206faa0a`.
- Runtime `2759e8ef-16ca-4be7-a2b3-be0d711a1e29`, Orca `1.4.211-kukapu.1`.
- Workspace `83438294-6397-425c-a0b2-8def0a505dda::/home/kukapu/dev/projects/exAgent`.

```text
orca status --json
orca worktree current --json
orca orchestration run-current --json
orca orchestration run-show --id run_37f56dd0d992 --json
orca orchestration worker-list --run run_37f56dd0d992 --include-remote --json
```

Después de confirmar transferencia y ausencia de otro coordinador actuando, usar
`run-use --id run_37f56dd0d992`. En esta sesión el relevo de contexto conservó el
mismo handle/generación; eso no debe presumirse para el siguiente proceso.
No crear otro Run por perder contexto ni forzar autoridad.

### Owner a reanudar, MISMA Task incompleta

- Task `task_ec3210551bcd`, Dispatch `ctx_5963c2e6fb6e`.
- Terminal `term_8e7b0a76-78b1-4804-9d23-d0e980b3c84f`.
- Astra low observado desde lanzamiento. Ownership exclusivo ROOT/docs/builds.
- Coordinador posee sólo `ORCA_CHECKPOINT.md` y este prompt de transferencia.
- Pausa solicitada `msg_198ee90c20b0`, confirmada `msg_65aee9b58627` y ACK.
  Contrastar cabecera del checkpoint antes de reanudar. No worker_done ni cesión.
- Terminal figura **user_owned / retained / user_takeover**. No cerrarlo por fuerza.

### Reviewer a conservar esperando

- Task `task_0ee986f3992e`, Dispatch `ctx_7c85ffbff803`.
- Terminal `term_0753dce2-cf9f-4d99-a8d9-eca3adfb7ba8`.
- Astra low. Misma review abierta, idle sin worker_done para próximo freeze.
- Copias `/tmp/opencode/exagent-r5-review`, subcopias `root6a65` y `fixf8b5`.
- Último dictamen acepta sólo raíz corregida f8b5. No acceptance de WIP posterior.
- Notificado relevo `msg_af2dc78fc299` sin despertarlo; no afirmar lectura.
- También figura user_owned/retained: conservar, no cierre forzado.

### Owner anterior: ya cerrado, NO reanudar

`task_1d1c02dc7d4c` / `ctx_5bb6fbe1a227`, terminal
`term_2d54008a-63d9-4e22-89fe-9db9424ee258`: worker_done succeeded con alcance
**parcial** autorizado, cesión ROOT confirmada `msg_77c63832e415`. Retained porque
es user_owned. Su contexto llegó a ~545k; el owner actual es fresco.
Integrador/reviewer R4 anteriores cerrados y released; no reactivarlos.

Procesar correo FIFO, responder preguntas por reply y luego ACK; un ACK puede
entregar otro lote. Mensaje encolado no prueba lectura. Si un Dispatch activo está
idle, inspecciona y envía continuación segura al MISMO terminal; nunca worker-start
sobre Dispatch activo. Stale/unverifiable no demuestra muerte.
Si hubo revocación/reinicio, seguir recuperación literal de la skill: Tasks ready
se relanzan con --task; --retry-of sólo intentos failed/blocked elegibles. No editar
estados para esquivar controles ni recuperar capabilities de logs.

## 4. Cómo garantizar Astra low

`worker-start --agent opencode --model openai/gpt-6-astra` **no admite --effort**.
No inventar flags ni cambiar configuración global. Un lanzamiento inicial heredó
high: se interrumpió sólo el turno readonly y se cambió la variante en la TUI antes
de continuar. Los lanzamientos posteriores sí mostraron low desde el inicio.

Método probado: la spec nueva empieza con heartbeat y espera de confirmación de
variant/ownership antes de investigar/build. Inspeccionar TUI/hook y confirmar low
por mensaje/reply. Si no es low, sólo en punto seguro/idle usar Commands (Ctrl+P),
`Variant cycle`, o Ctrl+T, inspeccionando después de cada pulsación. En esta versión
se observó high→xhigh→max→sin etiqueta→low. No reenviar una secuencia ciega ni confundir
launch.effective effort:null con low demostrado. Modelo principal no se cambia.

Preferir worker-read con redacción; **la redacción puede fallar en capabilities
partidas por wrapping de TUI**. Nunca volcar pantalla cruda. Si se consulta terminal,
añadir saneamiento antes de imprimir, por ejemplo reemplazar secuencias largas
alfanuméricas/base64url de 32+ caracteres; eso también oculta hashes/IDs de pantalla,
que se consultan por metadatos/archivos seguros aparte. No copiar capabilities al prompt.

## 5. Baselines y artefactos exactos

### R4 integrada aceptada

- Source279 `/tmp/opencode/exagent-r4-integration-source.tar.gz`:
  `cdd2a042387f24e6b29dd83adb1cfae06aad07669c2ee8682302aaa32083f013`.
- TAR103 `/tmp/opencode/exagent-r4-integration-final.tar`:
  `ac5447127d90e829185cfeb95d820bdbe0d3d1e1ee51750c8c0882cfd2601386`.
- Manifest `/tmp/opencode/exagent-r4-integration-manifest.json`:
  `1488bbd69be8ae8b872047ecd7a03839b5a29142054919a6393696da6ae3b1f8`.
- Review `/tmp/opencode/exagent-r4-integrated-review/REVIEW.md`: compile80,
  focal33, snippets9, ambas aplicaciones de deltas279 y TAR103 verificados.
- Owner803 pases/0 fallos/28 excluidos, consumidor mínimo/extensible186/0/0 y
  SQL opt-in15/0/0 sin iniciar Repo, grafos fijos copiados. No SQLreal/G5 limpio.
- Registro durable `docs/archive/2026-09-26-r4-integration.md`.
- Recepción documental posterior sólo cinco paths, sin mutar los artefactos aceptados.

### R5 raíz corregida aceptada PARCIAL offline

- Source291 `/tmp/opencode/exagent-r5-p2-source.tar.gz`:
  `f8b542f6f78d6d4fb59e0ac6945c658904badf14339f30b45c816b39b15cea1a`.
- Manifest `/tmp/opencode/exagent-r5-p2-manifest.json`:
  `b62f73c5383bb0463423cc098c566de76146934dce8c1c8431f352c5fc4c9453`.
- Diff `/tmp/opencode/exagent-r5-p2-from-root6a65.diff`:
  `7468738c00c9c919e405a6b0e6128c67c513225a2f95b932d5f0cf16119bc7e0`.
- Review `/tmp/opencode/exagent-r5-review/fixf8b5/REVIEW.md`: compile85,
  **10 probes previos byte-idénticos**, native recovery ACTIVO, focal35,
  adyacentes27, identidad291/291, todo exit0. Cuatro P2 cerrados.
- Owner compile85, suite850/0/28 seed37556, formato/links234-55 exit0.
  No TAR/consumer nuevo por estos checkpoints intermedios; distribución R5 pendiente.
- Coordinador comprobó SHA/291 fuentes raíz+manifest y diffcheck0.
- Aceptación parcial `msg_90820eaf8d7d`; recepción posterior sólo roadmap/handoff/
  root-progress:288 fuentes restantes intactas; links235/55/plan57/diffcheck0.
  `/tmp/opencode/exagent-r5-receipt-identity.json` separa esa prosa posterior.
- Registro durable `docs/archive/2026-09-26-r5-root-progress.md`.

El rojo previo queda en `/tmp/opencode/exagent-r5-review/root6a65/REVIEW.md` sobre
source6a65. Checkpoint administrativo anterior source5b43 y review padre son evidencia
histórica. No volver a implementarlos ni atribuir sus cifras al checkout WIP actual.
`/tmp` no es durable: comprobar presencia/hashes, no inventar evidencia si desaparece.

## 6. Contratos cerrados a preservar

### Foundation R1–R4

- Sobre wire obligatorio `{"arguments": objeto_lógico}`; envelope1/continuation2.
  Validación local sobre/schema/args efectivos antes de efectos. Hooks/DI/aprobación
  reciben args lógicos. before_tool no cambia ID/nombre/kind/metadata; after_model
  sigue transformación confiable preadmisión. Sin repair/defaults/fallback wire.
- ReqLLM stock perfil explícito chat_tools_v1; stream una vista process_stream,
  callbacks+respuesta final, lazy host, terminal válido antes de effects, guardian/
  ACK/close/reap. Límites postdecode64KiB/chunk,1MiB/4096chunks; no hard RAM upstream.
- Pérdidas upstream aceptadas: siblings malformed borrados sin señal; refusal junto
  a JSON válido puede perderse y el contenido resultar válido. Se valida todo lo
  semántico expuesto; no parser privado ni promesa raw.
- Native explícito, default Ecto :tool; output_profile chat_json_schema_v1;
  schema preparado tras hooks antes de request, Ecto autoridad final, retries contados.
- Host counters = admisiones/reservas exactas, no factura/efectos confirmados.
  Usage.accounting1 allowlisted califica normalized/reported/estimated y disponibilidad;
  no cero→unknown ni normalized presentado observado. Restore no repricing/doble suma.
- Namespace confiable `{namespace,kind,id}`, RuntimeIdentity exagent.scope.v1:
  +base64url JSON; Store.scoped descriptor único, key/payload exactos, sin atomización.
- Retención R3: P default1MiB/H8MiB,1..64MiB EFT postdecode. Reserva de todo batch
  preIO; oversized después de efecto conserva status/IDs/uso, nil+omisión explícita
  y terminal sin retry. Snapshot4 lee1/2/3; omitted-v1/Usage marker preservados.
  Historia omitida ceroModel/toolIO; errores/Usage4096B y cota ordinary2H+P+64KiB.
- Store R4 misma fila snapshot o record1, CAS/record lifetime/owner/attempt/fence;
  receipts ligados operación/actor/payload/revisión. Receipt viejo nunca permiso IO.
  ETS efímero gestionado; raw tid snapshots-only. Postgres opcional, DDL app-owned,
  SQL protocol tests no G3. Legacy rechaza envelopes, list los omite.
- JSONrecord8MiB,256effects/1024receipts; reserva cleanup por encoded bytes/IDs
  escapados/counter growth, no4224 fijo. Scan/prune acotados, no activos/uncertain,
  borrado exige quiescencia y no deduplicación eterna tras eliminar receipts.

### Raíz C7 parcial aceptada (ADR8.34)

- Run→paused→decide→resume root con mismo run_id/nuevo attempt; paused sólo tras
  persistencia confirmada+quiescencia, writer efímero liberado durante espera.
- Actores/plantillas/deps/codecs/modelos son host confiable, no resolubles desde
  módulos/credenciales persistidos. Model.validate_resume preIO requerido sólo C7.
- Approval1 liga call/args efectivos/schema/refs/digest JSON canónico: **1≠1.0**.
  Decisión exacta idempotente; opuesta/actor/payload/revisión distinta rechaza.
- Frames/cursor/historia/batch/model journal y outcomes tienen coherencia bidireccional.
  No aceptar outcome succeeded huérfano ni cursor que salte pendiente al restaurar.
- Native fingerprint portable excluye módulo Ecto; validator se reconstruye antes
  de consumir respuesta restaurada. Ecto-tool/native/retries siguen funcionando.
- Reservas históricas se revalidan contra límites actuales/ancestros sin segundo
  débito. Ledger restaura por identidad, sin repricing/dobleuso ni reset presupuestos.
- UTC deadline/expiry transcurren espera humana; expiry nil válida. Tiempo activo
  no consume espera y se debita conservador antesIO: crash no devuelve saldo gratis.
- Nuevo payload C7: J=max_checkpoint_bytes, token COMPLETO EFT1..8MiB default8MiB,
  dentro measurement/data_bytes; **cota C7 2H+P+J+65536**, ordinary intacta.
  JSON Store8MiB+reserva separado de EFTrecordR. Copias/concurrencia/nodos parametrizados,
  sin hard RAM universal. Dirty token exacto data-only, Store separado, retry sólo IO
  de persistencia; sin gigantes en reason4096/eventos ni replay de efecto.
- resolve_call sólo confirma resolución predispatch conocida, no overwrite de intent
  running/confirmed ni fabricated succeeded/failed. finalize_call sólo rawconfirmed→final,
  fase explícita incluso si hashes coinciden, conserva intent/status/raw_hash,
  journal+frame atómicos; segundo finalize nuevo rechaza, receipt exacto sí.
  Crash tras raw ACK usa raw confirmado sin repetir callable/afterhook.
- Pérdida de fence entre ACK y API externa sigue incierta; no exactly-once/rollback.
- Batch root/hermano confirmado, dos resumers, nueva VM desde fixture disco, dirty
  before/aftercommit y model stateful host codec ejercitados. Fixture disco no G3.
- Server WIP revisado sólo dos escenarios: pause/queue/uso y restore sinIO. No cierre
  global de Server; árbol, Session y resto recuperación continúan pendientes.

## 7. WIP del owner actual y decisiones pendientes

Leer su **checkpoint final de pausa** `docs/archive/2026-09-26-r5-tree-progress.md`
antes de actuar: contiene el inventario real y último gate, no extrapolar suite850
a este delta. Últimos gates actuales: Scope4/4, combinado Server+Scope7/7 y Server5/5
seed37556 exit0; no fullsuite/compileforce/formato/ExDoc/review del delta actual.
Todos los cinco runners síncronos terminaron. Otros cinco beam.smp se inventariaron
por PID/PPID sin atribuirlos a esta Task ni tocarlos; no cerrar procesos ajenos.

Dirección transversal ya aprobada en `msg_30668898edb2`:

- Mismo progress.runtime con frames por nodo, padre/call/descriptor y ledger de
  árbol único por operación. Frame2/Scope2 deben hacer rechazar árbol a lectores
  root-only antiguos; migración root1 explícita, sin tocar messagecontinuation2.
- Descriptor host durable opt-in para delegation_tool con builder/refs/codec; no
  persistir callable ni repetir callable padre al rehidratar. Delegación es cursor
  compuesto, no external effect running ficticio que impida pausar.
- Validar árbol completo, IDs/padres sin ciclos/huérfanos, autoridad original
  intersectada con actual de TODOS ancestros, costes/contadores una vez.
- Reserva de TODO árbol/slots/nodos/receipts/J/JSON antesIO. Rootpaused sólo sin IO
  propio pendiente; incertidumbre/dirty precede pausa.
- Session no finge transacción entre filas; debe reconciliar refs con autoridad Store.
- Retry explícito conserva intent incierto original y nuevo intento enlazado,
  idempotency key host disponible al callable. La key sola no garantiza deduplicación.
  Reconcile Model valida respuesta+estado portable+profile/output antes siguiente IO.

Avances reportados antes de la pausa (contrastar con checkpoint):

1. Scope2 export/import árbol confiable y cuatro focales verdes; guard root-only
   todavía no se levanta, no árbol C7 público completo.
2. Descriptor de delegación en construcción; primer compile chocó Kernel.binding/1,
   renombrado descriptor_data. No esconder el rojo ni atribuir aceptación funcional.
3. Oráculo Server terminal→reset→restart falló atomic_record_required por usar
   RuntimeCheckpoint legacy sobre envelope. Comando CAS `reset_snapshot` conserva
   ejecución/effects/receipts y sólo cambia snapshot conversacional. Se autorizó
   terminal elegible, revisiones/fence/lifetime monotónicos y negativos activos/
   pending/uncertain/dirty, retry exacto ACK perdido sin Model/toolIO.
4. `r53-server-reset-focal-02` verifica Server5/5: dos previos y tres nuevos con
   reset/restart/nextRun, before/afterACK y negativos pending/ready/claimed/uncertain/
   dirty. Falta probar nuevos receipts/JSON/J/cardinalidad1024/8MiB y review integrada.
   El descriptor/export_node sólo están compilados por focales; no habilitan árbol.

### Decisión técnica todavía SIN resolver

Ask original `msg_4a05a0ba3641` fue contestado **sólo para desbloquear la pausa**
mediante `msg_e24e5914a77a`; no aprobación/rechazo técnico. Nuevo coordinador debe
resolver con owner tras ownership (puede pedir un ask nuevo; no fingir que el viejo
permite una segunda respuesta contradictoria):

**A. Session:** hoy take_turn(change) es genérico; `{:ok,map}` se convierte en
shared_state y advance; Participant.ref no supone Server. Propuesta pendiente:
binding host opt-in `continuations: %{participant_id => %{store: scoped_store,
id: agent_id}}`, Store no persistido; ref pending pequeña/versionada en Session
snapshot con bump para lectores viejos, consulta autoritativa antes de advance/
restore incluso si ref local falta por crash entre filas. Session.pause independiente.

**B. Terminal deny/cancel:** snapshot puede conservar batch abierto. Propuesta
pendiente del owner: Server mantiene cola bloqueada hasta reset explícito del
terminal, preservando journal, en lugar de drenar historia inválida. Alternativa
por decidir: cierre explícito y veraz del batch cancelado que permita drenar.
No estabilizar como contrato ya aprobado. Revisa estados conocidos not_executed/
denied frente a efectos inciertos; no inventar outcomes ni borrar evidence.

## 8. Entorno y verificaciones

- Rama main, HEAD `7f25b336924d97baf1d4aa18898ec8db32385940`.
- ReqLLM1.24.0, Req0.7.4, Finch0.22, Mint1.10.1; lock SHA256
  `c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b`.
- Mínimo Elixir1.18 por llm_db; toolchain principal Elixir1.20.0/OTP29.0.5.
- Leer `docs/development/environment.md` ANTES de Mix. No reparar Hex global.
- Runners existentes: `/tmp/opencode/exagent-r4-integration-run.py` (usado R5,
  paths raíz explícitos, HEX_OFFLINE1, +S8), `/tmp/opencode/exagent-r11-run.py`.
  Leer antes de usar, etiquetas nuevas, no sobrescribir logs. Logs en exagent-r11.
- Prefijo existente (comprobar paths; /tmp no durable):

```bash
env -u MIX_EXS -u MIX_PATH -u MIX_INSTALL_RESTORE_PROJECT_DIR \
  PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin \
  MIX_HOME=/tmp/opencode/exagent-release-tooling \
  MIX_ARCHIVES=/tmp/opencode/exagent-release-tooling/native-archives \
  HEX_HOME=/tmp/opencode/exagent-release-tooling/hex \
  REBAR_CACHE_DIR=/tmp/opencode/exagent-release-tooling/rebar \
  EXAGENT_OFFLINE=1 MIX_ENV=test \
  mix test --warnings-as-errors --seed 37556
```

Los runners allowlisted evitan heredar credenciales y añaden config de pruebas
necesaria. Fixtures width5 existentes requieren +S8; fallos +S4 históricos son
seguimiento R8, no fix Scope ni portabilidad aceptada bajo cinco schedulers.

Gates al cerrar runtime: focales discriminantes, compileforce, suiteoffline,
formato, snippets/ExDoc/links/plan pertinentes; artefacto exacto+consumer cuando
corresponda integración/distribución. No ciclo completo TAR por cada párrafo o
subpaso intermedio. Preservar rojos y controles positivos. Excluidos no son pases.
Consumidor con grafo fijo copiado no es resolución limpia G5 ni CI remota.

## 9. Siguiente secuencia y criterio de continuidad

1. Recuperar mismo Run/flota/correo y confirmar pausa/ownership real.
2. Leer checkpoint owner, inventario y cambios posteriores a f8b5, sin reset/reimport.
3. Reanudar MISMA Task `task_ec3210551bcd` Astra low; resolver Session/terminales
   pendientes y continuar árbol/Server/Session/uncertainty conforme propuesta aprobada.
4. Gates por unidad; congelar fuentes para reviewer MISMA Task al cerrar frontera útil.
   Copias/builds propios, no compilar raíz mientras owner edita.
5. Sólo cerrar R5/C7 tras implementación+evidencia+review integradas. Nuevo TAR y
   consumidores afectados pendientes. Luego R6–R9 ejecutables según roadmap.
6. Gates G2/G3/G4/G5limpio/CI/G6 externo/publicación necesitan autorización/alcance;
   bloquear sólo esa unidad y seguir lo independiente. No convertirlo en éxito.

Lecturas enfocadas: AGENTS → cabecera ORCA_CHECKPOINT → checkpoint pausa owner →
handoff/roadmap§5 → ADR8.34 y 8.32/33 → release-scope/acceptance/environment → reviews
exactas citadas. Los archivos históricos conservan evidencia, no mandatos activos.

No te detengas por la transferencia ni termines tras lanzar workers: la continuidad
autorizada es implementar y supervisar con **Astra low** hasta resultado verificable,
bloqueo real o nueva pausa expresa del usuario.
