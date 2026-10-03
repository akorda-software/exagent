# Recepción de gates externos — 2026-09-27

Recepción DOCUMENTAL autorizada por coordinador `msg_12a78ba009d5`, en la misma
Task `task_137a8adffbdb`/`ctx_64cb87c3a6a5`, Astra LOW. El estado único permanece
en roadmap§5; este registro conserva evidencia y límites, no activa R6/R7.
Sin runtime, builds, TAR, resolución, publicación ni consumidores nuevos aquí.

## Identidades y aceptación acotada

Base común: fuente310 SHA256
`8b3bb038e9e8ec861f87a5c32e906ff97c95ad56f5c84adc52dc1df04c171f5b` y TAR115
`ba17a600c195691062c2529e7bf7f86146b9b198a332735b6b4840f92d0ba3b6`.
G3 importa únicamente Postgres corregido SHA256
`4b89df4b0d7bc1f90a26bacd5ebde76ca6b69c3b7c36ed477cdc8966dfa386f6`;
G4/G5 prueban la base congelada, no el nuevo delta ni un candidato final posterior.

| Recepción | Evidencia identificada | Alcance y límite |
|---|---|---|
| G3 perfil real aceptado | `/tmp/opencode/exagent-g3-postgres/REPORT.md`, SHA256 `393a6631ffac7f250f333eac66a37daf2a535ac5ef5ef073f611cc2285e64c88`; `FINAL-MANIFEST.json`, SHA256 `e6ac4f23b767873fad647ec5b1575cf1b8362ec1a768ce14a435e08bfba75792` | PostgreSQL17.11, READ COMMITTED, EctoSQL3.14/Postgrex0.22.4, Elixir1.20/OTP29; no aceptación C7 independiente ni todos los despliegues SQL |
| G4 comparación APIs aceptada | `/tmp/opencode/exagent-g4-backends/REPORT.md`, SHA256 `3b8540e03d4791a592ad7e56c3d008818f45d54ab939c299e1f71871d6c3528e` | Langfuse referencia provisional; UI y ruta native-exporter→cloud end-to-end pendientes, G4 completo abierto |
| G5 tramo limpio local aceptado | `/tmp/opencode/exagent-g5-clean-consumers/REPORT.md`, SHA256 `6f97741c5a05effea139c4bcd18897c4e3d7454482646b3feccc726d32a82fd9` | Nueva resolución Hex y consumidores6/44/9/12; CI remota/revisión final/matriz restante pendientes, no G5 completo |

### G3: durabilidad y falso ACK

21 casos distintos (8 primitivos,3 runtime,7 retry,3 Model recovery), más probes
de tokens entre VMs, árbol depth2 entre VMs y reinicio PostgreSQL, crash VM real,
red cerrada tras COMMIT antes del ACK y backup/restore29 envelopes. Oráculos:
un ganador CAS, receipts/revisiones conservados, journal sin efectos repetidos,
owner obsoleto rechazado, incertidumbre visible, costes históricos sin repricing.
El perfil nominal usa RLS desactivado; los negativos fijan rol restringido y
política DELETE false, además de trigger supresor. No certifica HA/failover,
SERIALIZABLE, pérdida física del host, transacciones entre filas ni exactly-once.

Los mismos probes intactos `g3_rls_probe.exs` SHA256
`456aff0bc84f294fac87d3b8faf03443ff24557067dbc5367696a8b4d2312754` y
`g3_delete_controls.exs` SHA256
`ef48bbd9cabfdafce915ac121669f883f508d105f940c37075498a3350eeb821`
pasaron de exit2 a exit0 con SQL4b89. `delete-strict-fixed-01` verifica exactamente
conflict, fila íntegra conservada, prune informa error y control permitido borra.
Primitivos8/runtime3 reejecutados sobre el fix; otros resultados reutilizados por
identidad, sin afirmar rerun total. Contenedor/volumen/red/DBs/password sintéticos
eliminados por G3; puerto5560 y socket liberados, evidencia/backup conservados.

### G4: comparación y trabajo pendiente

Ambos proyectos cloud autorizados recuperan74 spans/15 trazas sintéticas con
parentesco y privacidad comprobados. Langfuse conserva IDs OTLP y tipos tool/agent;
Opik regenera IDs, conserva el árbol tras correlación y proyecta diagnósticos en
input y tools como spans generales. La preferencia provisional responde a estas
diferencias medidas del perfil neutral, no a capacidades universales o gusto de UI.

