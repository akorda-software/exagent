# R1.4 — caracterización pública de streaming stock1.24

## Protocolo fijado antes de ejecutar

HEAD7f25b33 + WIP R1.2; lock `6fefa5f0ee909c3947db51fb562eaf9cf6b0ec8c3fd529e03a3071e02b85960f`.
No cambios de dependencia ni adopción de spikes. API observada: `stream_text/3`,
una única vista `StreamResponse.events/1`, `close/1`, accesores de metadata;
transporte Finch real contra servidor TCP loopback sintético. Ningún parser SSE
propio en biblioteca, llamada a proceso/callback privado ni mock de ReqLLM.

**Umbrales propuestos para aceptar una integración:** frame64KiB, respuesta256KiB,
cierre del socket y recursos efímeros en2s tras close/halt/muerte del consumidor.
Son oráculos de este experimento, no opciones que stock ya ofrezca ni garantías
publicadas. Timeout total15s/receive10s permite distinguir cleanup2s de timeout.
Cada corrida limitada a1MiB de bytes enviados y una conexión; seis escenarios
finitos, sin soak ni agotamiento de memoria. Pool dedicado size1/count1, teardown
explícito. El watermark1 mide chunks; nunca se interpreta como bytes.

Escenarios:

1. Crear stream sin enumerar: observar si la request ya llega al peer; distinguir
   apertura ansiosa upstream de una envoltura lazy posible en ExAgent.
2. Consumo único completo con terminal, cerrar metadata/transporte; acceso público
   a metadata antes/después de close y conteo de procesos efímeros complementario.
3. Frame grande256KiB y consumidor lento; frame incompleto512KiB sin separador:
   barreras de envío, memoria de VM/binaries y llegada pública de deltas. No inferir
   atribución exclusiva a ReqLLM desde memoria global que también incluye fixture.
4. EOF sin terminal, JSON/frame truncado y tool args incompletos: inspeccionar evento
   terminal y tool call ensamblada sin ejecutar tools. Un `finish` por EOF no prueba
   respuesta completa; ExAgent requeriría terminal provider válido.
5. Halt temprano de events con close explícito: peer confirma desconexión.
6. Muerte abrupta del owner/consumidor, sin ejecutar su after: peer observa si se
   cierra dentro2s. Contrastar owner antes/después de comenzar a enumerar.

**Inspección inicial:** código1.24 inicia transporte antes de devolver StreamResponse;
events es lazy sobre una fuente única, y close público cancela+detiene metadata.
StreamServer documenta high_watermark de chunks y overflow por evento de transporte,
no una cota de bytes. Búsqueda de límites frame/response/body por bytes en `lib/`
no encontró opción pública: hay riesgo de bloqueo, por demostrar con el loopback.

Resultados y decisión se añaden tras ejecutar; no aceptación previa de R1.4.

### Enmienda tras primer intento, antes del loopback efectivo

La probe inicial devuelve exit2,0/7: opciones `finch_name`, `high_watermark` y
`metadata_timeout` por request llegan a validación provider y son rechazadas por
NimbleOptions. No se ejecutaron los escenarios de red; es incompatibilidad entre
guía/contrato de streaming y fachada/provider stock, no evidencia de bytes/cleanup.
Para aislar el resto sin cambiar upstream se usa configuración pública de la VM
disposable: pool default size1/count1 y metadata_timeout10s, sin esos kwargs.
El watermark efectivo de stock es500;1 no pudo configurarse por esa API pública.
Los umbrales byte/cleanup y máximos del experimento no cambian. Se conserva el rojo.

## Resultado observado y decisión R1.4

Probe durable: `test/support/req_llm_streaming_probe.exs`, una vista events por
respuesta, sin invocar privados ni crear SSE/transporte alternativo en ExAgent.
Elixir1.20.0/OTP29.0.5, ReqLLM1.24.0 del lock intacto, dotenv false antes de
startup. Sólo configuración de la VM disposable, no configuración del host.

- **Apertura:** el peer recibe request antes de enumerar. La construcción de una
  closure no hace IO; envolver la apertura dentro de Stream.resource permitiría
  lazy en ExAgent, pero no resuelve los bloqueos restantes.
- **Una vista/terminal:** normal emite start,text_delta,finish y metadata stop.
  EOF tras texto o JSON truncado emite finish con razón incomplete; no éxito
  completo. Tool args truncados generan tool_call con `{}`, metadata invalid/raw
  y terminal incomplete: nunca autorizan efectos antes de validar terminal.
- **Bytes:** frame de262144bytes de texto se entrega íntegro como un delta, pese
  al presupuesto propuesto64KiB. Un frame incompleto de524288bytes sigue con
  socket abierto tras2s; no hay límite público predecode demostrado. Default
  watermark500 limita chunks, no este buffer de frame. Deltas VM-binary iniciales
  fueron1251136/1511816bytes y en repetición3876744/4147440bytes: incluyen fixture,
  logs/GC y toda la VM, **no atribución de memoria exclusiva ni prueba de infinito**.
