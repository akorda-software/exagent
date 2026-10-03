# Combinación de observabilidad — 2026-10-03

El usuario elige ExAgent como productor de spans en sus ejecuciones y autoriza
analizar y ejecutar el reparto con ReqLLM. Base: commit
`37fed281f369dfb2bea7a4f9a8ce6530e2f9e8ca`, ReqLLM 1.26.0 oficial.
El [recibo de evaluación anterior](OBSERVABILITY-OWNERSHIP.md) conserva el control
negativo y sus fuentes; sus cuatro casos no se presentan como pruebas de esta
implementación. Sin revisión independiente adicional, publicación, versión,
lock nuevo ni cambios en aplicaciones consumidoras.

## Decisión ejecutada

`ExAgent.Observability.ReqLLM.attach/1` registra una sola integración durante el
arranque del host mediante el behaviour público ReqLLM.OpenTelemetry.Adapter.
Dentro del contexto Model observado reutiliza el span ExAgent; fuera delega los
callbacks al OTelAdapter público stock. No alterna handlers alrededor de cada
petición, filtra spans ya creados, modifica ReqLLM o accede a su ETS privado.

La integración añade atributos permitidos de petición/respuesta, endpoint y
tiempo hasta el primer fragmento en segundos. Tokens, cache, coste cualificado,
estado, contenido y cierre permanecen en ExAgent. Los eventos y mensajes de error
upstream no entran en el span Model. El adapter ReqLLM pide payloads:none incluso
ante captura raw global; el redactor explícito ExAgent sigue controlando contenido.
La propagación de ownership es efímera; no cambia snapshots ni Store.

Un bridge stock incompatible o duplicado provoca un error de configuración
antes del IO en el adapter ReqLLM observado. Attach no elimina handlers ajenos.
Los Models que no usan ReqLLM siguen funcionando. Observability:false permite
la configuración standalone del host. El tracer/sampler elegido por ExAgent se
respeta también cuando no graba; no se sustituye por el provider default ReqLLM.

