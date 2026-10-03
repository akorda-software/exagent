# R5 root: checkpoint intermedio, no aceptación C7

## Alcance e identidad

Task R5 mantiene ownership ROOT, nominal1.3.0 y WIP anterior. Dirección/ADR8.34
aprobadas antes de runtime; checkpoint administrativo source5b43c0cb recibió
review temprana sin P1/P2, no aceptación del runtime posterior. Este registro
acompaña la copia inmutable root para review paralela sobre fuentes/build privados.
El owner continúa árbol/Server/Session; no freeze final ni publicación.

**Replan de cierre2026-09-26:** coordinador pide terminar los cuatro P2 de la raíz,
congelar y revalidar esta unidad antes de ceder a contexto fresco. Server WIP se
preserva e inventaría, sin ampliar árbol/Session ni recortar C7. No worker_done
hasta instrucción de cierre/cesión tras review.

## Implementado y ejercitado por API pública

- run→paused→decide→resume→succeeded root, mismo run_id e intento nuevo;
  liberación del proceso solicitante y writer durante espera.
- Modelo stateful rehidratado mediante codec host explícito; selección de tools
  validada con fingerprint, refs de definición/policy/modelo y args efectivos.
- Callback Model.validate_resume requerido para C7, ordinary-only preservado;
  stock ReqLLM sintético verifica binding de endpoint antes del efecto y envelope
  exactamente una vez después de continuar, con Usage normalized explícito.
- Dos resumers liberados por barrera, sólo uno ejecuta; current policy puede negar
  una llamada aprobada; cambio de definición/schema rechaza antes del efecto.
- Stream paused terminal y otro stream lazy al reanudar.
- Batch root con hermano confirmado no reejecutado; requests/tools exactos.
- Save antes/después commit al pausar y después de efecto real; token exacto
  data-only, retry sólo persistencia y sin nueva llamada al modelo/tool.
- Muerte real del owner durante tool con diario externo y cleanup observado;
  recover→uncertain y reconciliación host de resultado conocido, sin replay.
- VM nueva en dos procesos Elixir desde JSON de fixture disco test-only: diario
  model-first/effect/model-second, una sola ejecución de cada tramo. No prueba G3.
- Human wait mayor que el saldo activo sin consumirlo; ownerkill tras claim antes
  de IO pierde la reserva, sin saldo gratis. Ledger restaurado no repricia y
  conserva quality/coste estimado/contadores y límite original de requests.
- Token completo EFT exacto J/J−1 con control de llegada a Store; tokens futuros,
  malformados y namespace distinto rechazados. Cap JSON+reserva independiente de
  EFT; payload escapado elegido por tamaño real, no por una constante favorable.
- Postefecto que supera J conserva succeeded/IDs/Usage y marker checkpoint sin
  retener el payload gigante ni llamar al modelo siguiente; R medido EFT/JSON.

## Pendiente explícito

R5 no está completa ni aceptada. Faltan árbol/descriptor de delegation_tool,
presupuestos y autoridad de todos los ancestros restaurados; Server/Session,
colas/mutaciones/consulta/eventos integrados; todos los casos de crash/reconciliación
de estado de modelo y retry de efecto con idempotencia explícita de aplicación.
Los guards temporales root-only no son una reducción de alcance aceptada.

La review de esta copia debe profundizar validación de frames/cursors, reserva J
con slots simultáneos/Usage escapado, cleanup al límite, deadlines UTC y saldo
estrechado, args tras hooks, datos omitidos cero IO y owners obsoletos. Las pruebas
descritas no sustituyen todos esos oráculos ni la distribución final. No SQL real,
LLM pagado, Opik, nueva resolución, consumidores reales ni cambios globales.

## Evidencia y rojos conservados

