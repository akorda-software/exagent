# R5 continuación del relevo: checkpoint de transferencia, no aceptación

## Cierre owner de gates y distribución local — 2026-09-27

Después de a371, por orden expresa del coordinador, se completaron los gates de
VM árbol, Server/Session/cola/eventos/native, dos Models hijos inciertos y fronteras/
fallos exactos. No cambió producción: sólo pruebas/fixtures/documentación.
Compile92/suite921/0/28 seed37556 exit0; candidato TAR115 y consumidores6/106/30/12
exit0,117 módulos por perfil con procedencia de paquete. Matriz, detalles/rojos y
límites en `docs/archive/2026-09-27-c7-owner-matrix.md`; manifest final fija fuente,
TAR y delta documental. Reviewer bloqueado, no aceptación C7 ni gates externos.
Misma Task mantiene ownership hasta instrucción explícita; no comenzar R6.

## R55 segundo checkpoint: árbol corregido y recuperación inicial — 2026-09-27

Misma Task/Dispatch y ownership; no worker_done/cesión por este documento. Coordinador
pidió checkpoint tras vertical retry para decidir siguiente bloque, sin esperar una
review actualmente bloqueada por proveedor. No hubo intento de cambiar reviewer,
modelo/config ni canal para eludir ese bloqueo. No aceptación C7 independiente.

### P2 independiente reproducido y corregido

Fuente inicial árbol299 df6131 y manifest3b0aa0, ya congelados antes de este delta:
`/tmp/opencode/exagent-r55-tree-initial-{source.tar.gz,manifest.json}`. Reviewer
demostró replay de Model hijo al borrar nodo+ledger coherente conservando journal y
approval. Probe exacto sólo leído/ejecutado desde su copia privada:
`/tmp/opencode/exagent-r5-review/treedf6131/tree_review_probes_test.exs`, SHA256
`3cbfbc9d9d9906b667b310d7c27c743c94dddfef4ac58fe22490bf5c0d8919dc` antes/después.

Owner `r55-review-orphan-red-01`:3/4 exit2, mismo replay; `r55-review-orphan-green-01`:
47/47 exit0, incluye los4 probes intactos y nueva regresión permanente. Validación
inversa de todos los journals/approvals hacia run/nodo/request/ledger; contexto
virtual interno de hijo no se obtiene de una bandera JSON. Reejecución final tras
recuperación `r55-recovery-review-probes-01`:4/4 exit0. Es evidencia owner, no dictamen
del reviewer bloqueado ni aceptación del resto de los cambios.

### Recuperación implementada en este bloque

- `reconcile_model/5`: respuesta efectiva pos-hook + estado portable host y perfil/
  output validados, sin Model/after-hook replay; contabilidad por identidad y coste
  original no observado conservado unknown, sin reprice.
- Semántica retry confirmada expresamente por coordinador: riesgo de duplicación
  aceptado por host, original literalmente incierto, nuevo intento enlazado que
  gobierna el cursor. Binding/actor/revisión/key se contrastan con receipt exacto;
  no receipt viejo ni lease autorizan IO. Resultado/query/eventos exponen riesgo.
- Key real en RunContext/ModelRequestParameters y header público stock ReqLLM Chat;
  buffered/stream por TCP sintético observan entrega, no deduplicación externa.
  Perfiles no cualificados/caracteres de control rechazan preIO; no parser/fork.
- Frame/contador/intent Model se guardan atómicamente mediante begin_effect
  extendido; input efectivo portable queda medido dentro del journal/J/JSON y se
  restaura sin before-model. La duplicación de historia puede agotar la cota antes;
  no expulsar evidencia para admitir más trabajo. Lectura/migración root1 conservada.
- Retry Tool reserva un sub-batch nuevo, no repite el antiguo. Scope2 añade
  retry_batches y contribuciones por intento; Usage previa desconocida no se
  transforma en cero ni se repricia. Límites de todos los ancestros, activo y UTC
  siguen vinculantes. Cadenas/IDs/slots/receipts permanecen acotados.
- Start/prune no olvidan incertidumbre histórica sin `acknowledge_history/3`
  explícito, hash exacto y autorización de eliminación futura. Ese ACK no equivale
  a reconciliar el efecto ni borra inmediatamente.

### Gates posteriores a la fuente inicial

Mismo runner/allowlist/tooling/offline/+S8:8/seed37556; sin instalaciones o resolución.

