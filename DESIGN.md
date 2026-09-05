# ExAgent — Design Document

> Documento vivo. Describe la visión, principios, arquitectura y decisiones de
> diseño de ExAgent. Acompáñalo de `ROADMAP.md` para el plan de ejecución.

## 1. Visión

ExAgent aspira a ser una biblioteca/framework de agentes de propósito general
para Elixir: conectar la mayoría de proveedores relevantes, crear agentes con
poca configuración, invocar tools y componer flujos desde una llamada sencilla
hasta sistemas con estado, streaming y coordinación multi-agente.

El objetivo es una base de alta calidad que pueda mantenerse y ampliarse durante
años sin rediseñar continuamente sus contratos. Ser completo no significa
incluir todas las funciones en el núcleo ni prometer que todos los proveedores
ofrecen las mismas capacidades. La complejidad adicional debe ser opt-in.

Debe ser a la vez:

- **Ergonómico como pydanticAI** — tools con schema derivado del tipo, output
  estructurado con changesets, dependencias tipadas, capabilities/hooks.
- **Robusto como alloy / normandy** — supervisión, telemetría, límites de uso,
  agentes como procesos.
- **Con una ventaja que ningún framework Python/TS puede igualar**: el runtime
  multi-agente **nativo del BEAM**. Cada agente es un proceso supervisado con
  mailbox; la coordinación multi-agente es mensajería OTP, no un "agent-as-tool"
  workaround.

ExAgent es **agnóstico**: no asume ningún dominio. El caso motor (una partida
de D&D en Phoenix con DM + bots + humanos en tiempo real) es el banco de
pruebas, pero el diseño sirve para soporte multi-agente, pipelines de
investigación, editores colaborativos, etc.

Las aplicaciones del autor, incluida WhoamAI, son bancos de pruebas, no la
especificación de la librería. Una solución específica se queda en la aplicación
salvo que revele una necesidad general y encaje en las capas de ExAgent.

## 2. Principios

1. **Functional core, layered runtime** (inspirado en Pi). `ExAgent.run/3`
   sigue siendo one-shot y sin procesos propios; cualquier side-effect (eventos)
   es opt-in. Sobre él, capas opcionales y composibles: agente con estado →
   sesión → store. Nada te obliga a usar más capa de la que necesitas.
2. **Process-per-agent** (superpower del BEAM). Un agente ES un GenServer
   supervisado. Multi-agente = procesos mensajándose, con tolerancia a fallos
   real. Python/TS tienen que simular esto llamando agentes como tools.
3. **Ergonomía pydanticAI**. Deps (DI) tipadas vía `RunContext`, `deftool` que
   deriva JSON Schema de anotaciones `::`, output estructurado vía Ecto con
   retry, capabilities como middleware, `UsageLimits`.
4. **Agnóstico y componible**. Session = "interacción con estado coordinada
   entre participantes", no "partida". Store/Provider/Tool/Compaction/PubSub
   son behaviours: implementations intercambiables.
5. **Event-driven para tiempo real**. Cada capa emite eventos tipados (text
   deltas, tool calls, run steps, lifecycle) por PubSub. Cualquier UI
   (LiveView, CLI, channel) se suscribe. Convergencia de Pi + opencode + alloy.
6. **Sin dependencias forzadas**. DB-free por defecto (como hoy). Phoenix,
   Oban, Postgres, Redis son adaptadores opt-in, nunca requeridos.

### 2.1. Política de evolución y compatibilidad

**Dirección acordada con el autor el 2026-09-05:** construir ahora una base muy
sólida para poder ser más consistente después. La compatibilidad es una
preferencia de diseño importante, no una prohibición absoluta de mejorar un
contrato defectuoso.

Las aplicaciones conocidas del autor todavía no están en producción, lo que
permite afrontar ahora correcciones estructurales con menor coste de migración.
Eso no permite asumir que ningún consumidor externo de Hex dependa del contrato
publicado. Las versiones 1.x ya publicadas siguen sujetas a SemVer.

