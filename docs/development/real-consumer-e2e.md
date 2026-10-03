# E2E del consumidor Phoenix con OpenRouter

El consumidor hermano `exAgentTest/chat_app` contiene **23 escenarios opt-in** que
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
proveedores con reasoning activado y errores de red/reintentos con incertidumbre
externa requieren objetivos y oráculos propios. SQL entre VMs y pérdida de ACK
ya tienen su aceptación G3; no se atribuyen a esta matriz de modelos.

Estos escenarios no aceptan navegador JavaScript, SQL duradero entre VMs, HA,
facturación ni todos los modelos de OpenRouter. La matriz G2 anterior, G3 SQL,
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
