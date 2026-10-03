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
a ExDoc. El cambio de ExAgent es documental.

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