- **Preservar por defecto.** Preferir cambios internos o aditivos que resuelvan
  bien el problema sin alterar contratos válidos. No renombrar firmas, opciones
  o resultados por gusto, ni reorganizar capas sin un beneficio concreto.
- **Corregir la base cuando compense.** Aceptar cambios incompatibles si eliminan
  inconsistencias, problemas de seguridad, costes operativos o limitaciones
  generales que una solución compatible mantendría o agravaría. Una arquitectura
  más simple y coherente puede justificar una migración puntual.
- **No añadir deuda de compatibilidad sin necesidad.** Un alias, adaptador o modo
  anterior puede facilitar una migración real; debe tener alcance y criterio de
  retirada. No duplicar permanentemente dos semánticas solo por evitar reconocer
  una ruptura, ni eliminar compatibilidad barata y útil por principio.
- **Diseñar para extensiones previsibles, no hipotéticas.** Nuevos proveedores,
  tools o stores deben encajar mediante contratos pequeños y explícitos.
  No convertir cada diferencia de proveedor en una condición del loop central
  ni introducir un framework dentro del framework para usos sin evidencia.
- **Reconocer todos los contratos observables.** Compatibilidad incluye firmas,
  defaults, resultados y errores, esquemas JSON, eventos y su orden, historial,
  snapshots y semántica de cancelación, reintentos y uso. Mantener la aridad no
  basta para considerar un cambio compatible.
- **Comunicar y versionar.** Documentar impacto y migración antes de publicar;
  usar deprecación gradual cuando sea práctica y una major cuando cambie un
  contrato estable de forma incompatible. No publicar cambios estructurales
  silenciosamente como patch ni usar la fase temprana como excepción a SemVer.

### 2.2. Qué justifica un cambio de contrato

Antes de implementar una ruptura, dejar una decisión breve en este documento
con estos puntos; trasladar la migración y el impacto publicado al changelog:

1. **Problema demostrado:** caso reproducible, inconsistencia o limitación
   concreta. Separar lo observado de una hipótesis sobre rendimiento o uso.
2. **Beneficio general:** qué mejora para ExAgent y sus consumidores, no solo
   para la aplicación que motivó el cambio.
3. **Alternativas:** por qué una corrección interna, extensión compatible o
   adaptador no resuelve suficientemente el problema; coste de mantenerlo.
4. **Impacto y migración:** qué contratos cambian, qué consumidores conocidos
   los usan y qué deben hacer. Considerar datos persistidos y efectos externos.
5. **Evidencia:** regresión del problema, tests de contrato y escenarios de
   integración. Si cambia un adaptador, comprobar su backend real cuando sea
   necesario y registrar lo que no se haya podido verificar.
6. **Salida estable:** versión prevista, documentación y criterio para considerar
   cerrado el cambio. Evitar encadenar rupturas pequeñas del mismo concepto
   por no haber revisado antes sus relaciones con las demás capas.

No hace falta una propuesta extensa para cada bugfix. La profundidad de la
justificación y la verificación debe ser proporcional al impacto del cambio.

### 2.3. Base sólida antes de estabilizar

La fase actual prioriza consolidar lo existente antes de multiplicar funciones.
Estos son criterios de cierre, no garantías que ya se hayan demostrado:

- **Contratos coherentes entre capas:** mensajes, outputs, llamadas y resultados
  de tools, errores, uso, eventos e historial tienen significado explícito y
  no cambian accidentalmente al pasar del core al Server o a una Session.
- **Integración de proveedores extensible y honesta:** contrato común pequeño,
  capacidades y restricciones documentadas por backend. Distinguir soporte de
  texto, tools, streaming y salida estructurada; rechazar o explicar una
  capacidad no soportada, nunca degradarla en silencio. Compartir adaptadores
  compatibles donde tenga sentido sin ocultar particularidades necesarias.
- **Tools fiables:** argumentos y resultados validados, identidad de llamadas
  coherente, errores y permisos explícitos, cancelación y reintentos definidos.
  Un fallo no debe repetir silenciosamente un efecto externo; la app sigue
  siendo responsable de la idempotencia y seguridad de sus propias tools.
