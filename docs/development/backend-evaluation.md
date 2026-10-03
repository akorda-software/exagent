# Elección y aceptación del backend de observabilidad

**Mandato vigente 2026-10-02:** el usuario exige que **Langfuse y Opik queden
igual de validados**. Esto sustituye el criterio anterior de elegir sólo un
backend de referencia. Ambos deben demostrar el mismo escenario A10 con fuente
de candidata identificada: exportación nativa real, lectura API completa y
diagnóstico en UI autenticada de árbol, reintentos, checkpoint, pausa/resume,
correlación, contadores, calidad/procedencia/unidades y privacidad. Las diferencias
de IDs, tipos y presentación se registran mediante una correspondencia comprobada;
no se rebaja un oráculo para declarar equivalencia. Langfuse conserva su aceptación;
Opik cualifica transporte nativo y API33/33,667atributos y12modelos/uso;
la UI autenticada verifica los mismos12casos/248atributos que Langfuse y siete
vistas reales inspeccionadas. G4 ampliado aceptado en el perfil A10 finito.
La navegación/captura del navegador sigue inestable; no se certifica su
disponibilidad. Recibos,
plazos y fallos preservados en el registro de aceptación del checkout
`docs/orchestration/2026-10-01-v2-codex/OPIK-ACCEPTANCE.md`.

La pasada crítica027 posterior incorpora controles causales del arnés para
descendientes, rollback de secretos privados y contenido Opik inesperado. Limitar
la privacidad observada anteriormente a campos esperados/input-output/sentinels;
la nueva frontera ante metadata/error_info extra se verifica offline, sin nueva
ola cloud ni inferir que los datos aceptados contuvieran esos extras.

La preparación Opik024 reutiliza el A10 nativo y una proyección opcional propiedad
de la aplicación: conserva cada atributo/booleano/recurso como metadato mediante
el prefijo documentado `opik.metadata`, deriva la correspondencia UUID desde la
fuente pública fijada y comprueba las dos trazas completas. Los tools con contenido
off se representan como `general`; operación y estado siguen siendo verificables
en metadatos. Receta y controles del checkout:
`test/support/langfuse_acceptance/OPIK.md`. Ni ese mapeo ni los controles offline
aceptan el build cloud o la UI antes de observarlos.

**Estado2026-10-02:** Langfuse es la referencia cualificada del perfil A10
native→Collector→cloud. La pareja flow/recovery de candidata019 tiene33/33
observaciones verificadas por API,667atributos y12modelos/uso, parentage/estados
y privacidad. Una ola de cinco POST; la lectura final sólo tres GET/734ms, sin
repetir productor/SDK/Collector. G4 UI aceptado mediante inspección autorizada
de la sesión autenticada del usuario:12observaciones/248atributos coinciden y
cinco capturas muestran estados, IDs y costes estimados. Recibo a2058c08…d8f3.
ACK, API y UI no certifican retención durable o factura. Recibos/identidad y límites en
[roadmap](roadmap.md). Sin decisión de despliegue.

**Comparación histórica2026-09-27: APIs aceptadas; Langfuse referencia provisional.**
Ambos proyectos cloud autorizados recuperan74 spans/15 trazas sintéticas. Langfuse
conserva IDs OTLP y tipos tool/agent con el perfil neutral; Opik regenera IDs y
requiere correlación adicional. En esa fecha UI y ruta nativa estaban pendientes;
la cualificación posterior se registra arriba y no altera aquellas trazas.
Recepción, identidades y límites en
`../archive/2026-09-27-external-gates-receipt.md`; estado único en roadmap§5.

**Implementación recibida2026-10-01:** la instrumentación nativa ya distingue
`paused` y publica el intento y la referencia de continuación, con pruebas
deterministas sync/stream/Server. Esa corrección posterior no actualiza las trazas
cloud de la comparación histórica. La pareja019 posterior cualifica el escenario
compuesto y los intentos de pausa/resume por API y la inspección UI posterior;
no reimplementar esos atributos
por leer el diagnóstico fechado de abajo.