Migración y uso: [guía](../../guides/observability.md#reqllm-and-one-owner-for-request-spans),
[contrato](../../architecture/design.md#852-reparto-de-instrumentación-por-contexto-con-reqllm-stock-2026-10-03),
[alternativas](../../development/backend-evaluation.md#reqllm-and-exagent-instrumentation-ownership).

## Evidencia local

Claves sintéticas, HTTP/SSE loopback y SDK nativo. Sin APIs pagadas o cloud,
dotenv deshabilitado, EXAGENT_OFFLINE=1 MIX_ENV=test. Elixir 1.20.0/OTP 29.0.5
y Elixir 1.18.4/OTP 28.0; fuentes/deps/build/tooling privados para el segundo
runtime. Los 95 ficheros de runtime/config/Mix/lock son idénticos entre ambos.

| Ola | Resultado | Alcance |
|---|---|---|
| bridge-01 | 8 pasan, exit 0, 2.2 s | Primer reparto sync/stream, standalone y conflicto. |
| bridge-02 | 16 pasan, exit 0, 2.2 s | Añade privacidad, concurrencia, guard y callbacks adversos. |
| bridge-03 | 21 pasan, exit 0, 2.4 s | Añade sampling/named tracer, muerte/prune y controles de scope. |
| integration120 | 146 pasan, exit 0, 29.7 s | Incluye los 21 y observabilidad, ReqLLM, timeout, stream y host boundary. |
| integration118 | 146 pasan, exit 0, 32.6 s | Mismos casos y fuentes en el runtime mínimo. |
| doc-probe | 17 pasan, exit 0, 2.8 s | Ejecuta también el attach publicado en la guía. |

Sync y streaming hacen una sola petición HTTP, run→model y una generación con
2 output tokens, con y sin integración. El resultado conserva 3 input/2 output;
el pricing callback explícito se invoca una vez. La disponibilidad/cualificación
de input permanece distinta en este modelo dinámico sync/stream, sin inventarla.
Standalone mantiene su generación, timing y parentage de child callbacks.
Concurrencia usa barreras de respuesta, no sleeps como prueba de aislamiento.

Se cubren raw global y opciones content/langfuse, atributos adversos que intentan
sobrescribir accounting/estado/cierre, provider stop rechazado por el guard,
conflictos sin IO, no-ReqLLM, observability:false, sampler y provider nombrado.
Muerte del owner sync/stream cierra los spans ExAgent; el prune público retira
una entrada upstream pendiente y después devuelve cero.

## Instalación como paquete

TAR de verificación SHA256
`bcabae0f0ea6e51763ed955b7ff57032cd05addd9a16792e743df0a9ec2e0a70`:
169 ficheros idénticos al checkout en ese momento, incluidos 91 lib + mix.exs.
Versión nominal 1.3.0; añade el módulo de integración sin alterar dependencias.
Se construye desde el mirror privado 1.20 con los mismos 95 inputs de runtime.

Cuatro consumidores limpios none/API/SDK/exporter, sin lock del checkout:
7 contratos por grafo, **28 pasan**, cero fallos/exclusiones/skips.
Los 23 comandos únicos de tooling/deps/compile/graph/smoke terminan con exit 0.
El runner estricto termina con **exit 1** por TOML/WebSockex y gproc en exporter;
sin warnings ExAgent, supresión o fork. No confundir PASS funcional con strictdeps.

Un primer lanzamiento no llegó a instalar tooling: el driver omitía HOME al
usar un entorno mínimo y el preflight OTP falló. Se conserva; la ola anterior
propaga el HOME real sin cambiarlo y mantiene destinos de tooling aislados.
No se presenta aquella preparación fallida como un grafo ejecutado.

## Identidad de fuentes

| Fichero | SHA256 |
|---|---|
| lib/exagent/models/req_llm.ex | 538edf0241f07ec16cb55f4775c413fd8a5f17ee3a4deb68b7bab73cb6d86220 |
| lib/exagent/observability/open_telemetry.ex | 45edad26622c48a4e847aede8b2eb5b73b4acfcd5e055d27acb2f6d1c226fcad |
| lib/exagent/observability/req_llm.ex | 9b4e7981c6a3c728889f10cc235e949e735a943aa3aebc2bdfe7eed9b4b77bfc |
| test/exagent/observability/req_llm_bridge_test.exs | 421bbce922fd69fe120501d174574ee39cb5c9275a32be8981e393746f7c25b8 |
| test/support/documentation_probe.exs | e1552a2c8f304eefd6c15907a5c1e632e8cd98dabfbbf6246bbf5cc839e4fe68 |
| mix.exs | e0626c69638684b2008ecc1d801c518a10ee37153ec31c958fe111f216a785fc |
| mix.lock | 2637e0965ebdb015e04d505757bf0de5649affc35670ee77aa11745ecbbcdaeb |

Logs, hashes de los 95 inputs y recibos por fase:
`.exagent-local/otel-combination20261003/`.

## Rutina local completa

Primer bin/check: exit 1, 13.694 s; harness rojo antes de arrancar FULL.
El probe seleccionaba el segundo bloque dentro de una sección que ahora contiene
subsecciones y lanzó Enum.OutOfBoundsError. Se corrigió la selección por heading
explícito y se añadió evaluación del attach, sin cambiar runtime ni relajar oráculos.
Los 17 ejemplos pasan tras la corrección; el fallo inicial conserva su recibo.

Segundo bin/check: **exit 0**, 2016.977 s. Nueve fases terminan con exit 0:
whitespace, staged-whitespace, format, harness, suite, docs, docs-links, package
y package-isolation. FULL Elixir 1.20/OTP 29: **2198 pasan, cero fallos y 28
exclusiones**, 1976.3 s (25.3 async, 1951.0 sync). Las exclusiones siguen siendo
22 live-provider y seis PostgreSQL, filtradas antes de ejecutar; no timeouts/pases.
No se presenta la focal 1.18 como una nueva suite completa 1.18.

La documentación estricta genera 118 HTML/5260 targets, 116 Markdown/860 targets
y 116 EPUB/2906 targets, sin enlaces/anchors/resources locales rotos. El TAR de
esta rutina coincide byte a byte con el de los cuatro consumidores anteriores.
Logs: `.exagent-local/checks/20261003T145435Z-2052846/`.

El cierre documental incorpora estos resultados después de aquella rutina.
Primera generación final: exit 1 por tres referencias a recibos que no forman
parte de los extras ExDoc. Se sustituyen por enlaces al repositorio; el fallo
se conserva en final-docs.log. Segunda generación estricta y enlaces: exit 0,
118 HTML/5263 targets, 116 Markdown/863 targets y 116 EPUB/2909 targets, errors=[].
Formato, whitespace, build e isolation finales terminan con exit 0.

TAR final SHA256
`13f8cc9175625642159db1391fe0d2de65ae0bdb54e9a4eb16035674bc3ace3c`:
169 ficheros exactamente iguales al checkout; metadata y los 92 lib/Mix inputs
son idénticos al TAR probado en consumidores. Sólo cuatro documentos difieren:
design, changelog, roadmap y status. Se conserva el checksum de cada TAR;
no se repite FULL ni se atribuyen las pruebas del primero a otras fuentes.
Los recibos de ejecución, tests, lock y datos privados quedan fuera del paquete.
Las fuentes runtime/config/Mix/lock finales siguen iguales a los 95 inputs
verificados antes de ambas olas focales y FULL. Esta edición del recibo queda
fuera del TAR y no cambia su identidad.

## Límites que conserva la integración

ReqLLM mantiene su tracking in-flight. Muerte sin terminal puede dejar una
entrada; el host debe programar prune_stale_spans con TTL mayor que sus peticiones
activas permitidas. Prune elimina entradas, no finaliza spans; el watcher ExAgent
cierra los propios. No prometer límite duro de RAM upstream, cierre standalone
por prune o recuperación tras muerte del SDK/VM.

API 1.5/SDK 1.7 no suministra las meter APIs que comprueba ReqLLM. Se delegan sus
callbacks opcionales sin afirmar aceptación de métricas/exporter. La configuración
de handlers es estable desde el arranque; instrumentaciones arbitrarias de terceros
y cambios concurrentes de handlers quedan fuera de esta cualificación.

Langfuse y Opik conservan su aceptación equivalente anterior del perfil A10.
Este reparto y sus atributos adicionales tienen evidencia local nativa, sin una
nueva ola cloud/API/UI. Strictdeps, versión/tag/notas y pipeline/publicación Hex
siguen separados de esta implementación.
