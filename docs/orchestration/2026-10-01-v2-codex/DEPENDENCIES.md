# Dependencias — revisión autorizada, 2026-10-03

Base Git b80562b02efe627be67a37fbe71544732b6aff1a; rama codex/v2-candidate-029.
El usuario solicita revisar todos los paquetes antes de publicar. Commit/push/PR
autorizados previamente; sin bump, tag, merge, Hex ni cambios globales.
La [tabla vigente](../../development/dependencies.md) enumera versiones y fuentes.

## Delta y cobertura

API oficial Hex y `mix hex.outdated --all`:43 paquetes raíz,15 declarados y28
transitivos. Doce versiones posteriores; once upgrades oficiales compatibles:
Finch0.24/Mint1.11/HPAX1.1, JSV0.25/Texture2, Ecto3.14.2, Zoi0.18.11,
exporter test1.11, ExDoc0.40.4/Earmark1.4.46/Makeup1.2.2.
42 quedan en la última estable consultada. Gproc1.2 permanece porque grpcbox0.18
exige~>1.2.0 y excluye1.3. No override, fork, prerelease ni parser privado.
Outdated exit1 sólo por esa diferencia; hex.audit exit0, sin paquetes retirados
ni advisories detectados en la consulta. No es una auditoría universal.

Los mínimos HTTP/schema también cambian en mix.exs, protegiendo consumidores
sin lock de entrada. No cambian APIs/eventos/snapshots/guards de ExAgent.
Las dos fuentes lib editadas sólo ajustan comentarios JSV. Su vocabulario público
de codepoints/igualdad numérica y sus guards siguen necesarios y pasan regresiones.
El exporter1.11 corrige bool_value; probes de span/resource y escenarios ahora
exigen booleanos protobuf reales. Partial_success/HTTP ownership conservan límites.

Nueve dependencias declaradas de frameworks también se contrastan con Hex: sus
pins/rangos permiten la última estable, sin cambio de fixture ni app original.
No se presenta esa consulta como una nueva ejecución SDK/Phoenix/Oban.

## Recibos externos y focales

| Gate | Resultado y frontera |
|---|---|
| Schema/output/MCP HTTP |76 pases, exit0; rechazos/ref/callbacks/dialecto y fronteras públicas |
| OTLP nativo |7 pases, exit0; bool_value, partial_success y lifecycle/cleanup |
| G2 ola inicial |12 pases /1 fallo /1 no ejecutado;16 admisiones /3 efectos |
| G2 control causal |Length sync/stream pasan;2 admisiones /0 efectos;4.55s |
| G2 acumulado |14 escenarios cubiertos;18 admisiones /3 efectos /USD0.45 reservado, sin factura observada |
| PostgreSQL17.4 |14 fases pasan y cleanup true,79.12s; lostACK/two-resumers/fresh VM/Flow/recovery/backup |
| Consumidores limpios |8 grafos×7 contratos=56 pases /0 fallos/exclusiones/skips;46 comandos únicos exit0 |
| Strict dependencies |Runners exit1 sólo por warnings stock TOML/WebSockex/gproc; sin warnings de compilación ExAgent |
| FULL1.20/OTP29 |2.177 pases /0 fallos /28 exclusiones;2.007,4s |
| FULL1.18/OTP28 |2.177 pases /0 fallos /28 exclusiones;2.024,7s; runner exit0,total2.059,95s |
| bin/check |Nueve fases exit0,total2.073,45s; compile estricto/probes/FULL/docs/enlaces/TAR/aislamiento |

G2 conserva una negativa corta del proveedor con finish_reason stop al pedir
los números1–1000. No consigue el estímulo length. El control cambia sólo el
prompt a un párrafo benigno largo, conservando16 output tokens, límites, guards,
herramientas y oráculo incomplete_response. Los dos controles observan length
real y cero efectos; stream conserva un único terminal. La primera ola roja
queda intacta; no se afirma una nueva ola14/14 ni se repiten los doce aceptados.
El prompt causal se incorpora al harness raíz. Total18 requests/USD0.45 dentro
del cap original20/USD0.50; reserva no equivale a factura.

SQL tiene28 comandos:27 exit0 y el crash negativo de lost COMMIT ACK exit73,
todos coinciden con sus expected_exit. Reporte /tmp/exagent-pg-vm70ksa1/report.json,
SHA256 `5d13612f9d89618fdd167949f7f29669bd8e439a9b0ae032c7962a53537a93d0`.
El primer wrapper invocó su propia copia como proyecto y salió2 en preflight;
se conserva y el driver raíz ejecuta luego la copia física independiente.

