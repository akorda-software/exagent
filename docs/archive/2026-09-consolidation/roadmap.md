# ExAgent — Roadmap

> **Archivo cerrado de septiembre de 2026.** Conserva el seguimiento tal como
> quedó tras la consolidación; contiene checklists y estados de fechas distintas.
> La [hoja de ruta vigente](../../development/roadmap.md) es la fuente de prioridades.

> Estado: **1.0 completo**. Las fases 0–6 (núcleo, runtime con estado,
> persistencia, sesión, coordinación, robustez, producción + ecosistema) están
> implementadas y testeadas. Lo que queda está abajo, en "Próximo". El caso
> motor (partida de D&D en Phoenix) se construye sobre estas fases, pero ninguna
> fase es específica de D&D. Fundamento de diseño: ver `DESIGN.md`.

## Prioridad actual: consolidar antes de ampliar

Dirección acordada el 2026-09-05: construir una base de propósito general muy
sólida ahora, aprovechando que las aplicaciones conocidas del autor todavía
no están en producción, y estabilizar después los contratos revisados. Esto
no presupone el estado de los consumidores externos ni permite omitir SemVer.
La finalización histórica de 1.0 no certifica que estos criterios estén cerrados.

La política y criterios completos están en las secciones 2.1–2.3 de
[`DESIGN.md`](../../architecture/design.md). Este bloque tiene prioridad sobre ampliar funciones
del apartado «Próximo»; no vuelve a abrir indiscriminadamente todo lo entregado.

- [x] Documentar visión, compatibilidad por defecto, justificación de rupturas
  y criterios de estabilización; enlazarlos desde README e instrucciones del repo.
- [ ] Revisar conjuntamente los contratos públicos del core, Server, Session,
  tools, proveedores, errores, eventos, historial y snapshots; registrar
  inconsistencias demostradas y priorizar las que justifiquen cambios.
- [ ] Mantener una matriz de capacidades verificadas por proveedor y backend:
  texto, tools, streaming, outputs, uso y restricciones. Separar pruebas de
  payload offline de aceptación por el proveedor real.
- [ ] Consolidar regresiones de cancelación, cleanup, backpressure, límites,
  fallos de tools y efectos externos; medir cargas representativas.
- [ ] Validar ergonomía y migración en las aplicaciones conocidas y en ejemplos
  de distintos dominios; no extrapolar compatibilidad a consumidores no probados.
- [ ] Agrupar los cambios estructurales necesarios en una major coherente con
  guía de migración, en lugar de publicar rupturas parciales sucesivas.
- [ ] Cerrar la consolidación con contratos revisados, pruebas y documentación;
  desde ese punto priorizar evolución aditiva y deprecaciones planificadas.

### Investigación de base (2026-09-08)

- [x] Revisar la implementación y contrastar frameworks/harnesses, ecosistema
  Elixir y observabilidad abierta. Diagnóstico, fuentes y propuesta por unidades
  en [`RESEARCH.md`](research.md); no son decisiones de contrato aprobadas.
- [x] Verificar la suite offline del estado local: 310 tests pasan, 28 excluidos,
  con dos warnings preexistentes de aliases en el test de concurrencia del Server.
  Hex se instaló en un `MIX_HOME` temporal, sin modificar dependencias ni versión.
- [ ] Acordar contratos y alcance de recuperación; reproducir los
  gaps prioritarios antes de cerrar contratos o preparar nuevas firmas.
- [ ] Probar instrumentación OTel nativa y el mismo escenario en Langfuse/Opik,
  incluyendo privacidad, propagación entre procesos, uso y saturación. Ningún
  adaptador de observabilidad está implementado por esta investigación.
- [ ] Inventariar usos de Dragonex/WhoamAI con autorización y validar después la
  migración. No se han inspeccionado ni modificado consumidores en esta unidad.

