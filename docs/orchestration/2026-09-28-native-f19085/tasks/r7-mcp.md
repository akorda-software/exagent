# R7.4a MCP HTTP aislado

Researcher ses_f17ca2cb7ffetsGZ4wJWrlHt2c terminado sólo lectura.
Decisión provisional implementación: adapter pequeño sobre Finch0.22 existente,
HTTP/1.1 MCP2025-06-18, no dependencia nueva ni cambios stdio2024-11-05.
Anubis2.0.0 mantenido pero transporte inspeccionado materializa cuerpo antes de SSE;
adaptarlo no resuelve límites. Sin fork/internals. Contrastar fuentes al implementar.

ROOT exclusivo Frame8; observabilidad tiene otra copia privada. Intención worker
general exclusivo copia NUEVA /tmp/opencode, fuentes WIP estables hash-verificadas,
deps/build/rebar propios, sin enlaces a fuentes/build mutables ni secretos copiados.
No integración ROOT. No cloud/paid/SQL/infra/commits ni cambios globales.

Allowlist en copia:
- lib/exagent/mcp/client.ex
- lib/exagent/mcp/streamable_http.ex
- lib/exagent/mcp/streamable_http/{sse,message}.ex
- test/exagent/mcp/streamable_http{,_sse}_test.exs
- test/exagent/scenarios/mcp_http_authority_test.exs
- test/support/mcp_http_server.ex
- docs/development/r7-mcp-implementation.md

Client mantiene pending/deadlines/callers/admisión/terminal único. Workers HTTP
monitorizados, correlación generación+request+worker; no IO dentro GenServer.
Finch público stream_while, pool app-owned HTTP1; sin tocar Application/mix/lock.
JSON y SSE incrementales acotados; bytes/line/event/total/discovery/control con cotas,
deadline total monotónico, sin renovar por progress, redirects o POST retries.
Initialize2025-06-18 validado -> initialized202 -> ready; IDs exactos JSONRPC y
result/error excluyentes. Ping y error para requests no soportadas; sin sampling.
Paginación acotada o rechazo explícito, nunca catálogo truncado como completo.
Cabeceras por instancia, URL sin credenciales, reservadas controladas por adapter;
sesión sólo initialize válido, ASCII visible acotado; no logs secretos.
404 sesión invalida generación y pendientes; handshake nuevo SIN replay de tools.
401/403 explícitos. Cancelación best effort acotada nunca initialize; close DELETE
acotado/405 permitido, muerte abrupta owner limpia workers/sockets. Un timeout no
prueba rollback remoto. No GET espontáneo, Last-Event-ID, OAuth ni versión2025-11-25.

Tools normales preservan schemas/validación/allow-ask-deny/C7; call_tool directo no
es autorización runtime. Binding endpoint/principal debe ser host confiable: si falta
seam, bloqueo explícito sin tocar Frame8 ni fingir aceptación C7. No serializar sesión.

Matriz local: handshake JSON/SSE, bytes HTTP reales, auth aislada2clientes, framing
fragmentado/UTF8/CRLF/multidata, negativos IDs/version/content-type/status/EOF,
concurrencia/max_pending, cotas exacto/+1, timeout/caller-death/client-kill/close,
cancel/404/stale generation y cero replay; permisos y pausa cero efectos, save retry
sin replay donde APIs actuales lo permitan. Barreras/journal externos, no sleeps.
Fixture loopback efímera puerto0, no servidor desarrollo persistente ni asignación
de puerto registrado. Interoperabilidad SDK independiente posterior, no aceptar A9.

Gates focales nuevos + MCP stdio/schema/permisos intactos, formato/compile offline
en copia. No FULL rutinario Frame8 transitorio. Entrega REPORT/patch limitado,
baseline/delta/hashes/comandos/exits/rojos y propuesta docs4 privada, procesos liberados.
Revisión fresca e integración sólo tras ROOT liberado; R7.4 parcial, no gate cerrado.

## Recuperación de sesión dañada

Worker ses_f17c61409ffeYnC1K5myGjPvvJ ERROR invalid_encrypted_content; no continuar
esa conversación. Snapshot recuperable `/tmp/opencode/exagent-r7-mcp-7xhyz66_/snapshot0`,
artifacts contiene baseline/manifests/runner y focal.json con exit0 (no aceptación
del padre ni entrega completa). Proceso inspeccionado tras notificación: sólo tres
BEAM ajenos y FULL Frame8 ROOT, ningún build MCP. Preservar todos los artefactos.
Intención worker fresco continúa snapshot existente, verifica delta/ownership/gates
y termina mandato sin recopia ROOT ni reiniciar baseline; no integración autorizada.

## Decisión tras preflight recuperado

Reemplazo ses_f17bffb92ffe8QCbNB10cam3Hz terminó: HTTP ausente, sólo4tests nuevos,
81focales/compile102/formato exit0 owner, sin procesos propios. Padre leyó REPORT y
probe fingerprint y verificó SHA256SUMS completo. REPORT SHA
0386cfe861f403f6b0addc0635118db80992f704828ff38a5221035e439784cd;
delivery.patch bde285b16de2f2059b4aeaac0fb19dab4113fa6e77aa3b49f412fac304b12e95.
NO aceptación HTTP ni C7, no integrar preflight como feature.

