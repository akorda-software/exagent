# Prompt de relevo nocturno: ExAgent, consolidacion autonoma tras C6 neutral

> **Relevo histórico de una sesión terminada.** Las órdenes de ejecución y el
> backlog nocturno de este documento no se reactivan al leerlo. El
> [relevo vigente](../../development/handoff.md) resume el estado y las restricciones
> actuales. Los nombres de archivos antiguos se conservan como parte del registro.

## Cierre del alcance nocturno local — 2026-09-10

**La ejecución nocturna terminó su alcance local viable.** Este bloque y el estado
final de ORCHESTRATION.md prevalecen sobre la pausa/backlog históricos de abajo.
No volver a abrir las unidades completadas para llenar tiempo. Recuperar autoridad
y el nuevo mandato antes de asignar más trabajo; los gates externos siguen separados.

- Run `run_4315531152c9`, generation1, runtime/host/workspace originales; caller
  resuelto por Orca sin --from histórico. Baseline579/28 seed280440; cierre fresco:
  **619 correctos,0 fallos,28 excluidos**, seed37556, en1.20.0/OTP29.0.5,
  1.18.4/OTP28.0 y1.17.3/OTP27.3.4.17; compile forzado73 en cada uno.
- N01–N03 implementados y revisión fresca aceptada como caracterización local:
  exporter1.10 test-only, receptor loopback y decoder oficial. Booleanos→strings,
  partial_success ignorado y retención HTTP/átomos confirmados; cleanup propio
  ExAgent comprobado, cleanup nativo general NO. DESIGN8.8/OBSERVABILITY7.
- N05/N06 implementados: runner de consumidores TAR y mínimo1.17.3/OTP27.3.4.17
  oficial aislado; fix interno de warning SDK ausente,36 contratos focales verdes
  sobre el TAR intermedio. El TAR final pasa72 contratos runtime en12 consumidores
  y11/12 strict; sólo exporter/OTP29 conserva9 warnings gproc/exit1 estricto.
  N04/N12:68 spans/11POST; N07/N08: nueve tests con seis seeds independientes. Reviews
  posteriores cerraron P1/P2 del runner y reforzaron uso/snapshots con controles.
- N09/N10/N11 añaden20 tests: focal Mix del coordinador20/20, seed897031, revisión
  fresca sin bloqueantes. N13/N15:4000 runs medidos correctos,12200 spans locales,
  dos evals y4 focales; N14 no-change por falta de hotspot evitable demostrado.
  N16:16 bloques seleccionados,7 checks verdes y dos errores README corregidos.
- **Todos los workers están cerrados; no reutilizar sus handles.**16 Tasks/Dispatches
  completados y15 terminales distintas cerradas, con una reutilización útil. El
  retained histórico de ese primer intento no es un worker vivo: recurso final
  released y observación exited. N18 `task_7217175a868e` / `ctx_eb2d891ead54`
  terminó y fue liberado. Mailbox vacío; ningún trabajo continúa solo tras el turno.
- C0 14/14, snippets7/7 y R3 aislado1/1 en los tres runtimes. Siete ejemplos y smoke
  final pasan; framework_evals también funciona desde vendor del TAR sin OTel/SQL.
  La última revisión de carga/evals/snippets pasó sin hallazgos.
- TAR final revisado: `/tmp/opencode/exagent-night-final-reviewed-preview.tar`, SHA256
  `d656bd2a83608046028e031e3d6585c606d9a2fcb6f2774ba793da0fcc6c008a`, nominal1.2.0.
  Sus82 miembros coincidieron con los bytes finales del checkout. Formato, diff y
  docs con warnings-as-errors pasan. No es una release publicable1.x ni toda C8.
- **Incidente de tooling:** el bootstrap de paquete heredó MIX_ARCHIVES y sustituyó
  Hex2.5.1 del host mise1.20 por BEAM incompatible con OTP29. Fue una escritura
  accidental fuera del alcance. Se detuvieron las escrituras globales; reparación
  pendiente de autorización y sin backup previo exacto encontrado. El runner ahora
  verifica destinos efectivos antes de instalar y tiene control negativo sintético.
- Un shim `erl` también sobreescribía los prefixes del coordinador. Comando local
  comprobado en ACTION_PLAN10: PATH directo erlang29/bin:elixir1.20.0/bin:/usr/bin:/bin,
  MIX_HOME=/tmp/opencode/exagent-native-otlp-mix,
  MIX_ARCHIVES=/tmp/opencode/exagent-native-otlp-mix/archives. Verificar valores
  efectivos antes de bootstrap; no cambiar configuración global.
- WIP/untracked preservados, HEAD/version sin cambios. Ningún backend externo,
  consumidor, proveedor LLM pagado o DB real ejecutado. Recursos/ownership exactos
  y siguiente acción están en ORCHESTRATION.md; contrastar Run/mail/flota al retomar.

**Correcciones durante N18:** el primer full dio618/619 por una suposición de
batching del test de restart; barrera causal reprodujo y corrigió el test, con
16/16. El TAR anterior e665 reveló que1.20 infería el helper SDK false: startup y
sus helpers ahora se seleccionan realmente en compilación, cero diagnósticos1.17/
1.20 y SDK-presente16/16. También se separaron phase-*.term de graph.term para
evitar sobreescribir el grafo de consumidores; regresión roja→verde y aislamiento
  completo. N18 revisó y repitió las tres matrices con el TAR d656, ya verdes salvo
  strict gproc conocido. El benchmark previo es anterior al ajuste sólo de startup.

**Runner corregido y revisado:** MIX_EXS y selectores relacionados se verifican
dentro de cada hijo, work-dir es hijo directo nuevo real de/tmp/opencode, y warnings
se agregan por todas las fases. Los nuevos consumidores quedaron verificados. Los nueve
warnings gproc/OTP29 deben producir exit1 estricto aunque los contratos runtime
pasen; no suprimirlos ni llamar verde al gate estricto. La reparación del Hex host
sigue pendiente. Detalles y comandos exactos en ORCHESTRATION.md y ACTION_PLAN10.

**Siguiente trabajo con autorización propia:** reparar el Hex compartido; resolver
lifecycle/fidelidad del exporter nativo; comparar plataformas con acceso autorizado;
aceptar proveedores/DB/consumidores reales y decidir C7. No convertir esos gates en
permisos implícitos. Informes finales en `/tmp/opencode/exagent-night-final-verification.*`,
docs en `/tmp/opencode/exagent-night-final-docs/`; la evidencia durable vive en el repo.

El resto conserva el relevo inicial y sus limites; sus afirmaciones de "no se
ha empezado" describen el corte previo, no el estado actual.

Eres el nuevo coordinador de la evolucion de ExAgent. Este relevo sustituye una
conversacion larga; no necesitas recuperarla entera. Trabaja en
`/home/kukapu/dev/projects/exAgent`, habla con el usuario en espanol y continua la
implementacion desde el estado existente. **C1-C5 y C6 neutral ya estan
implementados y verificados offline.** El usuario se va a dormir y quiere dejar
este NUEVO coordinador avanzando durante la noche en varias unidades utiles,
sin necesitar su intervencion. La eleccion Langfuse/Opik puede esperar: no debe
bloquear OTLP local, hardening ni la aceptacion offline de C8.

