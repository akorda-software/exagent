# Evidencia recibida — snapshot anterior al cierre009/017

Registro conservado al reducir CURRENT. Las tareas/estados vigentes están en CURRENT.md.

# ExAgent v2 — continuación autorizada 2026-10-01

El usuario pide completar la implementación v2 y revoca la pausa. Proyecto:
`/home/kukapu/dev/projects/exAgent`; padre Codex `/root`; HEAD `7f25b33`, WIP
amplio preservado. Sin commit/push/bump/tag/publicación ni cambios a consumidores.
Antecedente: `../2026-09-28-native-f19085/CURRENT.md`, conservado como evidencia.
ReqLLM oficial stock, R1.2 aceptado y C7 incluidos; guards inciertos intactos.
Método: objetivos funcionales, una revisión independiente máxima por objetivo,
dueño corrige/regresa, sin re-review ni reruns rutinarios del padre.

Tooling privado: `/tmp/opencode/exagent-v2-codex-t6qgpstl/`, Hex2.5.1 copiado del
toolchain local aceptado1.18/OTP28; ejecución1.20.0/OTP29.0.5. No reparar Hex global.
`ROOT/_build` tiene dueño exclusivo009; el resto usa freezes/builds físicos propios.
No tocar BEAM/services ajenos. Externos relevantes mantienen autorización documentada;
cada ola exige fuente/alcance/admisión/presupuesto. No paid tests por defecto.

| Nº | Objetivo | Estado / dueño | Revisión |
|---|---|---|---|
| 001 | Delegación real Frame10, C7 y recover | Cerrado acotado; owner libera lib/build | 1/1, dos P2 corregidos |
| 002 | SDK oficial MCP: stdio y cuatro perfiles HTTP | Harness portable5/5 en freeze físico | R7 review011 cerrada1/1 |
| 003 | Runner TAR portable y CI de bytes comunes | Aislamiento verde; manifest7/adapter público regresados | Integración candidata pendiente |
| 004 | OTLP público, VM propia por batch y lifecycle finito | Receta8casos+C7+3ciclos verde en consumidor privado | R8 review014 cerrada1/1 |
| 005 | Retrieval externo: espacio confiable y resultados acotados | P2 excepción privada saneada; cuatro formas regresadas | R7 review011 cerrada1/1 |
| 006 | MCP C7 ligado a target/principal | Integradas12rutas; focal11 y VM5 combinadas verdes | R7 review011 cerrada1/1 |
| 007 | SQL portable, restart/recover/backup | Siete fases verdes PG17.4; candidata/A8 pendientes | Integración pendiente |
| 008 | Job externo C7 sin replay por duplicados | Receta VM privada exit0; extracción012 con API idéntica | R7 review011 cerrada1/1 |
| 009 | Routing, fan-out/fan-in, fail_fast/collect, C7/A8 | /root/delegation_owner; lib/tests/buildROOT exclusivo; Flow/Frame11 causal | 0/1 |
| 010 | Ruta OTLP gRPC→Collector oficial→HTTP | Release1.11/Collector0.162: HTTP5/5 + ciclo3 + controles3 verdes | R8 review014 cerrada1/1 |
| 011 | Integración R7 MCP/retrieval/job | Review única; P2 retrieval corregido por dueño/regresión | Cerrada1/1, sin re-review |
| 012 | Phoenix/LiveView/PubSub + Oban SQL reales | /root/mcp_sdk_harness; consumidor/build/cluster propios | Delta nuevo en revisión final R9 |
| 013 | SQL pérdida COMMIT/ACK real + dos resumersVM | Red/replay y dos resumers públicos verdes en freezes privados | Nuevo delta G3; candidata/A8 pendientes |
| 014 | Revisión independiente transporte004/010 | Padre independiente de autor;21fuentes idénticas, sin P1/P2 | Cerrada1/1 |
| 015 | Native/Collector→Langfuse/API/A10 | /root/otlp_transport prepara opt-in; sin leer.env ni cloudwrite | UI/admisión/candidata pendientes |
| 016 | Recetas R6.4 extracción/supervisor/revisión humana | Padre; nuevo ejemplo/docs con APIs públicas, no Root Mix | Verificar tras freeze009; incluida review009 única |