Los primeros runners de consumidores salen antes de instalar/compilar por omitir
HOME en el allowlist privado. El wrapper corregido preserva el HOME existente;
los ocho grafos posteriores usan nuevos directorios, tooling/deps/build físicos.
Los logs anteriores se conservan. Los contratos pasan; los runners posteriores
siguen exit1 por diagnóstico estricto: TOML15 por grafo1.18; TOML19/WebSockex19
por grafo1.20, más gproc9 en exporter1.20. Sin supresión ni política relajada.

TAR de cualificación:168 archivos,
SHA256 `0f3a725bfd0e4373c5c8ccb4abdb43dbe52bb87c686d84dffa7b83f4d29c2ed6`.
Los ocho locks resuelven ReqLLM1.26/Finch0.24/Mint1.11/HPAX1.1/JSV0.25/
Ecto3.14.2/Texture2/Zoi0.18.11. Exporter1.11 y gproc1.2 sólo en su grafo.
Runners115.52s(1.18) y143.26s(1.20). Recibos package-matrix/package-versions.

## Identidad y límites

Artefactos privados: `.exagent-local/dependencies20261003/`. Las dos suites usan
el mismo nuevo lock, con copia física de fuentes/deps para el runtime mínimo.
El prompt G2 posterior no es parte del código runtime ni se carga en FULL offline;
tiene su control real separado. Las actualizaciones de resultados/documentación
no renombraron el TAR de cualificación como el TAR final.

ExDoc0.40.4 final exit0, sin warnings. Readback:117HTML/5.188targets,
115Markdown(incluido llms)/836targets y115XHTML EPUB/2.865targets; cero
enlaces/anchors/recursos locales rotos. Navegador nuevo: tres vistas desktop
claro/oscuro y móvil390, sin overflow de página, tres navegaciones con anchor
Swup pasan. Capturas inspeccionadas. El primer probe buscó el sidebar antes de
su render asíncrono y luego cerrado en móvil; el harness privado espera render
y abre el menú móvil antes del click. No cambió el sitio para corregir el probe.
No se reetiquetan las36vistas históricas como pruebas nuevas.

TAR final SHA256:
`2b725ef5a9abd97b047d462952967b116b9ef47d3126d3126fd2ffb30b01ad40`.
168 archivos exactos al checkout; metadata y91fuentes lib/mix idénticas al TAR
de los consumidores. Sólo seis documentos difieren: design/changelog/dependencies/
otlp-transport/roadmap/status. No lock, tests, historial archivado ni ficheros
privados en el paquete. El readback privado final-tar-source.json confirma identidad
y límites; los mínimos ya se probaron en los ocho grafos sin lock de entrada.
No rerun de FULL/paid/consumidores por registrar estos resultados documentales.

Lock SHA256 `2637e0965ebdb015e04d505757bf0de5649affc35670ee77aa11745ecbbcdaeb`.
Las fuentes congeladas lib/config/mix/lock siguen exactas; sólo dos archivos de
tests difieren después del freeze: entrada G2 y su README. Harness G2 antes:
`30cded711be2745476abfb893ad2f9226723a01b00540dfda403e847fa75b723`;
después `26b2a783d89bc83e954bb6c3d864a73b8945a0915b0e2430ee8ca129699997a7`.
La corrección del prompt tiene los controles reales separados descritos arriba.

Rutina local: `.exagent-local/checks/20261003T093933Z-813369/`; exits.txt conserva
las nueve fases0. Suite mínima: minimum-suite/test.log/summary.term. Sus15 avisos
de compile son stock TOML; el gate propio compile y FULL salen0, sin compiler
warnings ExAgent. Las28 exclusiones son22 provider y6SQL, no pases ni timeouts.

Se conserva el recibo [ReqLLM1.26 anterior](REQ-LLM126.md), incluido FULL118 rojo.
La nueva revisión tiene su propia identidad. El E2E de la aplicación hermana y
la aceptación cloud/API/UI Langfuse/Opik conservan sus fechas y fuentes anteriores;
no hay una nueva ola app/cloud ni una ampliación de perfiles soportados.
SDK/API/bridge ExAgent no cambian. Exporter booleanos tiene nueva prueba nativa;
eso no demuestra durabilidad remota ni corrige todos sus límites de transporte.
G5 strict sigue abierto. No se activa nueva revisión independiente ni publicación.