Lee este archivo COMPLETO antes de asignar trabajo. Las secciones 1-7 conservan
mandato, limites, arquitectura y evidencia; 8-11 fijan la nueva ejecucion nocturna,
su backlog priorizado, criterios de cierre y continuidad. No necesitas cargar la
conversacion anterior de unas400k de contexto. Si eres un worker con Dispatch
inyectado, sigue SOLO tu Task; este mandato no te autoriza a abrir otro Run.

## 0. Punto exacto de pausa y ultima instruccion

El usuario pidio continuar mejorando ExAgent sin ayuda mientras duerme y despues
PAUSO al coordinador anterior para preparar este relevo, antes de gastar mas
contexto. **No se inicio implementacion nocturna, no se crearon Tasks/Dispatches
nuevos ni se lanzaron workers nuevos.** Esta preparacion solo modifica documentos.

Antes de esa pausa se redescubrieron Git/Orca y se repitio el baseline el
2026-09-09, aproximadamente21:52 UTC:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
```

Resultado: **579 correctos, 28 excluidos, seed806578**, 5.3s, Elixir1.20/OTP29.
HEAD y WIP siguen como en seccion2; buzon C6 vacio, sus nueve Dispatches terminados
y sus cinco workers cerrados. El Run sigue siendo `run_395ccad931e7` generation1;
no hay Run nocturno nuevo. Redescubre autoridad al arrancar, no la deduzcas de aqui.

**El usuario quiere ejecucion, no otro plan:** al recibir este relevo como nuevo
coordinador, organiza la primera oleada y empieza. Mantente supervisando y pasa a
las siguientes unidades viables tras cada verde. La pausa anterior fue para este
traspaso, no una revocacion del encargo nocturno del nuevo chat.

## 1. Mandato del usuario

El usuario quiere un framework de agentes excelente, mantenible y extensible
para Elixir/BEAM. Esta publicado en Hex y lo consumen Dragonex y WhoamAI. Acepta
breaking changes justificados para mejorar la base, con migracion y SemVer;
no quiere sacrificar el diseno por retrocompatibilidad ni hacer churn cosmetico.
No introduzcas comportamiento especifico de esos productos en la biblioteca.

Ha delegado las decisiones tecnicas ordinarias: investiga lo necesario, decide,
implementa, revisa y verifica. No le pidas elegir cada firma o mecanismo OTP.
Pregunta solo cuando falte una decision real de producto, acceso, coste o alcance.
Para este encargo nocturno, **no termines al cerrar la primera unidad ni el primer
verde**: continua por el backlog mientras haya trabajo autorizado y util. Si una
rama necesita al usuario, registra el gate y avanza otra. Solo cierra por pausa
expresa, limite real del entorno/tiempo, bloqueo de todas las ramas utiles o cierre
del alcance viable con evidencia. No inventes trabajo para gastar computo ni una
hora de despertar que el usuario no ha dado. Las notas no son una pausa salvo
que expresamente lo indiquen.

**Orquesta con Orca y Astra.** El usuario autoriza usar
`openai/gpt-6-astra` para TODOS los workers de este trabajo: implementacion,
investigacion y revision. No aplicar el reparto economico GLM/Muse de la skill
por defecto ni sustituir el modelo sin justificar el bloqueo. No cambies el
modelo/configuracion global del chat principal.

Reutiliza un agente solo si su contexto es util para la nueva tarea (por ejemplo,
su propio codigo y decisiones). No lo reutilices simplemente porque esta abierto.
Para revisiones independientes y areas distintas, prefiere agentes frescos.
Cierra/libera los que hayan terminado y no vayan a aportar continuidad.

## 2. Lectura inicial y estado Git: critico

Lee, en este orden:

1. `AGENTS.md`.
2. `ROADMAP.md`, especialmente el bloque C0-C8 y su estado final.
3. `ACTION_PLAN.md`: C6-C8, seccion 8 historica C1-C5 y seccion 9 final C6 neutral.
4. `DESIGN.md`: secciones 2.1-2.3 y decisiones 8.1-8.7.
5. `CHANGELOG.md`, Unreleased, `MIGRATION.md` y `OBSERVABILITY.md`.
6. `ORCHESTRATION.md`: pausa/preparacion nocturna, **Final C6 checkpoint** y su
   **Final acceptance and resources**. El cierre C1-C5 de mas abajo es historico.
7. `RESEARCH.md` para fuentes/contexto de observabilidad; no rehagas toda la
   investigacion del ecosistema. Usa documentacion actual/Context7 para las APIs
   concretas que vayas a implementar.

Algunos documentos conservan entradas historicas (319, 516, 541, 542 tests,
o 27 focales C6). El cierre actual es **579 tests correctos y 28 excluidos en
ambos runtimes**; decisiones finales y codigo prevalecen sobre cortes anteriores.

**Hay mucho trabajo valido SIN COMMIT, incluidos archivos UNTRACKED.** Todo el
core consolidado, nuevas clases, tests y documentos estan en este worktree.
No hagas reset/clean/stash/checkout para volver al commit base ni borres archivos
por no estar versionados. Inspecciona el estado actual y preserva cualquier
trabajo nuevo del usuario.

- HEAD al relevo: `c08125be71eada363d08ca463cc7df2ea7855e4a`.
- Rama `main`, un commit por delante y tres por detras de `origin/main`.
- Los tres commits remotos agregan OpenCode Zen/Go/version 1.3.0. Su adapter se
  traslado manualmente al nuevo contrato; **no se hizo merge**. No fusionar
  automaticamente ni reintroducir codigo viejo sobre las correcciones.
- `mix.exs` conserva version nominal **1.2.0**, pero el codigo contiene rupturas
  para una futura **major 2.x o posterior**. No es una release 1.x publicable.

Sin peticion expresa: **no commits, bumps, push/PR, Hex publish, despliegues,
reinicios/global config, ni modificaciones de consumidores**. Inferencia de los
workers Astra esta autorizada; eso NO autoriza tests pagados de proveedores LLM.
Usa apply_patch para ediciones manuales. No expongas credenciales ni capabilities.

Trabajo tecnico autonomo dentro del repo: codigo, tests, fixtures sinteticas,
benchmarks acotados, docs y empaquetado local. Dependencias necesarias y tooling de
pruebas se gestionan localmente; si hace falta un toolchain extra, solo aislamiento
en `/tmp/opencode`, origen verificado y sin configuracion/instalacion global. Si
el entorno no lo permite, registra ese limite y cambia a otra unidad. No instales
infraestructura para rellenar tiempo, no uses servicios pagados ni datos reales.

## 3. Orca: cargar la skill y recuperar autoridad

**Carga la skill `orca-orchestration` antes de asignar trabajo.** No basta con
usar subagentes nativos OpenCode. En este flujo utiliza Tasks/Dispatch/workers de
Orca, sin otra red paralela de subagentes. Sigue tambien las skills pertinentes
de debugging y verificacion cuando corresponda.

Descubre estado real desde el terminal del coordinador:

```bash
orca status --json
orca worktree current --json
orca orchestration run-current --json
orca orchestration run-list --json
```

Datos HISTORICOS para localizar la ejecucion, no credenciales ni autoridad nueva:

- Runtime: `bd91a4f6-82f0-4a36-b3c3-db7494593bc1`, host `local`.
- Orca observado: `1.4.198-kukapu.1`; OpenCode workers: `1.18.30`.
- Worktree key: `wt2:local:4d7e38d1-cc77-4904-90e3-7117ab004c64`.
- Worktree ID: `83438294-6397-425c-a0b2-8def0a505dda::/home/kukapu/dev/projects/exAgent`.
- Run C1-C5: `run_ab7595996c57`; fue generation1 durante su ejecucion. El ultimo
  descubrimiento lo muestra generation2 sin coordinador, tras enlazar C6.
- Run C6: `run_395ccad931e7`, generation 1; unidad neutral completada, aceptacion
  externa pendiente. Inspeccionarlo antes de decidir otro Run o retomar autoridad.
- Coordinador anterior: `term_64587472-faf7-47e2-875c-6f990f29d728`.
- **Los siete workers C1-C5 y los cinco C6 estan cerrados. No reutilizar handles.**
  La ultima verificacion fue task `task_5aa36ce92827`, dispatch `ctx_be95da946f17`,
  finalizado y liberado. Los registros retained historicos no prueban terminal viva.

Inspecciona el Run pertinente antes de enlazarlo o abrir un Run para el nuevo
mandato nocturno C6-local/C8. Este ultimo seria una nueva ejecucion autorizada,
no una excusa para duplicar un intento activo. No suplantes el
handle anterior con --from ni robes autoridad a otro coordinador activo.
Confirma identidad/generacion con el runtime y la skill.

### Diferencias verificadas de esta CLI frente a ejemplos de la skill

- `worker-start --spec` NO existe: crear Task primero, luego iniciar por --task.
- `worker-list --include-remote` NO existe en esta instalacion. Todos los workers
  anteriores fueron locales; revalida capacidades si cambia el runtime.
- OpenCode acepta --model, **no --effort**. No inventar --variant. Se observo Astra
  xhigh en autores/revisores C6 y high en verificador final; requested no demuestra
  estado actual. No se modifico el modelo/configuracion global del coordinador.
- Aviso de terminal background no discoverable NO exige abrirlo/focalizarlo.
- Ante incompatibilidad, consultar --help de ese comando; no actualizar Orca ni
  reiniciar el servidor que te aloja para resolverlo.

Plantillas (sustituye IDs por recibos reales):

```bash
orca orchestration task-create --run <run_id> --task-title "Resultado concreto" --spec "Objetivo, ownership, restricciones, pruebas, entrega" --json
orca orchestration worker-start --run <run_id> --task <task_id> --worktree path:/home/kukapu/dev/projects/exAgent --agent opencode --model openai/gpt-6-astra --json
orca orchestration check --run <run_id> --wait --timeout-ms 60000 --json
orca orchestration worker-list --run <run_id> --json
```

Procesa TODO el lote FIFO, leyendo cuerpos/payloads, y luego ACK por deliveryId.
Sin ACK, check repite el lote y puedes perder instrucciones nuevas por mirar
solo subjects. Responde preguntas con reply --id, no otro send inconexo. Instruye
tambien a workers a leer/confirmar su correo antes de subpasos y worker_done.

No recompiles fuentes compartidas mientras otro worker las edita. Ownership
exclusivo por area, contrato compartido con un responsable y ventana de build
coordinada. Un worker_done preparado sin tests no cierra la aceptacion: revisa
diff y ejecuta gates. La ultima revision debe tener contexto fresco.

worker-read --source auto puede paginar un transcript anterior; para progreso
reciente con PTY, --source terminal funciono. Ante source_changed, reinicia la
lectura, no reutilices cursor. Silencio/live/idle no prueban lo mismo: aplica
la supervision y recuperacion de la skill, sin matar o duplicar intentos inciertos.

worker-release cierra solo recursos probadamente propios y finalizados; puede
devolver retained con processAction none. En la ejecucion previa, con autorizacion
expresa del usuario para cerrar agentes sin uso, se verificaron Task terminada,
preview idle, identidad/path exactos y se cerraron panes concretos. Nunca --all,
nunca el coordinador, nunca un worker activo o una terminal ajena por aproximacion.

## 4. Base ya implementada: preservar sus invariantes

C0-C5 tienen implementacion y aceptacion offline; no empieces de cero:

- **Agente != proceso.** Definicion reutilizable, run concreto, Server opcional
  para conversacion, Session para coordinacion. OTP no hace replay/rollback de IO.
- **Un loop sync/stream.** run/3, stream_text:true y run_stream/3 comparten tools,
  Ecto, hooks, limites y estado del modelo. Stream publico: delta provisional,
  un result completo o un RunError; construccion lazy y cleanup bajo demanda.
  Terminal Model: `{:response, response, final_model}`; EOF incompleto es error.
- **Errores parciales.** `{:error, %ExAgent.RunError{reason, partial}}`. El resultado
  conserva output/messages/new_messages/usage/run_step/model y agrega IDs, status,
  usage_status, request_count/tool_calls, cost_cents/cost_status. RunError/model son
  runtime ricos y pueden contener credenciales: no serializarlos indiscriminadamente.
- **Tools.** JSV 0.22 valida antes de efectos; cache por definicion/schema exacto;
  argumentos sin coercion/defaults/atom creation; resultados JSON validos y sin
  duplicados incluso con Fragment. Ecto sigue siendo autoridad del output final.
  Casts/module refs ejecutables y HTTP/file schema resolution se bloquean antes
  de build; un solo dialecto efectivo draft7/2020-12. No quitar estos guards.
- **Vocabulario JSV acotado.** Corrige uniqueItems numerico y longitud Unicode
  por codepoints mediante extension publica; retirarlo cuando upstream pase
  sus regresiones. No reemplazar por un validador casero ni debilitar schemas.
- **Efectos/historia.** Batch conserva todos los outcomes; retries de ejecucion
  requieren ModelRetry explicito. ToolReturn.status distingue succeeded, denied,
  validation_error, failed, unknown, not_executed. La Response efectiva tras
  after_model_request gobierna output/tools; truncado no ejecuta llamadas.
- **ExecutionScope.** run_child/4 fija ancestry y comparte admision atomica,
  restricciones de ancestros, uso reconciliado y guardianes. Padres no suman otra
  vez totales ya inclusivos. Conserva el ultimo subtotal publicado si muere el
  scope. Estimadores/aprobadores no bloquean el actor de contabilidad.
- **Coste/limites.** run_step local; request_count de subarbol. CostGuard usa
  centimos por 1K tokens y conserva fracciones. Unknown no es cero ni factura.
  Estimador aridad1 homogeneo/aridad2 model-aware; deadline monotonic absoluto
  puede ser negativo; concurrencia fail-fast, sin cola infinita ni preemption
  universal de callbacks. IO ajeno al scope no se contabiliza magicamente.
- **Compaction.** Solo request_messages; canonical y new_messages se conservan.
  Protege instrucciones/ultimo User/grupos por ocurrencias, no por MapSet global
  de valores. Resumen User, no System. Historial canonico aun puede crecer.
- **Store/Session.** Store opt-in confirma antes de ACK positivo. CheckpointError
  conserva resultado/revision; dirty bloquea nuevas mutaciones; checkpoint/1
  reintenta SOLO save. Async admission es volatil. v2 writer/v1 reader validado;
  restore corrupto/futuro/id/policy incorrectos no arranca vacio ni sobreescribe.
  Policy viene de configuracion confiable; Session guarda una transicion completa.
- **MCP/HTTP.** Timers/monitores del caller, cierre unico, Port exits y prefijos
  validos antes de frame excesivo. MCP: 128 pending/8MiB frame; streaming: 1MiB
  frame/buffer, 8MiB respuesta, timeout demanda60s, configurables. HTTP retry y
  redirects false. Mantener defaults structured required/any y overrides validos.
- **Diagnostico.** ErrorProjection.reason/message compartido por telemetry/run!
  y Event; conserva provider/status/categoria seguros sin model/body/headers.
  on_progress y on_event interno explicito pueden llevar estado rico; no son
  automaticamente un payload exportable ni equivalentes a :telemetry.
- **C6.** Ver seccion siguiente: trazas opcionales, SDK app-owned, bounded processor
  y perfil fijo. ErrorProjection.diagnostic es mas estricto para OTel/checkpointlog;
  no sustituye los canales ricos explicitos. Server sintetizado por abort/crash
  marca partial/unknown tambien en retorno/Event, preservando subtotales conocidos.

Mapa principal: lib/exagent.ex, run_context.ex, execution_scope.ex, run_stream.ex,
model.ex, message.ex, error_projection.ex, tool/*, providers/*, telemetry.ex,
event.ex, server.ex, runtime_checkpoint.ex, snapshots y session/policy_codec.ex.

ReqLLM se evaluo y **no se adopto**: conservar adapters/helpers actuales evita
romper consumidores sin prueba de equivalencia. No reabrir la decision por moda.
OpenCode Zen/Go ya esta integrado al nuevo contrato.

## 5. C6: decision de observabilidad y aceptacion

Objetivo: configuracion ergonomica en la aplicacion (endpoint/credenciales) e
instrumentacion reutilizable de los agentes, sin atar ExAgent a un panel.

**Decidido e implementado:** OTel nativo Erlang/Elixir; OTLP como transporte de la
app, Collector opcional. Langfuse OSS es candidato preferente provisional; Opik
es alternativa seria. **Instrumentacion neutral verificada; ningun backend
elegido definitivamente y exporter OTLP real aun no probado.** Comparar
ambos con el mismo escenario real antes de decidir. Si ya existe Opik util,
conservarlo de partida; alojamiento/instancia/historico aun no estan confirmados.

Preferencia del usuario: mas funcionalidades sin licencia comercial a calidad
comparable; acepta funciones administrativas de pago si hay una ventaja relevante
demostrada en observabilidad. No volver a preguntar esta preferencia. Ambos cores
son abiertos; Apache vs MIT no demuestra por si solo mas producto gratuito.
Langfuse tiene funciones enterprise; Opik OSS limita gestion de usuarios.
Revalidar versiones/licencias al probar, sin predecir un ganador por estrellas.

### Unidad neutral implementada y verificada

- `ExAgent.Observability.OpenTelemetry.new/1`, opcion observability en Agent/run/
  Server/Session, capture_context/with_context efimeros. API1.5 y SDK1.7 opcionales;
  SDK runtime:false con arista de compilacion para consumidores. No moverlo a
  only:test: se reprodujo un host con SDK que quedaba sdk_unavailable por el orden.
- Spans run/model/tool/delegacion/compaction/checkpoint. Server comparte un unico
  run hasta save. Lazy stream captura al enumerar; colas al admitir. Contexto y
  tres claves Logger propias se limpian/restauran al entrar/salir sin borrar cambios
  ajenos. Monitores/guardianes cubren kill de operaciones y callbacks trap_exit.
- `BoundedProcessor`: slots finitos pending+inflight, batch/deadline, un exporter y
  observer de contadores con guardianes, flush coalescido sin ACK, shutdown descarta
  y puede ser reiniciado por supervisor SDK permanente. La app retira el provider.
  SDK BSP1.7 tiene cota blanda y no da estos contadores; no reemplazar sin evidencia.
- Contenido off; opt-in exige redactor, limites de entrada/plain data y UTF8 de
  salida antes de atributos. Structs/Ecto, thinking/model/deps/config y baggage
  excluidos. Bigints tienen cota real conservadora, no coste constante de16 bytes.
- Perfil exagent.gen_ai.v1, SHA b5d8440f6f126738fd50f927752cd669772c517b; sin inventar
  schemaURL. GenAI usage solo request; cache_write actual, Anthropic input inclusivo
  solo en proyeccion, custom semantica desconocida explicita. Costes del ledger,
  sin otro estimador. Agregadosrun inclusivos nativos separados.
- En terminal sintetico Server por abort/crash: partial/unknown en RunError/Event,
  sin perder cifras; span exagent.usage.source=last_progress y coste previo en
  exagent.cost.known_subtotal_cents, no como total. Errores core confirmados intactos.
- Bootstrap de processors/exporter sin secretos: con SASL activo, SDK/OTP imprime
  mfargs en restart. Credenciales desde env/config de exporter; opts %{} recomendado.
  No interceptar Logger global ni prometer redaccion de cualquier exporter externo.

R3 flush esta probado mediante `test/support/observability_processor_probe.exs`,
que fuerza scheduling en copia en memoria; **usar comando elixir aislado de su
cabecera, no mix run**. No agrega hooks productivos ni depende de /tmp. F1-F3 de
tracing reprodujeron6 fallos/21 antesfix y ahora hay21 tests; processor16. El total
nuevo es37 tests, mas ese probe separado. Dos revisores y verificador fueron frescos.

### Datos de la auditoria que ahorran repetir investigacion OTLP

Son observaciones de codigo/documentacion de las versiones consultadas, **no
aceptacion runtime del exporter real**. Revalidar al instalar la version concreta:

- API1.5.0, SDK1.7.0 y exporter1.10.0 corresponden al corte upstream
  `9f0511e705f18e4b3cc1767b42367ba49e02455a`. El exporter trae dependencias gRPC
  aunque se elija HTTP; no hacerlo obligatorio en la biblioteca por ese ensayo.
- Usar `:http_protobuf` para el primer ensayo: `http_json` figuraba como
  `{error, unimplemented}`. OTLP aceptado por una plataforma no prueba que este
  exporter implemente cada transporte/variante de ella.
- `otlp_endpoint` agrega v1/traces; `otlp_traces_endpoint` preserva path completo.
  El exporter consulta headers/config propios; credenciales fuera de los opts
  supervisados del processor, incluidos los del receptor falso (solo sentinels).
- La ruta HTTP considera200-202 exito e ignora el body exitoso, incluso
  partial_success. El mapping de timeout de request estaba comentado y el I/O
  ocurre mediante `:httpc`; no dar por activas env vars estandar solo por su nombre.
- La auditoria no vio cierre de profiles HTTP en shutdown nativo. Medir el
  lifecycle real antes de afirmar fuga o solucion: pueden ser recursos de app/SDK.
- El BSP nativo puede descartar batches fallidos sin replay, no tiene todos los
  contadores pedidos y su flush es cast. Nuestro processor ya resuelve su propia
  cota, ownership y wakeup, pero no certifica internals del exporter/HTTP remoto.

Informe detallado si sigue presente: `/tmp/opencode/exagent-c6-sdk-audit.md`.
Los tests native-OTLP todavia NO existen; los actuales usan exporters locales
con behaviour nativo y la matriz de consumidores no incluia el exporter OTLP.

### Aceptacion restante, sin rehacer lo anterior

Los criterios originales siguientes conservan valor como checklist de aceptacion;
1-6 ya tienen implementacion/evidencia offline en ACTION_PLAN9. Falta especialmente
la ruta exporter OTLP nativo/cleanup y 7 contra plataformas autorizadas:

1. Revisar instrumentacion/IDs existentes y docs OTel actuales. :telemetry tiene
   menos fronteras que RunEvent; no basta exportar todos sus payloads ni inferir
   una jerarquia completa desde los cuatro eventos historicos.
2. Adaptador opcional; API/SDK/exporter configurados por la app. No sustituir su
   tracer global ni imponer servicios externos/DB para el caso sencillo.
3. Spans run/model/tool/delegacion/compaction/checkpoint, propagacion explicita
   entre Tasks/GenServers y restauracion del contexto. Una operacion/span, no
   uno por token ni por toda la vida del Server. Perfil GenAI versionado: sus
   convenciones son mutables y OTLP aceptado no garantiza semantica de UI.
4. Contenido desactivado por defecto; opt-in y redaccion ANTES de exportar.
   No model/deps/config/keys en atributos o baggage. Aprovechar ErrorProjection;
   no confiar en masking tardio del backend ni prometer pensamiento interno oculto.
5. Exportacion asincrona con cola acotada, batch/saturacion/fallo observables,
   sin HTTP lento dentro del handler sincrono de :telemetry ni bloqueando el run.
6. Exporter local/in-memory y pruebas offline primero. Escenario comun: varias
   requests, tools paralelas, delegado, retry, error, cancelacion y checkpoint;
   comprobar IDs/arbol/errores/uso-cache-coste sin sumar padre+hijos dos veces.
7. Probar destino con datos sinteticos y acceso autorizado; inspeccionar API/UI,
   no solo HTTP200. Medir perdida de informacion, facilidad de diagnostico y
   operacion. Pruebas de backend caido, consumidor lento y ausencia de secretos.

Un trace muestreado no es el ledger de coste. Prompts, datasets, evaluaciones y
scores no migran automaticamente cambiando endpoint; su integracion va separada
del camino critico del run. No elegir/desplegar infraestructura ni contratar
servicios a escondidas. Si falta acceso, continuar las unidades locales de las
secciones8-9 y registrar el gate externo bloqueado, sin rehacer C6 neutral.

C7 es aprobacion diferida persistida, aun no implementada y condicionada al
alcance; no mantener workers esperando horas ni confundir replay de prompt con
resumir una operacion aprobada. C8 incluye proveedores/DB reales, migracion de
consumidores, cargas/evals y preparar la major, sin publicacion automatica.

## 6. Verificacion disponible y comandos

Ultimo cierre C6 neutral, 2026-09-09:

- Elixir1.20.0 / OTP29.0.5: 579 pass,28excluded, seed482769.
- Elixir1.18.4 / OTP28.0: 607 total,0fail,28excluded =579 pass, seed648445.
- Compile forzado de72 archivos con warnings-as-errors en ambos.
- Baseline nativo posterior, antes de la pausa nocturna:579/28, seed806578;
  no reemplaza la matriz anterior ni implica un nuevo cambio de implementacion.
- 14 invariantes en7 grupos C0 true. Los numeros historicos anteriores no son
  nuevos resultados; repetir baseline al iniciar el nuevo trabajo y registrar
  evidencia propia. Elixir1.17 NO esta probado aunque sea el minimo declarado.

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs --bench
EXAGENT_OFFLINE=1 elixir -pa _build/test/lib/opentelemetry/ebin -pa _build/test/lib/opentelemetry_api/ebin -pa _build/test/lib/telemetry/ebin test/support/observability_processor_probe.exs
```

