# Consumidor real028 — 2026-10-02

Mandato explícito del usuario: adaptar el proyecto hermano y probar10–20 casos
reales con su key OpenRouter. Consumidor `exAgentTest/chat_app`, WIP preservado,
sin Git ni cambios de `.env`.18 casos implementados y aceptados externamente;
preparación offline8 controles no se cuenta como proveedor. Tres fronteras P2 del
driver/admisión revisadas una vez y corregidas: señales del dueño, liberación de
fd/flock en preflight y flood/redacción a4MiB.12 controles finales y dos VMs
offline hasta60reservas/USD1.50. No re-review ni reinicio del ledger al fallar.

Perfil/modelo: OpenRouter GPT-4o-mini, ReqLLM1.24 stock/OpenAIChat sin reasoning;
tools chat_tools_v1/native chat_json_schema_v1, Elixir1.20.0/OTP29.0.5. Nuevo
ledger global60requests, input16KiB/10messages/output512, reserva25,000microUSD
por admisión; host exacto separado de precio normalizado o factura. Concurrency
de suite1; fan-out del caso14concurrency2; retries HTTP/output/tools0.

| Ola | Pase/fallo | Admisiones | Acumulado | Alcance |
|---|---|---|---|---|
|01|13/18,exit2|25|25|Se conservan cinco rojos y todas las fuentes|
|02|0/1,17excl,exit2|1|26|Diagnóstico06 invalid_tool_arguments/efectos0|
|03|1/1,17excl,exit0|3|29|06 secuencial, mismo oráculo de dos tools/resultados|
|04|1/1,17excl,exit0|2|31|17 consulta terminal mediante API administrativa|
|05|1/1,17excl,exit0|2|33|13 router instruido sobre Frame corregido|
|06|1/1,17excl,exit0|4|37|14 dos ramas instruidas/efectos/orden|
|07|1/1,17excl,exit0|3|40|15 extracción real/mapper Ecto/publish7|

Resultado agregado:18 escenarios aceptados,36requests/13efectos independientes
en sus ejecuciones verdes; fase completa40requests/1,000,000microUSD de reserva.
Factura null. Siete grupos registrados cerrados/reaptados, fuentes inmutables por
ola y ningún timeout/flood. No es un único18/18 sobre la fuente inicial; el delta
de cinco casos se explicita y los otros13pases se reutilizan por camino intacto.

06 reprodujo un lote de argumentos inválidos del modelo: guard del sobre intacto,
Model1/tool0/efectos0. La forma final es secuencial; el lote múltiple original
sigue sin aceptar. No cambiar validación, reparar JSON o anunciar ese lote verde.
17 era un oráculo del consumidor incorrecto: Layer0 resume requiere ready;
completed se consulta por Continuation.get y otro resume rechaza sin IO. No se
amplió ese contrato para satisfacer un test. Ambas olas fallidas se conservan.

13–15 encontraron un defecto propio nuevo: node_evidence10 esperaba sólo User
en la primera Request y rechazaba las instrucciones System canónicas. Diseño8.49
documenta el arreglo general: prefijo System seguido de un único User/input/run
exactos. Frame fuente final SHA
`bd20af0b5ef2f8955a28c81bf738172a98fe6f84d0647c13323f7b5c83b18d54`.
Stock offline/dummy-key/capability que bloquea IO da rojo con instrucciones,
control sin ellas alcanza el callback; tras el parche ambos lo alcanzan sin HTTP.
Tres regresiones API pasan strict en1.1s, conservar instrucciones/counters/
completed inerte y rechazar corrupciones;45 casos adyacentes pasan. El primer
fixture nuevo tenía tres errores de oráculo y warnings de unquote estático,
corregidos con context tags/JSON codec/input secuencial; los logs rojos permanecen.
No hay formato nuevo, fork, lock/library-deps ni migración.

El consumidor retiró su parser HTTP/vision privado y usa el adapter público stock;
imagen canónica plana y credenciales explícitas, ReqLLM.load_dotenv false.
Dependencias oficiales y lock del consumidor actualizados; el lock raíz intacto.
Precommit real del consumidor:15pases offline/18excl/exit0. Cold TOML19 y
WebSockex19 clasificados; no suppress/fork/reparación global. La suite live no usa
TestModel; éste sólo aparece en regresiones offline del paquete.

Recibos bajo `/tmp/opencode/exagent-v2-codex-t6qgpstl/e2e028/`:
summary SHA `f94dacdca2d17e93d74f4fec3af6964afbfa94006e8546814251de839979cccc`.
Driver review REPORT SHA
`8f084e04209f150b5542e909723ddb3966ab2a58e2afea81f40c9ebdf826b099`;
review receipt `69b5177556914ddf59f0882066d6d1e09de6aea2c4e9f66a9a3ca64b5c8431e1`.
Detalles/casos/counters en E2E-RESULTS del consumidor; guía distribuida
[E2E con OpenRouter](../../development/real-consumer-e2e.md).

No certifica navegadorJS/LiveView por WebSocket, SQL duradero entre VMs, HA/SLO,
billing, defaults DeepSeek/Gemini u otras combinaciones de catálogo. G2 anterior,
SQL, Langfuse y Opik conservan sus identidades; ninguna ola cloud repetida aquí.
La candidata derivada029 incorpora tres fuentes core corregidas frente026,
además de tests/harness/docs. CI remoto exacto y autorización Git/bump/Hex abiertos.
