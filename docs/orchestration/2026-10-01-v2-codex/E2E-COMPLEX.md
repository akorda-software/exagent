# Flujos E2E complejos — 2026-10-03

Encargo explícito: tres casos que combinen mecanismos y un recorrido completo de
aplicación. Los casos nuevos **24–27 pasan con TestModel y con GPT-6-Luna y
DeepSeek V4.1 Flash reales**. Se conserva el fallo inicial de DeepSeek 27 y los
rojos del montaje offline. No se cambian contratos ni guards de la biblioteca.

## Escenarios y evidencia

| Caso | Recorrido | Requests reales por modelo | Efectos sintéticos |
|---|---|---|---|
|24|Seis etapas: extracción JSON, Ecto, precio, publicación aprobada, archivo y resultado|9|3, una vez cada uno|
|25|Tres ramas, dos niveles de delegación, barrera de solapamiento y failure collect|9|2; un intento fallido sin efecto|
|26|Preparación/check/pago; VM sale73 después del efecto SQL antes del ACK; nueva VM espera lease real y recupera|4|2; payment uncertain sin replay|
|27|Preparación tipada, memoria Server, Session/turnos, busy/abort, paralelo/delegación, dos aprobaciones, salida73, PostgreSQL reiniciado, nueva VM, archivo y stream|24|8; increment_shared dos turnos, demás efectos una vez|

27 se divide en seed/resume: **14 + 10 peticiones**. Antes del reinicio, el estado
compartido es count1 y el siguiente participante b. La VM nueva recupera historial,
count1/turnb y permite count2 una sola vez. Rechaza el resume sin aprobar y las
decisiones con actor/hash incorrectos sin Model IO; los duplicados son inertes.
Cada aprobación permite su efecto y mantiene bloqueado el siguiente. Conserva el
fallo de la tercera rama; no repite preparación, mappers, audit ni reserve_stock.
La lectura completed de las raíces tampoco hace IO. Los deltas PubSub reconstruyen
el texto canónico final. El worker cancelado termina y Server vuelve a idle.

26 comprueba una frontera distinta: hay efecto externo observado pero el host no
recibe su ACK. El estado uncertain impide reanudar automáticamente; no se pretende
garantizar exactly-once externo. Recovery es administrativo, explícito e idempotente,
con lease real, sin reloj simulado. No se inventa un éxito para continuar ese pago.

La aplicación enlaza raíces públicas Composition/Flow/Server/Session; no introduce
Composition/Flow anidados. El caso completo combina las familias principales,
pero imagen/native output/deny conservan sus escenarios específicos. No acredita
todos los protocolos, reasoning activado, browser JavaScript ni HA.

## Ejecución y presupuestos

- Consumidor autorizado: `../exAgentTest/chat_app`; original `.env` preservado.
  Dependencias SQL oficiales sólo en test: EctoSQL3.14/Postgrex0.22.4.
- Tooling físico Elixir1.20.0/OTP29.0.5, ReqLLM1.26 stock/OpenRouter Chat/none.
  IDs exactos `openai/gpt-6-luna` y `deepseek/deepseek-v4.1-flash`.
  Luna sin temperature/top_p; DeepSeek top_p0.01; ningún fallback.
- Fuentes/deps/build privados existentes y útiles reutilizados. Cada fase de los
  casos26/27 arranca una BEAM nueva con módulos previamente compilados; PostgreSQL
  temporal propio17.4, socket Unix privado, TCP deshabilitado por el runner.
- `scripts/run_complex_e2e.py --offline` selecciona TestModel explícitamente;
  `--live --model ...` exige credencial/fingerprint y reutiliza el dueño acotado
  de `run_live_e2e.py`. Casos24–27 mediante `--cases` y ola nueva.
- Nuevas fases complex por modelo:120admisiones/USD3 de reserva estimada.
  Contador SQL conjunto32requests/caso entre raíces y VMs; límites root32requests/
  24tools,6pasos por agente, input16KiB/10mensajes/output512, retries0.
  Tools60s para incluir hijos/checkpoints, plazo y active-time raíz360s.
  El dueño global limita900s/log4MiB y cierra su grupo antes de reap.
- Los ledgers smoke anteriores permanecen intactos. No se reinician reservas ni
  se descuentan fallos. Factura observada null; TestModel no acredita proveedor.

| Perfil | Casos aceptados | Requests verdes | Fase completa | Reserva estimada | Efectos verdes |
|---|---|---|---|---|---|
| Luna |4/4|46|70/120|USD1.75/3|15|
| DeepSeek |4/4|46|53/120|USD1.325/3|15|

