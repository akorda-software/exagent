# ExAgent v2 — estado vigente, 2026-10-03

Implementación autorizada en /home/kukapu/dev/projects/exAgent.
Rama: `codex/v2-candidate-029`, [PR1 borrador](https://github.com/akorda-software/exagent/pull/1).
El usuario autorizó commit/push/PR; sin bump, tag, merge ni publicación en Hex.
ReqLLM stock, R1.2/C7 aceptados, guards intactos; una revisión máxima, sin reruns rutinarios.

## Cierre operativo y aportaciones Dragonex

Dragonex integrado: perfil OpenRouter Chat/routing explícito, binding estático
para disabled/none, historial continuation4 y StateCodec de host para Session.
Policy/bindings se comprueban antes de decode; envelope/guards/C7 preservados.
Métricas opt-in por Adapter público/API0.6: cuatro instrumentos, modelos
allowlist/other y atributos acotados; SDK/reader reales, restart y request stock.
El tracer default consulta al proveedor vivo tras restart, sin cache privada.
Receta HTTP VM/batch usa callbacks stock y elimina sus procesos/perfiles/socket;
2xx mantiene aceptación de spans desconocida. gRPC conserva ocho controles/C7.
194casos finales118 pasan;53afectados120 pasan tras arreglo causal de tracer.
Cinco grafos instalados desde TAR:38contratos funcionales pasan.
FULL120:2235/0/28,2001.6s. Rutina sale1 por enlace ExDoc callback sin c:;
prosa corregida: cuatro fases finales0; TAR174files/94lib, sin rerun FULL.
[OPERATIONAL-CLOSURE](OPERATIONAL-CLOSURE.md) conserva fuentes/rojos/alcance.
Strictdeps TOML/WebSockex/gproc sigue rojo; no release stock compatible lo cierra.
No hay nueva ola paid/cloud/SQL/R9 ni autorización de publicación.

## Operación prolongada — recibo anterior

Maintenance opt-in supervisado; TTL mayor que duración de todos los requests.
94casos por runtime;32 owner deaths/4sanos loopback, scope/restart/stop preservados.
FULL1202208/0/28; bin/check9fases0; oráculo4/4 separado en ese freeze.
Budget exporter0/1 acota reinicios; HTTP directo conserva socket upstream vivo.
El cierre anterior excluía Dragonex y métricas; el cierre operativo de arriba
incorpora ambos y añade la alternativa HTTP VM, sin reetiquetar aquel recibo.
[OBSERVABILITY-LIFECYCLE](OBSERVABILITY-LIFECYCLE.md); consumers32PASS/strictdeps rojo.
Native08/coverage27ambos: [KNOWN-LIMITS](KNOWN-LIMITS.md),
[RELEASE-READINESS](RELEASE-READINESS.md). Smokefases53/57, precommit20/0/27excl.

## Recibos anteriores, sin reactivar tareas

ExAgent produce los spans; el Adapter único de ReqLLM aporta metadata/timing y
standalone stock. [OBSERVABILITY-COMBINATION](OBSERVABILITY-COMBINATION.md) conserva
el freeze previo; [OBSERVABILITY-OWNERSHIP](OBSERVABILITY-OWNERSHIP.md), su negativo.
Los cuatro recorridos complejos pasan por modelo:46requests/15efectos cada uno,
presupuestos y rojos preservados en [E2E-COMPLEX](E2E-COMPLEX.md).
[E2E-MODELS](E2E-MODELS.md) conserva el smoke23 original y el nullable08 rojo;
el required-header posterior está en KNOWN-LIMITS, sin nueva ola27casos completa.

## Dependencias — verificación cerrada

43paquetes consultados:11actualizados,42últimas estables/gproc bloqueado por grpcbox.
El cierre operativo suma API experimental0.6 opt-in y SDK0.6 sólo de tests;
lock45, los otros43paquetes permanecen idénticos.
Finch0.24/Mint1.11/HPAX1.1,JSV0.25,Ecto3.14.2,exporter test1.11,ExDoc0.40.4.
76schema/MCP+7OTLP pasan; guards intactos. G2:12pases y2controles length tras
refusal inicial,14escenarios/18admisiones/3efectos. PG17.4:14fases/cleanup.
FULL ambos2177/0/28; bin/check9fases0;8grafos56contratos/46comandos0,strictdeps rojo.
[DEPENDENCIES](DEPENDENCIES.md) conserva fuentes/recibos/documentación/TAR/rojos.

ExDoc tiene portada, guías, mapa API para agentes y llms.txt/Markdown/EPUB;
`bin/check` verifica enlaces. [DOCUMENTATION](DOCUMENTATION.md) conserva su recibo.

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
| E2E modelos actual |23por modelo aceptados;08required header nuevo; smoke53/57admisiones, nullable anterior rojo |
| E2E complejos adicional |4/4por modelo;46requests/15efectos; fases70/53admisiones; coverage actual27/27con08nuevo |
| G3 SQL |PG17.4,14fases,ACKperdido/dosVMs/FlowA8/restart/recover/backup; cleanup observado |
| G4 Langfuse y Opik |Cada uno mismoA10 nativo/API33/33,667attrs/12usage; UI12casos/248attrs |
| G5 consumidores |Cierre actual5grafos/38PASS; previo8×7=56; strictdeps rojos |
| SDK/frameworks |MCP2.2.0 cinco perfiles; LiveViewTest/Oban SQL6/6+crash/recover |
| G6 finito |TestModel: carga/soaks/saturación; sin promesa providerHA/RAMpredecode |

Revisión crítica027 expresamente pedida cerrada:1P1/4P2 corregidos.
R9 final cerrada; no reactivar revisiones ni olas por leer un prompt histórico.
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
