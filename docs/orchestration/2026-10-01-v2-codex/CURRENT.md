# ExAgent v2 — estado vigente, 2026-10-02

Implementación activa y autorizada en /home/kukapu/dev/projects/exAgent.
Rama: `codex/v2-candidate-029`. Base de los fallos CI run02: `dad90ff`.
Commit inicial: `b709d57`. [PR1 borrador](https://github.com/akorda-software/exagent/pull/1).
El usuario autorizó commit/push/PR y observación del CI; sin bump, tag,
merge ni publicación en Hex. La pipeline de publicación vendrá después.
ReqLLM oficial stock, R1.2 aceptado, C7 incluido, guards intactos.
Una revisión máxima por objetivo; sin re-review ni reruns rutinarios del padre.

## Objetivo actual: corregir causas demostradas en CI030

[Run01](https://github.com/akorda-software/exagent/actions/runs/37008908156)
sobre b709d57: paquete/harness pasan; suite118 falla al compilar Regex de fixture
y comparar layouts constantes. Suite120 cancelada por el siguiente push:
no cuenta como pase. Correcciones dad90ff: fixtures runtime, formato canónico
1.20 y harness fijado a1.20.0. Focales por runtime:178restore +4stream strict;
165testfiles118 compilados sin warnings, sin ejecutar sus bodies.

[Run02](https://github.com/akorda-software/exagent/actions/runs/37010288171)
sobre dad90ff: **failure**. Compile pasa en ambos runtimes, formato1.20 pasa,
harness y TAR pasan. Consumidores:56contratos/0fallos/0excl, comandos exit0;
strictdeps rojos por TOML/WebSockex/gproc stock. No ocultar esos diagnósticos.
Suites118/120: exit124 tras3000s,76/72fallos anteriores al corte, sin totales.
54fallos por rutas /tmp/opencode ausentes y un MIX_BUILD_PATH obligatorio
en cada runtime; otros requieren diagnóstico causal, no aumento de timeout.

Correcciones causales probadas, fuentes/builds físicos separados:
- ci118_fixture_owner: cerrado. tmp_dir portable y ebins desde build real;
  controles originales rojos reproducidos;27/27 strict en cada runtime.
- ci_fanout_owner: cerrado. Fixture esperaba cinco hojas con cuatro workers;
  original S4 falla3/7, S8 pasa7/7. Ondas conservan mismas semillas/caps/oráculos;
  parche7/7 strict en118/S2,S4 y120/S2,S4,S8, también envbuild/deps ausente.
- Padre: cerrado. JSON/EFT cap falla por Store.ETS timeout bajo carga, reproducido;
  comando runtime retenido antes de IO y Transition directa conserva record_limit.
  Tres controles strict pasan ambos runtimes,120 también bajo carga controlada.
- ci_continuation_owner: cerrado.81ACK perfilados27.205s→18.968s;1015/1020vectores
  exactos ambos runtimes;79casos distintos118 y90en120, incluidos55boundaries
  y ochoSequence registrados por nombre tras corregir selectores desplazados.
  Única inspección independiente del padre0findings; no re-review.

Evidencia original y recibos nuevos: /tmp/opencode/exagent-v2-codex-t6qgpstl/ci030/.
Run02 TAR SHA50b1c645627996f9df2f4c677b773ea7b5d93113566b2dadf5b831461a17802a:
153archivos exactos dad90ff, core90 exacto029, sólo tres docs distribuidos cambian.
No aceptar una suite cortada, focales seleccionados ni deps strictRED como CIverde.
Core cambia sólo Record.canonical y JSON.normalize; rawencoded_result intacto.
RecordSHA6222e4c727e47fd67769dcbb421aeeeee50fc20ac308395f1cd052de1d46cad2.
JSONSHA7cbe704cd3263c8356fc5f0cb50ab8ae841ad76e2c007b5e7fc0b78a27ac13c4.
Fuente/recibos leídos de vuelta; formato completo1.20 exit0, lock intacto.
Siguiente: commit/push causal autorizado y una CI integrada de la vertical estable.

## Aceptaciones anteriores que se conservan

| Gate | Evidencia y límites |
|---|---|
| G1 FULL019 |2157pases/28excl/0fallos,2276s,exit1 por warnings propios;136focales correctivos strict; no suite exacta actual verde |
| G1 ExDoc029 |exit0/0warnings,105HTML/2643targets/0links propios rotos |
| G2 real |GPT-4o-mini/OpenRouter14/14,17admisiones/3efectos,USD0.425reserva; fase cerrada |
| E2E consumidor028 |18escenarios reales aceptados,40admisiones/USD1.00reserva,7grupos cerrados; factura null; initial13/18 preservado |
| G3 SQL |PG17.4,14fases/ACKperdido/dosVMs/FlowA8/restart/recover/backup;29hijos cerrados |
| G4 Langfuse y Opik |Cada backend mismoA10 nativo/API33/33,667attrs/12usage; UI12casos/248attrs aceptados |
| G5 consumidores |8grafos×7=56pases en ambos runtimes; strictdeps pendientes, también reproducidos remotamente |
| SDK/frameworks |MCP2.2.0 cinco perfiles; LiveViewTest/Oban SQL6/6+crash/recover y cleanup |
| G6 finito |TestModel: carga/soaks/saturación acotadas; sin promesa providerHA/RAMpredecode |

Revisión crítica027 expresamente solicitada cerrada:1P1/4P2 corregidos;
C7multirronda8, contabilidad30 y controles OTLP. E2E028 descubrió fix Frame:
prefijoSystem antes del único User exacto;3regresiones+45adyacentes pasan.
Sin otra revisión R9 ni nuevas olas paid/cloud por la cualificación CI.
Opik utiliza tehsuso/exagent autorizado; claves sólo privadas0600, nunca Git.
El consumidor hermano exAgentTest/chat_app conserva .env/WIP y59fuentes
untracked: cambios y E2E autorizados, commit del consumidor no autorizado.

## Identidad, límites y relevo

Candidata029 inmutable:153distribuidos/564fuentes, nominal1.3.0.
TAR SHA8dd4e80a24ae01bea4e62051cbc15c30113c4bb34142b36623e3cb9bd070c808.
Lock raíz33a222bfe0df7fffcd78af2d0a7bcc61c0a762255fd05f690492da6433e7f2bc.
Evidencia737miembros SHA9c079799c9ecd690de4140b0e8b43d2e06bfe1ad730f13ab0975dccce728f1ec.
[FINAL-CANDIDATE](FINAL-CANDIDATE.md), [CRITICAL-REVIEW](CRITICAL-REVIEW.md),
[E2E-ACCEPTANCE](E2E-ACCEPTANCE.md), [OPIK-ACCEPTANCE](OPIK-ACCEPTANCE.md)
conservan detalle/históricos/limitaciones. Roadmap único: docs/development/roadmap.md.

ROOT/_build exclusivo padre. Workers: fuentes/deps/build/tooling físicos privados;
no reparar Hex global ni tocar fuentes compilables de otro runtime.
Pruebas offline EXAGENT_OFFLINE=1 MIX_ENV=test; dotenv deshabilitado.
G2/OpenRouter, SQL, Langfuse y Opik aceptados: ninguna repetición externa nueva.
Hex posterior: APIkey de publicación en HEX_API_KEY permite CI sin TOTP por envío;
no crear clave, cambiar2FA, publicar o subir versión en este objetivo.