Matriz alternativa con versiones que ya estaban instaladas (revalidar con mise):

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-c6-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix compile --force --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test MIX_BUILD_PATH=/tmp/opencode/exagent-c6-compat-118-final mise exec elixir@1.18.4-otp-28 erlang@28.0 -- mix test --warnings-as-errors
```

Si cambian deps, builds alternativos pueden conservar .app/BEAM antiguos:
recompilar correctamente o usar otro MIX_BUILD_PATH temporal, no tocar WIP ni
suponer que --force del proyecto recompila todas las dependencias. No verificar
cambios con --no-compile: antes se uso SOLO como reproduccion controlada contra
BEAM previo, seguida de compilacion y verde.

Pruebas excluidas: proveedores reales y Postgres. MCP stdio Python y HTTP local
fake si se ejecutaron. Cinco ejemplos offline pasaron. Docs con warnings-as-errors
y Hex build LOCAL pasaron; artefactos temporales no son releases publicadas.

Conservar pisos Mint1.10/HPAX>=1.0.4 en manifiesto (no solo lock): se reprodujo que
Mint1.9 acumulaba un chunk enorme antes de que pudiera actuar nuestro limite.
Postgrex0.22.4/DBConnection2.10.2 son de tests; no introducir SQL obligatorio.

Cache: un spike controlado redujo p50 de1092 a143us (definicion reutilizada,
concurrencia1). Construccion paga preparacion; no es aceleracion de LLM real
ni equivale a los15us de la base antigua sin estas garantias. No quitar controles
para ganar un benchmark. Registrar overhead OTel desactivado/activado.

C6 midio50warmup/200muestras/c1: disabled p50/p95 56/70us, enabled123/178us,
construccion fuera. Ejemplo509/509 exportados, cero drops/error/timeout. Tres
consumidores minimos temporales sin OTel, API-only y SDK pasaron compile sinwarnings
y smoke; SDK compilo antesExAgent con deps.compile exagent --include-children.
No son Dragonex/WhoamAI. Informes /tmp/opencode/exagent-c6-final-verification.md y
logs exagent-c6-final-; evidencia durable ACTION_PLAN9 y tests. El baseline C6
mostro un timeout100ms de readiness previo a cambios: se amplio a1000ms conservando
checks de cancelacion. Una fixture schema de keys exactas se actualizo solo para
observability:nil, manteniendo la API original y ausencia de modos schema nuevos.

Los informes/logs de /tmp/opencode pueden desaparecer: ACTION_PLAN, DESIGN,
CHANGELOG y tests del repositorio son el respaldo persistente. Docs temporales:
/tmp/opencode/exagent-c6-docs, generadas con warnings-as-errors tras corregir un
autolink de la guia. Hex build LOCAL paso en /tmp/opencode/exagent-c6-preview.tar,
incluyendo docs de uso y SDK/API opcionales; conserva version1.2 nominal:
NO publicarlo como la major. Artefactos exagent-docs/consolidation-preview anteriores
son historicos. No hay workers activos ni una tarea que continue sola al cerrar.

## 7. Consumidores: contexto real, no permiso de modificacion

- Dragonex: `/home/kukapu/dev/projects/dragonex`, Git ExAgent a31b306/1.3.0.
  Usa Server.chat(stream_text:true), deps.on_text_delta, after_model_request con
  narracion y efectos antes del terminal, custom WorldDriven Session policy,
  OpenRouter/OpenCode. Reintenta beats completos y reconstruye historia desde
  sus eventos: debe migrar manejo de parciales para no repetir efectos.
  Hay fixtures que omiten mode requerido; arreglar consumidor, no debilitar schema.
  Su override local apunta ../exagent, distinto de ../exAgent en Linux.
- WhoamAI: `/home/kukapu/dev/projects/whoamai`, vendor/exAgent c08125b/1.2.0.
  Usa run sync, Ecto output, request_limit1, max_steps1, output_retries0 y un
  OpenRouterModel propio con Admission/coste antes de validar output. :busy local
  no es fallo del proveedor. Consume OpenAIChat.Config/encode_tools/
  to_openai_messages/parse_body; preservar controles de coste y tool_choice.

Ambos fueron inventariados en lectura, no ejecutados ni modificados. Cambiar este
repo no actualiza automaticamente sus pins/vendor. MIGRATION contiene puntos de
adaptacion concretos. No leer .env/DB/datos de usuarios para ese inventario.

## 8. Arranque y estrategia para la noche

1. Carga la skill, recupera autoridad/Run, revisa WIP y registra hora de inicio y
   baseline. Si acaba de verificarse y no cambio codigo, evita repetir checks sin
   motivo; cada implementacion nueva si necesita su aceptacion compilada propia.
2. Convierte la primera oleada en Tasks concretas con ownership. **Empieza pequeno:
   dos frentes independientes**, no18 workers a la vez. Un autor puede investigar,
   implementar y probar su unidad. Revisiones frescas al estabilizar el codigo.
3. Primer frente recomendado: N01-N03, OTLP nativo local. Segundo: N05/N06 sobre un
   artefacto congelado en /tmp, o inventario read-only de los siguientes riesgos.
   El segundo no debe compilar fuentes que el primero esta editando. Una prueba
   de un paquete congelado independiente si puede tener su propia ventana/build.
4. Ownership inicial razonable: autor OTLP posee tests/fixtures nuevos y, si hace
   falta, `lib/exagent/observability/*`; un solo responsable de mix.exs/mix.lock.
   Coordinador posee contratos/docs/checkpoints e integracion. N07-N11 requieren
   reasignar explicitamente core/runtime/protocolos; no dos escritores del mismo
   archivo. Los reviewers no implementan bajo una Task de solo lectura.
5. Tras una unidad verde, actualiza evidencia, liquida recursos, selecciona la
   siguiente unidad util y **continua**. La ausencia del usuario no bloquea
   decisiones tecnicas ordinarias, regresiones ni ensayos sinteticos.

No confundir una larga lista con trabajo realizado. Los IDs N01-N18 son etiquetas
de este backlog, **no IDs reales de Orca**. Crear Tasks conforme a necesidad y usar
siempre Task/Dispatch/terminal devueltos por el runtime. No hace falta materializar
todo el backlog en Orca antes de producir el primer cambio verificable.

## 9. Backlog nocturno autonomo, por prioridad y dependencias

Es una cola amplia para varias horas, no una obligacion de llenar tiempo ni una
promesa de completar cada item. No presupone que cada area tenga bugs. Primero
reproducir/caracterizar; modificar cuando haya beneficio demostrado. Si una unidad
ya tiene cobertura equivalente, comprobarlo y avanzar, no duplicarla para contar
tests. **Corregir P0/P1 reales tiene prioridad sobre ampliar ejemplos o cobertura.**

### A. Terminar la frontera local de C6 sin elegir plataforma

**N01 — Exporter OTLP nativo end-to-end con receptor loopback.**
Instalar solo en el entorno de pruebas las dependencias necesarias y verificar
APIs actuales con Context7. Usar `opentelemetry_exporter` nativo, SDK y processor
ya implementados; receptor efimero ligado a loopback/puerto dinamico. Verificar
POST, ruta completa, content-type y protobuf decodificado con codigo oficial,
resource/instrumentation scope, trace/span/parent IDs y atributos. Headers solo
sinteticos, contenidos sensibles fuera del cuerpo. Persistir el escenario en tests
o soporte del repo; no depender solamente de scripts /tmp. **Cierre:** una traza
ExAgent reconocible atraveso el exporter real y fue inspeccionada, no solo HTTP200.

**N02 — Matriz de errores y aceptacion parcial OTLP.** Depende de N01.
Receptor que devuelve401/403/429/503, corta conexion, demora respuesta o devuelve
200 con partial_success/rejected_spans; tiempos y cuerpos pequenos. Comprobar
que runs no esperan I/O del exporter, no se repiten efectos y counters distinguen
lo que realmente conocen. La auditoria de1.10 encontro que el exporter puede
ignorar partial_success y que flush no es ACK: confirmar, no presentarlo como fix
ya hecho. Documentar limitaciones upstream o corregir por una extension estrecha
si hay soporte/beneficio claro; no escribir otro cliente/protocolo OTLP completo.
**Cierre:** pruebas causales y semantica de delivery/counters honesta bajo fallo.

**N03 — Cleanup real de HTTP/exporter ante timeout y restart.** Depende de N01.
Medir en una VM propia perfiles `:httpc`/inets, sockets, procesos/monitores y tablas
antes/despues de varios ciclos init/export/timeout/shutdown/restart. La auditoria
observo que shutdown HTTP nativo no cierra expresamente sus profiles: es una
hipotesis de lifecycle a comprobar, no una fuga runtime certificada. Distinguir
recursos de SDK/app y recursos de ExAgent. Corregir fugas reales mediante ownership
o configuracion soportada, sin cerrar servicios/profiles ajenos ni cambiar globals
del VPS. Usar pocas iteraciones con barreras; nada de agotamiento deliberado de RAM,
FDs o atomos. **Cierre:** recursos poseidos recuperados o limite concreto sustentado
y alternativa segura documentada; no equiparar muerte del runner con cierre TCP.

**N04 — Escenario compuesto exportado, fidelidad del perfil.** Depende de N01.
Reutilizar escenario existente y componer requests multiples, tools paralelas,
delegado, correccion/retry, error, cancelacion, compaction y checkpoint. Inspeccionar
el protobuf recibido: un span por operacion, jerarquia correcta, sin spans por
token, uso/cache/coste por generacion frente a subtotales. Comprobar tambien fallo
despues de hook, cola de dos callers y error parcial sin coste cero inventado.
**Cierre:** prueba reproducible comun para futuros backends con aserciones de datos;
no afirmar que Langfuse/Opik ya renderizan bien ese mismo payload.

### B. C8: paquete, versiones y contrato de consumidor

**N05 — Consumir el paquete construido, no solo path al repo.** Independiente de N01
si usa tar congelado. Construir/desempaquetar un artefacto local en /tmp e instalarlo
en fixtures desechables: sin OTel/SQL, API sola, SDK configurado y exporter opt-in.
Probar un ejemplo de run, stream, tool tipada y checkpoint ETS. Verificar archivos
incluidos, opcion de SDK/order, ausencia de dependencias test/doc en runtime y que
ningun modulo dependa de un archivo solo disponible en el checkout. **Cierre:**
consumidores usan bytes del paquete, no symlink al codigo vivo. Nominal1.2.0 sigue
siendo preview local; **no publicar** ni cambiar pins de apps existentes.

**N06 — Minimo Elixir declarado y matriz de dependencias.** Puede usar N05 congelado.
Revalidar toolchains ya instalados. Intentar Elixir1.17 con OTP compatible en un
entorno aislado si se obtiene de fuente oficial verificable sin sudo/globales.
No modificar `.tool-versions` o mise global para probar. Ejecutar compile, contrato
core y pruebas pertinentes; separar fallo de tooling, incompatibilidad de una dep
y defecto ExAgent. Contrastar lock root y resolucion fresca dentro de rangos
permitidos. **Cierre:** evidencia propia del minimo o incompatibilidad localizada
con correccion justificada/documentacion; no inventar soporte ni bajar controles.
Si tooling no esta disponible, seguir N07+ y dejar gate claro, sin esperar al autor.

### C. Regresiones de core, runtime y protocolos

**N07 — Maquina de estados del Server y checkpoint bajo secuencias de fallos.**
Model-based/generativo acotado con semillas registradas: chat/send/stream/steer,
busy/queue_full, abort, owner/worker DOWN, Store error/raise y retry-save. Contar
efectos, terminales, revisiones y datos recuperables. Verificar que dirty impide
nuevas mutaciones/drain y que guardar otra vez no invoca modelo/tools. **Cierre:**
invariantes publicas despues de cada transicion; fallos reducidos a regresiones
deterministas. No relajar asserts ni introducir sleep largo para ocultar carreras.

**N08 — FSM Session, snapshots y restauracion adversarial.**
Secuencias join/rejoin/leave/start/pause/resume/handoff/turn/close, policy custom
confiable y restore frio. Validar roster/cursor/current/status, una transicion por
checkpoint y fallos de codec/load sin sobrescribir. Datos v1/v2, futuros, truncados
y policy/id incorrectos; sin atomos/modulos elegidos por bytes no confiables.
**Cierre:** modelo de estado simple independiente y escenarios de restore/cold
start; no convertir snapshots en replay universal ni incluir C7 por accidente.

**N09 — Scope/autoridad/contabilidad bajo concurrencia y errores.**
Hijos anidados/paralelos compiten por requests/concurrencia/budget/deadline;
intercalar rechazos, muerte de scope/owner y uso parcial. Contar requests reales
y efectos de tools, llamadas al estimador y subtotales por identidad. Verificar
herencia de deny/ask, admission previa y ausencia de doble conteo. Incluir limites
antes/despues de hooks que cambian la respuesta efectiva. **Cierre:** pruebas de
operaciones observables, sin suponer preemption de callbacks ajenos ni IO magico.

**N10 — Streaming/SSE/HTTP y MCP: fragmentacion y cleanup generativos.**
Reutilizar fakes existentes. Particiones de un mismo byte stream, CRLF, UTF8,
EOF/truncado, frames concatenados y prefijo valido seguido de tail excesivo.
Equivalencia sync/stream de terminal/modelo/history; consumer lento, halt,
suspension/reanudacion, caller death y late replies MCP. **Cierre:** mismo resultado
independiente de fragmentacion, limites en datos pequenos, finalizacion unica y
mailbox ajeno preservado. Nunca llamadas a proveedores reales ni puertos publicos.

**N11 — Frontera Tool/JSON Schema y resultados adversariales.**
Buscar huecos no cubiertos en dialectos/refs/encoding/claves ambiguas/defaults,
cache invalidada al cambiar definicion y hooks sobre tool efectiva. Probar antes
de efectos y conservar todos los outcomes de batch. Fuzz acotado y controles
positivos, sin generar atomos indefinidos. **Cierre:** validador JSV sigue siendo
autoridad del schema y Ecto del output; no validador casero, casts ejecutables,
resolucion HTTP/file ni weakening de schemas de consumidores para dar verde.

### D. Privacidad, operacion y rendimiento medidos

**N12 — Privacidad de extremo a extremo y aislamiento entre callers.**
Complementar, no duplicar, los tests C6: sentinels distintos en prompts, args,
results, model/deps, errores y credencial de transporte. El header sintetico debe
llegar al receptor para autenticar, **no** al cuerpo de spans/baggage/diagnosticos.
Comprobar contexto/Logger durante y despues de callbacks, entrada vacia, redactor
fallido/stateful/oversize y cleanup abrupto. **Cierre:** datos permitidos/omitidos
observados en la frontera real. Canales ricos explicitos no son automaticamente
exportables; no prometer sanitizar todos los logs de codigo arbitrario de la app.

**N13 — Carga acotada y soak con consumidores/exporters lentos.**
Comparar concurrencia1/8/32 (o menor si el host lo necesita), p50/p95/p99, maximos
observados de memoria/mailbox/pids/FDs/ETS en la VM de prueba, tiempos de cleanup,
drops y resultado correcto. Casos simples y con tools/delegacion; mismas entradas,
definicion reutilizada y warmup, OTel off/on. Duraciones/cantidades finitas fijadas
antes, sin saturar el VPS ni hacer polling infinito. **Cierre:** informe reproducible
con limites, recursos y seed; no reemplazar percentiles por una media favorable.

**N14 — Optimizacion dirigida solo a hotspots medidos.** Depende de N13 o evidencia
equivalente. Una mejora pequena a la vez, misma carga antes/despues, verificar
efectos/cleanup/privacidad y coste de construccion frente a reutilizacion. No quitar
JSV/guards/limites para ganar microsegundos ni agregar una cache global con secretos.
**Cierre:** beneficio medido sin regresion; si no hay hotspot relevante, registrar
que no requiere cambio y pasar a otra unidad, no inventar una reescritura.

### E. Aceptacion util para usuarios y cierre coherente

**N15 — Evals deterministas de framework en dos dominios genericos.**
Runner offline reproducible (ejemplo/test support, no nueva plataforma): output
tipado + lectura, efecto simulado + fallo + recuperacion, delegado restringido,
retry correctivo y checkpoint. Resultado verificable, efectos no autorizados=0,
requests/uso/coste conocido o desconocido, y criterios de exito claros. **Cierre:**
reporte legible por maquina y controles negativos; medir framework, no fingir un
benchmark de inteligencia ni ejecutar jueces/LLMs de pago.

**N16 — Matriz de capacidades, ejemplos y migracion auditables.**
Relacionar cada promesa de README/DESIGN/MIGRATION/OBSERVABILITY con test o gate
pendiente. Distinguir protocolo/adaptador de proveedor/modelo real, sync/stream,
outputs/tools/cache/errores. Verificar snippets en fixtures locales y corregir
docs/API ergonomica solo ante problemas demostrados. Contexto de Dragonex/WhoamAI
ya inventariado; no ejecutarlos ni editarlos. **Cierre:** matriz pequena y accionable,
no otra investigacion enciclopedica ni una garantia basada en contar proveedores.

**N17 — Dependencias y limites de contratos restantes, de forma focal.**
Revisar advisories/versiones reales de deps tocadas y pisos del manifiesto; cerrar
solo problemas aplicables con reproduccion/regresion, sin upgrades masivos.
Valorar gaps de ergonomia concretos descubiertos (por ejemplo contenido Ecto
opt-in actualmente omitido) solo si su solucion mantiene privacidad y una API
coherente; no convertir cada limitacion documentada en una feature obligatoria.
**C7 sigue condicionado al alcance**: se puede preparar una decision tecnica
acotada de aprobacion persistida/spike aislado, pero no introducir publicamente
continuaciones/replay o un workflow engine para llenar la noche. No es bloqueante
para N01-N16 ni requiere dejar workers esperando una aprobacion humana.

**N18 — Aceptacion integrada y relevo final.** Despues de las unidades completadas.
Revision fresca de cambios de alto riesgo, compile y suite offline, matriz de
runtimes disponibles y de consumidores del paquete, probes afectados, ejemplos,
docs warnings-as-errors, formato/diff y Hex build local. Separar excluded de pass.
Actualizar ROADMAP/ACTION_PLAN/DESIGN/CHANGELOG/MIGRATION y este relevo con
implementado/evidencia/limitaciones. **Cierre:** P0/P1 nuevos resueltos o delimitados
con evidencia y bloqueo real, WIP preservado, ninguna release automatica, recursos
Orca liquidados y siguiente accion recuperable. No declarar toda C8 cerrada: sus
backends/consumidores reales siguen requiriendo aceptacion propia.

## 10. Disciplina de ejecucion y continuidad entre unidades

- **Ciclo por unidad:** problema/hipotesis concreta -> reproduccion -> decision ->
  cambio minimo -> focales compilados -> review segun riesgo -> integracion ->
  evidencia durable -> siguiente unidad. Un test que solo imita la implementacion
  no sustituye una invariante de resultados/efectos/recursos.
- **Barreras y seeds:** preferir mensajes/monitores/fixtures causales. Si se usa
  scheduling instrumentado en copia aislada, explicitarlo y persistir un probe;
  no presentarlo como corrida sin instrumentacion. Reducir casos generados fallidos.
- **Builds:** un responsable por ventana, sin compilar fuentes editadas por otro.
  Las deps Erlang pueden compartir caches Rebar aunque MIX_BUILD_PATH difiera;
  no lanzar recompilaciones del mismo arbol en paralelo por asumir aislamiento.
  Nuevos buildpaths para grafos/runtimes distintos; nunca limpiar WIP para probar.
- **Sintetico/local:** sockets loopback y puertos dinamicos; datos inventados y
  servicios efimeros de la prueba. Cada test/probe posee y cierra sus procesos.
  Esto no autoriza Docker/despliegues, servicios persistentes, datos de usuarios
  ni instrumentar otras aplicaciones del VPS.
- **Dependencias/docs:** Context7 para las APIs concretas, contrastar version
  instalada cuando la documentacion va desfasada. Nuevas deps solo justificadas y
  de test/opt-in cuando corresponda. No reabrir ReqLLM o backend por moda.
- **No expandir permisos:** sin respuesta del usuario, no comprar, desplegar,
  publicar, cambiar version, commitear, ejecutar proveedores/DB reales o migrar
  consumidores. Registrar ese gate y elegir otra rama. No convertir ausencia en
  consentimiento ni llenar todas las tareas con preguntas que no son necesarias.
- **Supervision:** procesar mail FIFO, reply por ID a preguntas, ACK cada lote y
  revisar lo que devuelve el ACK. No terminar el turno con workers simplemente
  lanzados. Reutilizar contexto solo donde aporta, reviewers frescos; release al
  dejar de necesitar un agente, respetando liveness/propiedad real.
- **Presupuesto:** trabajo sustancial, no computo artificial. La preferencia por
  Astra es expresa; no cambiar modelo/config global ni sondear cuota con llamadas
  LLM repetidas. Ante un limite real, registrar evidencia y recuperacion soportada.
- **Contexto:** checkpoints breves despues de cada unidad y antes de acercarse al
  limite; no cargar todos los transcripts ni duplicar todo este relevo en cada
  worker. Guardar Task/Dispatch/ownership/gates/nextAction sin capabilities.
- **Compactacion:** preferir automatica del runtime. No ejecutar /compact manual
  en el coordinador y prometer auto-continuacion: esta CLI no la garantiza. Para
  una continuacion manual se necesita supervisor externo/usuario y autoridad
  revalidada, no timers ciegos. Un Run almacena estado/correo, no piensa solo.

## 11. Resultado esperado al terminar la noche

Continua trabajando durante esta sesion mientras haya unidades viables, sin
pararte al primer verde. Prioriza profundidad/correccion de varias unidades sobre
marcar todas superficialmente. Si finaliza el alcance util antes de lo previsto,
cierra con evidencia; si el usuario da una hora limite, deja de asignar trabajo
nuevo al alcanzarla y guarda un checkpoint seguro.

La entrega debe decir: que unidades se completaron, bugs realmente reproducidos
y corregidos, comandos/entornos/seeds y contadores, rendimiento con condiciones,
gates externos bloqueados, cambios observables y migracion, estado Git y workers.
No prometer seguir en segundo plano despues de terminar el turno: el siguiente
chat debe estar iniciado y mantener al coordinador ejecutandose. Si se pierde
runtime/autoridad, informar del bloqueo sin reiniciar servicios ni suplantar IDs.

**Primera accion despues de leer y recuperar:** abrir una oleada pequena de
OTLP local y aceptacion de artefacto/compatibilidad realmente independientes,
empezar la implementacion/verificacion y supervisar hasta poder pasar a la
siguiente. No devolver solamente otro prompt, un plan o una promesa de continuar.