| Label | Resultado |
|---|---|
| r55-model-recovery-01 |2/2 exit0, muerte tras efecto y estado portable ausente después de hook, negativos de actor/revisión/refs/codec/profile/accounting. |
| r55-retry-compile-01 |Compile incremental13, exit0. |
| r55-retry-adjacent-01 |49/49 exit0, árbol/raíz/Scope/resolution/Model recovery. |
| r55-retry-vertical-01 |2/2 exit0, Tool/Model key/counters/evidencia original y no replay de input/hook. |
| r55-retry-transport-01 |2/2 exit0, header buffered/stream stock real por TCP y rechazo pretransporte. |
| r55-retry-negatives-01 |7/7 exit0, competencia CAS, actor/stale/key/hash, args1≠1.0, budget y segunda muerte en cadena. |
| r55-retry-receipt-binding-01 |7/7 exit0 con enlace anclado a receipt de autorización. |
| r55-retry-time-integrity-01 |exit1, bloque de test insertado dentro de Task antes de variable authorized; error propio de edición, corregido sin cambiar runtime/aserciones. |
| r55-retry-time-integrity-02 |11/11 exit0, además corrupción de enlace, presupuesto activo no reiniciado y expiry tras autorización. |
| r55-recovery-compileforce-01 |**91 fuentes, exit0**,2.161s. |
| r55-recovery-suite-01 |**908 pasados/0 fallos/28 excluidos, exit0**,162.1s ExUnit/162.874s runner. |
| r55-recovery-review-probes-01 |4/4 exactos intactos, exit0 sobre runtime actual. |
| r55-recovery-snippets-01 |9/9 exit0, seed0; snippets mantenidos sobre BEAM test actuales. |
| r55-recovery-exdoc-01 |exit0, salida `/tmp/opencode/exagent-r55-docs`; compilación dev incremental14+2. |
| r55-recovery-format-01 |Formato exit0; git diff --check exit0. |

Checker de enlaces `/tmp/opencode/exagent-r55-links.json`:147 destinos relativos
en21 Markdown, cero ausentes; no consulta remotos/anchors sólo-fragmento. Checker
de plan existente:57 IDs únicos, A1–A10 y G1–G6 conservados, exit0. Esta nota añade
evidencia documental posterior a esos gates; no cambia runtime ni exige repetir
suite. El manifest del checkpoint registra las identidades y los logs completos.

Warnings upstream/fixtures y errores esperados de inyección de fallos quedan en los
logs. Fixture OTLP de task337bf intacta; su incidente no se reabre. No exclusiones
nuevas, assertions debilitadas, commits/version/deps/consumidores reales o servicios.

### Pendiente, sin rebajar alcance C7

Nueva VM con árbol completo desde fixture disco; composición pública adicional
árbol+Server/Session/queues/eventos; cotas exactas token J/JSON/receipts y ventanas
de fallos para todas las transiciones nuevas; más recuperación/retry en nodos y
perfiles tipados. Gates documentales/checkpoint se registran al acabar esta unidad.
Distribución TAR/consumidores de grafo fijo y revisión integral permanecen abiertas,
además de gates externos G2/G3/G4/G5 limpio. Estos pendientes no son nuevas
exclusiones del producto. Source de este checkpoint y dictamen siguiente se coordina
por CLI; owner conserva ROOT hasta instrucción expresa de cesión.

## R55 árbol integrado inicial — 2026-09-27, review pendiente

Owner exclusivo ROOT/docs/builds: task_b368f714cfd3/ctx_4950569ad27e; Astra LOW
verificado en TUI por coordinador antes de investigación/build y ownership concedido.
Misma Task continúa por instrucción expresa tras primer paso frame2/root; no cesión.
ORCA_CHECKPOINT y prompt de orquestación siguen exclusivos del coordinador.

### Cambio integrado

Frame2/scope2 en escritor público; lector root1 con fixture **real**
`test/fixtures/continuation-root1-f394.json`, emitida en VM efímera usando sólo los
Frame/Writer exactos del TAR aceptado f394 (hash verificado), sin reemplazar fuente
o BEAM del checkout. Generador `/tmp/opencode/exagent-r55-root1-fixture.exs`; warnings
de redefinición esperados en esa VM de generación, no silenciados. No downcast falso.

`children` mantiene frame/historia/configrefs/result/journal por run_id. Descriptor
host resuelve/reconstruye hijo; callable padre no se ejecuta. Writer único serializa
admisiones de Model/batches y transiciones de nodos. `node_checkpoint` deja avanzar
un hijo mientras otro hermano mantiene efecto en vuelo, sin relajar checkpoint/
pause/finish raíz. `delegation_outcome` liga raw/final del resultado hijo al padre,
sin intent externo de delegación inventado. Snapshot raíz y cuerpos/hashes de
Response/ToolReturn parentales se conservan y miden en la fila/token.

Restore valida grafo, ledger, snapshots, posición y vínculos antes de IO; reconstruye
Scopes confiables y aplica restricciones originales/actuales por ancestro, sin
repricing o segunda reserva. Reconcile tool usa el run_id de su intent, no siempre
el frame raíz. Resultados de hijo no representables tienen omisión bloqueante;
reservas incluyen copias/Model/tools en vuelo, mínimos delegados, nodos y receipts.
Deadline hijo guarda sólo UTC explícito, no lease/saldo efímero heredados.

### Evidencia incremental y rojos conservados

Runner existente `/tmp/opencode/exagent-r4-integration-run.py`; logs y metadata
`/tmp/opencode/exagent-r11/<label>.{log,json}`, allowlist, offline ambos flags,
Elixir1.20/OTP29 y +S8:8; seed37556. ReqLLM stock/lock/nominal sin cambios.

