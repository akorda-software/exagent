# ExAgent — Principios y decisiones de diseño

> Referencia de principios y decisiones. Para el mapa vigente, empieza por
> [Arquitectura actual](overview.md); para prioridades, consulta la
> [hoja de ruta](../development/roadmap.md).
>
> Las secciones 3–7 conservan el contexto arquitectónico original. Sus etiquetas
> «NUEVO»/«futuro» y comparativas no describen el estado actual. Las decisiones
> posteriores de la sección 8, las guías y el [estado verificado](../status.md)
> prevalecen sobre esas descripciones históricas.

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
- **Robusto al operar** — supervisión, telemetría, límites de uso y ownership
  explícito de tareas y conversaciones.
- **Idiomático del BEAM** — aislamiento y coordinación mediante procesos OTP
  cuando el caso lo requiere, manteniendo la definición de agente separada de
  una ejecución o proceso concreto. Delegar como tool también es composición
  válida; la recuperación de efectos necesita contratos adicionales a OTP.

ExAgent es **agnóstico**: no asume ningún dominio. El caso motor (una partida
de D&D en Phoenix con DM + bots + humanos en tiempo real) es el banco de
pruebas, pero el diseño sirve para soporte multi-agente, pipelines de
investigación, editores colaborativos, etc.

Las aplicaciones del autor, incluida WhoamAI, son bancos de pruebas, no la
especificación de la librería. Una solución específica se queda en la aplicación
salvo que revele una necesidad general y encaje en las capas de ExAgent.

## 2. Principios

1. **Core y runtime por capas** (inspirado en Pi). `ExAgent.run/3` es one-shot
   y no exige un Server conversacional; puede utilizar tareas para tools y
   ownership. Sobre él, capas opcionales: Server → Session → Store, usando
   sólo las que el consumidor necesita.
2. **Definición distinta de proceso.** Un agente es configuración reutilizable.
   Runs, conversaciones y coordinadores pueden tener owners supervisados con
   responsabilidades distintas. Reiniciar uno no revierte ni deduplica efectos
   externos; delegación como tool y mensajería OTP son técnicas complementarias.
3. **Ergonomía pydanticAI**. Deps (DI) tipadas vía `RunContext`, `deftool` que
   deriva JSON Schema de anotaciones `::`, output estructurado vía Ecto con
   retry, capabilities como middleware, `UsageLimits`.
4. **Agnóstico y componible**. Session = "interacción con estado coordinada
   entre participantes", no "partida". Model/Store/Compaction/PubSub y policies
   tienen contratos intercambiables; Tool agrupa schema y callable.
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

### 2.4. Investigación de consolidación (2026-09-08)

La revisión de implementación, frameworks/harnesses y observabilidad está en
[la investigación archivada](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/research.md).
Distingue evidencia local, fuentes externas,
limitaciones y propuestas pendientes de decisión con el autor; no introduce
contratos nuevos ni autoriza una reescritura o migración de consumidores.

Puntos a resolver antes de estabilizar: paridad del loop entre sync/stream,
validación y autoridad de tools, uso y efectos parciales, alcance de presupuestos
y permisos en delegación, recuperación y observabilidad desacoplada. La
instrumentación neutral OpenTelemetry se implementó y verificó posteriormente
en C6 (8.6–8.7). Langfuse/Opik como destinos de referencia todavía requieren
aceptación práctica; no hay una plataforma elegida.

Las afirmaciones históricas de este documento sobre proceso por agente,
superioridad frente a Python/TS y equivalencia entre snapshots y durabilidad no
deben interpretarse como garantías verificadas. La investigación propone separar
definición, ejecución, conversación y coordinación, y distinguir recuperación de
estado de reanudación segura de efectos externos. El mapa usa históricamente
`Provider`, pero el behaviour publicado actual se llama `ExAgent.Model`.

El autor ha pedido concretar el plan antes de implementar. El orden operativo,
dependencias y criterios de cierre están en
[el plan histórico de consolidación](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/action-plan.md)
(2026-09-09). Preparar este plan no fija
nuevas firmas, el destino de observabilidad ni el alcance final de reanudación;
esas decisiones se resuelven en las unidades indicadas.

Preferencia del autor aclarada el 2026-09-09: priorizar funciones sin licencia
comercial a calidad comparable; aceptar funciones avanzadas comerciales si una
mejora relevante de observabilidad lo justifica. La selección final exige la
prueba de C6; esta preferencia no autoriza compras ni fija un backend obligatorio.

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
    ├── ExAgent.Model           behaviour  ·  OpenAI/Anthropic/ZAI/OpenRouter/Test
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

Estos niveles no fuerzan una forma de ejecución. La mensajería y supervisión OTP
facilitan ownership e aislamiento en Elixir; otros lenguajes también ofrecen
procesos y runtimes durables. Session/Store no sustituyen un motor de replay de
efectos, y agent-as-tool puede usar tareas supervisadas perfectamente válidas.

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
- **Coordinación por composición.** Mensajería entre owners y delegación como
  tool cubren necesidades distintas. Elegirlas por el flujo y sus garantías,
  sin mantener la delegación como una API de segunda categoría.
- **Eventos como contrato de UI.** Phoenix no es requerido: el contrato son
  eventos tipados sobre PubSub. LiveView es un adaptador más.
