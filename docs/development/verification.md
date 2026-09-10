# Verificación y aceptación local

Usar un entorno compatible y aislado; en el workspace actual consultar primero
[entorno y tooling](environment.md). Todos los comandos runtime de esta página
son offline. No activar proveedores pagados o Postgres para conseguir un verde.

## Qué nos corresponde verificar

**Criterio acordado al cerrar la auditoría del 2026-09-10:** concentrar el testing
en ExAgent y en las garantías que ofrece a sus consumidores.

| Responsabilidad | Qué hacemos en ExAgent |
|---|---|
| Comportamiento interno de Req, gproc u otra dependencia | Corresponde a sus mantenedores; no duplicar sus suites ni asumir su mantenimiento por encontrar un warning. |
| Integración de ExAgent con sus dependencias | Probar nuestras fronteras: payloads y respuestas de adapters, schemas, uso/coste, efectos, ownership y dependencias opcionales. Los mantenedores externos no prueban nuestro código. |
| Paquete instalado por una aplicación | Comprobar bytes TAR, dependencias declaradas, compilación limpia y grafos opt-in. El entorno completo del repositorio puede ocultar una dependencia accidental. |

Si un defecto externo rompe una garantía concreta de ExAgent, conservar una
regresión pequeña en esa frontera y valorar solución upstream, versión compatible
o limitación documentada. La prioridad la determina su efecto real sobre ExAgent,
no la mera existencia de un diagnóstico de otra biblioteca. Los límites funcionales
del transporte OTel documentados no se equiparan a simples warnings del compilador.

### Frecuencia y lectura de los resultados

- **Desarrollo habitual:** focales del cambio, compilación del proyecto con warnings
  como errores, formato y suite offline. Añadir regresiones útiles junto a cada
  cambio de ExAgent; no mantener una auditoría transversal permanentemente abierta.
- **Integración/paquete:** ejecutar los grafos afectados al cambiar manifiesto,
  dependencias, SDK opcional, empaquetado o toolchain, y revisar el paquete candidato
  antes de publicar. No repetir toda la matriz por cada cambio documental o pequeño.
- **Probes y mediciones:** usar las focales pertinentes. Los experimentos temporales
  de mutación y los benchmarks completos no se convierten automáticamente en CI
  permanente. La segunda revisión evaluará su valor y frecuencia con el paquete final.

Los resultados funcionales y los diagnósticos de dependencias se registran por
separado. En la auditoría, los24contratos TAR pasaron mientras el comprobador
estricto devolvía exit1 por Req/gproc. Ese resultado se conserva: no demuestra un
fallo funcional ni convierte resolver esos warnings en requisito para continuar
el desarrollo o cerrar la auditoría. Su seguimiento es de menor prioridad, al
actualizar dependencias o preparar la publicación, salvo impacto real demostrado.

Esta aclaración fija prioridades y criterios de mantenimiento. Los comandos y la
CI actualmente implementados se describen abajo; sus flags, resultados históricos
y detección de warnings no se han alterado para declarar un verde distinto.

## Gate habitual del checkout

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
mix format --check-formatted
git diff --check
```

Aplicar el prefijo de tooling de este host cuando corresponda. Ejecutar primero
focales relevantes y después la suite integrada al cerrar una unidad de runtime.
Los cambios exclusivamente documentales deben comprobar enlaces, snippets,
ExDoc y membresía del paquete; no necesitan repetir benchmarks de rendimiento.

## Probes y ejemplos

| Qué prueba | Comando después de compilar |
|---|---|
| Invariantes de consolidación | `EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs` |
| Snippets de README y guías | `EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs` |
| OTLP nativo, errores y lifecycle | `EXAGENT_OFFLINE=1 MIX_ENV=test mix test test/exagent/observability --warnings-as-errors` |
| Evals deterministas | `EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/framework_evals.exs --json /tmp/opencode/framework-evals.json` |
| Fixture de carga pequeña | `EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/framework_load_probe.exs --smoke --json /tmp/opencode/framework-load-smoke.json` |

El probe R3 de flush requiere **Elixir directo**, sin cargar previamente ExAgent:

```bash
EXAGENT_OFFLINE=1 elixir \
  -pa _build/test/lib/opentelemetry/ebin \
  -pa _build/test/lib/opentelemetry_api/ebin \
  -pa _build/test/lib/telemetry/ebin \
  test/support/observability_processor_probe.exs