- **Operación acotada:** propiedad de tareas, cleanup, backpressure, límites de
  contexto/uso y observabilidad comprobados. Medir memoria, concurrencia y
  latencia en escenarios representativos antes de prometer eficiencia.
- **Ergonomía validada:** ejemplos mínimos ejecutables para crear un agente,
  cambiar de proveedor y llamar tools, además de escenarios con estado. Probar
  consumidores de distintos dominios para no diseñar únicamente para un juego.
- **Evolución verificable:** matriz de pruebas offline y de proveedores reales,
  migración de aplicaciones conocidas revisada, cambios de snapshots/eventos
  versionados cuando corresponda, documentación que distingue soporte probado,
  limitaciones y objetivos futuros.

Al cerrar esta consolidación, los contratos públicos revisados pasan a ser una
base estable. Las mejoras posteriores deben preferir extensiones y adaptadores,
con deprecaciones planificadas cuando hagan falta. Estabilizar no significa
congelar el producto ni prometer que nunca habrá otra major: significa reducir
las rupturas estructurales a decisiones excepcionales y bien justificadas.

## 3. De qué nos inspiramos (comparativa)

| Fuente | Qué tomamos de ella |
|---|---|
| **pydanticAI** | Estructura del `Agent` (instructions/tools/output/deps/model/settings/capabilities), `RunContext[deps]`, `UsageLimits`, delegación con usage compartido, taxonomía de los 5 niveles de complejidad, `agent.iter()` (iterar el grafo nodo a nodo). |
| **alloy** | Agente como GenServer supervisado, async dispatch vía PubSub, **context compaction** summary-based, **cost guard** (`max_budget_cents`), **prompt caching**, memory primitive como behaviour, telemetría por capa, `until_tool` para output estructurado. |
| **normandy** | Coordinación multi-agente reactiva (`race`/`all`/`some`), **sesiones distribuidas en tiers**, guardrails (admission control), MCP/A2A, circuit breakers, batch. |
| **Pi Agent** | **Separación de capas** (ai / agent-core / AgentSession / SessionManager / Runtime), `AgentState` explícito, **eventos** (`subscribe`), **árbol de sesiones** con branching/fork/clone, steer/followUp mid-stream, ResourceLoader. |
| **opencode** | **Primary vs subagents**, **permissions** `allow`/`ask`/`deny` con globs (human-in-the-loop), config de agente (mode/steps/task-permissions), **sesiones como árbol** (revert/unrevert), patrón server+SDK+SSE, compaction como agente oculto del sistema. |
| **Anthropic SDK / tool-use** | Loop canónico (tool_use → ejecutas → tool_result → repite; `stop_reason`), `strict:true`, distinción client/server tools. Tu `run/3` ya lo implementa. |

## 4. Mapa de módulos