- **Store persiste snapshots, no procesos vivos.** No se incluye el modelo vivo,
  pids ni closures de tools. Se persisten ids, history, usage, metadata y datos
  rehidratables con una plantilla confiable. JSON rechaza valores opacos, pero
  no detecta ni redacta secretos que la app haya introducido como strings.
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
- **Conformidad explícita por provider.** Validación local y restricciones strict
  del backend son contratos distintos. No anunciar strict por defecto ni forzar
  tool_choice sin que el adapter lo implemente y su aceptación esté verificada.

### 8.1. C2.1: admisión de tools ante permisos inválidos (2026-09-09)

Primera corrección acotada durante C0, antes de la revisión transversal completa
de C1. Se aplica la excepción del plan para defectos urgentes reproducidos.

- **Problema demostrado:** `new!(default: :approve)` acepta una acción que no
  pertenece a `:allow | :ask | :deny`. `resolve/3` la conserva y el loop solo
  bloquea `:deny`, por lo que ejecuta la tool. Un typo en `:default`/`:rules` se
  ignora y un callback `:approve` no invocable deja pasar `:ask`. El probe de C0
  registró un efecto con acción inválida; las nuevas regresiones dieron 8 fallos.
- **Beneficio general:** una configuración inválida no amplía accidentalmente la
  autoridad de una herramienta, tanto en one-shot como mediante Server.
- **Decisión:** `Permissions.new!/1` valida opciones, forma de reglas y acciones;
  rechaza entradas inválidas con `ArgumentError`. `decide/2` convierte una acción
  seleccionada desconocida en `:deny`; `resolve/3` solo autoriza `:allow` o un
  callback de aridad 1 que devuelve exactamente `:approve`. El loop requiere
  autorización positiva `:allow`, no solamente ausencia de `:deny`.
- **Alternativas:** validar solo el constructor deja expuestos structs públicos
  construidos/modificados directamente; corregir solo el loop oculta typos de
  configuración. Cambiar el default válido a `:deny` ampliaría la ruptura a todos
  los consumidores y no es necesario para este defecto.
- **Impacto/migración:** las configuraciones válidas conservan defaults, orden y
  globs; sin permisos se mantiene `:allow`. Corregir nombres de opciones y usar
  acciones átomo válidas. `:approve` es un retorno del callback, nunca una acción
  de regla/default. Las entradas inválidas antes aceptadas o fallidas con otra
  excepción ahora se rechazan/deniegan explícitamente. No cambia la forma del
  resultado de un run, sus eventos o snapshots; no se añade modo de compatibilidad.
- **Verificación:** nueve tests nuevos, incluidos constructor/resolución y contador
  de efectos en core/Server. Suite offline: 319 correctos, 28 excluidos; compilación
  forzada de 52 archivos con warnings como errores correcta. El probe pasa de un
  efecto a cero. No se atribuye a esta corrección la
  herencia de autoridad de delegados, la paridad de streaming ni un sandbox.
- **Salida estable:** C2.1 cerrada con sus regresiones; C1 y el resto de C2 siguen
  abiertos. Se registra como corrección de entradas fuera del contrato tipado,
  sin alterar defaults válidos. El paquete conjunto sigue requiriendo una major
  por los cambios de schema ya documentados; esta unidad no cambia la versión.

### 8.2. C1/C2: validación local de schemas de tools (2026-09-09)

El autor delega las decisiones técnicas y la implementación al coordinador de
Orca; los contratos se documentan y revisan independientemente antes del cierre.
Decisión implementada y comprobada en el primer gate offline; el cierre final y
sus límites se registran en ROADMAP:

- **Problema:** C0 demuestra que un argumento `"bad"` ejecuta una tool cuyo schema
  exige un entero. Publicar el schema al proveedor no valida el efecto local.
- **Decisión:** usar JSV 0.22.x como validador JSON Schema, detrás de helpers de
  `ExAgent.Tool`, sin exponer sus errores o structs como contrato público. Compilar
  una vez y reutilizar el validador cuando no cambie el schema; rechazar schemas
  inválidos antes de invocar tools. El core conectará la preparación al comienzo
  del run, antes de solicitudes al modelo, y la validación a cada invocación.
- **Entrada:** aceptar keys de mapa átomo/binario de las APIs existentes, comparar
  su representación JSON sin colisiones y conservar los argumentos originales
  para la closure. No convertir strings numéricos, crear átomos, aplicar defaults
  ni ejecutar casts. Rechazar valores no JSON y claves ambiguas átomo/binario.
- **Frontera del schema:** usar resolvers locales/embebidos, sin HTTP/file resolver;
  impedir refs a módulos y extensiones de casting ejecutables de JSV antes de
  compilar. Esto también afecta schemas recibidos por MCP. Debe comprobarse con
  pruebas que ninguna función local es llamada durante validación de un schema
  no confiable. Un schema inseguro/incompatible se rechaza, nunca se debilita.
- **Resultado:** comprobar serialización JSON antes de incorporar un tool return;
  no agregar un segundo sistema de output schema ni exigir Ecto para cada tool.
  El output estructurado final conserva Ecto como autoridad.
- **Alternativas:** escribir un validador parcial propio crea semánticas incompletas
  y deuda de mantenimiento; confiar en el proveedor mantiene el defecto; Ecto
  exclusivamente no cubre schemas externos de MCP. JSV requiere Elixir ~> 1.15,
  compatible con el mínimo ~> 1.17 declarado aquí. Se acepta una dependencia local
  justificada; no otro runtime de agentes.
