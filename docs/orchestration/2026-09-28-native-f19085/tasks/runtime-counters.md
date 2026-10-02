# Contadores runtime-owned entre hooks Model

Unidad de productor aprobada, no formato/control durable ni apertura restore.
Base batch cardinalidad aceptada; usage/control legacy siguen ambiguos.
Contexto completo en retry-control-contract.md y diagnósticos inmutables:
`/tmp/opencode/final-tools-diagnostic-f185cb0f/REPORT.md` (hooks cambian contadores).

## Contrato exacto

En before_model_request y after_model_request, preservar valores runtime confirmados
de tool_retries, output_retries_used, run_step, tool_calls, max_steps y el límite
agent.output_retries. Normalizar después de CADA capability, antes de la siguiente
y de admisión/capture/Model/Writer. No sólo al finalizar retained_transform.
Valores siguen observables, escrituras ignoradas restaurando confirmados (patrón
actual retención), no API de override ni modo legacy nuevo. Hooks trusted, no sandbox.

No congelar agente completo, modelo, settings, tools seleccionadas, request_messages
ni transformaciones after de respuesta válidas; conservar identidades/retención/
history/bindings/validación existentes. Protección acotada al estado real de Run:
no romper uso de Capabilities con mapas genéricos ni inventar campos en ellos.
No convertir resultados inválidos de hooks en válidos por defaults o coerción.

Cambio observable de comportamiento documentado en Capability, diseño y changelog
para major pendiente, sin bump/publicación. Refs/formatos/lectores legacy intactos;
no forzar conteos derivados a registros anteriores ni afirmar integridad nueva
del persistido. No cambiar tools.max_retries seleccionables por request ni los
otros contratos de authority/limits; este alcance son exactamente seis campos.

## Alcance y gates

Owner exclusivo ExAgent/Capability(s) y tests de hooks/runtime/counters, docs4
design/changelog/roadmap/r6-implementation; padre status/memoria. Mínimo seam/helper,
sin refactor general Run/DSL/engine ni cambios Frame/Writer/Scope/Message/Outcome.
No schema evidence nuevo, no restore prefijos/tools ni BatchResolution aún.

Guardar baseline/hash/delta/informe temprano /tmp/opencode nuevo. Repro causal antes
fix: reset/contaminación tool_retries en before/after; segundo callback ve alterado.
Matriz before/after×seis campos, dos capabilities ordenadas, límites agotados no
recargados, requests/runstep/tool_calls observables, contador retry real/reset success;
transformaciones legítimas conservadas, módulo/struct callbacks, mapas genéricos,
errores sin IO indebido. Runs directos y composición con persistencia real, snapshot/
intent no contienen contador manipulado; original refs/floors intactos. No tests
que únicamente llamen helper privado y den por probado runtime.

Diagnóstico original no sobrescribir (genera JSON path fijo). Si reaprovechar probe,
copiar/parametrizar artefactos y conservar rojos. Guards usage/retry persistido quedan
pendientes; no relabelar fixture vieja como corregida ni exigir contador derivado.
Focal/compile forzado/formato/FULLoffline WA48seed37556 con prefijo environment/
MIX_BUILD_PATH absoluto, timeout≥600000, sin serializar/relajar guard/timeouts.
Review fresca posterior; no pagos/SQL/global/infra/consumidores/commit/bump/Orca.

Owner general `ses_f182db467ffefsVtFIs85tx266` background ACTIVO, único producto/
build ROOT y docs4. Padre memoria/status. Entrega pendiente.

Notificación completed parcial: owner dice FULL aún ejecutando y ROOT reservado.
REPORT `/tmp/opencode/runtime-counters-f182db46/REPORT.md` leído por padre hasta70:
rojo causal4/4, matriz44/focal371/compile101 owner, FULL sin cierre. No aceptación
ni liberación inferida. Intención continuar MISMO owner para cerrar gate ya lanzado,
sellar hashes/docs e informe final; no relanzar FULL ni duplicar procesos.
Continuado `ses_f182db467ffefsVtFIs85tx266` background ACTIVO para completar entrega.

## Entrega final posterior

Mismo owner TERMINADO, ROOT libre. REPORT SHA
fab99f9e5f4eda8e1e626e51aa0b8cac60df5bd9bc14216ac76e2784a9d1a230
cotejado/leído por padre; source15/15 intacto y sólo3BEAM ajenos. FULL ÚNICO
1354pases28excluidos482.0s exit0 (sin relanzar);44matriz371focal/compile101/formato0
owner. Runtime sólo Capability(s),2tests+docs4. Review fresca pendiente, NO aceptación.
Intención revisor general sólo lectura producto, ROOT exclusivo; no FULL redundante.
Reviewer `ses_f1815c1c6ffe9qBuCLFKjrFFmg` TERMINADO favorable,124focales+8probes.
Padre leyó informe/fuente, cotejó15/15 y reejecutó8probes intactos WA48seed37556
exit0,0.3s. Informe `/tmp/opencode/runtime-counters-review-f1815c1c/REPORT.md`
SHA68b62e7780418bb22870da58dc875ce5a5e27ace75b92369743b1e4ef80a4f1a.
ACEPTADO productor offline; docs5 recibidas después del manifiesto. ROOT libre.
Legacy usage/retry rojos y guards intactos, no formato/control durable aún.
