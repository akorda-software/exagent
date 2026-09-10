# ExAgent: plan de accion para la consolidacion

> **Registro histórico de ejecución y evidencia, cerrado el 2026-09-10.** Los
> estados «pendiente»/«en curso» de entradas anteriores pertenecen a su fecha.
> No es el plan activo. Consulta [estado actual](../../status.md),
> [verificación](../../development/verification.md) y
> [hoja de ruta](../../development/roadmap.md) para continuar.

Fecha: **2026-09-09**. Estado: **ejecucion iniciada con autorizacion del autor**.
C0 tiene evidencia local; C2.1 corrige el defecto reproducido de permisos
invalidos y esta verificada. C1 tiene decisiones registradas en DESIGN 8.2-8.4;
C2-C5 estan implementados y verificados offline tras revisiones Astra bajo Orca.
La unidad neutral de C6 tambien esta implementada y verificada offline; la
eleccion del backend sigue pendiente de comparacion practica autorizada.

Base: [investigacion](research.md), [principios y contratos](../../architecture/design.md#2-principios)
y [estado de ejecucion](roadmap.md). Este documento concreta el orden operativo;
RESEARCH conserva las fuentes y ROADMAP registra avances, evidencia y limites.

## 1. Resultado buscado

Una base con la misma semantica de herramientas, resultados, errores y uso en
one-shot, streaming y runtime con estado; recuperacion con garantias explicitas;
observabilidad opcional y portable; y una migracion coherente de los contratos
que necesiten cambiar. Conservar la ergonomia del caso sencillo sin DB/Phoenix.

**Unidad de trabajo:** problema reproducido, decision, cambio acotado,
verificacion y documentacion. El final de una unidad debe ser util y comprobable,
no depender de una reescritura futura para volver a funcionar.

La durabilidad de ejecuciones arbitrarias, un motor de grafos, RAG incorporado,
nuevos protocolos multiagente y una plataforma propia de monitorizacion quedan
fuera de este ciclo. ReqLLM se evalua antes de ampliar adaptadores; Oban queda
para una necesidad posterior de despacho durable demostrada.

## 2. Orden y dependencias

Orden de ejecucion por defecto: **C0 -> C1 -> C2 -> C3 -> C4 -> C5 -> C6 ->
C7, si se incluye -> C8**. El progreso real esta en ROADMAP y la evidencia inicial
en la seccion 7. C2.1 es la correccion urgente permitida por la regla de abajo.

| Unidad | Entrega | Dependencias para cerrar |
|---|---|---|
| C0. Base y reproducciones | Estado Git/runtime identificado, matriz de contratos y escenarios prioritarios. | Ninguna. |
| C1. Decisiones de contrato | Semantica transversal y migraciones previstas, antes de fijar firmas. | C0. |
| C2. Tools y autoridad | Validacion local, permisos coherentes y errores/retries explicitos. | C1. |
| C3. Ejecucion y proveedores | Loop canonico sync/stream, adapters conformes y transporte acotado. | C1, C2; decision acotada sobre ReqLLM. |
| C4. Recursos y delegacion | Uso parcial/agregado, limites, autoridad descendiente y contexto valido. | C2, C3. |
| C5. Runtime y recuperacion | Ownership, eventos, checkpoints, snapshots y FSM consistentes. | C3, C4. |
| C6. Observabilidad | OTel opcional y backend de referencia probado con el mismo escenario. | C3-C5; requisitos de plataforma aclarados. |
| C7. Aprobacion diferida | Esperas como datos y resolucion tras restart, si se acuerda incluirla. | C2, C4, C5; ampliar pruebas OTel de C6. |
| C8. Cierre y migracion | Matriz real de soporte, carga/evals y guia de major revisadas. | C2-C6; C7 solo si forma parte del alcance. |

El contrato de observabilidad se disena en C1. Su instrumentacion basica puede
empezar tras C4, pero C6 no se cierra sin comprobar C5 y el destino real. La
eleccion Langfuse/Opik no bloquea C0-C5 ni el trabajo neutral de OTel.

Un defecto urgente reproducido puede corregirse antes en una unidad pequena
con regresion. Esto no autoriza a omitir el analisis de contrato ni a introducir
rupturas no relacionadas. No repetir todo el estudio del ecosistema en cada fase.

## 3. Unidades de ejecucion

En los apartados **Zonas**, las rutas abreviadas son relativas a `lib/exagent/`;
el archivo del core se indica expresamente como `lib/exagent.ex`.

### C0. Fijar la base y caracterizar los riesgos

**Trabajo:**
1. Registrar HEAD, diff y divergencia remota; revisar cambios relevantes antes
   de decidir la base de implementacion. Preservar el trabajo local. Una
   sincronizacion de Git no forma parte automatica de este plan.
2. Repetir baseline offline al comenzar la implementacion; registrar Elixir/OTP,
   warnings y exclusiones. Los 310 tests de RESEARCH son evidencia historica,
   no el resultado de esta unidad futura.
3. Inventariar contratos de core/Model, tools, Server/Session, eventos y Store.
   Para cada gap P0 de RESEARCH: reproduccion aislada, observacion esperada,
   impacto y estado confirmado/descartado/pendiente con motivo.
4. Preparar dos escenarios sin dominio incrustado: consulta con output tipado
   y tool de lectura; operacion con efecto simulado, fallo y delegacion.
5. Pedir ubicacion y alcance de lectura de Dragonex/WhoamAI para inventariar
   llamadas, opciones, snapshots y backends usados. Si no estan disponibles,
   marcar desconocido y no afirmar compatibilidad de consumidores.
6. Capturar medidas iniciales de los escenarios offline representativos (latencia,
   memoria y concurrencia), con configuracion reproducible, para comparar C8
   contra el punto de partida y separar overhead local de latencia del proveedor.

**Entrega/cierre:** matriz con columnas contrato, comportamiento actual,
escenario, evidencia, unidad responsable e impacto potencial. Las reproducciones
fallidas pueden vivir aisladas; no dejar la suite normal roja al cerrar C0.
Ningun P0 queda sin clasificacion ni siguiente paso. Esta unidad no exige
redisenar todos los contratos ni reproducir todos los P1 antes de continuar.

### C1. Acordar las semanticas transversales

**Trabajo:**
1. Fijar Agent/Run/Conversation/Server/Session y el behaviour real `ExAgent.Model`.
   Corregir las afirmaciones documentales que confunden supervision y durabilidad.
2. Definir identidad de run, request/intento y tool call; resultado terminal,
   cancelacion y progreso parcial. Contemplar necesidades de aprobacion diferida
   antes de publicar formatos, sin agregar estados hipoteticos si C7 se excluye.
3. Definir errores de validacion corregibles, denegacion, fallo de ejecucion y
   resultado de efecto desconocido; decidir que informacion conserva el caller.
4. Definir alcance de permisos, uso y limites, y significado de ACK/checkpoint.
   Separar historial autoritativo de la proyeccion enviada al modelo.
5. Fijar eventos terminales/deltas, correlacion telemetry y politica de contenido
   del adaptador OTel. Distinguir contrato propio estable y convenciones GenAI
   versionadas externas.

**Entrega/cierre:** decisiones breves en DESIGN con problema, beneficio general,
alternativas, impacto, migracion y verificacion; inventario de rupturas en
CHANGELOG. Los cambios sin ruptura se identifican tambien. El autor ha delegado
las decisiones tecnicas al coordinador; documentarlas y revisarlas de forma
independiente. Consultar al autor solo decisiones de producto, acceso o coste
que no esten cubiertas, no firmas y detalles internos ordinarios.
Cada unidad posterior tiene invariantes concretas y contratos a preservar.

### C2. Unificar el contrato de herramientas

**Zonas:** `lib/exagent.ex`, `tool.ex`, `tools.ex`, `permissions.ex`,
`output_schema.ex`, integracion de MCP y delegacion con el pipeline de tools.

**Trabajo:** validar argumentos antes de invocar; definir validacion/serializacion
de resultados; rechazar configuracion de permisos invalida; normalizar el camino
de autorizacion/aprobacion/ejecucion; separar retry de correccion del modelo y
retry de un efecto externo. Conservar Ecto como autoridad final del output y
corregir las reflexiones que no representan fielmente tipos/validaciones.

**Pruebas de cierre:** tipos/requeridos/extras, errores anidados, reglas invalidas,
denegacion y aprobacion ausente sin ejecutar la tool; excepcion/timeout; batch
con una operacion completada y otra fallida. Tools locales, MCP y delegacion no
evitan controles de su invocacion como tool por usar otra ruta; la autoridad
de las operaciones internas del delegado se cierra en C4. Los resultados/errores
sobreviven segun C1; ningun retry de efecto incierto se introduce como
automatismo silencioso.

### C3. Loop canonico y frontera de proveedores

**Zonas:** `lib/exagent.ex`, `model.ex`, `model_profile.ex`, `models/`,
`providers/`, especialmente `providers/sse.ex`.

**Trabajo:**
1. Hacer una evaluacion acotada de ReqLLM: paridad de mensajes/IDs/uso/errores,
   streaming, cleanup, versiones minimas y coste de dependencias. Concluir
   adoptar adaptador estrecho o conservar providers propios; no esperar a que
   soporte todos los modelos ni convertirlo en una reescritura del framework.
2. Llevar sync y streaming al mismo ciclo model/tools, con resultado final,
   hooks, limites y estado de modelo equivalentes. Resolver cuando empieza la
   request y quien posee/cierra un stream no consumido o abandonado.
3. Robustecer SSE y ensamblado de tool calls de OpenAIChat/Anthropic; conservar
   mensajes ajenos al transporte y acotar recursos.
4. Aplicar capacidades reales por backend y traduccion de schemas. Rechazar
   capacidades no soportadas en vez de degradarlas silenciosamente.

**Pruebas de cierre:** mismo escenario normal/stream con tools, output tipado,
hooks, error y TestModel stateful; frames fragmentados/CRLF/malformados/truncados;
cancelacion y abandono; proveedor sin capability. Matriz por protocolo/backend,
no solo por nombre de modelo. La aceptacion real se prueba de forma acotada al
tocar un adaptador, si esta autorizada; si no, se registra pendiente para C8.

### C4. Presupuesto, delegacion y contexto

**Zonas:** `coordination.ex`, `run_context.ex`, `usage_limits.ex`,
`cost_guard.ex`, `compaction.ex` y manejo de uso en core/runtime.

**Trabajo:** conservar uso parcial y detalles cache/reasoning; definir admision
del arbol de delegacion antes de fan-out; reconciliar consumo sin doble conteo.
Presupuesto, concurrencia, deadline y limite de pasos son controles separados.
Definir herencia/restriccion de autoridad descendiente y contabilizar compaction
u otras llamadas auxiliares. Coste desconocido debe seguir siendo desconocido.

Separar historial y contexto proyectado; preservar instrucciones y parejas de
tool call/resultado al compactar. Contar o estimar explicitamente tools y grandes
resultados, y controlar el crecimiento dentro de un mismo run.

**Pruebas de cierre:** hijos paralelos compitiendo por el ultimo presupuesto,
delegado fallido, cancelacion sin usage final, estimador ausente, permisos de
hijos y compaction repetida en limites de call/result. Limites preventivos y
umbrales retrospectivos se documentan sin prometer una factura exacta.

### C5. Runtime, eventos y persistencia fiables

**Zonas:** `server.ex`, `session.ex`, sus snapshots/policies, `event.ex`,
`store/`, `mcp/client.ex` y ownership de tareas/transportes.

**Trabajo:** integrar estado parcial definido en C1; preservar detalles de uso
y payloads async; definir entrega/orden/identidad de terminales y deltas tardios.
Tratar retornos de error y excepciones de Store; implementar el ACK decidido;
validar versiones/datos corruptos y compatibilidad de policy al restaurar.
Mantener coherencia de Session en pause/leave/resume, join repetido y handoff.
Cerrar pendientes MCP al morir caller, expirar timeout o parar transporte.

**Pruebas de cierre:** muerte de owner/worker, abort contra finalizacion, consumer
lento, cola llena y ausencia de huerfanos; Store que devuelve error y que eleva;
restart en fronteras de checkpoint; snapshot antiguo/futuro/corrupto; secuencias
de FSM y respuestas MCP tardias. ETS prueba el contrato local; Postgres real
requiere verificacion propia. Sin afirmar reanudacion de efectos en vuelo que
este modelo de snapshots no soporte.

### C6. Instrumentacion y backend de referencia

**Trabajo:** implementar instrumentacion opcional usando OTel nativo, sin crear
otro estandar ni reemplazar la configuracion global de la aplicacion. Propagar
contexto entre procesos y limpiar el contexto tras cada solicitud. Instrumentar
run/model/tools/delegacion/compaction/checkpoint con perfil GenAI versionado.
Exportacion asincrona acotada, contenido opt-in y redaccion previa a exportar.

Primero usar exporter de prueba local sin red. Despues ejecutar el mismo escenario
en Langfuse y Opik, con versiones fijadas, acceso autorizado e inputs sinteticos.
Para la primera prueba no hace falta un modelo de pago: TestModel puede generar
las operaciones observadas. Collector es opcional. Si ya hay una instancia util
de Opik, probarla como punto de partida antes de justificar una migracion.

**Pruebas de cierre:** jerarquia e IDs, uso/cache/coste sin duplicados, errores y
cancelacion, ausencia de contenido no autorizado, proyecto/entorno correctos,
backend caido/saturacion sin bloquear runs; overhead desactivado/activado.
Comparar informacion recuperada por API/UI, no solo HTTP 200. Registrar costes
operativos y funciones OSS necesarias; elegir backend segun estos resultados.
Un ejemplo reproducible debe funcionar configurando endpoint y credenciales en
la app. No usar telemetria muestreada como contabilidad autoritativa.

**Regla de eleccion aclarada el 2026-09-09:** preferir mayor cobertura util sin
licencia comercial cuando la calidad sea comparable. Aceptar funciones avanzadas
comerciales si existe una ventaja relevante y demostrada en observabilidad.
Langfuse OSS sigue como candidato preferente para una integracion nueva por su
encaje documentado; no se ha demostrado una superioridad de lectura frente a
Opik. Ambos ofrecen un core abierto y tienen limites de producto distintos:
MIT frente a Apache-2.0 no basta para decidir cual cubre mas necesidades sin pago.

Comprobar tareas concretas con el mismo escenario: localizar el fallo introducido,
reconstruir delegacion/retries, inspeccionar inputs/resultados permitidos, explicar
coste/cache y filtrar runs relacionados. Registrar aciertos, informacion perdida,
pasos y tiempo de diagnostico; contrastar licencia de las funciones realmente
usadas y carga de operacion. Una diferencia de etiquetas o apariencia no basta
por si sola para justificar el compromiso comercial. No decidir por estrellas
ni por una prediccion de supervivencia del proveedor.

### C7. Aprobacion diferida, alcance condicionado

**Recomendacion pendiente de acuerdo:** incluir aprobaciones pendientes
serializables, sin prometer un motor universal de ejecucion durable.

**Trabajo:** representar la operacion pendiente y su resolucion sin mantener un
worker bloqueado. Vincular aprobacion a identidad, herramienta, argumentos y
autoridad definidos por la app; revalidar al continuar. Persistir y versionar la
continuacion necesaria, conservando presupuesto y operaciones ya resueltas.

**Pruebas de cierre:** aprobar/denegar tras restart; resolucion duplicada o tardia;
argumentos alterados, actor incorrecto, cancelacion durante espera, expiracion y
cambio de version incompatible. Un unico efecto autorizado en los casos
deduplicables; incertidumbre explicita cuando no se pueda garantizar el resultado.
Completar trazas de suspension/reanudacion y migracion de snapshots.

Si se pospone C7, mantener documentado el alcance sincrono actual de `approve`;
no agregar una API publica de continuaciones a medio implementar. C8 debe
indicar expresamente si C7 esta incluido o fuera de la version candidata.

### C8. Aceptacion, medidas y migracion de la major

**Trabajo:** escenarios de dos dominios, evals deterministas y, con autorizacion,
modelos reales. Medir exito verificable, coste por exito, TTFT/duracion, memoria,
mailboxes/colas y overhead de observabilidad con configuracion reproducible.
Definir umbrales a partir de baseline y objetivos de uso, no inventar cifras.

Probar versiones de Elixir/OTP declaradas soportadas y empaquetado sin SQL/OTel
obligatorios para el caso sencillo. Preparar guia de APIs/defaults/errores/eventos
y snapshots; actualizar ejemplos ejecutables y matriz por backend. Inventariar
datos persistidos y planificar migracion/rollback: reinstalar el paquete anterior
no garantiza leer snapshots nuevos. Validar consumidores conocidos autorizados.

**Cierre:** P0 resueltos o descartados con evidencia; limitaciones restantes
explicitamente aceptadas para el alcance; regresiones y verificaciones reales
pertinentes registradas; migracion revisada. Resultado: candidata a major,
no publicacion automatica. El cambio de schema ya pendiente obliga a una major
posterior a 1.x; no se cambia version ni se publica por ejecutar este plan.

## 4. Disciplina de verificacion y seguimiento

En cada unidad:
1. Reproducir el problema antes del cambio; agregar la regresion que demuestra
   la invariante, no tests que se limiten a copiar la implementacion.
2. Ejecutar tests focales y checks de los archivos modificados; despues, suite
   offline al cerrar una unidad de runtime:

   ```bash
   EXAGENT_OFFLINE=1 MIX_ENV=test mix test
   ```

3. Registrar comando exacto, entorno, resultado, exclusiones y limites. Un
   `MIX_HOME` temporal u otro requisito del entorno se documenta si hace falta.
4. Los fixtures prueban payloads/contratos locales. La aceptacion de proveedores,
   Store Postgres y backend de trazas se prueba por separado; no activar llamadas
   pagadas ni servicios nuevos como efecto lateral de la suite offline.
5. Revisar impacto transversal, actualizar DESIGN/CHANGELOG si cambia un
   contrato y ROADMAP con avance real. Pasar a la siguiente unidad cuando cumpla
   su cierre; no repetir checks sin cambios o preocupaciones que lo justifiquen.

Ficha minima de seguimiento: **unidad, estado, problema/evidencia, decision,
archivos, verificacion, migracion, limitaciones y siguiente paso**. Usar pruebas y
documentos existentes cuando encajen; no crear un sistema de gestion adicional.

## 5. Decisiones y efecto sobre el orden

| Decision | Estado / criterio | Donde bloquea |
|---|---|---|
| D1. Alojamiento e instancia actual | Confirmar si Opik se usa en cloud o servidor propio y si hay historico que conservar. No asumir una migracion. | Prueba/despliegue real de C6; no el core. |
| D2. Alcance de funciones OSS | Criterio aclarado por el autor: preferencia por funciones sin licencia comercial; aceptar funciones avanzadas comerciales si mejora de forma relevante la observabilidad. Calidad comparable: priorizar cobertura abierta util. | No requiere otra aclaracion de preferencia; la seleccion se verifica en C6. |
| D3. Aprobacion/reanudacion | Conversacion fiable en C5 y aprobacion diferida acotada en C7; workflow durable arbitrario fuera. | Inclusión de C7 y promesas de la major; considerar en C1. |
| D4. Consumidores y backends | Inventario read-only realizado: Dragonex Git a31b306/1.3.0, WhoamAI vendor c08125b/1.2.0. Migracion/ejecucion de consumidores y pruebas pagadas siguen requiriendo alcance autorizado. | Validacion real C3/C8; no el desarrollo offline del framework. |

El autor ha autorizado comenzar la ejecucion el 2026-09-09. Las decisiones
tecnicas internas se resuelven en su unidad; no pedir al autor que elija cada
modulo, estructura o mecanismo de OTP.

## 6. Alojamiento frente a licencia: la pregunta de observabilidad

Son dos ejes independientes:

- **Cloud gestionado:** el proveedor opera la plataforma. Puede tener un plan
  gratuito con limites y planes pagados por uso/funciones.
- **Self-hosted OSS:** se instala la parte abierta en infraestructura propia,
  sin pagar licencia por esas funciones. Se siguen pagando/operando servidor,
  almacenamiento y backups; los modelos tienen su coste independiente.
- **Self-hosted enterprise:** corre tambien en infraestructura propia, pero
  ciertas funciones requieren comprar una licencia comercial.

Ejemplos de funciones administrativas: permisos para que un miembro vea solo
un proyecto; politica integrada que borra trazas tras 30 dias; registro de
cambios administrativos en la plataforma. **Estos permisos no son los permisos
de tools de ExAgent, ni esa auditoria es la traza que muestra lo que hizo la IA.**

La documentacion de Langfuse distingue core MIT (trazas, evaluacion, prompts,
datasets) de RBAC por proyecto, retencion y audit logs enterprise, incluso en
self-hosting. Existen controles basicos de acceso en OSS: no confundir esto con
una plataforma enteramente sin autenticacion. Opik OSS tiene una limitacion
distinta: su guia self-host excluye gestion de usuarios.

**Respuesta del autor, 2026-09-09:** preferir todas las funciones sin licencia
comercial, pero aceptar funciones avanzadas comerciales si la calidad de la
observabilidad justifica la diferencia. Si hay poca diferencia, preferir la
opcion que cubra mas necesidades sin licencia. Es una preferencia fuerte, no
una prohibicion absoluta de modelos open-core ni una autorizacion de compra.
Las trazas del core no requieren por ello una licencia enterprise.

Fuentes reconsultadas para Langfuse y contraste con la investigacion:
[licencia enterprise](https://langfuse.com/self-hosting/license-key),
[comparativa publicada de funciones](https://github.com/langfuse/langfuse-docs/blob/main/components/home/pricing/PricingTable.tsx),
[self-hosting de Opik](https://www.comet.com/docs/opik/self-host/overview).
Revalidar terminos/versiones al ejecutar C6; no elegir segun precios supuestos.

## 7. Evidencia C0 y primera unidad (2026-09-09)

**Base:** HEAD `c08125be71eada363d08ca463cc7df2ea7855e4a`, con los documentos
de investigacion/planificacion locales preservados. Se revisaron los tres
commits de `origin/main` pendientes (`97ebc37`, `f134f1d`, `a31b306`): agregan
OpenCode Zen/Go, sus endpoints/configuracion y version 1.3.0. No contienen las
correcciones prioritarias. Se conserva la base local auditada; no se fusiona
Git ni se elimina el trabajo remoto. Antes de C3 habra que resolver esa
integracion para evitar ignorar un adaptador publicado posteriormente.

**Baseline fresco:** `EXAGENT_OFFLINE=1 MIX_ENV=test mix test` dio **310 tests
correctos y 28 excluidos**, seed `784466`. Elixir 1.20.0 compilado con OTP 27,
ejecutandose sobre OTP 29, 24 schedulers. Esta vez el entorno tiene Hex disponible
y no necesita el MIX_HOME temporal anterior. La recompilacion mostro warnings
de dependencias HPAX y opciones xref, mas los dos aliases preexistentes del test
de concurrencia. No se modificaron dependencias.

### Inventario inicial de contratos

| Frontera | Contrato actual relevante | Revision posterior |
|---|---|---|
| Core (`lib/exagent.ex`) | Agent es struct; `run/3` devuelve `{:ok, result}` o `{:error, reason}`. Exito: output/messages/new_messages/usage/run_step/model. `run_stream/3` tiene otra forma de resultado. | C1/C3: equivalencia de ejecucion y progreso parcial. |
| Model (`lib/exagent/model.ex`) | `request/4` devuelve response y model final; `request_stream/4` es opcional y devuelve enumerable/error. `profile/1` opcional con defaults permisivos. | C1/C3: estado final stream y capabilities reales. |
| Tools (`lib/exagent/tool.ex`, `lib/exagent/tools.ex`) | Nombre/schema/callable, `takes_ctx: true` y `max_retries: 1` por defecto; output Ecto usa `final_result`. | C2: validacion, identidad, resultado y retries. |
| Server (`lib/exagent/server.ex`) | `chat/3` sincrono; async devuelve request_id; cola maxima 8 por defecto; abort, history y uso; worker supervisado; Store opt-in. | C1/C5: ACK, estado parcial, eventos y propiedad. |
| Session (`lib/exagent/session.ex`) | Estados created/running/paused/closed/done; roster, current y policy; take_turn devuelve nuevo estado y siguiente participante. | C1/C5: invariantes de FSM y persistencia de policy. |
| Event (`lib/exagent/event.ex`) | Envelope version 1; seq, type, payload y correlacion; entrega `{:exagent_event, event}` mediante PubSub. IDs de correlacion pueden ser nil. | C1/C5/C6: correlacion, terminales/deltas y frontera OTel. |
| Store (`lib/exagent/store.ex`) | save devuelve `:ok` o error; load devuelve snapshot/error; config opaca. Default sin Store; ETS/Postgres intercambiables por behaviour. | C1/C5: ACK/error/recuperacion y aceptacion por backend. |
| Snapshots (`lib/exagent/server/snapshot.ex`, `lib/exagent/session/snapshot.ex`) | Version 1 y JSON; Server guarda history/uso/metadata/provider_state opcional; Session roster/policy/shared_state. La plantilla viva la aporta la app. | C1/C5: validacion de versiones/datos y migracion; JSON no redacta secretos. |

**Reproductor persistente:**

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs --bench
```

Emite observaciones JSON, no una suite de regresion. Un campo `false` describe
una invariante de consolidacion incumplida; `probe_error` indica un fallo del
propio experimento, no confirma el defecto. Usa TestModel, efectos simulados,
un Store de error y frames Req sinteticos, sin proveedores/DB/red. Los numeros
siguientes se capturaron **antes** de corregir permisos:

| Riesgo / contrato | Observacion reproducida | Responsable / impacto |
|---|---|---|
| P0-1. Resultado/loop streaming | Normal devuelve Ticket valido en 2 pasos; `run_stream` devuelve texto vacio sin model final; `stream_text` agota 3 pasos. | C1/C3: resultado, estado Model y semantica de streaming. |
| P0-2. SSE | Se pierde un mensaje ajeno; dos frames CRLF dan solo `:done`. Cleanup del response si se ejecuta. | C3: framing y ownership de mailbox. Laziness HTTP y saturacion aun pendientes. |
| P0-3. Args de tools | Schema exige entero, llega `"bad"`, se ejecuta 1 efecto y el run termina ok. | C2: validacion antes de efectos; elegir alcance de schemas. |
| P0-4. Permisos | `default: :approve` no se rechaza; struct invalido ejecuta 1 efecto. Las regresiones nuevas fallan en 8 de 20 tests. | C2.1: correccion urgente; decision en DESIGN 8.1. |
| P0-5. Delegacion | Solo se permite `delegate` en el padre, pero el hijo ejecuta su tool; 3 requests totales con limite 1 del padre. | C1/C4: limites actuales por run y ausencia de herencia, no presupuesto global ya implementado. |
| P0-6. Progreso tras fallo | Una tool tiene exito, falla el modelo; dos intentos explicitos del caller producen 2 efectos, history vacio y uso 0 en Server. | C1/C5: estado parcial y politica de repeticion; no se afirma retry automatico del framework. |
| P0-7. Checkpoint | Store devuelve error; el caller recibe ok y el error no genera log. Una llamada `health` sincroniza el final del checkpoint. | C1/C5: observabilidad del error y significado del ACK. No decide aun ACK durable. |

Los P1 conservan sus referencias y unidades en RESEARCH; se reproducen al abrir
su unidad. El inventario de Dragonex/WhoamAI queda **desconocido**: faltan rutas y
alcance de acceso; no se han inspeccionado/modificado ni declarado compatibles.
Esto no bloquea C2.1, que conserva el contrato de configuraciones validas.

### Medidas iniciales sinteticas

200 runs medidos por fila, tras 20 de warmup, sin OTel, HTTP ni Store. Los
escenarios son consulta con output Ecto/tool de lectura y registro de efecto
simulado seguido de fallo del modelo. Ambos verifican el tipo de resultado.

| Escenario | Concurrencia | p50 / p95 (us) | Tiempo total (us) | Max. memoria worker al finalizar (bytes) |
|---|---:|---:|---:|---:|
| Lectura estructurada | 1 | 15 / 20 | 5392 | 18664 |
| Lectura estructurada | 8 | 33 / 93 | 2382 | 18664 |
| Efecto y fallo | 1 | 14 / 20 | 3663 | 13776 |
| Efecto y fallo | 8 | 52 / 87 | 2692 | 13776 |

Mailbox del worker al finalizar: 0 en las cuatro filas. Son muestras locales
cortas, no picos de memoria, medicion de backpressure, benchmark de proveedores
ni SLO de produccion. Excluyen memoria de procesos hijos y no garantizan colas
acotadas bajo carga. Sirven como baseline reproducible; C8 requiere medidas mas
representativas antes de afirmar mejoras de rendimiento.

### Cierre de C2.1 y siguiente paso

Implementados validacion de opciones/reglas/acciones, rechazo de acciones
desconocidas y aprobaciones no invocables, y admision positiva en el loop. Se
conservan default `:allow`, reglas validas y aprobaciones validas. El contador
del probe paso de **1 efecto a 0**; ahora el constructor rechaza la accion
invalida. Las otras seis reproducciones siguen abiertas, no se han ocultado.

Verificacion final de runtime:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test
EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs
```

Compilacion de 52 archivos correcta con warnings como errores. Suite **319
tests correctos, 28 excluidos**, seed `567723`; nueve tests nuevos de permisos,
incluidos contadores de efectos en core y Server. Persisten los dos warnings
preexistentes de aliases de tests; la suite completa no se ha declarado libre
de warnings. No se han probado backends reales ni otras versiones de Elixir.

**Siguiente unidad:** C1 transversal a partir de la matriz, especialmente
resultado/estado parcial y semantica sync/stream antes de implementar C2/C3
completos. La correccion C2.1 no da por cerrada toda la admision, validacion de
argumentos, delegacion ni recuperacion. Inventario de consumidores pendiente de
rutas/acceso en ese corte C0; el inventario read-only posterior ya esta realizado,
pero su migracion/aceptacion y la eleccion de observabilidad siguen abiertas.

## 8. Consolidacion orquestada C1-C5

El autor delego decisiones tecnicas y pidio workers Astra. Run Orca
`run_ab7595996c57`; el checkpoint operativo esta en ORCHESTRATION.md. Se separaron
ownership de core, tools, providers, runtime y MCP/compaction, con verificacion
centralizada tras congelar editores. Las revisiones se asignaron a autores
distintos; para las ultimas tareas se abrieron workers frescos y se cerraron
los agentes anteriores sin tarea, conforme a la indicacion posterior del autor.

### Implementacion y evidencia ya obtenidas

- C1: decisiones y migracion en DESIGN 8.2-8.4 y MIGRATION.md, con inventario
  read-only de Dragonex (Git a31b306/1.3.0) y WhoamAI (vendor c08125b/1.2.0).
- C2: JSV 0.22, validacion previa a efectos, resultados JSON portables, schema
  cacheado, defensa previa a casts/modulos, uniones/map(), outcomes completos y
  reintento de ejecucion solo mediante senal explicita.
- C3: loop canonico sync/stream, modelo final, puentes bajo demanda y cleanup,
  framing limitado, ensamblado OpenAI/Anthropic y adapter OpenCode preservando
  helpers consumidos. Se conserva la frontera propia tras evaluar ReqLLM.
- C4: scope del arbol, admision atomica, permisos de ancestros, uso reconciliado,
  costes fraccionales conocidos/desconocidos, deadline/concurrencia separados y
  compactacion por proyeccion con historial autoritativo intacto.
- C5: checkpoint confirmado/dirty/retry-save, progreso parcial, terminal unico,
  snapshots v2/lector v1 seguro, FSM/cursors/handoff y pending MCP con ownership.

Primer gate conjunto: **516 tests correctos, 28 excluidos**, seed `398741`,
warnings como errores; las siete comprobaciones C0 dan true. Los errores de
integracion iniciales incluyeron warnings de bitstrings, sintaxis de un test y
migracion de expectativas antiguas; se corrigieron manteniendo invariantes de
efectos/cleanup. Se reprodujo por separado el EXIT de inicializacion enlazada
en OTP29 y se aislaron esas pruebas, sin alterar el contrato OTP del runtime.

### Iteracion de revision final

Los hallazgos se convirtieron en regresiones publicas contra los BEAM previos
sin revertir WIP (`mix test --no-compile`): **17 fallos de 42**, seed `155080`.
Tras corregir respuesta efectiva de hooks, snapshot conocido ante Scope DOWN,
proyeccion segura de errores, finalizadores/guardianes y ocurrencias de grupos
de compaction, el gate compilado dio **43 tests correctos**, seed `686206`.
Compilacion forzada correcta de **70 archivos** con warnings como errores.

### Rendimiento local medido

Un spike controlo la preparacion explicita de las mismas tools: reconstruir JSV
dominaba el overhead. Se preparo oportunistamente la definicion valida en new,
con validacion en cada llamada y reconstruccion si cambia el schema. Errores de
schema siguen devolviendo RunError al ejecutar. No se introdujo cache global.

| Mismo spike, 200 muestras / 20 warmup | Antes p50 (us) | Despues p50 (us) |
|---|---:|---:|
| Lectura estructurada, concurrencia 1 | 1092 | 143 |
| Lectura estructurada, concurrencia 8 | 1472 | 356 |
| Efecto y fallo, concurrencia 1 | 1038 | 137 |
| Efecto y fallo, concurrencia 8 | 1440 | 342 |

Son costes del runtime offline; la preparacion se paga al construir y solo se
amortiza al reutilizar la definicion. No son mejoras de latencia de un LLM ni
memoria pico del arbol. La version inicial de 15us carecia de las garantias que
ahora se verifican; no se presenta como rendimiento equivalente.

### Gate de salida completado

Un verificador Astra nuevo ejecuto compile forzado, suite con warnings como
errores y probe en ambos runtimes: **541 correctos/28 excluidos**, semillas
`957568` (1.20/29) y `135797` (1.18/28); las 14 invariantes C0 fueron true.
No modifico fuentes y uso un MIX_BUILD_PATH aislado para el runtime alternativo.

El cierre de docs detecto locks heredados de Mint/HPAX con advisories que
afectaban la entrega de chunks antes de aplicar limites. Una regresion TCP
local mostro timeout en vez de limite al anunciar 256 MiB y enviar solo 128 bytes.
Se exigieron Mint 1.10/HPAX 1.0.4 en el manifiesto (no basta el lock para consumidores)
y se actualizaron Postgrex 0.22.4/DBConnection 2.10.2 de tests. La regresion paso;
ambas suites finales dieron **542 correctos, 28 excluidos**:

| Runtime final | Compile | Suite | Seed |
|---|---|---|---|
| Elixir 1.20.0 / OTP 29.0.5 | 70 archivos, warnings-as-errors, exit 0 | 542 pass, 28 excluded | 950880 |
| Elixir 1.18.4 / OTP 28.0 | 70 archivos, warnings-as-errors, exit 0 | 570 total, 0 fail, 28 excluded (542 pass) | 580649 |

El build alternativo antiguo conservaba metadata .app de versiones previas;
se reconstruyo en `/tmp/opencode/exagent-compat-118-final`, sin borrar WIP ni
cambiar configuracion global. Comandos finales:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix test --warnings-as-errors
```

Tambien pasaron los cinco ejemplos offline demo/stateful_agent/multi_agent_session/
dnd_session/durable_oban (este ultimo solo receta + codec, no Oban real), y la
generacion de docs con warnings-as-errors en `/tmp/opencode/exagent-docs`.
`mix hex.build` tambien produjo `/tmp/opencode/exagent-consolidation-preview.tar`,
solo como comprobacion local del manifiesto: no se publico y conserva la version
nominal 1.2.0, por lo que no es una release de la major pendiente.
Se corrigio la suscripcion del collector del ejemplo estatal y se actualizaron
README/MIGRATION, evitando promesas de replay automatico. No hay workers activos.

Elixir1.17, proveedores reales, Postgres y migraciones de aplicaciones no estan
certificados por estas pruebas. C6 (OTel/plataforma), C7 (aprobacion diferida) y
aceptacion externa C8 permanecen como siguientes unidades, no implementaciones
que este cierre afirme terminadas. No se subio version, publico ni hizo commit.

## 9. C6 neutral: implementacion y aceptacion offline (2026-09-09)

Run Orca `run_395ccad931e7`, workers `openai/gpt-6-astra`, dos revisiones frescas y
verificador final independiente. **Unidad neutral cerrada offline; C6 completo
permanece abierto por OTLP/backend real y comparacion Langfuse/Opik.** No se eligio
ni desplego una plataforma. Mandato y limites de coste/consumidores siguen vigentes.

### Contrato implementado

- `ExAgent.Observability.OpenTelemetry.new/1` y `observability:` opt-in, con API y
  SDK opcionales; SDK `runtime: false`. App propietaria de tracer/provider, recurso,
  sampler y exporter, sin sustitucion de configuracion global. Guia en
  [OBSERVABILITY.md](../../guides/observability.md), incluida en los manifiestos docs/paquete.
- Spans por run, request, tool, delegacion, compaction y checkpoint; Server comparte
  un unico run con su worker hasta guardar. Contexto explicito en Tasks, colas y
  GenServers, restauracion de contexto y claves Logger propias, cierre por owner
  death, streaming lazy y ausencia de spans por token o por vida completa de Server.
- Contenido ausente por defecto. Opt-in exige redactor fail-closed, entrada plain
  data acotada y salida UTF-8 limitada antes del SDK; structs/Ecto y objetos runtime
  no se serializan automaticamente. Sin baggage, configuracion, mensajes de
  excepciones ni modelos vivos en atributos. IDs/labels deben ser no secretos.
- Perfil `exagent.gen_ai.v1`, GenAI SHA `b5d8440`: uso de generacion separado de
  agregados de run, cache Anthropic inclusiva solo en proyeccion, semantica custom
  desconocida explicita y coste reutilizado del ledger sin otro estimador.
- `BoundedProcessor` extiende el SDK nativo porque su BSP1.7 tiene cota blanda y
  carece de los contadores requeridos. Slots finitos incluyen pending/inflight,
  batch y deadlines fuera del run, un exporter worker, observer de snapshots
  escalares y guardianes acotados. Flush coalescido asincrono, sin ACK remoto;
  shutdown descarta, sin retry implicito del batch. Cantidad de spans no es bytes.

### Problemas reproducidos y resueltos durante revision

1. Un consumidor con SDK propio compilaba ExAgent antes del SDK y quedaba
   permanentemente `sdk_unavailable`; arista SDK opcional y rama ausente sin
   warnings. Se probaron tres grafos de dependencias limpios, no solo el root.
2. Exporter/observer con `trap_exit` quedaban huerfanos tras matar al manager;
   guardianes independientes cierran procesos/tablas propios. Un flush concurrente
   se perdia entre seleccion vacia/reset; la segunda comprobacion conserva el
   trabajo. La ventana exacta se fuerza en una copia en memoria mediante el probe
   persistente `test/support/observability_processor_probe.exs`, sin hooks productivos.
3. Abort/crash sintetizado de Server afirmaba consumo completo/coste cero desde
   progreso anterior a la request. Retorno rico, Event y span ahora expresan
   partial/unknown preservando subtotales; los resultados normales del core retienen
   completitud confirmada. No se recomputa uso ni precio. DESIGN8.7 y MIGRATION
   explican este ajuste observable de la major pendiente.
4. Contexto vacio conservaba IDs Logger durante el callback y bigint eludia la
   cota previa al redactor. Regresiones reprodujeron seis fallos de21; los fixes
   aislados dieron21/21 antes del gate compilado final.
5. SDK/OTP conserva bootstrap args en child specs; con informes SASL activos se
   reprodujo un sentinel en logs si se pasa como exporter opts. La configuracion
   segura lo resuelve dentro de init desde env/config de app y no lo expone en
   mfargs. Esta frontera se documenta, no se oculta con un filtro Logger global.

### Evidencia final

Baseline fresco previo a C6: native542/28, seed517405, compile70 y14 invariantes C0.
La matriz inicial tuvo un timeout100ms de readiness en ServerOwnershipTest; su
archivo paso12/12 sin cambios. Se amplio esa barrera a1000ms conservando las
aserciones de cancelacion; ambas suites finales pasan. Dos fixtures nuevos OTel
(normalizacion Store y saved_at por intento) y una lista exhaustiva antigua de
campos ExAgent se corrigieron sin alterar schema API/defaults ni debilitar checks.

| Gate final independiente | Resultado |
|---|---|
| Elixir1.20.0 / OTP29.0.5 | Compile72 warnings-as-errors; **579 correctos, 28 excluidos**, seed482769 |
| Elixir1.18.4 / OTP28.0, build limpio separado | Compile72 warnings-as-errors; **607 total, 0 fallos, 28 excluidos =579 correctos**, seed648445 |
| C0 en ambos runtimes | Las14 invariantes de7 grupos true |
| Probe R3 scheduling aislado | 1 test correcto, seed0 |
| Consumidor sin OTel/SQL | Compile63 sin warnings y run correcto |
| Consumidor API sola | Compile63 sin warnings, run/stream no-op y contexto restaurado |
| Consumidor SDK | SDK compila antes de ExAgent con `deps.compile exagent --include-children`; run y barrera de2 spans correctos |
| Ejemplo local/bench | **509/509 spans exportados**, cero drops/errores/timeouts, cola e inflight0 |

Comandos principales:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs --bench
EXAGENT_OFFLINE=1 elixir -pa _build/test/lib/opentelemetry/ebin -pa _build/test/lib/opentelemetry_api/ebin -pa _build/test/lib/telemetry/ebin test/support/observability_processor_probe.exs
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-c6-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-c6-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix test --warnings-as-errors
```

Medida final: misma definicion/TestModel, 50 warmup, 200 muestras, concurrencia1,
construccion excluida. Desactivado p50/p95 **56/70us**, activado **123/178us**.
Es overhead local sintetico, no latencia de LLM ni SLO. Los tres consumidores
temporales usaron builds nuevos y resuelven Req0.7.4/Finch0.23 frente al lock
root Req0.6.1/Finch0.22, sin implicar compatibilidad con todo consumidor posible.
Rebar descarto un DAG cache antiguo y recompilo correctamente SDK en la matriz;
no hubo warnings del compilador del proyecto o de los consumidores finales.

Informe detallado/logs: `/tmp/opencode/exagent-c6-final-verification.md` y prefijo
`/tmp/opencode/exagent-c6-final-`. La evidencia durable es esta seccion, las decisiones
DESIGN8.6–8.7 y las regresiones del repositorio. Los cinco workers C6 estan cerrados.

### Limites y siguiente gate

Faltan exporter OTLP nativo/HTTP real y su cleanup integral, API/UI Langfuse/Opik,
proyectos/credenciales/entorno reales y comparacion funcional/operativa. No basta
el exporter in-memory ni HTTP200 para cerrar esos puntos. Sigue pendiente acceso
autorizado y confirmar si existe Opik/historico util; no se despliega infraestructura
ni se contrata un servicio como efecto lateral. Modelos reales, Postgres, consumidores
Dragonex/WhoamAI y minimo Elixir1.17 tambien siguen fuera de esta evidencia.
Sin commit, bump, publicacion, despliegue o cambios de esas aplicaciones.

## 10. Ejecucion nocturna y matriz de aceptacion (2026-09-09)

El nuevo mandato empieza a las 22:20 UTC en Run `run_4315531152c9`, generación 1.
Baseline propio: **579 correctos, 28 excluidos**, seed280440. Se preserva toda la
implementacion local anterior. N01–N03 y N05–N06 se asignan a dos workers Astra:
OTLP nativo loopback y consumidores de bytes de un paquete congelado, con fuentes,
dependencias y ventanas de compilacion separadas. Asignar no significa aceptar;
los resultados de cada unidad se incorporan aqui tras verificar y revisar.

### Matriz focal de promesas y evidencia (preparacion N16)

Las rutas siguientes son del checkout y sus pruebas forman parte del baseline
offline anterior, salvo donde se indica pendiente. Esta matriz relaciona las
promesas actuales de README/DESIGN/MIGRATION/OBSERVABILITY con fronteras verificables;
no convierte una prueba de protocolo en certificacion de cada modelo comercial.

| Promesa / documento | Evidencia reproducible en el checkout | Limite o gate restante |
|---|---|---|
| Un loop sync/stream, output Ecto y estado Model (README Streaming; MIGRATION2) | `test/exagent/core_contract_test.exs`: efectos/uso/modelo, output tipado sync/public stream y terminal ausente; `final_review_regression_test.exs`: respuesta efectiva/hook en los tres modos, incluido stream_text. | Cada adapter custom debe migrar su terminal. Cada enumeracion es otra ejecucion. |
| Schema Ecto fiel sin modos paralelos (DESIGN8; MIGRATION3) | `output_schema_contract_test.exs`, `output_schema_test.exs`: carga fria, requeridos/opcionales/embeds y payload `final_result`. | Changeset final es autoridad; strict/anyOf en proveedor real pendiente. |
| Tools validadas antes de efectos (DESIGN8.2; MIGRATION3) | `tool_validation_test.exs`, `tool_definition_cache_test.exs`, `core_contract_test.exs`: refs/casts, claves, Unicode, cache y hooks sobre la tool efectiva. | Callbacks locales no son sandbox; dialectos admitidos draft7/2020-12, sin resolucion remota. |
| Errores parciales y ausencia de replay implicito (MIGRATION1/3) | `core_contract_test.exs`, `final_review_regression_test.exs`: batch fallido conserva efectos, despues-hook, uso y modelo conocido. | App conserva idempotencia/reconciliacion externa; parcial no autoriza otro efecto. |
| Autoridad/coste por arbol (README Coordination; MIGRATION4) | `execution_scope_test.exs`: competencia por ultimo slot, deny/ask de ancestros, nietos, fractional cents y muerte de scope. | IO ajeno no se mide; umbrales de tokens/coste no predicen consumo en vuelo. |
| Compaction conserva historia canonica (MIGRATION4) | `compaction_test.exs`, `iteration_c_test.exs`: proyeccion y grupos por ocurrencias; probes C0. | No limita historia persistida ni contabiliza automaticamente un resumidor externo. |
| ACK despues de save y retry solo almacenamiento (README Store; MIGRATION5) | `server_checkpoint_contract_test.exs`, `server_ownership_test.exs`: barreras Store/queue/kill, dirty y efecto preservado. | Cola async volatil; Postgres excluido requiere aceptacion propia. |
| Session/restauracion segura (DESIGN8.3; MIGRATION5) | `session_fsm_contract_test.exs`, `session_cold_restore_test.exs`, `session_persistence_test.exs`: roster/cursor/handoff, policy confiable, v1/v2 y rechazo de corruptos. | Snapshot de estado no es reanudacion universal; C7 condicionado. |
| OpenAI-compatible sync/SSE (README Models) | `providers/openai_chat_test.exs`, `providers/streaming_test.exs`, `output_schema_contract_test.exs`; `models/opencode_test.exs` verifica configuracion Zen/Go y contrato comun. | OpenAI/OpenRouter/OpenCode comparten adapter; aceptar un payload no prueba soporte real de cada modelo/gateway. |
| Anthropic sync/SSE y cache (OBSERVABILITY4; README Models) | `providers/anthropic_test.exs`, `providers/streaming_test.exs`: bloques/tool JSON/usage/cache/thinking. | Z.AI usa ese protocolo; no supone paridad del backend ni thinking de todo modelo. |
| Streaming/MCP acotados y cleanup (README MCP/Models) | `providers/sse_test.exs`, `providers/stream_transport_test.exs`, `mcp/client_test.exs`, `mcp/client_e2e_test.exs`: fragmentacion, chunk incompleto, cierre TCP real y stdio local. | Callback/backend ajeno conserva su lifecycle; timeout local no implica rollback remoto. |
| Eventos seguros y OTel opcional (OBSERVABILITY2–5) | `event_error_projection_test.exs`, `observability/open_telemetry_test.exs`, `observability/bounded_processor_test.exs` y probe R3 aislado. | Canales ricos explicitos conservan datos runtime; contenido off no certifica logs arbitrarios de apps/exporters. |
| OTLP y plataforma (OBSERVABILITY6–7) | N01–N03 verifican transporte nativo y delimitan fallos/lifecycle; N04/N12 entregan escenario compuesto y privacidad, con refuerzo de oráculos en revisión final. | Cleanup HTTP general, fidelidad booleana y recepción parcial siguen limitados; API/UI Langfuse/Opik requiere acceso y N18 integra los gates finales. |
| Paquete/minimo declarado (README Requirements/Installation) | N05–N06: TAR, cuatro grafos y fix verificado en Elixir1.17.3/OTP27.3.4.17; revisión fresca pendiente. | No certifica todos los patches/OTP25/26 ni Dragonex/WhoamAI; matriz raíz mínima y aceptación final en N18. |

`ModelProfile.supports_tools` se aplica al core y al output mediante tool. Los flags
de JSON nativo/thinking son declarativos para modos no seleccionados actualmente;
no prometen negociacion completa. Un modelo sync-only puede rechazar streaming.
Los snippets que requieren API key, MCP externo, Repo o funciones de la app son
recetas, no ejemplos offline certificados. La comprobacion ejecutable de snippets
y el cierre completo de N16 siguen pendientes; se priorizan defectos reproducidos.

### N17 focal: dependencias de la frontera OTLP

Tras resolver exporter 1.10.0 como dependencia **solo test, runtime:false**, se
inspecciono el diff del manifiesto/lock: las nuevas transitivas pertenecen a ese
exporter (incluido grpcbox aunque el ensayo use HTTP). API1.5/SDK1.7 conservan su
opcionalidad de consumidor, y Mint1.10/HPAX1.0.4 sus pisos de seguridad. No se
añadio el exporter al grafo obligatorio publicado ni se hicieron upgrades ajenos.

Consulta actual de Hex2.5.1, contrastada con su documentación/ayuda:
`EXAGENT_OFFLINE=1 MIX_ENV=test mix hex.audit` -> exit 0,
`No retired or security advisory packages found` (2026-09-09, 22:28 UTC).
Es evidencia del catalogo de advisories para el lock resuelto, no una auditoria
exhaustiva ni prueba de los limites de lifecycle; estos se miden en N03. No hay
un advisory aplicable demostrado que justifique otro upgrade en esta unidad.

### N01–N03: entrega local y primer gate integrado

Task `task_df8f94538ab0`, Dispatch `ctx_0ed3fc45043f`: cuatro tests nuevos de VM
aislada (`native_otlp_test.exs`, receptor/probe persistidos bajo test/support),
exporter 1.10.0 test-only y codec protobuf oficial. Focal **4/4**, seed576860;
coordinador repite suite compilada: **583 correctos, 28 excluidos**, seed280424, 11.1s.
Revisión fresca `task_ba1c3ef3eeab` / `ctx_8c19b7d9dd60` completada: no encuentra
P0/P1 nuevo del patch y repite los cuatro probes con exit 0. Recurso liberado y
terminal cerrada. No se añadieron fixes de biblioteca en N01–N03.

Cada traza simple contiene 4 spans, 2 requests y 1 tool; la matriz de siete casos
usa una barrera HTTP real para demostrar que otro run avanza. Totales por caso:
4 llamadas al modelo, 2 efectos y 2 requests HTTP. Con 8 spans admitidos,
401/403/429/503/close dan 4 exported + 4 failed; timeout da 4 exported + 4 timed_out;
200/rejected_spans=4 da 8 exported porque el exporter ignora partial_success.
Son callbacks, no ACK remoto. Los checks explícitos de IDs entre runs y tags
numéricos se amplían en N04; el revisor los identificó como gaps de aserciones,
sin demostrar un defecto runtime en los payloads observados.

N03 confirma con tres ciclos nativos normales: profiles 2→3→4→5 y ETS +4/ciclo;
el cleanup diagnóstico vuelve a 2 profiles. En tres ciclos BP timeout/reinit/
shutdown mueren siete procesos ExAgent propios y su ETS, pero el handler/socket
HTTP sobrevive. Detener solo el profile tampoco lo cierra en OTP29. En una VM
exclusiva, cancelar requests observadas antes de retirar profiles recupera los
gauges de procesos/monitores/ETS/puertos/sockets al baseline caliente, manteniendo
default/ajeno. Los átomos nativos, siete/profile (14 por timeout/reinit), no se
recuperan. Booleanos SDK true/false llegan como strings en span/resource, demostrado
sin ExAgent con controles positivos. **Caracterización cerrada; lifecycle general
nativo y fidelidad booleana siguen limitados**, no arreglados por otra capa.
DESIGN8.8 y OBSERVABILITY7 contienen decisión, alternativas y límite de adopción.

Informe completo: `/tmp/opencode/exagent-night-otlp-wave1.md`; evidencia durable en
tests, esta seccion y docs de contrato. N04/N12 ya continuan en nueva Task
`task_f4a858b961f2` / `ctx_76661ceb4f2f`, mismo autor por contexto propio util,
solo archivos nuevos para mantener estable la revision de N01–N03.

### Incidente de aislamiento de tooling y comando de recuperacion local

El bootstrap N05/N06 heredó MIX_ARCHIVES del host pese a MIX_HOME temporal y escribió
Hex2.5.1 en el entorno mise Elixir1.20 con BEAM del toolchain1.17 incompatible con
OTP29. Fue una escritura accidental fuera del alcance. Se detuvieron las mutaciones
globales; no se afirma que el Hex compartido esté reparado. Los logs, la causa y el
preflight correctivo corresponden al autor del paquete; su entrega debe conservar
el incidente explícitamente.

El coordinador reprodujo además que su `erl` era un shim mise que sobreescribe
MIX_HOME/MIX_ARCHIVES incluso con prefix. Se verificaron los valores efectivos con
PATH directo, sin modificar configuración global. El gate583/28 usa exactamente:

```bash
PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin MIX_HOME=/tmp/opencode/exagent-native-otlp-mix MIX_ARCHIVES=/tmp/opencode/exagent-native-otlp-mix/archives EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
```

Este Hex temporal2.5.1 se obtuvo con el instalador oficial; no hace falta repetir su
instalación si sigue presente. Los nuevos workers deben redescubrir paths/runtimes
y comprobar destinos efectivos antes de bootstrap. Reparar el Hex compartido queda
como gate de autorización; no bloquea otras pruebas aisladas.

### N05/N06: paquete real, mínimo y corrección interna

Task `task_7715da65eff2` / Dispatch `ctx_6e8f963febf8` completada; terminal liberada
y cerrada. Runner y regresión de aislamiento persistidos en
`test/support/package_acceptance.exs` y `package_acceptance_isolation.exs`, con siete
plantillas bajo `test/fixtures/package_acceptance/`. Revisor fresco en curso:
`task_20017e13c7a8` / `ctx_caa7f89c6b7a`.

El runner verifica checksum externo/interno, 80 archivos del paquete, 63 fuentes
y provenance de los 104 módulos compilados desde bytes copiados, sin symlink al
checkout. Cuatro consumidores prueban ausencia de OTel/SQL, API sola, SDK y exporter
opt-in, orden SDK→ExAgent y seis contratos cada uno: run, tool tipada/validación sin
efectos, stream lazy, output Ecto, RunError y checkpoint/restore ETS. SDK/exporter
exportan13/13 spans. Grafos/builds/dep sources/Rebar caches son independientes.

- TAR original: `exagent-night-wave1-preview.tar`, SHA256
  `ddd66c13a4a87e8900828826ed15ef2d0f599d048d5abe8310c3b6bd3927eea2`.
  Tres matrices ejecutaron72 contratos:1.20/29 fresh y1.17/27 fresh/lock raíz.
  Los cuatro consumidores1.17 sin SDK/API revelaron un warning de ExAgent que las
  flags del consumidor no elevaban retroactivamente. Los reportes iniciales que
  decían ausencia de warnings quedaron corregidos explícitamente.
- Fix interno en `BoundedProcessor`: helper privado con decisión SDK en compilación,
  preservando retornos/validación y ausencia permanente cuando faltaban records.
  El runner ahora inspecciona warnings de la compilación de dependencia. El TAR
  viejo reproduce exit1 por ese warning, aunque sus seis contratos runtime pasan.
- TAR corregido: `/tmp/opencode/exagent-night-package-fixed-preview.tar`, SHA256
  `09c9b831dc9f02c3e84735f4c2510d1f3ffe27c32c15c220df077487a18c734b`.
  Mínimo fresh, cuatro modos:24/24; mínimo con snapshot raíz none/API:12/12.
  **36/36 y cero warnings completos**, seed771506. SDK/exporter conservan13/13.
  La rama SDK presente también pasa16 tests del processor en el gate N04.
- OTP27.3.4.17 y Elixir1.17.3 se obtuvieron de releases oficiales con hashes
  verificados, únicamente bajo `/tmp/opencode/exagent-night-package-toolchain`.
  OTP se compiló con `make -j4`; no se modificaron runtimes ni configuración mise
  del host. La escritura accidental de Hex descrita arriba es una excepción real
  de aislamiento, no un cambio de toolchain omitido de esta evidencia.

Fresh resolvió Req0.7.4/Finch0.23/Ecto3.14.2 frente al snapshot raíz0.6.1/0.22/3.14.0;
Mint1.10/HPAX1.0.4/JSV0.22 se preservan. Exporter OTP29 trae nueve warnings de gproc,
distintos del warning ExAgent corregido. El grafo activo/runtime excluye SQL y docs;
un lock copiado con entradas extra no implica que esas aplicaciones se arranquen.
No se certifican todos los patches1.17, OTP25/26 ni consumidores reales.

Informe con comandos completos, fuentes/digests, locks y fases de warnings:
`/tmp/opencode/exagent-night-package-wave1.md`. El snapshot de lock reutilizable está
en `/tmp/opencode/exagent-night-package-117-lock/input.mix.lock`. Para N18 usar
plain `elixir test/support/package_acceptance.exs`, no Mix desde el repo; work-dir
nuevo bajo el prefijo `/tmp/opencode/exagent-night-package`, `--tar`, `--checksum`,
`--mode all`, `--seed 771506` y opcional `--lock`. El preflight comprueba destinos
Mix efectivos en un hijo antes del bootstrap; positivo y negativo con entorno
hostil sintético se verificaron en1.17 y1.20 sin escribir fuera de/tmp.

### N04/N12 y N07/N08: escenarios compuestos y secuencias independientes

Nuevo gate compilado conjunto del coordinador, a las23:06UTC: **595 correctos,
28 excluidos**, seed37556,14.6s, Elixir1.20/OTP29. Usa el prefix directo/Hex temporal
de esta sección. Ambos autores terminaron y sus terminales fueron liberadas/cerradas.
Revisión fresca conjunta `task_519718afe6d4` / `ctx_5ba842c9d4b5` en curso.

- N04/N12 (`task_f4a858b961f2` / `ctx_76661ceb4f2f`): tres tests nuevos en
  `native_otlp_scenario_test.exs` y probe persistido. **68 spans/11 POST**:16 en
  compuesto,15 en colas/after-hook y37 en privacidad/contexto/cleanup. Jerarquía
  exacta, tags enteros de uso/cache, IDs distintos entre callers y ausencia de
  spans por cinco deltas. Off/on conservan4 requests,43/8 tokens,0.51 céntimos y
  diez invocaciones del estimador; checkpoint fallido sólo reintenta save.
  Abort conserva subtotal0.12 con coste desconocido; after-hook no borra efecto
  completado. Sentinels se observan en callbacks antes de verificar su ausencia
  del protobuf; redactor stateful A/B, ocho campos, excepción/oversize, input
  limitado, contexto vacío y owner/tool DOWN tienen controles positivos y negativos.
  Focal compilado19/19, seed86420 (incluye16 tests previos del processor).
- N07/N08 (`task_b0811b2c406f` / `ctx_20f4cfb015d6`): nueve tests nuevos con oráculos
  independientes y seis semillas. Server7031/28042/91117 ejecuta64 comandos por
  seed (+hasta4 para asentar), comparando health/history/usage/efectos/requests/
  terminales/revisiones/snapshots después de cada transición. Session8013/28042/
  61009 ejecuta48 comandos generados, restores v1/v2, dirty/retry y cierre, hasta75
  operaciones por seed, con una lista de actores pendientes que no copia su cursor.
  Owner loss conserva el último checkpoint y pierde cola volátil sin deshacer el
  efecto anterior; codec/load adversarial conserva bytes y no crea el nombre de
  módulo hostil como átomo. Focal VM directa9/9, seed280424; incluido después en
  el gate Mix595/28. Cobertura fría de módulos y carreras primitivas existente se
  conserva sin duplicarla. No se demostró un defecto productivo nuevo.

Informes: `/tmp/opencode/exagent-night-otlp-scenario.md` y
`/tmp/opencode/exagent-night-runtime-sequences.md`. Los errores corregidos durante
estos dos desarrollos fueron de sus fixtures; no se presentan como fixes del core.
Los límites HTTP nativos y la aceptación de plataformas siguen separados.

### N09/N10/N11: fronteras compuestas, focal compilado y revisión

Autores `task_82cc29550b2c` / `ctx_9254d24ee5d1` y `task_f9dbadf89f4b` /
`ctx_7c73cf170221` entregaron y fueron liberados con terminales cerradas.
El coordinador ejecutó sin --no-compile los cuatro archivos nuevos:
**20 correctos**, seed897031, warnings-as-errors. No cambió código productivo.
Revisión fresca `task_03c8f361251b` / `ctx_b3c34ddfb2f3` en curso.

- N09: siete tests y18 runs pequeños de árboles con profundidad2–3,3–5 hojas y
 1–2 slots finales. Seeds9109/91109,9211/92211,9301–9304,9401/9402. Las llamadas
  reales del modelo, efectos y estimadores forman el ledger esperado; se comprueban
  requests/concurrencia/budget desconocido, herencia de tres niveles, deadline y
  sustitución de identidad Model antes del request. Los casos de DOWN/uso parcial
  equivalentes se conservaron en pruebas previas.
- N11: cuatro tests,62 runs y ocho combinaciones pequeñas de refs/defaults/cache.
  Seeds11101/11102 a11401/11402 más11303. Reubicación de refs y targets cacheados,
  promoción de literales a schemas peligrosos con cero callbacks/model effects,
  seis outcomes de batch con hooks efectivos y cardinalidad antes/después del
  límite. Schema sigue bajo JSV; no se habilitan casts, resolución remota ni átomos
  derivados de entradas. Resultados JSON y todos los outcomes permanecen visibles.
- N10: nueve tests con seeds37556/106033/910247. Paridad de adapters OpenAI/
  Anthropic:14 runs,28 requests y14 efectos; EOF sin terminal:12 requests y cero
  efectos.36 tails SSE adversariales y15 secuencias MCP con39 calls cubren UTF8
  multisplit, cancelación dentro de frame, late replies, límites64/128 bytes y
  suspend/resume/halt/death con mailbox ajeno. Los nuevos transportes son fakes;
  el cierre TCP real sigue respaldado por las regresiones loopback anteriores.

Evidencia de autores: N09/N11 focal97/97 seed91109 y final11/11 seed37556 contra
BEAM existentes usando --no-compile; esa elección no se presenta como compilación
productiva. N10 focal VM directa9/9 seed37556, con cero diagnósticos. El posterior
gate compilado20/20 del coordinador resuelve esa limitación local; la suite entera
y matriz de runtimes siguen en N18. Informes en `/tmp/opencode/exagent-night-scope-tools.md`
y `/tmp/opencode/exagent-night-protocols.md`.

### Revisión de aceptación: fixes antes de reutilizar el runner

Review de paquete `ctx_caa7f89c6b7a` completado: confirmó bytes, grafos y provenance
de18 consumidores y el fix del helper SDK; reprodujo un P1 del runner por MIX_EXS
heredado, y dos P2 por warnings de compile.log omitidos y ancestro symlink aceptado.
Las reproducciones usaron sólo fake-host/copias de/tmp y comandos sustituidos sin
instalar. El bootstrap de paquete queda suspendido mientras se corrige; no se
anula la evidencia de los consumidores ya auditados ni se afirma aislamiento total.

Review de escenarios `ctx_5ba842c9d4b5` pasó12/12 y no demostró defecto productivo.
Identificó dos gaps de aserciones: distribución exacta por request de tokens/cache/
coste y tokens parciales, y payload completo/uso durable de Server. Los dos reviewers
fueron liberados. Astra fresco `task_a92dfdb9e95e` / `ctx_71bb943bd26e` tiene ownership
exclusivo de esos fixes de tests/runner, sin lib ni compilación raíz. La política
elegida mantiene warnings estrictos en todas las fases, conservando por separado
runtime_contracts=passed; no se ocultan los warnings conocidos de gproc/OTP29.

N13/N14/N15 ya están en desarrollo por `task_96bd23c04c12` / `ctx_0c13dbf200ae`:
carga acotada, optimización sólo si la evidencia la justifica y evals deterministas
en dos dominios. Aún no hay resultados de esa unidad que atribuir como aceptados.

### Cierre de revisiones de fronteras y de los fixes de aceptación

N09/N10/N11: revisión fresca `ctx_b3c34ddfb2f3` terminada sin hallazgos bloqueantes;
repitió20 tests en VM directa, seed37556. El gate Mix del coordinador20/20,
seed897031, es evidencia separada del --no-compile del autor. Dos precisiones
retenidas: el round-trip del batch prueba serialización/decodificación, mientras
IDs/statuses exactos se comparan antes; la colisión de claves no es por sí sola
un control diferencial del schema efectivo. Las pruebas primitivas respectivas
siguen cubiertas. Revisor liberado con terminal cerrada.

Los fixes de aceptación (`task_a92dfdb9e95e` / `ctx_71bb943bd26e`) completaron:

- Selector/destino del runner: eliminación de MIX_EXS y selectores relacionados,
  guardia dentro de cada hijo antes de CLI, preflight con CLI real, positivo de
  proyecto local y rechazo de selector externo introducido después del preflight.
  Sólo work-dir nuevo, hijo directo real de `/tmp/opencode`, con prefix
  `exagent-night-package`; lstat rechaza enlaces, dangling y entradas existentes
  antes de escribir. Los controles preservan fake-host y targets sintéticos.
- Ocho fases de diagnóstico conservan `.log`/`.term`; warnings de cualquier fase
  producen exit1 estricto, con `runtime_contracts: :passed` separado cuando procede.
  El replay de nueve warnings reales gproc/OTP29 ahora falla correctamente; no es
  una nueva compilación ni un upgrade. Fallos tempranos de bootstrap conservan su
  diagnóstico/exit, pero pueden terminar antes de generar summary.term superior.
- Oráculo OTLP: tabla independiente por run/request con tokens/coste/cache y
  reasoning exactos, tokens10/2 en Event/span de abort y12/3 tras after-hook.
  Server: nombre/args/contenido/status, uso2/1 y5/3 discriminables, totales7/4,
  y checks de ambos contadores/payloads en memoria, intento, durable y restore,
  incluyendo una lectura JSON independiente del codec del producto.

El P1 se reprodujo con una copia que ejecutaba `mix help`, no instalaciones.
Controles de aislamiento pasan en1.20/29 y1.17/27; siete tests focales pasan,
seed37556. Trece mutaciones de expected data se rechazan por sus aserciones;
no son trece defectos productivos ni modificaciones de BEAM de la biblioteca.
Revisión final fresca `task_2a3ede223363` / `ctx_aa5440b6c911` confirma cierre
R1–R3/R1–R2, aislamiento PASS y7/7, hashes intactos. Autor y revisor liberados.
El runner queda disponible para el bootstrap aislado de N18 dentro de ese alcance;
no es sandbox de paquetes/flags VM arbitrarios ni de modificaciones concurrentes.

Informes: `/tmp/opencode/exagent-night-acceptance-fixes.md`,
`exagent-night-acceptance-fixes-review.md` y `exagent-night-boundaries-review.md`.
La reparación del Hex compartido sigue fuera de autorización y no se ejecutó.

### N13/N14/N15: mediciones finitas y evaluaciones de framework

Task `task_96bd23c04c12` / Dispatch `ctx_0c13dbf200ae` completada; autor liberado.
Cuatro archivos nuevos: `examples/framework_scenarios.exs`, `framework_evals.exs`,
`test/support/framework_load_probe.exs` y `test/exagent/framework_evals_test.exs`.
Focal compilado4/4, seed131415; ejemplo final con dos dominios y controles verdes.
Revisión final fresca en curso antes de cerrar N18.

Los datos `[3,5,8,13]` alimentan lectura delegada, retry explícito y output Ecto29/4,
con checkpoint confirmado:5 requests,15/10 tokens y coste sintético conocido0.25.
El segundo dominio completa un efecto y falla el modelo/save:6 requests, subtotal
15/10, coste desconocido y2 intentos de save. Retry-save, checkpoint limpio y
restore no repiten modelos/tools/estimador. Los controles prueban deny ancestral,
JSV sin coerción, Ecto inválido y sensibilidad a datos distintos, requests y uso
duplicados. Un efecto de control positivo se distingue de cero efectos no
autorizados; no hay jueces LLM ni medida de inteligencia.

Matriz declarada antes de medir: seed131415,18 filas barajadas,32 warmups y200
muestras por fila, tres definiciones reutilizadas y c1/8/32 con OTel off/on. Dos
mini-soaks adicionales de200 runs/c8 duran2.628s/2.639s con callback2ms/exporter3ms;
no son un soak de horas. **4000/4000 runs medidos correctos**,10000 requests y
12200 spans medidos exportados localmente sin pérdidas normales. Warmups640,
saturación64 y kickoff1 se registran aparte, sin inflar ese denominador.

| Caso | Concurrencia | Off p50/p95/p99 (µs) | On p50/p95/p99 (µs) |
|---|---:|---:|---:|
| Simple | 1 | 44/99/568 | 112/187/282 |
| Simple | 8 | 283/399/728 | 336/514/721 |
| Simple | 32 | 362/553/597 | 565/1186/1383 |
| Tools + Ecto | 1 | 226/396/650 | 445/614/864 |
| Tools + Ecto | 8 | 749/872/920 | 857/1175/1303 |
| Tools + Ecto | 32 | 1052/1402/1475 | 1498/1923/2091 |
| Delegación + Ecto | 1 | 517/828/1005 | 829/1180/1440 |
| Delegación + Ecto | 8 | 1209/1623/1775 | 1735/2068/2214 |
| Delegación + Ecto | 32 | 1975/2361/2422 | 3034/3699/3971 |

Runtime1.20.0/OTP29.0.5,24 schedulers, sin afinidad cambiada. Latencia individual
excluye construcción, espera previa y drain. Recursos de la VM muestreados cada5ms
más coste de recolección y fronteras: máximo observado92,264,648 bytes BEAM (~88MiB),
432 procesos,19FDs,68ETS y mailbox35. Son máximos muestreados, no simultáneos ni
cotas absolutas. Retención normal máxima976/2048; tras cada fila pending/inflight0
y cero pids/ETS propios supervivientes. Cleanup máximo observado1793µs.

Barrera separada:642 intentos de span =32 aceptados +610 drops;30 pendientes y2
en vuelo ocupan32 slots mientras64 runs terminan. Tras liberar:32 exports en5
batches, sin supervivientes propios. El exporter es local/in-memory: no demuestra
recepción durable ni resuelve el HTTP nativo de N03.

**N14: no-change.** La matriz no identifica trabajo evitable en una función
concreta ni un SLO incumplido. Construcción medida es primer uso con carga lazy,
no percentiles calientes; se conserva la preparación por definición ya existente.
No se ejecutó un profiler ni se afirma ausencia de todo hotspot futuro.

Comandos con el prefix seguro de esta sección:
`mix run examples/framework_evals.exs --json <path>` y
`mix run test/support/framework_load_probe.exs --json <path>`;
`--smoke` valida una carga pequeña, sin usarla como dataset de rendimiento.
Artefactos: `/tmp/opencode/exagent-night-framework-{load,evals}.json`, muestras
crudas, hashes y recursos; informe `/tmp/opencode/exagent-night-load-evals.md`.
El JSON es el canal fiable, pues stdout puede incluir logs esperados.

### N16: documentación ejecutable y matriz revisada

Task `task_7337be7518bf` / Dispatch `ctx_236f352de8d4` completada; autor liberado.
`test/support/documentation_probe.exs` selecciona16 codeblocks reales, comprobando
ausencia/duplicados/vacíos y registrando origen/hash antes de sustituciones. Once
se ejecutan con fixtures/modelos explícitos; cinco quedan como sintaxis/receta
(Mix.install, Repo, MCP externo, Config y fragmento de dependencias).

Se reprodujeron dos defectos reales de README: ctx/days sin uso y expansión de
`%WeatherReport{}` dentro de la misma evaluación que define el módulo. El
coordinador los corrigió tras una barrera de compilación: `_ctx`, uso de days sin
renombrar su propiedad JSON, y pattern `%{__struct__: WeatherReport}`. No cambian
contratos de biblioteca. Probe final **7/7**, seed0, sin diagnósticos/exclusiones:
loop/stream, deftool, Ecto con rechazo y retry, Session/handoff/delegación, ambas
ramas RunError y tracing contextual/redactor. Un SDK nominal preparado sólo en
la VM permite observar8 spans; `new/1` no inicializa por ello el SDK.

La matriz anterior fue ajustada para atribuir los tres modos a las pruebas que
realmente los cubren y para reflejar la entrega N04/N12. Ejecución directa:
`EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs`
con PATH directo al runtime. Informe `/tmp/opencode/exagent-night-documentation.md`.
N18 volverá a ejecutar el probe con los BEAM recompilados y generará docs; recetas
externas y compatibilidad de modelos/backend siguen gates independientes.

### N18 en curso: reproducción de una suposición de batching en el test de restart

El primer full nativo limpio del verificador compiló73 fuentes de ExAgent, pero
dio618/619 correctos,28 excluidos, seed37556: el test de restart del processor
esperaba dos spans en el primer batch y recibió sólo `crossing_restart`. El mismo
archivo/seed pasó16/16 aisladamente. No se atribuyó el fallo a pérdida de spans.

Con la ventana raíz pausada, el coordinador reprodujo causalmente la intercalación:
terminar crossing, flush y barrera de recepción del primer export antes de crear
after_restart, reencolando ese mensaje para mantener la antigua aserción. El caso
dio0/1,15 excluidos con el mismo fallo. El exporter del fixture espera un ACK,
por lo que el segundo span pertenece legítimamente a otro batch.

Sólo se corrigió `test/exagent/observability/bounded_processor_test.exs`: conserva
esa barrera explícita y exige ambos exports por separado, nombres e IDs distintos,
accepted=exported=2 y retained=0, además de provider/tracer/ownership anteriores.
Focal compilado16/16 seed37556 y formato correcto. No cambió biblioteca, paquete ni
timeout; tampoco se relajó el conteo de entrega. Fuentes congeladas de nuevo y
N18 reabierto para revisión independiente y repetición de las suites completas.

Las compilaciones frescas revelan también warnings upstream (gproc/OTP29 y opciones
xref de dependencias), guardados por fase; exit0 del compilador con
warnings-as-errors del proyecto no significa que todo su grafo no tenga avisos.

### N18: cierre cross-version de startup y separación de artefactos

El TAR e665 pasó24 contratos strict en1.18 y24 en1.17, pero su grafo native1.20
sin SDK/API-only emitió un warning propio: la inferencia alcanzaba el helper
`sdk_available?()` y detectaba `dynamic(false)` en el match. Esto no quedó cubierto
por repetir sólo el mínimo después del primer fix. El coordinador reprodujo el
diagnóstico con compilación aislada real antes del siguiente cambio.

La selección final ocurre alrededor de `start_link/1` en compilación. La rama sin
SDK retorna directamente sdk_unavailable; la rama con SDK conserva validación y
start originales. Defaults y helpers privados sólo se compilan donde son usados,
sin warnings de código muerto ni supresión de inferencia. Prueba aislada con
telemetry real: cero diagnósticos en1.20/29 y1.17/27, incluso conservando unavailable
tras cargar SDK posteriormente; focal compilado SDK presente16/16 seed37556.
DESIGN8.9 y CHANGELOG reflejan esta decisión final, no el helper intermedio.

Al leer los nuevos artefactos se detectó otra colisión del runner: su diagnóstico
`graph.term` reemplazaba el grafo real que acababa de escribir el consumidor.
Una regresión del hijo que escribe un grafo sintético reprodujo la sustitución.
Los diagnósticos ahora usan `phase-*.term`, separados de graph.term/provenance.term;
la regresión exige ambos archivos y el aislamiento completo pasa. No se perdió
evidencia runtime de ejecución: los logs originales conservan el grafo observado,
pero la forma del artefacto anterior no se presenta como correcta.

TAR revisado para aceptación final:
`/tmp/opencode/exagent-night-final-reviewed-preview.tar`, SHA256
`d656bd2a83608046028e031e3d6585c606d9a2fcb6f2774ba793da0fcc6c008a`, nominal1.2.0.
Se preservaron todos los TAR anteriores. N18 vuelve a revisar/verificar los cambios
y sus tres matrices. El benchmark de4000 runs precede este ajuste sólo de startup,
fuera de su tramo medido; conserva su identidad histórica y N18 usa un smoke final.

### Cierre final N18 — 2026-09-10

Verificador fresco `task_7217175a868e` / `ctx_eb2d891ead54`, tras la última revisión
de carga/docs sin hallazgos. Ejecutó los gates con dependencias, tooling y builds
propios por runtime, sin editar fuentes. Se investigaron/reverificaron los fallos
anteriores; no se borraron sus evidencias ni se contaron excluidos como pases.

| Gate final | Elixir1.20.0 / OTP29.0.5 | Elixir1.18.4 / OTP28.0 | Elixir1.17.3 / OTP27.3.4.17 |
|---|---:|---:|---:|
| Compile forzado con warnings-as-errors | 73 fuentes, exit0 | 73 fuentes, exit0 | 73 fuentes, exit0 |
| Suite offline | **619 pass,0 fail,28 excluded** | **619 pass,0 fail,28 excluded** | **619 pass,0 fail,28 excluded** |
| Total incluyendo excluidos | 647 | 647 | 647 |
| Seed | 37556 | 37556 | 37556 |
| Duración ExUnit | 14.8s | 14.8s | 14.5s |
| C0 | 14/14 true | 14/14 true | 14/14 true |
| Snippets sobre BEAM propios | 7/7,0 diagnósticos | 7/7,0 diagnósticos | 7/7,0 diagnósticos |
| Probe R3 aislado | 1/1 | 1/1 | 1/1 |

El grafo fresco nativo emitió nueve warnings gproc y dos deprecaciones xref de
Postgrex/Req; están conservados por fase. Las73 fuentes del proyecto en el compile
final no emitieron diagnósticos. No se llama warning-free a ese grafo completo.

**Paquete final d656:**82 archivos y104 módulos por consumidor, todos desde bytes
vendor propios; los82 hashes del paquete coinciden con el checkout final. Doce
consumidores (none/API/SDK/exporter × tres runtimes) pasan **72/72 contratos runtime**.
Once pasan también strict; sólo exporter/OTP29 devuelve **exit1/phase_warnings**
por los nueve warnings gproc, conservando runtime_contracts=passed. No se suprimen
ni se actualiza la dependencia para ocultarlos. No hay warnings ExAgent residuales.

Directorios finales, todos bajo `/tmp/opencode/`:

- `exagent-night-package-n18-native-fresh-v2`:24/24 runtime,3/4 strict.
- `exagent-night-package-n18-118-fresh-v2`:24/24 runtime y4/4 strict.
- `exagent-night-package-n18-117-lock-v2`:24/24 runtime y4/4 strict.

Se comprueban grafo/provenance/SDK order/pisos de decoder y ausencia SQL/docs en
runtime. graph.term y phase-graph.term coexisten y el grafo coincide con el log.
Los entornos no heredan secretos/selectores/flags del host; preflight real precede
al bootstrap local. Los controles revisados de aislamiento pasan21/21 en native y
mínimo, sin instalar herramientas durante esos controles.

Siete ejemplos nativos salen0. Observability sin benchmark exporta9/9 y queda sin
cola; framework_evals funciona también **desde vendor del TAR en el consumidor
none**, con cases idénticos a raíz. Load smoke final:160/160 runs,400 requests,
488 spans medidos; saturación32 exports/50 drops y sin supervivientes propios.
Es una comprobación pequeña del código final, no una nueva medida de rendimiento.

Comandos principales reproducibles (con entorno directo/aislado por runtime):

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors --seed 37556
EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs
# Elixir directo y -pa al build PROPIO, no mix run:
EXAGENT_OFFLINE=1 elixir -pa '<build>/lib/*/ebin' test/support/documentation_probe.exs
```

Para R3 usar su cabecera con sólo SDK/API/telemetry. El driver temporal y el JSON
conservan todos los comandos completos, variables explícitas y exit codes:
`/tmp/opencode/exagent-night-final-driver.py`,
`/tmp/opencode/exagent-night-final-verification.{md,json,term}` y logs
`/tmp/opencode/exagent-night-final-n18/{native,118,117}/`. Las evidencias durables
son esta sección, los tests/probes y decisiones del repo; /tmp puede desaparecer.

El coordinador generó docs con warnings-as-errors en
`/tmp/opencode/exagent-night-final-docs` (HTML/Markdown/EPUB, exit0), después del
cierre de workers, y vuelve a generarlas al incorporar esta evidencia final.
Formato global y git diff --check pasan. HEAD sigue c08125be71eada363d08ca463cc7df2ea7855e4a;
lock conserva SHA256 f99728b5362bd570aa85c8d6a2ebfe178655ba3b726ba04a416990227f4d85f4
durante la aceptación final. WIP/untracked y versión nominal se preservan.

**Recursos:**16 Tasks/Dispatches terminados,15 workers distintos cerrados; uno se
reutilizó con contexto útil. El registro retained histórico de su primer intento
no es una terminal viva: su recurso final figura released y observation exited.
Mailbox vacío; no scheduler o trabajo posterior implícito al cerrar esta sesión.

**Alcance y límites:** aceptación local nocturna terminada, no toda C6/C8. Continúan
gates de HTTP nativo longevo, booleanos/partial_success, API/UI Langfuse/Opik,
proveedores/modelos/DB/consumidores reales y C7 condicionado. La escritura accidental
del Hex compartido se documentó/contuvo; su reparación sigue pendiente de autorización.
No hubo commit, bump, merge, publicación, despliegue, reinicio ni modificación de
Dragonex/WhoamAI. La inferencia Astra de workers no equivale a tests LLM pagados.