- **Impacto/migración:** argumentos antes aceptados fuera de schema y resultados
  no serializables dejan de ejecutarse/aceptarse silenciosamente. Revisar schemas,
  claves y datos en tools manuales, macros y MCP; declaraciones válidas conservan
  el callable. Este cambio observable pertenece a la major pendiente y debe tener
  una única semántica, no un flag permanente para desactivar validación.
- **Revisión y evidencia:** un spike inicial usó 0.20; se adoptó 0.22 por los fixes
  upstream de recursión/regex. Cinco hallazgos independientes se reprodujeron en
  ambas versiones y se corrigieron; 25 regresiones Tool pasaron aisladamente y
  el primer gate conjunto dio 516 tests correctos, 28 excluidos. Incluyen controles
  positivos de callbacks JSV y cero invocaciones a través de la frontera segura.
  Fuentes: [JSV](https://hexdocs.pm/jsv/0.22.0/JSV.html) y
  [resolvers](https://hexdocs.pm/jsv/0.22.0/resolvers.html).
- **Correcciones acotadas:** mediante la extensión pública de vocabularios se
  corrigen igualdad numérica recursiva de uniqueItems y longitud por puntos de
  código Unicode; los demás keywords se delegan a JSV. Retirar ese adaptador
  cuando upstream pase las mismas regresiones. Los resultados se codifican y
  decodifican como objetos ordenados para detectar JSON inválido/keys duplicadas,
  incluso en Fragment, conservando el valor original y sus encoders válidos.
- **Límites explícitos:** se admite un único dialecto efectivo draft7 o 2020-12
  por documento; mezcla de dialectos se rechaza, no se interpreta como el padre.
  El preflight de referencias es conservador entre recursos. Defaults inertes se
  omiten sólo de la proyección privada de build para evitar que JSV los escanee
  como schemas, pero los referenciados se conservan íntegros y pueden mantener
  restricciones upstream. No se cambia el schema publicado ni se aplican defaults
  a argumentos. Validar un encoder no garantiza que un encoder con estado repita
  los mismos bytes en otra llamada; callbacks locales no están en un sandbox.

### 8.3. C1: ejecución, errores y recuperación coherentes (2026-09-09)

Decisiones técnicas del coordinador bajo la autonomía delegada por el autor,
contrastadas por dos workers Astra de diseño. Implementación y aceptación se
registran aparte. El primer gate C2-C5 pasó 516 tests offline y las siete
reproducciones C0; revisión final y mediciones posteriores siguen en ROADMAP.

**Problemas y beneficio.** C0 reproduce seis gaps todavía abiertos entre tools,
streaming, delegación y persistencia. Una misma ejecución debe conservar output,
historial, estado Model y uso aunque falle o se consuma como stream. La recuperación
de conversación no debe confundirse con replay seguro de efectos externos.

1. **Definición y runtime.** `%ExAgent{}` es definición reutilizable; run es una
   ejecución; Server es owner opcional de conversación; Session coordina roster,
   policy y shared_state. Delegación como tool y procesos supervisados son
   composiciones compatibles, no una jerarquía de superioridad entre lenguajes.
2. **Error con progreso.** Mantener `{:ok, result}` / `{:error, reason}` en la
   frontera, usando `%ExAgent.RunError{reason: causa, partial: result}` para fallos
   operacionales del loop. Conservar los campos de éxito y añadir identidad/status
   y completitud de uso donde haga falta. El parcial lleva último historial/modelo
   confirmados; texto incompleto de una request queda separado, no como respuesta
   ejecutable. La causa mantiene las categorías anteriores, sin otro modo legacy.
3. **Un loop.** `run/3`, `run/3` con `stream_text: true` y `run_stream/3` comparten
   validación, hooks, límites, tools y finalización. El stream público conserva
   `{:delta, text}` y `{:result, result_completo}` en éxito; en fallo emite un único
   `{:error, RunError}`, nunca otro pseudoresultado exitoso. Deltas son provisionales
   de todas las requests; output proviene del resultado final validado.
4. **Model streaming.** Los adapters devuelven deltas y un terminal
   `{:response, response, final_model}` o error. El dispatcher difiere la llamada
   hasta consumir; ausencia de terminal es error, no éxito vacío. Todos los
   adapters propios migran juntos; los custom tienen una migración explícita.
   Un puente bajo demanda posee worker/transporte y los cancela al detenerse o
   morir el consumidor. Cada enumeración es una nueva ejecución. Suspensión sin
   halt y transporte push requieren límites explícitos, no promesas de detección
   automática de abandono ni de backpressure por usar Enumerable.
5. **Tools y efectos.** Resolver nombre/argumentos efectivos después del hook
   previo; identidad no puede mutar. Aplicar schema y permisos a esa misma tool.
   Recoger todos los outcomes del batch antes de decidir fallo y preservar cada
   resultado/uso. ToolReturn añade estado legible por máquina, incluyendo denied,
   validation_error, failed, unknown y not_executed. Validación y ModelRetry
   explícito pueden pedir corrección; una excepción/timeout de ejecución no
   provoca retry automático de un efecto incierto. Toda llamada de una respuesta
   completa obtiene resolución; la ausencia de resultado no demuestra rollback.
6. **Árbol de ejecución.** La delegación del framework comparte una admisión
   serializada de requests/tools y consumo reconciliado por identidad, con
   restricciones locales adicionales. Políticas descendientes se intersectan:
   una regla hija no elimina deny/ask del padre. `max_steps` sigue siendo local;
   los límites de request del scope abarcan el árbol. Tokens/coste son consumo
   conocido y pueden sobrepasarse por operaciones en vuelo; sin estimador no
   se puede tratar un presupuesto monetario como coste cero. No sumar dos veces
   usage del delegado. IO o llamadas fuera del scope hechas por la app no se
   contabilizan ni restringen mágicamente.
7. **Historial y contexto.** Historial autoritativo conserva eventos de conversación;
   compactación produce proyección para la request, preservando instrucciones y
   parejas call/result. `new_messages` es sufijo real. No ejecutar tool calls de
   una respuesta truncada ni reejecutarlas al restaurar el historial.
8. **ACK y Store opt-in.** Sin Store, confirmación terminal es de memoria. Con Store,
   chat/transición confirma éxito después de save `:ok` de la revisión completa;
   la admisión async sigue siendo cola volátil. Fallo save conserva estado/output
   y devuelve `%ExAgent.CheckpointError{operation, reason, result, revision}`.
   Mientras esa revisión esté sucia, nuevas mutaciones se bloquean; `checkpoint/1`
   reintenta sólo guardar, no tools/model/change_fn. Read/health siguen disponibles
   si el adapter no bloquea. Save síncrono bloqueado no se convierte en durable
   por matarlo; el timeout de IO corresponde inicialmente al adapter.
9. **Terminal runtime.** Server integra progreso de éxito/error, intenta checkpoint
   y emite un terminal propio, sin duplicar el terminal temprano del core. Preserva
   output JSON y Usage.details sin serializar el modelo vivo en PubSub. Abort vs
   resultado se resuelve por el primer mensaje decisivo del owner; late events no
   contaminan el siguiente run. Emisión única del owner vivo no garantiza entrega
   a cada suscriptor ni terminal después de su muerte.
10. **Restore y Session.** Sólo not_found permite arrancar nuevo. Snapshot inválido,
    futuro, id/policy incorrectos o error de load fallan explícitamente sin
    sobrescribir datos buenos. Escribir formato revisado y leer v1 válido mediante
    migración acotada para consumidores 1.x. Policy se reconstruye sólo desde el
    módulo confiable configurado, no elegido por bytes persistidos. Session guarda
    una transición completa por take_turn; join repetido actualiza ref/metadata
    sin duplicar roster; cambios de kind se rechazan. Paused sin actor se resuelve
    al resume; done/closed no resucitan por join. Handoff usa callback explícito
    de policy, conservando cursor; custom sin soporte devuelve error sin mutar.
11. **MCP.** Pending tiene timer y monitor del caller; response/error/timeout/death
    cierran una sola vez y limpian recursos. Timeout retorna error, no replay;
    transporte cerrado vacía pending y no vuelve ready por respuestas tardías.
    La cancelación local no afirma que el servidor remoto haya revertido el efecto.

**Alternativas descartadas:** conservar el loop textual separado, añadir un flag
permanente para resultados parciales, sumar límites después de fan-out, fusionar
globs con last-match para herencia y ocultar save fallido con ACK positivo. Tampoco
se añade un motor universal de workflows o exactly-once para resolver estos casos.

**Impacto/migración:** major conjunta para patrones de error (`error.reason` y
`error.partial`), terminal de adapters custom, semántica agentic del stream,
retries explícitos de tools, autoridad descendiente, ACK con Store y snapshots.
Los callers de checkpoint fallido deben usar `checkpoint/1`, no repetir el prompt
o change_fn; las apps siguen siendo responsables de la idempotencia externa.
Runtime y modelos vivos pueden contener credenciales y nunca se vuelcan completos
en snapshots/trazas. El lector v1 responde a datos reales 1.x y se retirará sólo
con una deprecación futura anunciada; no es un segundo modo de ejecución.

**Aceptación:** regresiones de los probes C0, paridad sync/stream, batches con
éxitos y fallos, cancelación/owner death, competencia por presupuesto, restore
inválido y Store fallido con retry de save sin repetir efectos; revisión Astra
independiente y suite offline. Provider/Store reales y comparación OTel se
verifican por separado. No cambiar versión ni publicar durante esta ejecución.

### 8.4. C3: consolidar adapters propios antes de adoptar ReqLLM

Evaluación acotada el 2026-09-09: ReqLLM proporciona streams de eventos, metadata
separada y cierre explícito mediante StreamResponse. Es una opción válida para
un adaptador futuro, pero no elimina el trabajo de traducir mensajes, uso,
errores y ownership al contrato de ExAgent.

El inventario read-only confirma un consumidor concreto: WhoamAI usa directamente
`OpenAIChat.Config`, `encode_tools/1`, `to_openai_messages/1` y `parse_body/2` dentro
de un adapter que reserva/liquida coste antes de validar output y desactiva retries
HTTP. Dragonex usa OpenRouter y el adapter OpenCode de los commits remotos.

**Decisión de este ciclo:** conservar y consolidar estos adapters y helpers
públicos, incorporar manualmente el adapter OpenCode ya existente sin bump/merge
y corregir el transporte/ensamblado streaming bajo la nueva frontera Model.
Adoptar ReqLLM ahora introduciría a la vez otro contrato de transporte, stream y
metadata sin prueba de equivalencia de esos consumidores. No se duplica un
segundo backend ReqLLM especulativo ni se declara incompatible la biblioteca:
su adopción se reabre con un adaptador estrecho y evidencia que reduzca realmente
responsabilidad propia sin perder contratos.

La comparación fue de documentación/API y consumidores, no un benchmark o una
aceptación de ReqLLM en ExAgent. La primera implementación C3 debe verificar
laziness, cancelación, consumo lento, límites en bytes y framing SSE/JSON de los
adapters actuales. Fuentes: [host integration](https://github.com/agentjido/req_llm/blob/main/guides/host-integration.md)
y [stream migration](https://github.com/agentjido/req_llm/blob/main/guides/streaming-migration.md).

### 8.5. C3: mínimos del decoder HTTP (2026-09-09)

Al cerrar documentación, Hex señaló advisories en los locks heredados de Mint
1.9.0 y HPAX 1.0.3. Son relevantes para el transporte, no una advertencia genérica:
Mint acumulaba un chunk HTTP completo antes de entregarlo al callback, haciendo
ineficaz el límite de bytes de ExAgent durante un chunk enorme sin terminar.

**Reproducción:** un servidor TCP local anuncia un chunk de 256 MiB y entrega
sólo 128 bytes. Con límite de respuesta 64 bytes, Mint 1.9.0 acaba en timeout,
no en el límite de ExAgent. No se generan grandes asignaciones para probarlo.

**Decisión:** exigir Mint >=1.10 y HPAX >=1.0.4 dentro de sus rangos 1.x, además
de Req/Finch, y actualizar esos locks. Un lock local no protege consumidores de
Hex, por lo que el mínimo debe estar en el manifiesto. Sin overrides ni fork.
Estas versiones incluyen límites/streaming de chunks y correcciones de parser
HTTP/HPACK necesarias antes del callback. Restricciones de aplicación más bajas
deben actualizarse; es parte de la major pendiente.

La dependencia Postgrex sólo de tests se actualiza a 0.22.4 para retirar los
advisories de stream/comments y Notifications del entorno de desarrollo. Esas
funciones no se usan en Store; no se afirma explotación ni se añade SQL al core.
La aceptación de Postgres real continúa pendiente.

**Verificación:** regresión TCP anterior, suite/matriz offline y construcción de
docs después del cambio. Fuentes:
[chunks](https://api.osv.dev/v1/vulns/EEF-CVE-2026-56810),
[líneas HTTP](https://api.osv.dev/v1/vulns/EEF-CVE-2026-82728),
[HPACK](https://api.osv.dev/v1/vulns/EEF-CVE-2026-58226).

### 8.6. C6: observabilidad opcional y frontera de exportación (2026-09-09)

Decisión técnica del coordinador bajo la delegación del autor. Implementación
neutral verificada offline; aceptación y límites en ROADMAP y ACTION_PLAN9.
Esta decisión no selecciona una plataforma ni certifica un backend externo.

- **Problema demostrado:** `Telemetry` conserva cuatro fronteras históricas y
  `RunEvent` es un canal explícito de estado rico. Ninguno permite por sí solo
  reconstruir spans de requests, delegaciones y checkpoints con contexto entre
  procesos. Exportar indiscriminadamente eventos/resultados expondría contenido
  y objetos runtime que pueden contener credenciales.
- **Beneficio general:** correlacionar operaciones de una app BEAM mediante OTel
  nativo, conservando el mismo core y permitiendo cambiar el transporte/destino
  sin incorporar una plataforma de observabilidad a la biblioteca.
- **Contrato aditivo elegido:** configuración `observability:` opt-in mediante
  `ExAgent.Observability.OpenTelemetry.new/1`; aplicación a definición/run y
  runtime opcional. La aplicación configura API/SDK, tracer provider, recurso y
  exporter. ExAgent no reemplaza el tracer global ni instala servicios. Contexto
  explícito efímero en límites de Tasks, GenServers y colas; siempre restaurar el
  contexto del proceso al acabar la operación. No persistir contexto en snapshots.
- **Fronteras:** un span por run/request/tool/delegación/compaction/checkpoint,
  preservando identidades existentes y lazy streams. El span de generación acaba
  antes de hooks posteriores/tools. Cancelación debe cerrar operaciones poseídas
  sin depender exclusivamente del `after` de un proceso que puede morir por kill.
  No spans por token ni uno que cubra toda la vida de un Server.
- **Uso:** `gen_ai.usage.*` corresponde a cada request, con cache cuando existe.
  Totales inclusivos del árbol quedan bajo atributos propios diferenciados; no
  volver a sumarlos como otra generación. Coste es el ya observado/reconciliado,
  sin reinvocar el estimador ni fabricar cero cuando es desconocido. Sampling no
  convierte la traza en un ledger. El perfil GenAI propio se versiona y referencia
  una revisión externa concreta, pues esas convenciones son mutables.
- **Privacidad:** contenido desactivado por defecto. El opt-in requiere redactor
  explícito fail-closed y límites previos a atributos/exportación. No volcar model,
  deps, configuración, claves, metadata arbitraria o errores crudos; emplear la
  proyección segura de categorías. No copiar baggage como atributos. El redactor
  no autoriza exportar razonamiento oculto o datos que el proveedor no devuelve.
- **Operación:** exportar fuera del run, con admisión acotada y descarte/fallo
  observable. La auditoría del SDK1.7.0 confirmó que su BSP comprueba
  `max_queue_size` periódicamente, sin cota dura ni contadores de las pérdidas
  requeridas, y no limita el tamaño de cada batch. Se implementa por ello
  `ExAgent.Observability.BoundedProcessor`, extensión opt-in del behaviour público,
  conservando tracer/exporter nativos y elección de provider en la app. La cota
  incluye spans pendientes/en vuelo; cantidad de spans no equivale a bytes de
  un exporter arbitrario. Un `force_flush` asíncrono no es ACK de recepción.
- **Alternativas:** exportar todo PubSub o hacer HTTP desde telemetry mezcla
  contratos, privacidad y latencia; fijar un SDK de Langfuse/Opik acopla el core.
  Duplicar permanentemente el runtime de tracing carece de justificación: preferir
  la API nativa y extensiones acotadas sólo para gaps comprobados.
- **Impacto/migración:** opt-in aditivo, sin nuevos defaults de ejecución ni formatos
  de snapshot. La app aporta sus dependencias/configuración de observabilidad y
  decide qué contenido redactado permite. La major pendiente por C1-C5 permanece;
  esta unidad no cambia versión ni publica. Producto/datasets/scores/prompts y la
  migración de históricos quedan separados del transporte OTLP.
- **Verificación prevista:** exporter local, árbol/IDs, error/retry/cancelación,
  tools paralelas y delegado, checkpoint confirmado/fallido, aislamiento entre
  requests, secretos sintéticos, exporter lento/caído, saturación y overhead.
  La comparación API/UI de Langfuse/Opik exige acceso autorizado y el mismo
  escenario; no se cierra ese gate con HTTP200 ni con tests offline.

Cortes auditados: API1.5.0/SDK1.7.0/exporter1.10.0 en
[`9f0511e`](https://github.com/open-telemetry/opentelemetry-erlang/tree/9f0511e705f18e4b3cc1767b42367ba49e02455a).
Perfil GenAI contra
[`b5d8440`](https://github.com/open-telemetry/semantic-conventions-genai/tree/b5d8440f6f126738fd50f927752cd669772c517b),
que usa `cache_write.input_tokens` y todavía no publica schema URL. No emitir
simultáneamente la denominación antigua para fingir compatibilidad. La omisión
de uso GenAI agregado en run es una decisión de este perfil, no una prohibición
normativa de OTel. La auditoría identificó además metadata Logger residual tras
`otel_ctx.detach`; restaurar también esas claves, preservando metadata ajena.
Los errores retornados por exporters y una respuesta OTLP exitosa no demuestran
recepción durable ni ausencia de rechazos parciales. Processors/exporters ajenos
aportados por la app conservan sus propias garantías de I/O, logging y cleanup.

### 8.7. C6: integración opcional, terminación y límites de privacidad

La primera implementación compiló 72 archivos y pasó 27 tests focales tras corregir
dos fixtures. Dos revisores Astra frescos identificaron fronteras adicionales;
sus fixes pasaron la aceptación final: 579 tests correctos y 28 excluidos en ambos
runtimes, tres consumidores limpios y el probe determinista R3. ACTION_PLAN9
conserva comandos, semillas y límites; la comparación externa permanece pendiente.

- **Compilación opcional, problema demostrado:** un consumidor temporal con API y
  SDK propios compila ExAgent antes del SDK; el processor queda permanentemente
  `sdk_unavailable` por su selección de record en compilación. Los consumidores
  sin SDK también revelaron un warning de acceso a un tuple inválido en la rama
  ausente. **Decisión:** declarar SDK opcional y `runtime: false` en todos los
  entornos, en lugar de sólo en tests, y compilar una rama ausente correcta. La
  arista garantiza el orden cuando la app aporta SDK sin imponerlo al consumidor
  básico ni arrancarlo globalmente. Forzar manualmente recompilaciones en la app
  es un workaround frágil, no la configuración pública. Verificar tres consumidores:
  sin OTel, API sola y SDK nativo, además del proyecto raíz.
- **Ownership y flush:** la reproducción aislada mostró que un exporter que
  atrapa exits conserva el worker y su ETS tras matar al manager. Es un proceso
  propio, no un hijo desligado de terceros: requiere vigilancia independiente de
  callbacks. Una barrera de scheduling en copia en memoria reprodujo la pérdida
  de flush entre selección vacía y reset del bit. Corregir esa sincronización sin
  convertir cada span/flush en otro payload ilimitado. Mantener descarte sin replay,
  capacidad en vuelo y contadores diagnósticos, no una promesa de recepción durable.
- **Terminal sintetizado:** el progreso previo a admitir una request puede decir
  completo/coste cero conocido. Al abortar o perder el worker, el Server no puede
  certificar que ese subtotal siga completo. Corregir conservadoramente el terminal
  sintetizado, preservando subtotales conocidos y sin reinvocar el estimador, para
  que retorno, Event y traza expresen la misma incertidumbre. Los parciales recibidos
  normalmente del core conservan su información confirmada. Una divergencia sólo
  en la traza ocultaría el problema a otros consumidores. Es un ajuste observable
  de completitud de la major pendiente; nunca interpretar un subtotal parcial como
  factura final ni cero consumo por falta de informe.
- **Contexto y contenido:** restaurar Logger al salir no basta si el contexto
  adjuntado está vacío: las claves propias previas también deben desaparecer
  durante el callback. Preservar metadata ajena. Los enteros arbitrariamente grandes
  no pueden consumir un presupuesto fijo de 16 bytes antes del redactor; verificar
  admisión escalar realmente acotada, con casos pequeños y controles positivos,
  sin alterar la validación de tools ni aplicar coerción.
- **Credenciales y bootstrap:** el SDK/OTP guarda los argumentos originales del
  child spec antes de entrar en el processor; puede imprimirlos en informes de
  supervisión. `format_status` propio no elimina esa copia. El contrato exige
  opciones de bootstrap no secretas y resolver credenciales dentro del exporter
  desde entorno/configuración de app. La receta OTLP usa opciones vacías y headers
  externos a `processors:`. No se introduce un filtro Logger global ni un detector
  ficticio de secretos arbitrarios; se documenta y prueba la frontera concreta.

**Migración y beneficio:** ninguna dependencia de tracing/SQL es obligatoria y no
se cambia el provider global. Las aplicaciones que opten por OTel reciben un orden
de compilación fiable y una configuración de credenciales explícita; las que
consumen cancelaciones deben respetar completitud desconocida. No cambian schemas,
historial ni snapshot version. La aceptación incluye regresiones de las fronteras,
matriz offline y ejemplos, con límites externos separados en ROADMAP/ACTION_PLAN.
El processor custom se justifica por gaps concretos del SDK 1.7; reconsiderarlo si
upstream ofrece admisión/counters/lifecycle equivalentes y pasa estas regresiones,
con migración/deprecación en vez de mantener dos implementaciones por inercia.

### 8.8. N01–N03: native OTLP acceptance and lifecycle ownership (2026-09-09)

- **Demonstrated problem:** real exporter1.10/SDK1.7/API1.5 loopback tests show
  boolean attributes converted into strings, successful `partial_success` bodies
  ignored, and native HTTP profiles retained after normal shutdown. A processor
  timeout kills its own exporter worker but does not cancel the native TCP request.
  Stopping the profile alone also leaves the active OTP29 handler/socket alive.
- **Decision/general benefit:** persist local wire/failure/lifecycle probes using
  the official protobuf codec, with explicit callback counters and ownership
  barriers. The exporter is test-only; host applications still select and own
  their transport. Qualify the HTTP recipe rather than claim cleanup or faithful
  delivery from a green HTTP status. OBSERVABILITY7 records the measured contract.
- **Alternatives:** a global before/after profile diff cannot establish ownership
  in a concurrent application. Private PID-derived names, killing shared inets,
  a vendor patch or a second OTLP client would hide ownership defects and expand
  this framework's responsibilities. A bounded disposable-VM diagnostic cancels
  observed requests before removing its own profiles, but cannot reclaim atoms
  or serve as a universal application adapter.
- **Observable impact/migration:** no new production API, snapshot or ledger
  semantics. `exported` means successful exporter callback, not remote accepted
  spans; the observed native exporter cannot report OTLP partial rejection through
  that callback. Consumers of the preview must not infer network cancellation from
  processor timeout/shutdown. General HTTP lifecycle needs upstream fixes or an
  independently accepted isolated exporter boundary. The pending major remains
  unversioned/unpublished; no new compatibility mode is introduced.
- **Verification:** four compiled isolated-VM tests pass (seed576860); initial
  integrated native gate583/28, seed280424. Seven error cases count actual model
  calls/effects and use a blocked real HTTP request as causal barrier. Three direct
  and three processor lifecycle cycles preserve unrelated/default profiles and
  distinguish native atoms/resources from seven tracked ExAgent-owned processes.
  This closes local characterization, not general native cleanup, gRPC or platform
  API/UI acceptance. Independent review and later night gates are in ACTION_PLAN10.

### 8.9. N06: optional SDK compilation on the declared minimum

The frozen-package matrix on Elixir1.17.3/OTP27.3.4.17 reproduced a compiler warning
in `BoundedProcessor.start_link/1` only when SDK records were absent. Its constant
`with` match was tolerated by newer compilers. Consumer-level warnings-as-errors
did not retrospectively reject dependency compilation, so acceptance now checks
that phase's warnings explicitly.

The initial private-helper fix passed 36 minimum-runtime consumer contracts, but
N18's clean Elixir1.20 consumer inferred that helper's constant false return and
reported another impossible `with` match. Final selection therefore happens at
compile time around `start_link/1` itself: absent SDK returns `sdk_unavailable`,
while the SDK-present branch retains the original validation/start path. Its
private validation/default helpers are compiled only where reachable, avoiding
unused-code warnings in older compilers. Loading SDK later still cannot bypass
missing compiled records. There is only one active SDK lifecycle implementation.

Suppressing diagnostics, runtime-only availability and disguising a constant to
evade compiler inference were rejected. No API/default/migration/minimum change
is needed. Isolated actual compilation has zero diagnostics on1.17 and1.20, and
the SDK-present processor passes16 tests; N18 repeats the real TAR consumer matrix
after this final change. Earlier595/28 and the initial TAR are historical gates,
not the final matrix. Detailed red/green evidence remains in ACTION_PLAN10.

### 8.10. Auditoría de testing: fidelidad de IDs en mensajes (2026-09-10)

- **Problema demostrado:** un roundtrip público `Message.to_json/from_json` pierde
  los IDs no nulos de `Part.Text` y `Part.Thinking`, aunque conserva contenido y
  firma. Las fixtures anteriores de igualdad usaban `id: nil` y no discriminaban
  esa pérdida. La reproducción sobre BEAM del baseline devuelve error con IDs
  sintéticos distintos; se trata de un defecto del codec, además del gap del test.
- **Decisión y beneficio general:** conservar esos IDs como campos opcionales en
  el codec. El lector admite datos anteriores sin ID y el escritor no añade una
  key nula a los mensajes que no lo tienen. La identidad suministrada por un
  adapter/consumidor sobrevive a la persistencia y reanudación del historial.
- **Alternativas:** rebajar «lossless» a comparar sólo longitudes/IDs nulos oculta
  pérdida de datos públicos. Un codec paralelo o una nueva versión completa de
  snapshot para un campo opcional no aporta una frontera necesaria aquí.
- **Impacto y migración:** cambia el JSON emitido sólo cuando existe ese ID;
  lectores anteriores lo ignoraban. Leer snapshots antiguos sigue produciendo
  `nil` donde no se guardó un ID; no se reconstruyen IDs perdidos. No cambia la
  omisión documentada de `ToolReturn.usage`, el modelo vivo ni snapshot v2.
  El conjunto de consolidación sigue destinado a una major; no se cambia versión
  ni se publica durante la auditoría.
- **Verificación:** reproducción negativa antes del fix; regresión con igualdad
  de conversación y JSON crudo, IDs distintos, contenido/firma y datos legacy sin
  ID. La aceptación compilada y revisión independiente se registran en
  [auditoría de testing](../development/testing-audit.md).

### 8.11. Auditoría: preservar datos antes de validar/admitir (2026-09-10)

**Problema demostrado.** La auditoría readonly encontró cuatro fronteras sin
oráculo equivalente. Reproducciones offline sobre el baseline compilado usan
adapters Req sintéticos, schema público validado por JSV/Ecto, JSON-RPC MCP local
y callbacks de delegación que consumen sus datos. Los 45 casos temporales producen
24 controles correctos y 21 fallos; son cuatro familias de defectos, no 21 bugs.

| Frontera | Observación negativa | Decisión autorizada |
|---|---|---|
| Usage de OpenAI/Anthropic | Omitir un contador o enviar usage vacío se transforma en cero, complete/known; bajo presupuesto se ejecutan una tool y una segunda request. | Conservar `nil` por dimensión no reportada, tanto omitida como explícitamente nula. Cero explícito sigue siendo conocido; el scope conserva subtotales y decide admisión con sus flags. No inferir consumo desde total/cache. |
| Reflexión OutputSchema | Enum integer/boolean se convierte en strings; exclusión deja pasar valores prohibidos, arrays reciben minLength/maxLength y `is` se omite. | Conservar tipos JSON nativos, mantener mapeo de enums átomo a string y aplicar minItems/maxItems a arrays, minLength/maxLength a strings, incluido `is`. |
| MCP → Tool | `inputSchema: false` y su alias se sustituyen por object permisivo, produciendo `tools/call`. | Seleccionar por presencia, con nombre estándar prioritario; conservar `false` para la frontera Tool que ya soporta schemas booleanos. Fallback sólo cuando faltan ambas keys; datos presentes incompatibles no se vuelven permisivos. |
| Delegación | El builder recibe contexto/args correctos, pero una key átomo válida se busca dos veces como string y el hijo recibe prompt vacío. | Buscar la key JSON equivalente ya presente, sin crear átomos ni alterar los args originales del builder; conservar rechazo previo de colisiones. |

**Beneficio general y alternativas.** La biblioteca no debe perder información
antes de las fronteras que deciden permisos, coste, output y ejecución. Modificar
los fixtures para esperar cero/strings/prompt vacío ocultaría el problema;
desactivar validación, reconstruir uso hipotético o añadir modos legacy duplicaría
semánticas incorrectas. Se corrigen los adaptadores mínimos y se conserva la
responsabilidad de JSV, Ecto y ExecutionScope.

**Impacto y migración.** Usage sin una dimensión deja de certificar consumo/coste
completo y puede bloquear operaciones posteriores bajo presupuesto. Consumidores
deben respetar `usage_status`/`cost_status`, no convertir `nil` en factura cero.
Cambian los schemas emitidos para las validaciones descritas: revisar snapshots
de payload y compatibilidad del backend real. La reflexión sigue siendo aproximada
para validaciones custom/condicionales y conteos de texto distintos de JSON Schema;
no se promete equivalencia universal con un changeset. Specs MCP incompatibles
dejan de recibir defaults permisivos; la opción `prompt_arg` sigue siendo string,
y se preserva la representación átomo/string ya admitida en argumentos.

Estas correcciones pertenecen al contrato conjunto de la major pendiente; no hay
nuevo modo, versión ni publicación. No se autorizan aquí nuevos proveedores,
aprobación persistida, sandbox ni replay de efectos.

La revisión independiente reprodujo dos aristas del primer fix: `true`/`false`
como nombres de miembros Ecto.Enum son strings publicados, distintos de un field
booleano nativo; y `is`/min/max deben intersectarse, también entre llamadas de
validación, no sobrescribirse según su orden. La corrección final consulta el tipo
Ecto del field y conserva bounds acumulados, incluidas contradicciones que deben
seguir sin admitir valores. Cinco regresiones nuevas discriminan estos casos.

**Verificación exigida.** Trasladar las reproducciones a regresiones mantenibles,
incluyendo positivos de cero explícito, schemas string/object y keys string;
comprobar sync/stream, efecto remoto local observado y datos entregados al hijo.
El control MCP de casts/refs ya rechazaba correctamente y debe conservarse.
Compilación y gates integrados con warnings-as-errors, revisión fresca y límites
se registran en [la auditoría](../development/testing-audit.md). Ninguna VM directa
contra BEAM previos sustituye la aceptación compilada de los cambios.

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

Ver la [hoja de ruta vigente](../development/roadmap.md) para las próximas unidades
y [estado](../status.md) para la última aceptación. Los números de tests de las
decisiones anteriores son evidencia de su fecha, no nuevos resultados.