```
ExAgent (lib)
│
├── Núcleo funcional — EXISTE
│   ├── ExAgent.run/3 · run!/2 · run_stream/3        one-shot: model ⇄ tools
│   ├── ExAgent.RunContext[deps]                     DI + usage + messages + tool info
│   ├── ExAgent.Tool · ExAgent.Tools (deftool)       JSON schema derivado del tipo ::
│   ├── ExAgent.Schema · OutputSchema                Ecto → JSON schema + validate + retry
│   ├── ExAgent.Message · Part                       request/response/usage, serializable
│   ├── ExAgent.ModelSettings · UsageLimits          temperature; límites tokens/requests/tool_calls
│   └── ExAgent.Capability · Capabilities            middleware componible (hooks before/after)
│
├── Layer 1 — Agente con estado — NUEVO
│   └── ExAgent.Server          GenServer supervisado
│         · chat/3 · stream/3 · send_message/3 (async → evento)
│         · AgentState: agent + history + usage + model + status + pending
│         · emite eventos (text_delta · tool_call_finished · run_finished)
│         · steer/2 · abort/1   (cancelar o encolar follow-up)
│
├── Layer 2 — Sesión / Coordinación — NUEVO (agnóstico)
│   ├── ExAgent.Session         GenServer
│   │     · lifecycle: new/join/leave/start/turn/pause/resume/close
│   │     · participantes: humanos + pids de ExAgent.Server (vía Registry)
│   │     · turn policy (behaviour): round_robin · initiative · supervisor · custom
│   │     · shared_state: struct app-defined (Ecto) — "el mundo"; tools acceden vía deps
│   │     · broadcasts SessionEvents por PubSub
│   └── ExAgent.Coordination
│         · delegation_tool  (pydanticAI: agent-as-tool, usage compartido)
│         · handoff          (trivial: mensaje entre procesos)
│         · (futuro) race/all/some
│
└── Cross-cutting — behaviours / adaptadores
    ├── ExAgent.Store           behaviour  ·  snapshots · ETS (dev) → Postgres (prod)
    ├── ExAgent.Provider        EXISTE (behaviour)  ·  OpenAI/Anthropic/ZAI/OpenRouter/Test
    ├── ExAgent.PubSub          behaviour  ·  None | Local Registry | Phoenix.PubSub | custom
    ├── ExAgent.Compaction      behaviour  ·  summary-based; se engancha como capability
    ├── ExAgent.Permissions     (futuro)   ·  allow/ask/deny + approval human-in-the-loop
    └── ExAgent.Telemetry       EXISTE     ·  eventos en todas las capas
```

## 5. Los 5 niveles de complejidad (pydanticAI) y cómo los cubre ExAgent

ExAgent debe servir para cada nivel sin que el superior contamine al inferior:

| Nivel | pydanticAI | ExAgent |
|---|---|---|
| 1. Agente único | `Agent.run()` | `ExAgent.run/3` (one-shot, sin procesos) |
| 2. Delegación (agent-as-tool) | tool que llama a otro agent, `usage` compartido | `ExAgent.Coordination.delegation_tool/2` |
| 3. Hand-off programático | código de app encadena agents | app code entre `ExAgent.Server` (procesos) |
| 4. Graph / FSM de control | `pydantic-graph` (lib aparte) | `ExAgent.Session` + `TurnPolicy` (FSM sobre participantes) |
| 5. Deep agents | planning + files + delegation + sandbox + durable | Session + compaction + delegation + approval + Store durable |

La diferencia clave: en Python/TS los niveles 2–5 son "un agente llama a otro
como tool" porque **no hay procesos**. En ExAgent son **procesos que se
mensajean**, supervisados, con estado real y resumible. Más simple, más robusto.

## 6. Modelo de eventos (convergencia Pi + opencode + alloy)

Regla central: **eventos y telemetry no son lo mismo**.

- `ExAgent.Event` es el contrato de UI/runtime. Lo consumen LiveView, CLI,
  Channels, logs de producto, tests de flujos y cualquier proceso interesado.
- `:telemetry` sigue siendo observabilidad técnica. Lo consumen métricas, OTel,
  dashboards y alertas. Puede emitirse en paralelo, pero no sustituye al evento.

Un evento es un envelope versionado y serializable:

```elixir
%ExAgent.Event{
  version: 1,
  id: "evt_...",
  seq: 12,
  type: :tool_call_finished,
  source: :run,
  occurred_at: ~U[...],
  run_id: "run_...",
  request_id: "req_...",
  agent_id: "agent_...",
  session_id: nil,
  participant_id: nil,
  payload: %{},
  metadata: %{}
}
```

Terminología fija:

- **run**: una invocación completa del loop (`ExAgent.run/3`) para un prompt,
  incluyendo retries y tool calls hasta producir output final o error.
- **run step**: una request al modelo + su response + el batch de tools que esa
  response dispare.
- **session turn**: turno de un participante dentro de `ExAgent.Session`. No se
  usa `turn` para pasos internos del loop, para no mezclarlo con D&D/soporte.

Eventos previstos:

