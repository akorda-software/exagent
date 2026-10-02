# Candidata v2 — evidencia y límites, 2026-10-02

Implementación autorizada, HEAD7f25b336924d97baf1d4aa18898ec8db32385940 y WIP
preservado; versión nominal1.3.0. Este registro acredita los perfiles probados.
G4 Langfuse y Opik están aceptados por transporte/API/UI en el perfil A10.
CI remoto exacto sigue pendiente. El usuario autoriza el2026-10-02 commit/push
en rama nueva y PR borrador para ejecutarlo; `codex/v2-candidate-029` es la rama
activa, commit inicial `b709d571240cc75b6044d4f53ac34ce795347a3c` y PR1 borrador.
Publicación y bump siguen pendientes; la pipeline Hex será posterior.
El tablero único de trabajo está en docs/development/roadmap.md.

## Preview actual029: revisión crítica y consumidor real

CI030 inicial sobre ese commit: empaquetado y harness verdes; suite1.18 roja por
formato dependiente de versión y Macro.escape de Regex compilada en un fixture.
La corrección causal prepara formato canónico1.20 y construcción runtime del
fixture; el core distribuido no cambia. Suite1.20 aún en curso; consumidores
remotos56contratos/0fallos/0excl y comandos exit0, pero jobs estrictos rojos por
warnings stock TOML/WebSockex y gproc. No presentar CI completa verde.
Run [37008908156](https://github.com/akorda-software/exagent/actions/runs/37008908156).
El TAR remoto tiene SHA d9a90625965001daef4a1fa52eb89174769401f53a31b22a65cf2911d573478f
y las153fuentes029 exactas; el orden de empaquetado difiere.
Correcciones focales offline:178/178 InputRestore/OutputRetryRestore en cada
runtime, más4/4 Stream (26excluidos por selección) en cada uno, exit0 strict.
La compilación estática118 de165tests descubre seis warnings propios de cuatro
layouts constantes; se construyen desde tags/contexto runtime. El nuevo push
sustituirá la ejecución anterior; no contar una suite cancelada como pase.

Artefacto local: `/tmp/opencode/exagent-v2-codex-t6qgpstl/candidate029/exagent-1.3.0.tar`.
SHA256 `8dd4e80a24ae01bea4e62051cbc15c30113c4bb34142b36623e3cb9bd070c808`.
CHECKSUM interno `07dce1b2f572b595b7f833b4e25afe7262f41ccfa9f48df16ba81b3327c47957`.
153distribuidos, manifest `f38445beeff85a540704fc7b5405f1603ade2834586b0bba9e57649386ee79b0`;
564fuentes, manifest `28e028096205ca06afa404fa2ba88e65345feb8a6f58540b972f1df9c557f862`.
Identidad `c0763591affce0fdc048ce9be2dc7385ec0e828a77a0ddef63f0db233ad19eda`.
Lock raíz intacto `33a222bfe0df7fffcd78af2d0a7bcc61c0a762255fd05f690492da6433e7f2bc`.
Nominal1.3.0; sin bump/publicación. Root/copia/TAR cotejados antes del freeze;
CURRENT/FINAL reciben este relevo posterior y permanecen fuera del TAR.

Frente026 cambian tres fuentes core: Scope subtotal sparse, Transition aprobación
multirronda y Frame instrucciones System en hojas; mix.exs sólo añade el extra
ExDoc de E2E. Resto del delta: docs/tests/arnés. Las primeras dos correcciones
provienen de la pasada027 expresamente solicitada:1P1/4P2, tres scopes disjuntos,
sin re-review; contabilidad30focales y C7matriz8/restore viejo sin replay. Tres
P2 del arnés OTLP llevan pruebas offline, sin nueva ola cloud. La tercera
corrección procede de los E2E028, con3regresiones strict y45adyacentes verdes.
Todos los rojos históricos, incluidos los fixtures nuevos corregidos, se conservan.

[CRITICAL-REVIEW](CRITICAL-REVIEW.md) y [E2E-ACCEPTANCE](E2E-ACCEPTANCE.md) detallan
evidencia/limitaciones.18escenarios de aplicación reales GPT-4o-mini/OpenRouter
aceptados mediante ola inicial13/18 y cinco repeticiones causales; diagnóstico06
adicional rojo.40admisiones/USD1.00 reserva de60/USD1.50, factura null y siete
grupos cerrados. Los18verdes suman36requests/13efectos independientes. No es un
único18/18 inicial;13pases se reutilizan por caminos no afectados, con fuentes
por ola. Lote múltiple06 sin aceptar/finalsecuencial;17 consulta completed por
API administrativa, sin ampliar Layer0 resume. Consumerprecommit15offline/18excl/
exit0; modelos/.env preservados, dependencias oficiales listas.

G1docs029 exit0/cero warnings/3.373s,105HTML/2643targets/cero enlaces propios
rotos; guía nueva renderizada. No nuevas llamadas a Langfuse/Opik, SQL, FULL,
SDK ni matriz56. Sus recibos se reutilizan sólo con el alcance no afectado;026
permanece inmutable y no recibe aceptación retroactiva del nuevo código.

Adición de evidencia `candidate029/evidence-critical-e2e.tar.gz`:
737miembros/3914351bytes, SHA
`9c079799c9ecd690de4140b0e8b43d2e06bfe1ad730f13ab0975dccce728f1ec`.
Índice `6670c33fc1776fdafb7e07cfdffa0151f9c8c40ee23c95bf59e99e2808264008`;
recibo `57cd402384f3235f18cb800b63d539870e20d6113c666b653e8d12673475de61`.
Todos los miembros cotejados al leer de vuelta, clave existente ausente en todos
los payloads. Incluye564fuentes del paquete,59del consumidor, artefacto nominal,
recibos/rojos/controles y source/cases/admisiones/logs redactados de siete olas.
Manifest consumidor `c8422278bf31a7421ce529a569c857f35f38f58c27f85a551c51a0e9358f7516`.
Selección curada; manifests pueden referenciar evidencia privada no incluida.

Lib de05–07 exacta a029;01–04 difieren sólo en Frame. Su delta es el certificado
de hojas estructurales, no usado por los13pases originales/06/17PlainC7. Controles
portados del arnés y SourceScope/Transition coinciden con las entregas selladas.
Formato focal y diff check pasan. No commit/push/tag/bump/Hex ni tooling global.
CI remota sobre revisión exacta necesita autorización Git; diagnósticos strict
stock conservados. No anunciar v2 publicada ni todos los gates completos.

## Preview anterior026 y paridad Opik

Artefacto local: `/tmp/opencode/exagent-v2-codex-t6qgpstl/candidate026/exagent-1.3.0.tar`.
SHA256 `860c6c15fe1f28fdf332b69981a071f0b59daec360b2633caf00b427bd3c1017`.
CHECKSUM interno `4e2ac1f8c09fb04b0346b04ff9b2d5e8abc9fec517de502a8b8eb15fa824f6ce`.
Distribución152, manifest `c9486f1deb1e32ebb83f960ba5f277eb4293062de213b282a4dfeff5953d7b7d`;
fuente física556, manifest `73d13eb0dc622e77a953f29da5d100ed3171af7c94b6f5f26a955c7bfb941d8d`.
Identidad SHA `34a8ce9ce570a5c5d53c8a5cec5e3199f9f31f491498da731ef68fd366c5464f`.
Frente025 sólo cambian seis MD distribuidos de aceptación; todos los bytes
ejecutables distribuidos y lock permanecen exactos. Los relevos CURRENT/FINAL
se actualizan después del freeze y quedan fuera del TAR. La fuente congelada
conserva sus versiones de ese momento, no atribuye los recibos posteriores al
texto anterior.

Candidata025 introdujo dos fixes causales de receta opcional frente023: hook
de proyección del mapa SDK público y IO binario/Latin1 en packet4. Core/lock
conservan la cualificación común. El arnés Opik y sus plazos tienen identidad
propia; no se atribuyen al dictamen previo R9. Única review0240P1/2P2, corregidos
por el dueño con controles causales;717oráculos/29fronteras/9packet4. La derivada
verifica AST/formato de seis archivos Elixir y13Python parseados/byte-idénticos
al arnés sellado04; recibo `opik-derivative-verification.json` SHA
`f55eb4acc570406e5c9935ebb8bc208dfddcbc1c8e79980a6b08e6faf6e7eb55`.
Sin nueva review, FULL, G2 pagado, SQL, SDK, frameworks o consumidores.

[OPIK-ACCEPTANCE](OPIK-ACCEPTANCE.md) registra cincoPOST/33ACK y API33/33,
667atributos/12modelos, UI12casos/248atributos y siete vistas reales inspeccionadas.
Recibo UI SHA `e0a9be73d2553b9164cd7a6163673bcc45e0e8e28c565e7fc305bda030e3e0f9`.
Los mismos criterios que Langfuse, con sus IDs/tipos/plazos comprobados y sus
fallos de navegación/captura conservados. La UI diagnóstica posterior también
confirma ocho spans en la segunda ola fallida, sin aceptar esa ola completa;
recibo `ui/partial-wave/receipt.json` SHA
`cb1e4b6c74c38c4e4530198c68e5be58d98efaaad9f3c7e4f541db5000e8e41f`.

G1docs026 real: exit0,0warnings,1.920s,104HTML/2630targets/cero enlaces propios
rotos.114archivos HTML/assets con hashes cotejados. Recibo outputsreport SHA
`1a526d2cb2ebf9c0894825a180c99d3a9314e3dd0df3b585d74c436b4837e35c`;
manifest SHA `4b9967e093cced4668f9d2be8c36ab2f63f9ea3e92438b793db0fd763fe788de`.

Adición `candidate026/evidence-opik.tar.gz`:232miembros/3341215bytes, SHA
`8bda3850f1d33c36dfb66aa6ab459d79576a901dab3ecead55a257010e1dd6a0`.
Índice SHA `1021f720a6df3e8fb727b0d6481ebc9bed24ee289e72d8f0d35bdfbeb94cf835`.
Todos los miembros leídos de vuelta y cotejados; sin claves/cookies/tokens ni
cuerpos API brutos. Incluye fuente pública fijada, arnés/review, recibos nativos/
API/controles, fallos preservados y UI/DOM/PNG/PDF reales. Selección curada, no
copia de deps/builds privados; sus manifests pueden referenciar archivos externos
a esta adición. Base022 y adición023 permanecen inmutables.

La entrega local está preparada. CI remoto exacto, diagnósticos estrictos rojos
stock y autorización Git/publicación siguen abiertos. No bump/tag/Hex ni cambios
a consumidores. No anunciar v2 completa/publicada con esos pendientes.

## Preview anterior023 y aceptación UI Langfuse

Artefacto local: /tmp/opencode/exagent-v2-codex-t6qgpstl/candidate023/exagent-1.3.0.tar.
SHA256:0661eef403d5089b1d7d75bea08bb56c87ccf333f48e81d187457630ec7177b1.
CHECKSUM interno:1c8ad57c5fc6f9935f3d8bcf7d6e3a70efc16374782ee536fb85e7637142c6fb.
Distribución152, manifest0886b4fa81725553434c0b8d9157801078fbbd339d12e106a8378d6b117a0c5b;
fuente física546, manifest0f24e3d1690b4aae9f58a9a4b258381b64e5963d47e270437c23576f9e2162ff.
Identidad d044a816aff46b60fcc1e560ada5cf98e04611ebfeaac83978b7b3d4def9b39d.
qualification-delta.json SHA
b2cea32a17c9b8a1d62980d198db11264a6d856d97fef40bd7442f6eac5135bb.
Sólo cambian cuatro MD distribuidos frente022: status/changelog/roadmap/backend
evaluation. Todos los archivos distribuidos noMD y lock son byte-idénticos;
reutilizan la cualificación funcional019 y la prueba de equivalencia022. No nuevo
FULL, proveedor pagado, SQL, SDK, frameworks, carga, API ni Producer/Collector.
Root/paquete/copia física coinciden en152archivos; no build copiado ni publicación.

G1docs023 real exit0/0warnings/1.925s,104HTML/2626targets/cero enlaces propios
rotos; las cuatro páginas renderizan el nuevo estado UI. Recibo outputsreport
SHA b706252ce9622df10add6b7a7b64d445bc06485b48936fd305050a998936e261;
manifest128/128 SHA9da8bf868b44aafc37aea832993c4cd3eb94f68f02a6f9bc2605f17985aa4cdd.
Log ExDoc5af95d374bdec6d1cb4c9bdb646cb395bfe7810d49f596a23a0fd89978c0fdbe.
La revisión independiente únicaR9 sobre022 se conserva, sin nueva review por
documentar la aceptación UI. Los relevos de este directorio se actualizan después
del freeze; no están en el TAR.

[UI-ACCEPTANCE](UI-ACCEPTANCE.md) registra la inspección autorizada de la sesión
autenticada del usuario:12observaciones/248atributos renderizados y cinco capturas
inspeccionadas. G4 A10 aceptado, receipt SHA
a2058c08d89b5b1d9f4036e87e9626bbe20cf8988faf47115573a830da99d8f3.
El archivo de evidencia022 permanece congelado como evidencia anterior;
este recibo UI y su documentación se conservan como adición separada.

Adición local candidate023/evidence-ui.tar.gz:41miembros/1227429bytes, SHA
6d21869a83c29f63e6a7a2e03995cd4ada8df5be917990fe8a26892f417093ad.
Índice SHA8519d4ef0eb90876afd8ea595e70c14225e14b8d5601f58f440df5ef9aa3efd9;
todos los miembros extraídos y cotejados. Incluye siete imágenes sin modificar,
recibos UI/DOM y errores de captura preservados, identidad/delta del paquete,
ExDoc y registro UI. support-equivalence.json prueba414fuentes noMD byte-idénticas
entre022/023/Root, incluyendo tests/config/CI, además del paquete; sin nuevo
runtime test. El índice relaciona la base022 congelada; los manifests referencian
otros artefactos fuera de esta selección. Los relevos CURRENT/FINAL se actualizan
después del freeze y no forman parte de esta adición.

## Preview anterior022

Artefacto local: /tmp/opencode/exagent-v2-codex-t6qgpstl/candidate022/exagent-1.3.0.tar.
SHA256:d89a1434c3909a95d7d4395b9a5d6db41543c6c99b720ccb37794acb11d9907b.
CHECKSUM interno:e78068880eb7dfd57da562e8d29876fe8d2935472e29d268bc8cd75cf0854e28.
Distribución152, manifest6c44690180e7532ae1bd5f4aa87fb80128025f9e5e6266c5b3735a8c4639b54c;
fuente física545, manifest3c0890b37704a4f5b5a382c86091ea74cebe34c5e40a75665dfa40537693aaba.
Identidadcfca8b15539bdbba01b7124bbc214fcf32d86f504f3680e844836a15c94cf4ad.
qualification-delta.json SHA2700d5594d0de62bba84af2bbf45dba3f073ca3cb2c2c0607451471631b4c37e:
quince rutas distribuidas posteriores a019, sólo docs/Mixmetadata/Capabilitydoc.
Frente021 sólo cambian dos MD para distinguir cota lote8 de máximo observado2.
Lib, ejemplos, deps/app y lock conservan la evidencia funcional de019;152archivos
del paquete coinciden exactamente con Root y copia física. Los relevos/recibos
de este directorio, fuera del TAR, se actualizan después del freeze.

G1docs022: ExDoc --warnings-as-errors exit0,1.973s,0warnings; auditexit0,
104HTML/2626targets locales/cero rotos. Se comprobaron131artefactos del manifest
con hashes exactos; docs021130artefactos e históricos019 permanecen intactos.
docs022/REPORT.md SHA28563b3fec60cfa4acf95003f8bfa6465cbca76807b7150f7dd472cd12a5d66a;
outputsreport.json SHAeeedd32b3c2c97f8f4daa966612ed4ab235b64148764b7a54a9812db4915dc64;
manifest SHA b6c026ff1bfc94df2b440e48a724ebab70fde99bcb8f44aa24b15845ea7f1e72.
Build caliente con tooling literal privado; no nuevo runtime qualification,
red/proveedor/backend ni writes globales. Se conservan40warnings upstream del
coldbuild inicial, URLs externas/source_ref sin certificar y G5strictRED.

## Identidad de cualificación funcional

Todos los perfiles comunes siguientes usan candidata019:

- TAR SHA256:4629a1f2d22669b5fc352dcb62b8711cf11a4a2940a0c1fa25f3e98a8611c233.
- CHECKSUM interno Hex:3303e5b9fad5ae30337c5aa1a6af77902527b46a1b347a23baad193e6486ba5a.
-152 archivos distribuidos, manifest655306629ac5ba5a661cb3b81ba7397a2fdc0d8cbe633543ad41be3c56728952.
-540 fuentes físicas, manifest1eac93c7f44d444448ee669f436bb5a935b7852ae32a626b88fac2904d830437.
- Lock raíz33a222bfe0df7fffcd78af2d0a7bcc61c0a762255fd05f690492da6433e7f2bc.

Artefactos originales bajo /tmp/opencode/exagent-v2-codex-t6qgpstl/.
Consumer exportador015 usa su lock independiente4f7947774c597783b5372049f32a7afdbc32cc0cf1330c5368662a8d303f2fd3.
El parche oficial Mint raíz1.10.2/floor1.10.2+ y ReqLLM1.24 stock están en019.
Los consumidores de resolución libre eligieron Mint1.11.0; no se equiparan locks.

## Resultados y recibos

| Perfil | Evidencia observada | Recibo relativo al directorio temporal |
|---|---|---|
| G1 FULL | 2157pases/28excluidos,0fallos,2276s; exit1por warnings-as-errors | candidate019/full-current01.json |
| Corrección fixtures | 136pases,exit0,30.509s,0warnings; fuente antes/después igual | candidate019/req-fixture-final06.json |
| G2 real mínimo | GPT-4o-mini/OpenRouter,14/14casos,17admisiones,3efectos | candidate019/g2-live01/summary.json |
| G3 real | PG17.4,14fases,29hijos/PGcerrados, SHOWtimeout5s | /tmp/exagent-pg-epesxtjc/report.json |
| G4 API | 33/33filas,667attrs,12usage;3GET734ms,0POST/replay | langfuse015/langfuse-read-wave-rj2274f7/receipt.json |
| G5 grafos | 8×7=56contratos PASS,0skip/excl; strict8REDdeps | g5-018/REPORT.md |
| MCP SDK | 5/5perfiles,mcp2.2.0,38IDs/10efectos,cleanup | candidate019/exagent-mcp-sdk-un5pugyz/report.json |
| Frameworks | LiveViewTest/Oban SQL6/6+crash73/recover0,1request/1efecto | g5-018/framework/framework12-hvqpo630/report.json |
| G6 finito | 18rows×200+2soaks200/c8+saturation64/cap32; cota lote8/observado2 | candidate019/load-current01.json |
| Recetas016 | typed/router/review humana/completed inerte; mapper/efecto1 | candidate019/recipes-current01.json |
| ExDoc inicial corregido | 104HTML/2620targets/0enlaces propios rotos; exit0 | docs019/outputsreport.json |

SHA256 de esos recibos, en el mismo orden:

```text
37fbe945ba384f5061a3c392b85fe3c63485ca5d288f72769ad55d0616ecccb6 FULL
a3d0cb283d5761014b05fc70021e495a721c80205d972e67ff99337b9452450e fixtures
525b4d711daba406e8b03160d5a1d7a17d779a556ddcc4354b9082d3df3f979d G2
3ad0613e403d154831cc89c589655e65d94f1831007eda553924c4916cc5bfd8 G3
4fb95d1aa080ede9578fd0c6150f0f9756bcc9a1ba3d77aebaa9d07ab386c825 G4
6505474cce2cfe7e3a6fd6eeb1dc05362ed5afc2a46318cfd12654a796f21bd4 G5
d382d944e3b8183f7e5542f11951bbed2b225d92f83089f297ab1f48a7a89c7c SDK
d9c8337b8922b81b7d95f07c171e6c323d4c3bd0f97064c413278c6ec71c2cfc frameworks
a2f63d9ba4a2c067c42ae2cb0c87f36ab8558927f2bc57521e9c76e0568cef49 G6
817275135faa11ef892c870ce7e9e0aed9315aa2d20bfc7cb92ae13e2ef76aec recipes
a04b6491649aa29307fca176cdf682e7558dd40a79598b1416fe5848e80c390f ExDoc
```

## Correcciones posteriores a019

Producción sólo cambia una frase de moduledoc en Capability. Mix añade el extra
execution-flow y el filtro de descubrimiento de la app fixture separada. Docs
corrigen enlaces/anclas y actualizan estado. El nuevo preview mantiene funciones,
configuración runtime, ejemplos, constraints y lock: la comparación AST/identidad
se conserva con el preview. No se afirma que la suite histórica ejecutó su TAR.

Comparación final:90 archivos lib con AST igual ignorando docattrs; Mix igual
salvo docs y filtro de la app fixture, lock byte-idéntico. Prueba
candidate021/root-runtime-ast02.log SHA
25f3c41e5e8e39318b7865a761c3d299392d9cd32f1c68ef2cff421841d1a692.
Compile forzado del proyecto exit0/cero warnings; formato global/diffcheck0 y
AST Python verde. candidate021/root-check02.json SHA
23b6eefc0d4d3caccacc3174a38de82b8578772d2009b4db515b913d3a0b42f6
reusa compile01 con127archivos de fuentes/metadata de compilación cotejados
byte-idénticos. El rojo format01
detectó sólo sangría del productor Langfuse; corregida por apply_patch.

Soporte fuera del TAR: adapter módulo Req con callbacks ligados al dueño,
Registry/Child slots y resolución acotada del worker buffered stock; tests
transfer/allow y limpieza observada. Driver SQL importa exacto
da6ba58eb696635e7fa52a8c05570cfab2f86cf41baedd9858eea9ebae0074e1.
Driver Langfuse final importado11/11 exactos, ocho deltas;
langfuse015/delivery015-r7hyjlai/root-imported.json SHA
40e0f071db66c9c44a354cc4d59497d9a3b9627a1e6858499777dcdde66a0405.
Entry G2 corrige carga condicional de su helper: dos ramas offline pasan con
cero warnings, dos rechazos de reserva previa permanecen. Receipt
candidate019/g2-entry-load-order-final.json SHA
25fff5a3ad681637527e82514f77e39f5aae93fdc455a8ec3fa95509991739ad.
No rerun pagado ni nuevas cualificaciones por esos controles.

El productor015 importado se formateó después: SHA final Root
8f1b0e0faf4370f09b43f4fc00f4a5eae6bdb4babc491f1154f4d86c880a0d98,
con AST idéntico al ejecutado def14dff…fd970; la misma prueba final lo confirma.
El recibo de importación11/11 describe el instante previo a ese formato.

La pasada independiente R9 cubre integración/deltas nuevos, con seis P2 de
harness/oráculos corregidos por recibos del dueño y ninguno concreto pendiente.
Revisión1/1 cerrada sobre022, sin re-review de esos fixes, Core009 propio ni
unidades ya revisadas. r9-review/REPORT.md SHA
daf5414fc7cd9921865bdad1522d911cd6b35c88a3d8bbb4c8d5512355710fc8;
manifest36/36 exactos SHA
ddd34cf79d65f90207dab1b4578607d2742b1a502a0bcbcb0c84482918b173b0.
El dictamen conserva UI/CI remoto pendientes, FULLestricto y G5diagnósticos RED.

## Límites que conservan los recibos

G1 FULLestricto rojo queda intacto: una advertencia de testfilters y155de adapter
función Req0.7.4. Los136focales se solapan; no se suman como136casos nuevos.
G5 warnings oficiales: TOML15(OTP28),TOML19+WebSockex19(OTP29),gproc9 adicionales
en exporter29. Ninguno atribuido a ExAgent. Diagnóstico020 confirma últimas
releases TOML0.7.0/WebSockex0.5.1; gproc1.3.0 corrige nueve sitios pero
grpcbox0.18.0 sólo admite~>1.2.0. No suppress, fork ni update para forzar verde.
dependency-warnings020/REPORT.md SHA
d78f3623a3dadef624c7a3229bdb55a9739183fbdbef4a1cbd74c6653bd589e2.

G2: una ola concurrency1/retries0; admisión20requests/USD0.50, reservaUSD0.425,
factura null. Otros modelos/providers/modalidades sin aceptación por catálogo.
G3: backup sólo de su DB principal, sin RLS/HA/SERIALIZABLE/hostloss. Dos logs
restart crecieron con stdout del daemon;26logs enteros coinciden y dos prefijos
de567bytes conservan los hashes de comando. Sello final separado, sin editar
el recibo original.

G4: seis escenas A10 en una pareja18+15spans,12requests/6calls lógicas/4efectos;
cinco POST y33ACK, readerfinal3GET/12s/limit32/cap512KiB. Los siete spans tool
incluyen pausa/resume del mismo call. Metadata v4 de paths literales y prioridad
gen_ai.tool.name derivadas de fuente oficial; ninguna reparación de datos nativos.
Default una traza rechazó79,919ETF>64KiB; pareja expresamente admitida mantiene
portraza32spans/64KiB, chunks8/concurrency1/retries0. ACK/API no prueban UI,
retención durable ni factura. Todas las VMs/Collector/readers propios cerraron.
Rojos de consulta/proyección/name y perfil original quedan conservados.

Frameworks no certifican navegadorJS/WebSocket/HA/throughput de producción.
MCP no añade OAuth/TLS/reconnect/cancel/chaos ni protocolo2026. G6 usa TestModel,
muestreo finito y coejecución con FULL; no SLO real, fuga a largo plazo o RAM dura
upstream predecode. Fuente/excluidos/errores/cleanup se conservan por perfil.
ExDoc no verifica606URLs externas/source_ref nominalv1.3.0; sus links de código
main no certifican publicación de este WIP.

## Aceptación visual y pendiente remoto

Trazas del perfil aceptado, inspeccionadas en la sesión preparada por el usuario:

- [Flow](https://cloud.langfuse.com/project/cmujo5tsd08uiad0cqi6bw9ag/traces/2237aa029ba291aa36501dc62bb10b98).
- [Recovery](https://cloud.langfuse.com/project/cmujo5tsd08uiad0cqi6bw9ag/traces/0a56501beec20d4f91f61c85ae157f49).

El usuario aportó capturas de ambos IDs el 2026-10-02 desde su navegador.
Se observa el árbol esperado de Flow, tres errores deliberados de Recovery con
retries, resúmenes14/20tokens y Preview Input null / Output undefined. El perfil
content:false excluye prompts/respuestas/argumentos/resultados: ese Preview no
indica fallo funcional. Los tokens de esta pareja son sintéticos de TestModel,
no factura de proveedor. Las capturas no muestran Attributes: siguen pendientes
paused/succeeded, igualdad de run_id y continuation.record_id con attempt_id
distinto entre pausa/resume, y accesibilidad de calidad/procedencia/unidades.
Estas propiedades ya tienen evidencia API, que no sustituye su renderizado UI.

Recibo adicional fuera del paquete y del archivo de evidencia congelados:
langfuse-ui-user-2026-10-02/receipt.json, SHA
95af1724718633c485be71cdddfa09a0db3e167694fe8acc7b2046f6a9542276.
Copias exactas flow.png SHA
901d5d272651f4b69ad2a44f56fa69debc9f5051db82e9a57e02e297fdf124f9
y recovery.png SHA
9daa869779ac9b215993b25a6ea1b1324851bc0bce31ba52e8698fb133936f9f.
Estado parcial user_ui_tree_error_usage_privacy_observed_attributes_not_shown;
cero consultas/POST/Producer nuevos. En ese instante seguían pendientes los
Attributes; aquel recibo parcial permanece sin alterar. Después el usuario
autorizó inspección del navegador del host y se cerró la UI mediante vistas,
snapshots y cinco capturas reales: paused/succeeded, correlación y nuevo intento,
calidad/procedencia/unidades y retries verificados. Recibo final a2058c08…d8f3,
detallado arriba. Ninguna aceptación inferida sólo de API ni autorización Git.
CI remoto necesita commit/push autorizado expresamente para la revisión exacta.
El diagnóstico estricto G5 conserva exit1; no se promete CI verde con estos avisos.
Bump/tag/Hex y cambios a aplicaciones consumidoras requieren encargo propio.

Entrega de evidencia local: candidate022/evidence.tar.gz,49miembros/236230bytes,
SHA b220ce54ea9d0bee05ef30e9b839a8e74ec473720f914d02a7fd44c220b95403.
Índice SHAf7c543be796c4e14e71221382541f4045b1e30ba71fc5a033a2b6e818466a064;
48payloads cotejados tras extraer, más índice. Contiene recibos originales,
informes, identidad/delta/proof, logs seleccionados y snapshots de este relevo;
sus manifests pueden referenciar otros artefactos del run no incluidos.
La solicitud async de commit/push a main está pendiente; ninguna mutación Git.
