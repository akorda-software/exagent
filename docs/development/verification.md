# Verificación y aceptación local

Usar un entorno compatible y aislado; en el workspace actual consultar primero
[entorno y tooling](environment.md). Todos los comandos runtime de esta página
son offline. No activar proveedores pagados o Postgres para conseguir un verde.

Para v2.0.0, [producción y aceptación](production-acceptance.md) define los escenarios
A1–A10 y gates G1–G6. El [roadmap](roadmap.md) decide cuándo ejecutarlos. Esta guía
conserva los comandos del checkout; preparar el plan no añade todavía los runners
de capacidades nuevas ni convierte los gates externos en pruebas offline.

**Cadencia vigente:** [flujo simplificado](execution-flow.md). Ejecutar focales por
delta durante desarrollo y una suite integrada al estabilizar la vertical; no
todos los comandos de esta guía por cada microhito o cambio documental. Como
máximo una revisión independiente por objetivo y sin repetir sus probes en el padre.

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
  permanente. La única revisión de integración evalúa su valor y frecuencia con el
  paquete final, siguiendo execution-flow; no iniciar una cadena de re-review.

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

### Regresión habitual OpenRouter, opt-in por cambio relevante

Ejecutar una ola live acotada cuando cambien admisión, opciones, schema/output,
historia/codec o transporte del perfil anunciado, y al cualificar candidata. Un
cambio de prosa o un test offline no activa llamadas pagadas. No es un bucle
continuo, cron, fallback para obtener verde ni parte implícita de `mix test`.

1. Identificar fuente/manifest/lock y copiar físicamente ese freeze a un área de
   cualificación con builds privados. Ejecutar primero compile/focales stock TCP y
   negativos sin credenciales. Nunca probar una copia de ROOT que sigue editándose.
2. Fijar endpoint, ID exacto, API/perfiles y opciones; consultar evidencia actual de
   capacidades y precio. El mínimo aceptado de2026-09-27 es OpenRouter
   `openai/gpt-4o-mini`, stock1.24/OpenAIChat, chat_tools_v1 y controles native
   separados. Luna none tiene13/14 (length_stream no cualificado); GLM5.3Flash y
   DeepSeek4.1Flash sólo un control de texto buffered cada uno. Reasoning opcional
   no demuestra none y obligatorio no permite falsear capabilities.
3. Activar explícitamente una **nueva ola** y selección de casos antes del primer
   request. El usuario mantiene autorización live permanente para trabajo relevante;
   el grant interno identifica fuente/cap/política y no exige pedir aprobación humana
   rutinaria de nuevo. Registrar máximo de admisiones y reserva USD, concurrencia1 y retries0.
   La ola histórica gpt-4o-mini usó17 admisiones/3 efectos/0 retries bajo USD2/30;
   sus resultados/ledger no se reutilizan como una ola nueva. Reservar antes de cada
   admisión, detenerse al límite y mantener errores/intentos en el ledger.
4. Inyectar únicamente OPENROUTER_API_KEY no vacía en el entorno privado del hijo,
   desde el archivo local de la aplicación protegido0600 o un lanzador confiable.
   No copiar `.env` al artefacto, volcar entorno/headers, poner la clave en argv ni
   activar proveedores/DB ajenos. Los workers offline no leen esa credencial.
5. Reusar los selectores del harness G2: texto sync/stream_text/run_stream, tool y
   Ecto en esas superficies, native separado, vacío legítimo y length real. Exigir
   argumentos/recibo/IDs/historia exactos, Ecto real, un efecto por tool válida,
   terminal único, y0 efectos en length. No aceptar HTTP400 como prueba de length.
6. Guardar comandos/exits/fuente, admissions/effects, uso normalizado y coste
   estimado por separado de factura observada. Distinguir aceptada/limitada/no
   soportada/no verificada por combinación. Un rojo no autoriza cambiar oráculos,
   reparar JSON, borrar flags o subir presupuesto en silencio.

El harness portable mantenido vive en `test/support/openrouter_qualification/`,
fuera de la suite pagada por defecto y sin depender del ledger agotado de una Task.
Desde un checkout estable, con el prefijo de [entorno](environment.md), elegir un
directorio **nuevo** por invocación y un presupuesto dentro de la ola asignada:

```bash
python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model openai/gpt-4o-mini \
  --artifacts /tmp/opencode/exagent-online-gpt4-new \
  --max-admissions 20 --budget-usd 1.0

python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model openai/gpt-6-luna \
  --artifacts /tmp/opencode/exagent-online-luna-new \
  --max-admissions 20 --budget-usd 1.0

python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model z-ai/glm-5.3-flash \
  --artifacts /tmp/opencode/exagent-online-glm-text-new \
  --max-admissions 1 --budget-usd 0.6

python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model deepseek/deepseek-v4.1-flash \
  --artifacts /tmp/opencode/exagent-online-deepseek-text-new \
  --max-admissions 1 --budget-usd 0.6
```

Se puede omitir `--dotenv` si un lanzador privado ya inyectó sólo la clave requerida.
Sin `--live`/`--offline-check`, el wrapper sale64 antes de leerla, crear artefactos o
invocar Mix/red. GLM/DeepSeek sólo permiten text_sync; no se les fuerzan capabilities
para tools. `--cases tools_stream,native_sync` selecciona explícitamente un subset,
sin llamar a ese subset una matriz completa. La selección completa de Luna conserva
el oráculo length real y **puede salir1**; nunca ocultar su rojo o repetir hasta verde.