## Olas y fallos conservados

| Ola | Resultado | Admisiones | Tiempo ExUnit/driver | Source SHA prefijo |
|---|---|---|---|---|
| Offline01 |24pasa;25 falla worker sin confirmar|17|21.817s|Ver source.json|
| Offline02 diagnóstico |25 reproduce; efecto leaf y middle final confirmados, outer sin final|8|12.093s|Ver source.json|
| Offline03 |25 acaba las nueve requests, pero merge del fixture devuelve un tuple no JSON|9|15.186s|Ver source.json|
| Offline04 |25/26pasan;27 llega a su segunda aprobación y falla selector del fixture|31|62.685s|Ver source.json|
| Offline05 |27pasa completo|24|29.592s|Ver source.json|
| Luna01 |24–27pasan|46|127.977s|0d02762fe2bb|
| DeepSeek01 |24–26pasan;27 falla copia literal de Session tras siete requests|29|81.374s|0d02762fe2bb|
| DeepSeek02 |27pasa con copia ASCII explícita|24|53.405s|bda6e379457a|
| Luna02 |27pasa con la misma instrucción actualizada|24|57.065s|bda6e379457a|

Las tres correcciones offline afectan al montaje:60s explícitos para tools de
delegación frente a los10s heredados del smoke, resultado directo del merge, y
seleccionar sólo la aprobación pendiente manteniendo las decisiones anteriores.
Con60s el outer termina; el intento de10s conservaba un hijo confirmado pero el
wrapper seguía wrapping. No se relaja el guard de workers ni se toca el runtime.
La recuperación de26 espera el lease de30s; no es una prueba excluida por timeout.

DeepSeek27 se detuvo al comparar COUNT_1. Se conservan su efecto y el recibo rojo;
la instrucción nueva pide copiar el ASCII devuelto por la herramienta, preservando
underscores. No incluye el valor esperado ni repara la respuesta. El control guarda
COUNT_1/COUNT_2, terminal stop, un Part.Text y cero reasoning_details. El mismo
control pasa en Luna. Reutilizar24–26 no los convierte en una ola nueva4/4.

Todos los **nueve grupos de escenarios y sus nueve clusters propios** se cierran.
Los diagnósticos administrativos posteriores también paran el cluster original;
no hacen peticiones al modelo. Los ficheros SQL sintéticos quedan conservados para
diagnóstico. Fuentes inmutables durante cada ola. Precommit final exit0:
**17 offline pasan / 27 opt-in excluidos**, seed6085 en el precommit final.

## Identidad y distribución

Artefactos privados: `.exagent-local/complex-e2e20261003/`. Resumen SHA256:
`985dbaba322e340955ba3723aa07732f3f38f2cd80614267a2c3c7342391419f`.
El resumen identifica recibos/casos/ledgers, efectos, grupos y cleanup PostgreSQL.
Los manifests `source.json` identifican fuentes completas de cada ola; los sources
globales son `0d02762fe2bb16d925d6289c7a558f83df129aa797a4f752ac3915d52510ffaf`
y `bda6e379457af1da4e44fa4c51f9679cbfbf116815fc6e15d86e295c2f6cffa1`.

52ficheros ejecutables/config/lock del consumidor original coinciden con la copia
probada. Las94fuentes lib/config/mix/lock raíz coinciden con la biblioteca privada;
root lock SHA256 `2637e0965ebdb015e04d505757bf0de5649affc35670ee77aa11745ecbbcdaeb`.
La documentación posterior se verifica por separado. No se repite FULL/G2/G3/cloud
ni se abre otra review R9 por este delta de consumidor/documentación.

ExDoc estricto exit0:117HTML/5204targets,115Markdown/847targets y115EPUB/2876targets,
cero enlaces/anchors/resources rotos. Build e isolation del TAR exit0;
SHA256 `8c5dc15a220ec353c42db7a6a6b11c7723f4a41402834e94811d0c7b7a490c9e`.
168ficheros exactos al checkout; metadata y91fuentes lib/Mix iguales al TAR
documental anterior de dependencias. Cambian cinco documentos, sin tests,
artefactos privados ni registros de ejecución archivados en la distribución.
Recibos `documentation-receipt.json` y `final-tar-source.json` en el directorio privado.

La cobertura conjunta reutiliza [E2E-MODELS](E2E-MODELS.md): **27/27Luna y
26/27DeepSeek**. El08nativo DeepSeek permanece rojo y el perfil nativo completo
continúa sin aceptar. No se comitea el consumidor untracked, ni se hace bump,
tag, merge o publicación Hex.