| Label | Resultado / alcance |
|---|---|
| r55-frame2-focal-01 |37/37, exit0; writer/restore Scope2 inicial raíz. |
| r55-root1-fixture-01 |Genera7349 bytes root1 del escritor aceptado, exit0; warnings de redefinición aislada explicados arriba. |
| r55-frame2-focal-02 |39/39, exit0; lector real, upgrade, corrupción/downcast antes de codec host. |
| r55-tree-compile-01 |Compile incremental5, exit0. |
| r55-tree-vertical-01 |0/1 exit2: checkpoint de hijo rechazado con hermano running; guard raíz correcto. |
| r55-tree-vertical-02 |1/1 exit0 tras node_checkpoint/delegation_outcome acotados. Hijo pending+hermano confirmado, pause quiescente y resume sin callable padre/replay/doble admisión. |
| r55-tree-root-regression-01 |40/40 exit0, árbol+raíz/Scope/resolution. |
| r55-tree-hardening-01 |36/36 exit0 tras reservas, bindings y copias/omisión. |
| r55-tree-depth-01 |exit1, error sintáctico propio de inserción en helper del test; corregido sin tocar runtime. |
| r55-tree-depth-02 |1/2 exit2, fixture esperaba5 callbacks de precio pero el hijo derecho heredaba el estimador y lo invocaba además para su propio subtotal. |
| r55-tree-depth-03 |2/2 exit0: precio derecho explícito5, medio7 y raíz2→11; subtotal raíz10→43 sin repricing. Colisión de call IDs entre nodos y profundidad2. |
| r55-tree-negatives-01 |5/5 exit0; budgets raíz/intermedio, deadline actual, corrupción de grafo/journal/cursor/outcomes, espera más allá del lease y PIDs hijos muertos. |
| r55-tree-ownership-01 |7/7 exit0; dos resumers y muerte root/writer/scope/leaf, recover y reconcile de efecto en su nodo sin repetirlo. |
| r55-tree-runtime-focal-01 |**81/81 exit0**, raíz/Scope/resolution/árbol/Server/Session;49.1s. |

Warnings Req de adapter fixture y avisos operacionales checkpoint_failed en tests
de fallo conservados; no regresión de compilación ni exclusiones nuevas.

### Frontera de esta fuente para revisión paralela

Implementación inicial de árbol, **no aceptación R5/C7**. Misma review task_0ee986f3992e
reservada; coordinador entrega freeze, owner no despierta reviewer directamente.
Continúan Model uncertainty/reconcile/retry explícito con idempotencia entregada,
cotas exactas y fallos compuestos adicionales, nueva VM de árbol, composición de
árbol con Server/Session, gates integrados/distribución y revisión final. Evidencia
de raíz/Server/Session anterior se reutiliza sólo en sus fronteras no afectadas;
focal81 no se presenta como fullsuite, SQL/G3 ni consumidores/G5 limpio.

## Recepción posterior al freeze: aceptación parcial y cesión — 2026-09-27

Esta sección es prosa posterior, no parte de sourcef394 revisada. Coordinador
`msg_95f14728b813` acepta unidad PARCIAL Server/Session offline, autoriza cierre
parcial task_ec3210551bcd y cesión ROOT/docs/builds al worker_done, sin procesos
propios activos. No acepta C7 árbol/completo ni distribución. Nuevo owner fresco
continúa los8 pasos ejecutables de abajo; misma review C7 sigue abierta.

Dictamen leído: `/tmp/opencode/exagent-r5-review/correctedf394/REVIEW.md`.
P2 Session5628 cerrado sobre probe exacto, sin nuevos P1/P2 concretos; verificación
independiente compile88, Session/reset exactos3, focal36+3 no seleccionados,
witness1, adyacentes49 e identidad297/297, todos exit0. Fixture OTLP integrada
revisada y lifecycle fresco pasa; full887/0/28/docs siguen evidencia owner.

Artefactos inmutables:

- Source297: `/tmp/opencode/exagent-r54-corrected-source.tar.gz`, SHA256
  `f394ad9964d80ad3a4b76a82f79b9eaa5c6daf27732dae41a3fc9403aa6d8048`.
- Manifest: `/tmp/opencode/exagent-r54-corrected-manifest.json`, SHA256
  `6499ccf3c6108f7dffdf7f0b4b2fe3ee812f83a6e464d6889676c9590482d378`.
- Delta5628: `/tmp/opencode/exagent-r54-from-5628.diff`, SHA256
  `f9c2e44950fc0e715b7641f305aec370afca5c987f33023973abe57611c8d136`.
- Deltaf8b5: `/tmp/opencode/exagent-r54-from-f8b5.diff`, SHA256
  `f6dcaa09027774246b5d71f1ebaa4ce0e2e6d52338fb2ad0d4d95fa45257bd92`.

Sólo roadmap/handoff/este registro reciben esta nota. Identidad de los otros294
archivos y enlaces/diffcheck se comprueban sin nuevos builds/suite/TAR; no atribuir
revisión de esta recepción documental al freeze anterior.

## Frontera corregida R54: cierre parcial pendiente de review/cesión

**Integración autorizada posterior — 2026-09-27:** `msg_abd2ce8eb68d` autoriza
exclusivamente la fixture OTLP de task_337bf480683b, no producción. Informe
`/tmp/opencode/exagent-otlp-diagnosis/DIAGNOSIS.md`, SHA256
`a36fbe36a3c2efd47e87f92b06bccd4614cee4865f1678720bd74c79dee48f5f`;
patch `fixture.apply_patch`, SHA256
`aa363eaea3906b184b12955fbbdfec39680de2fc62fe15030fa63f88001a782f`.
Owner verificó hashes y aplicó sólo ese delta mediante apply_patch; fixture final
`test/support/native_otlp_probe.exs`, SHA256
`23d63a8690ba53a884c04cfa188ae6d675298c3d77474120dc8cb4414e515a71`.
Autoría/diagnóstico son de esa Task independiente; integración ROOT de ésta.

