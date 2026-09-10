# ExAgent: investigacion y propuesta de consolidacion

> **Investigación histórica, no instrucciones actuales ni contratos nuevos.**
> Conserva las fuentes y observaciones de su fecha. Las decisiones adoptadas están
> en [diseño](../../architecture/design.md); los siguientes pasos están en la
> [hoja de ruta](../../development/roadmap.md).

Fecha de consulta: **2026-09-08**. Estado: **propuesta para discutir, no contrato
aprobado ni funcionalidad implementada**. Complementa [DESIGN.md](../../architecture/design.md) y
[ROADMAP.md](roadmap.md); no sustituye sus decisiones vigentes.

Seguimiento 2026-09-09: [ACTION_PLAN, seccion 7](action-plan.md#7-evidencia-c0-y-primera-unidad-2026-09-09)
contiene las reproducciones C0 y el cierre de C2.1 (permisos invalidos). Los
hallazgos de abajo describen la base auditada anterior a esa correccion.

## 1. Recomendacion ejecutiva

**Conservar la arquitectura por capas, consolidar sus garantias y preparar una
major coherente si los contratos revisados lo requieren. No reescribir ExAgent
ni convertirlo en la suma de funcionalidades de otros frameworks.**

La oportunidad no es tener mas tipos de agentes: es que una operacion conserve
su significado al pasar del loop a streaming, a un proceso supervisado, a una
delegacion y a una recuperacion. La ventaja defendible de BEAM es operar muchas
ejecuciones concurrentes con aislamiento y ownership explicitos. No garantiza
respuestas mejores del modelo, inferencia mas rapida ni efectos exactly-once.

Propuesta de observabilidad: **OpenTelemetry nativo de Erlang/Elixir, OTLP como
transporte y Langfuse OSS como primer backend de referencia provisional**.
**Opik es la alternativa principal**, no una herramienta obsoleta que haya que
descartar. La eleccion definitiva debe pasar una prueba de interoperabilidad,
privacidad y operacion. El framework no debe depender de ninguno de los dos.

Cambiar el endpoint no migra automaticamente datasets, prompts, evaluadores,
permisos o historicos. OTel reduce acoplamiento; no elimina todos los costes de
migracion ni permite predecir que empresa o producto durara mas.

## 2. Alcance y evidencia

- Revision estatica de implementacion, tests y documentos de ExAgent, en el
  commit local `c08125be71eada363d08ca463cc7df2ea7855e4a`.
- Consulta de documentacion oficial, codigo, licencias, releases y API de Hex;
  Context7 para Pydantic AI, Langfuse y OpenTelemetry Erlang/Elixir.
- Comparacion selectiva de Python, TypeScript y Elixir. No es un censo de todos
  los frameworks; Java, .NET, Go y Rust no se han auditado en profundidad.
- No se han modificado APIs, dependencias ni las aplicaciones Dragonex y
  WhoamAI. Sus contratos y necesidades de migracion aun no estan inventariados.
- No se han ejecutado proveedores pagados, Postgres, plataformas de tracing ni
  benchmarks comparativos. Una fuente describe su producto; no certifica su
  comportamiento dentro de ExAgent.
- No se ha sincronizado Git: la rama local indicaba un commit por delante y
  tres por detras de `origin/main`. El diagnostico corresponde al commit citado,
  no a cambios remotos pendientes de integrar.

**Verificacion local:** `EXAGENT_OFFLINE=1 MIX_ENV=test mix test` se detuvo
inicialmente por ausencia de Hex. Se instalo Hex 2.5.1 solo en un `MIX_HOME`
temporal y se ejecuto:

```bash
MIX_HOME=/tmp/opencode/exagent-research-mix EXAGENT_OFFLINE=1 MIX_ENV=test mix test
```

Resultado: **310 tests pasan, 28 excluidos**, semilla `472977`, Elixir 1.20.3 y
OTP 29. Dos warnings preexistentes de aliases sin usar en
`test/exagent/scenarios/server_concurrency_test.exs:14`. Se excluyeron Postgres y
proveedores reales; esto no verifica su compatibilidad. No se cambiaron las
versiones del proyecto ni su lockfile.

En este informe, **observado** significa visible en codigo/documentacion;
**pendiente** significa que falta una reproduccion especifica, una medida o una
prueba de backend. Que la suite existente pase no cierra los gaps de cobertura.

## 3. Conceptos que conviene fijar

| Concepto | Significado propuesto | No implica |
|---|---|---|
| Model | Backend y estado/configuracion de inferencia; un adaptador traduce su protocolo. | Memoria o autoridad sobre herramientas. |
| Agent | Definicion reutilizable: instrucciones, tools, dependencias, output y politicas. | Un GenServer ni una conversacion concreta. |
| Run | Una ejecucion del loop con llamadas al modelo y tools. | Una sola request HTTP. |
| Conversation | Continuidad entre runs, historial y referencias a artefactos. | Un proceso permanentemente vivo. |
| Server | Owner opcional de conversacion y ejecuciones, con admission control. | Workflow durable. |
| Session de ExAgent | Coordinacion de participantes, turnos y estado compartido. | Una Session de OpenAI SDK ni un grafo generico. |
| Workflow | Coordinacion de pasos, esperas y efectos, con o sin decisiones LLM. | Multiagente o recuperacion durable por defecto. |
| Harness | Entorno de ejecucion: loop, tools, contexto, permisos y controles operativos. | Sandbox ni inteligencia del modelo. |

Hay que revisar las afirmaciones de `DESIGN.md:44-46,217-219,322-325`:
**agent-as-tool y proceso supervisado son dimensiones ortogonales**. Una tool
puede delegar en una tarea supervisada; un workflow puede componer funciones.
Python y TypeScript tambien tienen procesos y runtimes de ejecucion durable.
OTP facilita aislamiento y supervision, pero no resuelve automaticamente
transacciones distribuidas, mailboxes acotados o cancelacion remota.

El behaviour actual de proveedores se llama **`ExAgent.Model`**
(`lib/exagent/model.ex:32-83`), no `ExAgent.Provider`. Conviene corregir el mapa
documental antes de proponer nombres nuevos.

## 4. Que conservar de ExAgent

- Core one-shot, Server y Session opcionales; uso sencillo sin DB ni Phoenix.
- Behaviours pequenos para modelos, almacenamiento, PubSub y compactacion.
- Ecto como autoridad de validacion final, sin dos semanticas paralelas de
  schema mantenidas exclusivamente por compatibilidad.
- Historial con identidad de tool calls y resultados; serializacion JSON
  portable en vez de persistir procesos o funciones vivas.
- Ownership del worker, guardian del Server, aislamiento de excepciones y
  pruebas de abort/crash, incluida la muerte del owner con `:kill`.
- Separacion de eventos de runtime y `:telemetry`.
- TestModel, adaptador Req de pruebas y transporte MCP sustituible: buenos
  puntos para ampliar pruebas deterministas y de conformidad.

Fuentes locales: `lib/exagent/server.ex:576-619`,
`test/exagent/server_ownership_test.exs`,
`test/exagent/output_schema_contract_test.exs`,
`test/exagent/correctness_fixes_test.exs`.

## 5. Gaps de consolidacion

Estos hallazgos priorizan investigacion y pruebas, no autorizan por si solos
cambiar contratos. Cada ruptura necesita problema reproducido, alternativas,
impacto, migracion y criterio de cierre conforme a `DESIGN.md:95-113`.

| Prioridad | Observacion y evidencia local | Consecuencia / verificacion pendiente |
|---|---|---|
| P0 | `run_stream/3` usa una ruta sin `drive/1`; el loop tiene ademas `stream_text: true`. Resultados y estado del modelo difieren (`lib/exagent.ex:171-207,323-404`; TestModel: `lib/exagent/models/test.ex:54-69`). | Streaming no debe cambiar validacion, limites, permisos o significado del resultado. Faltan escenarios de paridad con tools y output estructurado. |
| P0 | SSE recibe cualquier mensaje y descarta `:unknown`; separa frames solo con `\n\n` y descarta JSON invalido (`lib/exagent/providers/sse.ex:36-110`). La request HTTP empieza al construir el stream (`lib/exagent/providers/openai_chat.ex:118-150`). | Probar preservacion de mensajes ajenos, CRLF, truncado, errores y abandono sin consumir; medir buffers/mailbox. No llamar lazy a toda la operacion. |
| P0 | Se decodifican argumentos JSON, pero no se validan contra el schema antes de la closure (`lib/exagent.ex:630-653`; `lib/exagent/tools.ex:150-159`). | Probar tipos, requeridos, extras y resultados no serializables. Un schema enviado al modelo no protege un efecto externo. |
| P0 | `Permissions.new!/1` admite acciones no reconocidas; `resolve/3` las conserva y el loop solo bloquea `:deny` (`lib/exagent/permissions.ex:46-52,73-81`; `lib/exagent.ex:614-625`). | Reproducir configuracion invalida y exigir rechazo/fail-closed. El default documentado `:allow` es otra decision, no este defecto. |
| P0 | Delegation reenvia solo `deps`, suma uso tras exito y no transmite permisos, estimador ni presupuesto compartido (`lib/exagent/coordination.ex:26-30,73-82`). | Contabilidad agregada posterior no equivale a admision sobre todo el arbol. Probar hijos paralelos, fallidos y anidados. |
| P0 | Errores terminales pierden el estado parcial; Server integra/checkpointa el resultado exitoso, no el progreso de un run fallido (`lib/exagent.ex:545-587,677-725`; `lib/exagent/server.ex:420-433`). | Una tool puede producir un efecto antes del fallo posterior. Duplicacion real no reproducida; hace falta historial de efectos y uso parcial antes de definir retry/recuperacion. |
| P0 | El retorno `{:error, reason}` de Store se ignora; checkpoint solo registra excepciones (`lib/exagent/server.ex:795-813`; `lib/exagent/session.ex:502-513`). Server responde antes del checkpoint (`server.ex:426-428`). | Definir si el ACK significa terminado en memoria o confirmado durablemente. Probar errores retornados, crash entre efecto/checkpoint y versiones de snapshots desconocidas. |
| P1 | Compactacion ignora tokens de ToolCall/ToolReturn/Thinking, corta por numero de mensajes y solo trata historia anterior al run (`lib/exagent/compaction.ex:30-41,103-120,143-160`). | Probar pairing, instrucciones, outputs grandes y crecimiento dentro de un run. Separar historial autoritativo de contexto enviado al modelo. |
| P1 | Session tiene transiciones que revisar: pause/leave/resume, join repetido, handoff sobre estado opaco y restauracion con otra policy (`lib/exagent/session.ex:251-281,401-449,529-559`). | Reproducir secuencias y probar invariantes de roster/current/policy. Mas politicas no resuelven una FSM inconsistente. |
| P1 | MCP envia llamadas pendientes concurrentes pese a documentar serializacion; el timeout del caller no expira `pending` internamente (`lib/exagent/mcp/client.ex:27-33,176-184,303-343`). | Probar caller muerto, timeout, respuesta tardia, cancelacion y limite de pendientes. Cancelar localmente no cancela la tool remota. |
| P1 | Solo hay cuatro eventos telemetry documentados; falta correlacion de requests/tools. El Server pierde `usage.details` y ciertos payloads de eventos (`lib/exagent/telemetry.ex:9-14`; `lib/exagent/server.ex:714-743,847-862`). | No basta con conectar un exporter para tener trazas completas. Revisar identidad, terminales, coste/cache y output async estructurado. |

Otras divergencias a caracterizar: `ModelProfile` es advisory, no una negociacion
aplicada; Anthropic streaming no ensambla tool calls en la ruta inspeccionada
(`lib/exagent/providers/anthropic.ex:378-417`); el `strict: true` anunciado en
DESIGN no se emite en los encoders actuales. La matriz de nueve modelos reales
usa OpenRouter/OpenAIChat, no nueve protocolos independientes.

El codec JSON tampoco elimina secretos serializables de history, metadata o
shared_state. "No persistir el objeto model con API key" y "ningun snapshot
contiene secretos" son garantias diferentes.

## 6. Frameworks y harnesses

Referencias consultadas, no ranking por estrellas ni benchmark de calidad:

| Proyecto / corte versionado | Decision interesante | Que no copiar |
|---|---|---|
| [Pydantic AI v2.41.0][pai], 2026-09-08, MIT | Validacion, deps, toolsets, deferred tools, pruebas y observabilidad integradas con un loop tipado. | Trasladar cada clase/hook a Elixir o asumir que schema equivale a enforcement. |
| [Pydantic AI Harness v0.29.1][pai-harness], 2026-09-08, MIT | Separar harnesses opinionados y capacidades experimentales del core. | Incluir shell, filesystem o memoria especializada en todo agente. |
| [OpenCode v1.18.29][opencode], 2026-09-04, MIT | Control visible de ejecucion, permisos, subagentes, compaction y servidor desacoplado de clientes. | Defaults de asistente local confiable en una biblioteca para SaaS multiusuario. |
| [LangGraph 1.2.11][langgraph], 2026-08-11, MIT | Checkpoints por pasos, interrupcion y recuperacion con semantica explicita. | Un motor de grafos antes de demostrar que las capas actuales no bastan. |
| [Deep Agents 0.7.13][deepagents], 2026-09-02, MIT | Harness opinionado sobre un runtime; tools, contexto y delegacion como composicion. | Tools incorporadas que amplian autoridad sin ser obvias para el consumidor. |
| [OpenAI Agents SDK Python v0.22.1][oai], 2026-09-08, MIT | Diferenciar handoff, agent-as-tool, Runner y estado serializable de aprobacion. | Suponer que todos los guardrails cubren todas las herramientas o que rechazar output revierte efectos. |
| [Pi v0.85.1][pi], 2026-09-05, MIT | Loop pequeno, proyeccion de contexto separada e historial versionado. | Convertir decisiones minimalistas de producto en ausencia de garantias del framework. |

### Pydantic AI: la referencia principal

Su [documentacion de outputs][pai-output] distingue tool/native/prompted output.
La validacion local sigue siendo diferente de las restricciones del proveedor.
Hay excepciones deliberadas: `StructuredDict` y `Tool.from_schema` no aportan
automaticamente la misma validacion que una funcion tipada. ExAgent debe ser
explicito sobre el subconjunto reflejable por Ecto y la traduccion por backend.

Los [toolsets][pai-toolsets] aportan agrupacion, filtrado y lifecycle por run.
La leccion no es crear muchas abstracciones: es que tools locales, MCP y
delegacion compartan identidad, controles y cleanup sin rutas de escape.

Los [deferred tools][pai-deferred] distinguen aprobar una operacion de recibir
su resultado externo. Una continuacion puede ser datos correlacionados por
tool call, sin un worker bloqueado durante horas. La aprobacion necesita un
registro autoritativo del servidor; historial/aprobaciones enviados por el
cliente no constituyen autorizacion.

La [guia de retries][pai-retries] distingue transporte, SDK, workflow, fallback,
tools y validacion de output. Sus limites no son intercambiables: request logica
no equivale a intento HTTP; estimacion de coste no equivale a factura exacta.
La integracion [Temporal][pai-temporal] advierte incluso de uso de subagentes
no propagado al padre cuando se confia en mutaciones de contexto dentro de
actividades. En BEAM conviene devolver contabilidad explicita, no asumir que
compartir una referencia resuelve limites globales o replay.

### OpenCode: producto y frontera de confianza

Su [politica de seguridad][opencode-security] dice que **no es un sandbox** y
que sus permisos son una funcion de UX, no aislamiento. Una biblioteca usada
en aplicaciones debe separar autorizacion del actor/tenant, aprobacion humana
y autoridad efectiva del proceso ejecutor.

El [codigo de compaction][opencode-compaction] combina presupuesto de contexto,
poda de resultados y resumen. Los valores concretos responden a un coding
harness, no a cualquier dominio. Sus eventos distinguen fronteras durables de
deltas efimeros; eso no convierte todo SSE en replay fiable o backpressure.

### Recuperacion no es reinicio

LangGraph documenta checkpoints `sync`, `async` y `exit`, con diferentes
ventanas de perdida; [interrupt][langgraph-interrupt] reejecuta el nodo desde
su comienzo, no congela una pila arbitraria. En ExAgent, checkpoint tras run
es persistencia conversacional, no reanudacion segura en mitad de una tool.

La ventana dificil es siempre: **efecto externo realizado, resultado todavia
no registrado**. Se necesita idempotencia en el destino o reconciliacion;
cuando no exista, puede haber un resultado desconocido que no deba reintentarse
a ciegas. Supervision, snapshots, outbox y cancelacion no dan exactly-once
sobre una API remota arbitraria.

## 7. Reutilizar dentro de Elixir

| Proyecto / version Hex consultada | Licencia principal | Uso razonable en ExAgent |
|---|---|---|
| [Jido 2.3.3][jido] | Apache-2.0 | Referencia de agente como datos + directivas, runtime opcional y distincion journal/checkpoint. No anidar otro runtime sin necesidad. |
| [ReqLLM 1.22.0][reqllm] | Apache-2.0 | Candidato para un adaptador estrecho detras de `ExAgent.Model`; delegar transporte, no permisos/loop. |
| [LangChain Elixir 0.13.1][langchain-ex] | Apache-2.0 | Referencia de mensajes y streams. Su adaptador ChatReqLLM demuestra que puede reutilizarse transporte conservando el loop propio. |
| [Ash AI 1.0.2][ash-ai] | MIT | Adaptador de tools para aplicaciones que ya tienen Ash; respetar actor, tenant y politicas. No exigir Ash a todos. |
| [Alloy 0.12.4][alloy] | MIT | Comparacion de loop/middleware y separacion de runtime; API pre-1.0, no garantia de madurez por existir. |
| [Normandy 1.3.0][normandy] | MIT | Estudiar coordinacion y fallos distribuidos; sus decisiones de persistencia difieren del JSON portable de ExAgent. |
| [Oban OSS 2.24.1][oban] | Apache-2.0 | Adaptador opcional de despacho persistente y retries. No almacena por si mismo una continuacion del agente ni asegura efectos exactly-once. |

**ReqLLM merece una prueba, no una adopcion inmediata.** Revisar compatibilidad
de Elixir/OTP, dependencias transitivas, fidelidad de mensajes, categorias de uso,
retries y cleanup. `StreamResponse` tiene un unico consumidor; recoger metadata
y cerrar recursos requiere un adaptador correcto. Mantener contratos propios
de ejecucion evita trasladar el lock-in a otra biblioteca.

**Oban no deberia envolver un run completo con retry ciego.** Su unicidad de
insercion no es exactly-once; un job rescatado puede repetir efectos. Un worker
tampoco debe dar por terminado el trabajo porque `send_message` lo acepto en
una cola en memoria. Workflows avanzados de Oban Pro son una oferta comercial
separada, no una garantia implicita del adaptador OSS.

## 8. Observabilidad abierta

### Tres responsabilidades distintas

1. **Instrumentacion:** que operaciones medimos y como las correlacionamos.
2. **Transporte/procesamiento:** exportar, agrupar, filtrar y distribuir datos.
3. **Producto:** UI, busqueda, costes, prompts, datasets y evaluaciones.

[OpenTelemetry Erlang/Elixir][otel-erlang] cubre la primera y parte de la segunda.
Sus trazas estan declaradas estables; metricas y logs figuran en Development.
El [Collector][collector] procesa/distribuye; no es una UI IA ni un evaluador.
OpenLLMetry es instrumentacion sobre OTel, no un sustituto de Opik/Langfuse.

### Comparacion para elegir destino

| Opcion | Apertura | Ingestion y encaje | Coste/limite a considerar |
|---|---|---|---|
| [Langfuse v4.30.0][langfuse-license] | Core MIT; directorios enterprise bajo licencia distinta. | [OTLP HTTP protobuf/JSON][langfuse-otel], no gRPC directo. Claves public/secret por proyecto, Basic Auth. Tipos agent/tool/generation documentados. | Web/worker, Postgres, ClickHouse, Redis/Valkey y blob/S3. Retencion automatica, RBAC por proyecto, audit logs y masking servidor son [enterprise][langfuse-ee]. |
| [Opik 2.2.54][opik-license] | Repositorio Apache-2.0. | [OTLP HTTP][opik-otel]; cloud usa API key y workspace/proyecto. Trazas, costes, datasets y evaluacion. | [Self-host OSS sin gestion de usuarios][opik-selfhost]. Stack con multiples servicios/almacenes; Compose local no se anuncia production-ready. |
| [Arize Phoenix v20.8.0][phoenix-license] | Servidor ELv2, source available; no licencia OSS OSI. OpenInference es Apache-2.0. | OTLP HTTP/gRPC; modelo de spans OpenInference, con conversion de ciertos `gen_ai.*`. | Despliegue inicial mas simple con SQLite/Postgres. Evaluar explicitamente las restricciones ELv2 si fuera candidato. No confundir con Phoenix web de Elixir. |
| [OpenLLMetry][openllmetry] | Apache-2.0. | Instrumentaciones de LLM/frameworks sobre OTel. | No aporta una UI/evaluador autocontenido ni hace falta para instrumentar ExAgent nativamente. |
| OTel + Jaeger / Tempo | OTel y Jaeger Apache-2.0; Tempo/Grafana con licencia principal AGPL. | Trazas distribuidas generales; util si la app ya tiene ese stack. | No equivale a gestion de prompts, datasets y experimentos IA. |

La preferencia provisional por Langfuse se debe a la ruta documentada para
lenguajes sin SDK propio, autenticacion self-host y mapeo agent/tool, no a que
sea demostrablemente mas rapido o vaya a sobrevivir a Opik. **Si retencion y
gobierno completos sin licencia comercial son requisitos obligatorios, hay que
revisar esta preferencia.** Opik tampoco incluye gestion de usuarios en OSS.

**Criterio aclarado por el autor el 2026-09-09:** a calidad comparable, preferir
mayor cobertura util sin licencia comercial; aceptar funciones avanzadas
comerciales si una mejora relevante de observabilidad lo justifica. No exige
que toda funcion administrativa sea OSS. Langfuse sigue como candidato
preferente para una integracion nueva, sujeto a la prueba de C6 en ACTION_PLAN.
No se ha demostrado una diferencia grande de calidad de lectura frente a Opik.
Ambos cores son abiertos; la comparacion debe ser por funcionalidades disponibles,
no asumir que Apache-2.0 incluye mas producto que MIT.

Si ya hubiera una instalacion de Opik con historico y evaluaciones utiles,
conservarla seria el punto de partida: esta investigacion no demuestra un
beneficio que justifique migrarla. No se ha comprobado si ese consumidor existe.

No se han auditado todas las dependencias transitivas ni condiciones comerciales.
Licencias permisivas y self-hosting hacen posible conservar una version; no
garantizan mantenerla sin coste ni que futuras releases tengan iguales terminos.

### OTLP no implica equivalencia semantica

Las [convenciones GenAI][genai] siguen en Development. Conviene fijar una
revision/perfil pequeno y probarlo; un prefijo `gen_ai.` no certifica conformidad.

Los mappers consultados muestran diferencias concretas: Langfuse reconoce
`invoke_agent`/`execute_tool`; Opik convierte `invoke_agent` a tipo `general`;
Phoenix sintetiza atributos OpenInference desde ciertos atributos GenAI. Una
peticion aceptada puede producir una visualizacion incompleta o mal clasificada.
Fuentes de codigo: [Langfuse][langfuse-types], [Opik][opik-mapping],
[Phoenix][phoenix-mapping].

Langfuse v4 documenta ademas `x-langfuse-ingestion-version: 4` para ingestion
en tiempo real: sin el header las trazas OTLP directas pueden tardar hasta diez
minutos. Endpoint, version y mapeo importan, no solo la API key.

Tres niveles de portabilidad: **transporte**, **interpretacion IA** y
**datos/producto**. Solo el primero se aproxima a cambiar endpoint y headers.
Scores, experimentos y prompts necesitan adaptadores separados; no deben entrar
en el camino critico del run ni convertirse en autoridad de su estado.

### Arquitectura candidata

```text
ExAgent core / Server / tools / modelos
  -> instrumentacion OTel opcional + metadata permitida
  -> redaccion antes de exportar
  -> OTLP HTTP directo, o Collector opcional
       -> perfil/mapeo Langfuse
       -> perfil/mapeo Opik
       -> backend general de trazas

Runner de evaluacion separado
  -> escenarios/resultados propios
  -> publicacion de scores/experimentos por adaptador
```

- Conservar `:telemetry` para el ecosistema Elixir y eventos de runtime para UI.
  No exportar automaticamente todo PubSub ni crear otro estandar propio de tracing.
- Instrumentar run, request al modelo, tool, delegacion, compaction y checkpoint.
  Registrar retries, cancelacion, errores, duracion, modelo y uso sin inventar
  informacion que el proveedor no devuelve.
- Propagar contexto explicitamente en los limites de Tasks, GenServers y colas;
  el contexto OTel por defecto vive en el process dictionary. Restaurarlo tras
  cada solicitud para no atribuir un tenant/run al siguiente.
- Un span por operacion, no por token ni por toda la vida de un Server. Para
  esperas largas/reanudaciones, valorar nuevas trazas con links e identidad
  persistente; no depender de que el backend renderice todos los links igual.
- Exporter/SDK configurados por la aplicacion. ExAgent no debe reemplazar su
  tracer global ni forzar Collector, credenciales o servicios externos.
- Nada de HTTP desde handlers sincronos de telemetry. Batching, cola acotada,
  exportacion fuera del camino critico y contadores de descarte ante saturacion.
- No sumar el uso agregado del padre como otra generacion facturable ademas
  de sus hijos. Distinguir tokens inclusivos/cache, coste estimado y factura.
  Trazas muestreadas no son un ledger completo de gasto.

### Privacidad y operacion

La propuesta es **contenido desactivado por defecto** en el adaptador, incluyendo
prompts, respuestas y argumentos/resultados de tools. El contenido debe ser
opt-in, limitado y redactado antes de serializar/exportar. Revisar tambien
excepciones, nombres, metadata, URLs, adjuntos y baggage. No prometer acceso al
razonamiento interno del modelo: solo se observa lo que su API expone.

No usar API keys ni informacion personal en baggage; puede viajar a terceros.
Separar proyecto/entorno de aislamiento real de permisos. Self-hosting exige
TLS, control de acceso, backups, retencion y borrado de almacenamiento auxiliar.

Advertencia concreta: el [masking servidor de Langfuse][langfuse-masking] ocurre
despues de persistencia temporal en blob storage y su callback es fail-open por
defecto. No sirve para garantizar que datos sin redactar nunca se almacenen.
Redaccion de lectura/UI tampoco equivale a eliminar originales. Los jueces LLM
pueden enviar datos a proveedores externos aunque la plataforma sea self-hosted.

### Prueba de aceptacion antes de elegir

1. Enviar el mismo escenario desde Elixir a Langfuse y Opik: dos requests LLM,
   tools paralelas, delegado, retry, error y cancelacion. Verificar arbol e IDs.
2. Verificar tokens de cache/reasoning, modelo desconocido y ausencia de doble
   conteo; distinguir dato ausente de cero.
3. Introducir secretos/PII sinteticos en inputs, tools y excepciones; comprobar
   que no llegan a exporter, backend, almacenamiento temporal ni logs.
4. Verificar credenciales, proyecto, entorno y consulta de todas las operaciones
   relacionadas; no confundir etiquetas con autorizacion multi-tenant.
5. Simular backend caido y consumidor lento; medir latencia del run, memoria,
   saturacion, reintentos y descarte sin crecimiento indefinido.
6. Publicar/recuperar un score y documentar las diferencias de IDs y semantica
   entre API de evaluacion y OTLP. Probar una exportacion util del historico.

## 9. Lo que aporta la experiencia de otros equipos

Las siguientes son fuentes tecnicas primarias de Anthropic. Son experiencias
de un mismo proveedor, no un consenso independiente ni benchmarks de ExAgent:

- [Writing effective tools for agents][expert-tools], 2025-09-11: herramientas
  inequivocas, respuestas relevantes y pruebas separadas de los ejemplos usados
  para optimizar. Evaluar la interfaz de una tool, no solo su JSON.
- [Effective context engineering][expert-context], 2025-09-29: seleccion de
  contexto, recuperacion bajo demanda y compactacion. No hay un umbral universal
  ni prueba de que mas subagentes siempre mejoren el resultado.
- [Effective harnesses for long-running agents][expert-harness], 2025-11-26:
  progreso incremental, artefactos de continuidad y verificacion del entorno.
  La demostracion se centra en desarrollo web, no en efectos transaccionales.
- [Demystifying evals for AI agents][expert-evals], 2026-01-09: separar tarea,
  ensayo, transcript y resultado real; calibrar jueces y repetir ensayos.
  Medir estado final y restricciones, no una unica trayectoria obligatoria.
- [Scaling Managed Agents][expert-managed], 2026-04-08: separar harness,
  ejecucion de tools y log durable. Sus mejoras de latencia corresponden a su
  infraestructura, no son predicciones de rendimiento de BEAM.

La sintesis aplicable es: **menos automatismos opacos, mejores herramientas,
estado verificable y evaluaciones propias**. Comparar agente unico, flujo
determinista y multiagente con presupuestos comparables antes de multiplicar
procesos, llamadas o coordinadores.

## 10. Hoja de ruta propuesta

El [plan de accion detallado](action-plan.md), preparado el 2026-09-09, concreta
estas unidades en C0-C8. Anticipa la evaluacion acotada de ReqLLM a la frontera
de proveedores para evitar rehacer adaptadores antes de decidir si reutilizarlos.
La tabla siguiente conserva la propuesta inicial de esta investigacion; el orden
operativo esta en ACTION_PLAN y el progreso real se registra en ROADMAP.

| Unidad | Entrega | Criterio de cierre | Estado |
|---|---|---|---|
| A. Caracterizacion | Matriz de contratos y reproducciones de P0; ejemplos de dos dominios. | Cada riesgo prioritario tiene resultado reproducido, limite documentado o descarte justificado. | Pendiente. |
| B. Loop y tools | Paridad sync/stream; validacion antes de efectos; errores/uso parciales; limites y autoridad de delegacion. | Mismo significado entre core/Server/stream; pruebas de fallos y cancelacion. ADRs y migracion para rupturas. | Propuesta. |
| C. Observabilidad | Adaptador OTel y perfil versionado; prueba Langfuse/Opik. Puede avanzar sobre contratos fijados en B. | Arbol/uso/errores correctos, privacidad y backpressure probados; backend elegido con evidencia. | Propuesta, no integrada. |
| D. Recuperacion | Semantica de ACK/checkpoint; snapshots versionados; FSM Session; aprobacion como datos. | Reinicio en fronteras criticas sin repeticion silenciosa de efectos; resultado incierto explicito cuando proceda. | Propuesta. |
| E. Ecosistema | Evaluar ReqLLM; adaptadores/toolsets solo por necesidad demostrada; durabilidad Oban si se necesita. | Menos responsabilidad propia sin degradacion silenciosa de contratos. | Evaluacion futura. |
| F. Estabilizacion | Guia de major, aceptacion real de backends, evals y medidas de carga, migracion de consumidores. | Evidencia por contrato/proveedor y adopcion revisada en aplicaciones autorizadas. | Pendiente; sin version ni publicacion decididas. |

No bloquear un bugfix interno urgente por esperar a toda la major. Tampoco
publicar como patch cambios observables de schema, errores, permisos, retry o
snapshots. La major ya requerida por el contrato de output pendiente debe
coordinarse con otras rupturas necesarias, no convertirse en excusa para churn.

Medidas utiles: exito verificable por tarea, efectos no autorizados, recuperacion,
coste por exito, TTFT y duracion total, memoria por run, mailbox/cola bajo carga,
overhead OTel activado/desactivado y perdida de informacion tras compactacion.
Registrar modelo/backend/version/fecha, concurrencia y distribuciones, no solo
un promedio. No fijar promesas de rendimiento antes de medir.

## 11. Decisiones de seguimiento

1. **Direccion:** consolidacion incremental con un core pequeno y runtime
   opt-in; breaking changes justificados agrupados, sin reescritura total.
2. **Observabilidad:** aceptar OTel como base y probar Langfuse frente a Opik
   antes de fijar el backend de referencia. Ninguno obligatorio al usar ExAgent.
3. **Alcance de OSS (criterio aclarado el 2026-09-09):** preferir funciones sin
   licencia comercial si la calidad es comparable; aceptar limites comerciales
   avanzados por una mejora relevante y demostrada. Eleccion final pendiente
   de prueba, sin cambiar la instrumentacion neutral.
4. **Recuperacion:** priorizar inicialmente conversacion fiable y aprobaciones
   pendientes, o exigir desde la primera major reanudacion durable de runs
   largos. Son costes y garantias distintos; no asumir lo segundo por usar OTP.

Recomendacion de orden: aprobar la direccion, empezar por A y revisar sus
resultados antes de fijar firmas o formatos nuevos. Inventariar usos reales de
Dragonex/WhoamAI con permiso; no adaptar consumidores silenciosamente.

## Fuentes

Los enlaces versionados fijan el corte consultado. Las paginas de documentacion
sin tag son mutables y deben revalidarse al implementar. Las versiones citadas
no implican que se hayan instalado o probado en este workspace.

[pai]: https://github.com/pydantic/pydantic-ai/releases/tag/v2.41.0
[pai-harness]: https://github.com/pydantic/pydantic-ai-harness/blob/v0.29.1/README.md
[pai-output]: https://github.com/pydantic/pydantic-ai/blob/v2.41.0/docs/output.md
[pai-toolsets]: https://github.com/pydantic/pydantic-ai/blob/v2.41.0/docs/toolsets.md
[pai-deferred]: https://github.com/pydantic/pydantic-ai/blob/v2.41.0/docs/deferred-tools.md
[pai-retries]: https://github.com/pydantic/pydantic-ai/blob/v2.41.0/docs/retries.md
[pai-temporal]: https://github.com/pydantic/pydantic-ai/blob/v2.41.0/docs/durable_execution/temporal.md
[opencode]: https://github.com/anomalyco/opencode/releases/tag/v1.18.29
[opencode-security]: https://github.com/anomalyco/opencode/blob/v1.18.29/SECURITY.md
[opencode-compaction]: https://github.com/anomalyco/opencode/blob/v1.18.29/packages/opencode/src/session/compaction.ts
[langgraph]: https://github.com/langchain-ai/langgraph/releases/tag/1.2.11
[langgraph-interrupt]: https://github.com/langchain-ai/docs/blob/f1eefffeae61e39672ce7420a6657716777334db/src/oss/langgraph/interrupts.mdx
[deepagents]: https://github.com/langchain-ai/deepagents/releases/tag/deepagents%3D%3D0.7.13
[oai]: https://github.com/openai/openai-agents-python/releases/tag/v0.22.1
[pi]: https://github.com/earendil-works/pi/blob/v0.85.1/packages/agent/README.md
[jido]: https://hexdocs.pm/jido/2.3.3/readme.html
[reqllm]: https://hexdocs.pm/req_llm/1.22.0/ReqLLM.html
[langchain-ex]: https://hexdocs.pm/langchain/0.13.1/LangChain.ChatModels.ChatReqLLM.html
[ash-ai]: https://hexdocs.pm/ash_ai/1.0.2/readme.html
[alloy]: https://hexdocs.pm/alloy/0.12.4/Alloy.html
[normandy]: https://hexdocs.pm/normandy/1.3.0/readme.html
[oban]: https://hexdocs.pm/oban/2.24.1/Oban.html
[otel-erlang]: https://opentelemetry.io/docs/languages/erlang/
[collector]: https://opentelemetry.io/docs/collector/
[genai]: https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-spans.md
[langfuse-license]: https://github.com/langfuse/langfuse/blob/v4.30.0/LICENSE
[langfuse-otel]: https://langfuse.com/integrations/native/opentelemetry
[langfuse-ee]: https://langfuse.com/self-hosting/license-key
[langfuse-types]: https://github.com/langfuse/langfuse/blob/v4.30.0/packages/shared/src/server/otel/ObservationTypeMapper.ts
[langfuse-masking]: https://langfuse.com/self-hosting/security/data-masking
[opik-license]: https://github.com/comet-ml/opik/blob/2.2.54/LICENSE
[opik-otel]: https://www.comet.com/docs/opik/integrations/opentelemetry
[opik-selfhost]: https://www.comet.com/docs/opik/self-host/overview
[opik-mapping]: https://github.com/comet-ml/opik/blob/2.2.54/apps/opik-backend/src/main/java/com/comet/opik/domain/mapping/otel/GenAIMappingRules.java
[phoenix-license]: https://github.com/Arize-ai/phoenix/blob/arize-phoenix-v20.8.0/LICENSE
[phoenix-mapping]: https://github.com/Arize-ai/phoenix/blob/arize-phoenix-v20.8.0/src/phoenix/trace/gen_ai/conversion.py
[openllmetry]: https://github.com/traceloop/openllmetry
[expert-tools]: https://www.anthropic.com/engineering/writing-tools-for-agents
[expert-context]: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
[expert-harness]: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
[expert-evals]: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
[expert-managed]: https://www.anthropic.com/engineering/managed-agents
