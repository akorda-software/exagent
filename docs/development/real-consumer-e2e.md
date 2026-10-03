# E2E del consumidor Phoenix con OpenRouter

El consumidor hermano `exAgentTest/chat_app` contiene **27 escenarios opt-in** que
recorren aplicación, API pública de ExAgent, ReqLLM stock y un modelo real. La
suite offline habitual excluye estos casos. Datos, tickets y efectos son sintéticos;
el modelo, transporte y herramientas locales usados en la ola live son reales.

## Perfil y ejecución

El driver `scripts/run_live_e2e.py` selecciona uno de estos dos IDs exactos:

| Modelo | Selección y opciones específicas |
|---|---|
| [GPT-6-Luna](https://openrouter.ai/openai/gpt-6-luna) | `--model openai/gpt-6-luna` (predeterminado), sin temperature ni top_p |
| [DeepSeek V4.1 Flash](https://openrouter.ai/deepseek/deepseek-v4.1-flash) | `--model deepseek/deepseek-v4.1-flash`, top_p 0.01 |

Ambos usan `https://openrouter.ai/api/v1`, OpenAI Chat, ReqLLM **1.26.0** stock,
`chat_tools_v1`, `chat_json_schema_v1` y el modo explícito `reasoning_mode: :none`.
El descriptor describe ese protocolo efectivo del gateway; no certifica la API
nativa de cada fabricante ni sus modos de razonamiento activado. El adaptador
stock emite `reasoning_effort: "none"` y `max_completion_tokens: 512`.
La [documentación de OpenRouter](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
describe el control de razonamiento del gateway. Los parámetros de muestreo
admitidos difieren entre estos modelos; no imponer temperature a Luna.
No hay cambio del `.env`, parser privado, TestModel ni fallback en los casos live.
Seleccionar otro ID o reutilizar el ledger de otro modelo rechaza antes de HTTP.

Primero preparar dependencias y ejecutar `EXAGENT_OFFLINE=1 MIX_ENV=test mix
precommit`. Después, desde el consumidor y con un directorio de evidencia nuevo:

```bash
mkdir -m 700 /tmp/chat-app-e2e-luna /tmp/chat-app-e2e-deepseek
e2e_source_sha=$(python3 scripts/run_live_e2e.py --fingerprint)
python3 scripts/run_live_e2e.py --live --model openai/gpt-6-luna --env-file .env \
  --source-sha256 "$e2e_source_sha" \
  --phase-ledger /tmp/chat-app-e2e-luna/phase.json \
  --artifacts /tmp/chat-app-e2e-luna/wave-01
python3 scripts/run_live_e2e.py --live --model deepseek/deepseek-v4.1-flash --env-file .env \
  --source-sha256 "$e2e_source_sha" \
  --phase-ledger /tmp/chat-app-e2e-deepseek/phase.json \
  --artifacts /tmp/chat-app-e2e-deepseek/wave-01
```

El opt-in es obligatorio; el driver rechaza `EXAGENT_OFFLINE=1`, otra identidad
de runner o una fuente cambiada antes de leer la clave. El ledger persistente
se comparte entre VMs e intentos **del mismo modelo**:60 peticiones como máximo, reserva25,000microUSD
por petición y1,500,000microUSD totales. Un fallo consume su reserva. No es una
factura ni un límite impuesto por OpenRouter. La admisión mide16KiB de entrada
JSON lógica,10 mensajes y512 tokens de salida; cada agente limita4requests,
3tools y4pasos, sin retries automáticos de HTTP/output/tools.

Una repetición causal usa `--cases 8` (o `--test-line`) y el mismo `--phase-ledger`
con una ola nueva. `--cases 12,13,14` selecciona varios casos por sus IDs estables;
no combinarlo con `--test-line`. La suite se detiene al primer fallo; los casos
todavía sin ejecutar se seleccionan en la siguiente ola. No reiniciar el ledger
ni repetir los casos ya aceptados por cambiar prosa.
El dueño limita900s y4MiB de log, conserva el líder hasta cerrar su grupo propio
y redacta la clave antes de guardar stdout. `source.json`, `admissions.json`,
`cases.json`, `case-NN.json` y `receipt.json` identifican fuente, contadores,
efectos independientes, pases/exclusiones, reserva y cleanup. Errores operativos
usan categorías acotadas; no exportar RunError.partial ni structs con credenciales.

## Escenarios y alcance

| Casos | Frontera y oráculo |
|---|---|
|01–02|Chat sync y streaming: marcador exacto sin código añadido, un terminal y deltas iguales al texto final|
|03–06|Herramientas reales: suma, palabras, hora UTC y dos llamadas en secuencia; cada efecto una vez|
|07–09|Ticket de texto tool/native y PNG: Ecto valida cabecera, cantidades y precios|
|10–12|Server con memoria/reset, Phoenix PubSub con identidad/request y Session con dos turnos/estado compartido|
|13–15|Router seleccionado, dos ramas paralelas en orden de definición y Composition con mapper tipado una vez|
|16|Delegación real: peticiones del hijo reconciliadas una vez en el ancestro|
|17–18|C7 approve/deny: actor host/payload exactos, duplicados, cero efecto antes y ausencia de replay terminal|
|19|Permisos deny: intento real de herramienta, efecto cero y ausencia de retry|
|20|Error de herramienta: categoría exacta, un callback sin efecto y parada sin otra petición Model|
|21|Server ocupado/abort: rechazos busy sin HTTP, cancelación observada, worker cerrado y estado idle|
|22|Presupuesto de una petición: efecto único y rechazo antes de otro Model IO|
|23|Composition con C7: extracción/mapper una vez, pausa antes del efecto, aprobación duplicada inerte y resume sin replay|

Los cinco casos añadidos comprueban caminos de rechazo/cancelación y la unión
de coordinación con aprobaciones. Escribir un escenario o excluirlo offline
no prueba el proveedor. Los contadores separan admisiones, intentos de callback
y efectos de los fixtures; una cancelación sin resultado final deja el contador
público de tools sin dato, no inventa cero.

La cobertura adicional útil queda delimitada: navegador JavaScript real,
proveedores con reasoning activado y errores de transporte requieren objetivos
y oráculos propios. Los cuatro escenarios complejos siguientes añaden SQL entre
VMs y pérdida de ACK a la matriz del consumidor; G3 conserva su aceptación propia.

Estos escenarios no aceptan navegador JavaScript, HA, facturación ni todos los
modelos de OpenRouter. La matriz G2 anterior, G3 SQL,
G4 Langfuse/Opik y los controles críticos027 conservan sus propios perfiles y
recibos. Los resultados efectivamente obtenidos viven en `E2E-RESULTS.md` del
consumidor y en el recibo vigente del checkout; una exclusión nunca cuenta como pase.

## Aceptación 2026-10-03

Los 23 escenarios se ejecutan para **cada modelo**, con el grafo de dependencias
actual. Precommit consumer: **17 pases offline, cero fallos, 23 exclusiones live**.

| Modelo | Escenarios aceptados | Admisiones de fase | Reserva estimada | Resultado pendiente |
|---|---|---|---|---|
| GPT-6-Luna | 23/23; ola inicial completa y controles causales de marcador | 51 | USD1.275 | Ninguno en esta matriz |
| DeepSeek V4.1 Flash | 22/23, en varias olas con fallos originales conservados | 54 | USD1.35 | 08: ticket JSON nativo, merchant/currency null |

Los casos aceptados suman 44/43 peticiones y 15 efectos sintéticos por modelo.
Los totales de fase incluyen todos los diagnósticos y fallos, sin reset ni refund.
La factura observada permanece null. Todos los 16 grupos propios se cerraron y
las fuentes de cada ola permanecieron inmutables.

DeepSeek alteró marcadores y llegó a incluir el marcador dentro de código ajeno
a la petición. Se conserva ese falso positivo del oráculo antiguo. Los controles
con copia ASCII explícita y comparación exacta pasan en ambos modelos; para
DeepSeek se usa top_p 0.01. Esto no prueba determinismo. El fallo 08 se reproduce
sin cambiar el prompt: el objeto Ecto conserva total/fecha, pero merchant y
currency faltan. Pasar el schema no demuestra fidelidad de extracción. No se
rellenan campos, se reparan respuestas ni se elimina el oráculo; ese caso y la
cualificación completa del perfil nativo de DeepSeek siguen sin aceptar.

La biblioteca y el lock raíz coinciden con la candidata cualificada anterior;
sólo cambian fixtures/driver/lock del consumidor y documentación. Los casos no
afectados reutilizan sus bytes/recibos; los cuatro caminos de marcador cambiados
se comprueban aparte. El [recibo fechado](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/E2E-MODELS.md)
conserva olas, hashes, fallo de instrumentación y límites. No se repite FULL,
G2, SQL ni Langfuse/Opik por estos cambios.

## Flujos complejos 24–27

La suite `complex` reúne tres combinaciones y un recorrido de aplicación completo.
Cada caso usa su propia base de datos en un PostgreSQL temporal del runner, por
socket Unix privado y sin TCP. No usa la base de datos ni el proyecto cloud del
usuario. Los datos y efectos siguen siendo sintéticos; en `--live` las decisiones
y respuestas del modelo se obtienen mediante ReqLLM stock y OpenRouter.

| Caso | Combinación | Comprobaciones |
|---|---|---|
|24|Pedido con seis etapas: extracción, validación Ecto, precio, aprobación de publicación, archivo y resultado|Mappers y efectos una vez; ningún efecto antes de aprobar; decisión duplicada y lectura completed sin IO|
|25|Tres ramas paralelas, dos niveles de delegación y una rama fallida|Barrera entre dos workers demuestra solapamiento; contadores incluyen hijos; merge conserva orden y fallo; efectos confirmados una vez|
|26|Tres etapas con pérdida del ACK del pago|La VM sale justo después del efecto SQL; una VM nueva espera el lease real y recupera administrativamente; estado uncertain, sin repetir pago ni Model IO|
|27|Preparación tipada, Server con memoria, Session por turnos, busy/abort, paralelo con delegación, dos aprobaciones, fallo de una rama, reinicio, archivo y stream por PubSub|Salida abrupta de VM y reinicio PostgreSQL; nueva VM restaura historial/estado/turno; aprobaciones separan efectos; trabajo confirmado y rama fallida no se repiten; deltas corresponden al terminal|

El caso 27 combina las fronteras principales de la aplicación. Los permisos deny,
la extracción nativa y la entrada de imagen conservan sus casos específicos:
no se promete que una sola conversación ejercite todos los modos incompatibles.
La aplicación enlaza raíces Composition/Flow/Server/Session mediante sus APIs;
no introduce definiciones Composition/Flow anidadas. La propiedad de cada raíz
y sus contadores permanece independiente. Un contador SQL de la aplicación
admite como máximo **32 peticiones por caso**, también después de cambiar de VM.

Primero comprobar el montaje sin proveedor; después ejecutar ambos perfiles:

```bash
mkdir -m 700 /tmp/chat-complex-offline /tmp/chat-complex-luna /tmp/chat-complex-deepseek
e2e_source_sha=$(python3 scripts/run_live_e2e.py --fingerprint)
EXAGENT_OFFLINE=1 MIX_ENV=test python3 scripts/run_complex_e2e.py --offline \
  --pg-bin /ruta/absoluta/postgres/bin --source-sha256 "$e2e_source_sha" \
  --phase-ledger /tmp/chat-complex-offline/phase.json \
  --artifacts /tmp/chat-complex-offline/wave-01
MIX_ENV=test python3 scripts/run_complex_e2e.py --live --model openai/gpt-6-luna \
  --env-file .env --pg-bin /ruta/absoluta/postgres/bin \
  --source-sha256 "$e2e_source_sha" --phase-ledger /tmp/chat-complex-luna/phase.json \
  --artifacts /tmp/chat-complex-luna/wave-01
MIX_ENV=test python3 scripts/run_complex_e2e.py --live --model deepseek/deepseek-v4.1-flash \
  --env-file .env --pg-bin /ruta/absoluta/postgres/bin \
  --source-sha256 "$e2e_source_sha" --phase-ledger /tmp/chat-complex-deepseek/phase.json \
  --artifacts /tmp/chat-complex-deepseek/wave-01
```

La instalación PostgreSQL debe existir y tener una ruta física, sin symlinks.
`mix precommit` prepara los módulos de soporte; cada fase ejecuta una BEAM nueva
con `--no-compile` sobre esos mismos bytes. SQL es una dependencia sólo de test.
Los cambios se limitan al consumidor autorizado y sus fixtures.

Cada modelo abre una fase **complex de 120 admisiones / USD3 reservado**; es
independiente de la fase smoke de 60 / USD1.50, cuyos recibos se conservan.
Se mantienen las cotas de entrada/salida y los retries desactivados. Las tools
complejas tienen un timeout finito de 60s para incluir el trabajo de los hijos
y los checkpoints SQL; las raíces tienen plazo/tiempo activo de 360s.
Los intentos fallidos consumen presupuesto y permanecen en la evidencia.
`--cases 26,27` selecciona una continuación causal con el mismo ledger.
El contador SQL observa todas las raíces; sus eventos son instrumentación del
fixture, no una recomendación de que los mappers de producción tengan efectos.

`--offline` usa TestModel explícitamente y comprueba el montaje, sin acreditar
compatibilidad del proveedor. No se usa TestModel ni fallback en `--live`.
La evidencia incluye las fases de VM, efectos SQL, decisiones, contadores,
source SHA, cierre del grupo de procesos y parada del PostgreSQL propio.
La suite habitual excluye los cuatro casos SQL y los 23 casos de proveedor.

**Aceptación compleja 2026-10-03:** los cuatro casos pasan con TestModel y con
cada modelo real. Los verdes de cada modelo suman **46 peticiones / 15 efectos**:
24:9, 25:9, 26:4 y 27:24 peticiones. Luna pasa la ola completa y el control del
prompt Session actualizado. DeepSeek pasa 24–26 en la primera ola; el fallo de
copia literal de Session en 27 se conserva y el control causal pasa tras pedir
copia ASCII explícita, con el mismo oráculo y sin reparar respuestas.
Las fases complex acumulan **70/53 admisiones** y reservas **USD1.75/1.325** para
Luna/DeepSeek, incluyendo todos los intentos; factura observada null.
Todos los nueve grupos de escenarios y sus clusters PostgreSQL propios se cierran.
Precommit final:17 pases offline, cero fallos,27 exclusiones opt-in.

La cobertura conjunta alcanza **27/27 para Luna y 26/27 para DeepSeek** mediante
recibos separados; el ticket JSON nativo 08 de la suite smoke sigue sin aceptar.
No se repiten los otros 23 escenarios ni FULL/G2/G3/cloud. El runtime y lock raíz
permanecen idénticos; SQL se añade sólo al montaje de test del consumidor.
El [recibo complejo](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/E2E-COMPLEX.md)
registra identidades, rojos de montaje y controles de ambos modelos.

## Recibos históricos

**Aceptación2026-10-02:**18 escenarios aceptados mediante ola inicial13/18 y cinco
repeticiones causales; un diagnóstico adicional de06 se conserva rojo.40requests
acumuladas/1,000,000microUSD de reserva, factura null, siete grupos propios cerrados.
Los18 verdes suman36requests/13efectos independientes. Se reutilizan los13pases
por caminos no afectados, con manifests por ola; no declarar un único18/18 inicial.
13–15 detectaron un defecto del certificado: el prefix System canónico debía
preceder al único User/input exacto. Diseño8.49 registra el arreglo y sus3regresiones
strict/45adyacentes.06 rechazó argumentos inválidos sin efectos y se acepta en
secuencia; el lote múltiple original sigue sin aceptar.17 usa Continuation.get
para completed; otro Layer0 resume rechaza sin IO. Precommit consumer15offline/
18excl/exit0. G2/SQL/Langfuse/Opik anteriores no se repiten ni cambian de identidad.