La barrera adversarial de la copia privada reprodujo lectura diagnóstica partida:
ETS-size1 anterior combinado con timeout1/ready posterior aunque ETS real ya era0.
El monitor DOWN del worker no certifica que el processor haya procesado su propio
DOWN. La fixture ahora espera el predicado original, sincroniza con
`:sys.get_state(processor)` y toma stats frescas; mismas aserciones,250ms y3ciclos.
No fuga reproducida ni reconstrucción demostrada del scheduling histórico; no
se modifica la semántica/contabilidad del processor. Evidencia independiente:
pristine297/297, rojo causal1, fixed-adversarial3ciclos, native4/4 y formato exit0.
Nueva **suite integrada r54-otlp-integrated-suite-01:887/0/28, exit0,134.397s**,
única ejecución pertinente tras incorporar fixture. El rojo anterior se conserva.

Coordinador autorizó cerrar esta Task **parcialmente** después de gates, freeze
corregido y revalidación independiente favorable. Después habrá nuevo owner Astra
LOW fresco para árbol/Model uncertainty/resto C7, sin repetir R0–R4 ni otra propuesta
general. ROOT/docs/builds siguen aquí hasta confirmación explícita; no worker_done
ni cesión automática por este documento. La misma review C7 permanece abierta.

### Cambios posteriores a source5628

- **P2 independiente Session:** probe exacto
  `/tmp/opencode/exagent-r5-review/server-session5628/session_review_probes_test.exs`,
  SHA256 `cec4a245d573c0f3ba115a665c22ecb844a25dedab572e3f7318ab5933ddcb65`.
  Repro owner1/2: error nuevo tras consumir runA desaparecía al consultar terminalA.
  Refresh ahora conserva diagnósticos locales y su identidad; sólo limpia
  indisponibilidad transitoria cuando no reemplaza error conocido.
- **Reconcile local aprobado:** Session.reconcile_turn/3 reconoce witness≤8192 EFT
  con diagnostic_id nuevo, Session/revisión y Store exactos. No callback, avance ni
  modificación shared_state/consumed. Pending/uncertain/dirty/missing/identidad
  cambiada no se liberan. Persistencia de diagnóstico, staleA contraB, restart y ACK
  perdido ejercitados. El prototipo3 sin error se normaliza; error antiguo sin ID
  falla cerrado. No es reconciliación de efectos externos.
- **Abort Server:** linked Writer y registro ACK efímero antes de dispatch Store;
  Server detiene root y writer registrado. Tres rojos iniciales (pending sin
  cancelar, efecto quedaba claimed, writer bloqueado sobrevivía) se corrigieron;
  luego dos rojos reales de commit externo tardío demostraron que eso no bastaba.
  `create_cancelled` absent crea frame terminal abort_version1 no ejecutable;
  `fence_admission` sobre terminal previo conserva snapshot/efectos/lifetime y
  aumenta revisión con una identidad acotada de admisión abortada. Comandos tardíos
  mantienen expected/lifetime inmutables y no atraviesan la barrera.
- **Ventanas verificadas:** Store externo test-only confirma después de barrera y
  orden inverso con ACK retenido; create/start, ambos fallos ACK de barrera, restart/
  nuevo run, muerte abrupta Server, stream con writer anidado, efecto incierto sin
  replay. J completo se rechaza antesStore; JSON8MiB exacto/+1 y receipts1024/replay
  tienen oráculos reducer sobre datos controlados, separados de los tests públicos.
  Abort frame no admite claim/resume; no prueba SQL G3.
- **Dirty con carrera perdida:** retry exacto puede devolver record_mismatch si
  la admisión antigua ganó después de fallo de barrera. Server queda dirty/blocked,
  no cambia comando ni drena. Se prueba inspección, cancelación host explícita
  ligada al run objetivo y recarga del Server; no replay de cola volátil.
- **Leave causal final:** leave de participante ligado consumido devolvía :ok y
  dejaba checkpoint imposible de restaurar. Se reprodujo público y en regresión
  permanente9/10. Decisión aprobada: continuation_binding_retained mientras existe
  fila; detach roster+binding sólo con ausencia confirmada y sin pending/error.
  Leave nunca borra Store. Prueba negativa, consumed intacto, borrado terminal host,
  detach y restore posterior pasan. Ordinary leave conserva regresiones.

### Gates y rojos R54

Mismo runner allowlist, Elixir1.20/OTP29, +S8:8, offline, seed37556 salvo snippets0.
Todos los logs/argv/exits viven en `/tmp/opencode/exagent-r11/<label>.{log,json}`.

