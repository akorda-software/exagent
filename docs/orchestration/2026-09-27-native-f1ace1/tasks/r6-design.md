# R6 — diseño recibido

Researcher `ses_f1acc9c45ffeqirznUvkmBkcUk`, Astra low, sólo lectura.
Padre contrastó Coordination59–128, ExAgent392–459, Frame57–168 y Writer22–118.

## Dirección aceptada para concretar

- Composición estructurada host (agente/secuencia/router/paralelo), no Model ficticio.
- Reutilizar loop, scope ancestral, journal/Writer/CAS C7; ninguna Store/máquina
  de efectos paralela. Hoy los nodos C7 se enlazan a tool-call: hace falta seam real.
- API pequeña, resultado/error parcial común; historias por hoja, no concatenadas.
- Merge orden declarado, concurrencia finita, collect/fail-fast explícitos.
- Router/mapping puros en host; decisión/input confirmado no se recalcula al resume.
- Nuevo formato discriminado/versionado; Frame3 no recibe campos silenciosos.
- Restore valida grafo↔journal, restricciones actuales, contabilidad sin repricing.

## Primera vertical propuesta

Secuencia durable A→B: A confirma output; B contiene delegado que pausa. Liberar
owner, rehidratar desde bytes, aprobar y finalizar sin repetir A ni requests/tools
confirmadas. Diseño exacto/ADR antes de estabilizar API. Router/paralelo vendrán
después sobre el mismo formato, no una secuencia efímera desechable.

## Gates

ID/version/fingerprint cambiado preIO; autoridad/contadores compartidos; pause ACK
y quiescencia; dos resumers; ACK perdido/retry exclusivamente persistencia; owner
kill/efecto incierto; bounds de outputs/journal/cleanup; lectores legacy intactos.
Review fresca de formato/continuación requerida. Nueva VM y SQL A8 quedan gates
externos separados; fixtures ETS no los aceptan.

## Archivos esperados (propuesta, no permiso ilimitado)

Coordination.Composition nuevo, seam ExAgent y ExecutionScope, Frame/Writer/
Transition y validadores Record/ScopeLedger sólo si necesario. Tests focales y
docs diseño/changelog/roadmap. No ReqLLM/Server/Session preventivamente.

## Entrega documental posterior

Worker `ses_f1ac7ec83ffe3E25IFjI5zoxzs` escribió ADR8.38, propuesta
docs/development/r6-implementation.md, changelog y roadmap EN CURSO. Padre leyó
ADR/propuesta y diff-check0. Sólo diseño, no código/tests. No bloqueo técnico ni
permiso ausente: se continúa mismo owner, ahora con primer hito de código y tests.
Record2/Frame4 son propuestas sujetas al gate, no contratos ya aceptados.

## Estado

Sin implementación ni tests nuevos al recibir la propuesta. ROOT cedido al worker
R6; smoke usa copia congelada/builds privados. Informe researcher recibido completo
en conversación; aquí se conserva decisión y criterio, no copia del log.

## Hito constructor aceptado

Worker implementó new/binding/validate_binding experimental, sin run/resume stubs
ni cambios C7. Owner49 focales. Review fresca `ses_f1ab57621fferW3f2jLhglzBYS`
encontró P2 structs truncadas→KeyError. Padre reprodujo rojo15/16, añadió regresión
y patrón de campos completos; verde50 adyacentes WA/formato0 seed37556.
Reviewer revalidó16focales y119probes sin excepciones; P2 cerrado. Fuente000831f5,
test4a3a370d. Informe /tmp/opencode/exagent-r6-review-zR92CG/REPORT.md leído.
Un intento reviewer anterior ses_f1ab85268ffesLXmQGINBsXDbz falló cifrado proveedor,
sin dictamen; sustituido por contexto fresco, no evidencia de fallo producto.
Constructor aceptado offline, NO secuencia ejecutable/restore/newVM/SQL/R6 cerrada.
Siguiente owner fresco integra runtime sin repetir este hito ni diseñar otro motor.