Cada ola registra fingerprint real de fuentes/lock, catálogo público seleccionado,
settings/casos, ledger, resultados, logs redactados y resumen. Límites CLI máximos:
80admisiones/USD5; reserva mínima por admisión0.025GPT4/0.05Luna/0.60texto razonador,
con input sintético≤16KiB/10mensajes y output256/length16. Son reservas operativas,
no factura ni cota matemática de tokenizer. Revalidar precios al cambiar catálogo;
los directorios nuevos no amplían un presupuesto global compartido. Reuso de
directorio rechaza y conserva sus bytes: **no** borrar/editar ledger para repetir.

La comprobación de portabilidad no llama a OpenRouter ni carga claves:

```bash
python3 test/support/openrouter_qualification/run.py
# exit64 esperado
python3 test/support/openrouter_qualification/run.py \
  --offline-check --model openai/gpt-6-luna \
  --catalog /ruta/al/catalogo-publico.json \
  --artifacts /tmp/opencode/exagent-online-offline-new \
  --cases tools_stream,native_sync --max-admissions 10 --budget-usd 1.0
```

El snapshot de catálogo debe tener array `models` y conservar fecha/procedencia;
`--catalog` también permite una ola live deliberadamente fijada a ese snapshot.
El README junto al runner detalla los supuestos. Es tooling del checkout, no del
TAR de biblioteca. `real_providers_test.exs` conserva nueve slugs históricos con
otro perfil: `--include integration` genérico no reproduce esta cualificación ni
impone el presupuesto monetario anterior.

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

El directorio debe ser nuevo y sus padres deben ser directorios reales, sin
symlinks; puede estar bajo el temporal del host o del runner CI. `--checksum` permite
fijar el SHA256 del TAR; `--lock` usa un snapshot de lock. El runner materializa
bytes del paquete, no symlinks al checkout; valida los cuatro modos `none/api/sdk/exporter`,
orden SDK, grafo, provenance y siete contratos runtime por modo, incluido C7 con
Model/Tool/Store/PubSub de la aplicación. El manifiesto exige nombre, módulo y
resultado de cada caso, además de totales y cero skips/exclusiones.
El grafo exporter nuevo resuelve la release1.11 usada por la receta Collector;
su smoke HTTP finito no acepta por sí mismo el lifecycle stock ni el backend.

`summary.term` separa runtime de diagnóstico estricto. `graph.term` contiene el
grafo; `phase-graph.term`, su diagnóstico. Los warnings gproc/OTP29 conocidos deben
seguir produciendo exit1 estricto aunque sus contratos runtime pasen. No se
suprimen ni se cuentan como defectos de ejecución de ExAgent.

El control de aislamiento no instala herramientas:

```bash
elixir test/support/package_acceptance_isolation.exs /tmp/opencode/exagent-docs-preview.tar
```

### Perfil SQL explícito y portable

`test/support/postgres_acceptance/` crea un cluster PostgreSQL nativo propio,
con TCP desactivado y socket privado. Sólo `--execute` lo activa; `--list` no
arranca procesos ni conecta a una base. Requiere un checkout/consumidor físico
aislado y dependencias presentes, además de `MIX_ARCHIVES`/`MIX_REBAR3` aislados
existentes. El runner fija sus propios homes/cachés/build y limpia selectores
heredados; no toca ROOT/_build ni configura servicios/globales del host.

```bash
python3 test/support/postgres_acceptance/run.py --execute \
  --project /absolute/path/to/isolated-project \
  --pg-bin /absolute/path/to/postgresql/bin
```

Prueba CAS real, receipts, rechazo de DELETE con trigger, pausa/resume entre VMs
tras reinicio de DB, crash tras un efecto, incertidumbre sin replay y backup/restore
de bytes. El README de checkout `test/support/postgres_acceptance/README.md` declara
los límites y escenarios pendientes. El perfil17.4/READ COMMITTED se ejecutó sobre
un freeze privado el2026-10-01; no acepta la candidata final, composición A8, RLS,
ni todos los despliegues G3. Objective013 añade un proxy propio loopback→socket
privado que pierde realmente la respuesta tras COMMIT; bootstrap+delta pasan con
replay del recibo/revisión intacta, sin repetir las siete fases anteriores.
Otro delta ejecuta dos `ExAgent.resume` públicos en VMs simultáneas: SQL externo
confirma1winner,2requests totales/1effect y completed válido, con cleanup propio.
Esos recibos tampoco aceptan Flow11 ni candidata. Un ACK descartado por la fixture
original se etiqueta sintético. Las advertencias upstream se conservan en los logs.

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

La aceptación TAR exige resultado ExUnit estructurado con los **siete nombres
esperados**, cero fallos, cero skips/exclusiones y las observaciones de sus escenarios.
Los archivos `runtime-results.etf` y `runtime-stats.etf` se conservan con el resumen.
Un exit0 que omite C7 o cualquiera de los casos no certifica los siete contratos. CI prepara un
único TAR y publica su SHA256 como artefacto; los consumidores Elixir1.18/OTP28 y
Elixir1.20/OTP29 verifican esos mismos bytes en los cuatro grafos, con tooling,
deps y builds aislados. La ejecución remota sobre una revisión exacta sigue
pendiente: configurar el job no constituye aceptación G5. El gate manual de bytes
continúa siendo obligatorio para esa frontera. Las probes de fixtures sobre BEAM
existentes se etiquetan como investigación, no aceptación nueva de paquete/orden SDK.

## Cómo registrar un resultado

Guardar fecha, revisión/estado WIP, runtime efectivo, comandos/exit codes, semillas,
pass/fail/excluded, límites y artefactos. Actualizar [estado](../status.md) sólo con
la última aceptación significativa; el detalle de una sesión cerrada va al archivo.
Los números históricos nocturnos no se atribuyen automáticamente a una nueva
reorganización ni a una versión futura de dependencias.