Runner existente inspeccionado `/tmp/opencode/exagent-r4-integration-run.py`,
labels nuevos r51/r52, entorno allowlist sin secretos, +S8:8, Elixir1.20/OTP29,
EXAGENT_OFFLINE=1/MIX_ENV=test/HEX_OFFLINE=1. Logs en `/tmp/opencode/exagent-r11`.
La ejecución nueva se identifica en el manifiesto del checkpoint; suite815/0/28
pertenece sólo al checkpoint administrativo y no se atribuye al root nuevo.

- r51-focal-01: dos rojos por operation_id de fixture reutilizado; se hicieron
  distintos para alcanzar la frontera pretendida, sin relajar assertions.
- r51-focal-03: FaultStore carecía del callback scan exigido por capabilities;
  se completó la fixture, no se abrió la negociación fail-closed.
- r52-compile-01/02: sintaxis de lista y uso incorrecto Message.to_json con Part;
  corregidos usando la lista Request pública existente.
- r52-root-01: `not nil` en la rama ask; corregido a booleano explícito. Writer
  redácta status/mensajes de crash porque config/deps son datos vivos host.
- r52-root-10: fixture Unicode cruzaba primero el límite JSON del comando, no el
  del record+reserva buscado; se derivó el tamaño desde el token real y su reserva.
El rojo y su diagnóstico se conservan; no se cambió el límite para pasar.

Evidencia incremental previa al checkpoint: root18/18 en
r52-stock-root-01, focal41/41 en r52-root-11 y preflight41/41 en
r52-preflight-01, seed37556 exit0. Gate root actual: compile forzado84 en
r52-root-compileforce-01 y suite833/0/28 en r52-root-suite-01, seed37556 exit0.
Formato inicial sólo detectó un salto de línea de frame.ex; Mix format lo corrigió
sin cambio de AST/runtime. Consultar manifiesto del checkpoint para la revalidación
focal/formato posterior y hashes exactos; no hay TAR/consumer nuevo en esta frontera.

## Review6a65 y corrección causal

La review fresca `/tmp/opencode/exagent-r5-review/root6a65/REVIEW.md` identificó
cuatro P2 (cinco rojos): igualdad1/1.0, cursor/outcome incoherentes, fingerprint
native que incluía módulo Ecto y límite tools actual0 omitido en resume. Owner
reprodujo los cinco en `r5-p2-review-red-01` (2/7 pasan,1 excluido recovery_pending)
y cuatro grupos permanentes en `r5-p2-permanent-red-01` (18/22 pasan).

Correcciones y comandos resolve_call/finalize_call fueron aprobados antes de su
estabilización. ADR8.34 explica fases, hashes, migración y reserva. No hay igualdad
coercitiva de payload, restitución de contador ni módulo ejecutable en fingerprint.
El frame se contrasta con el journal en ambos sentidos y el cursor con la frontera
real. Native recovery se reactivó, reconstruyendo su validator sin request repetida.

Probes **exactos e intactos** del reviewer, SHA256:

- root_review_probes_test.exs:55d9dfd106ab935fbe6193af9b49f606707d3b6a2fd44be8026d24dda503bb00
- root_recovery_probes_test.exs:e9830e1e03e19f0fe88fd212391b463caea4087d5af9bb917bb5a31a3c121db8
- root_reservation_probes_test.exs:8f4285f0a16fe7d5ffd776e0deb2a7065509e6f9924f6f36dfa548fd2a935175

`r5-p2-independent-exact-01`, seed92626, **10/10 exit0**, sin exclusión de native
recovery. El oráculo simultáneo3 tools/Usage4096/J300000 conserva tres efectos,
omisión y ledger: token rechazado613574 EFT, data pública31059, record25894 EFT /
76847 JSON. El codec Message no lleva Usage contribuida dentro de ToolReturn;
la autoridad es el ledger. La prosa de reserva se corrigió, no el codec.