Limitaciones: auditoría estática más suite existente, no reproducciones nuevas
de todos los hallazgos. Sin llamadas a proveedores, Postgres, despliegues de
tracing ni benchmarks; no se han verificado cambios remotos pendientes de Git.
Se mantiene abierta la revisión conjunta de contratos indicada arriba.

### Plan de acción preparado (2026-09-09)

- [x] Concretar la investigación en [`ACTION_PLAN.md`](action-plan.md), con
  tareas, dependencias, criterios de cierre, verificación y decisiones pendientes.
- [x] Registrar preferencia de observabilidad: mayor cobertura sin licencia
  comercial a calidad comparable; aceptar funciones avanzadas comerciales por
  una mejora relevante demostrada. D2 queda aclarada; backend pendiente de C6.
- [x] **C0 técnico:** base, inventario inicial y siete riesgos P0 reproducidos;
  medidas sintéticas iniciales registradas. Consumidores aún desconocidos.
- [x] **C1 decisiones:** semánticas transversales y migraciones fijadas en DESIGN
  8.2–8.4 bajo autonomía delegada, con dos propuestas Astra y el inventario real
  de consumidores. La verificación de su implementación pertenece a C2–C5.
- [x] **C2 (offline):** validación, permisos, resultados y retries explícitos de tools.
  - [x] **C2.1:** corregir admisión ante configuración/acciones de permisos
    inválidas y callbacks de aprobación no invocables, con regresiones de efectos.
- [x] **C3 (offline):** loop sync/stream común, transporte limitado, adapters y
  evaluación acotada de ReqLLM; aceptación real por backend pendiente en C8.
- [x] **C4 (offline):** uso, presupuesto/autoridad de delegación y proyección de contexto.
- [x] **C5 (offline):** ownership, eventos, checkpoint/retry-save, snapshots y FSM;
  Store Postgres real y recuperación de efectos arbitrarios no están certificados.
- [ ] **C6:** integrar OTel opcional y validar el backend de referencia.
  - [x] Instrumentación neutral y aceptación offline mediante Orca/Astra, dos
    revisiones frescas y verificador final independiente. Spans, propagación,
    privacidad opt-in, processor acotado y ejemplo documentados en OBSERVABILITY.
  - [x] **579 correctos/28 excluidos** en Elixir1.20/OTP29 y 1.18/OTP28, compile72
    con warnings-as-errors, 14 invariantes C0 en ambos y probe R3 determinista.
    Tres consumidores limpios (sin OTel, API sola y SDK) compilan sin warnings;
    el último prueba el orden de compilación SDK→ExAgent y exportación real al fake.
  - [x] Ejemplo509/509 spans, cero pérdidas/fallos. Overhead local de200 muestras
    tras50 warmup: p50/p95 desactivado56/70us, activado123/178us, concurrencia1.
    Son medidas sintéticas, no SLO de proveedores. Detalle en ACTION_PLAN9.
  - [x] Auditoría focal del SDK/API publicados y perfil GenAI actual: cota BSP
    blanda, flush sin ACK, contadores ausentes y metadata Logger residual. Se
    justifica un processor nativo opt-in acotado; decisiones/fuentes en DESIGN8.6.
    Los fixes de revisión incluyen compilación opcional, trap_exit/flush, Logger,
    bigint y completitud conservadora de abort; decisiones en DESIGN8.6–8.7.
  - [x] Exporter OTLP nativo contra loopback con protobuf inspeccionado, matriz de
    fallos y caracterización de lifecycle (N01–N03; evidencia nocturna debajo).
  - [ ] Cleanup HTTP general del exporter y comparación API/UI Langfuse/Opik con
    acceso autorizado. Los límites upstream están reproducidos; ningún backend
    está elegido ni desplegado.
- [ ] **C7, condicionado al alcance:** aprobación diferida como datos recuperables.
- [ ] **C8:** aceptación real, medidas de carga/evals y migración de la major.

