# R6 persistencia — hitos y cambio de estrategia

## Scope aceptado

Owner `ses_f1aaecc76ffeDNHivDh90V4NXA`: start_structural sin Model raíz, mismas
restricciones/ledger/restore JSON sin repricing;8 tests nuevos. Informe
/tmp/opencode/exagent-r6-structural-f1aae/REPORT.md; owner54focal/compile94/full971pases
28excluidos WA. MIX_BUILD_PATH explícito requerido por test nuevaVM preexistente.
Reviewer `ses_f1ab57621fferW3f2jLhglzBYS`:54focal/probes/hashes7/7 sin hallazgos;
/tmp/opencode/exagent-r6-scope-review-Zikgjb/REPORT.md. Padre leyó delta y hashes.

## Intentos sin avance

- `ses_f1a99ef77ffekkIaeHOmQ2vA3o` Astra low: inspección, cero edits/tests,
  sin bloqueo técnico. No se contabiliza como avance.
- Comodín `anthropic/claude-opus-5-5#high`, `ses_f1a975fb3ffeBMjmwFi4JksWBi`:
  OAuth refresh failed antes de trabajo. Usuario informado de `claude` en terminal;
  no manipulación global/credenciales. Sigue bloqueado, no reintentar ciegamente.
- Cambio estrategia: unidad reducida a raíz vacía, sin exigir toda secuencia.

## Raíz vacía aceptada

Owner `ses_f1a965a98ffe5XQfyn4I9v2lin`: mismo Writer/Checkpoint/Transition/Store,
Record2/execution2 composition/Frame4 empty/StructuralSnapshot1, creación/claim/
JSON roundtrip, rechazo explícito hojas/finish/operaciones todavía no implementadas.
Informe /tmp/opencode/exagent-r6-root-f1a965/REPORT.md; 8tests nuevos,92focal,
compile95/suite979pases28excluidos WA seed37556, no providers. SHA11/11 verificados.

Review fresco `ses_f1a84411fffeuRRhT4st6rtPc0`:21focal verdes, probes3/5:
P2 preflight de reopen proyectaba record nuevo en lugar del persistido; on_writer
se ejecutaba antes de receipt_limit/expired. CAS sin corrupción, no efectos hoja.
Padre añadió2regresiones permanentes (filas JSON/ETS), reprodujo8/10 y cambió sólo
structural_claim_capacity(record || projected, config). Segundo claim ya rechaza
preIO sin Writer creado, como exige contrato. Verde94focal WA/formato0.
Revalidación reviewer28/0=5probes originales+23focales; P2 cerrado sin hallazgos.
Informe actualizado /tmp/opencode/exagent-r6-review-f1a844/REPORT.md, hashes
SHA256SUMS-recheck11/11 cotejados por padre antes de recepción documental.
No full suite después del fix de una expresión:979 es evidencia owner anterior,
94/28 son gates post-fix. Cero procesos propios en las entregas.

## Próxima unidad y límites

Hoja por step real (no call/request ficticia), input confirmado antes de activar,
loop existente bajo Writer/Scope raíz, output confirmado/cursor; grafo↔journal y
legacy intactos. Después A→B/delegado/pausa/resume/nuevaVM. No engine/Store paralelo.
Hasta entonces raíz vacía no equivale a composición ejecutable ni cierre R6.
