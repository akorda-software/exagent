# ExAgent v2 — estado vigente, 2026-10-04

El usuario autoriza subir todo directamente a `main`, sin PR obligatoria.
Versión2.0.0/workflow/docs ya en main; PR1 integrada automáticamente por el push.
Deltas de otro dueño: guía backend y causa RequestError con copia Response omitida.
159focales juntos pasan en copia propia1.20/29,14.3s; FULL anterior no cubre estos deltas.
Pendientes clave HEX_API_KEY, tag oficial y release; push a main no publica.
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
No hay nueva ola paid/cloud/SQL/R9. El usuario acepta deuda externa sin modificar upstream.

## Preparación de publicación

Workflow release:published estable; manual preview nunca publica/recibe secretos.
Guard version/changelog/docs/tag/main; compilación/docs/TAR sin suites largas en CI.
API key package:hexpm/exagent evita TOTP por envío; creación web puede pedir2FA.
Sin --replace; TAR idéntico permite docs. Readback compara bytes y docs versionadas.
17guards/18doc y compile/docs/TAR pasan; consumidor2.0:
8contratos0fallos/strictRED38warnings.94lib/lock idénticos en ese checkpoint;
[RELEASE-PREPARATION](RELEASE-PREPARATION.md) y [MAIN-INTEGRATION](MAIN-INTEGRATION.md) conservan identidades.

## Operación prolongada — recibo anterior

Maintenance/budget/94focales por runtime: [OBSERVABILITY-LIFECYCLE](OBSERVABILITY-LIFECYCLE.md).
FULL previo2208/0/28 y32contratos conservan identidad; no incluían Dragonex/métricas.
Native08/coverage27ambos: [KNOWN-LIMITS](KNOWN-LIMITS.md) y [RELEASE-READINESS](RELEASE-READINESS.md).

## Recibos anteriores, sin reactivar tareas

ExAgent produce los spans; el Adapter único de ReqLLM aporta metadata/timing y
standalone stock. [OBSERVABILITY-COMBINATION](OBSERVABILITY-COMBINATION.md) conserva
el freeze previo; [OBSERVABILITY-OWNERSHIP](OBSERVABILITY-OWNERSHIP.md), su negativo.
Los cuatro recorridos complejos pasan por modelo:46requests/15efectos cada uno,
presupuestos y rojos preservados en [E2E-COMPLEX](E2E-COMPLEX.md).
[E2E-MODELS](E2E-MODELS.md) conserva el smoke23 original y el nullable08 rojo;
el required-header posterior está en KNOWN-LIMITS, sin nueva ola27casos completa.

## Dependencias — verificación cerrada

Lock45: revisión43paquetes/11actualizaciones y dos paquetes metric0.6 añadidos.
Gproc bloqueado por grpcbox; warnings upstream intactos. [DEPENDENCIES](DEPENDENCIES.md)
conserva fuentes/recibos/TAR/rojos, FULL previo y G2/PG anteriores.

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
Offline EXAGENT_OFFLINE=1 MIX_ENV=test, dotenv deshabilitado. Siguiente: crear
clave, guardar secreto GitHub y publicar release oficial; preview opcional. Commits directos a main.