Focal permanente `r5-p2-resolution-focal-02`: **34/34 exit0**, seed37556. Incluye
raw/final con hook identity/transformación/fallo/oversized, ownerkill después de ACK
raw y pérdida de ACK final, cero replay de efecto/hook, resoluciones preIO y
negativos running/confirmed/segundo finalize/status/fence. JSON exacto/+1 con actor
escapado conserva raw→final→finish; cardinalidad se añade al gate posterior.
Las cifras finales de compile/suite/formato están en el manifiesto corregido.

## Server WIP preservado para la siguiente unidad

Antes del aviso de prioridad P2 se implementó una sección inicial en
`lib/exagent/server.ex`, `lib/exagent/event.ex` y
`test/exagent/continuation_server_test.exs`, con seams en Writer/Frame: configuración
atómica de inicio, consulta/decisión/resume, pausa terminal, cola retenida y modelo/
uso restaurados sin doble suma. Dos escenarios públicos pasan: pausa→resume con
cola posterior y acumulado9 tokens, y reinicio del Server pendiente sin IO.

Este WIP **no cierra Server ni R5.7**. Falta completar y revisar reset/abort y todas
las ventanas dirty/cancel/terminales/colas de esa integración, Session y árbol de
delegación, así como gates finales y distribución. No se amplía desde aquí antes
de aceptar la raíz corregida; el relevo a contexto fresco se coordina expresamente.

## Gate del checkpoint corregido

- `r5-p2-compileforce-01`:85 fuentes, exit0.
- `r5-p2-suite-01`:850 pasan,0 fallos,28 excluidos, seed37556, exit0;127.107s de
  runner. Incluye la nueva frontera de cardinalidad raw/final (1024 exacto/+1).
- `r5-p2-format-01`:formato exit0; `git diff --check`:exit0.
- Checker local de documentación:234 enlaces en55 Markdown, exit0.
- Probes independientes exactos:10/10 seed92626 exit0, incluida native recovery;
  los hashes anteriores corresponden a los archivos realmente reejecutados.

La copia fuente/manifiesto corregidos contienen todo WIP preservado, con diff
contra root6a65 para separar el delta reparado. No TAR, resolución ni consumidor
nuevo por este checkpoint intermedio; distribución y guía de uso final siguen al
cierre integrado. El gate es evidencia owner pendiente de revalidación fresca,
no autocierre de los P2 ni aceptación de C7.

## Recepción posterior al freeze — aceptación parcial

Esta prosa se escribió **después** de congelar sourcef8b5 y no pertenece a sus bytes.
Coordinador msg_90820eaf8d7d acepta la raíz corregida PARCIAL offline y acota el
cierre de task_1d1c02dc7d4c a esta unidad, con cesión ROOT/docs/builds a contexto fresco.
Reviewer task_0ee986f3992e/ctx_7c85ffbff803, dictamen
`/tmp/opencode/exagent-r5-review/fixf8b5/REVIEW.md`: cuatro P2 cerrados causalmente,
sin P1/P2 concreto nuevo en el alcance revisado; compile85/probes10/focal35/
adyacentes27 e identidad291/291 independientes exit0. Coordinador también confirmó
identidad291 y diff-check0. Suite850 sigue evidencia owner, no ejecución del reviewer.

Artefactos aceptados e inmutables:

- source:f8b542f6f78d6d4fb59e0ac6945c658904badf14339f30b45c816b39b15cea1a
- manifest:b62f73c5383bb0463423cc098c566de76146934dce8c1c8431f352c5fc4c9453
- diff-root6a65:7468738c00c9c919e405a6b0e6128c67c513225a2f95b932d5f0cf16119bc7e0

No fase R5/C7, Server/Session completo, árbol, SQL ni distribución aceptados. El
handoff vigente concreta archivos/invariantes y pendientes; la review permanece
abierta para el siguiente freeze. Esta recepción modifica sólo roadmap, este
registro y handoff; verifica identidad del resto contra el freeze y enlaces/plan,
sin repetir suite/TAR/consumidor ni atribuir review de prosa nueva a f8b5.