```
:run_started · :run_finished · :run_failed
:run_step_started · :run_step_finished
:message_created
:text_delta · :thinking_delta
:tool_call_started · :tool_call_finished
:usage_updated
:server_request_queued · :server_request_cancelled
:approval_requested
:compaction_started · :compaction_finished
:session_started · :participant_joined · :participant_left
:session_turn_changed · :shared_state_updated · :session_closed
```

Transporte: `ExAgent.PubSub` es un behaviour pequeño, no una dependencia.

- `:none` / `ExAgent.PubSub.None`: default sin side-effects.
- `ExAgent.PubSub.Local`: PubSub local con `Registry` de claves duplicadas.
- `ExAgent.PubSub.Phoenix`: adaptador opcional que llama a `Phoenix.PubSub`
  dinámicamente si la app lo tiene instalado.
- `custom`: cualquier módulo que implemente `broadcast/3` y, si aplica,
  `subscribe/2`.

Los mensajes publicados usan la forma `{:exagent_event, %ExAgent.Event{}}`.
Topics recomendados: `"exagent:agent:<agent_id>"` y
`"exagent:session:<session_id>"`.

## 7. Cómo encajan dominios concretos (demuestra agnosticidad)

- **D&D (caso motor).** DM = `ExAgent.Server` con tools de DM; bots = `Server`
  con tools de jugador; la partida = `Session` (initiative order = TurnPolicy,
  mundo = `shared_state` Ecto). La `Session` es el único writer del mundo; los
  tools reciben en `deps` un servicio/ref de sesión y piden cambios mediante la
  API de la Session. Humanos = LiveView publicando acciones a la Session; tiempo
  real vía PubSub.
- **Soporte multi-agente.** Supervisor = `Session` con TurnPolicy
  supervisor-driven; especialistas = `Server`; handoff = delegación; guardrails
  = capabilities.
- **Pipeline de investigación.** `Session` lineal/ramificada; cada paso un
  `Server`; compaction entre pasos; resultado estructurado (Ecto).
- **Chat asistido simple.** Solo nivel 1: `ExAgent.run/3` + tu propio store.
  No pagas la complejidad de Session.

## 8. Decisiones de diseño clave (con rationale)

- **Alloy/Normandy son referencias, no dependencias runtime por defecto.** Se
  toman sus técnicas (event envelopes, backpressure, compaction, stores por
  tiers, circuit breakers), pero ExAgent no debe wrappear otro framework salvo
  que un adaptador opt-in lo justifique.
- **DB-free, behaviours everywhere.** El framework no posee DB ni cola. Store,
  PubSub, Compaction son behaviours. Evita acoplar a Postgres/Oban/Phoenix
  (lección de alloy y del README actual).
- **Server = conversación con estado; Session = coordinación.** `ExAgent.Server`
  conserva history/usage/model y ejecuta runs. No decide turnos entre
  participantes ni conoce `shared_state`. Eso pertenece a `ExAgent.Session`.
- **Session = FSM sobre participantes.** No es "una partida"; es una máquina de
  estados genérica coordinando N participantes con una política de turnos. Un
  `TurnPolicy` behaviour permite round-robin, initiative, supervisor, o custom.
- **Session es single-writer del `shared_state`.** Los tools nunca mutan el
  mundo directamente. Reciben deps de dominio que llaman a la Session, que
  serializa la actualización, emite `:shared_state_updated` y mantiene invariantes.
- **Multi-agent = mensajería, no tool-calls.** La coordinación usa mensajes
  entre procesos (Registry localiza agentes). La delegación *está disponible*
  como tool para compatibilidad con el patrón pydanticAI, pero no es el
  mecanismo principal.
- **Eventos como contrato de UI.** Phoenix no es requerido: el contrato son
  eventos tipados sobre PubSub. LiveView es un adaptador más.
- **Store persiste snapshots, no procesos vivos.** Nunca se persisten pids,
  closures/captures de tools ni credenciales. Se persisten ids, history
  serializada, usage, metadata y referencias/templates rehidratables por la app.
  Esto evita bloquear el futuro Postgres/multi-nodo desde la Fase 2.
