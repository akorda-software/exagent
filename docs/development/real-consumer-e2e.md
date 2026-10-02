# E2E del consumidor Phoenix con OpenRouter

El consumidor hermano `exAgentTest/chat_app` contiene18 escenarios opt-in que
recorren aplicación, API pública de ExAgent, ReqLLM stock y un modelo real. La
suite offline habitual excluye estos casos. Datos, tickets y efectos son sintéticos;
el modelo, transporte y herramientas locales usados en la ola live son reales.

## Perfil y ejecución

El driver `scripts/run_live_e2e.py` del consumidor usa explícitamente
`openai/gpt-4o-mini` en `https://openrouter.ai/api/v1`, OpenAI Chat sin reasoning,
ReqLLM1.24, `chat_tools_v1` y `chat_json_schema_v1`. Ese perfil temporal no modifica
los modelos ni la credencial del `.env` del usuario. No hay parser HTTP privado,
fork, TestModel ni fallback en los18 escenarios live.

Primero preparar dependencias y ejecutar `EXAGENT_OFFLINE=1 MIX_ENV=test mix
precommit`. Después, desde el consumidor y con un directorio de evidencia nuevo:

```bash
mkdir -m 700 /tmp/chat-app-e2e
e2e_source_sha=$(python3 scripts/run_live_e2e.py --fingerprint)
python3 scripts/run_live_e2e.py --live --env-file .env \
  --source-sha256 "$e2e_source_sha" \
  --phase-ledger /tmp/chat-app-e2e/phase.json \
  --artifacts /tmp/chat-app-e2e/wave-01
```

El opt-in es obligatorio; el driver rechaza `EXAGENT_OFFLINE=1`, otra identidad
de runner o una fuente cambiada antes de leer la clave. El ledger persistente
se comparte entre VMs e intentos:60 peticiones como máximo, reserva25,000microUSD
por petición y1,500,000microUSD totales. Un fallo consume su reserva. No es una
factura ni un límite impuesto por OpenRouter. La admisión mide16KiB de entrada
JSON lógica,10 mensajes y512 tokens de salida; cada agente limita4requests,
3tools y4pasos, sin retries automáticos de HTTP/output/tools.

Una repetición causal usa `--test-line` y el mismo `--phase-ledger` con una ola
nueva. No reiniciar el ledger ni repetir los casos ya aceptados por cambiar prosa.
El dueño limita900s y4MiB de log, conserva el líder hasta cerrar su grupo propio
y redacta la clave antes de guardar stdout. `source.json`, `admissions.json`,
`cases.json`, `case-NN.json` y `receipt.json` identifican fuente, contadores,
efectos independientes, pases/exclusiones, reserva y cleanup. Errores operativos
usan categorías acotadas; no exportar RunError.partial ni structs con credenciales.

## Escenarios y alcance

| Casos | Frontera y oráculo |
|---|---|
|01–02|Chat sync y streaming: marcador, un terminal y deltas iguales al texto final|
|03–06|Herramientas reales: suma, palabras, hora UTC y dos llamadas en secuencia; cada efecto una vez|
|07–09|Ticket de texto tool/native y PNG: Ecto valida cabecera, cantidades y precios|
|10–12|Server con memoria/reset, Phoenix PubSub con identidad/request y Session con dos turnos/estado compartido|
|13–15|Router seleccionado, dos ramas paralelas en orden de definición y Composition con mapper tipado una vez|
|16|Delegación real: peticiones del hijo reconciliadas una vez en el ancestro|
|17–18|C7 approve/deny: actor host/payload exactos, duplicados, cero efecto antes y ausencia de replay terminal|

Estos escenarios no aceptan navegador JavaScript, SQL duradero entre VMs, HA,
facturación ni todos los modelos de OpenRouter. La matriz G2 anterior, G3 SQL,
G4 Langfuse/Opik y los controles críticos027 conservan sus propios perfiles y
recibos. Los resultados efectivamente obtenidos viven en `E2E-RESULTS.md` del
consumidor y en el registro028 del checkout; una exclusión nunca cuenta como pase.

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
