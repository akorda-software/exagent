# Dependencias de la candidata v2

Revisión del **2026-10-03**, solicitada antes de publicar. Se contrastan los
**43 paquetes Hex** del lock raíz con la API pública de Hex y `mix hex.outdated
--all`: producción, dependencias opcionales, tests, documentación y transitivas.
La fecha importa: «última estable» describe esa consulta, no una promesa futura.

El cierre operativo posterior añade dos paquetes oficiales0.6, sin cambiar los
43anteriores: API experimental OTel opcional/runtime false y SDK experimental sólo
test para verificar métricas. El lock tiene ahora45entradas. Sus requisitos públicos
son compatibles con API1.5/SDK1.7; la aplicación consumidora decide instalar/arrancar
su SDK de métricas. No equivale a iniciar dos exporters de tracing. Fuentes:
[API0.6](https://hex.pm/packages/opentelemetry_api_experimental/0.6.0) y
[SDK0.6](https://hex.pm/packages/opentelemetry_experimental/0.6.0).

## Resultado del resolver

Había doce paquetes con una release estable posterior. Se actualizan once y se
mantiene una incompatibilidad explícita: **gproc 1.2.0**, porque grpcbox 0.18.0
requiere `~> 1.2.0`, excluyendo la release 1.3.0. No se fuerza con un override.
Los otros **42 paquetes** quedan en la última estable consultada.

| Paquete | Antes | Ahora | Fuente oficial |
|---|---|---|---|
| earmark_parser | 1.4.45 | 1.4.46 | [Hex](https://hex.pm/packages/earmark_parser/1.4.46) |
| ecto | 3.14.0 | 3.14.2 | [Changelog](https://hexdocs.pm/ecto/changelog.html) |
| ex_doc | 0.40.3 | 0.40.4 | [Changelog](https://hexdocs.pm/ex_doc/changelog.html) |
| finch | 0.22.0 | 0.24.0 | [Changelog](https://hexdocs.pm/finch/changelog.html) |
| hpax | 1.0.4 | 1.1.0 | [Changelog](https://github.com/elixir-mint/hpax/blob/v1.1.0/CHANGELOG.md) |
| jsv | 0.22.0 | 0.25.0 | [Changelog](https://github.com/lud/jsv/blob/main/CHANGELOG.md) |
| makeup | 1.2.1 | 1.2.2 | [Hex](https://hex.pm/packages/makeup/1.2.2) |
| mint | 1.10.2 | 1.11.0 | [Changelog](https://github.com/elixir-mint/mint/blob/v1.11.0/CHANGELOG.md) |
| opentelemetry_exporter | 1.10.0 | 1.11.0 | [Changelog](https://github.com/open-telemetry/opentelemetry-erlang/blob/main/apps/opentelemetry_exporter/CHANGELOG.md) |
| texture | 1.2.1 | 2.0.0 | [Changelog](https://github.com/lud/texture/blob/main/CHANGELOG.md) |
| zoi | 0.18.7 | 0.18.11 | [Changelog](https://github.com/phcurado/zoi/blob/v0.18.11/CHANGELOG.md) |

### Paquetes que ya estaban al día

| Paquete | Última estable consultada |
|---|---|
| abnf_parsec | 2.1.0 |
| acceptor_pool | 1.0.1 |
| ts_chatterbox (app chatterbox) | 0.16.0 |
| ctx | 0.6.0 |
| db_connection | 2.10.2 |
| decimal | 3.1.1 |
| dotenvy | 1.2.1 |
| ecto_sql | 3.14.0 |
| grpcbox | 0.18.0 |
| hpack_erl (app hpack) | 0.3.0 |
| idna | 7.1.0 |
| jason | 1.4.5 |
| llm_db | 2026.9.8 |
| makeup_elixir | 1.0.1 |
| makeup_erlang | 1.1.0 |
| mime | 2.0.7 |
| nimble_options | 1.1.1 |
| nimble_parsec | 1.4.2 |
| nimble_pool | 1.1.0 |
| opentelemetry | 1.7.0 |
| opentelemetry_api | 1.5.0 |
| postgrex | 0.22.4 |
| req | 0.7.4 |
| req_llm | 1.26.0 |
| server_sent_events | 1.1.0 |
| splode | 0.3.2 |
| ssl_verify_fun | 1.1.7 |
| telemetry | 1.4.2 |
| tls_certificate_check | 1.35.0 |
| toml | 0.7.0 |
| websockex | 0.5.1 |

Las versiones y fechas se obtienen de `https://hex.pm/api/packages/<paquete>` y
su endpoint público `releases/<versión>`. No se seleccionan prereleases ni releases
retiradas. El lock no contiene dependencias Git o de path que queden fuera de esa
consulta. Los pins históricos de recetas/fixtures conservan su propia identidad;
esta tabla describe el paquete ExAgent y su lock, no actualiza apps consumidoras.

También se consultan las nueve dependencias declaradas en la fixture de frameworks:
Phoenix1.8.15, LiveView1.2.12, PubSub2.3.0, Oban2.24.1, Ecto SQL3.14.0,
Postgrex0.22.4 y lazy_html0.1.13 ya fijan la última estable. Los rangos declarados
permiten Phoenix HTML4.3.0 y Floki0.38.4. Esta consulta no renombra sus ejecuciones
históricas como una nueva aceptación ni modifica la aplicación hermana.

## Compatibilidad y mínimos publicados

- Finch 0.24, Mint 1.11 y HPAX 1.1 se adoptan juntos. Mint cambia el tratamiento
  del receive timeout; Finch cierra la conexión HTTP/1 tras errores antes de
  devolverla al pool. Sus mínimos en `mix.exs` protegen resoluciones de consumidores;
  cambiar sólo el lock de la biblioteca no lo haría.
- JSV se restringe a `~> 0.25.0`. Su normalización de errores incorpora niveles
  internos y conserva todos por defecto. ExAgent sigue exponiendo path/keyword/
  message y usa los mismos guards de referencias, callbacks, dialectos y datos.
  La redacción de mensajes generados por JSV puede variar; no basar decisiones
  de aplicación en coincidencias literales con su prosa de diagnóstico.
  Se conserva la extensión pública de codepoints/igualdad numérica: upstream
  todavía no satisface esas regresiones. Texture 2 cambia el matching de segmentos
  URI prefijados; no añade resolución de red/file ni habilita formatos en ExAgent.
- Ecto 3.14.2 permanece dentro del rango declarado. Ecto SQL/Postgrex y API/SDK
  OTel ya estaban en la última estable. SDK y exporter siguen siendo opt-in/test;
  una aplicación sin OTel no los instala por actualizar ExAgent.
- Exporter 1.11 corrige los booleanos de spans/resources. Los probes exigen ahora
  protobuf `bool_value`, incluido checkpoint retry y compaction changed. La nueva
  release no certifica recepción durable ni elimina por sí sola los límites de
  HTTP partial_success/ownership.
- ExDoc 0.40.4 y sus parsers/lexers son sólo tooling dev. Mantener verificación
  estricta de HTML, Markdown/llms y EPUB tras actualizar el generador.

Ninguna actualización sube el mínimo Elixir 1.18 declarado. No cambian firmas,
schemas/eventos/snapshots, guards de proveedores o política de reintentos de ExAgent.
Las apps con pins inferiores a los nuevos mínimos deben revisar su lock/constraints;
no se modifica una aplicación original desde esta revisión.

## Verificación de esta revisión

El resolver oficial y `hex.outdated --all` confirman 42 paquetes actuales y gproc
bloqueado; el comando sale 1 por esa diferencia conocida. `mix hex.audit` sale 0:
no encuentra paquetes retirados ni advisories para este lock en esa consulta.
Eso no sustituye pruebas de nuestras fronteras ni constituye una auditoría universal.

Primeras pruebas: 76 casos de schemas/output/MCP HTTP y siete probes nativos OTLP
pasan. El fallo inicial de cuatro probes conserva el pin obsoleto a exporter 1.10;
se mantiene su log y se actualiza la caracterización al comportamiento 1.11.

| Comprobación nueva | Resultado |
|---|---|
| Suite Elixir1.20/OTP29 |2.177 pases /0 fallos /28 exclusiones;2.007,4s |
| Suite Elixir1.18/OTP28 |2.177 pases /0 fallos /28 exclusiones;2.024,7s |
| Rutina local bin/check |Nueve fases exit0;2.073,45s, incluye compile estricto, probes, docs/enlaces y TAR/aislamiento |
| PostgreSQL17.4 |14 fases y cleanup pasan; incluye ACK perdido, dos resumers, fresh VM, recovery y backup |
| TAR en consumidores |Ocho grafos sin lock de entrada,56 contratos pasan y46 comandos exit0 |
| Diagnóstico stock |Los runners de consumidores siguen exit1 por TOML/WebSockex/gproc; sin warnings de compilación ExAgent |

Las28 exclusiones offline son22 tests de proveedores reales y seis de PostgreSQL;
no son pases. La suite1.18 anterior de la revisión ReqLLM conserva su fallo de
readiness y su corrección focal; estas ejecuciones nuevas tienen el lock actualizado
y su propio recibo. No se sustituye aquel resultado por el actual.

G2 real conserva doce escenarios aceptados de la primera ola; el caso de corte
recibe una negativa breve del modelo con terminal `stop`, dejando sin conseguir
el estímulo `length`. Un control causal sustituye sólo el prompt por un párrafo
inofensivo largo, con el mismo límite16/oráculo/guards. Los dos casos sync/stream
pasan con `length` real y cero efectos. Los catorce escenarios quedan cubiertos
con16+2admisiones,3efectos y USD0.45 reservado, sin factura observada. Se conservan
la ola inicial12pases/1fallo/1sin ejecutar y los dos controles posteriores; no se
presenta como una nueva ola completa14/14 ni se vuelve a ejecutar lo ya aceptado.

Durante esta revisión de dependencias, el E2E de la aplicación hermana y la
aceptación API/UI Langfuse/Opik conservaron su evidencia anterior; no hubo una
nueva ola app/cloud en ese objetivo. La [comparación posterior de modelos](real-consumer-e2e.md)
tiene su propio recibo: 23 escenarios Luna y 22 aceptados de 23 DeepSeek,
sin convertirlo en otra ejecución G2 ni cloud. El cambio del exporter
tiene la nueva aceptación nativa local descrita arriba. Recibos y límites en el
[registro de esta revisión](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/DEPENDENCIES.md).

Para revisar versiones antes de otra release, ejecutar `mix hex.outdated --all`
y `mix hex.audit` con el tooling aislado del proyecto. Examinar changelogs y
constraints antes de `mix deps.update`; probar nuestras fronteras y los consumidores
afectados. Una biblioteca publicada no distribuye su lock: los mínimos necesarios
deben estar en el manifiesto. No mezclar una actualización con bump/tag/Hex.

Los avisos stock TOML/WebSockex/gproc siguen siendo un seguimiento separado.
La [investigación posterior](known-limits.md) identifica cada categoría y su
ruta, la corrección OTP29 publicada en gproc1.3 bloqueada por grpcbox, y el arreglo
de charlists TOML aún sin release compatible. Versiones/lock y diagnóstico intactos.
«Versión actual» no significa «sin avisos». No se suprimen avisos, se parchean
dependencias ni se declara verde el diagnóstico estricto desde pases funcionales.
Consultar [verificación](verification.md), [estado](../status.md) y
[roadmap](roadmap.md) para la aceptación vigente y los siguientes pasos de release.