Se separa bloqueo binding automático C7 de implementación transporte. Continuar
mismo owner/copia para HTTP funcional y matriz transporte/permisos; C7 endpoint/
principal queda gate explícito pendiente. No autorizar seam Tool/continuation.
No afirmar fingerprint protege destino ni nueva sesión autoriza replay. Referencias
host existentes son dirección a cualificar después, no garantía ya probada.
HTTP1 es precondición confiable del pool app-owned, no introspección demostrable:
documentarla y probar fixture HTTP1; no prometer autodetección/rechazo de pools HTTP2.
Ninguna de esas dos limitaciones impide implementar transporte standalone. Se mantiene
allowlist/aislamiento/gates y todos los límites de lifecycle, sin ampliar runtime.
Preservar entrega preflight sellada; nuevos artefactos bajo artifacts/transport/.

## Entrega HTTP recuperada tras segundo error de contexto

ses_f17bffb92ffe8QCbNB10cam3Hz ERROR invalid_encrypted_content, no continuar sesión.
Sí dejó artifacts/transport/REPORT.md funcional, leído padre, SHA
0dd215d32a5747b1723e18bb67d2bb95dd5b6fb18c3e2221e101b296453de824;
delivery.patch e261e7475775eefdbc8669e02a3deff93682ed04dfe82f7af8d9872fc6f83964.
Owner114focales/compile106/formato0,9rutas acumuladas; HTTP implementado según informe,
no aceptación aún. Padre verificó SHA256SUMS transporte y preflight completos.
Primer chequeo preflight ejecutado desde cwd transporte falló por rutas relativas;
repetido desde artifacts correcto todo OK, no corrupción demostrada.
Procesos: sólo3BEAM ajenos y FULL ROOT Frame8, ninguno MCP. REPORT confirma commands
síncronos terminados y process-cleanup vacío. Copia/build MCP liberados.
Intención reviewer fresco exclusivo copia MCP, sin corregir, comprobar fuentes/delta/
baseline reconstruido por hash y evidencia HTTP real/límites/cleanup/no replay.
No integración ROOT, sin repetir implementación ni reusar sesión dañada.

## Review HTTP: P2 segmentación SSE

Reviewer ses_f179dea7fffeeXpWyv8h7HYGtq TERMINADO, BUILD liberado; padre leyó
artifacts/review-fresh/REPORT.md y cotejó SHA
9adf3f3c27da556f5f7854b8ac1b716597949553337cfaddb18192484e2898ba.
114focales/compile106/formato0, probes5/6 exit2. SSE.feed procesa chunk completo y
pierde eventos completos si sufijo falla. TCP real terminal válido+comentario257B
con max_line256: split éxito, coalescido sse_line_limit. P2, no replay demostrado.
No aceptar ni integrar. Intención worker FRESCO (owners previos dañados) corrige sólo
MCP parser/transporte/tests necesarios en misma copia, sin ampliar allowlist ni tocar
ROOT. Históricos inmutables, artefactos nuevos artifacts/fix-sse/. Repro intacto
antes/después; si probe observacional parser antiguo entra en conflicto con cambio
API interno, conservar original y documentar equivalente contractual sin ocultar rojo.
Terminal debe ganar sin procesar suffix; errores previos terminal/cotas antes de él
siguen rechazando. Probar particiones UTF8/line/event/multievent/control y cleanup.
Focales+compile/formato y nueva entrega sellada; revisión independiente posterior.

Fix worker ses_f179648ebffe8PGjQrrhlDupPT TERMINADO, build privado liberado.
Padre leyó artifacts/fix-sse/REPORT.md SHA
2a5942be15e09268c512ab27f44d58d966922a2f8f1df29726788a2a0df5b943 y cotejó
SHA256SUMS completo; patch acumulado ffb311e86bfb933daa4337408bc1b59af15c6aa518da002c33354ad08f7e8bc7.
Owner probes intactos5/6→6/6, focal121/121 compile106/formato0. Nuevo next/2
event-at-a-time y presupuesto hasta terminal; feed/2 full-input conserva API y
probe observacional.5rutas delta (2runtime/2tests/doc). No aceptación aún.
Intención continuar reviewer original exclusivamente copia/build MCP y artefactos
nuevos review-validation/, sin sobrescribir históricos; confirmar P2 y límite bytes.

## Aceptación privada acotada

Reviewer ses_f179dea7fffeeXpWyv8h7HYGtq TERMINADO favorable,6probes originales+
121focales+2oráculos suplementarios; compile106/formato0 independientes.
Padre leyó artifacts/review-validation/REPORT.md SHA
28bd6c20a788c415317b2cc02185705610a590eec70a1a5dc1d19f4938c2ca7a cotejado,
patch acumuladoffb311e8 y probe originalc1088d82 cotejados;397/397 fuentes verificadas.
Padre ejecutó personalmente8probes (6intactos+2suplementarios), exit0 WA48seed37556,
logs/receipt review-validation/parent-probes.{log,json}. MCP HTTP unidad privada
ACEPTADA offline; no integrada ROOT ni cierre R7.4/A9, C7 binding/SDKinterop pendientes.
ROOT integrador Frame8+OTel activo; no ampliar su scope en caliente ni pisar build.
Después de entrega/revisión integrada, comparar Client ROOT baselinefcc1aecf y ausencia
paths nuevos; integrar patch acumulado9rutas + consolidación docs en unidad propia.
Copia/build MCP libre. No necesidad de repetir implementación ni review ya aceptada.
