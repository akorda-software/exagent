# Verificación y aceptación local

Usar un entorno compatible y aislado; en el workspace actual consultar primero
[entorno y tooling](environment.md). Todos los comandos runtime de esta página
son offline. No activar proveedores pagados o Postgres para conseguir un verde.

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

## Cómo registrar un resultado

Guardar fecha, revisión/estado WIP, runtime efectivo, comandos/exit codes, semillas,
pass/fail/excluded, límites y artefactos. Actualizar [estado](../status.md) sólo con
la última aceptación significativa; el detalle de una sesión cerrada va al archivo.
Los números históricos nocturnos no se atribuyen automáticamente a una nueva
reorganización ni a una versión futura de dependencias.