La evidencia es ejecución ExAgent→exporter nativo→captura OTLP local, seguida de
relay de esos bytes→ingestión/readback cloud; no es transporte directo aceptado.
Coste estimado cualificado permanece en atributos, campos de coste backend nulos,
sin doble suma de agregados; no prueba factura real ni toda la matriz missing/zero.
Builds cloud y funcionalidades de plan contratado no se verificaron.

Gaps R7 demostrados: pause exporta succeeded aunque resultado paused; faltan
correlaciones approval/attempt. Quedan ownership/lifecycle exporter1.10, booleanos,
partial_success, saturación/pérdida/recuperación, uso/coste cualificado y UI
autenticada. Se planifican, sin corrección runtime dentro de esta recepción.

### G5: resolución nueva y CI pendiente

Cuatro consumidores físicos sin lock/deps/BEAM de ROOT resuelven en Hex oficial y
prueban el TARba17: mínimo6/runtime44/extensible9/SQL opt-in12, cero fallos/skips/
exclusiones, seed771506. ReqLLM1.24.0/Req0.7.4/Finch0.23/Mint1.10.1;
117 módulos por perfil con procedencia local comprobada. No SQL real en ese perfil.
Bootstrap mínimo del runner portable también pasa desde homes vacíos. Warnings
upstream visibles: no gate global warnings-as-errors ni mínimo1.18 revalidado.

Propuesta privada de cuatro archivos CI/runner/graph/names NO integrada. CI remota
sobre commit exacto y candidata final tras R6/R7 permanece pendiente; ejecución
remota histórica fallida no acepta estos bytes. No commit/push/publicación aquí.

## Bloqueos recibidos y siguiente frontera

- **G2 mínimo rojo:** stock1.24 live marca argumentos inválidos tras primer fragmento
  vacío aunque el JSON final sea válido. Recepción final `msg_03c769f7cc13` incorpora
  el anexo oficial1.25 offline: mismo defecto derivado por APIs públicas
  stream_text/process_stream con TCP sintético, sin inyectar flags. Control name-only
  válido admite; JSON final truncado rechaza. Tres requests TCP, cero LLM/coste nuevo;
  las18 admisiones reales previas permanecen. Conservar guards, sin upgrade ROOT,
  fork/parche ni degradación silenciosa a buffered/native. La Task de diagnóstico
  terminó correctamente; el gate G2 no pasó. Autorización y credenciales disponibles
  no resuelven este bloqueo técnico.
- **Review C7 bloqueada:** segundo rechazo del servicio del reviewer, sin dictamen
  final ni aceptación independiente. `model-binding-probes.log` falla por fixture
  KeyError (`output` frente a `output_type`), no confirma P2 de producto. No presentar
  ausencia de dictamen como review favorable ni reintentar eludiendo el rechazo.
- Publicación autorizada únicamente DESPUÉS de los gates; hoy bloqueada por G2 y
  review, además de trabajo restante del plan. Ownership ROOT/docs/builds retenido
  por este owner hasta cierre/cesión expresa; checkpoint y prompt siguen del coord.

### Identidad del anexo G2 recibido

- `/tmp/opencode/exagent-g2-openrouter/REPORT.md` (Appendix252+), SHA256
  `69eecb0f382cf56a7d696c978d7604406cbd33c95eb083e2a28c35c889a3c47a`.
- Informe original preservado `REPORT-1.24.md`, SHA256
  `7caf0bb9dea22563a110b4cb2ec6d1d79d8ccd672deb86b0935e00dcb46aa24f`.
- `consumer125/repro.exs`, SHA256
  `297667bca8dabe6baed71449187595e53a0209522bb079e32e19dd37148bc855`;
  lock privado SHA256
  `76b8cd893654c2343b2c9f1ad1dd36baebf7c29ebae051757a97f624ecee7ff7`.
- `consumer125/verification.json` registra278 archivos stock idénticos al paquete
  oficial y fuente310 de su base/lock conservados. Esto no afirma que el ROOT actual
  sea idéntico a la fuente congelada: ROOT contiene el fix4b89 y deltas documentales.
  ReqLLM1.25 se evaluó sólo en consumidor privado; no integración ExAgent1.25 aceptada.