| Label | Evidencia |
|---|---|
| r54-server-abort-red-01 |9/12; tres fallos causales abort descritos arriba. |
| r54-server-abort-green-01 |Root+Server39/39, exit0; aún no cubría commit tardío. |
| r54-session-review-red-01 |Probe independiente exacto1/2, exit2. |
| r54-session-review-green-01 |3/9; bug nuevo propio en witness usando and con nil/string, BadBooleanError. Corregido con booleanos explícitos, sin ocultar rojo. |
| r54-session-review-green-02 |9/9, incluye ambos probes exactos intactos, exit0. |
| r54-session-reconcile-focal-01 |11/11, exactos+permanentes/witness/ACK, exit0. |
| r54-abort-deferred-red-01 |12/14; create y start externos confirmaban después de abort. |
| r54-abort-deferred-green-01 |50/50 root/Server/Session, exit0. |
| r54-abort-orders-focal-01 |17/17 Server, exit0, ambos órdenes y muerte Server. |
| r54-abort-ack-focal-01 |21 tests pasan pero exit1 por warning1.20 en comparación de constante generada; se precalculó atributo de fixture, sin silenciar warnings. |
| r54-runtime-session-focal-01 |60/60 con root y probe independiente, exit0. |
| r54-barrier-caps-focal-01 |24/24 Server, exit0. |
| r54-dirty-barrier-focal-01 |25/25 Server, exit0. |
| r54-session-leave-red-01 |Probe público0/1, restore_failed tras leave :ok; además warning de nombre de archivo temporal no terminado en _test.exs. |
| r54-session-leave-permanent-red-01 |9/10; leave :ok incumplía negativa de contrato aprobada. |
| r54-session-leave-green-01 |51/51, incluye todas las suites Session y probe independiente, exit0. |
| r54-corrected-compileforce-01 |88 fuentes forzadas, exit0. |
| r54-corrected-suite-01 |**887/0/28**, exit0,134.56s. Primera suite del nuevo runtime corregido; no borra la anterior867/868. |
| r54-doc-snippets-01 |Snippets9/9, exit0. |
| r54-exdoc-01 |exit1: enlaces a archivos checkout-only y propuestaR5 fuera de extras. |
| r54-exdoc-02 |exit0: archivos archivados como rutas sólo checkout y propuestaR5 registrada en extras. |
| r54-format-01 |Formato exit0; git diff --check exit0. |

Checker de links mantenidos: `/tmp/opencode/exagent-r54-links.json`,147 targets
relativos en21 Markdown, cero ausentes. No consulta URLs externas ni pretende
validar anchors sólo-fragmento. ExDoc final posterior a esta prosa queda identificado
en el manifest corregido. Runtime no cambió después de suite887; los cambios de
Mix/propuesta/handoff posteriores son registro ExDoc y documentación.

Mix sólo cambia por registro ExDoc de r5-implementation; nominal/deps/lock intactos.
La propuesta corrige aridades documentales reconcile/5 y retry_checkpoint/2. No
instalación/resolución nueva. Los últimos checks documentales/formato y la identidad
de fuente corregida quedan en su manifest; no paquete Hex/TAR consumidor por esta
frontera parcial autorizada. La integración fixture/diagnóstico causal posterior
está registrada en la cabecera, sin atribuirla a los verdes anteriores ni afirmar
reconstrucción exacta del fallo histórico.

### Relevo ejecutable pendiente (sin nueva auditoría general)

1. Reutilizar aprobación de dirección tree en diseño8.34/r5-implementation: mismo
   loop, writer efímero único, fila CAS; frame2/scope2 explícitos y reader root1
   validado por consumidor existente. No alterar Snapshot4/omitted-v1/accounting1/
   message continuation2/envelope1. Contexto fresco empieza **integración**, no R0.
2. `Coordination.delegation_tool` ya guarda `%Continuation.Delegation{}` host en
   Tool.delegation; config refs/codec, builder, prompt_arg y restricciones existen.
   descriptor_data/1 proyecta sólo datos para fingerprint; resolve/3 es preparatorio
   y todavía no usado. `ExAgent.run_child` sigue con guard descriptor-required;
   no retirarlo hasta el vertical público hijo ask+hermano completado sin replay.
3. `Frame.capture/restore` y `Writer` aún asumen `progress.runtime` raíz única.
   Extender por nodo con padres/call/request IDs, historia/cursor/model data,
   refs/selected inventory, outcomes y journal compuesto de delegación (no inventar
   efecto externo). Usar loop actual `execute_scoped`, `run_tool_raw`,
   `execute_effective_call`, `pause_run`, `succeed`; no reinvocar callable padre.
4. `ExecutionScope.export_tree/restore_tree` y ScopeLedger2 ya conservan Usage
   por ancestro/operación, counts y batches. Restore exige árbol host previamente
   construido; NO reconstruye autoridades/config. `export_node` es sólo proyección
   propia. Guard `export` root-only sigue activo. Integrar nodos/ownership vivos,
   autoridad ORIGINAL+ACTUAL, límites y deadlines de TODOS ancestros, sin repricing,
   sumar hijos ni debitar de nuevo un batch reservado.
5. Writer.admit/batch/model_done/outcome/settle/pause/finish, reference y reserva
   `reserve_outcome` aún apuntan a raíz. Revisión de TODAS copias/slots J/JSON/receipts
   por árbol antes de IO; IDs call/model vinculados a nodo. Root paused sólo ACK y
   quiescencia conjunta, dirty/uncertain prevalecen; raw/final/resolve_call coherentes
   en ambas direcciones. Conservar pruebas de review raíz y hooks transformadores.
