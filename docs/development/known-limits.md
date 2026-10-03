# Límites conocidos: causa, corrección y seguimiento

Investigación del **2026-10-03**, sobre la candidata v2 y ReqLLM1.26 stock.
El [estado](../status.md) distingue resultados actuales de recibos históricos.

## Extracción nativa DeepSeek: contrato de la aplicación

El caso08 esperaba comercio y moneda exactos, pero el `Receipt` de la demo sólo
declaraba `items` obligatorio. Sus campos de cabecera admitían `null` en JSON
Schema y Ecto. Esa permisividad es útil para mostrar tickets parcialmente legibles,
pero no expresa la exigencia de una extracción de cabecera completa.

ExAgent refleja el changeset del consumidor; no puede decidir qué datos son
obligatorios en cada dominio. `ExAgent.OutputSchema.validate/2` aceptaba el objeto
con cabecera incompleta conforme a ese contrato. Esto no demuestra fidelidad
semántica del modelo: el oráculo de la aplicación lo rechazaba correctamente.

**Corrección:** el E2E nativo usa ahora `ChatApp.E2E.NativeReceipt`, cuyo changeset
declara `merchant` y `currency` obligatorios. ExAgent deriva strings no nullable
y los incluye en `required`; si faltan, la validación local rechaza. La demo
conserva su esquema parcial. Prompt, dato sintético, oráculo, API, muestreo y
retries0 permanecen. No se rellenan campos ni se cambia el parser de la biblioteca.

Se probaron cinco peticiones reales acotadas:

| Control | Resultado | Peticiones |
|---|---|---:|
| Header obligatorio, mismo prompt/oráculo, DeepSeek | Correcto: TEST MARKET/EUR, fecha/total e item exactos |1|
| Mismo cambio, Luna | Correcto |1|
| Volver al contrato nullable, DeepSeek | Falla otra vez: merchant/currency null |1|
| Fixture final NativeReceipt, DeepSeek | Caso08 completo pasa |1|
| Fixture final NativeReceipt, Luna | Caso08 completo pasa |1|

La rutina offline del consumidor pasa **20 casos /0 fallos /27 exclusiones**,
incluidas tres regresiones del contrato: rechazo del fallo observado, schema
requerido y valores completos aceptados sin completar datos ausentes.
Los52 inputs ejecutables/config/lock del WIP coinciden con la copia probada;
los95 inputs de biblioteca coincidían en el freeze previo a añadir esta página
a ExDoc. Esa corrección08 no cambió el runtime; las mejoras de operación
posteriores se describen abajo con sus propias pruebas.

La cobertura conjunta pasa a **27/27 por modelo** reutilizando los26 casos
inalterados y cualificando sólo el08 nuevo. No es una nueva ola completa27/27.
La extracción con el antiguo contrato nullable conserva su fallo; tampoco se
demuestra determinismo, otro proveedor, reasoning activado ni cualquier schema.
Los cinco controles consumen USD0.125 de reserva, sin factura observada. Las
fases smoke existentes quedan en Luna53/60 y DeepSeek57/60, sin reset/refund;
las fases complex permanecen separadas.

Para una integración, declarar en el changeset los datos que realmente exige
la aplicación. Mantener la validación semántica independiente: un string presente
todavía puede contener un comercio equivocado. Ver [Tools and output](../guides/tools-and-output.md)
y [E2E del consumidor](real-consumer-e2e.md).

## Tracking abandonado ReqLLM: mantenimiento supervisado

Ahora la aplicación puede añadir `ExAgent.Observability.ReqLLM.Maintenance` a
su supervisor con `ttl_ms:` e `interval_ms:` explícitos. Ambos son enteros
positivos; el intervalo admite1..4_294_967_295ms. El child usa únicamente el prune
público del bridge integrado y queda dormido cuando éste no está instalado.
No inicia SDK ni handlers, no termina spans y no retira entradas de otro bridge.
Parar o reiniciar el child conserva la configuración de tracing del host.

**Precondición:** TTL mayor que la duración máxima de todas las peticiones
ReqLLM permitidas, incluidas standalone/stream/retries. Si alguna puede durar
indefinidamente, ningún TTL finito cumple: acotar esas peticiones antes de activar
el mantenimiento. La edad no demuestra muerte; un TTL corto puede eliminar
tracking activo. No es un límite duro de RAM
ni de la tabla upstream. `stats/0` devuelve ticks, pases y entradas retiradas,
sin IDs/contenido/spans; sus contadores se reinician con el proceso.

Las pruebas hacen32 cancelaciones por owner kill y4 requests sanos sobre
HTTP/SSE local, en dos oleadas por superficie. Tras una pasada posterior al TTL,
no queda tracking abandonado; las peticiones activas más cortas que el TTL
conservan su ID/terminal y una única generación. Streaming puede retirar entradas
por su propio evento de excepción: no atribuir todas las bajas al mantenimiento.
También se comprueban configuración, supervisión, timer obsoleto, otro handler y
parada sin detach. Ver [guía](../guides/observability.md).

## Exporter HTTP: reinicios acotados, limpieza upstream aún abierta

`BoundedProcessor` añade `max_exporter_restarts`: entero no negativo, o infinity
para conservar el default anterior. Al agotar el presupuesto de reinicios
por instancia, desactiva admisión, descarta spans pendientes y permanece
unavailable. No reejecuta batches ni efectos. Un callback de error terminado no
recrea worker; los nuevos contadores exporter_restarts/restart_limit_reached son
numéricos y acumulativos sólo en esa instancia. Reiniciar SDK/app/VM lo resetea.

