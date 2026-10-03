# ExAgent v2 — estado vigente, 2026-10-03

Implementación autorizada en /home/kukapu/dev/projects/exAgent.
Rama: `codex/v2-candidate-029`, [PR1 borrador](https://github.com/akorda-software/exagent/pull/1).
El usuario autorizó commit/push/PR; sin bump, tag, merge ni publicación en Hex.
ReqLLM oficial stock, R1.2 aceptado, C7 incluido, guards intactos.
Una revisión máxima por objetivo; sin re-review ni reruns rutinarios del padre.

## Ownership de observabilidad — evaluación cerrada

ReqLLM1.26 bridge opt-in; ExAgent no lo activa.4controles SDK/HTTP-SSE pasan:
1request/1generación por defecto; ambos bridges1request/2generaciones,output2→4
al sumar observaciones, ledger intacto. Se recomienda productor ExAgent para sus
runs; reparto parcial valorado/no implementado.32focales0; docs/enlaces/build/
isolation0. Runtime/lock intactos, sin FULL/cloud/re-review/bump/publicación.
[OBSERVABILITY-OWNERSHIP](OBSERVABILITY-OWNERSHIP.md) conserva análisis y evidencia.

## E2E complejos — cuatro nuevos escenarios cerrados

24:C7/seis etapas;25:paralelo/doble delegación/collect;26:efecto sin ACK/recovery;
27:memoria/Session/abort/paralelo/dos aprobaciones/PGrestart/stream entre VMs.
TestModel y ambos modelos4/4,46requests/15efectos cada uno. Rojo DeepSeek27 y
control ASCII conservados, oráculos intactos. Complex70/53admisiones,
USD1.75/1.325reserva, factura null. Nueve grupos/clusters cerrados; precommit17/0/27excl.
Fuentes idénticas; cobertura conjunta27/27Luna y26/27DeepSeek,08nativo rojo.
[E2E-COMPLEX](E2E-COMPLEX.md) conserva fuentes, documentación/TAR y límites.

## E2E Luna/DeepSeek — recibo smoke anterior

23casos por modelo: Luna23,DeepSeek22; native JSON merchant/currency null rojo.
51/54admisiones/USD1.275/1.35reserva, factura null,16grupos cerrados; guards intactos.
ReqLLM1.26 stock/Chat/none. [E2E-MODELS](E2E-MODELS.md) conserva fuentes/rojos/controles.

## Dependencias — verificación cerrada

43paquetes consultados:11actualizados,42últimas estables/gproc bloqueado por grpcbox.
Finch0.24/Mint1.11/HPAX1.1,JSV0.25,Ecto3.14.2,exporter test1.11,ExDoc0.40.4.
76schema/MCP+7OTLP pasan; guards intactos. G2:12pases y2controles length tras
refusal inicial,14escenarios/18admisiones/3efectos. PG17.4:14fases/cleanup.
FULL ambos2177/0/28; bin/check9fases0;8grafos56contratos/46comandos0,strictdeps rojo.
[DEPENDENCIES](DEPENDENCIES.md) conserva fuentes/recibos/documentación/TAR/rojos.

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

Validar local con `bin/check`; CI workflow_dispatch/seis jobs en esta rama.
`--package-consumers` opt-in;22live+6PG excluidos offline, no timeouts/pases.
[Run03](https://github.com/akorda-software/exagent/actions/runs/37019949320)
sobre f69aede:ambos2176/0/28; paquete/harness/8grafos56contratos/46comandos0.
Global **failure** por TOML/WebSockex/gproc stock; G5strict abierto, sin supresión.
Recibos/run01–02/optimización81ACK/review única en ci030/roadmap; no reactivar.
Los TAR fechados conservan identidad; no relabel ni promesa de speedup20×.

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
