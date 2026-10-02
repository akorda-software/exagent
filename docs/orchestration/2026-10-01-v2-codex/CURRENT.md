# ExAgent v2 — estado vigente 2026-10-02

Usuario pide completar v2; implementación activa en
/home/kukapu/dev/projects/exAgent, HEAD7f25b33, WIP preservado. ReqLLM oficial
stock, R1.2 aceptado, C7 incluido y guards no demostrados intactos.
El usuario autoriza expresamente el2026-10-02 commit/push en rama nueva y PR
borrador para ejecutar CI remota. Rama `codex/v2-candidate-029`, commit inicial
`b709d571240cc75b6044d4f53ac34ce795347a3c`, PR1 en GitHub;
sin bump/tag/Hex. La pipeline de publicación se preparará después de observar CI.
Una revisión máxima por objetivo, dueño corrige/regresa; sin re-review ni reruns
rutinarios del padre. Paralelo autorizado en la transcripción recibida.

CI030 inicial: [run37008908156](https://github.com/akorda-software/exagent/actions/runs/37008908156),
fuente exacta b709d57. Empaquetado y harness pasan; suite1.18 roja por formato
entre versiones y fixture Regex compilada que Macro.escape no admite en1.18.
Corrección causal en preparación: formato canónico1.20 y Regex en setup runtime,
sin cambiar core ni relajar oráculos. Suite1.20 sigue en curso; consumidores
56contratos/0fallos/0excl con todos los comandos exit0, strictjobs rojos por
warnings stock TOML/WebSockex y gproc. No ocultar ese diagnóstico.
TAR remoto d9a90625965001daef4a1fa52eb89174769401f53a31b22a65cf2911d573478f:
153fuentes exactas029, distinto orden de empaquetado. Evidencia privada en
`/tmp/opencode/exagent-v2-codex-t6qgpstl/ci030/run01/`.029 queda inmutable.

Focales de la corrección: InputRestore/OutputRetryRestore178/178 en ambos
runtimes, exit0 strict; compilación estática118 de165tests detecta seis warnings
propios en cuatro casos Stream de layout constante. Tags/contexto runtime
corrigen esos cuatro sin cambiar assertions:4/4 strict en ambos runtimes,
26excluidos por selección. Logs/rojo original en `ci030/fixture-owner/`.
El nuevo push sustituirá la ejecución previa mediante la concurrencia del PR;
una suite cancelada no cuenta como pase. Los gates estrictos stock se conservan.

Mandato posterior del usuario2026-10-02: pide expresamente una pasada adicional
de código crítico y pruebas con subagentes antes de Git. Objetivo027 cerrado sobre
la candidata026 preparada: C7/Flow/delegación; contabilidad/límites; transporte
OTLP/admisión/oráculos. Tres frentes disjuntos en paralelo, una pasada solicitada,
sin cadena posterior de re-review. Pruebas offline/aisladas, sin nuevos paid/cloud.
Preservar026/evidencia aceptada y WIP;1P1/4P2 integrados con SHA exacto:
C7 multirronda8/8+restore previo sin replay; subtotal sparse5+25;
tres fronteras OTLP. No atribuir nuevos hallazgos a todas las olas anteriores.
Detalle [CRITICAL-REVIEW](CRITICAL-REVIEW.md); diagnóstico14s retirado.

Mandato posterior2026-10-02: el usuario autoriza adaptar el consumidor hermano
`exAgentTest/chat_app` y añadir entre10 y20 casos E2E con OpenRouter real usando
su credencial existente. Objetivo028 cerrado: consumidor ReqLLM stock y18 escenarios
aceptados externamente, con oráculos de estado/efectos y admisión finita.
La suite habitual sigue offline; no reutilizar el ledger G2 cerrado ni presentar
dobles TestModel como pruebas reales. WIP y `.env` del consumidor se preservan;
credenciales fuera de recibos, argumentos y Git. Ola01 13/18 y cinco repeticiones
causales, más diagnóstico06 invalid_tool_arguments/efectos0.06 finalsecuencial;
17 consulta terminal administrativa y rechazo de Layer0 resumecompleted sin IO.
13–15 descubrieron un defecto propio de Frame: permitir prefijoSystem antes del
único User/input exacto;3regresiones strict/45adyacentes y los tres casos reales
pasan, sin formato nuevo. Total40requests/USD1.00 reserva de60/USD1.50, factura
null; siete grupos cerrados, fuente por ola inmutable. Los18verdes suman36requests/
13efectos. Driverreview única3P2 corregidos/12controles, guard entre dosVMs60.
Precommit consumeractual15offline/18excl/exit0; depslistas/.envpreservado. La fase
live está cerrada; no reset/rerun de sus pases. Detalle [E2E-ACCEPTANCE](E2E-ACCEPTANCE.md).

Tooling privado y recibos: /tmp/opencode/exagent-v2-codex-t6qgpstl/.
Elixir1.20.0/OTP29.0.5 actual, consumidores también1.18.4/OTP28.0.
ROOT/_build es exclusivo del padre; agentes usan copias/builds físicos separados.
No reparación global. G2 real y POST Langfuse cerrados: ningún rerun externo nuevo.
Mandato posterior2026-10-02: usuario exige Opik igual de validado que Langfuse y
reflejar ambos como requisitos de v2. Objetivo024 cerrado: mismo A10/candidata,
transporte nativo real/API completa/UI, sin repetir Langfuse ni G2 pagado. G4
ampliado aceptado en ambos perfiles A10; candidato023/evidencia anteriores intactos.
Scope Opik Cloud ahora `tehsuso/exagent`, proyecto01a0fbf6-7f3c-7005-bfe0-77e38d2a5d41.
El usuario creó/autorizó esa cuenta exclusiva de pruebas y aportó su API key;
se guarda sólo en0600, sin cambiar `.env`/clave/histórico deakorda. Candidata025,
dos fixes causales de receta opcional (proyección y binary IPC); core/lock intactos.
Nativo/API verde en `opik-wave-w7smi_fb`, cincoPOST/33ACK, cuatroGET2786ms,
33/33 y667attrs/12usage; dos fallos anteriores500ms/1s preservados. PerfilHTTP3s,
RPC3.5s/batch5s/export20s/owner28s/Collector30s guard intacto. UI aceptada:
12casos/248attrs y siete vistas reales inspeccionadas, recibo e0a9be73…3e0f9.
Network Error/captura Orca y recortes físicos conservados como limitación;
no certificar estabilidad del navegador. La respuesta/captura del usuario confirma
cuatro logs y el agente completó los estados en la pestaña autenticada sin recargar.
Detalle y fuente sellada en [OPIK-ACCEPTANCE](OPIK-ACCEPTANCE.md). No repetir
productor/API/Langfuse por un fallo UI. Revisión024 única0P1/2P2 corregidos por
frontera29 y control de cleanup; sin re-review ni otra auditoría R9.

## Fuente y evidencia

Candidata funcional019, nominal1.3.0,152 archivos distribuidos,540 fuentes:
TAR4629a1f2d22669b5fc352dcb62b8711cf11a4a2940a0c1fa25f3e98a8611c233.
Lock33a222bfe0df7fffcd78af2d0a7bcc61c0a762255fd05f690492da6433e7f2bc.
Fuente final009 Flow:73+11 casos, review1/1 con tres findings corregidos.
Delegación001:784 casos distintos/VM4/matriz26, review1/1; rojos históricos intactos.
Seq9/delegación10/Flow11, API/root/noModel, JSON64KiB/32ramas/journal8MiB intactos.

| Gate | Resultado cualificado |
|---|---|
| G1 FULL019 | 2157 pases,28 excluidos,cero fallos;2276s,exit1 warnings propios de fixtures |
| G1 corrección causal | 136 focales exit0/cero warnings; sólo adapter público/test Registry/filtro consumer |
| G1 ExDoc | Exact029 exit0/0warnings,105HTML/2643targets/0links propios rotos; nueva guía E2E renderizada |
| G2 mínimo real | GPT-4o-mini/OpenRouter,14/14,17admisiones/3efectos; reservaUSD0.425/billingnull;0reruns |
| Consumidor real028 | 18escenarios aceptados por ola01+causales;40admisiones/USD1.00 reserva, sietegrupos cerrados; primer13/18 rojo conservado, factura null |
| G3 real | PG17.4,14fases/ACKperdido/dosVMs/FlowA8/restart/recover/backup;SHOW5s,29hijos/PGcerrados |
| G4 native/API | Pareja18+15spans,5POST/33ACK; última3GET734ms verifica33/33,667attrs/12usage/parentage/privacy |
| G4 UI | Aceptado por agente autorizado en sesión del usuario:12observaciones/248attrs,cinco capturas; estados/IDs/retries/calidad/cents/privacy |
| G4 Opik ampliado | Nativo/API33/33 y UI12casos/248attrs/siete vistas aceptados; mismos criterios que Langfuse. Fallos/plazos/limitación UI en OPIK-ACCEPTANCE |
| G5 consumidores | 8grafos×7=56PASS,0fail/skips/excl; strictREDdeps, dos runtimes; CI remoto pendiente |
| SDK/frameworks | MCP2.2.0 cinco perfiles5/5; LiveViewTest/Oban SQL6/6+crash73/recover0,cleanup |
| G6 finito | 18rows×200+2soaks200/c8+saturation64/cap32; cota lote8/observado2; TestModel,cleanup |
| Recetas016 | Typed/router/review humana y completed inerte PASS sobre019; mapper/efecto una vez |

ExDoc cambia sólo docs/metadata. lib/capability tiene una frase de moduledoc.
Root recibió driver SQL exacto da6ba58e…74e1 y Langfuse soporte11/11 hashes;
Req fixture final06 y helper opcional G2 con dos controles offline sin warnings.
No nuevo FULL ni nueva aceptación pagada. El preview anterior023 TAR
0661eef403d5089b1d7d75bea08bb56c87ccf333f48e81d187457630ec7177b1.
152distribuidos/546fuentes; frente022 sólo cuatro MD de estado de aceptación UI.
Todos los distribuidos noMD y lock byte-idénticos a022; la prueba AST90 contra019
sigue vigente para ese artefacto. G1docs023 verde. La nueva derivada025 añade dos
fixes causales de receta opcional y su aceptación Opik. Su cierre documental026
se identifica aparte; core/lock cualificados permanecen exactos y el formateo
posterior de seis archivos se verifica por AST sin repetir aceptación cloud.

Strict upstream: TOML0.7.0/WebSockex0.5.1 últimas releases, sin parche posterior.
gproc1.3.0 corrige9sitios pero grpcbox0.18.0 exige~>1.2.0; no override/fork/suppress.
020 cerrado,8GET/30.5s; no installs/compiles/paid IO. Exits rojos conservados.

Recibos y hashes: [FINAL-CANDIDATE](FINAL-CANDIDATE.md).
[EVIDENCE](EVIDENCE.md) conserva estados anteriores como historia.
El tablero único sigue en docs/development/roadmap.md; este relevo sólo ejecuta
ese estado, sin convertir prompts archivados en tareas.

## Dueños y siguiente acción

- Padre:027 integrado y028 real cerrado, incluido fix de instrucciones System
  de Frame. Sella029/ExDoc/evidencia con lock raíz intacto. Siguiente: autorización
  Git/CI remoto exacto; ninguna nueva ola pagada/cloud ni re-review.
  No repetir gates funcionales para documentación.
- delegation_owner: R9 única pasada de integración/deltas003/012/013/015/017 y
  nuevos fixtures; corregidos mediante recibos del owner, sin relectura.
  Dictamen1/1 cerrado sobre022, seisP2 corregidos/ninguno pendiente;36SHAcheck0.
 023 sólo incorpora cuatro MD con el nuevo recibo UI; sin nueva revisión.
  REPORTdaf5414f…0fc8, sin reruns/relectura de fixes ni procesos/build propios.
- mcp_sdk_harness:018/020/ExDoc019/021/022 cerrados en copias físicas propias.
- otlp_transport:015 cerrado; patch8deltas/11finales importado exacto.
  Única review0240P1/2P2 cerrada; fixes owner con controles causales29/9/717.
  Sin re-review. API no sustituye UI, factura ni retención durable.

Entrega preparada: candidate023/exagent-1.3.0.tar, evidencia histórica022
evidence.tar.gz (49miembros,SHAb220ce54…95403) y adición023 evidence-ui.tar.gz
(41miembros/1227429bytes,SHA6d21869a…093ad), cotejada tras extraer. Incluye recibo
UI a2058c08…d8f3, siete imágenes y prueba414fuentes noMD byte-idénticas a022.
Estos tres artefactos anteriores son históricos e inmutables. Entrega anterior026:
`candidate026/exagent-1.3.0.tar`, SHA860c6c15…c1017,152distribuidos/556fuentes;
frente025 sólo seis MD, todo ejecutable distribuido y lock byte-idénticos.
`candidate026/evidence-opik.tar.gz`,232miembros/3341215bytes,SHA8bda3850…dd6a0,
leídos de vuelta y cotejados, sin claves. G1docs026104HTML/2630targets/0warnings/
0links rotos y114hashes; detalles en FINAL-CANDIDATE. Entrega actual029:
TAR8dd4e80a…0c808,153distribuidos/564fuentes y lock intacto; tres cambios core
demostrados por027/028. Evidencia737miembros/SHA9c079799…8f1ec,59fuentes del
consumidor/rojos/recibos/controles y siete olas live, cotejada al leer de vuelta.
ExDoc029105HTML/2643targets/cero warnings/links propios rotos. Los relevos
CURRENT/FINAL posteriores quedan fuera del TAR. Ninguna mutación Git;
queda CI remoto exacto. AGENTS.md exige petición
expresa de commit. No anunciar
v2 completa/publicada con estos gates abiertos. No repetir G2, SQL, SDK,
frameworks, consumidores56, carga ni FULL por documentación.

Fresh traces para el navegador del usuario:
- [Flow](https://cloud.langfuse.com/project/cmujo5tsd08uiad0cqi6bw9ag/traces/2237aa029ba291aa36501dc62bb10b98)
- [Recovery](https://cloud.langfuse.com/project/cmujo5tsd08uiad0cqi6bw9ag/traces/0a56501beec20d4f91f61c85ae157f49)

Las capturas iniciales y su recibo parcial95af1724…276 se conservan. Después el
usuario preparó la sesión autenticada del host y autorizó inspección por agente;
la aceptación visual está cerrada, no repetir la pregunta ni nuevas lecturas.
[UI-ACCEPTANCE](UI-ACCEPTANCE.md) registra12observaciones/248attrs y cinco capturas.
Receipt langfuse-ui-agent-2026-10-02/ui-acceptance.json SHA
a2058c08d89b5b1d9f4036e87e9626bbe20cf8988faf47115573a830da99d8f3.
Pausa/resume y IDs, quality/source/cents, retries y privacy verificados;14/20tokens
son TestModel sintético. Cero nuevos Producer/SDK/Collector/Model o REST directo;
las lecturas UI sí acceden al backend. Pestaña del usuario abierta; sin extraer
cookies/credenciales. Errores iniciales de captura Orca conservados, no de ExAgent.
Esta autorización es para UI, no Git.023 añadió su estado público;022 y su
archivo de evidencia congelados permanecen intactos. G1docs023:
outputsreport SHAb706252c…6e261; manifest128/128SHA9da8bf86…a4cdd.