- **Cleanup observado:** close/halt cierran TCP y el handle de metadata. Matar al
  creador antes o después de comenzar la misma enumeración cierra ambos dentro2s;
  el DOWN de metadata se verifica antes del close de limpieza del test. No acepta
  todos los escenarios de handoff entre owners distintos ni una VM longeva.
- Los dumps OTP del kill muestran el marcador de key **sintética** en
  telemetry.original_opts aunque request headers aparezcan redactados. No había
  credenciales reales; es otra frontera a revisar antes de usar streaming live,
  no se corrigió ni ocultó en esta unidad.

**Decisión confirmada por el coordinador:** R1.4 bloqueada por presupuesto público
de bytes predecode ausente; basta requisito no satisfecho, sin extrapolar a OOM
ni seguridad universal. `request_stream` permanece unsupported; no integración
parcial encubierta, fork ni dependencias nuevas. Se necesita API pública de límite
frame/respuesta y error/cleanup antes de materializar contenido, o una decisión
explícita de dependencia/alcance; watermark y timeout no prueban cota de bytes.

## Review buffered recibida durante la unidad

Informe completo `/tmp/opencode/exagent-r12-review/REVIEW.md`, task_5062a20e4aed,
sobre TAR61eaffda. Revisor terminó; no había aceptado los cambios posteriores.

1. **A1/P1:** `[]` JSON pasa a `{}` en Defaults + ResponseBuilder, se elimina raw
   e invalidity; la API pública ya es indistinguible de un objeto vacío legítimo.
   Root reprodujo un efecto con schema object/additionalProperties:false. Custom
   Model/Test que conserva `[]` sí rechaza y `{}` válido ejecuta una vez.
2. **A2/P1:** Anthropic redacted_thinking se descarta antes del mensaje público y
   content se elimina de provider_meta. El callback inerte upstream no protege
   efectos posteriores del loop si se acepta esa continuación incompleta.
3. **A3/P2:** supports_thinking=true incluso con reasoning.enabled=false.

**Guards autorizados, no fixes upstream:** perfil tools:false para todo ReqLLM
stock; tool/output definitions se rechazan antes de IO, también historial con
toolcalls y calls inesperadas en respuesta. Anthropic thinking explícito,
reasoning no false o cualquier continuación Response se rechazan antes de IO;
thinking visible inesperado falla. Thinking sólo se anuncia para OpenAI con
capability enabled y sin supported:false. Test/custom/legacy no cambian.

Se rebaja **R1.2 a aceptación parcial**, R1.3 suma Anthropic a Google. Retirar guards
exige señal pública fiel de argumentos/bloques; no se analiza wire privado, no se
infiere invalidez de `{}`, no se adopta el spike usage. Texto/imagen y reasoning-only
Responses probados siguen disponibles; tools/Ecto-tool no se presentan aceptados.

Regresiones `test/exagent/req_llm_safety_test.exs`: caracterización stock con controles
objeto/array, rechazo de adapter ceroIO/efectos, custom/Test positivo/negativo,
capability positiva/negativa y redacted. Las dos caracterizaciones no exigen mantener
el bug como contrato: son tripwires para revisar/retirar el guard si cambia upstream.
Los tests que aceptaban tools del adapter se convierten en guards explícitos, no
skips; las cifras previas672/9 pertenecen a bytes anteriores rechazados por review.

## Readiness: diagnóstico acotado preservando el rojo

La suite guardada volvió a fallar en server_ownership:41 readiness100ms,677/678.
Con autorización se ejecutó **una** corrida diagnóstica: mantuvo assert100ms y
re-raise, midiendo la llegada posterior a155ms desde admisión; server waiting,
cola0, gen_server.loop y eventos run_started/run_step_started ya emitidos.
No era pérdida de trabajo/cola atascada en esa observación. Se corrigió **sólo**
la barrera readiness a1000ms; todos los asserts DOWN/cancelación conservan límites.
Se retiró instrumentación y suite final678/0/28 pasó. No se atribuye el retraso a
Mint ni se convierte el diagnóstico instrumentado rojo en aceptación verde.

## Comandos, exits y artefactos

Driver `/tmp/opencode/exagent-r11-run.py` reutilizado con prefijo aislado de
environment.md, allowlist de entorno, EXAGENT_OFFLINE=1/MIX_ENV=test y labels nuevos.
Cada log/JSON en `/tmp/opencode/exagent-r11/` conserva comandos, entorno, exit y wall.
Semilla37556 salvo snippets0; ninguna llamada pagada/backend ni instalación tooling.