El control nativo con presupuesto0 y exporter1.11 crea **un solo perfil**.
Un POST retenido agota su deadline y tres admisiones posteriores se descartan,
sin nuevo worker/perfil/POST. El socket original sigue vivo: limitar recreaciones
no lo libera, ni elimina átomos existentes. Sólo el probe, dentro de su VM
exclusiva, cancela su petición y cierra el perfil mediante APIs públicas OTP.
Los controles ilimitados anteriores conservan su resultado negativo.

La consulta Hex confirma1.11; su shutdown HTTP no libera el perfil. Las fuentes
oficiales main inspeccionadas también conservan perfil derivado de PID y shutdown
sin limpieza HTTP. La solución completa requiere un lifecycle upstream o una
frontera de exporter VM propia cualificada; no introducir inspección privada de
perfiles ni cerrar inets compartido desde la biblioteca.

## Métricas: incompatibilidad concreta de las APIs opcionales

El bridge stock ReqLLM1.26 requiere `otel_meter_provider.get_meter/3` y
`otel_histogram.record/4`. El [API experimental0.6 publicado](https://hex.pm/packages/opentelemetry_api_experimental/0.6.0)
exporta get_meter/1–2 y record/5; create_histogram/3 sí coincide. Añadir solamente
ese paquete no satisface el detector de capacidades stock. El API estable1.5
del lock no incluye esas APIs de métricas.

Se verifican fuentes oficiales de ambos paquetes experimentales0.6 y checksums
de sus TAR; sólo inspección, sin instalarlos o cambiar el lock. La aceptación de
trazas no cubre histogramas/exportación de métricas. Un adapter público compatible
o una corrección upstream necesita su propia aceptación de API, unidades,
atributos/cardinalidad y reader/exporter. No se añade un shim ni se declara verde.

Observabilidad integrada:94casos pasan en ambos runtimes1.18/28 y1.20/29,
incluidos los nuevos controles de mantenimiento y presupuesto. Los recibos cloud,
SQL, paid y FULL anteriores mantienen sus identidades y perfiles.

## Avisos estrictos de dependencias: compatibles, pendientes upstream

La consulta oficial confirma las mismas versiones disponibles. Los34 archivos
de fuentes TOML/WebSockex/gproc coinciden con los compilados en el recibo de
consumidores anterior, por lo que se reutiliza ese diagnóstico identificado.

| Dependencia / ruta | Aviso observado | Corrección y límite actual |
|---|---|---|
| ReqLLM → llm_db → TOML0.7 |15 deprecaciones de charlists y4 ramas inalcanzables del decoder datetime | La [corrección de charlists](https://github.com/bitwalker/toml-elixir/pull/43) está mergeada; [Hex sigue en0.7.0](https://hex.pm/packages/toml). No equivale a corregir los cuatro avisos de tipos. |
| ReqLLM → WebSockex0.5.1 |19 avisos de variables de tamaño de bitstring que necesitan pin explícito | [0.5.1 sigue siendo la release estable](https://hex.pm/packages/websockex). Las sesiones WebSocket upstream no son el transporte HTTP/SSE cualificado de ExAgent. |
| Exporter opt-in → grpcbox0.18 → gproc1.2 |8 avisos de bindings exportados desde subexpresiones y1 de lists:zf | La [corrección OTP29](https://github.com/uwiger/gproc/pull/206) está en [gproc1.3](https://hex.pm/packages/gproc/1.3.0), pero [grpcbox0.18](https://hex.pm/packages/grpcbox/0.18.0) requiere `~>1.2.0`. |

Los contadores son líneas de diagnóstico, no defectos funcionales ni fallos de
tests. Algunos avisos WebSockex se repiten en la misma ubicación. Los de gproc
son también deuda para versiones futuras de OTP; no se promete compatibilidad
con un runtime futuro que retire esos comportamientos.

No hay una actualización oficial compatible que deje limpio este grafo hoy.
Se mantiene el lock y no se introduce fork, parche, override ni supresión.
Los contratos funcionales de consumidores pasan; el diagnóstico estricto sigue
rojo. Esta investigación no cambia su criterio ni concede una excepción de
publicación. No hay warning de compilación ExAgent en esos recibos.

### Siguiente acción verificable

- TOML: adoptar una release publicada que incluya los arreglos pertinentes;
  comprobar catálogo/model resolution y consumidores afectados.
- WebSockex: adoptar una release compatible con el pin explícito corregido;
  comprobar los grafos ReqLLM y nuestras fronteras HTTP/SSE. No anunciar realtime
  como aceptado por instalar ese arreglo.
- grpcbox/gproc: esperar un rango publicado que permita gproc1.3 sin override;
  comprobar el grafo exporter, transporte OTLP local y contratos OTel afectados.

Volver a consultar sólo esos paquetes antes de adoptar un cambio. Conservar los
diagnósticos originales y los SHA de cada artefacto; no repetir suites de terceros
ni toda la matriz por una nota documental. [Dependencias](dependencies.md) y
[verificación](verification.md) describen la política y los comandos existentes.

El [recibo de investigación](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/KNOWN-LIMITS.md)
conserva controles, fuentes, presupuestos y resultados. Observabilidad cloud,
métricas exportadas, SQL y carga no reciben una nueva aceptación en este objetivo.
