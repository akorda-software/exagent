# R7.2 — alternativa OTLP/gRPC en consumidor privado

**2026-10-01: lote local verde; receta experimental, integración pendiente.**
El harness nuevo en `test/support/otlp_transport/` demuestra una alternativa con
SDK/API nativos, conversión oficial y cliente gRPC público. El límite HTTP1.10.0
de la [guía vigente](../guides/observability.md#7-native-otlp-http-measured-local-contract-and-limits)
permanece. Este lote no acepta G4 ni modifica la configuración/dependencias del
paquete o de aplicaciones existentes.

## Decisión y procedencia

Hex seguía publicando exporter1.10.0 al consultar el
[paquete oficial](https://hex.pm/packages/opentelemetry_exporter). La revisión
oficial [9cb8b3627cf68aeb0df7b3243378f0c2520cff66](https://github.com/open-telemetry/opentelemetry-erlang/commit/9cb8b3627cf68aeb0df7b3243378f0c2520cff66)
del2026-09-21 declara exporter1.11.0 **previo a release** y ya convierte booleanos
antes de átomos. Se descarga esa revisión exacta completa, sin editar sus fuentes,
y se copia su aplicación exporter al consumidor privado. API1.5.0, SDK1.7.0,
grpcbox0.18.0 y sus dependencias se copian del grafo local resuelto. No se añade
fork, parche, sustitución de módulo, decoder propio ni dependencia al core.

La combinación HTTP con Finch se descartó antes de implementarla: el encoder y
decoder generado del exporter están marcados `@private`. Un `export` Erlang no
convierte por sí solo ese contrato en público. El código de la receta usa:

- El callback nativo `otel_exporter_traces` y la conversión documentada
  [`otel_otlp_traces:to_proto/2`](https://opentelemetry-exporter.hexdocs.pm/otel_otlp_traces.html).
- El cliente documentado
  [`opentelemetry_trace_service:export/3`](https://hexdocs.pm/opentelemetry_exporter/opentelemetry_trace_service.html),
  que retorna el response gRPC completo y encapsula su encoder/decoder.
- Contexto con deadline y canal dedicado mediante las interfaces de
  [grpcbox](https://github.com/tsloughter/grpcbox). No se usa el callback stock que
  descarta el response, ni se inspeccionan nombres/perfiles HTTP privados.

Sólo el receptor sintético registra el módulo protobuf generado para que grpcbox
sirva el protocolo real. Es instrumentación del fixture, no una API requerida por
el exporter del consumidor. El mantenimiento sigue condicionado al pin oficial
previo a release y a revalidar las APIs/configuración al adoptarlo; no se afirma
que el paquete raíz ya tenga una nueva release estable.

## Ownership y contadores

Cada batch crea un canal con nombre de término/referencia, sin generar átomos por
PID. Un monitor independiente posee ese canal y lo cierra cuando termina el
callback o muere su worker. `sync_start: true` evita anunciar un canal antes de
tener subchannels. `stop(name, :shutdown)` cierra los subchannels/conexiones; la
variante predeterminada de `stop/1` usa `force_delete` y no equivale a ese cierre.
No se cierran canales de otra aplicación ni los servicios compartidos de inets.

El processor conserva su admisión/cola/deadline y nunca reintenta un batch. En el
fixture el exporter manda al observador sólo escalares y un indicador de warning;
no envía la respuesta, el texto remoto de error ni metadata/credenciales.

| Contador | Significado en este lote |
|---|---|
| `accepted` / `dropped_queue_full` | Admission propia del processor, incluida la carga en vuelo. |
| `sent` | Spans de la petición cuya entrega se intentó; el receptor prueba su llegada en este fixture. |
| `reported_accepted` / `rejected` | Resultado declarado por el response OTLP válido, no recepción durable del backend. |
| `unknown` | El callback falló/expiró sin confirmar aceptación o rechazo individual. |
| `exported` / `export_failed` / `export_timed_out` | Resultado del callback/batch según el processor, no suma de spans aceptados remotamente. |

Un partial con1 rechazo de2 conserva `reported_accepted=1,rejected=1` y devuelve
fallo del callback, por lo que el processor cuenta `export_failed=2`. El batch
entero se descarta sin replay. Un warning con0 rechazos conserva el indicador y
retorna éxito. Error/timeout conservan2 unknown. Si el worker muere no puede
mandar su receipt: `export_timed_out=2` muestra esa pérdida; el informe no inventa
una recepción o un rechazo individual para esos spans.

## Perfil ejecutado y resultado

Consumidor nuevo, Elixir1.20.0/OTP29.0.5, cuatro schedulers, loopback dinámico, datos
sintéticos,2 spans por batch, capacidad2 y un tercero rechazado en todos los
casos. Se ejecutaron success, partial, warning sin rechazo, gRPC error, timeout
del cliente y muerte por deadline del worker; después3 ciclos equivalentes de
success/shutdown. El reporte conserva los contadores completos de cada caso.

| Caso | Processor exported / failed / timed_out | Response aceptados / rechazados / unknown | Bytes protobuf request / response |
|---|---|---|---|
| Success | 2 / 0 / 0 | 2 / 0 / 0 | 417 / 0 |
| Partial | 0 / 2 / 0 | 1 / 1 / 0 | 417 / 25 |
| Warning | 2 / 0 / 0 | 2 / 0 / 0 | 417 / 21 |
| gRPC error | 0 / 2 / 0 | Sin confirmación / sin confirmación / 2 | 417 / no payload de éxito |
| Timeout cliente | 0 / 2 / 0 | Sin confirmación / sin confirmación / 2 | 417 / no payload de éxito |
| Worker terminado | 0 / 0 / 2 | Sin receipt del callback | 417 / no payload de éxito |

Los booleanos true/false llegan como `bool_value` en spans y resource; string/int
y las longitudes de IDs son controles independientes. Los bytes protobuf se
miden mediante el stats handler documentado del **servidor**: payload, no headers,
framing HTTP2 ni TLS. La petición ocupa1570 bytes de término Erlang externo; la
respuesta ocupa6/85/83 en success/partial/warning. Son medidas distintas.

Después del warmup de transporte **y de los propios gauges**, los3 ciclos
recuperan exactamente127 procesos,56 ETS,4 puertos,18 monitores y2 perfiles httpc.
Átomos constantes28316 en la ejecución final; no se añaden perfiles HTTP. Cuatro
PIDs propios monitorizados están DOWN en cada caso y no quedan sockets cliente
hacia el puerto del receptor. Una respuesta tardía no revierte el fallo/timeout.
El callback remoto que el fixture dejó esperando necesita su liberación propia:
cancelar el cliente no prueba rollback ni terminación del trabajo del servidor.

Los comandos `mix deps.get`, `mix compile --warnings-as-errors` y
`mix run --no-start probe.exs` salen0 en el consumidor privado. El compile conserva
**9 warnings upstream de gproc1.2.0 en OTP29**:8 bindings exportados desde
subexpresiones y1 `lists:zf/2` deprecado. Ninguno procede de los dos módulos
locales; no se suprimen ni se presenta el grafo como libre de warnings de deps.

Recepción final: `test/support/otlp_transport/receipt-2026-10-01.json`.
Artefactos detallados del lote: el path `consumer` del receipt, con
`commands.jsonl`, `deps.log`, `compile.log`, `probe.log` y `report.json`. El runner
por defecto no ejecuta el lote; el README del checkout `test/support/otlp_transport/README.md`
incluye el comando opt-in y tooling aislado.

## Límites y siguiente integración

El probe configura128 atributos y128 caracteres por string para los spans
sintéticos, con valores ASCII en este perfil: el límite upstream usa
`string:length`, no una cota general de bytes Unicode/arrays. Se configuran2 slots
del processor y2 spans/batch. La receta comprueba máximo8 spans y65.536
bytes de término convertido antes del IO y65.536 bytes de término response tras
decode; este lote no cualifica todas sus fronteras de máximo/máximo+1 ni payloads
arbitrarios. La conversión copia datos y el cliente upstream decodifica antes de
esa última comprobación: no hay garantía hard RAM predecode ni límite general de
bytes de todos los spans vivos/allocations del SDK.

Deadline del cliente250ms; deadline del processor1500ms, excepto el control de
worker muerto con150ms frente a cliente5000ms. La espera local de inicialización/
receipt de cleanup es1500ms y shutdown del processor1000ms. **El cierre público
de canal de grpcbox espera `infinity` internamente**: este lote prueba que termina
en los fallos elegidos, no un límite universal si el canal se bloquea al cerrar.
El guard podría permanecer en ese caso. El runner limita a45s la VM privada y
cierra sólo su grupo de procesos, lo que acota el experimento, no transforma esta
receta en operación longeva aceptada dentro de una VM compartida.

Falta integrar un run ExAgent/instrumentación real con la ruta elegida, cualificar
TLS/auth y destinos, y decidir una frontera mantenida de cleanup para un host
longevo. El siguiente gate debe conservar la separación de ownership/dependencia,
receipt remoto y aceptación durable. No se sustituye una prueba de ExAgent por
estos records sintéticos del SDK.

Un Collector puede recibir gRPC y exportar HTTP, pero su cola/export/lifecycle y
su respuesta parcial son otra frontera que debe medirse. No se desplegó ni
cualificó un Collector en este lote. Langfuse sigue
declarando [ingestión HTTP y ausencia de gRPC](https://langfuse.com/integrations/native/opentelemetry):
esta alternativa no es la ruta directa native→Langfuse. API/UI cloud, la elección
final de backend y G4 siguen pendientes.