6. Continuation.reconcile actual sólo tool raíz. Faltan recuperación Model con
   respuesta+estado portable/perfil/output/metadata validados y retry explícito con
   idempotency key host entregada realmente al callable/proveedor. Conservar intent/
   incertidumbre original e intento nuevo enlazado; lease/receipt viejos no conceden
   IO. No inferir modelo confirmado desde plantilla ni repetir hook/efecto tras raw.
7. Oráculos faltantes: árbol+hermano confirmado, restricciones de cada ancestro,
   cancel/restart/reconcile y nueva VM desde fixture disco; modelo antes/durante/
   después de effect/save, idempotencia explícita y negativos de definición/modelo/
   args/policy/corrupción. Server/Session nuevos deben componerse con árbol y resto
   C7; probar finales/colas/eventos integrados y preservar turn control independiente.
8. Gate integrado final y distribución de mismo artefacto: compileforce/fullsuite/
   formato/docs/snippets/links/ExDoc, source+manifest y TAR/consumidores fixed graph
   mínimo/runtime/extensible/SQL opt-in sin SQL real ni resolución nueva. No G5 limpio.
   Misma review independiente C7 requerida antes de aceptar fase; R6–9 no activos.

Reviewer sólo valida su copia inmutable. Mantener ownership ROOT hasta instrucción
de cesión; ORCA_CHECKPOINT y prompt de relevo del coordinador permanecen excluidos.

## Actualización tras reanudación: fuente intermedia Server/Session

`msg_d0a932d877b5` reanuda misma Task/Dispatch/ownership Astra LOW. Resuelve las
dos propuestas diferidas de abajo: binding host opt-in Session y reset explícito
Server ante terminal con batch abierto. Firma complete_turn/4 aprobada por ask:
ref versionada ligada participante/namespace/id/lifetime/run/revisión; consumed
por lifetime+run, no revisión. Callback de cálculo puro, reconsulta antes de
advance, no exactly-once ante muerte VM ni CAS entre filas.

**Nuevo runtime:** Server deriva `:reset_required` al restaurar deny/cancel/expire
con batch abierto; mantiene cola y rechaza ejecución/model mutation hasta ACK de
reset. Reset conserva execution/efectos y receipts; drena cola sólo después del
ACK. Tests9 Server incluyen reinicio, dos terminales, cola, pre/postcommit y cotas:
token J exacto/J−1 por API pública antesStore; JSON8MiB exacto/+1 y receipts1024
con replay exacto mediante reducer sobre record derivado del ciclo público. Estos
dos oráculos de capacidad no se describen como pruebas SQL ni de public dispatch.

Session implementa bindings confiables, continuation/2 y complete_turn/4. Snapshot3
para opt-in, ordinary2 y lectores1/2 conservados; v3 con guard omitido/downcast o
binding faltante/cambiado se rechaza. Máximo64 bindings, IDs EFT≤512, referencia
EFT≤4096 y entrada≤8192; un consumed por binding, nunca lista eterna. Store/refs
de procesos no se serializan. Restore consulta fila aun sin pending local; pre/post
change frenan avance y sustitución de shared_state, con bloqueo end/handoff/leave.
Pause/resume de turno sigue independiente. Complete exige terminal sin unresolved,
referencia exacta y turno; guarda consumed lifetime/run. Segunda lectura cambiada
conserva bloqueo/estado anterior sin repetir callback. Dirty Session conserva
candidato y sólo reintenta snapshot, sin prometer atomicidad con la fila de agente.

**Evidencia incremental nueva**, mismo runner/entorno/seed37556:

- `r53-server-terminal-focal-01`:Server7/7 exit0.
- `r53-session-focal-01`:Session nuevo+persistencia/FSM26/26 exit0.
- `r53-session-focal-02`:27/29, dos rojos de fixture: script agotado en segunda
  iteración y start_link negativo enlazado propagando EXIT al test.
- `r53-session-focal-03`:28/29; la segunda iteración creaba Session observando un
  terminal anterior y luego reemplazaba el run antes de completarlo: rechazo de
  identidad correcto, callback no invocado. La fixture ahora usa el mismo terminal
  autorizado en dos Sessions independientes y comprueba resultado exacto en error
  dirty; no se relajó el bloqueo de producto para hacerla pasar.
- `r53-session-focal-04`:45/45 incluyendo todas las suites Session existentes,
  antes de añadir último test64/+1 y guard v3 ausente.
- `r53-server-session-caps-01`:15/15 (Server9+Session6), exit0.
- `r53-server-session-compileforce-01`:88 fuentes forzadas, exit0.
- `r53-server-session-suite-01`:867/868 pasan,28 excluidos, exit2,133.33s.
  Único rojo: native OTLP lifecycle en VM separada, `timed_out.retained == 0`
  observó1 en `test/support/native_otlp_probe.exs:202`. Fuentes OTLP no editadas;
  no atribuir causalidad a C7 ni declarar resuelto por repetición.
- `r53-native-lifecycle-focal-01`:misma prueba intacta línea23,1/1 y3 no seleccionados,
  exit0,2.785s. Rojo integrado no reproducido en esta única focal; diagnóstico causal
  pendiente R7/R8 según `msg_86dc4e6ddf5d`. No se modificó OTLP ni se
  repitió toda la suite hasta conseguir un verde.