Estado: bloque C1–C5 implementado, revisado e integrado mediante Orca/Astra.
Resultado final: **542 tests correctos, 28 excluidos**, con warnings como errores,
en Elixir 1.20/OTP29 y 1.18/OTP28; compilación forzada de 70 archivos correcta.
El verificador fresco independiente confirmó primero 541/28 en ambos runtimes;
el cierre posterior añadió una regresión TCP y mínimos seguros Mint/HPAX,
repitiendo ambas suites. Las 14 invariantes de los siete grupos C0 pasan.
Se corrigieron también los dos warnings preexistentes de aliases de tests.
Detalle y límites en [ACTION_PLAN, sección 8](action-plan.md#8-consolidacion-orquestada-c1-c5).
Los workers están cerrados y el checkpoint está en ORCHESTRATION.md.
El inventario read-only de Dragonex/WhoamAI
ya está disponible: Dragonex Git a31b306/1.3.0, WhoamAI vendor c08125b/1.2.0;
aceptación/migración de consumidores aún pendiente, sin editar sus aplicaciones.
La selección Langfuse/Opik depende de comprobar calidad, funciones disponibles
y operación con el criterio aclarado; el alojamiento sigue por confirmar.
Esto no bloquea las primeras unidades ni el diseño OTel.
Siguiente externo: resolver el lifecycle HTTP nativo y comparar Langfuse/Opik;
el transporte local y la base neutral tienen la evidencia nocturna de abajo.
Después, alcance C7 y aceptación/migración real C8.
No se ha publicado ni cambiado versión. Los cinco workers C6 también están cerrados.
El mínimo Elixir1.17 quedó verificado posteriormente en N06/N18, en la combinación
concreta indicada abajo. Las fases históricas no sustituyen estos criterios.

- [x] Preparar `NEXT_AGENT_PROMPT.md` para relevar al coordinador con contexto
  limpio: mandato, Orca/Astra, contratos, evidencia final y restricciones.
- [x] Ampliar el relevo para el encargo nocturno posterior: 18 unidades priorizadas
  de OTLP local, paquete/toolchains, propiedades de runtime/protocolos, privacidad,
  cargas, evals y cierre. El usuario pausó la implementación para preparar ese
  prompt; ese corte histórico precede a la ejecución nocturna descrita debajo.
  Baseline previo al relevo: 579 correctos/28 excluidos, seed806578. La comparación
  de plataforma requiere acceso, pero no bloquea las demás unidades autónomas.

### Consolidación nocturna: alcance local cerrado (2026-09-09/10)

Run Orca `run_4315531152c9`, generación1, workers Astra. Baseline579/28,
seed280440; cierre independiente **619 correctos,28 excluidos** en cada runtime,
seed37556: Elixir1.20.0/OTP29.0.5,1.18.4/OTP28.0 y1.17.3/OTP27.3.4.17.
Son40 tests nuevos sobre la base; los casos generados y probes tienen sus propios
denominadores. Detalles, comandos y límites en ACTION_PLAN10.

- [x] N01–N04/N12: OTLP nativo loopback con protobuf, fallos y privacidad; escenario
  compuesto68 spans/11POST. N03 caracteriza retención nativa de perfiles/átomos/
  sockets y verifica cleanup propio, sin certificar lifecycle HTTP general.
- [x] N05/N06: consumidores de bytes TAR y mínima combinación comprobada. Startup
  SDK opcional corregido para compilar sin warnings propios en1.17 y1.20. Runner
  revisado protege selectores/destinos y conserva grafos/diagnósticos por separado.
- [x] N07–N11: secuencias con oráculos independientes, restore adversarial, admisión
  y autoridad por árbol, cache/schema/hooks y fragmentación/cleanup de protocolos.
  No se demostró un defecto productivo nuevo en esos escenarios.
- [x] N13/N15:4000 runs medidos correctos y12200 spans locales sin pérdidas normales;
  percentiles c1/8/32, mini-soak finito y saturación32/610. Evals en dos dominios con
  controles negativos. N14 concluye no-change, sin hotspot causal que justifique
  otra optimización ni retirar garantías.
- [x] N16/N17 focal:16 snippets (11 ejecutados/5 recetas),7 checks y dos errores
  README corregidos; matriz de promesas y auditoría de deps tocadas, sin upgrades
  especulativos ni inferir soporte de cada backend real.
- [x] N18: compile forzado73 y suite en tres runtimes; C0 14/14, snippets7/7 y R3 1/1
  en los tres; siete ejemplos y smoke final. Paquete final:72/72 contratos runtime,
 11/12 consumidores estrictos verdes. Exporter/OTP29 sigue rojo estricto por nueve
  warnings gproc conocidos; no se ocultan ni se cuentan como fallos runtime.
  Docs con warnings-as-errors, formato y diff correctos; ningún worker activo.

**Límites abiertos:** P1 operacional del HTTP nativo, booleans/partial-success del
exporter, comparación Langfuse/Opik, proveedores/DB/consumidores reales y alcance C7.
C8 completo no se declara cerrado. Se conserva HEAD/WIP/untracked y nominal1.2.0,
sin publicación, commit, bump, merge, despliegue ni cambios en consumidores.

**Incidente de tooling:** un bootstrap heredó MIX_ARCHIVES y sustituyó Hex
compartido por BEAM incompatible. Se contuvo y corrigió el runner; los gates finales
usan tooling explícitamente aislado. El Hex compartido sigue pendiente de reparación
autorizada. Evidencia y comandos locales seguros en ORCHESTRATION/ACTION_PLAN.

Convención histórica: cada fase = módulos + tests + un ejemplo en `examples/` o
`test/support/`. (Nota: el alias `mix check` corre tests en entorno dev; usar
`MIX_ENV=test mix test`.)

---

## Fase 0 — Núcleo funcional ✅ (HECHO)

Loop `model ⇄ tools`, providers (OpenAI/Anthropic/ZAI/OpenRouter/Test),
`deftool`, output estructurado Ecto, streaming lazy, capabilities, `UsageLimits`,
telemetría, serialización de message history.

Es la base implementada sobre la que se apoya todo. Su revisión se rige por la
prioridad actual de consolidación, no por una prohibición de cambiar el núcleo.

---

## Fase 1 — Agente con estado: `ExAgent.Server`

**Objetivo.** Un agente longevo, supervisado, con memoria e historial, que emite
eventos. La pieza que falta para cualquier uso más allá de one-shot.

**Módulos.**
- `ExAgent.Event` — envelope versionado y serializable. Campos mínimos:
  `version`, `id`, `seq`, `type`, `source`, `occurred_at`, `run_id`,
  `request_id`, `agent_id`, `session_id`, `participant_id`, `payload`,
  `metadata`.
- `ExAgent.PubSub` behaviour — `broadcast/3` y `subscribe/2` opcional.
  Implementaciones: `None` (default), `Local` (Registry local), `Phoenix`
  (adaptador dinámico sin dependencia dura).
- `ExAgent.Server` (GenServer) — `start_link/1`, `chat/3`, `stream/3`,
  `send_message/3` (async → eventos), `steer/2`, `abort/1`, `set_model/2`,
  `history/1`, `usage/1`, `health/1`.
- Estado interno del Server (no público): agent + history + usage acumulado +
  model + status + current_task + pending queue + pubsub/topic + metadata.
- `ExAgent.AgentSupervisor` — `DynamicSupervisor` + `Registry` para
  arrancar/localizar agentes por id/nombre.
- `ExAgent.TaskSupervisor` — tareas supervisadas para que el GenServer siga
  respondiendo a `abort/1`, `health/1` y backpressure durante un run largo.

**Cambios pequeños al core funcional.**
- `ExAgent.run/3` debe aceptar un `:on_event` opcional usado por `Server` para
  publicar eventos del loop. Default: no-op.
- El result debe exponer el `model` final o provider state equivalente para que
  `Server` preserve modelos stateful como `ExAgent.Models.Test` entre chats.
- `Server` no debe duplicar system instructions en cada chat: las instrucciones
  se materializan una vez en el history de conversación y los siguientes runs
  agregan solo el nuevo user prompt.

**Semántica de concurrencia.**
- `chat/3`: bloquea al caller, ejecuta un run completo y actualiza history/usage.
- `send_message/3`: devuelve `{:ok, request_id}` inmediatamente y publica eventos
  en `"exagent:agent:<agent_id>"`.
- `stream/3`: usa el streaming actual para texto/deltas. En Fase 1 no promete
  tool-loop streaming completo; eso requiere el futuro stream de eventos del core.
- `abort/1`: cancela la tarea actual y emite `:server_request_cancelled`.
- `steer/2`: en Fase 1 encola un follow-up o metadata para el siguiente run. No
  modifica una request HTTP ya enviada al provider.
- Backpressure explícito: `:busy` si no hay cola; `:queue_full` si `max_pending`
  se supera.

**Cierre de fase.**
- Tests: arrancar un Server con `TestModel`, encadenar dos `chat/3` (el segundo
  ve el history del primero), `send_message/3` entrega resultado vía evento,
  eventos tienen envelope estable + `seq` monotónico, `abort/1` cancela la tarea,
  `send_message/3` respeta `:busy`/`:queue_full`.
- Ejemplo `examples/stateful_agent.exs`: agente conversacional offline.

**No incluye.** Durabilidad tras restart. Eso empieza en Fase 2.

**Sin esto no hay:** DM con vida ni ningún agente persistente.

---

## Fase 2 — Persistencia: `ExAgent.Store` (behaviour) + impl ETS ✅ (HECHO)

**Objetivo.** Estado resumible tras crash/restart. Desacoplado vía behaviour y
sin persistir procesos vivos, secrets ni function captures.

**Módulos.**
- `ExAgent.Server.Snapshot` — snapshot serializable: `agent_id`,
  `message_history`, `usage`, `model_ref/provider_state` si es serializable,
  `metadata`, timestamps. No contiene pids, API keys ni tool captures.
- `ExAgent.Store` (behaviour) — `save_agent_snapshot/2`,
  `load_agent_snapshot/1`, `save_session_snapshot/2`, `load_session_snapshot/1`,
  `list_agent_snapshots/1`, `delete/1`.
- `ExAgent.Store.ETS` — implementación en proceso (dev/test). Aunque ETS pueda
  guardar términos arbitrarios, sus tests deben pasar por serialización para no
  diseñar una API imposible de llevar a Postgres.
- `ExAgent.Server` se engancha: checkpoint tras cada `:run_finished`; al restart,
  recibe de la app el `agent` vivo y rehidrata history/usage desde el Store.

**Cierre de fase.**
- Tests: matar un Server supervisado → reaparece con su history intacta;
  guardar/cargar snapshot serializado; ETS aislado por namespace/sesión;
  confirmar que snapshots no incluyen secrets ni captures de tools.
- Documentar el contrato del behaviour para que Postgres venga después trivial.

**Sin esto no hay:** durabilidad; un crash pierde la partida.

---

## Fase 3 — Sesión: `ExAgent.Session` (agnóstica) ✅ (HECHO)

**Objetivo.** Una interacción con estado coordinada entre varios participantes
(humanos y/o agentes), con turnos y estado compartido. **El núcleo del
multi-agente y de la partida.**

**Módulos.**
- `ExAgent.Session` (GenServer) — lifecycle:
  `new/1 · join/2 · leave/2 · start/1 · take_turn/2 · pause/1 · resume/1 · close/1`.
  Mantiene `participants`, `shared_state` (struct app-defined), `turn_state` y
  `policy_state`.
- `ExAgent.Session.TurnPolicy` (behaviour) — `init/1`, `next_participant/2`,
  `can_act?/3` y estado propio de política. Implementaciones: `RoundRobin`,
  `Initiative`, `SupervisorDriven`.
- `ExAgent.Session.SharedState` — conveniencia para leer/escribir el struct
  compartido. La Session es el único writer: los tools reciben en
  `RunContext.deps` un servicio/ref que llama a la Session para leer o proponer
  cambios (patrón pydanticAI, sin estado mutable compartido).
- Session emite eventos por PubSub: `:participant_joined ·
  :session_turn_changed · :shared_state_updated · :session_closed`.

**Cierre de fase.**
- Tests: 2 `ExAgent.Server` + 1 "humano" (proceso de test) coordinados por
  `RoundRobin`; un turno modifica `shared_state` y el siguiente participante lo
  lee; escrituras concurrentes pasan por la Session; `pause/resume` congela y
  reanuda; `Initiative` respeta el orden dado.
- Ejemplo `examples/multi_agent_session.exs`: dos agentes (TestModel)
  intercambian turnos sobre un estado compartido.

**Agnosticidad explícita:** nada sabe de D&D. `shared_state` puede ser un mundo,
un ticket de soporte, un doc colaborativo.

---

## Fase 4 — Coordinación multi-agente: `ExAgent.Coordination` ✅ (HECHO)

**Objetivo.** Patrones de orquestación sobre la Session.

**Módulos.**
- `ExAgent.Coordination.delegation_tool/2` — genera un `Tool` que invoca a otro
  agente (patrón pydanticAI nivel 2); **usage compartido** entre padre e hijo.
- `ExAgent.Coordination.handoff/2` — pasa el control de un participante a otro
  (mensajería directa entre procesos).
- `ExAgent.Coordination.SupervisorPolicy` (TurnPolicy) — un participante
  "DM/supervisor" decide a quién delegar cada turno.

**Cierre de fase.**
- Tests: delegación con TestModel (el agente padre llama al hijo, el `usage`
  final suma ambos); handoff transfiere el turno; supervisor dirige a 2 bots.
- Cubre niveles 2 y 3 de la taxonomía pydanticAI.

---

## Fase 5 — Robustez/coste: Compaction, Cost guard, Prompt caching ✅ (HECHO)

**Objetivo.** Sesiones largas sin reventar contexto ni presupuesto.

**Módulos.**
- `ExAgent.Compaction` (behaviour) + `ExAgent.Compaction.Summary` —
  resume el historial al acercarse al límite de tokens (alloy/Pi). Se engancha
  como `Capability` (hook `before_model_request`).
- `ExAgent.CostGuard` — `max_budget_cents` / `max_tokens` frena el loop
  (alloy). Integrado en `UsageLimits` ya existente, añadiendo `tool_calls_limit`
  si aún no existe.
- Prompt caching Anthropic — `cache: true` añade breakpoints (alloy); ahorro
  60–90% en input.

**Cierre de fase.** Tests con historial sintético largo → compaction reduce
tokens manteniendo coherencia (TestModel); cost guard detiene al superar budget.

---

## Fase 6 — Producción y ecosistema: Permissions, MCP, Postgres, LiveView (parcial)

**Objetivo.** Lo que falta para llevar D&D (y apps reales) a producción.

**Hecho en 0.3.0:**

- `ExAgent.Permissions` — `allow/ask/deny` con globs por tool (opencode),
  fail-closed, integrado en `run/3` vía `:permissions` + `:approve`.
- `ExAgent.PubSub.Phoenix` — adaptador validado con LiveView real.

**Hecho en 0.4.0:**

- `ExAgent.Store.Postgres` — store durable vía Ecto/Postgrex (deps opcionales).
  Serialización JSON estricta (nunca terms opacos), `migrate/1` idempotente.
  Testado con Postgres real (auto-skip del tag `:postgres` si no hay BD).

**Hecho en 0.5.0:**

- MCP client — `ExAgent.MCP.Client` (stdio JSON-RPC) consume tool servers
  externos y los expone como `ExAgent.Tool`. `ExAgent.MCP.Protocol` es el core
  puro y testeable; validado con mock transport + un e2e real (python server).

**Hecho en 0.5.1 (scenario hardening):**

- Suite de **escenarios de integración** (`test/exagent/scenarios/`) que
  compone todas las capas en historias reales (no solo aisladas), más una
  matriz de 9 modelos vía OpenRouter (`:integration`). Véase `CHANGELOG.md`.
- Bugs que la suite sacó a la luz y se cerraron: `OutputSchema` ahora refleja
  las validaciones del changeset (enum/min/max) en el JSON Schema enviado al
  modelo; `Compaction.Capability` preserva `new_messages` tras compactar;
  `AgentSupervisor` subió `max_restarts` para que un crash de agente no cascade.

**Hecho en 0.5.2 (deep bug-hunt):**

- Pasada de caza-bugs con tres subagentes (core, runtime, cobertura) que sacó a
  la luz ~14 bugs confirmados, ahora cerrados: providers que crasheaban con
  respuestas malformadas (`choices: []`, `content: null`, `tool_calls: null`);
  un task de tool que mataba el proceso agente al levantar error; output calls
  duplicados que dejaban el historial irreplicable; deadlock de sesión al
  marcharse el participante con el turno (las 3 políticas); handlers de
  streaming sin guard que corruptaban el run siguiente; abort vs completación;
  pubsub que crasheaba; checkpoint silenciosamente tragado. Véase `CHANGELOG.md`.

**Próximo (post-1.0):**

- [x] Unificar la generación de output estructurado con los requeridos/nulos
  declarados por Ecto, recursivamente en embeds, sin nuevas opciones ni campos
  de agente y conservando las firmas originales. Cubiertos el fallback sin
  changeset, los módulos sin cargar y el payload de `final_result`. Se conservan
  los fixes de opciones del Server, cancelación al morir su dueño y reenvío de
  `extra`. Cambio observable y migración documentados en `CHANGELOG.md`.
  Verificación offline: 310 tests pasan y 28 quedan excluidos; compilación
  forzada con warnings como errores y formato de archivos tocados correctos.
  Los 61 tests focales pasan también con warnings como errores. La suite completa
  mantiene dos avisos preexistentes de aliases sin usar en el test de concurrencia
  del Server, fuera de los archivos modificados.
- [ ] Antes de publicar este contrato: preparar una nueva major posterior a 1.x
  y verificar `anyOf` y restricciones strict contra los backends reales usados.
  La verificación offline no sustituye esa aceptación; este trabajo no publica,
  no sube versión ni contacta proveedores o Postgres.

- Aprobación async real (`:approval_requested` que pausa/reanuda el run o la
  Session, no bloquea dentro de un tool) sobre la base de Permissions.
- App LiveView de referencia jugable — `examples/dnd_session.exs` demuestra la
  coordinación D&D offline (DM + bot + humano + mundo); una app Phoenix
  completa queda como proyecto dedicado (la integración LiveView ya está probada
  por `chat_app`).

---

## Orden recomendado y dependencias

```
Fase 0 (✅) ──► Fase 1 (Server) ──► Fase 2 (Store) ──► Fase 3 (Session)
                                                            │
                                                            ▼
                                            Fase 4 (Coordination)
                                                            │
                                  Fase 5 (Compaction/Cost/Caching) ── paralelo
                                                            ▼
                                            Fase 6 (Prod: Perms/MCP/PG/LV)
```

Fases 1→3 son el camino crítico para tener el primer "juego jugable" (DM
supervisado + durabilidad + sesión con turnos). 4–6 amplían sin bloquear.

## Criterio 1.0 (cumplido)

- Fases 0–6 completas + suite de escenarios de integración + matriz de
  proveedores reales (9 modelos vía OpenRouter) + docs (ex_doc con grupos por
  capa). 284 tests.
- Pasada de caza-bugs profunda (3 subagentes) con todos los hallazgos cerrados.
- `DESIGN.md` y `ROADMAP.md` referenciados desde el README.