- **Backpressure antes que magia.** `send_message/3` debe devolver `:busy` o
  `:queue_full` de forma explícita. Las colas infinitas son un bug de producto.
- **El run pertenece al Server.** Un guardián por ejecución monitoriza al dueño
  y al worker; al morir el Server cancela el run incluso ante `:kill`, y termina
  al completar, abortar o fallar el worker. La cancelación es asíncrona y no
  revierte efectos externos ni alcanza procesos desligados creados por la app.
  Los permisos, aprobación y estimador de coste se conservan también en cola;
  el Server sigue controlando los identificadores internos y el canal de eventos.
- **Un único contrato de schema basado en Ecto.** Se prioriza la mantenibilidad
  a largo plazo frente a conservar dos ramas para una discrepancia entre el
  schema generado y su changeset. `OutputSchema.json_schema/1` conserva su firma
  original; no se añaden modos, opciones ni campos al agente. Los requeridos
  declarados se respetan incluso vacíos. Los opcionales admiten nulo sin debilitar
  las restricciones reflejadas; `embeds_many` sigue siendo array, nunca nulo.
  Los campos requeridos no admiten nulo, pero sus embeds pueden contener campos
  opcionales: la misma regla se aplica recursivamente a todos los niveles.
  Sin changeset se conserva el fallback que requiere todos los campos. La
  reflexión carga el módulo antes de comprobar sus callbacks para no confundir
  un módulo aún no cargado con uno sin changeset.
- **Cambio observable exige major y migración explícita.** Conservar las firmas
  y resultados no vuelve compatible el nuevo JSON Schema de `final_result`.
  La próxima publicación que lo incluya requiere una major posterior a 1.x;
  este trabajo no cambia versión ni publica. Los consumidores deben declarar
  campos obligatorios mediante `validate_required/2` (embeds con
  `cast_embed/3` y `required: true`), revisar supuestos de presencia/nulos y
  snapshots, y probar el soporte de `anyOf` y las restricciones strict del
  backend real. Los tests offline solo comprueban el payload emitido. La
  reflexión sobre atributos vacíos no representa perfectamente validaciones
  custom o condicionales: el changeset real sigue siendo la autoridad final,
  con los mismos resultados de validación y mecanismo de reintentos.
- **Correcciones de contratos existentes, no nuevos defaults.** El reenvío de
  permisos, aprobación y estimador del Server corrige opciones ya soportadas por
  el run; la cancelación del worker restaura su pertenencia al Server. OpenAIChat
  reenvía el `extra` ya existente para opciones de proveedor (razonamiento o
  selección de herramienta), pero reserva modelo, mensajes, herramientas y modo
  de streaming; los ajustes tipados explícitos prevalecen. Omitir esas opciones
  o dejar `extra` vacío conserva los defaults previos. Las opciones suministradas
  dejan de ignorarse; los runs huérfanos dejan de continuar en segundo plano.
- **Sin motor de graphs genérico al inicio.** La Session + TurnPolicy cubre el
  caso de uso sin la complejidad de un `pydantic-graph` completo. Se evaluará
  si un dominio lo justifica.
- **`strict: true` por defecto** en schemas de tools cuando el provider lo
  soporte (mejor conformidad; lección de Anthropic).

## 9. Estado actual y no-goals

**Hecho (núcleo funcional):** loop, providers (OpenAI/Anthropic/ZAI/OpenRouter/Test),
deftool, output estructurado Ecto, streaming lazy, capabilities, UsageLimits,
telemetría, serialización de history.

**No-goals explícitos (al inicio):**
- No motor de graphs/FSM genérico tipo pydantic-graph.
- No MCP server propio (sí client en fases tardías).
- No A2A entre nodos distribuidos hasta que Store Postgres lo habilite.
- No RAG/embeddings/vectores dentro del core (vivirá como capability opcional).
- No persistir credenciales, pids, refs ni captures de funciones en Store.

Ver `ROADMAP.md` para el plan de ejecución por fases.