- `r53-server-session-format-01`:formato exit0; `git diff --check` exit0.

Además del inventario inicial se modifican `lib/exagent/session.ex`,
`lib/exagent/session/snapshot.ex` y `docs/guides/migration.md`, y se añaden
`lib/exagent/session/continuations.ex`, `test/exagent/continuation_session_test.exs`.
Diseño/changelog/migración reflejan la dirección antes de estabilizar. Reviewer
recibirá fuente/manifest/diff contra f8b5, autorizado por `msg_0045265b9bdf`, sin
TAR/consumidor repetitivo. La revisión intermedia no acepta C7 completo.

**Pendientes que no cambian:** descriptor compilado pero todavía no consumido por
loop; Frame2/Writer por nodo y árbol/autoridad ancestral/reservas integradas siguen
sin implementar, guards root-only activos. Server abort/cancel activo y restantes
ventanas dirty/queue/events, probes completos Session de incertidumbre/retención,
recuperación de estado Model y retry de efecto con idempotencia entregada al host
siguen requeridos. No review independiente ni distribución final de este delta.

El checkpoint de pausa y su inventario son históricos inmutables: la prosa de abajo
describe exactamente lo recibido al transferir, no el estado runtime actual.

## Estado y ownership al pausar

Task `task_ec3210551bcd`, dispatch `ctx_5963c2e6fb6e`, Astra LOW confirmado por
coordinador antes de investigar. ROOT/docs/builds exclusivos de este worker;
`ORCA_CHECKPOINT.md` y `docs/prompts/orchestration-handoff-2026-09-26.md` son del
coordinador. No ceder ownership ni enviar worker_done por esta pausa.

El usuario pidió transferir coordinación del mismo Run. Mensaje
`msg_198ee90c20b0` exige pausar en punto seguro, guardar inventario y quedar idle
sin sondeo hasta reanudación. La implementación sigue autorizada, pero no continuar
ampliaciones ni gates nuevos durante esta transferencia. Todos los comandos runtime
propios terminaron sin procesos de build/test dejados en background; ningún servicio,
worker adicional o recurso externo fue iniciado.

Base preservada: source291 `f8b542f6f78d6d4fb59e0ac6945c658904badf14339f30b45c816b39b15cea1a`
y recepción documental posterior descrita en handoff; nominal1.3.0, HEAD7f25b33 y
lockc20a0cb9 intactos. La review previa sólo acepta raíz parcial. No se repitieron
R0–R4, suite completa, TAR ni consumidores. Ninguna publicación/instalación/global/
LLM/SQL/Opik ni delegación de trabajo.

## Matriz criterio → bytes/evidencia → huecos

| Criterio | Delta de esta Task / evidencia | Hueco explícito |
|---|---|---|
| R5.1/4/5 árbol | ADR8.34 ampliado con dirección aprobada frame2/scope2. Nuevo `continuation/scope_ledger.ex`; seams `ExecutionScope.export_tree/restore_tree/export_node`. Cuatro tests directos del seam, no aceptación de API C7. | Frame2, restauración confiable completa, journal de delegación y writer por nodo NO implementados. Guards root-only intactos. |
| Contabilidad por identidad | Scope2 conserva nodos/padres, contadores, batches y Usage ya cualificado por ancestro. Restore exige árbol host previamente construido idéntico; no crea configuración desde bytes. Roundtrip sin repricing/doble débito y rechazos atómicos de corrupción probados. | Integrar con frames/autoridad original+actual de TODOS ancestros; reservas J/JSON/slots y oráculo público hijo pendiente+hermano confirmado. No atribuir a este codec validación de políticas que no serializa. |
| Descriptor confiable | Nuevo `continuation/delegation.ex`; campo privado Tool.delegation y construcción opt-in `Coordination.delegation_tool(..., continuation: child_config)`. Frame.fingerprint incorpora sólo refs/prompt_arg/descriptor_version; no closures. | Compilado, sin test focal propio todavía. El loop NO consume el descriptor y run_child durable sigue rechazando; no anunciar delegación durable utilizable. Resolver config/builder antes de IO al integrar. |
| R5.7 reset Server | Nuevo `reset_snapshot` terminal-only en Transition y ruta Server.reset CAS. Oráculo público terminal→reset→restart→siguiente run; fallos antes/tras commit, retry exacto y negativos pending/ready/claimed/uncertain/dirty. Cinco tests Server pasan (dos previos + tres nuevos). | No cierra Server: abort/cancel/terminal/cola, eventos y recovery completos pendientes; reserva/cap/cardinalidad del nuevo comando aún no probadas. |
| Session | Lectura focal confirma Session genérica: change(shared_state), Participant.ref app arbitrario. | Propuesta binding confiable y snapshot de ref pendiente DIFERIDA, sin código Session nuevo. |
| R5.6 | Foundation raíz revisada reutilizada. | Modelo incierto/reconcile con estado portable y retry explícito con idempotency key entregada a callable/proveedor no implementados aquí. |
| Integración/distribución | Sólo focales incrementales abajo. | Compileforce/fullsuite/formato/docs/ExDoc/snippets/links/freeze/TAR/consumidor fijo y review independiente integrados pendientes. |

