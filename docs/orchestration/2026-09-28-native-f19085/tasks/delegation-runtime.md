# Objetivo funcional: delegación real y continuación durable

Autorización vigente del usuario: continuar v2 con flujo simplificado2026-10-01.
Un dueño implementa/evoluciona la vertical, con como máximo una revisión al terminar;
no propuestas/reviews intermedias ni repetición del padre. No delegar desde el hijo.

## Resultado exigido

Ejecutar con el loop real y APIs de Composition, no comandos CAS sintéticos:
**A efecto → B sibling + delegado D → D sibling + dos asks → workers DOWN y pausa
raíz ACK → dos decisiones → VM nueva → D final → crash antes de wrapper B →
recuperación administrativa explícita → wrapper/final B → C**.

Mismo Writer/Record/Store/Scope, autoridad raíz y budget; prefijos confirmados inertes,
sin repetir hooks, tools, mappings, pricing ni charge de uso. No prometer SQL ni
exactly-once externo. Una VM distinta puede usar el Store de fichero de tests existente.

## Ejecutar, no reauditar

1. Conectar producer10/Writer/loop/Tool.delegate y demostrar pronto **A→B(D)→C real**.
   Esto es checkpoint de código, no aceptación pública ni otra unidad/review.
2. Completar pausa mixed, inventario/monitor/drain y dos decisiones sin workers propios
   vivos tras devolver paused. Resolver definiciones host con refs exactas postclaim;
   datos históricos cerrados no ejecutan callbacks. Restore10 por las mismas APIs.
3. Recuperación10 explícita y retornos raw/final correctos, guardando ambigüedad de
   preparación/wrapper: nunca autoreplay por desconocer si el callback se ejecutó.
4. Completar los caminos de fallo del runtime que esta activación necesita (host/raw/
   root/retención, drain/cierre), reutilizando los contratos CAS existentes. No abrir
   IO o fronteras no probadas para conseguir el escenario feliz. Preservar C7/secuencia.
5. Matriz focal de identidad/autoridad, ACK/crash, carreras/resumers, pasos/delegados
   múltiples, contadores/uso, límites de source y cleanup. Una regresión integrada
   cuando la vertical esté estable, no antes de lograr ejecución real ni por cada fix.

## Contrato ya decidido

Consultar `delegation-schema-proposal.md` y sus enmiendas finales; no reinterpretar
las frases preliminares como nueva gate de diseño. `structural-delegation.md` es
historial/evidencia. Record2/Execution2/Frame10/ScopeLedger2/Approval1, RequestData2,
raw failed10 canónico y terminal-Retry se conservan. Lifetimes7/8/9 inmutables, sin
migración automática, modos públicos duplicados ni callback reejecutado como settlement.
Reserva previa composicional y créditos sólo propios; no subir límites/truncar
diagnósticos/relajar validadores. Recovery administrativa, no renovar saldo/deadline,
autorecovery, stale-reference refresh ni reconciliación automática nueva.

## Propiedad y alcance causal

Dueño: ROOT runtime/tests/build y docs causales. Padre: memoria/CURRENT/DECISIONS.
Editar lo necesario en ExAgent/Composition/Tool/Writer/Frame/Transition/Record/
CompositionRestore/Scope/Authority y helpers relacionados; fixtures/tests existentes
y nuevos, docs diseño/changelog/R6/roadmap/status. No bloquearse por un archivo fuera
de una allowlist: justificar su relación causal. Cambios nuevos de contrato/alcance
requieren decisión breve del padre, no escalamiento por cada ajuste de fixture.
No escribir memoria del padre, otros frentes ni aplicaciones consumidoras.

## Entrega y límite de gasto

- Empezar por código vivo, no otra sesión de investigación de validadores. En el
  primer despacho entregar ejecución real probada o bloqueo causal concreto y WIP;
  sin progreso ejecutable no se autoriza repetir un despacho equivalente.
- Reusar pruebas/harness de secuencia/VM y CAS10 ya existentes. Focales mínimas por
  delta, compile/formato al estabilizar; no FULL/69/164/166 por rutina. Tras activar
  el productor, sí corresponde una suite integrada sobre esas fuentes finales.
- Si falta contexto, checkpoint corto de código/casos pendientes y liberar procesos;
  continuar el objetivo sin review parcial ni rehacer diseño. No fingir aceptación.
- Un informe final en destino nuevo `/tmp/opencode`, delta, comandos/exits, fuentes
  afectadas/hash y límites. Preservar fallos; no carpetas baseline/logs interminables.
- Offline/test y tooling aislado de environment.md, build absoluto ROOT/_build,
  WA/maxcases48/seed37556, timeout600000 para tests. Un solo owner build; sin polling.
- Sin paid/SQL, infra, instalación/globalconfig, secretos, forks, commits/push/bump,
  publicación ni procesos ajenos. No nuevas features router/paralelo/R7 en este encargo.

Baseline integrado1845pases/28excluidos precede CAS10; no declararlo suite actual.
La entrega decide después una revisión única de esta vertical. No aceptar v2/R6
general o producción por cumplir únicamente este escenario.

## Recuperación tras sesión dañada

Owner inicial `ses_f096d6e80ffeGp4D5XyTe19uA0` error invalid_encrypted_content, NOreusar.
Dejó ExAgent/Writer/Frame/Delegation/Composition y nuevo delegation_runtime_test.exs.
WIP intacto, sin checks propios activos. `/tmp/opencode/exagent-delegation-runtime-Iyegfm/`
contiene initial-runtime.tar/initial.sha256 y real01/02.log. Último real02:0/1,
invalid_record antes del primer Model de A (request_count0), no hito aceptado.
Continuar ese código/test, no regenerarlo. Snapshot WIP de padre en
`/tmp/opencode/exagent-flow-simple-mcermh9s/encrypted-recovery-wip.tar`.
Sin repetir auditorías previas, cambiar modelos/configuración ni otra revisión.