| Label | Comando | Exit / segundos | Resultado |
|---|---|---|---|
| r14-streaming-probe | Elixir directo probe |2 /3.005 |0/7; kwargs rechazados, sin aceptación de red |
| r14-streaming-stock-defaults | misma probe, config pública de VM corregida |0 /5.258 |7/0/0 caracterización |
| r14-streaming-final | probe con DOWN observado antes de close de limpieza |0 /5.272 |7/0/0, no aceptación R1.4 |
| r14-buffered-p1-red | `mix test test/exagent/req_llm_safety_test.exs --warnings-as-errors --seed 37556` |2 /2.765 |2/5, tres defectos reproducidos |
| r14-buffered-p1-green | mismo focal con guards |0 /2.991 |5/0/0 |
| r14-safe-buffered-focals | safety + req_llm_model_test con mismos flags |0 /5.420 |18/0/0 |
| r14-compile | `mix compile --force --warnings-as-errors` |0 /1.686 |77 fuentes |
| r14-suite | `mix test --warnings-as-errors --seed 37556` |2 /19.829 |677/1/28, readiness |
| r14-readiness-diagnostic | mismo comando, instrumentación conserva fallo |2 /19.664 |677/1/28; llegada155ms |
| r14-suite-final | mismo comando, sólo readiness corregida |0 /20.041 |**678/0/28** |
| r14-format | `mix format --check-formatted` |0 /0.419 |formato correcto |
| r14-preview | `mix hex.build --output /tmp/opencode/exagent-r11/r14-safe-preview.tar` |0 /0.490 |99 miembros |
| r14-consumer-deps | `mix deps.get` en consumidor nativo nuevo |0 /1.444 |resolución propia sin lock raíz |
| r14-consumer-tests | `mix test --warnings-as-errors --seed 37556` en consumidor |0 /22.895 |**9/0/0**,65 fuentes paquete |
| r14-consumer-graph | `mix run --no-start graph.exs` |0 /0.756 |25 apps,107 módulos con provenance local |
| r14-docs | `MIX_ENV=dev mix docs --warnings-as-errors` |0 /1.786 |ExDoc correcto |
| r14-snippets | Elixir directo documentation_probe con dotenv false |0 /1.410 |7/0/0 seed0 |
| r14-links / r14-plan | checkers locales de enlaces/IDs |0 /0.041;0 /0.022 |212links/38Markdown;57IDs/10escenarios/6gates |

28 excluidos son integración providers/Postgres, no aceptación externa. Logs de
kill y args_lost en probe son estímulos sintéticos esperados; no se suprimen.
La suite runtime se repitió por guards P1, no para fingir streaming aceptado.

### Identidad del cierre seguro

| Artefacto | SHA256 |
|---|---|
| Lock raíz sin cambios | `6fefa5f0ee909c3947db51fb562eaf9cf6b0ec8c3fd529e03a3071e02b85960f` |
| Adapter guardado | `b48ec19c189293ac3e3060c3ce3a96a78a71d937678351b18c849dedee900d40` |
| Probe streaming | `cdc89a387dd7816598d3b3ef460fafe02c02f11583e458f8d6f50ba865baef73` |
| Regresiones safety | `595cc77a26e9a2e0b2627d3fcdbefa2f17b1ef454d99951c2da2e568ec1f95ad` |
| TAR safe | `70ae28528769da3d2d148074ba1f42fdbdaa6f60814ad8c6ecbc29229590fcc5` |
| Lock consumidor independiente | `08e7fa6aee64f42c8ddaee8d5e0e7b70d57413e7b74a04aa2b7cbec30758750f` |

Consumidor `/tmp/opencode/exagent-r14-safe/consumer-native`, bytes TAR sin symlink,
manifest/checksum en `package-input.json` del padre; fuentes/deps/build propios.
Los seis escenarios existentes se mantienen, ahora con texto+guard tools ceroIO
y custom Model, más tres tests host. Sin SQL/Jido/SDK obligatorios. Warnings
TOML/WebSockex y cuatro deprecaciones del transporte funcional Req0.7 se conservan;
no pase strict. Sólo se revalidó el grafo nativo afectado, no toda la matriz1.18.
No atribuir al nuevo TAR los pases de bytes anteriores; versión nominal sin bump.
El cierre documental posterior a su construcción sólo actualiza resultados/rutas,
no altera las fuentes probadas ni pretende publicar una candidata2.0.
`git diff --check` final exit0. No hubo cambios de deps/lock ni a consumidores
reales; las únicas instancias reiniciadas fueron VMs/fixtures efímeras propias.

## Trabajo siguiente independiente y dependencias reales

**R1.6 limitado es viable en una nueva task:** settings/opciones de texto buffered,
precedencia por instancia/gateway, auth y claves reservadas, timeout total frente a
receive/pool, intento único y errores diagnósticos con transporte sintético. Hoy
ya hay knobs básicos, allowlist pequeña, extra rechazado, redirect:false y
max_retries:0; eso no cierra toda la negociación/options/retries de R1.6.

Dependen de resolución pública upstream: fidelidad tool args (R1.2), bloques
Anthropic/firmas Google (R1.3), bytes de streaming (R1.4), uso observado/derivado
(R1.5), y aceptación integral de retries/contabilidad/stream en R1.6. R1.7 puede
preparar fixtures textuales/runtime, pero no cierra paridad; R1.8 no retira legacy.
No bloqueo global de todo trabajo, tampoco avanzar R2 sin fronteras R1 aceptadas.
No se inicia R1.6 ni otra task en esta entrega. La decisión de versión/extensión
externa queda con evidencia; ningún patch/path/fork fue adoptado de forma implícita.