## Decisiones aprobadas y diferidas

La respuesta al primer ask aprobó descriptor host opt-in, loop/writer/fila únicos,
versionado interno explícito frame2/scope2 (lectores antiguos rechazan árbol),
compatibilidad root1 validada, árbol íntegro sin ciclos/huérfanos/IDs duplicados,
costes por operación/ancestro sin sumar hijos y journal compuesto inequívoco.
Exigió reserva de TODO árbol antes de IO, quiescencia antes de paused y dirty/
incertidumbre con precedencia; Session sin transacción ficticia; retry explícito
conservando intent incierto y nueva identidad enlazada. ADR recoge la dirección,
no dice que esos mecanismos estén implementados.

`msg_765609e30216` ratificó reset_snapshot terminal-only: conservar execution,
effects/receipts/lifetime/fence y revisión monotónica; negativos activos/dirty y
ACK perdido. Runtime actual no borra ni recrea la fila. Error de reset conserva
token exacto y bloquea mutaciones; checkpoint repite sólo persistencia.

Ask `msg_4a05a0ba3641` está **sin decisión técnica**, respuesta sólo ordenó pausa:

1. Session opt-in `continuations: %{participant_id => %{store: scoped_store,
   id: agent_id}}`, Store siempre host y ref pequeña persistida con versión que
   lectores anteriores rechacen. Consultar fila autoritativa antes de advance/
   restore incluso si crash entre filas dejó sin ref local; turno pause separado.
2. Deny/cancel dejan hoy snapshot con batch abierto. Se propuso mantener cola
   Server bloqueada hasta reset explícito terminal, en vez de drenar historia
   inválida o fabricar ToolReturns. Alternativa a decidir: cerrar batch de forma
   explícita para permitir drenado automático. NO implementado ni aprobado.

## Archivos atribuidos a esta Task

Runtime nuevos: `lib/exagent/continuation/{scope_ledger,delegation}.ex`.
Runtime modificados: `lib/exagent/{execution_scope,tool,coordination,server}.ex`,
`lib/exagent/continuation/{frame,transition}.ex`.
Tests: nuevo `test/exagent/continuation_scope_ledger_test.exs` y delta en
`test/exagent/continuation_server_test.exs`.
Docs: secciones añadidas a diseño8.34 y changelog; este registro, handoff y
roadmap actualizados para la pausa. Todo el diff previo/untracked se conserva;
no atribuirlo a este worker. No cambios en ExAgent loop, RunContext, Session,
mix/lock ni codecs de mensajes/snapshots de esta Task.

## Comandos, rojos y límites de evidencia

Runner leído `/tmp/opencode/exagent-r4-integration-run.py`; paths existentes
verificados antes de Mix. Allowlist sin secretos, Elixir1.20/OTP29, +S8:8,
EXAGENT_OFFLINE=1/HEX_OFFLINE=1/MIX_ENV=test, builds ROOT `_build/test`, deps ROOT.
Logs y argv/entorno/exits JSON en `/tmp/opencode/exagent-r11/<label>.{log,json}`.

| Label | Resultado |
|---|---|
| r53-tree-ledger-focal-01 | `mix test test/exagent/continuation_scope_ledger_test.exs --warnings-as-errors --seed 37556`;4/4 exit0. |
| r53-server-reset-red-01 | Compilación bloqueada por nombre local binding/1 frente a Kernel.binding/1 en descriptor nuevo; no alcanzó test. Se renombró a descriptor_data/1. |
| r53-server-reset-red-02 | Server2/3; rojo causal reset con CheckpointError reason atomic_record_required; casos Server previos verdes. |
| r53-server-reset-green-01 | Server+scope7/7 exit0, después de ruta CAS y reducer reset_snapshot. |
| r53-server-reset-focal-02 | Último runtime: Server5/5 exit0; incluye before/afterACK retry sin IO y rechazos activos/uncertain/dirty. |

No exclusiones nuevas, seeds37556. No test nuevo prueba todavía C7 delegado ni
Session. No gate adicional durante pausa. Scope export_node y descriptor sólo
compilados por las últimas focales; antes de continuar añadir oráculos pertinentes
y contrastar con review-root existente, sin usar los verdes de root como prueba de
árbol. `reset_snapshot` no necesita reserva de cleanup de ejecución (sólo terminal),
pero su nuevo receipt/JSON/J y límites1024/8MiB deben probarse; no se ha demostrado
esa frontera aún. No afirmar formato/fullsuites/review de este delta.

## Próxima acción al reanudar

Nuevo coordinador confirma reanudación/ownership de la misma Task; resolver el ask
Session/terminales pendiente. Revisar inventario de pausa y mailbox, sin repetir
auditoría general. Completar límites/tests del reset y descriptor; integrar árbol
real en Frame/Writer/loop/Scope con journal compuesto y rehidratación íntegra antes
de levantar guard; después terminar Server/Session/uncertainty. Source f8b5 y su
review siguen referencia de raíz, no aceptación del nuevo delta. Reviewer
task_0ee986f3992e/ctx_7c85ffbff803 reservado para freeze integrado, no despertado por
este worker. La aceptación final C7 requiere revisión independiente.