Esta página desarrolla **R7.1–R7.3/A10/G4** del [plan de producción](roadmap.md). Se busca una
integración de referencia general del paquete, sin depender de la migración de
Dragonex/WhoamAI. Empezar por transporte/configuración local; el acceso al backend
es necesario para cerrar su aceptación, no para realizar esa preparación.

**Ampliación histórica autorizada 2026-09-27:** evaluar **Langfuse y Opik** como alternativas
para G4 y elegir la integración de referencia por evidencia. No se exige migrar ni
certificar ambos para cerrar el gate en aquel alcance; el mandato del2026-10-02
supersede esa exención. Se mantienen los datos sintéticos y la
preservación de cualquier histórico existente.

Se evaluaron únicamente los proyectos sintéticos autorizados exagent en Langfuse
EU y Comet Cloud/Opik. Los builds cloud no se exponen en las APIs consultadas;
ningún histórico ajeno se inspeccionó. La disponibilidad de otras instancias Opik
no implica permiso para modificarlas o leer datos reales.

## Lo decidido

- OTel nativo y configuración de SDK/exporter propiedad de la aplicación.
- Collector opcional; ExAgent no incorpora la plataforma al core.
- Contenido off, opt-in con redactor previo y límites; sin serializar modelos,
  deps, credenciales o baggage en atributos.
- Langfuse y Opik tienen aceptación A10 por transporte/API/UI con las mismas
  fronteras. La comparación API histórica permanece separada. La entrega
  documenta dos integraciones cualificadas, sus recetas
  y diferencias verificadas. No decide un despliegue ni certifica otros perfiles.
- A calidad comparable se prefiere más funcionalidad sin licencia comercial.
  Funciones administrativas comerciales sólo compensan por una ventaja demostrada;
  esa preferencia no autoriza compras ni necesita preguntarse otra vez.

## ReqLLM and ExAgent instrumentation ownership

**Decisión posterior2026-10-03:** el usuario elige ExAgent como único productor
de spans en sus ejecuciones y autoriza implementar la combinación. Se añade
`ExAgent.Observability.ReqLLM.attach/1` como adaptador público del bridge stock:
ReqLLM enriquece el span Model existente y conserva spans standalone. Accounting,
privacidad, identidad y lifecycle Model siguen en ExAgent. La evaluación anterior
y su negativo se conservan abajo; no son el comportamiento actual del adapter.
No se activa una publicación o bump por esta decisión.

