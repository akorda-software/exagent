# ExAgent v2 — estado vigente, 2026-10-03

Implementación autorizada en /home/kukapu/dev/projects/exAgent.
Rama: `codex/v2-candidate-029`, [PR1 borrador](https://github.com/akorda-software/exagent/pull/1).
El usuario autorizó commit/push/PR; sin bump, tag, merge ni publicación en Hex.
ReqLLM oficial stock, R1.2 aceptado, C7 incluido, guards intactos.
Una revisión máxima por objetivo; sin re-review ni reruns rutinarios del padre.

## E2E complejos — cuatro nuevos escenarios cerrados

Usuario pide tres combinaciones y un recorrido completo.24:seis etapas tipadas/
C7;25:paralelo/doble delegación/fallo collect;26:VMmuerta tras efecto antes ACK/
lease real/recover uncertain;27:memoria/Session/busy-abort/paralelo/delegación/
dos approvals/restart PostgreSQL/nuevaVM/archivo/PubSubstream. TestModel4/4 y
ambos modelos reales4/4,46requests/15efectos por modelo. Rojo DeepSeek27 Session
conservado; copia ASCII explícita pasa sin relajar oráculo, control27 también Luna.
Fases complex70/53requests/USD1.75/1.325reserva, factura null; smoke51/54intactas.
Nueve grupos/clusters cerrados. Precommit17/0/27excl;52fuentes consumer/94runtime
idénticas a las ejecutadas; rootlock intacto. Cobertura conjunta27/27Luna y
26/27DeepSeek;08nativo rojo. Sin FULL/G2/G3/cloud ni revisión nueva.
[E2E-COMPLEX](E2E-COMPLEX.md) conserva recibos, fuentes, límites y rojos.
ExDoc117HTML/5204targets,115MD/847,115EPUB/2876,0linksrotos; build/isolation0.
TAR168exactos/91runtime intactos, SHA8c5dc15a220ec353c42db7a6a6b11c7723f4a41402834e94811d0c7b7a490c9e.

## E2E Luna/DeepSeek — recibo smoke anterior

Usuario elige ambos modelos. 23casos ejecutados por modelo: Luna23aceptados,
DeepSeek22/23; ticket JSON nativo reproduce merchant/currency null, no aceptado.
Cinco casos nuevos de rechazo/cleanup/límite/Composition+C7 pasan en ambos.
Marcadores con copia explícita/oráculo exacto pasan; rojos/falso positivo guardados.
Precommit17/0/23excl;51/54requests/USD1.275/1.35reserva, factura null,16grupos cerrados.
ReqLLM1.26 stock/Chat/none; lib/lock intactos, ExDoc/links/TAR verificados. [E2E-MODELS](E2E-MODELS.md).

## Dependencias — verificación cerrada

Usuario pide revisar todas antes de publicar. 43 paquetes consultados: 12 nuevas
releases,11actualizadas,42últimas estables/1bloqueada(gproc por grpcbox~>1.2.0).
Finch0.24/Mint1.11/HPAX1.1 juntos; JSV0.25, Ecto3.14.2, exporter test1.11,
ExDoc0.40.4 y cuatro transitivas. Guards/API/lifetimes intactos; sin overrides.
76 schema/output/MCP y7OTLP pasan; bool_value native corregido upstream.
G2:12aceptados iniciales; length_sync obtuvo stop/refusal y length_stream no corrió.
Prompt largo benigno obtiene length sync/stream sin efectos: dos controles pasan.
14escenarios cubiertos,18admisiones/3efectos/USD0.45reserva; fallo inicial conservado.
PG17.4 nuevo14fases/cleanup;8grafos limpios56contratos/46comandos0,strictdeps rojo.
FULL ambos2177/0/28;1202007.4s/1182024.7s. bin/check nueve fases0,total2073.45s.
Artefactos privados: .exagent-local/dependencies20261003; fuentes runtime congeladas.
[DEPENDENCIES](DEPENDENCIES.md) conserva recibos/fallos/controles y límites.
ExDoc117HTML/115MD/115EPUB,0linksrotos;3vistas/anchors pasan. TAR168exactos,
metadata/91runtime iguales al cualificado;SHA2b725ef5a9abd97b047d462952967b116b9ef47d3126d3126fd2ffb30b01ad40.

## ReqLLM 1.26 — recibo anterior

[REQ-LLM126](REQ-LLM126.md): FULL1202177/0/28 y FULL1182176/1/28, readiness
corregido con13focales por runtime; G214/14 y app18/18, PG14fases y8grafos.
Guard/cache/redacted blocks cualificados; conservar identidad de cada receipt.

## Documentación para personas y agentes

Portada ExDoc, diez guías, entrada para agentes y llms.txt/Markdown/API.
Histórico byte-idéntico archivado; HTML/EPUB stock y formatter público Markdown.
`bin/check` incluye docs-links; runtime/lock intactos. [DOCUMENTATION](DOCUMENTATION.md).
No repetir FULL/G2/G3/G4 por este cambio documental.

## Rutina local y CI

El usuario elige validar local antes de commit/push; CI sólo workflow_dispatch
en esta rama, con seis jobs conservados. `main` cambia al integrar el PR.
`bin/check`: formato, compile/probes, suite, ExDoc/enlaces, TAR/aislamiento.
`--package-consumers` opt-in;22live+6PG excluidos offline, no timeouts ni pases.
Primera invocación completa previa:8fases exit0,2176pases/0fallos/28excl;
suite1979.7s, total2024.1s. No afirmar aceleración20× o nueva ejecución completa.

[Run03](https://github.com/akorda-software/exagent/actions/runs/37019949320)
sobre `f69aedea1a2f7c94c546fa95b631a71664110b4d`:
compile/test ambos y formato1.20 exit0;377fuentes exactas por runtime.
Elixir1.18.4/OTP28.0:2176pases/0fallos/28excl,2706.4s.
Elixir1.20.0/OTP29.0.5:2176pases/0fallos/28excl,2072.4s.
Paquete/harness pasan;56contratos en8grafos pasan,46comandos exit0.
Run global **failure** sólo por strictdeps: TOML ambos, WebSockex120,
gproc exporter120. Sin compilerwarnings ExAgent, supresión, fork u override.
CI funcional aceptado; G5strict upstream abierto. No afirmar CI global verde.
TAR run03 eff31a95803c414657333e1344831fcb8b7099460c481a664a3e4b0828fdbd3f:
153archivos exactos f69aede. No confundirlo con el nuevo TAR documental.

Run01/02 rojos y correcciones causales conservados en ci030/roadmap;
81ACK27.205s→18.968s, diferencial1015/1020vectores, review única0findings.

## Aceptaciones cerradas y límites

| Gate | Evidencia |
|---|---|
| G1 dependencias actuales | FULL ambos2177/0/28; receipt118 rojo anterior permanece en REQ-LLM126 |
| G2 real dependencias actuales |12pases iniciales y2length controles,14escenarios cubiertos;18requests/3efectos/USD0.45reserva; fallo inicial preservado |
| E2E consumidor028 |18escenarios reales,40admisiones/USD1.00reserva; initial13/18 y cinco retries preservados |
| E2E modelos actual |23por modelo; Luna23/DeepSeek22aceptados, caso08rojo;51/54admisiones |
| E2E complejos adicional |4/4por modelo;46requests/15efectos; fases70/53admisiones; coverage conjunta27/26aceptados |
| G3 SQL |PG17.4,14fases,ACKperdido/dosVMs/FlowA8/restart/recover/backup; cleanup observado |
| G4 Langfuse y Opik |Cada uno mismoA10 nativo/API33/33,667attrs/12usage; UI12casos/248attrs |
| G5 consumidores |8grafos×7=56PASS; strictdeps siguen rojos |
| SDK/frameworks |MCP2.2.0 cinco perfiles; LiveViewTest/Oban SQL6/6+crash/recover |
| G6 finito |TestModel: carga/soaks/saturación; sin promesa providerHA/RAMpredecode |

Revisión crítica027 expresamente pedida cerrada:1P1/4P2 corregidos.
R9 final cerrada; no reactivar revisiones ni nuevas olas paid/cloud.
Opik tehsuso/exagent autorizado; claves sólo privadas0600, nunca Git.
Consumidor exAgentTest/chat_app mantiene .env/WIP y código untracked;
sus cambios/E2E están autorizados, su commit no está autorizado.

## Relevo

Roadmap único: docs/development/roadmap.md. [FINAL-CANDIDATE](FINAL-CANDIDATE.md),
[CRITICAL-REVIEW](CRITICAL-REVIEW.md), [E2E](E2E-ACCEPTANCE.md),
[OPIK](OPIK-ACCEPTANCE.md) conservan identidad y límites de las candidatas previas.
ROOT/_build exclusivo padre; workers con fuentes/deps/build/tooling privados.
Offline EXAGENT_OFFLINE=1 MIX_ENV=test, dotenv deshabilitado.
Hex posterior: APIkey de publicación en HEX_API_KEY permite CI sin TOTP por envío;
no crear clave, cambiar2FA, publicar o versionar en este objetivo.
