# ExAgent v2 — estado vigente, 2026-10-02

Implementación autorizada en /home/kukapu/dev/projects/exAgent.
Rama: `codex/v2-candidate-029`, [PR1 borrador](https://github.com/akorda-software/exagent/pull/1).
El usuario autorizó commit/push/PR; sin bump, tag, merge ni publicación en Hex.
ReqLLM oficial stock, R1.2 aceptado, C7 incluido, guards intactos.
Una revisión máxima por objetivo; sin re-review ni reruns rutinarios del padre.

## Documentación para personas y agentes

Encargo explícito posterior al gate local: portada ExDoc y diez guías por tarea,
entrada de integración para agentes, llms.txt/Markdown y navegación de API.
Estado actual separado del histórico: cuerpo anterior byte-idéntico archivado.
HTML/EPUB stock; formatter público Markdown corrige rutas aplanadas y protege código.
`bin/check` incluye el nuevo gate docs-links. Fuente runtime/lock intacta.
Evidencia y límites de este delta: [DOCUMENTATION](DOCUMENTATION.md).
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

Run01 sobreb709d57: paquete/harness pasan,118compile falla y120cancelado.
Run02 sobredad90ff: failure/timeouts3000s con76/72fallos previos, sin totales.
Correcciones causales cerradas en f69: tmp_dir/build real, fanout por oleadas,
oráculo JSON/EFT independiente de ETS y menor coste de normalización/canonical.
27portables+7fanout+3cap por runtime;79casos118/90en120;1015/1020vectores exactos.
81ACK27.205s→18.968s; una inspección independiente0findings, sin re-review.
Originales y recibos: /tmp/opencode/exagent-v2-codex-t6qgpstl/ci030/.

## Aceptaciones cerradas y límites

| Gate | Evidencia |
|---|---|
| G1 FULL actual |2176pases/0fallos/28excl ambos runtimes; FULL0192157/28/exit1 conservado como histórico |
| G2 real |GPT-4o-mini/OpenRouter14/14,17requests/3efectos,USD0.425reserva; sin factura observada |
| E2E consumidor028 |18escenarios reales,40admisiones/USD1.00reserva; initial13/18 y cinco retries preservados |
| G3 SQL |PG17.4,14fases,ACKperdido/dosVMs/FlowA8/restart/recover/backup; cleanup observado |
| G4 Langfuse y Opik |Cada uno mismoA10 nativo/API33/33,667attrs/12usage; UI12casos/248attrs |
| G5 consumidores |8grafos×7=56PASS; strictdeps siguen rojos |
| SDK/frameworks |MCP2.2.0 cinco perfiles; LiveViewTest/Oban SQL6/6+crash/recover |
| G6 finito |TestModel: carga/soaks/saturación; sin promesa providerHA/RAMpredecode |

Revisión crítica027 expresamente pedida cerrada:1P1/4P2 corregidos.
R9 final cerrada; no reactivar revisiones ni nuevas olas paid/cloud.
Opik tehsuso/exagent autorizado; claves sólo privadas0600, nunca Git.
Consumidor exAgentTest/chat_app mantiene .env/WIP y59fuentes untracked;
sus cambios/E2E están autorizados, su commit no está autorizado.

## Relevo

Roadmap único: docs/development/roadmap.md. [FINAL-CANDIDATE](FINAL-CANDIDATE.md),
[CRITICAL-REVIEW](CRITICAL-REVIEW.md), [E2E](E2E-ACCEPTANCE.md),
[OPIK](OPIK-ACCEPTANCE.md) conservan identidad y límites de las candidatas previas.
ROOT/_build exclusivo padre; workers con fuentes/deps/build/tooling privados.
Offline EXAGENT_OFFLINE=1 MIX_ENV=test, dotenv deshabilitado.
Hex posterior: APIkey de publicación en HEX_API_KEY permite CI sin TOTP por envío;
no crear clave, cambiar2FA, publicar o versionar en este objetivo.