Fuentes oficiales fijadas a la dependencia instalada:
[guía de telemetría ReqLLM1.26](https://github.com/agentjido/req_llm/blob/v1.26.0/guides/telemetry.md),
[bridge y lifecycle](https://github.com/agentjido/req_llm/blob/v1.26.0/lib/req_llm/open_telemetry.ex),
[atributos](https://github.com/agentjido/req_llm/blob/v1.26.0/lib/req_llm/open_telemetry/attributes.ex)
y
[mapper público](https://github.com/agentjido/req_llm/blob/v1.26.0/lib/req_llm/telemetry/open_telemetry.ex).
Las fuentes del lock, la guía y un control local con SDK real sustentan la
comparación; no se infiere comportamiento de una versión futura.

| Responsabilidad | ReqLLM1.26 | ExAgent actual |
|---|---|---|
| Petición al modelo | Bridge opt-in: atributos de petición, respuesta, errores, tokens y costes disponibles. | Span del contrato Model, incluidos adapters ReqLLM y Models custom/Test. El bridge integrado reutiliza ese span; los bridges independientes se solapaban. |
| Tiempo de primera salida y métricas | Timing de streaming, histogramas de duración/tokens/primera salida si el adaptador dispone de métricas; más detalle del cliente. | La integración conserva el timing y delega métricas a ReqLLM si el host tiene sus meter APIs. El perfil API1.5/SDK1.7 observado no dispone de ellas; no se afirma exportación de métricas. |
| Herramientas | Puede representar herramientas built-in ejecutadas por el proveedor; la ejecución de funciones del caller corresponde al caller. | Ejecución local, permisos, error, delegación y contexto de las herramientas del agente. |
| Ejecución y coordinación | No conoce el loop, Server, Session, Composition o Flow de ExAgent. | Árbol de operaciones, IDs de run/paso/intento y contexto a través de workers. No se promete un span para cada API administrativa. |
| Aprobación y recuperación | La petición termina; no observa el record durable ni la espera humana. | Pausa cierra el intento; resume abre otro con identidad durable, checkpoint y contadores de lifetime. |
| Uso y coste | Datos normalizados de la petición y coste calculado cuando está disponible; no conoce las admisiones o agregados de ExAgent. | Proyecta el ledger existente: admisiones exactas, tokens cualificados, disponibilidad/procedencia y costes estimados; no ejecuta otro callback de precios. |
| Privacidad | Contenido off; opt-in requiere payloads raw y modo de captura. Su política es independiente de ExAgent. | Contenido off, redactor explícito, límites previos al SDK y allowlist de identificadores. |
| Muerte abrupta del worker | Sin evento terminal puede quedar una entrada ETS; detach/prune elimina la entrada, sin finalizar aquel span. | Watcher cierra la operación y conserva sólo progreso conocido, parcial; no recupera tokens no reportados. |
| SDK/exportación | Usa el SDK/exporter de la aplicación; no instala transporte cloud. | Misma autoridad host. BoundedProcessor limita la ruta de exportación y puede procesar spans de otras instrumentaciones. |

### Qué hemos demostrado sobre el solapamiento

El negativo original del commit37fed28 usa **ReqLLM1.26 stock**, SDK
nativo, clave sintética y un servidor HTTP/SSE en loopback; no TestModel, API
pagada ni Collector/backend cloud. Matriz sync/public run_stream × bridge ReqLLM
desactivado/activado explícitamente: cuatro casos pasaron. El test actual mantiene
el servidor/SDK y comprueba la integración y el rechazo, no espera duplicación.

| Configuración observada | Peticiones HTTP | Spans por ejecución | Suma de output tokens de generaciones | Resultado ExAgent |
|---|---:|---|---:|---:|
| Sólo ExAgent | 1 | run → model | 2 | 2 |
| Ambos bridges | 1 | run → model → cliente ReqLLM | 4 | 2 |

El parentesco y trace ID coinciden en ambas superficies. Los contadores de
ExAgent siguen1request/0tools y sus tokens3input/2output: **el solapamiento está
en observaciones, no en otra petición o un doble cargo observado**. Se comprueba
ausencia de prompt/respuesta/clave sintética en los atributos con contenido off.
Los cuatro casos no certifican todos los campos, paths de error, métricas, privacy
opt-in ni facturación/UI de las plataformas.

El input GenAI no se usa como oráculo de duplicación: para este modelo dinámico
la proyección sync de ExAgent conserva el valor normalizado3 sin afirmar
semántica inclusiva, mientras streaming sí dispone de esa semántica. El bridge
ReqLLM publica input3 en ambos. No convertir esa diferencia en datos perdidos ni
equivalencia de los contratos de accounting.

Se conservan dos montajes fallidos del nuevo fixture: el primero asumía
`:text_delta` en la API pública y sólo claves string; el segundo suponía la misma
disponibilidad de input GenAI en sync/stream. Se corrigieron esas expectativas
según el contrato y los atributos observados, sin cambiar biblioteca/guards.
Logs locales: `.exagent-local/prepublish-20261003/bridge-01..03.log`.

### Alternativas y decisión para v2

| Alternativa | Ventaja | Coste o pérdida |
|---|---|---|
| Sólo ReqLLM | Una instrumentación de cliente con buen detalle de petición y métricas. | Pierde las operaciones, identidad durable, host counters y Models no ReqLLM de ExAgent. No sustituye la observabilidad del framework. |
| Sólo ExAgent para runs ExAgent | Un span Model por petición, mismo perfil para todos los Models, privacidad/lifecycle propios y aceptación A10 existente. | Mantiene la pequeña proyección Model y no incorpora automáticamente todas las métricas/atributos ReqLLM. |
| ExAgent para orquestación + ReqLLM como único productor del span de generación | Puede reducir mapping propio y aprovechar detalle/metrics del cliente. | Requiere diseño de identidad, accounting, cancelación, Models custom, privacy y scope; no está implementado ni cualificado. |
| ExAgent produce el span; adaptador ReqLLM lo enriquece | Conserva ownership y añade datos de cliente usando el mapper/behaviour público stock. ReqLLM standalone conserva sus spans. | Requiere attach host integrado y conserva el mantenimiento TTL del tracking upstream. Opción elegida e implementada. |

**Decisión ejecutada:** ExAgent conserva su span Model y el bridge integrado añade
sólo request_id, response_id/model, server.address/port, max_tokens, stream y
time_to_first_chunk en segundos, con labels256bytes y tipos/rangos comprobados.
No exporta eventos/error messages/contenido upstream, no termina aquel span y no
sobrescribe tokens, cache, uso/coste cualificado o estado del guard ExAgent.
El perfil GenAI sigue fijado a b5d8440; estos atributos estándar de petición/
respuesta/timing están en aquella revisión, sin schema URL inventado.
ReqLLM normaliza y calcula sus propios datos; la proyección de ejecución sigue
usando el Response/ledger público existente y un pricing callback como máximo.
No se instala otro SDK, transporte Langfuse/Opik, pricing table o parser.

Delegar sólo la generación es una alternativa razonable si demuestra una mejora
de mantenimiento o diagnóstico. No basta con borrar el span Model: su estado
describe también la aceptación del resultado por el contrato ExAgent, mientras
una petición de proveedor puede terminar correctamente y fallar después nuestros
guards. La alternativa debe conservar o representar explícitamente esa diferencia,
el contexto/tracer host, los IDs, la cualificación del uso, la muerte del worker
y los Models que no utilizan ReqLLM. Tampoco puede prometer que nuestro redactor
controle un span de otro productor.

ReqLLM attach sigue global; el reparto usa su Adapter público y contexto Model
ephemeral ExAgent propagado por workers. El host hace un único attach integrado,
sin alternar handlers por llamada. Fuera de aquel contexto delega todos los
callbacks stock, incluidos child spans y métricas opcionales. NativeAPI sin SDK
sigue no-op; el tracer/sampler elegido por ExAgent no se sustituye por el default
de ReqLLM. El host con otro bridge recibe conflicting_req_llm_bridge al attach,
sin perder su handler. El adapter ReqLLM observado rechaza también handlers
incompatibles/duplicados antes de IO con observability_conflict. Models que no
usan ReqLLM no se bloquean; instrumentación arbitraria ajena y cambios de
handlers en caliente no se cualifican.

El adapter fuerza telemetry payloads:none incluso ante raw global. Content/langfuse
del bridge sólo afectan a llamadas standalone; el redactor ExAgent sigue siendo
la frontera del Model observado. El bridge stock todavía almacena in-flight ETS:
owner death sin terminal deja una entrada y el prune público la retira. La
integración expone prune_stale_spans(ttl_ms) para mantenimiento periódico host,
sin acceso al ETS privado ni prometer limpiar aquel estado desde nuestro watcher.
TTL debe superar las peticiones activas permitidas. Es un límite upstream
observado, no un span ExAgent abierto ni una garantía de memoria upstream dura.

El test actual incorpora sync/public stream con y sin bridge integrado, llamadas
standalone sync/stream, concurrencia por barrera, provider stop rechazado por
ExAgent, sampling/named provider, proyección de atributos adversos, raw global,
conflictos/no IO, y owner death/prune en ambas superficies. Estos controles
qualifican la frontera local; los resultados finales quedan en roadmap/CURRENT.
Los anteriores rojos y el recibo de duplicación mantienen su identidad.

BoundedProcessor/exporter es otra responsabilidad: cambiar el productor de spans
no elimina la necesidad de cola finita, pérdida observable y lifecycle de
transporte. Langfuse y Opik mantienen **la misma aceptación A10 del perfil ExAgent**;
no se reetiqueta esa evidencia como aceptación ReqLLM-only o híbrida. Un cambio
del productor/perfil requiere actualizar diseño/migración y comprobar las
fronteras nativas/API/UI afectadas en ambos, sin repetir gates ajenos por rutina.

## Pendientes registrados tras la comparación histórica

La lista siguiente conserva el diagnóstico del 2026-09-27. La ruta nativa,
lifecycle acotado, reintentos y atributos de pausa/resume ya tienen aceptación
posterior API/UI en el perfil A10 descrito arriba. No reactivar esas tareas desde
esta lista. Los escenarios cloud no probados conservan sus límites.

1. UI autenticada: localizar error/tool/checkpoint retry, costes cualificados y
   los dos intentos tras restart; registrar pasos y campos, no inferir UI desde API.
2. Ruta directa nativa y lifecycle: la comparación utilizó captura local y relay
   acotado, no certifica operación longeva, partial_success, saturación ni cleanup.
3. Revalidar en API/UI los atributos actuales de paused e intento, junto a la
   correlación de aprobación entre VMs. La comparación histórica observó el gap
   anterior; la corrección offline del core no certifica la presentación cloud.
4. Completar missing/normalized-zero/cache/cancel y presentación del coste estimado
   sin sumar agregados inclusivos ni confundirlo con factura. Builds cloud/planes
   efectivos siguen sin verificación; no inferir funcionalidades por ofertas públicas.

No registrar valores de credenciales aquí. Crear infraestructura, contratar
servicios o cambiar consumidores requiere alcance explícito.

## Gate previo: transporte fiable

El recibo histórico HTTP1.10.0 pierde tipos booleanos. La revisión de
[dependencias](dependencies.md) adopta la release1.11.0, que corrige esa pérdida.
El exporter HTTP sigue ignorando successful `partial_success` y conservando
recursos HTTP/perfiles/átomos en ciertos ciclos.
El processor limita sus propios recursos, pero no corrige ese lifecycle ajeno.
Resolver o verificar una alternativa de transporte/ownership antes de presentar
esa receta como operación longeva aceptada. La
[guía de observabilidad](../guides/observability.md) conserva el detalle.

## Comparación con el mismo escenario

Comparar Langfuse y Opik contra los mismos criterios y registrar la elección.
Reutilizar instancias disponibles; no hace falta desplegar dos plataformas por
rutina ni migrar datos existentes para cerrar el gate de backend.

Reutilizar `test/support/native_otlp_scenario_probe.exs` y los datos sintéticos
de las pruebas. Fijar versiones de las plataformas evaluadas y revisar sus docs/licencias
actuales antes de conectarlas; las fuentes históricas no certifican la versión futura.

| Tarea de diagnóstico | Qué comprobar en API y UI |
|---|---|
| Reconstruir un run | Un span por operación, parentesco, IDs y delegación; sin spans por token. |
| Encontrar fallo/retry | Corrección explícita, tool con efecto previo, error posterior a hook y cancelación parcial. |
| Explicar uso/coste | Requests frente a subtotales inclusivos, cache, datos desconocidos y ningún doble conteo. |
| Recuperación | Primer save fallido y retry-save sin reabrir ni repetir el run. |
| Pausa/continuación | Aprobación persistida, reinicio y nuevo intento correlacionado; sin doble coste ni spans vivos durante la espera humana. |
| Privacidad/contexto | Contenido permitido/redactado y separación de callers; sentinels privados ausentes. |
| Operación | Backend caído/lento, pérdida observable, latencia y recuperación de recursos. |
| Producto y licencia | Funciones realmente usadas, limitaciones OSS, pasos de diagnóstico y esfuerzo de operación. |

HTTP200 y un árbol visual parecido no bastan. Registrar información perdida,
aciertos, pasos/tiempo para localizar cada fallo y límites operativos. La decisión
final debe explicar por qué una opción sirve mejor a esas tareas.

Prompts, datasets, scores, evaluaciones e históricos tienen integración/migración
separada: cambiar endpoint OTLP no los traslada. Después de decidir, actualizar
[estado](../status.md), [roadmap](roadmap.md), guía y aceptación del paquete.