## Recibos y límites vigentes

- 001: `delegation/REPORT.md` SHA
  `b4e895958721e3a348884d16d55a14d387b2ae8a85e486fafd989f6089bad406`.
  784casos afectados distintos verdes; VMmixed4/4, matriz26/26 y regresiones
  legacy/productor10. FULL inicial1543/2093,550fallos,28excl,2482.5s exit2
  permanece rojo; veinte familias tienen regresión causal. No FULL final global
  verde nuevo. P2 retry y raw8KiB ante cota4096 corregidos sin wrapper/replay.
  Fuente38/38 sellada `delegation/final-source.sha256` SHA8718022b…65154;
  dictamen único `delegation/review.md` SHA2291fb29…4312f. Slot durable10
  64KiB; no cambio de payload/history global ni guard Model/root no certificado.
- 002: mcp2.2.0/mcp-types2.2.0 oficiales,133archivos verificados/28distribuciones.
  Mismos cinco perfiles, no diez al repetir posformato. Recibo final
  `mcp-sdk/exagent-mcp-sdk-a2fq1cx3/report.json` SHAad351d30…b0ca9:
  38requests únicos,10effects,2DELETE,5PID/4listeners cerrados. No nueva
  cualificación OAuth/TLS/cancel/reconnect/chaos/protocolo2026/otrosSDK.
- 006: repro rojo2/2, fix/regresión150/150 incluidos11nuevos y cinco fasesVM.
  Huellas locales y root1fixture aceptada permanecen byte-idénticas.
  No endpoint/principal/credentials reales autenticados por esas referencias.
  Ordinario unbound usable; durable requiere identidad host. Cambio de target/
  principal rechaza antes de Model/ToolIO; misma identidad permite rotar secretos.
  Patch completo SHA66f97058…88d2 aplicado12/12, design8.43. Freeze combinado
  `mcp-integrated-c5epccv5/project`,2190archivos, manifestSHA6ae53bec…87eb8;
  focal única11 verde, reciboSHA3f75e5c9…6fd, sin repetir150/SDK. ROOT vuelve a009.
- 003: runner ya acepta temporales portables con todos los padres reales;
  rechazo symlink/existing/selector y diagnóstico estricto siguen. Control con
  TAR sintético exit0, artefactos `/tmp/exagent-package-isolation-1790877896782277595/`.
  CI prepara un único TAR/hash para cuatro grafos en dos runtimes; remoto no
  ejecutado. Piloto previo a009 `package-pilot-nbo5ih3a`: TAR real generado
  sin bump; siete tests ejecutados verdes, gate exit1 por manifest antiguo seis
  y warnings de dependencias/fixture. Se conservan rojos. Manifest7 exige nombres/
  módulo/state exactos y cuatro negativos rechazan; isolation focal realTARexit0
  `/tmp/exagent-package-isolation-1790885357446921052`. Adapter módulo público
  con Agent privado pasa caso stockbuffered/tools/native sin warnings propios;
  logs `adapter-focal01/02/03` conservan rojos y regresión. No aceptación candidata.
- 004: receta empaquetable `examples/otlp_transport/` y guía aislada.
  Recibo `test/support/otlp_transport/receipt-isolated-2026-10-01.json`
  SHAa2dd0bd1…4400;8casos+C7(3paused+3resumed)+3ciclos privados. Cleanup de
  grupo OS creado/reap propio; gate compartido1VM, deadline y callback finitos.
  Converter/cliente públicos; encoder privado sólo fixture. Pin oficial1.11pre,
  overhead425–450ms;50warnings upstream compile/41run visibles, propios0.
  No cloud/backend/Collector aceptado;010 investiga release1.11 publicada y ruta.