```

R3 instrumenta una copia en memoria para forzar scheduling; no es una corrida sin
instrumentación. En builds alternativos, apuntar `-pa` a **su propio** directorio.
El load completo se ejecuta sin `--smoke` sólo cuando una medida nueva esté
justificada, con workload fijado antes y sin seleccionar el mejor intento.

## Documentación

```bash
EXAGENT_OFFLINE=1 MIX_ENV=dev mix docs --warnings-as-errors --output /tmp/opencode/exagent-docs
```

El probe documental selecciona codeblocks reales y falla si faltan/son ambiguos.
Sustituye sólo modelos/callbacks de fixtures declaradas. Las recetas Mix.install,
Config, Repo y MCP externo se distinguen de bloques realmente ejecutados.

Al reorganizar páginas comprobar también:

1. Links locales Markdown y rutas de los lectores de snippets.
2. `docs/README.md` y README como entradas coherentes.
3. Extras/grupos ExDoc y nombres HTML sin colisiones de basename.
4. Archivos documentales incluidos en `mix.exs` y en el TAR real.
5. Ausencia de registros de ejecución archivados en el paquete de uso habitual.

## Consumidores de bytes del paquete

Construir sólo un preview local, sin publicación ni cambio de versión:

```bash
EXAGENT_OFFLINE=1 mix hex.build --output /tmp/opencode/exagent-docs-preview.tar
elixir test/support/package_acceptance.exs \
  --tar /tmp/opencode/exagent-docs-preview.tar \
  --work-dir /tmp/opencode/exagent-night-package-docs-check \
  --mode all --seed 771506
```

El directorio debe ser nuevo y directo bajo `/tmp/opencode`. `--checksum` permite
fijar el SHA256 del TAR; `--lock` usa un snapshot de lock. El runner materializa
bytes del paquete, no symlinks al checkout; valida los cuatro modos `none/api/sdk/exporter`,
orden SDK, grafo, provenance y seis contratos runtime por modo.

`summary.term` separa runtime de diagnóstico estricto. `graph.term` contiene el
grafo; `phase-graph.term`, su diagnóstico. Los warnings gproc/OTP29 conocidos deben
seguir produciendo exit1 estricto aunque sus contratos runtime pasen. No se
suprimen ni se cuentan como defectos de ejecución de ExAgent.

El control de aislamiento no instala herramientas:

```bash
elixir test/support/package_acceptance_isolation.exs /tmp/opencode/exagent-docs-preview.tar
```

## Gates de harness y CI tras la auditoría

`.github/workflows/ci.yml` conserva la matriz existente y fija explícitamente
`EXAGENT_OFFLINE=1 MIX_ENV=test`. Un job adicional Elixir1.20/OTP29 ejecuta el
harness finito. Su runner guarda comandos, exit codes, warnings y logs con los
totales/exclusiones, además de hashes de fuentes y BEAM, incluso si falla una fase.
El comando local equivalente, con el prefijo de [entorno](environment.md), es:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test elixir test/support/testing_audit_harness_ci.exs suite /tmp/opencode/exagent-suite-check
EXAGENT_OFFLINE=1 MIX_ENV=test elixir test/support/testing_audit_harness_ci.exs harness /tmp/opencode/exagent-harness-check
```

`suite` ejecuta compile forzado, formato sin escritura y tests con warnings-as-errors;
`harness` ejecuta compile, C0, snippets, R3 aislado, evals y load smoke. El driver
usa GNU `timeout`, disponible en los runners Ubuntu. `mix check` conserva su alias
histórico y no equivale a este gate. La ejecución local del driver no prueba que
la matriz remota de GitHub haya pasado.

C0 ofrece `--json <path>` y devuelve exit1 si falta una invariante requerida o
hay un error del probe. Evals exige los casos/criterios requeridos; carga exige
filas/muestras/percentiles coherentes y cero pérdidas normales. La saturación se
evalúa aparte. Para volver a comprobar un JSON guardado sin ejecutar escenarios:

```bash
elixir -pa '_build/test/lib/jason/ebin' test/support/testing_audit_harness_validate.exs c0 /tmp/opencode/exagent-harness-check/c0.json
elixir -pa '_build/test/lib/jason/ebin' test/support/testing_audit_harness_validate.exs evals /tmp/opencode/exagent-harness-check/evals.json
elixir -pa '_build/test/lib/jason/ebin' test/support/testing_audit_harness_validate.exs load /tmp/opencode/exagent-harness-check/load.json
```

Estos validadores detectan vacíos, campos ausentes y resultados incompatibles con
el manifest; no convierten datos fabricados en evidencia de una ejecución. Los
controles negativos de datos se distinguen de mutaciones del comportamiento.

La aceptación TAR exige resultado ExUnit estructurado con los **seis nombres
esperados**, cero fallos, cero skips/exclusiones y las observaciones de sus escenarios.
Los archivos `runtime-results.etf` y `runtime-stats.etf` se conservan con el resumen.
Un exit0 que ejecutó cinco casos ya no certifica los seis contratos. El job TAR de
CI sigue pendiente de adaptar el bootstrap host-specific; el gate manual de bytes
continúa siendo obligatorio para esa frontera. Las probes de fixtures sobre BEAM
existentes se etiquetan como investigación, no aceptación nueva de paquete/orden SDK.

## Cómo registrar un resultado

Guardar fecha, revisión/estado WIP, runtime efectivo, comandos/exit codes, semillas,
pass/fail/excluded, límites y artefactos. Actualizar [estado](../status.md) sólo con
la última aceptación significativa; el detalle de una sesión cerrada va al archivo.
Los números históricos nocturnos no se atribuyen automáticamente a una nueva
reorganización ni a una versión futura de dependencias.