- 005/008: retrieval y job son ejemplos públicos, ninguna dep obligatoria nueva.
  Retrieval dos espacios/sólo deps host/no selector remoto/3hits×2048bytes.
  Job get/run/decide/resume/terminal sin IO, modelo2/tool1/effect1 y duplicados
  inertes; actor autenticado por app. Review011 encontró fuga al callback retrieval
  raised: rescue/catch sanea error/raise/throw/exit a retrieval_unavailable,
  una invocación cada uno sin repetir IO ni exponer sentinel. SourceSHA8949b136…75fa,
  regression `r7-review/retrieval-owner-fix.log` exit0; reviewREPORTSHAf12f368…f38.
  TAR/Oban todavía pendientes.
- 007: `/tmp/exagent-pg-q9qa49pf/report.json` SHA1dea0228…3cad6.
  PG17.4/READ COMMITTED, sockets0700 propios/no5432; VMcrash73, restartDB,
  approval/resumeVM, uncertain sin replay, CAS/DELETEtrigger real, dump/restore
  idéntico4records2effects. Cleanuptrue, fuente92manifest65f8bcfb…956e,
  lockc20a0cb9 intacto. Rootprobe formateado después: recibo no acepta esos
  bytes ni candidata/A8/RLS/ACKperdido realmente en red/raceclaims2VM/HA.
- 013: `/tmp/exagent-pg-jwtg8lzq/report.json` SHA7c158fbf…beb8 acepta sólo bootstrap
  y corte real de COMMIT en proxy propio, sobre el mismo core físico anterior.
  Cliente no confirmado; DBrevision1 existe; replay recibo idéntico, sin Model/tool.
  Cuatro conexiones incluidas2cancelaciones, errors[], cierre proxy0/clustertrue.
  Primer control CancelRequest no soportado conservado; forwarding + chequeo final
  regresados. Dos resumers públicos en VMs simultáneas pasan:
  `/tmp/exagent-pg-hvimwsu5/report.json` SHA44335a58…841e2. Uno gana;
  observaciones SQL externas confirman2requests reales/1effect incluyendo prepausa.
  Rojo de oráculo publicready→approved preservado; helper agrupado sin warnings.
  Default nuevo12fases, race en segundo DB propio; full/A8/candidata pendientes.
- 014: `r8-review/REPORT.md` SHAd2ef2051…dc; fuente21 antes/después idéntica,
  manifestSHAb6680a0a…d559. Padre es independiente del autor004/010, sin repetir
  matrices ni escribir cloud. No P1/P2 en perfil finito Linux/host confiable;
  converter publicado/pin y coste VM se mantienen como límites explícitos.
- 009: Frame10 prefix/fatalglobal no representa collect; Flow/Frame11 conserva
  lectura9/10 sin relabel/migración. Router elige una hoja confiable; parallel
  ejecuta lista acotada de hojas que pueden delegar. Scope/Writer/CAS/approvals
  se reutilizan, merge por orden definido. Fuentes cambiantes no se congelan
  para gates externos hasta entrega estable.
- G4 UI: usuario confirmó que revisará desde su propio navegador; no puede
  iniciar sesión aquí. Entregar enlaces/traceIDs/comprobaciones breves; no
  inferir aceptación visual desde API. Ninguna herramienta browser/MCP disponible.
  Parent prepara acceso/API sólo al proyecto sintético exagent ya autorizado;
  no inspeccionar históricos ajenos ni volcar secretos. A10 depende de009.

## Próximo trabajo

Completar009/012 y verificar016; preparar015; deltas013 verdes antes de candidata.
Revisiones011/R7 y014/R8 cerradas. La nueva
Flow009 recibirá una revisión única tras fuente estable. Preparar
consumidores mínimo/runtime/durable/extensible/instrumentado, matriz local y
carga finita. Congelar candidata sólo sin features pendientes; correr G1–G6
pertinentes con identidades comunes, live en ola admitida. CI remoto/publicación
requieren solicitud expresa sobre resultado concreto preparado.
