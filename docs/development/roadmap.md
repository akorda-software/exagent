# Roadmap ejecutable de ExAgent v2.0.0

**Actualización2026-10-02:** implementación v2 activada por el usuario; R6/R7
implementados en los perfiles acotados y mínimo R1 cualificado mediante G2 real.
Candidata común con pruebas locales, SQL, consumidores, frameworks, SDK y carga.
Langfuse G4 aceptado en la sesión autenticada autorizada; la revisión única R9
está cerrada. El usuario amplió el alcance el2026-10-02: Opik debe tener el mismo
nivel de validación nativa/API/UI. Ambos pasan nativo/API33/33 y UI12casos/248attrs
en el perfil A10 finito. CI run02 falla en las suites completas; las correcciones
causales están comiteadas. Run03 pasa ambas suites completas:2176pases/0fallos/
28excl por runtime, exit0; diagnóstico strictdeps rojo upstream. Guards intactos.
Fuente única de
estado y orden de trabajo. El [alcance](release-scope.md) define producto/garantías;
la [matriz de aceptación](production-acceptance.md) define cómo se demuestran.
El relevo vigente está en `docs/prompts/continue-native.md`; los anteriores
conservan contexto fechado. Su lectura como contexto no amplía un encargo.

**Entrada vigente2026-10-02:** `docs/prompts/continue-native.md` (sólo checkout)
y [flujo simplificado](execution-flow.md). Los siguientes hitos fechados conservan
evidencia, no reactivan investigaciones, revisiones ni probes del padre ya cerrados.

**Rutina local2026-10-02:** el usuario elige validar antes de commit/push en su
máquina y evitar suites automáticas por push/PR. `bin/check` reúne formato,
compile estricto/probes, suite offline, ExDoc y TAR/aislamiento; consumidores
limpios con `--package-consumers`. CI remota queda manual en la rama del PR,
con seis jobs conservados; `main` cambia al integrar.22integration+6postgres
son filtros offline, no timeouts. Ver [verificación](verification.md).
Rutina comprobada una vez:8fases exit0,2176pases/0fallos/28excl; suite1979.7s
y total2024.1s. Casi todo el tiempo sync; no se demuestra aceleración20×.
Control negativo whitespace exit2 antes de Mix y opciones desconocidas exit64.
Fuente runtime intacta respecto a f69aede; sin re-review ni nuevas llamadas reales.

**Documentación de uso2026-10-02:** encargo explícito de páginas útiles para personas
y agentes. Portada ExDoc, diez guías por tarea, mapa de APIs para agentes y grupos
de navegación por uso/integración/referencia/mantenimiento. El estado actual se
resume sin pendientes obsoletos; su cuerpo anterior queda íntegro en el archivo.
HTML/EPUB conservan ExDoc stock; el formatter Markdown público reubica los enlaces
relativos y protege snippets, con regresión de tooling. `llms.txt` sigue siendo
generado por ExDoc. `bin/check` incorpora `docs-links`; este delta documental se
verifica con sus gates, sin volver a ejecutar FULL ni cualificaciones externas.
ExDoc estricto exit0:116HTML/5135targets,114Markdown(incluido llms)/811targets
y114XHTML EPUB/2837targets, cero enlaces/anchors/recursos locales rotos.
Probe17casos:30bloques ejecutados y11setup parseados, cero warnings. Navegador:
36vistas desktop claro/oscuro y móvil, búsqueda/teclado/sidebar pasan sin errores.
El TAR documental y sus checks de metadata se sellan en el recibo del objetivo;
no se sustituyen los SHA del CI o de las candidatas funcionales anteriores.

**Git/CI030 autorizado2026-10-02:** commit inicial `b709d57` en
`codex/v2-candidate-029`, [PR1 borrador](https://github.com/akorda-software/exagent/pull/1)
y [run37008908156](https://github.com/akorda-software/exagent/actions/runs/37008908156).
Run inicial: paquete/harness pasan; suite1.18 falla por Regex compilada y warnings
de layouts constantes, y suite1.20 se cancela con el siguiente push. Corrección
`dad90ff`: formato canónico1.20, fixtures runtime,178restore+4stream strict en cada
runtime y165testfiles118 compilados sin warnings, sin ejecutar sus bodies.
[Run02](https://github.com/akorda-software/exagent/actions/runs/37010288171) sobre
ese commit: compile ambos/formato1.20/harness/paquete pasan; consumidores remotos
56contratos/0fallos/0excl y comandos exit0, strictdeps rojos TOML/WebSockex/gproc.
Suites118/120 alcanzan timeout3000s con76/72fallos anteriores, sin totales finales:
54rutas temporales no portables y un build env obligatorio por runtime; fanout
espera cinco workers con cuatro slots; JSON-cap depende de latencia ETS; otras
reanudaciones vencen y requieren diagnóstico. No subir deadlines ni contar como
verde una suite cortada. Correcciones causales cerradas: tmp_dir/build real,
barrier por oleadas, oráculo JSON/EFT independiente de IO y menor coste de
normalización/canonicalización conservando bytes/errores/guards. Focales cerrados:
27portables+7fanout+3JSON/EFT por runtime;79casos distintos118/90en120 del frente
de normalización, incluidos55boundaries y ochoSequence corregidos por nombre.
Diferencial1015/1020vectores exacto en ambos;81ACK27.205s→18.968s perfilados.
Una inspección independiente del padre0findings; sin re-review. Correcciones
comiteadas y subidas en `f69aedea1a2f7c94c546fa95b631a71664110b4d`.
[Run03](https://github.com/akorda-software/exagent/actions/runs/37019949320), lanzado
14:27:03UTC, pasa paquete/harness y56contratos consumidores,46comandos exit0;
strictdeps rojos. Ambas suites completas pasan con warnings-as-errors:
2176pases/0fallos/28excl por runtime;1.18 en2706.4s,1.20 en2072.4s. Compile
ambos y formato1.20 exit0; cero compilerwarnings en tests. Las377fuentes de
cada artifact coinciden con el commit. Jobs completos46m20s y35m33s.
TAR SHAeff31a95803c414657333e1344831fcb8b7099460c481a664a3e4b0828fdbd3f:
153archivos exactos al commit. Restricción temporal14:39–14:44UTC impide lecturas;
el usuario restablece acceso14:44UTC y gh confirma ambas suites aún en curso.
Run final **failure** exclusivamente por warnings stock en jobs consumidores:
TOML15(1.18); TOML19/WebSockex19 y gproc9(exporter) en1.20. Sin warnings
ExAgent, supresión, fork ni actualización forzada. Conservar seguimiento upstream
y G5strict abierto; no afirmar CI global verde. Recibos: `ci030/run03/`.
Sin bump/tag/Hex; la pipeline de
publicación será posterior. Recibos privados en `ci030/run02/` y owners disjuntos.

## 1. Dirección y condiciones de cierre

- ExAgent conserva runtime/Model pequeños; **ReqLLM oficial stock será el backend
  principal**, sin fork/vendor/patch/monkeypatch/parser wire privado ni runtime Jido.
- Aprovechar patrones de Jido sin importar su runtime: transiciones explícitas,
  ownership, identidad estable, contexto proyectado y continuación controlada.
- **C7 entra en v2 por confirmación expresa del usuario en esta planificación:**
  aprobación humana persistida y continuación acotada. Sustituye su aplazamiento.
- Las apps actuales son pruebas de concepto y no condicionan el paquete. Se prueban
  consumidores genéricos de APIs públicas, no migraciones de esas aplicaciones.
- Objetivo: **v2.0.0 apta para producción en los perfiles y combinaciones aceptados**,
  con extensiones para otros escenarios. No se certifica cualquier provider,
  despliegue distribuido o efecto externo por pertenecer al catálogo de ReqLLM.
- Tener todas las casillas de implementación no sustituye aceptación externa,
  revisión de candidata y comprobación del artefacto distribuido.

La versión nominal sigue siendo1.3.0; este plan no hace bump ni publicación.
R0–R9 sustituyen H1–H6/H3.0. El plan y alcance anteriores, con evidencia intacta,
están en `docs/archive/2026-09-release-{roadmap,scope}.md`.

## 2. Tablero y dependencias

| Fase | Resultado | Depende de | Estado |
|---|---|---|---|
| R0 | Checkout, baseline y ejecución recuperables | Activación del agente | Verificada2026-09-21 |
| R1 | ReqLLM stock cualificado y transporte duplicado retirado | R0 | Mínimo chat_tools_v1 aceptado offline y G2 real14/14 con GPT-4o-mini vía OpenRouter; otras capacidades siguen según su matriz |
| R2 | Contratos del núcleo y extensiones cerrados | R1 | Aceptada offline2026-09-26; base y R2.3 con review independiente |
| R3 | Runtime, contexto y coordinación operables | R2 | Aceptada offline2026-09-26 tras revalidación independiente R3.4; gates externos abiertos |
| R4 | Persistencia y primitivas de continuación atómicas | R2; integración R3 | Base offline y G3 real14fases sobre candidata019: restart, ACK perdido, dos resumers, backup/restore y cleanup observados |
| R5 | Aprobación persistida y recuperación de ejecución | R3 + R4 | C7 ordinario/composición/MCP integrado; G3/FlowA8 y Oban SQL prueban pausa/resume y recuperación explícita sin replay en sus perfiles |
| R6 | Composición multi-agente coherente | R3; R4/R5 para pausa durable | Implementado y revisado: secuencia9/delegación10/Flow11. Final00973+11; recetas públicas PASS y A8 SQL entreVMs sobre019. FULL2157sin fallos; guards generales no demostrados siguen cerrados |
| R7 | Observabilidad e integraciones utilizables | R1/R2; cierre sobre R5/R6 | MCP SDK5/5, binding, retrieval/job y LiveView/Oban6/6; Langfuse y Opik A10 nativo/API/UI aceptados con los mismos criterios por mandato2026-10-02 |
| R8 | Cualificación externa, consumidores, carga y CI | R1–R7 pertinentes | G2mínimo/G3/G6 aceptados; ocho grafos56contratos pasan también remotamente. CI030run03: paquete/harness y ambas suites completas verdes;2176pases/0fallos/28excl por runtime. Strictdeps RED upstream |
| R9 | Revisión final, candidata y release2.0.0 | R0–R8 aceptados | Revisión única cerrada y candidata029 preparada; PR1 borrador autorizado. CI030 funcional aceptado; run global failure sólo por diagnóstico strictdeps upstream. G5strict abierto, sin versionar ni publicar |

```text
R0 → R1 → R2 → R3 ───────→ R6 ──┐
             └→ R4 → R5 ────────┼→ R8 → R9
     R1/R2 ──────────────→ R7 ──┘
```

R4 puede diseñarse tras R2 mientras se cierra R3. R7 y la preparación de entornos
R8 pueden avanzar tras R1/R2; su cierre debe incluir pausa/reanudación y composición.
Orden por defecto para un agente único: R0,R1,R2,R3,R4,R5,R6,R7,R8,R9. Un bloqueo
externo permite pasar a una unidad cuyos prerrequisitos reales sí estén disponibles.
Dependencias de cierre no prohíben preparar interfaces o fixtures antes.

## 3. Método de ejecución y economía de tokens

**Método vigente2026-10-01:** objetivo funcional → implementación/focales →
como máximo una revisión del delta acumulado → correcciones/regresiones → seguir.
Sin re-review ni rerun rutinario del padre; una suite integrada al estabilizar,
no por microsubset. [Política completa](execution-flow.md). La capacidad de
agotamiento10 recibió review favorable y rerun padre7/7 antes de este cambio;
su P1 interno queda cerrado, sin nuevos tests ni aceptación VM/producto.
Recepción/evidencia única en [R6 implementation](r6-implementation.md).
Los «pendiente de review/padre» de las entradas fechadas inferiores son históricos;
el estado de ejecución vigente está en CURRENT y el tablero§2.

### Cualificación común — 2026-10-02

Fuente funcional: candidata019, nominal1.3.0, TAR SHA256
`4629a1f2d22669b5fc352dcb62b8711cf11a4a2940a0c1fa25f3e98a8611c233`,
152 archivos distribuidos y lock33a222bf…f2bc. Los recibos de cada perfil conservan
fuente, comandos, exits y cleanup. La revisión R9 cubre sólo integración/deltas
nuevos; las unidades ya revisadas conservan su dictamen único.

- **G1:** FULL2157pases/28excluidos, cero fallos funcionales,2276s; exit1 por
  warnings de fixtures y adapters función Req. Corrección causal sólo de tests:
  adapter módulo público con aislamiento Registry y filtro de la app consumidora;
 136focales pasan, exit0 y cero warnings. Se conserva FULLestricto rojo y no se
  repite por estas correcciones. ExDoc real corregido104páginas/2620targets,
  cero enlaces propios rotos; la actualización documental final se sella aparte.
- **G2:** catorce casos reales del perfil mínimo con GPT-4o-mini/OpenRouter,
  ReqLLM1.24 stock,17admisiones/3efectos, concurrency1/retries0. Admisión20requests/
  USD0.50; reserva observadaUSD0.425, factura no observada. No otros providers
  cualificados ni nuevos reruns pagados.
- **G3:** PG17.4 real,14fases, pérdida COMMIT/ACK, dos resumers con un winner,
  FlowA8/crash/restart/freshVM y backup/restore de su DB. SHOWstatement_timeout5s,
 29hijos y PG cerrados. Driver corregido importado; rojos originales conservados.
- **G4:** pareja A10flow/recovery de18+15spans, cinco POST y33ACK. Lectura final
  tres GET/734ms valida33filas/667atributos/12modelos y uso, parentage/estados/
  privacidad. Perfil API v4 documentado desde fuente oficial; ningún POST ni
  productor repetido. API no acredita UI, retención durable ni factura.
  El usuario autorizó inspeccionar su sesión autenticada:12observaciones y248
  atributos coinciden en la UI, cinco capturas inspeccionadas. Pausa/resume
  mantienen run_id/record_id con nuevo attempt_id; retries, calidad/procedencia,
  costes estimados en cents y contenido ausente observados. Recibo UI
  a2058c08…d8f3, sin nuevos Producer/Collector/Model ni consultas REST directas.
  Tokens sintéticos y estimaciones no son factura; la UI no prueba retención.
- **G5:** ocho grafos×siete contratos=56PASS, sin skips/exclusiones; SDK5/5 y
  LiveView/Oban6/6 más crash73/recover0 sobre el mismo TAR. Los ocho diagnósticos
  estrictos salen1 por TOML/WebSockex/gproc oficiales, sin warning ExAgent.
  TOML0.7.0/WebSockex0.5.1 son las últimas releases; gproc1.3.0 corrige sus sitios
  pero grpcbox0.18.0 exige~>1.2.0. Sin suppress/forks/updates arbitrarios.
- **G6:**18filas×200muestras, dos soaks200/c8 y saturación64runs/capacity32/
  batch_ceiling8; límites y cleanup medidos con TestModel. No SLO del backend,
  soak prolongado ni garantía hardRAMpredecode.

Los cambios posteriores a019 incluyen documentación, soporte de pruebas y dos
fixes causales de la receta opcional aislada (proyección pública e IO binario).
La nueva
identidad declara ese delta y conserva la cualificación funcional de019.
Los recibos/hashes completos están en
`docs/orchestration/2026-10-01-v2-codex/FINAL-CANDIDATE.md` (sólo checkout).
Langfuse G4 visual queda aceptado en ese perfil. El mandato posterior del usuario
exige la misma profundidad en Opik: nativo/API33/33,667attrs/12usage aceptados
en candidata025 y workspace de pruebas autorizado `tehsuso/exagent`; UI12casos/
248attrs y siete vistas reales inspeccionadas aceptados, recibo e0a9be73…3e0f9.
Navegación/captura inestables conservadas como limitación. Se conservan fallos500ms/1s y el perfil finalHTTP3s,
RPC3.5s/VM5s/export20s/owner28s/Collector30s sin retries ni ampliar el guard30s.
Detalle en el registro del checkout `OPIK-ACCEPTANCE.md`. Sin
repetir las ondas Langfuse ni el proveedor pagado. CI remoto exacto sigue pendiente; sin bump,
commit/publicación ni modificación de aplicaciones consumidoras.

**P1 exhaustion composicional —2026-09-29, revisión pendiente.** Record calcula
el máximo de copias terminales más reservas remanentes sobre cualquier subconjunto
de nodos agotados, con crédito exclusivo de sus slots retirados. Fuente−1/exact/+1
del probe muestra rechazo temprano/cierre/cierre. Original sin editar conserva rojo
en control roomy sink-funded; copia con ajuste autorizado de dos líneas pasa2/2,
sin relajar±1 ni cambiar producción. Matriz permanente10 nuevos/171.3s,69existentes
seleccionados/323.0s y10oracle/legacy/10.6s (246excluidos), todos exit0; compile118WA,
formato global/diff0. Conservation por fase/slots propios/preimágenes/escaping y
negativos de source/raw; sin aceptación Frame10/VM/R6. Review original y probespadre
pendientes; detalles y rojos de fixtures preservados en R6 implementation.

**Output exhaustion CAS10 —2026-09-29, revisión pendiente.** Implementación interna
de la decisión autorizada: última atestación retry terminal sin permiso IO ni used++;
entry/history/nodefailed/raw delegado/frontier atómicos y certificado de fuente,
descriptor, counters e historia exactos. Mixed CALL/NODE orden estructural, drain/
failed/refund existentes y capacidad de copias/recibos conservados. Pruebas CAS0/1/N,
mutaciones, dos órdenes estructurales y de llegada, ambigüedad, pause/reclaim y
source±1 en [R6 implementation](r6-implementation.md). No productor10/VM/R6 aceptados;
raw/host/root fatal generales, retención fatal y recovery permanecen cerrados.

Gates finales:164 seleccionados (incl9 nuevos)/438.9s y166 legacy/209.8s, todos exit0;
compile117WA, formato global/diff0 y8 hashes runtime/tests estables. No FULL; los
focales anteriores se solapan. Capacidad mixed1213099 y step-only234759, fuente±1;
límites callfatal previamente revisados siguen pasando. Detalle exacto en R6.

**Fix P1 control final/recibos CAS10 —2026-09-29, review pendiente.** Runtime sólo
Record:4116 bytes del allowance existente por call separados de alternativas
success/cancel, crédito de crecimiento JSON final exacto sin tocar raw/frontier;
recibo settled child/host y resolution gastados sin duplicar crédito effect/consumed.
Repro original rojo1/2→verde2/2; variante child detectó recibo pendiente, corregido;
regresión exitosa de consumo también conserva su recibo. Nuevas pruebas CAS con
sourceMAX antesfatal±1, roomy, raw/final4096, receipts512 escapados, Unicode/plain,
siblings completed/cancelled y crédito4092 exacto. Gates finales134seleccionados
(incl6nuevos)/384.2s, original2/2, legacy4/4; compile116WA/formato/diff0. Identidad en
[R6 implementation](r6-implementation.md). No aceptación fatal/productor10/VM/R6;
legacy y guards restantes intactos, review independiente y probes padre pendientes.

**Call-fatal failed closure CAS10 —2026-09-29, revisión acumulada pendiente.**
Implementado finish interno10 sobre fatal de call final confirmado: drain de trabajo
ya admitido, blocked conservando evidencia, cancelled sólo no terminal elegible,
failed raíz/refund del claim único, get/status/delete y reset estructural cerrado.
Ambigüedad impide cierre; no consumption/ToolReturn ficticio ni doble accounting.
Reserva alternativa de cierre antes de admisión, recibos/frontier separados. No
productor10/publicresume/VM/PID-drain/R6 aceptados. Raw/host/root/node fatal,
exhaustion/output_failed/retention-fatal/recovery/general cancel/expire pendientes
y cerrados. Evidencia exacta, fallos históricos y matriz en R6 implementation.
Owner final150/150 (incluye8 nuevos), legacy4, compile115WA/formato global/diff0;
tests trusted CAS, no aceptación independiente ni garantía worker/VM.

**Fatal-control CAS10 parcial —2026-09-29, revisión pendiente.** Confirmación final
de wrapper y cierre de nuevas admisiones atómicos; selección por ruta/orden original,
drain de outcomes/wrappers ya admitidos, reserva adicional de copia frontier. No es
cierre de la misión fatal10: raw/host/root/node, output_failed/exhaustion, resolución
fatal, blocked/cancel estructural, failed terminal/refund/fachada y su matriz de
capacidad siguen pendientes/fail-closed. Productor9/legacy intactos; sin claim VM/R6.
Evidencia, históricos rojos y límites en [R6 implementation](r6-implementation.md).
Gate histórico114/115 conservado: límite fijo del oráculo rechazaba antes de dispatch.
Tras autorización puntual del principal se deriva el umbral del flujo CAS/reservas
actuales, manteniendo raw65536±1 y añadiendo el límite original como rechazo preciso
antes de dispatch. Rerun completo116/116 exit0, focal18/18 y legacy4; runtime intacto.
No se acepta por ello fatal10 completo/producto/R6; revisión acumulada pendiente.

**Cierre exitoso CAS10 —2026-09-29, revisión independiente pendiente.** Implementado
step_output atómico/plain+typed, avance de prefijo y terminal raíz con certificado
global y refund único del claim vigente. Flujo Aeffect→B(Dtypedretry/Epause2)→C
conserva contexto/evidencia/accounting; bytes pendientes plain se reservan antesACK,
sin tocar la reserva typed aceptada. Record/get data-only; CompositionRestore10
permanece cerrado, pendiente consumer seam terminal con definition binding. No
productor10, VM, callbacks/quiescencia viva ni R6 aceptados. Fatal/recovery/cancel/
expire/uncertain siguen rechazados. Evidencia exacta y límites en
[R6 implementation](r6-implementation.md).

**Fix causal output-capacity10 —2026-09-29, revisión pendiente.** La review bloqueante
reprodujo2 fallos del mismo defecto: ACK sin reservar copias de consumo obligatorio.
Record incorpora reserva pendiente history/result y proyecciones correlacionadas,
crédito materializado sin duplicación y recibo consumible. Originales v4:3/5 antes,
5/5 después sin cambiar oráculos;7 casos permanentes de boundary±1/escapes/recibos
máximos/replay/siblings/históricos y rechazo temprano preciso con control positivo.
Detalle y gates finales en [R6 implementation](r6-implementation.md). No aceptación
de output10, productor/VM ni R6; negativos y productores legacy intactos.

**Output tipado/retry CAS10 interno2026-09-29 — revisión pendiente.** Integradas
atestación, consumo sin request nueva, pause2decide/reclaim y terminalchild tipado
con raw canónico y wrapper independiente, preservando accounting. Certificado global
de hash/source/fingerprint/posición/historia/contadores y límites; callbacks no se
reejecutan al decode. Regresión seleccionada380 pasa (no FULL); gates finales y
casos nuevos detallados en [R6 implementation](r6-implementation.md). Sin cambios
de tests antiguos ni productores9. Exhaustion/fatal no certificado, rootterminal,
recovery/uncertain/cancel/expire y productor10/VM siguen fuera; no aceptación R6.

**Accounting CAS10 interno2026-09-29 — implementado, revisión pendiente.**26 tests
nuevos verifican contribuciones cualificadas Model/tool, Scope2 ancestral root/B/D,
partial/normalized/costes, pause2decide/reclaim y continuación hasta D→wrapperY→B,
sin doble contribución ni repricing. Seam ScopeLedger nil autorizado y corregido con
decoder existente; Usage.sum/Retention intactos. Reservas host y cuotas se comprueban
en admisión; observación/ledger/outcome y consumos correlacionados atómicos. Regresión
seleccionada235 y2 probes separados pasan tras permiso puntual para cambiar sólo el
oráculo Model no nulo por commit+operación/counters exactos/cero observado≠nil. Rechazo
wrapper intacto; compile112WA/formato global/diff verdes. Históricos234/235 y232/233
preservados. Revisión independiente pendiente, sin aceptaciónFrame10/R6.
Detalles y artefactos en [R6 implementation](r6-implementation.md). Productor10/VM,
outputretry/rootterminal/uncertain/fatal/cancel/expire continúan fuera del subset.

**Corrección causal CAS10, revisión independiente pendiente:** los cuatro defectos
de la review bloqueante tienen regresiones rojo→verde: historial omitted no autoriza
Model nuevo, child unknown rechaza sin perder wrapping, reserva descontada sólo por
resultados JSON materializados y motivos host post-hook atestados sin recalcular args
originales. Tests permanentes con create/CAS/roundtrip, cierre bounded y límites±1;
detalle de comandos/errores de oráculo en R6 implementation. No aceptación subset
ni expansión: productor9 intacto,10/usage externo no nil/output retry/rootterminal/
uncertain/fatal siguen cerrados; nil no significa coste cero.

**Checkpoint interno2026-09-29 — Store/CAS10 parcial, pendiente review.**
Create→claim→B/delegadoD con sibling settled+2asks→suspend/pause→decisiones públicas
parciales→ready/reclaim/frontier probado con roundtrip en cada ACK; childrawX→wrap→
finalY→reduce/consume también. RequestData2 preimagen exacta bajo contexto interno10;
legacy1/productor9 intactos.113 focales (14 nuevos),207 legacy seleccionados.
Source/effect/observación/outcomes atómicos; fallos attach/raw/settle/pause, lost ACK,
dos claimants, epoch/fence, input no-default, hash/schema/refs y capacidad cubiertos.
No quiescencia de workers/VM ni productor10. **Pendientes del mismo frente:** uso
externo no nulo, output resolutions/retry, terminal raíz/recovery; fatal/output_failed
siguen cerrados. Sólo ausencia de uso admitida aquí, nunca promesa de coste cero.
No marcar R6 ni transiciones10 completas; integrar pendientes antes del productor.
Evidencia/limitaciones en [implementación R6](r6-implementation.md).

**Incremento interno2026-09-29 — fuentes child/host, NO admisión10.**
Conversión childterminal pura: success exacto, failed con proyección portable lossy
aprobada; omitted/cancelled no inventan payload. Certificado SOURCE enlaza padre,
request/call/binding y fuente única, bytes/control exactos y sin effect/accounting
ficticio. No confunde raw con output final transformado por hooks. Host enum parcial
cerrado: permission_denied observado, sin evaluar autoridad actual. Otros caminos
predispatch necesitan representación de preparación fallida (unknown tool no tiene
schema/binding válido); no se inventan. Entryglobal/Record/transitions/productor10
cerrados; wrapperfinal, cancelación con raw previo, authority/requestdata y
globalfatal/outputfailed pendientes. Fixtures coherentes sintéticas, no productor/VM.
Evidencia de comandos y limitaciones en `/tmp/opencode/frame10-sources-JCYces/REPORT.md`.

**Incremento interno2026-09-29 —partición raw e historia10, certificado aún incompleto.**
Los mismos lectores comprueban globalmente efectos tool, operaciones contributed y
outcomes actuales; fases sin fuente/running externo/raw/wrapping/blocked sin fabricar
resultados. Replay desde el primer batch con consumo exacto comprueba los contadores
de entrada al reducer y rechaza borrar batches históricos con sus efectos.14 casos
adicionales: focal79 (35 gramática +44 journal/output), legacy selectiva62, ambos exit0.
Un rojo intermedio detectó estados de effect inventados `intent/uncertain`: corregidos
a `running`, conforme Record/Retry; ambos inventados ahora son negativos explícitos.
No FULL/VM ni aceptación global10. Hay ambigüedad pendiente de decisión para preservar
la conversión de delegado fallido: razones distintas producen el mismo error portable
actual pero distintos raw ToolReturn; no se eligió silenciosamente otra proyección.
Prueba y detalles en `/tmp/opencode/frame10-journal-complete-FXHNF6xU/REPORT.md`.
Child/host, request-data/authority y fatal/output-failed siguen pendientes; gates
evidence10/Record10/transiciones10 cerrados. La misión de certificado completo NO cerrada.

**Incremento interno2026-09-29 —journal10 parcial, gates cerrados.** Helpers existentes
`ToolEvidence.calls/reduce_resolution` verifican Record original, Models y batches admitidos,
hash/orden/call binding, final effect-backed raw/final y accounting none/contributed,
reducción retry/reset/fatal y consumo adyacente índice/hash. OutputResolution10 añade
posición suspended-response y retry consumido sin request sucesora ficticia, con árbol,
historia/modelos/counters reales; failed genérico continúa rechazado.30 casos nuevos
sintéticos, focal65/65 incluyendo35 de gramática; regresión legacy279/279 (527.4s),
compile forzado110WA/formato global/diff sin errores; no productor10/VM10/atomicidadCAS.
`evidence?10`, Record.execution10 y transiciones10 siguen cerrados. Pendientes: child
conversion pura, host reasons, raw parcial, tool-orphans/evidencia global y cadena de
retries, failed/output fatal exacto, integración runtime. Informe y gates restantes:
`/tmp/opencode/frame10-journal-fresh-iVQZzt8g/REPORT.md`. No aceptación Frame10/R6.

**Incremento interno2026-09-29 —Frame10 todavía inactivo.** Gramática tipada de
árbol/nodos/links/frontier y Call10 raw/control implementada con pruebas sintéticas;
Record y transiciones rechazan10, productores continúan9. No es aceptación de
delegación ni certificado de evidencia/quiescencia. Focal final35/35 y regresión
349/349 (incluye33 casos nuevos anteriores), compile109WA/formato global/diff0;
sin FULL ni review nueva. Pendientes: fuentes host,
atestaciones journal/model-order/hashes/accounting, OutputResolution10, reducer/
consumo, transiciones/resolver/drain y vertical VM. Alcance y reemplazos prevalentes:
`docs/orchestration/2026-09-28-native-f19085/tasks/structural-delegation.md` (última
sección). La recepción de producto vigente sigue siendo la siguiente.

**Recepción vigente2026-09-29 —evidencia activa Frame9 aceptada offline acotada.**
Misma Composition.resume/3 con recover explícito/referencia exacta: final/resuelto/
accounting aceptado/control completo, prefijos tools propios y output retry/success
actual atestado, incluidas approvals históricamente consumidas. No autorización de
request nueva por coincidencia de ID/args; current allow no supera original ask.
Record/retry plans globales antes de vista privada, reducers con Record original,
contadores host exactos sin repricing/redebit y uso cualificado conservado.
Owner FULL1845/28/1410.3s exit0, compile109WA/formato global/diff0,55casos=25+30;
review favorable40existentes+4propios, identidad9+306. Padre9hashes/copia roundtrip,
mismos4probes corregidos4pases/16.7s/exit0, no adicionales. Informes/SHA/log en
[implementación R6](r6-implementation.md). Owner54/55 rojo→4focales→FULL verde y
harness fallidos conservados; review original3/4 por oráculo allow sobre ask no se
reinterpreta verde: copia corregida4/4 sin source fix. Fatal actual falla sin C/refund
final, fatal histórico negativo; preparación typed host prioritaria. Retry estructural
unsupported, tool exception intent unresolved sin unknown confirmado. Parse inflado
no equivale a CAS válido oversized; capacidades separadas. Legacy7/8/single9/C7
allpending intactos; ETS/VM ficheros no certifican SQL ni preempción de callbacks.
No mixed/raw/uncertain/delegación/router/paralelo/general R6/SQL/live/producción.
Siguiente: investigación estructural sólo lectura delegación+C7 quiescente/mixed-control,
sin implementación activada ni sustituir obligaciones de producto por microsubsets.

**Histórico de la misma unidad, ampliación de matriz2026-09-29 —antes de aceptación.**30 casos
adicionales (55 acumulados), runtime intacto: authority/binding/effectiveargs sobre
approvals consumidas, contribuciones tool cualificadas, observability con deadlines,
owner kill/fencing y capacidad activa±1 separada del parser. Evidencia recuperable en
`/tmp/opencode/sequence-active-matrix-xzij2ykz/REPORT.md` y R6 implementation. FULL
integrado único1845pases/28excluidos/1410.3s exit0, compile109WA/formato/diff0 y306/306
identidades fuente intactas. Review independiente y aceptación padre pendientes.

**Histórico: checkpoint funcional autorizado2026-09-29 —antes de aceptación.**
Mandato sellado `sequence-active-evidence.md` posterior a la recepción8.41. Runtime
delta sólo CompositionRestore: vista privada por hoja tras validación global,
batch/prefix final resuelto, output retry/success actual y approvals consumidas exactas.
25 casos nuevos incluyen A→B dos approvals públicas→batch resuelto→VMfresh→output
retry→segunda VMfresh→B→C;6requests/3tools/coste58, historia inmutable. Dos negativos
antiguos exactos autorizados ahora verifican éxito. Checkpoint y matriz pendiente
en [R6 implementation](r6-implementation.md); FULL final/review aún no ejecutados.
No cierre por helper ni aceptación R6; continuar la misma unidad funcional.

**Base recibida2026-09-29 —C7 secuencia todo-pending aceptado offline antes de evidencia activa.**
Pausa raíz ACK y hoja proyectada, halt antes de C, dos decisiones host (partial
pending/último approve ready/deny terminal), nuevo claim y resume VM sin replay del
prefijo; counters/budget/refund exactos. Owner FULL1790/28/1121.2s exit0 separado de
review favorable271existentes+7propios/compile108WA/formato global/diff0, identidad
15+303; padre15hashes/helper/runner y roundtrip de copia, mismos7probes7pases/13.2s
exit0. Informes/SHA y log en [implementación R6](r6-implementation.md).
57casos owner=43+14, sin sumar reruns. Padre recibe los dos antiguos negativos
causales sin inventar autorización previa; históricos y provenance conservados.
Allpending se certifica post-resultados async: mixed puede tener efectos y falla
cerrado sin pause/refund, no barrera atómica preadmisión. Currentdeny puede dejar
outcomes denied y continuar C sin tools B, distinto de admindeny terminal.
Refs/policy preclaim no equivalen a schema/Model efectivo postclaim. Record2/Frame9
experimental direccional; lectores viejos rechazan nuevas filas, deadlines antiguos
intactos. No mixed/raw/delegación/general R6/router/paralelo/SQL/live/producción ni
binding MCP endpoint/principal o preempción de callbacks iniciados. Siguiente unidad:
investigación sólo lectura, sin nueva implementación activada.

**Histórico C7 secuencia, implementación autorizada2026-09-29 —antes de aceptación.**

Ampliación de matriz owner fresco:14 casos adicionales, focal129/129 exit0.
Token parse±1 separado de capacidad CAS, cambios postapproval refs/policy/schema/
binding Model real, observability batch aprobado y siguiente Model con expiración
budget/lease y positivos. Runtime intacto; artefactos en
`/tmp/opencode/sequence-approvals-matrix-f14f3b0f/REPORT.md`. FULL integrado único
1790pases/28excluidos,1121.2s,exit0; compile108WA/formato/diff0. Identidad acumulada
15rutas y provenance de dos antiguos negativos en R6 implementation;
review/aceptación abiertas.
Mandato sellado `sequence-approvals.md` sustituye el estado de investigación del
hito inferior. Vertical funcional Acompleted→B dos ask→pausaACK→decisiones públicas→
ready→VM nueva B→C implementado dentro de seis módulos, Record2/Frame9/Approval1.
Pausa raíz exacta/refund, decisiones inmutables, restore por evidencia, historial
aprobado y límites temporales/capacidad cubiertos por nueva matriz. Evidencia actual
y pendientes en R6 implementation y `/tmp/opencode/sequence-approvals-f153afda/REPORT.md`.
Owner43casos nuevos, focal final105/105 y FULL final único1776pases/28excluidos,
1098.2s exit0; compile forzado108WA/formato global/diff0 e identidad303/303 intacta.
Review independiente, aceptación C7/R6 y gates externos siguen pendientes.

**Base recibida2026-09-29 —recuperación acotada aceptada offline, anterior a C7.**
Composition.resume continúa ready9 empty/between/input sin operaciones propias y
terminal texto sin tool-history propia/typed-succeeded admitido; completed data-only,
recover explícito y prefijo sin replay/repricing. Helper cerrado exacto, claim ACK,
deadline cached y guard post-intent-ACK preservan autoridad, counters y partial.
Owner FULL1733/28/967.8s exit0; review fresca favorable29(2+10+17)+113+3observability;
padre identidad6/6 y mismos15(2+10+3) probes,12.6s exit0 en copia completa nueva con
roundtrip de rutas. No15casos adicionales. Informes/SHA y log padre en
[implementación R6](r6-implementation.md). Sustituye pendientes de recovery inferiores;
rojos P1/P2, harness y sampling10ms permanecen históricos. Finito abandonado agota;
ilimitado positivo bajo límites vigentes; antiguos deadlines persistidos no se amplían.
No preempción atómica de callbacks iniciados, batch/output-retry activo multileaf,
raw/uncertain, C7 composiciones, delegación/router/paralelo, R6 general o SQL/live/producción.
MCP SDK y R7/A9/G4 conservan su alcance separado. Próximo C7 es investigación sólo
lectura, no mandato de implementación; sin bump/publicación.

**Histórico P1 residual ACK intent —2026-09-29, antes de review.** El review posterior
reprodujo Model IO después de budget/lease expirados al retener el ACK del intent.
El motor compartido revalida Scope justo antes de dispatch buffered/stream y calcula
timeout restante sin renovar deadline. Intent confirmado queda unresolved si no hay
IO. Recuperación del worker interrumpido preservó código/tests y rojos originales;
17regresiones dispatch pasan, incluidos siblings tool negativos/positivos;113focales
y10probes originales intactos pasan. Los dos probes causales nuevos también pasan.
Gates finales e identidad en R6 implementation y
`/tmp/opencode/sequence-intent-fix-recovery-unique/REPORT.md`. FULL final1733pases/
28excluidos/967.8s exit0; compile107WA/formato global/diff0,420/420rutas pre-FULL
intactas tras el gate. Notas de cierre posteriores. No aceptación recovery.

**Histórico recovery corrección de review P1/P2 —2026-09-28, antes de nueva review.**
Tres rojos originales reproducidos en copias nuevas; dos causas: reserva renovada
tras on_writer y valores root inválidos admitidos antes del claim. Deadline único
desde ACK, checks de preparación y validación Scope pre-CAS implementados; probes
intactos10/10 verdes. Regresiones permanentes owner/codec/preflight/sucesor/ACK y
opciones root añadidas; rechazo estructural de estimador aridad1 también pre-CAS,
sin ejecutarlo ni cambiar scopes ordinarios. Focal amplio446pases previo a ese
último ajuste; focal final74pases y probes finales10/10 más causal3/3 (mismos fallos
originales), todos exit0. Gates finales en R6 implementation y
`/tmp/opencode/sequence-recovery-fix-f159fe36/REPORT.md`; FULL1706 inferior es
histórico previo al fix. Recovery permanece sin aceptación; status lo mantiene el padre.
**Cierre worker2026-09-29:** FULL único final1716pases/28excluidos/948.9s exit0;
compile forzado107WA/formato/diff exit0. Identidad runtime/tests296/296 intacta
tras FULL; docs de recepción posteriores identificados aparte. Review independiente
y probes padre siguen requeridos antes de aceptar recovery.

**Histórico recuperación de secuencia implementada2026-09-28, antes de revisión independiente.**
API experimental resume con referencia estricta, recover explícito, prefijo cerrado
sin efectos históricos y mismo Writer/Scope/ledger. Checkpoint1 focal56pases/33.6s;
checkpoint2 integrado410pases/659.7s incluye VM real betweenA/inputB/terminalB,
texto/typed-succeeded, prefijos tools/retries, CAS/ACK/budget/autoridad/cleanup y
matriz pública ±1. Tras corrección temporal CAS/ACK, focal33/51.0s y **FULL final
1706pases/28excluidos/933.0s exit0**, compile forzado107WA/formato8fuentes exit0.
Gates finales y alcance exacto en R6 implementation y
`/tmp/opencode/sequence-recovery-f15f35af/REPORT.md`. No autoaceptación de recovery,
R6 general ni producción; aceptación anterior de run permanece separada.

**Base recibida2026-09-28 —secuencia durable aceptada offline, anterior a resume.**
`Composition.run/3` ejecuta N pasos con único Scope/Writer/claim/presupuesto,
mapping confirmado y refund raíz final; completed multileaf es inspección data-only.
Review favorable62focales+5probes previos en copia corregida+2nuevos terminales;
padre26/26hashes y cambio único exacto de assertion, mismos7probes7pases/3.3s/exit0.
Owner FULL1673pases/28excluidos/885.2s exit0 es evidencia separada, no otro FULL.
Informes/hashes/log padre en [implementación R6](r6-implementation.md).
Original4/5 y FULL1651/1652 conservan sus fallos históricos. Se sustituyen sólo los
pendientes de esta unidad; no restore activo multileaf/C7 composiciones/rawuncertain/
delegación/router/paralelo, R6 general ni SQL/live/producción.

**MCP SDK —aceptado offline acotado2026-09-28.** SDK oficial Python `mcp2.2.0`,
stdio `2024-11-05` y HTTP `2025-06-18` JSON/SSE × session/stateless, tools textuales
localhost mediante Client/Tool/permisos reales: discovery/schema/call/error/DELETE/
cleanup. Owner5/5 y review5/5 sin skips son los mismos cinco casos, no diez distintos
ni un rerun padre. Owner `/tmp/opencode/mcp-sdk-interop-G1ERXY8j/REPORT.md`, SHA256
`727d2a29e8060160b003b596ab7e3e64970434d72396c11583cb917df96a90e9`;
review `/tmp/opencode/mcp-sdk-interop-G1ERXY8j/review-fresh/REPORT.md`, SHA256
`e52735d55e26768b441a02c3469fa0d455401356613d5c424baac9ac849660f1`.
Review comprobó procedencia/SDK sin parches,128archivos wheel/28deps,24respuestas
HTTP, efectos/permisos/lifecycle y cleanup6PID/4listeners; padre cotejó cinco módulos
MCP ROOT/copia byte-idénticos. Límites65KiB/pending4/tools4 sólo HTTP; stdio defaults
8MiB/128, sin estrés. Harness portable pendiente de integración ROOT; repetir en
directorio nuevo porque runner escribe endpoints.json, nunca sobre entrega sellada.
No OAuth/TLS/cancel/reconnect/chaos/C7binding/protocolo2026/otrosSDK/multileaf/SQL
ni cierre R7.4/A9/R7/G4. Esta recepción es sólo documental.

**Frame9 corrección de dos P2 —2026-09-28, aceptada offline.** Descriptor separa
admisión de mapping y conserva razones; Composition maneja pérdida Writer en
apertura/lecturas usando sólo ACKs recibidos, subtotal partial y sin token inventado.
9casos permanentes nuevos más assertions causales; focal62 pasa y matriz12 real
pasó en la ejecución amplia previa (un fallo de barrera nueva, luego corregida).
Los5probes originales intactos pasan de3/5 a4/5: el rojo residual exige la vieja
razón invalidinput, incompatible con preservar la cuota exacta requerida. No se
modifican sus assertions ni se presenta como gate verde. Gates integrados e identidad
en `/tmp/opencode/sequence-fix-unique/REPORT.md`; revisión y probes padre recibidos.
FULL integrado1673pases/28excluidos,885.2s suite/886.3s comando, exit0;
compile-forzado107 WA, formato y diff exit0. Offline WA48seed37556; aceptación acotada arriba.

**Frame9 cierre de matriz —2026-09-28, incluido en aceptación acotada.** Nueva matriz12casos
usa Composition.run/Writer/Store reales: límite público±1, JSON+cleanup±1,
token±1 y horizonte receipts con checkpoints CAS auténticos en outputA/inputB/
intentB. Ajuste causal autorizado: assert export de run/3; resume/2 y demás
negativas intactas. Runtime sin cambios. Gates finales y manifiestos se registran
en `/tmp/opencode/sequence-frame9-boundaries-f1651f1d/REPORT.md` y R6 implementation;
owner focal112/166.5s, compile-forzado107 WA y FULL1664pases/28excluidos/880.9s,
exit0 offline WA48seed37556. El FULL1651/1652 fallido sigue como evidencia histórica;
review posterior aceptó la secuencia en el alcance anterior, no R6 general.

**Histórico Frame9 fase2 — API/proyección integrada2026-09-28, aún sin aceptación en ese hito.**
`Composition.run` usa el loop/Writer/Scope existente; proyección confirmed común
con completed data-only, metadata/token previo a cleanup y tracing OTel existente.
Oráculos API, VM, owner kills/tickets/accounting y fixture auténtica8 incorporados;
en ese hito quedaban matriz exacta±1 y review fresca. Gates/pendientes y
artefactos en `/tmp/opencode/sequence-frame9-phase2-f168b0f9/REPORT.md`.
Owner compile107/formato/diff0 y576focales; FULL1651/1652,28excluidos,exit2:
expectativa histórica de ausencia de `Composition.run/3` en
`composition_definition_test.exs:40`, fuera de allowlist, no editada. Requiere
autorización causal para actualizarla y revalidar, recibida en el cierre de matriz
arriba; el FULL fallido se conserva, sin excepción al gate.

**Histórico Frame9 fase1 — vertical A→B→C integrada2026-09-28, aún sin aceptación en ese hito.**
Un único Writer/Scope/CAS persiste texto/tools/typed/retries, mapping confirmado,
tickets PID/revisión/índice y presupuesto intacto entre pasos con refund raíz final.
Productor/Record/Transition9 integrados; lifetimes7/8 conservados; restore activo
multi bloqueado por binding, completed data-only. Gates nuevos y pendientes exactos
en `/tmp/opencode/sequence-frame9-f16bf3ff/REPORT.md` e implementación R6. Fase2
Composition.run/proyección/tracing integrados en fase2 arriba. Revisión fresca requerida.

**Histórico Frame9 fase1 — hito preparatorio parcial2026-09-28.**
Validación estructural explícita de prefijos y partición de evidencia leaf/global
implementadas.31pruebas nuevas; focal523pases/537.6s WA48seed37556,exit0.
Productor8/Record/Writer/Transition intactos: todavía no hay ejecución A→B→C,
tickets multistep, refund final ni restore9. No cierre de fase1 ni R6.
Continuar el mandato `tasks/sequence-frame9.md` del run nativo vigente conservando
este delta probado. Informe recuperable
`/tmp/opencode/sequence-frame9-f16d8c61/REPORT.md`; matriz y límites en
[implementación R6](r6-implementation.md). No FULL en este hito preparatorio.

**R6 Frame8 final/control —aceptado offline acotado2026-09-28:** subset autorizado en
`tasks/next-r6-frame8.md` del run nativo vigente. Baseline402archivos preservado en
`/tmp/opencode/r6-tools-f17600f0/REPORT.md`; primer informe parcial preservado aparte.
Review fresca50casos distintos (43focales+3independientes+4adyacentes), sin P1/P2
reproducible: `/tmp/opencode/r6-tools-review-fresh-928a/REPORT.md`, SHA
`326c054b6cbd08c7d42db6df699dcad2354f7058519724b1a761ca5e93ae2439`.
Padre cotejó source12/12 y reejecutó3probes intactos WA48seed37556 exit0/9.3s,
`parent-probes.log/.exit` y JSON nuevos timestamped en ese directorio. Acepta sólo
single-leaf Frame8 final/control/prefix; no raw/uncertain/no-control/rejected/omitted,
legacy7tools/approval-retryplans/delegación/A→B ni R6 general/SQL/cloud/live.
Evidencia owner separada, REPORT SHA
`74024782c03dd74401d9d9f371ee41f8b185a5e2d9d813c193ec2726d2a9c71a`:
compile107/focal261 (99nuevos), MCP37 y FULL siguiente. Esta recepción docs5 es
posterior a los bytes revisados; siguiente unidad requiere propuesta contrastada.
**Entrega final owner recibida:** oracle MCP autorizado admite
DOWN normal/killed con PID/ref exactos; dos regresiones fuerzan ambos órdenes sin
cambiar plazos250/2000, preservando cierre/timeout/pending/late-success y cleanup.
Focal MCP+probe original37pases/1.9s, formato/diff exit0. FULL final1568pases,
28excluidos,716.8s,WA48seed37556 offline,exit0. Manifiesto405archivos
SHAfb4bb3b5cff4ae7691c269655073db61770ab940cfb4ec4fa9c88e08bc0d53b3.
Runtime R6/MCP estable; siguientes entregas fallidas se conservan como historia.
ROOT/build liberados en REPORT; aceptación de la unidad recibida arriba, no R6 completo.
Los pendientes de autorización/review siguientes pertenecen a entregas históricas.

**Entrega anterior owner:** padre autorizó el test output_retry_restore1374; se
actualizó sólo ese caso a success data-only con historia/accounting/no_new_io y
codec host una vez, conservando vecinos. Focal4/4,6.3s,formato/diff exit0. Nueva
identidad405archivos SHA94c1c8a3710146fbf099a127fae468cf4b583869755bff177d5e953b9bc59795;
FULL1565/1566,28excluidos,719.8s,WA48seed37556 exit2 por fallo DISTINTO:
MCP streamable_http_test643 espera DOWN:killed, recibió normal y cierre de socket.
MCP intacto. Diagnóstico externo local2/2 fuerza ambos órdenes transporte/guardian,
verifica socket cerrado/timeout/rechazo late-success; original aislado2pases. No
FULL verde por restar el caso; decisión del padre fuera allowlist y review pendientes.
Lo siguiente conserva la entrega anterior y su fallo ya corregido bajo autorización.
Implementado consumidor current-first, prefijos continuables y batch final/resuelto,
sin replay ni doble accounting. Matriz nueva99casos, focal final261pases/266.1s,
compile forzado107/formato/diff exit0. FULL integrado nuevo1565/1566pases,
28excluidos,717.3s,WA48seed37556,exit2: único fallo es el negativo obsoleto indicado
abajo; no gate aceptado ni review fresca todavía. Rojo causal2→verde2 y fallos de
fixtures conservados. Padre autorizó actualizar sólo el negativo productor780/801,
ahora positivo. Focal anterior217/218 detectó otro negativo obsoleto fuera de allowlist:
`composition_output_retry_restore_test.exs:1374/1381`, prefijo final→output success.
Permanece intacto y pendiente de autorización; no aceptación ni cierre R6.
Manifiesto previo al FULL405archivos SHA170a594e101565e186926a39d95dd2a2315c7d52ea4f507c4c1b1b525ea5fee1,
sin cambios producto/tests tras gates. Recepción documental final separada en REPORT.

**Integración MCP HTTP —2026-09-28, aceptada offline tras review integrada del padre.**
Padre revisó diff/docs, cotejó377/377archivos del manifiesto y nueve rutas
byte-idénticas a la entrega privada. REPORT owner
`/tmp/opencode/exagent-integration-mcp-qlq7ladh/REPORT.md`, SHA
`9b192949fa5a68988909f8766d278052d4bfcb7351679b3f8efeb996f9f3a208`.
Review padre ROOT:77pases (8probes intactos+69adyacentes),20.9s, WA48seed37556
exit0; `parent-review.{command,log,exit}` en ese directorio. Estos77 casos son
evidencia del padre, separados del FULL1467/28/508.9s owner siguiente; no nuevo FULL.
La recepción documental posterior actualiza cuatro docs, incluido el documento MCP;
la coincidencia9/9 describe la entrega revisada, no los bytes de esta nueva prosa.
Entrega privada aceptada121focales+6+2review y padre8probes/397hashes, tras corregir
P2 de segmentación SSE. Patch exacto9rutas `ffb311e86bfb933daa4337408bc1b59af15c6aa518da002c33354ad08f7e8bc7`
aplicado sin conflictos: Client baselinefcc1aecf y ocho rutas nuevas ausentes.
Artefactos/baseline completo en `/tmp/opencode/exagent-integration-mcp-qlq7ladh/`.
Nueva identidad ROOT377archivos (`integrated-manifest.json`): MCP121pases,
8probes reviewer originales intactos y adyacente Frame8+OTel69pases, todos exit0.
Formato global, compile forzado106 WA y diff-check exit0. FULL único nuevo:
1467pases/28excluidos,508.9s, WA48seed37556 exit0; prefijo environment.md,
EXAGENT_OFFLINE=1 MIX_ENV=test y build absoluto ROOT. Producto sin cambios después
de gates; recepción documental final aparte en final-manifest/delta y REPORT.
Delta exacto14rutas: nueve del patch byte-idénticas a entrega privada y cinco docs.
FULL1423/28 pertenece a la integración anterior;121+6+2privados no son gates ROOT.
Contrato en diseño8.40 y [documento MCP](r7-mcp-implementation.md), con recepción
actual y propuestas privadas históricas separadas. HTTP1-only app-owned confiable,
MCP2025-06-18, no redirect/replay, JSON/SSE terminal-aware y límites postdelivery;
sin detección fiable HTTP2 ni hard RAM upstream. C7 binding endpoint/principal
pendiente; interop SDK posterior acotada aceptada arriba. No cierre R7.4/A9/R7/G4 ni R6 completo.

**Integración Frame8 + OTel —2026-09-28, aceptada offline tras review integrada.**
Recepción del dictamen `/tmp/opencode/integration-review-dNfJQyRC/REPORT.md`
SHA `c58bcc93e5b4e68d05744d128daeeeb504b378541166588e15abb72f41ec75f7`:
review9oráculos+69focales ROOT exit0, source369/369 intacto, sin P1/P2 en alcance.
Estos78 casos son review independiente; no un nuevo FULL ni los145privados.
Patch privado corregido5a060902 integrado con hashes exactos en OTel y dos tests;
Frame8 runtime intacto. Docs6 consolidan ambas recepciones. Artefactos recuperados
`/tmp/opencode/exagent-integration-frame8-r7-xkdxkNR2/recovery/REPORT.md`;
baseline histórico preservado, diff tracked y lista untracked idénticos al recuperar.
Nueva identidad compuesta `integrated-manifest.json`: focal476pases/337.5s y9oráculos
OTel originales/0.4s exit0; formato global, compile forzado102 WA y diff-check exit0.
FULL único integrado1423pases/28excluidos,509.6s, WA48seed37556 exit0, con build
absoluto ROOT y prefijo environment. No cambios de runtime/tests tras estos gates;
recepción documental final identificada aparte en final-manifest/delta. Review de
integración recibida arriba; sin cierre R6/R7/G4.

OTel privado: owner145focales, reviewer145+9oráculos y padre9 intactos WA48seed37556
exit0. Review `/tmp/opencode/exagent-r7-worker-O6Cjkklr/review-validation/REPORT.md`
SHA2349fb541cfcfd664b562cea20b15156aca3d4722a47594ba0f45a55a1b1296e.
P2 previo struct Access/version1.0 conserva rojo7/9→verde9/9; adenda exige mapa plano
sin __struct__ y versión entera1. Sin spans administrativos ni métricas nuevas;
accounting lifetime no sumable. Langfuse referencia provisional; G4/backend abierto.

**Productor Frame8 accounting/control — aceptado offline2026-09-28.**
Review95 (55productor+33contrato+7probes), padre7intactos WA48seed37556 exit0;
source19/19 cotejado. `/tmp/opencode/frame8-review-20260928-fresh/REPORT.md`
SHA49eb910f4fe1e749f7c34772b27ca248acd17d4ef3ac86fc7355c6cfa41c7ee0.
Sin P1/P2 en alcance; no reinterpretación legacy usage/retry ni restore tools.
Mandato exacto aprobado en tasks/tool-evidence-producer.md del run nativo vigente.
Preflight/baseline preservados en `/tmp/opencode/tool-evidence-f180bea3/REPORT.md`.
Antes de editar runtime se detectó que CompositionRestore, fuera de la lista
autorizada inicialmente, rechazaba cualquier versión distinta de7 incluso completed sin tools.
Probe aislado:2/3pases,1rojo contractual, exit2 WA48seed37556; no es fixture Frame8
auténtica ni gate de productor/CAS. Se solicitó autorizar sólo la discriminación
7/8 de ese módulo conservando las exclusiones de tools/prefijos/batches.
Padre autorizó explícitamente el discriminador7/8; bloqueo resuelto. Productor/
validator8 implementados con observación independiente, negativa durable previa
a aplicación y partial persistente, control postsettle, reservas concurrentes y
legacy7 lifetime. Matriz auténtica CAS/decode/ACK/VM/crash y límites en implementación
R6. Primer FULL1397/1400/28 exit2 por expectativas/ubicación de fixtures, corregidos.
Gates finales owner: matriz55pases, focal combinado88pases, compile forzado102/formato/diff exit0;
FULL1409pases/28excluidos WA48seed37556 exit0,508.2s. Reserva prebatch con margen
revalidado en outcomes; timeout existente30ms intacto. Review recibida arriba.
Sin restore tools nuevo ni aceptación R6.

**Restore input0 aceptado offline2026-09-28:** review integrada+delta floors,
171/171 independientes WA48 y padre46/0 (input_restore+probe intacto), sin P1/P2
restante en alcance. Informe `/tmp/opencode/exagent-restore-floor-recheck-f199cb6f/REPORT.md`
SHA0cafcd64b571ab37b2b88f6bdf6eeffaef00670921a15e5f71701ce5a2f88a3d.
Sólo input0/completed data-only; no restore general/A→B/SQL/live/R6 completo.

**Corrección P1 restore input0 —2026-09-28, revalidada:**
review fresca rechazó la entrega anterior por perder permission_floor singular
actual de hoja. Probe intacto reproducido1/2rojo; fix mínimo conserva singular y
añade floor persistido a la conjunción plural.16regresiones integradas cubren
root/leaf×singular/plural×deny/ask×current/original, con orden de reglas e
inmutabilidad. Focal171/0 incluye probe original/equivalentes Frame7/codec,
permisos y legacy; compile99/formato0 y FULL1088/0/28 WA48 seed37556,214.0s.
Evidencia `/tmp/opencode/exagent-restore-floor-f19bf814/REPORT.md`. La aceptación
posterior está arriba; no se amplía la frontera restaurable.

**Restore input0 R6 — entrega owner2026-09-28, revisión pendiente:** recuperado
parcial interrumpido, Frame7 autoridad efectiva inmutable y seam interno
resume_composition_step para una hoja input/request0 sin operaciones; completed
data-only. Otros cursores, intents/approval/raw/atestación rechazan antes de callbacks.
VM nueva desde JSON, carrera CAS con barreras, owner death/recovery explícito,
floor/permisos/límites/deadline/budget y legacy7 cubiertos en matriz de
`r6-implementation.md`. Compile99/formato0, focal123/0 y FULL1072/0/28 WA48
seed37556 (205.0s). Siete probes intactos+legacy38/40: dos supuestos de fixture
Frame6 incompatibles con writer7; equivalentes Frame7 permanentes verdes, sin
alterar probes ni regenerar fixtures. Evidencia nueva en
`/tmp/opencode/exagent-restore-recovered-f19bf814/`. No restore general/A→B/SQL/live
ni aceptación R6 completa; la base paso único aceptada siguiente se conserva.

**R6 paso→hoja, aceptado offline2026-09-28:** dictamen independiente final
`/tmp/opencode/exagent-reserve-acceptance-f1a519/REPORT.md` SHA262a4a2f:
72pases exit0, siete probes intactos y límites exactos; sin P1/P2 restante en alcance.
Padre cotejó informe/hashes/delta y revalidó35pases (matriz+supplemental) WA48
seed37556, exit0. Acepta PASO ÚNICO, no restore ejecutable/A→B/SQL/live/R6 completo.
El detalle siguiente conserva evidencia owner y evolución; recepción única en§5.

**Corrección final de cardinalidad:**
Follow-up acotado del review integrado: <code>Record.tree_children/1</code> omitía Frame6 y
relajaba reservas sin finalizar la hoja. Añadido6 al mismo helper, sin nuevo formato.
Probe intacto rojo→verde; reservas5receipts/33800bytes restauradas,1019receipts y
JSON+cleanup exactos aceptados, invasión+1 rechazada. Owner158/0 focal/probes,
compile97/formato0 y FULL1043/0/28 WA48 seed37556 (195.1s). Evidencia nueva en
`/tmp/opencode/exagent-frame6-reserve-f1a381/`; revalidación aceptada arriba.
**Histórico previo al P2 de cardinalidad:** el review rechazó el hito1010 por
reserva concurrente y output tipado.
Unidad contractual posterior: Frame6/atestación output ligada a RequestData,
ToolReturn/Retry con procedencia y pareja current/comando sintéticos coherente.
Nueva evidencia en `/tmp/opencode/exagent-contract-f1a381/`, detalle en implementación
R6: owner73/0 matriz+seis probes intactos, focal integrado318/0, compile97/formato0
y FULL1041/0/28 WA48 seed37556 en193.2s. Review entonces pendiente;
no se atribuye aceptación a los verdes históricos siguientes.
Entrega previa: corregidos vínculo ToolReturn/outcomes↔journal en CAS/decode y limpieza exacta de
adhesión vacía tras fallo de capture/capacidad. Probes residuales intactos reprodujeron
3 rojos antes del cambio; focal ampliado272/0 WA seed37556 después. Incluye probes
originales y nuevos, fronteras/retención, owner death y guards de cleanup. Evidencia
en `/tmp/opencode/exagent-residual-f1a381/`; gate final1010/0/28 WA, max_cases48,
seed37556 (187.6s), compile95/formato exit0 y probes/focal final45/0 exit0.
No habilita secuenciador, run/resume ni aceptación R6 completa.

1. Elegir un objetivo funcional, marcarlo en curso y escribir su resultado esperado antes
   de modificar código. Reusar implementaciones/tests válidos; no reiniciar la base.
2. Revisar sólo sus fuentes, contratos y riesgos. Consultar documentación vigente
   de dependencias cuando cambie una integración; fijar la versión inspeccionada.
3. Para cambios observables, dejar decisión en diseño y migración en changelog/guía
   **antes de estabilizar la API**: problema, beneficio, alternativas, impacto y prueba.
4. Implementar una sección vertical utilizable; probar datos/efectos observables y
   controles negativos pertinentes. No considerar aceptación un mock de toda la feature.
5. Ejecutar focales afectados durante desarrollo y una suite integrada al estabilizar
   la vertical. Matrices completas ante cambios de integración/candidata, no por microhito.
6. Como máximo una revisión independiente del delta funcional acumulado. Corregir
   hallazgos con sus regresiones, sin re-review ni rerun rutinario del padre. R9 revisa
   integración/distribución y delta no revisado, no otra vez las unidades aceptadas.
7. Registrar evidencia y limitaciones aquí; actualizar estado sólo ante una aceptación
   significativa. Avanzar a la siguiente unidad sin pedir permiso rutinario para cada edit.

**Límites de inversión:** no nuevo framework de plugins, event sourcing completo,
parser por proveedor, cliente OTLP, motor distribuido o plataforma de evals por
comodidad. Usar release oficial y APIs públicas; no adaptación de fuentes upstream.
Un adapter público host debe ser pequeño y no reconstruir protocolos del proveedor.
No perseguir cero warnings ajenos ni reabrir la auditoría cerrada por inercia.
Si dos intentos no producen evidencia nueva sobre un bloqueo, cambiar de método,
acotar reproducción o pedir el dato preciso; no repetir el mismo gate esperando suerte.

Los nombres de módulos nuevos de abajo son orientativos. No son APIs publicadas;
el ejecutor elegirá firmas coherentes con la decisión documentada de cada unidad.

## R0. Preparación reproducible

**Objetivo:** comenzar sobre el trabajo real, sin perder WIP ni confundir evidencia
antigua con una ejecución nueva. Es un preflight, no otra auditoría transversal.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R0.1 | Inventariar HEAD, diff/untracked, nominal, lock y estado de gates. Identificar qué archivos contienen trabajo previo. | Registro recuperable; no reset/stash/clean ni checkout que pierda WIP. |
| R0.2 | Validar entorno aislado de `environment.md`, versiones efectivas y ownership de build. | Paths/toolchain observados; no reparación global de Hex ni secretos en logs. |
| R0.3 | Reproducir baseline offline pertinente y guardar contrato de partida para R1. | Comando/seed/pass/fail/excluded actuales; fallos nuevos clasificados antes de culpar al adapter. |
| R0.4 | Preparar registro de evidencia y lista única de accesos externos necesarios. | Proveedores/modelos/presupuesto, DB sintética y backend solicitados una vez; se puede seguir offline. |

**Fuentes:** AGENTS, estado, diseño2.1–2.3, verificación, entorno, mix/lock y CI.
**Salida histórica:** R1.1. Para retomar ahora, preflight breve de checkout/entorno
y gate R1.2; no repetir R0 completo ni inventariar Dragonex/WhoamAI.

## R1. ReqLLM como backend principal

**Recepción 2026-09-25:** dictamen fresco R1.5 `task_5b79c7a35e0c`,
`/tmp/opencode/exagent-r15-stock-review/REVIEW.md`: aceptable offline sobre TAR
`3c7867ad00661bd426e74e9f86a9f5440168d0bcdecfbff65c1950575fcdae42`,
173/173 exit0 y sin P1/P2 concretos pendientes; coordinador40 exit0 comunicado.
Se conserva suite owner751/0/28 seed37556 y consumidor48/0/0 de grafo fijo
copiado (no nuevo G5), lock `c20a0cb9…`. No es G2 ni cierre R1/C7.
Dispatch `task_08559dbb6a28` inicia sólo R1.3/6/7 del perfil `chat_tools_v1`:
reutilizar gates historia/settings y añadir evidencia compuesta de runtime/tools;
inventario preparatorio R1.8, sin retirada ni cambio de backend por defecto.

**Resultado owner R1.3/6/7:** cuatro oráculos nuevos, ningún cambio runtime/API:
continuation2 ligada a provider/model/endpoint, tool_choice auto|required efectivo
y Ecto/native preIO, dos compuestos ReqLLM stock TCP con delegación/Ecto retry,
Server stream, Session/ETS/savefailure/retry/restore, autoridad ancestral y OTel.
Compile80, focal16/16 y suite755/0/28 seed37556 exit0. Matriz criterio→test,
limitaciones, rojos de fixture e inventario mínimo de retirada en
`docs/archive/2026-09-25-r1-qualified-composition.md`. Revisión fresca recibida:
`task_990f3c2c9283`, dictamen aceptable offline, 4/4 e identidad del TAR final
`d2bfe978ba2d2906fd31be39378cdee971fac761239d6808319110001de4387d`, corrección
documental §5 cerrada y sin P1/P2 concretos pendientes. R1.8 por
`task_51127c5dd54e` dejó propuesta API/inventario antes de retirar código; dictamen
final recibido2026-09-26 según §5. Guards,
bounded postdecode/cleanup, unknown legacy v1/v2 y C7 pendiente permanecen.

**Objetivo:** sustituir responsabilidad propia de providers, no añadir otro modo
permanente. Referencia examinada1.24.0; resolver/aceptar versión y lock reales.
La [dirección](framework-direction.md) conserva hallazgos y fuentes del análisis.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R1.1 | Añadir dependencia en entorno aislado; comprobar API host estable, grafo mínimo y runtime; ADR del límite Model/ReqLLM. | Consumidor limpio resuelve/compila; sin dependencia Jido ni SDK/DB forzados. |
| R1.2 | Primero gate stock del sobre obligatorio genérico `{arguments: objeto}`; después integrar buffered/schema lógico sin prometer raw. Modelo/spec/instancia/gateway conservados. | ReqLLM real+transporte sintético; negativos cero efectos, vacío/no vacío válidos uno; schema/raíz/refs/strict/history/codec/output/autoridad según aceptación. No levantar guards antes de gate; stream se verifica junto a R1.4. |
| R1.3 | Perfiles explícitos, contenido/IDs/metadata permitida y codec/historia versionados con sobre exactamente una vez. | Mínimo Chat-compatible sin reasoning/provider-native; modelo→tool→modelo fiel, restore/compaction; excluir antes de IO paths que pierden metadata. Responses/Anthropic/Google por combinación, sin fallback silencioso ni todas obligatorias por catálogo. |
| R1.4 | Streaming una vista, lazy host, terminales y cleanup; preferir evaluar process_stream callbacks/Response final frente a events público. | Cero efectos incompletos; success/halt/error/EOF/timeout/cancel/owner kill cierran transporte/metadata. Deadlines/admisión/concurrencia y buffers propios postdecode chunks/bytes acotados/medidos; coste O(respuesta), sin hard RAM predecode. |
| R1.5 | Separar requests/intentos/tools exactos del host de tokens/cache normalizados/reportados y coste estimado; calidad/procedencia/disponibilidad, unidades y snapshots. | Cero normalizado no es observado ni heurística unknown; ordinary execution limitada por host sigue sin accounting; strict dependiente de datos ausentes rechaza. Cache/retries/evento-terminal/restore/hijos no duplican, migración Usage/OTel explícita. |
| R1.6 | Settings/tool choice/output/sobre/strict y retries; precedencia/auth ya textual conservada, subset no representable rechaza antes de IO. | Payload efectivo probado por perfil; no cambiar defaults/optional a required para strict en silencio; intentos host visibles, sin retries ocultos de efectos ni fallback wire/modelo. |
| R1.7 | Integrar run, stream_text, run_stream, hooks, scope, compaction, Server/Session, Store y OTel con nuevos contratos. | Paridad lógica/sobre/history/output/uso/cleanup; compuesto con efectos contados y consumidor del paquete, no extrapolar del tramo textual previo. |
| R1.8 | Migrar wrappers/gateways/extensiones y retirar transporte/adapters/helpers wire duplicados en la major tras aceptar perfiles requeridos. | Un backend general stock, Test/Model custom; inventario de retirada y migración de schema/history/codec/Usage/strict. No legacy general permanente; sin exigir todas las familias opcionales. |

**Decisiones obligatorias:**

- El sobre es hipótesis, no fix upstream. Validar sobre/schema lógico, hooks y
  args efectivos antes de autoridad/efecto; callbacks noop. JSON truncado o invalidez
  explícita jamás se reparan. Subset de refs/raíz/strict demostrado o rechazo preIO,
  sin rewriter general. Historia inválida no se vuelve válida al envolverla.
- Métricas upstream son orientativas con calidad/procedencia; no inventar presencia
  ni factura, ni heurística cero=unknown. La admisión host sigue siendo exacta/atómica.
  Datos ausentes no bloquean uso ordinario con límites host; solicitudes strict que
  dependen de ellos rechazan explícitamente, sin rebajar la API silenciosamente.
- Elegir una sola vista del StreamResponse; no enumerar eventos y después volver
  a materializar. No hard RAM predecode; sí límites propios postdecode/cleanup.
- ReqLLM no ejecuta nuestras tools ni administra aprobación/presupuesto. Capacidades
  ejecutadas en el proveedor se admiten antes de la request con política explícita.
- Delimitar tiempo total, pool/IO e intentos reales. Deshabilitar o contabilizar
  retries automáticos; no usar fallback de agente completo para un fallo parcial.
- Deprecaciones/floors sólo con impacto documentado; no elevar toolchain para ocultar
  warnings. Resolver los mínimos efectivos del grafo en vez de asumir el de ReqLLM.

**Archivos/fronteras:** `model.ex`, `message.ex`, `settings.ex`, `model_profile.ex`,
`models/`, `providers/`, `mix.exs`/lock, tests de provider/stream y fixtures TAR.
**Gate:** suite offline y consumidor mínimo/stream; revisión fresca de R1.4–R1.6.
La aceptación live pertenece a R8; todavía no se anuncia todo el catálogo soportado.

## R2. Contratos públicos del núcleo

**Objetivo:** cerrar ahora los puntos estructurales que eviten rupturas repetidas.
Conservar lo válido y corregir con una major coherente lo que limite casos generales.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R2.1 | Clasificar API estable/experimental/interna y revisar definición/run/resultado/error/contexto/evento. Diseñar estados `paused` sin implementar aún Store. | Un mapa público pequeño; mismo significado sync/stream/runtime; no aliases cosméticos ni modos de resultado divergentes. |
| R2.2 | Mensajes, proyección wire y codec versionados: args lógicos/sobre, contenido y continuación cualificados. | Roundtrip IDs/datos/orden; historia previa migra o rechaza explícitamente, nunca envolver inválidos ni fallback; provider incompatible falla preIO. |
| R2.3 | Ecto-tool con mismo sobre validado; JSON Schema nativo separado sólo donde cualificado; retry contabilizado. | Vacío válido/no vacío, inválido, null/embeds, refs/strict/schema no representable y retry sync/stream; Ecto autoridad final, sin reparación que legitime efecto. |
| R2.4 | Tool efectiva tras hooks: validación, allow/ask/deny, callable, batch, timeout y error de efecto incierto. | Denegación antes de efecto; hooks no cambian identidad ni amplían ancestros; cada call tiene outcome. |
| R2.5 | Revisar Capability/DI y selección de modelo/tools por request. Mantener estado/errores consistentes si falla un hook. | Tests de orden, aislamiento, error previo/posterior y contexto real entregado; sin segundo sistema de plugins. |
| R2.6 | Formalizar extensiones Model/Tool/Store/PubSub/policy y negociación de capacidades. | Un consumidor externo implementa Model y tool sin APIs privadas; soporte desconocido no se convierte silenciosamente en sí. |

**Prerrequisito de salida:** ADRs de mensajes, resultados pausados y capacidades
están escritos antes de R4/R5. No es un permiso para rediseñar todas las structs.
**Gate:** contratos core/tool/schema/event, paridad de superficies y snippets públicos.

## R3. Runtime, contexto y coordinación

**Objetivo:** ownership e identidad al estilo de los patrones útiles de Jido,
aplicados a Server/Session existentes en vez de envolver otro AgentServer.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R3.1 | Identidades de agente/conversación/run/request/participante e intentos; correlación y lifecycle público. | IDs estables donde corresponde, intentos distinguibles, terminal único por owner vivo, late events aislados. |
| R3.2 | Cola, busy/queue_full, steer/follow-up, deadlines y cancelación de descendientes. | Dos callers, saturación, timeout y muerte brusca: orden y cleanup observados; cola volátil descrita como tal. |
| R3.3 | Scope: contadores host/admisión atómica, autoridad ancestral, métricas estimadas con calidad/availability e identidad; restore por datos. | Competencia por una request; ordinary execution sin accounting y strict rechazado explícitamente cuando falta; snapshots/retries/hijos sin doble suma ni unidades confundidas. |
| R3.4 | Proyección/compaction y límites de entrada/salida/payload; sobre wire e historia lógica separados. | Historia canónica/codec intactos, call/result pareados y sobre una vez; límites propios postdecode e historia medidos, sin promesa hard RAM upstream. |
| R3.5 | Session single-writer y políticas, join/leave/handoff/restore, referencias confiables y namespaces de consumidor. | Turnos humanos/agentes y cambios concurrentes coherentes; mismo ID en namespaces distintos no mezcla datos. |
| R3.6 | Contratos de extensión del runtime para integración Phoenix/jobs. | Ejemplo mínimo de eventos e interrupción; nunca se equipara PubSub a cola durable ni reinicio OTP a replay seguro. |

**Archivos:** Server, Session/policies, ExecutionScope, RunStream, Compaction,
Event/PubSub y pruebas de secuencias/ownership existentes.
**Gate:** secuencias finitas con oráculo de efectos/estado y carga smoke relevante.
No scheduler distribuido, Pods ni hibernación automática obligatoria en esta fase.

## R4. Persistencia que permita continuar con seguridad

**Objetivo:** conservar checkpoint confirmado y añadir los mínimos atómicos que
necesitará C7. Guardar datos y progreso, nunca una pila Elixir o callback serializado.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R4.1 | ADR de datos durables: conversación, ejecución/continuación, aprobación y outcomes de efectos. IDs, revisiones y versiones separados. | Schema explícito, datos mínimos, referencias a definiciones confiables; sin secrets/pids/funs ni snapshot que elija módulo arbitrario. |
| R4.2 | Extender Store con capacidades para guardar transición y reclamar revisión de forma atómica; decidir transaction/CAS del adapter. | Dos claimants no ganan; conflicto explícito; store que sólo admite snapshots rechaza continuación antes de efectos. |
| R4.3 | Adapter ETS para semántica local y Postgres durable con migraciones propiedad de la app. Conservar modo DB-free. | Misma conformidad de API, rollback/conflictos observables, ETS etiquetado efímero; DB real se acepta en R8. |
| R4.4 | Revisión dirty/ACK/retry-save y recuperación de writes interrumpidos; lectura de snapshots v1/v2 ya soportados. | Save fallido no confirma éxito ni reejecuta tool/change_fn; corrupción/futuro/mismatch no sobrescribe estado válido. |
| R4.5 | Claim/owner/attempt/fencing para rechazar resultados de owners obsoletos; política de trabajos in-flight inciertos. | Crash entre claim/efecto/save preserva incertidumbre; expirar un lease no da permiso para repetir un efecto externo. |
| R4.6 | Retención, borrado explícito por namespace, estado diagnóstico y backup/restore documentados. | Cleanup no elimina una aprobación activa ni cruza scopes; migración/restore probados con datos sintéticos. |

**Contratos a decidir antes de código:** granularidad de transacción; identidad de
idempotencia; qué write es ACK durable; fencing y recuperación tras pérdida del owner;
versionado de definiciones; política de retención. Usar callbacks de capability
opcionales cuando sea suficiente; no fingir CAS mediante load+save separados.

**Gate:** conformidad Store y fallos intercalados; revisión fresca. La transacción
Store no vuelve transaccional la API externa que llama una tool.

## R5. Aprobación persistida y continuación acotada (C7)

**Objetivo:** una ejecución puede quedar esperando decisión humana, liberar sus
procesos y continuar una sola vez por revisión aceptada, incluso tras reinicio.
La decisión del usuario incluye esta capacidad en la v2; no se rebaja a un callback
bloqueado en memoria para cerrar la fase.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R5.1 | Máquina de estados y API: pendiente/decidida/reclamada/en ejecución/completada/denegada/expirada/cancelada/incierta; transiciones legales. | Tabla de transición, terminales e invariantes; firmas/errores/versiones en diseño y migración. |
| R5.2 | Pausar antes del efecto con tool/args efectivos validados, hash de payload, call ID, policy/definición y progreso del batch. | `paused`/approval event sólo tras save confirmado; cero efecto de la call pendiente y sin proceso bloqueado necesario para recordar la petición. |
| R5.3 | API de approve/deny/cancel/expiry, correlación y contexto de actor proporcionado por la app confiable. | Decisión repetida idempotente; decisiones opuestas/revisión obsoleta/actor no autorizado rechazadas; ningún LLM se autoaprueba. |
| R5.4 | Resume desde plantilla confiable: rehidratar tools/deps, revalidar schema/permisos actuales y reclamar continuación. | Reinicio de VM con DB sintética, dos resumers concurrentes y cambio de policy/definición; sin ampliar autoridad ni repetir pasos confirmados. |
| R5.5 | Pausa en batches/delegación/composición: guardar outcomes ya completados, presupuesto y árbol lógico; alcanzar frontera sin IO propio en vuelo. | Hijo pide aprobación, hermanos completan/se cancelan según política explícita, root retorna paused; al continuar no hay doble uso ni tools huérfanas. |
| R5.6 | Resolver crash con efecto incierto: estado inspectable y reconciliación/retry explícito con idempotencia de aplicación cuando proceda. | Crash antes/durante/después de efecto: nunca retry ciego; registrar resultado recuperado sin simular rollback ni exactly-once. |
| R5.7 | Eventos y stream: terminal de pausa, nuevo stream al continuar, estado disponible por consulta; UX ejemplo sin dependencia web obligatoria. | Pérdida de PubSub no pierde aprobación; consumidor puede reconectar; cola posterior no salta una ejecución pendiente inadvertidamente. |

**Precisiones de contrato:**

- La aprobación autoriza la llamada exacta, no una tool cualquiera con argumentos
  nuevos; modificación de args requiere nueva decisión. La policy vigente puede
  restringir más al reanudar; bytes persistidos no amplían autoridad.
- No guardar contexto de OTel, GenServers, task refs ni secretos para rehidratar.
  Deps/auth provienen de callbacks/configuración confiables del host.
- Persistir deadlines/expiraciones con semántica válida tras reinicio; tiempos
  monotónicos de una VM no son timestamps portables. Definir qué tiempo cuenta
  durante espera humana para no expirar ambiguamente el presupuesto del run.
- Un stream terminado con pausa no revive: la continuación abre otro consumo
  correlacionado al mismo trabajo lógico y un intento nuevo.
- El claim impide dos decisiones/resumers activos para una revisión; no garantiza
  una sola escritura externa ante caída después del efecto. Ese caso se expone.

**Gate:** escenarios A5–A7 de aceptación, diario de efectos, muerte real de owners
y restore en nueva VM; revisión fresca antes de anunciar C7 implementado.

## R6. Composición multi-agente

**Objetivo0092026-10-01:** Flow11 router confiable y paralelo acotado implementados
con ordered outcomes, fail_fast/collect, max32 ramas/concurrency32(default4),
resultados JSON separados64KiB y journal Scope/CAS/C7 únicos. A8offline cruza dos
VMs/crash Dfinal anteswrapper, completando sin repetición de fuentes/historia.
Selector/merge admitidos sin resultado tras VMcrash quedan uncertain sin replay ni
refund; owner Model muerto conserva el mismo guard. Native span parentage público
tool→delegation→D y Flow→branch probado. ADR8.44 y R6 implementation registran
causas/oráculos/rojos. Matriz final73/73,149.3s y compatibilidad puntual10/9 11/11,
10.2s, exit0 en fuente post-fixes. Previa183/183,155.2s, fuente pre-findings.
Review única009 cerrada: P1 drain approval concurrente y dos P2 de plazos corregidos
por el dueño, con casos known/unknown y ACK perdidos, sin segunda revisión.
recetas R6.4, SQL/A8 y candidato/FULL se reciben separadamente sin rerun rutinario.

**Recepción vigente2026-10-01:** secuencia/restore9 y C7 aceptados offline; contratos
y CAS10 aceptados internamente, incluido agotamiento/reserva compuesta. Completed y
legacy7/8/9 conservados. Producer/restore10 y delegación real con C7 quiescente y
recuperación entre VMs tienen evidencia ejecutada4/4 y matriz26/26. Integración
completa terminó1543/2093pases con550rojos de retry y fixtures/oráculos históricos.
La única review detectó dos P2:corregidos6/6; regresión20familias cerrada784casos
distintos (legacy9 auténtico/ACK10/runtime10),13rojos intermedios corregidos/verificados.
Sin FULL final global nuevo de001 ni aceptación general R6. Router/fan-out/fan-in
son el nuevo009 indicado arriba. Evidencia/límites en implementación R6 y CURRENT vigente.
Los hitos inferiores conservan evidencia y pendientes históricos de su fecha.

**Nuevo hito interno2026-09-28 — paso único, parcial:** seam ExAgent→Writer que
confirma input/enlace real step antes de ejecutar el loop hoja original y confirma
output/cursor después, con mismo Scope/journal/CAS/fila. Frame5 y hojas Frame3,
root0operations; Frame4 vacío y fix de preflight del padre conservados. ACK input
bloquea IO, ACK output retry sólo datos. Inspección desde bytes distingue pendiente
y completado, pero **no hay reanudación ejecutable de hoja interrumpida**: falta
persistir/restaurar el piso de autoridad raíz. No Composition.run/resume público,
A→B, delegado ask/resume ni aceptación C7 composición. Evidencia propia/delta en
`/tmp/opencode/exagent-r6-step-f1a965/REPORT.md`; ver propuesta y ADR8.38. Review
independiente del nuevo delta pendiente. Los hitos inferiores conservan su evidencia
original; la aceptación/fix posterior de raíz vacía figura en la tabla de recepción.

**Actualización de revisión/recuperación2026-09-28:** la review independiente
detectó P1 (completion sin evidencia Model ligada) y P2 (ticket retenido tras
rechazo preattach). Correcciones recuperadas tras fallo del proveedor del worker,
todavía pendientes de revalidación independiente:56focales/probes originales/tool
real/MCP verdes, compile95/formato0 y suite habitual **1001/0/28 WA max_cases48**,
seed37556,184.8s, exit0. Fixture MCP separa handshake default+ready de request50ms;
runtime MCP intacto. Esto resuelve el gate concurrente pendiente de abajo, pero
no acepta el paso ni R6. Evidencia en
`/tmp/opencode/exagent-blockers-f1a4bc/RECOVERY.md`; rojos originales conservados
en `docs/orchestration/2026-09-27-native-f1ace1/tasks/r6-step-review.md`.

Evidencia original de este delta:13tests nuevos, focal107/0 WA, compile95/formato/diffcheck0;
suite completa994/0/28 WA **max_cases1**, seed37556. Gate habitual48 pendiente:
dos suites993/1/28 por el mismo timeout del test MCP.ClientTest:140, aislado3/3.
No se tocó MCP ni se considera resuelta su causa; no convertir el verde serial en
aceptación del gate concurrente. Logs y freeze separados en el informe del paso.

**Hito adicional2026-09-28:** apertura/claim de raíz estructural vacía implementados
en el Writer/Checkpoint/Transition/Store actuales, Record2/execution2 y Frame4
estrictamente vacío, snapshot composition1 sin Model. JSON/load/get y callbacks
negativos, segundo claimant, ACK perdido, fencing y J+cleanup:8tests nuevos,
focal92/0, compile95, suite979/0/28 WA seed37556 exit0. Evidencia
`/tmp/opencode/exagent-r6-root-f1a965/REPORT.md`. Sin hojas/step links/secuenciador,
sin run/resume público ni cierre R6/A8/C7 composición. Review independiente pendiente.
La propuesta detalla los campos/operaciones rechazados hasta el siguiente hito.

Hito parcial2026-09-28: raíz estructural interna ExecutionScope sin Model, con
admisión/contabilidad ancestral existente y restore Scope2 sin operaciones propias
ni repricing. Ocho tests nuevos, focal54/0, compile94 y suite971/0/28 WA seed37556
exit0; informe `/tmp/opencode/exagent-r6-structural-f1aae/REPORT.md`. Sin cambio de
formatos legacy ni Writer. NO secuencia durable: siguen pendientes snapshot/Frame
discriminados, step links, Writer/seam de hojas y run/resume/input/output/C7. No
bloqueo técnico demostrado; entrega parcial, no cierre R6.2–3 ni A8.

Histórico de la primera subunidad: ADR8.38 y propuesta
`docs/development/r6-implementation.md`, secuencia durable A→B con delegado de B
pausado. Constructor/binding definition1 implementado y focales verdes; sin
ejecución/pausa de composición ni gates runtime aceptados. Router,
paralelo y cierre R6 siguen pendientes.

**Objetivo:** resolver flujos habituales sin escribir un graph engine universal.
Reusar el run y scope aceptados; Session sigue coordinando participantes/turnos.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R6.1 | ADR de composición: secuencia, routing explícito y fan-out/fan-in acotado; agente como paso o tool. | API mínima y resultado común; no confundir grafo de ejecución con historial ni con topology de procesos. |
| R6.2 | Implementar composición y resultados parciales con orden de merge determinista y políticas fail-fast/collect explícitas. | Ramas desordenadas, una falla, límite compartido y cancelación; contabilizar y conservar todos los efectos observados. |
| R6.3 | Integrar pausa/continuación: definition ID/version confiables, cursor y outputs de pasos confirmados. | Secuencia y rama delegada pausadas/restauradas; no persistir funciones ni repetir pasos finalizados; cambios de definición rechazan o migran explícitamente. |
| R6.4 | Recetas genéricas: extracción tipada, supervisor/especialistas y pipeline con revisión humana. | Ejecutables desde paquete, con tests deterministas de decisiones/efectos; no reglas de una app real en el core. |

No incluir DSL de grafos arbitrarios, scheduler distribuido o todas las estrategias
ToT/GoT/ReAct por paridad comercial. No añadir retries automáticos de un workflow
completo. Si una nueva abstracción no simplifica las recetas, revisar su necesidad.

## R7. Observabilidad e integraciones

**Objetivo:** operar y extender el paquete sin acoplarlo a un dashboard o framework.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R7.1 | Una instrumentación por operación con contexto ReqLLM; contadores host separados de uso normalizado/estimado y calidad/procedencia/unidades. | Correlación run/tool/child/request/checkpoint; availability preservada, cero normalizado no observado; sin duplicar subtotales/coste/spans ni traces cruzadas. |
| R7.2 | Ruta OTLP operable, procesador/exporter y límites/errores documentados; reevaluar componentes propios sólo con evidencia. | Tipos/partial-success/fallos/cleanup reales; backend lento no bloquea al agente; pérdida acotada observable. |
| R7.3 | Trazas de pausa y continuación e integraciones Langfuse y Opik igualmente cualificadas, mandato2026-10-02. | A10 nativo/API/UI aceptado en ambos: dos intentos correlacionados, aprobación/save fallido y recuperación; no span abierto durante días. Recibos separados en§5, mismo oráculo12casos/248attrs. |
| R7.4 | Consolidar MCP cliente stdio y añadir cliente remoto Streamable HTTP mediante dependencia mantenida o adapter pequeño. Elegir por evidencia antes de implementar transporte. | Tools externas siguen validación/permisos/C7; auth por conexión, sesiones, timeout/cancel/late reply y cleanup en transportes aceptados. |
| R7.5 | Recetas Phoenix.PubSub/LiveView y job externo; recuperación de estado, streaming y approvals por APIs públicas. | Consumidor sin Phoenix sigue funcionando; actor/autorización resueltos por app; un job reintentado no autoriza replay de effects. |
| R7.6 | Receta retrieval/memoria externa como tool/Capability y diagnóstico de configuración mínima. | Dos espacios aislados, referencias/payloads acotados y contenido no confiable sin autoridad system; sin vector DB obligatoria ni motor RAG propio. |

Seguir [backend](backend-evaluation.md) para las dos integraciones aceptadas y sus límites.
Proveedor-native MCP/tools no sustituye nuestro cliente ni hereda mágicamente el
control de tools locales. Elegir explícitamente qué capacidades se admiten.
No adoptar un paquete deprecado por aparecer en la comparación antigua.

### Integración R7 recibida — 2026-10-01, alcance acotado

Objetivos002/005/006/008 y revisión única011. El harness portátil ejecuta los
cinco perfiles SDK MCP2.2.0 originales sin editar el SDK:38requests únicos,
10effects y cierre de5peers/4listeners. Recibo final
`/tmp/opencode/exagent-v2-codex-t6qgpstl/mcp-sdk/exagent-mcp-sdk-a2fq1cx3/report.json`,
SHA256`ad351d306b4d43c37848fd006790f4c670b0b4e3bc6ad57f453d603d879b0ca9`.
Es evidencia de esos perfiles, no nuevos casos por la ejecución posformato.

El binding C7 MCP liga destino/principal host, protocolo/transporte y digest de
URL pública; sesiones/headers/secretos no se persisten. Cambio de target/principal
rechaza antes de IO, misma identidad permite rotación de credenciales. Doce rutas
integradas byte-idénticas; focal combinada11/11,exit0, sin skips, después de001,
sin repetir150/SDK. Recibo combinado SHA256
`3f75e5c98b90b638db4d582f28fb7fda9223e452a0777cddc02babf3281dc6fd`,
en `mcp-integrated-c5epccv5/receipt.json` del mismo lote. Design8.43 y
[guía del binding](mcp-continuation-binding.md) describen migración y límites.

Dictamen único `r7-review/REPORT.md`, SHA256
`f12f36815a00232539de9dad28d606ea9c5c6bd22e5b83f8e912a4d7bc040f38`:
un P2 de excepción privada en retrieval; ningún otro P1/P2 concreto en el perfil.
El dueño lo corrigió en la frontera del callback y regresó error devuelto,
excepción, throw y exit capturable: una búsqueda,request1/tool1 por fallo,
ToolReturnfailed y detalle privado ausente. VM privada exit0, sin re-review;
`r7-review/retrieval-owner-fix.log`. Fuente de receta corregida SHA256
`8949b1365eb5e9901135df8111c5eba03a9db2dbe72af37c70d2bc1e040a75fa`.
Retrieval mantiene dos espacios sólo host y cotas3hits×2048bytes. El job público
usa get/run/decide/resume y los duplicados pending/completed no añaden IO.

Esta recepción acepta esas unidades offline acotadas. No cualifica por sí sola
OAuth/TLS/cancel/reconnect/chaos con SDK, protocolos nuevos, servicio retrieval,
Oban/LiveView reales, SQL, TAR final o G4. Las referencias MCP declaran identidad
confiable; no autentican el peer ni la correspondencia de unas credenciales.
Los siguientes consumidores prueban las recetas contra frameworks reales y la
candidata. La ruta OTLP004 tiene8casos+C7+3ciclos privados;010 prueba Collector
oficial temporal→HTTP antes de una nueva ola backend admitida.

## R8. Cualificación de producción

**Objetivo:** demostrar los perfiles del alcance con la candidata, no extrapolar
desde tests offline o el número de modelos del catálogo.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R8.1 | G2 del mínimo Chat-compatible sin reasoning/provider-native; otras familias/modalidades/gateways por capacidad anunciada. | Modelo/versión/endpoint/API/config fijos; tools/sobre/Ecto/stream/history/error/uso real; presupuesto autorizado. Ninguna aceptación por catálogo ni fallback silencioso. |
| R8.2 | Postgres real para Store, continuaciones/approval claims y migraciones; restart/backup/restore. | Revisión/outcomes sobreviven nueva VM; claims concurrentes, caída/timeout DB, retry-save y recuperación incierta observados. |
| R8.3 | Consumidores TAR independientes: mínimo, runtime, durable, extensible e instrumentado. | Mismo hash; instalación sin checkout/symlink, API pública, grafos opcionales y casos A1–A10 pertinentes. |
| R8.4 | Carga/aislamiento: streams lentos, saturación, owners efímeros y pausas; admisión/deadlines/retención propia postdecode. | Umbrales previos en chunks/bytes/concurrencia, coste upstream O(respuesta) e historia descritos; conteos completos, cero contaminación y cleanup medido, no hard RAM predecode. |
| R8.5 | Matriz runtime/deps y CI portable offline + jobs externos opt-in. | Mínimo declarado y combinaciones publicadas verificadas; CI remoto sobre revisión exacta, artefactos por fase y TAR incluido. |
| R8.6 | Matriz pública y guía operativa: capacidades soportadas/limitadas/no verificadas, límites, configuración, diagnóstico y recuperación. | Cada afirmación enlaza a evidencia; excluidos no pasan; perfiles que requieren DB/backend no se aceptan con fixtures. |

Targets tras resolver R1.1: Elixir1.18/OTP28 y1.20/OTP29; `llm_db` obligatorio
exige1.18 y sustituye el objetivo inicial1.17/OTP27 (decisión autorizada, diseño8.15).
Fijar patches y registrar ejecuciones en R1/R8; no implica soportar cualquier par.
Los gates A1–A10 y G1–G6 se detallan en [aceptación](production-acceptance.md).

## R9. Candidata, revisión y publicación

**Estado2026-10-02:** la implementación requerida tiene fuente y evidencia
cualificada en§3. La pasada única R9 de integración/distribución está cerrada:
seisP2 corregidos mediante recibos owner, sin segunda review. El
preview final incorpora documentación/soporte posterior a019, manteniendo los
contratos runtime y lock. G4 visual está aceptado; CI remoto exacto impide anunciar el cierre
de todos los gates; los diagnósticos estrictos upstream permanecen visibles.

| ID | Trabajo / entrega | Aceptación |
|---|---|---|
| R9.1 | Congelar alcance e identificar candidata: revisión + WIP/hash, lock, manifiesto, changelog y migración1.x→2.0.0. | Ninguna feature requerida pendiente; APIs/snippets/docs actuales; los ejemplos no dependen de secretos/paths del host. |
| R9.2 | Una revisión de integración/distribución y delta aún no revisado, siguiendo `docs/prompts/testing-review-final.md`; resolver hallazgos sin re-review. | Sin defectos propios bloqueantes; correcciones prueban fronteras afectadas y generan nueva identidad de candidata. Reutilizar evidencia de capacidades ya aceptadas. |
| R9.3 | Gate integrado final de distribución y operación, guía de upgrade/rollback y lista de límites conocidos. | TAR candidato y evidencia corresponden al mismo contenido; ready-to-release claramente separado de publicado. |
| R9.4 | Con autorización expresa: bump2.0.0, commit/tag/push/publicación según alcance autorizado; reconstruir/verificar artefacto final. | El TAR final se vuelve a identificar/probar; instalación limpia del publicado coincide con lo aceptado. |

La solicitud actual prepara el plan y fija el objetivo2.0.0, no autoriza publicar
ni modificar consumidores. Sin permisos de R9.4, terminar como **lista para
versionar/publicar**, nunca como «v2 publicada». Una revisión de fuente no demuestra
por sí sola fiabilidad de la release instalada.

## 4. Bloqueos externos y reglas de escalado

| Bloqueo | Qué necesita el ejecutor | Trabajo independiente disponible |
|---|---|---|
| Providers reales | Modelos/endpoints y presupuesto total/concurrencia autorizados; credenciales por canal seguro | Fixtures de integración, contratos, docs y consumidores offline |
| DB | Postgres sintético aislado, namespace, permisos de migración/destrucción de datos de prueba | Conformidad Store, errores y CAS con fixture local |
| Observabilidad | Instancia/proyecto Opik, versión, endpoints y acceso a API/UI con datos sintéticos | Transporte local y spans/privacidad/recursos |
| Gap upstream ReqLLM | API pública de release oficial suficiente para el perfil | Gate pequeño, excluir perfil afectado/seguir release futura; sin fork/patch/parser privado |
| Gap MCP/OTel | API pública suficiente o corrección acotada/versionada | Reproducción de frontera y otras unidades |
| CI/revisión final | Revisión disponible en remoto y autorización Git necesaria; revisor fresco | Gate local, candidata no publicada e inventario de delta |
| Publicación | Permiso expreso para las operaciones release | Entrega lista para versionar/publicar |

Bloquear sólo la unidad afectada. Un bloqueo que impide una garantía obligatoria
no puede convertirse silenciosamente en «limitación aceptada» para cerrar v2:
proponer el cambio de alcance al usuario con impacto. Diseño8.22 ya aprobó los
límites y métricas revisados, no otros recortes. No usar ningún fork/patch/vendor,
monkeypatch ni API privada ReqLLM como salida de un bloqueo.

## 5. Registro por subunidad y relevo

Las casillas/estados viven aquí. Los informes técnicos pueden añadir evidencia,
pero no una segunda lista de trabajo. Al cerrar una unidad, registrar:

Toda subunidad empieza pendiente mientras no tenga un registro explícito. Añadir
una fila al iniciarla y actualizarla al verificar/bloquear; el estado de fase sólo
cambia cuando se cumplen todas sus condiciones de cierre.

| Subunidad | Estado | Evidencia / siguiente acción |
|---|---|---|
| Revisión crítica adicional027 | Cerrada e integrada;1P1/4P2 corregidos | Tres scopes disjuntos sobre026: C7 multirronda8/8 y restore previo sin replay; subtotal sparse5causales+25adyacentes; ownership/rollback/privacy OTLP seis controles privados y4 rutas portadas. Fuentes finales cotejadas por SHA; lock intacto. Sin re-review/paid/cloud. Diagnóstico14s retirado por oráculo insuficiente. Identidades y límites en CRITICAL-REVIEW del checkout; derivada posterior se sella aparte. |
| E2E consumidor real028 | Cerrado:18 escenarios aceptados externamente | `exAgentTest/chat_app` migrado a ReqLLM stock; GPT-4o-mini/OpenRouter. Ola inicial13/18 y cinco repeticiones causales, diagnóstico06 conservado;40admisiones/USD1.00 reserva de60/USD1.50, input16KiB/10messages/output512. Siete grupos cerrados y fuentes por ola;18 verdes suman36requests/13efectos, no único18/18 inicial ni factura. Driver review única3P2/12controles y admisión offline entre dosVMs. Nuevo bug Frame/instrucciones System corregido:3regresiones strict+45adyacentes, sin formato/lock nuevo. Consumer precommit15offline/18excl/exit0; `.env` y modelos preservados. Lote múltiple06 sin aceptar, finalsecuencial;17 consulta completed administrativa. Guía real-consumer-e2e y E2E-ACCEPTANCE del checkout. Sin Git/bump/Hex; CI remoto pendiente. |
| R1/R8.1 G2mínimo | Cualificado2026-10-01 sobre019 | GPT-4o-mini/OpenRouter chat_tools_v1,14/14,17admisiones/3efectos; reserve0.425USD/billingnull. Receipt525b4d71…f979d. Sin más paid IO. |
| R4/R5/R6/R8.2 G3real+A8 | Cualificado2026-10-01 sobre019 | PG17.4,14fases,29hijoscleanup, SHOW5s, ACK perdido/dosVMs/restart/Flow/backup. Receipt3ad0613e…bfd8; driverfix exacto importado. |
| R6.4 recetas | Verificado2026-10-02 sobre019 | typed/router/review humana y completed inerte; source5c681b7b…9fdb5, recibo81727513…6aec. Efecto/mapper una vez. |
| R7/R8 frameworks+SDK | Cualificado2026-10-01 sobre019 | LiveViewTest/Oban SQL6/6+crash73/recover0 y SDK5/5. Sin browserJS/HA/OAuthTLS ni protocolos adicionales. |
| R7.3/R8 G4 Langfuse | Aceptado2026-10-02 en perfil A10 | Pareja nativa33spans/667attrs/12usage API; UI autenticada12observaciones/248attrs y cinco capturas. ReceiptAPI4fb95d1a…6c825/UIa2058c08…d8f3; cero reruns Producer/Collector/Model. |
| R7.3/R8 G4 Opik | Aceptado2026-10-02 en perfil A10 | Candidata025, tehsuso/exagent,18+15spans/5POST/33ACK, API4GET2786ms/33rows/667attrs/12usage. UI12casos/248attrs y siete vistas reales inspeccionadas; recibo e0a9be73…3e0f9. Mismos criterios que Langfuse, sin certificar estabilidad de UI. Fallos500ms/1s y navegación/captura preservados; perfilHTTP3s finito. Registro checkout OPIK-ACCEPTANCE. |
| R8.3–5 consumidores/CI | Runtime56PASS; strict RED; remoto pendiente | Ocho grafos1.18.4/OTP28 y1.20/OTP29. Report6505474c…1bd4. Warns oficiales clasificados; CI conserva sus exits y precisa autorización Git exacta. |
| R8.4 G6finito | Cualificado2026-10-01 sobre019 | 18rows+2soaks+saturación64/cap32, cota lote8/máximo observado2; receipta2f63d9b…cef49. TestModel/cleanup medido, sin SLO/soak prolongado. |
| R9/G1 candidata | Preparada2026-10-02; CI remoto pendiente | FULL2157/28sin fallos/exit1warnings; corrección136focales exit0/0warns; ExDoc104HTML/0enlaces propios rotos. Revisión única1/1 cerrada y preview documental; no publicación. |
| R6.3 evidencia activa Frame9 | Aceptada offline acotada2026-09-29, vigente | Final/resuelto/accounting aceptado/control completo, ownprefix/outputretry/success y approvals consumidas, misma resume API. Owner FULL1845/28/1410.3s exit0/compile109WA/formato/diff0,55=25+30; review40existentes+4propios,9+306identidad; padre9hashes y mismos4probes4pases/16.7s exit0. Informes/SHA en implementación R6. Rojos owner54/55 y review3/4 preservados. No mixed/raw/uncertain/delegación/router/paralelo/R6 general/SQL/live/producción. Siguiente: research sólo lectura delegación+C7 quiescente/mixed-control. |
| R6.3 C7 secuencia primer batch todo-pending | Aceptado offline acotado2026-09-29, anterior a evidencia activa | Pausa ACK raíz/hoja proyectada, halt C, dos decisiones host, nuevo claim y resume VM; prefix/counters/budget/refund exactos. Owner FULL1790/28/1121.2s; review271existentes+7propios/compile108WA/formato/diff0, identidad15+303; padre15hashes y mismos7probes7pases/13.2s exit0.57owner=43+14. Informes/SHA y provenance en implementación R6. Sin atomicidad preadmisión mixed, general R6/raw/delegación/router/paralelo/SQL/live/producción/MCPprincipal. Próximo trabajo de ese hito: investigación sólo lectura. |
| R6.3 recuperación ready9 acotada | Aceptada offline2026-09-29, antes de C7 | Empty/between/input sin operaciones y terminal seguro, prefijo inerte, claim ACK/deadline/guard postintent. Owner FULL1733/28/967.8s, review29+113+3, padre6hashes y mismos15probes/12.6s exit0; evidencia en implementación R6. C7 se acepta en la fila superior; resto de batch/output-retry general permanece abierto. |
| R6.2–3 secuencia durable Frame9 | Aceptada offline acotada2026-09-28 | Composition.run N pasos, único Scope/Writer/claim/budget, mapping confirmado y refund raíz final; completed data-only, lifetimes7/8 y subsets single-leaf9 conservados. Owner FULL1673/28/885.2s exit0, review62+5copia+2terminales; padre26hashes y mismos7probes7/7 exit0. Identidades en implementación R6; rojos históricos intactos. Pendiente restore activo multileaf/C7 composiciones/rawuncertain/delegación/router/paralelo/R6 general/SQL/live. |
| R7.4 interop SDK independiente | Aceptada offline acotada2026-09-28 | Python mcp2.2.0; stdio2024-11-05, HTTP2025-06-18 JSON/SSE session/stateless, text tools localhost. Owner5/review5 mismos casos sin skips, identidad ROOT/copia cotejada; informes/hashes/límites en§3. Harness portable pendiente; no OAuthTLS/cancel/reconnect/chaos/C7binding/protocolo2026/otrosSDK/multileaf/SQL ni cierre R7.4/A9/R7/G4. |
| R6.3 Frame8 final/control/prefix | Aceptado offline acotado2026-09-28 | Single-leaf con prefijos continuables y batch actual final/resuelto; sin replay ni doble accounting, host/preparación vigentes. Review50distintos (43+3+4), padre3probes intactos exit0/9.3s/source12/12; REPORT326c054b y owner74024782 identificados en§3. Owner compile107/focal261 (99nuevos)/MCP37/FULL1568pases28excluidos716.8s exit0 separados; FULL fallidos preservados. MCP delta test-only causal de dos órdenes, runtime intacto. Raw/uncertain/no-control/rejected/omitted/legacy7tools/approval-retryplans/delegación/A→B fuera. R6 general y SQL/cloud/live abiertos; siguiente unidad por propuesta contrastada. |
| R6 productor: contadores runtime-owned en hooks Model | Aceptado offline2026-09-28 | Seis campos restaurados tras cada capability; transforms legítimas/mapas genéricos intactos. Review124focales+8probes, padre8probes intactos WA48seed37556 exit0;15/15hashes/delta cotejados. Informe `/tmp/opencode/runtime-counters-review-f1815c1c/REPORT.md` SHA68b62e7780418bb22870da58dc875ce5a5e27ace75b92369743b1e4ef80a4f1a. Owner rojo4/matriz44/focal371/FULL1354pases28excluidos482.0s WA48seed37556/compile101/formato0 separado. Legacy retry/usage siguen ambiguos, sin evidencia durable nueva ni apertura restore/R6. |
| R6 integridad histórica batch/usage | Batch aceptado offline2026-09-28; usage BLOQUEADO | Validación Frame común de cardinalidad histórica/actual por request. Review141focales+4probes, padre4probes intactos WA48seed37556 exit0,13/13hashes/delta cotejados. Informe `/tmp/opencode/final-tools-review-fresh-20260928/REPORT.md` SHA54643917143e985b07d8c2ad712890c627a354b48cfb5c456646e73e81b7d301. Owner compile101/focal357/FULL1310pases28excluidos WA48 seed37556 exit0/formato0 separado. ToolReturn.usage no se serializa/hashea: falta evidencia independiente por call; no inventar cantidades. Red-final1/3pasa: usage/retry siguen rojos conocidos. Guards/counters intactos, no aceptación restore/R6/SQL/live. |
| R6.3 cadena output atestada | Aceptada offline2026-09-28 | Runtime sólo CompositionRestore; atestación actual success/retry tras N respuestas Model confirmadas sin batches/tools, Record/consumidores intactos. Review208focales+7probes, padre7probes intactos WA48seed37556 exit0; delta leído/manifiesto17/17 cotejado. Informe `/tmp/opencode/output-chain-review-f186a998/REPORT.md` SHA81fb2bb19acabcde880cbb6912ca4d9dcb45440ff7913bc005e5d500db7981ed. Owner rojo5/matriz134/focal578/compile101/formato0/FULL1287pases28excluidos WA48 seed37556,468.9s exit0 separado. Historia mixta/VM/CAS/ACK/crash/corrupción/autoridad/retención. TextoN sin atestación/batches/incertidumbre/A→B fuera; no cierre R6/SQL/live. |
| R6.3 primera response textual | Aceptada offline2026-09-28 | Frame7 response1, un Model confirmado y una operación, host text/tool; mismo loop/Writer/Scope, sin nuevo IO/mapping/after_model/Ecto ni repricing. Review169/0 con matriz37 final y pisos/input0; padre37/0 WA48, manifiesto11/11 cotejado. Informe `/tmp/opencode/exagent-text-review-f19634a3/REPORT.md` SHAe33afbafb943d5a8fd03533064f7e0eba53cab6fe5b99a0608cdd8d7f2fd4a0c. Owner compile99/formato/FULL1125/0/28 WA48 seed37556,258.8s. Probe suplementario reviewer no ejecutado no cuenta como evidencia. No formato nuevo, atestaciones ejecutables, restore general, A→B ni R6/SQL/live. |
| R6.3 primera atestación output retry | Aceptada offline2026-09-28 | Partes exactas sin validar args1, configuración HOST postclaim una vez/cache efímero y descriptor exacto/fingerprint; request NUEVA admitida actual∩original y consumo durable en begin_effect. Review167focales+5probes, padre5probes intactos WA48 seed37556 exit0, hashes11/11 y delta cotejados. Informe `/tmp/opencode/output-retry-review-f18c726f/REPORT.md` SHA97f98a0148ff5956d7d59699975c9d5e27a778888428057b7a3444b40e087cd7. Owner matriz58/0, focal297/0 antes2tests finales, compile101/FULL1211pases28excluidos WA48 seed37556,363.8s,exit0 separado. Agotamiento Retry.content; protección fail hasta append. Restore posterior bloqueado salvo completed/tokens data-only; loop vivo normal. Sin formato/token/motor nuevo ni cierre R6/SQL/live. |
| R6.3 output succeeded portable | Aceptado offline2026-09-28 | Frame7 response1 con una atestación succeeded, binding versionado preclaim y descriptor data-only; partes exactas una vez por loop/Writer sin Ecto/reflexión/Model/hooks/siblings ni nueva resolución. Resultado JSON; ambas omisiones conservan errores. Review109focales+5probes, padre5probes intactos exit0; hashes11/11 y delta cotejados. Informe `/tmp/opencode/output-success-review-astra-20260928/REPORT.md` SHA5b27e6e620f7e6409d02dca0dfb0244ab25f161a8f78df831a3bde2a2d7aca1b. Owner focal197/compile100/formato0/FULL1153pases28excluidos WA48 seed37556,290.2s,exit0 separado. FULL histórico interrumpido con3fallos boundary conservado, causa desconocida; verdes posteriores no la prueban. No retry/raw/general/A→B/SQL/live ni R6 completo. Siguiente: output retry confirmado. |
| R6.3 restore input0 | Aceptado offline2026-09-28 | Frame7 autoridad efectiva inmutable, current∩original y claim fresco; VM nueva/carrera CAS/completed data-only. Review171/171 tras P1 floor singular corregido; padre46/0, hashes/delta cotejados. Owner FULL1088/0/28 WA48/compile99/formato. Informe `/tmp/opencode/exagent-restore-floor-recheck-f199cb6f/REPORT.md` SHA0cafcd64. Dos probes antiguos incompatibles con writer7 permanecen rojos históricos; equivalentes7 verificados independientemente. Sólo input/request0 sin operaciones y completed; siguiente response/evidencia confirmada, no A→B/delegado/SQL/live/R6 completo. |
| R6.2–3 paso único integrado | Aceptado offline2026-09-28 | Frame5/6, input/link antes IO, output después, evidencia Model/tool/Retry/output y cleanup pre-write. Review integral más delta mínimo Record.tree_children6:72/0 independientes con siete probes intactos; padre35/0 WA48, hashes cotejados, sin P1/P2 abierto. Owner158focal/compile97/formato/FULL1043/0/28 WA48 seed37556. Informe final `/tmp/opencode/exagent-reserve-acceptance-f1a519/REPORT.md` SHA262a4a2fa5649e73a5187ff54667aadbc4912d385320da875ccdf94285f74841. Reservas5receipts/33800bytes;1019/1020 y8MiB/+1 verificados. Restore sólo inspección; siguiente piso autoridad raíz y ejecución desde bytes. No A→B/delegado/SQL/live/R6 completo. |
| R6.2–3 persistencia raíz vacía | Aceptada offline2026-09-28 tras corregir preflight | Record2/execution2/Frame4 empty+StructuralSnapshot1 sin Model raíz, mismo Writer/CAS/Store; todavía no admite hojas. Owner92focal/compile95/suite979pases28excluidos WA. Review encontró P2: reapertura preflight contra proyección nueva; padre reprodujo dos rojos y corrigió para usar record persistido, focal94 WA/formato0. Revalidación independiente28/0 (5probes+23focales), SHA11/11 cotejados, sin hallazgos pendientes: `/tmp/opencode/exagent-r6-review-f1a844/REPORT.md` y SHA256SUMS-recheck. CAS/ACK data-only/claim/conflicto/receipts/deadline conservados. Resta enlazar hojas, inputs/outputs confirmados y secuenciador; no A→B, nuevaVM/SQL composición ni R6 completo. |
| R6.2–3 raíz Scope estructural | Base aceptada offline2026-09-28; secuencia posterior aceptada arriba | Mismo ExecutionScope con raíz sin Model/operaciones propias y Scope2 sin cambio de formato; loops hoja/admisión/autoridad ancestral/restore JSON sin repricing. Owner8tests nuevos/focal54/compile94/suite971pases28excluidos WA seed37556; MIX_BUILD_PATH absoluto necesario para test existente nuevaVM, sin cambiar producto. Review independiente54focal+probes marker/restore/legacy, formato y7/7 hashes, sin hallazgos: `/tmp/opencode/exagent-r6-scope-review-Zikgjb/REPORT.md`. Freeze deltaea290d7b. Ese hito no incluía Writer/Frame/Record ni Composition.run/resume; persistencia y enlaces step se integraron después. |
| R8.1 smoke final congelado | Aceptado subset live2026-09-27 sobre ef308 | Continuación nativa EL LISTO: GPT4omini OpenRouter tools_stream/native_stream/length_stream3/3 exit0,4admisiones/1efecto inocuo/USD0.10reserva bajo8/USD0.50, concurrencia1/retries0. Terminal length real con15deltas/0efectos; no prueba obediencia textual ni Luna. REPORT `/tmp/opencode/native-smoke-live-f1ace1/REPORT.md` SHAd30ba225d964696e619f2b8e5fbb7288e43314b8976f46e774074c5b4a4e12e2, hashes/resultados/ledger verificados por padre; fuente324 intacta. Uso normalized, factura desconocida. Incidente previo de copia build rompió enlaces relativos: causa/fixture3/3 y cotas negativas verificadas sin cambiar producto. No nueva matriz14casos, no aceptación del delta R6 ni release. |
| R6.1 / primera vertical R6.2–3 | Constructor/binding aceptado offline; secuencia posterior aceptada arriba, R6 general en curso | ADR8.38 y r6-implementation.md. new/binding/validate_binding sin callbacks, definition1 canónico≤64KiB/255 pasos, límites exactos y corrupción rehashed. Review fresca detectó P2 struct truncada→KeyError; padre reprodujo15/16 y corrigió patrón, focal adyacente50/0/0 WA seed37556/formato0. Revalidación independiente16/0 y119 probes sin excepciones, sin hallazgos concretos restantes: `/tmp/opencode/exagent-r6-review-zR92CG/REPORT.md`, fuente000831f5/test4a3a370d. En ese hito no había run/resume y Record2/Frame4 eran propuesta; seam y ejecución secuencial fueron aceptados después. Restan recuperación activa multileaf/C7 composiciones, delegado, router/paralelo y SQL A8/live. No cierre R6. |
| R8.1 regresión live habitual | Harness portable7files75af aceptado tras review offline | test/support/openrouter_qualification checkout-only: --live/ledger nuevo/fingerprint/casos/modelo/caps80/USD5/concurrencia1/retries0, entorno privado.6executables exactos entrega56bf; proof75af/verification23db owner y review172e verifican optin64/fixtures/reuse/budget negativo sin LLMonline. Comandos mantenidos en verification.md; autorización permanente para cambios relevantes, no tests pagados por defecto ni otro framework. |
| R1 prioridad terminal incompleto | Aceptada offlinedda4 tras review fresca; distribución final identificada aparte | ADR8.37: finish público fallido manda, partial válido existente o nil, sin codec/usage inventada; success sigue guards. Rojo→focal74, compile93/suite947/0/28 WA owner; independiente55focal/2probes16TCP/native2 y review172e sinP1/P2. No cualifica length_streamLuna13/14 ni convierte tool_calls enlength. Recepción/artefacto consolidado en archivo none/binding; sin nueva suite por prosa. |
| R1 / C7 modo none y binding estático | Aceptado offlineb609 tras review fresca; G2 separado acotado | ADR8.36: none/caps veraces/opción pública/max_tokens único, continuation3/Frame3/Abort2/binding4KiB. Review SHA dfc4e158:compile93/focal93/probes4, sin P1/P2. Owner suite946/0/28 WA, focal45, snippets9/docs verdes; fuente final44b9 y TAR e50b con consumidores6/177/32/15. Tree2 auténtico/root1/J/data-only/abort conservados. G2Luna comunicado13/14, length_stream no cualificado; delta terminal posterior tiene review propia. Registro docs/archive/2026-09-27-reasoning-none-binding.md; no aceptación universal ni reuse de G5/admisión2a74. |
| R1.2 / R1.4 admisión final | Aceptada offline por coordinador tras review fresca2a74 | Diseño8.35: diagnósticos conservados/error no nil rechazado, sobre/schema/autoridad intactos. Independiente focal60+probes6, sin P1/P2 concreto; REVIEW SHA7ec91a94. Owner focal74/compile92/suite933/0/28/snippets9/docs y consumidores6/164/30/15. Coord verificó fuente final08e55/manifest a8ebba/TAR3c180; runtime/tests iguales a2a74. Esta recepción documental posterior no cambia esos artefactos ni relabela G5ba17. Registro docs/archive/2026-09-27-final-argument-admission.md. |
| R8.2 / G3 recepción final | Perfil real PostgreSQL17.11 READ COMMITTED aceptado, incluido fix4b89 | Coordinador msg_12a78ba009d5:21casos distintos más VM/DBrestart/red tras COMMIT/backup29 envelopes; probes RLS/trigger exactos rojo2→verde0, cleanup realizado. No todos los despliegues SQL ni aceptación C7 independiente. Evidencias/hashes en docs/archive/2026-09-27-external-gates-receipt.md. |
| R7.3 / G4 comparación | APIs aceptadas; Langfuse referencia provisional, G4 completo abierto | Ambos74spans/15trazas, parentesco/accounting/privacy recuperados. Langfuse conserva IDs/tipos; Opik requiere correlación. Relay de captura nativa no certifica exporter→cloud directo; UI, lifecycle/exporter y gaps pausa/approval/attempt pendientes R7, sin runtime nuevo. Registro de recepción27sept. |
| R8.3 / R8.5 / G5 local | Resolución limpia y consumidores locales aceptados; G5 completo pendiente | TARba17, nuevaHex/ReqLLM1.24,6/44/9/12 contratos, procedencia117 módulos/perfil y bootstrap mínimo limpio. CI remota exacta/finalR6R7/matriz restante pendientes; propuesta4 archivos NO integrada. No atribuir este gate al delta4b89 posterior. Registro de recepción27sept. |
| R8.1 / G2 mínimo | GPT4 mínimo aceptado; extensión acotada concluida, length_streamLuna abierto | REPORTfinal5b542ee1: gpt4omini14/14 source2a74 y2regresionesstream b609; Luna none13/14 b609, no length_stream; GLM5.3Flash/DeepSeek4.1Flash sólo1texto buffered cadauno source2a74, tools bloqueadas.40admisiones/7efectos/USD2.37reserva(no factura),0retry/concurrencia1. Endpoint OpenRouter/API/perfiles exactos en reporte; no G2 universal ni falsa cualificación3modelos completos. Delta terminal autónomo no cambia el rojoLuna. Recepción/hashes en archivo none/binding. |
| R5 / review C7 final | Framework aceptado offline, con SQL4b89 separado | Dictamen final /tmp/opencode/exagent-r5-review/final8b3b/REVIEW.md: sin nuevo P1/P2 concreto; compile92/probes5/recovery12/binding2/integración11 e identidad310/115. Coordinador acepta source8b3b + SQL4b89, no TARba17 que aún conserva SQL viejo; no G2/release ni aceptación automática de nueva admisión. Las filas R5 inferiores conservan la evidencia de sus checkpoints anteriores a esta aceptación integrada. |
| R8.1 / G2 ejemplos | Corrección documental y defaults de tests acotada | Diagnóstico G2 task_62f2220c6ec1/ctx_87a1152ecb1a: ReqLLM1.24 exige temperature float. Tres ejemplos stock, snippet y dos defaults de real_providers_test usan0.0, sin alterar aserciones/coerción runtime ni cierre G2; ownerfix no ejecuta tests pagados. |
| R5.1 | Raíz parcial aceptada offline | ADR8.34, frame/ledger/writer root y J sobre sourcef8b542f6. Review task_0ee986f3992e:compile85/probes10/focal35/adyacentes27 e identidad291 exit0; cuatro P2 cerrados. Máquina/árbol completo y C7 integral pendientes. |
| R5.2 | Raíz parcial aceptada offline2026-09-26 | Coordinador msg_90820eaf8d7d acepta sourcef8b542f6/manifestb62f73c5, no prosa posterior. Review causal cierra4P2 de6a65; owner compile85/suite850/0/28 seed37556 y probes exactos10/10 seed92626. Matriz docs/archive/2026-09-26-r5-root-progress.md; no C7 completo ni distribución. |
| R5.3 | Raíz parcial aceptada offline | API host get/decide approve/deny/cancel/expire, binding/revisión/actor/receipts y competencia en raíz; integración final del árbol/Server/Session pendiente. |
| R5.4 | Implementado/verificado offline por owner; pendiente review integrada | Reader root1 real; Frame2/Scope2 y grafo/journal/approval bidireccional, actual/original por ancestro, dos resumers. Dos VMs nuevas rehidratan árbol depth2 desde disco test-only,11 entradas de journal una vez y coste10→43 sin repricing; no SQL/G3. P2 inverso reproducido/corregido por owner, sin revalidación independiente. |
| R5.5 | Implementado/verificado offline por owner; pendiente review integrada | Árbol9, compuestos4 y fronteras/fallos7 verdes; writer/fila únicos, sin callable padre ni falso efecto delegado. J72268/J−1 preIO, JSON+cleanup8MiB y receipts1024 exactos. Último compile92/suite921/0/28 seed37556 exit0; mismos bytes producción de a371. Consumidores candidato115:6/106/30/12, grafo fijo copiado, no G5 limpio. Matriz docs/archive/2026-09-27-c7-owner-matrix.md; fuente/TAR finales fijados en manifest. |
| R5.6 | Implementado/verificado offline por owner; pendiente review integrada | Model3 incluye dos hijos inciertos reconciliados separadamente; retry/HTTP9, actor/stale/1vs1.0/CAS/cadena/muerte/activo/expiry, riesgo histórico y retención. Faults before/after nodefinish/raw/final/Model intent y reserva exacta adicional retry; key real stock buffered/stream sin dedupe prometida. Suite921 exit0 y perfiles de paquete en matriz; review bloqueada, no aceptación C7. |
| R5.7 | Base Server/Session aceptada; composición árbol verificada owner, pendiente review | Base f394/6499 aceptada por msg_95f14728b813; esa revisión no cubre R55. Nuevos públicos prueban árbol+stream/cola/eventos, restart Server+Session, turn completion una vez, deny/cancel/reset y native por nodo; consumidor runtime106 exit0. Fixture OTLP task337bf intacta. Suite921/0/28; aceptación C7 integrada bloqueada por reviewer, sin SQL/live/G5 limpio. |
| R4.1 | Aceptada offline tras review integrada | ADR8.33, record1 y snapshot público1–4; sourcecdd2/TARac54/manifest1488. Independiente compile80/focal33/snippets9/deltas279/TAR103 exit0, sin P1/P2 concreto. Owner803/0/28 y consumer186 siguen evidencia owner. Registro: docs/archive/2026-09-26-r4-integration.md. |
| R4.2 | Aceptada offline tras review integrada | Capabilities fail-closed, CAS/receipts actor/payload, carreras ETS y guard legacy preefecto; runtime/tests revisados preservados. |
| R4.3 | Aceptada offline y perfil G3 real acotado | ETS efímero, Postgres fila única y DDL app-owned. Recepción G3 arriba acepta PG17.11 READ COMMITTED, CAS/rollback/locking y fix4b89; no todos los despliegues SQL ni C7 independiente. |
| R4.4 | Aceptada offline tras review integrada | Dirty seam exacto, ACK perdido y retry sólo persistencia; legacy1–3/4 y omisión R3.4 intactos. Runtime C7 sigue R5. |
| R4.5 | Aceptada offline tras review integrada | Claims/fences/receipts/lease y crash intent/outcome conservan incertidumbre; no replay ni permiso nuevo por receipt antiguo. |
| R4.6 | Aceptada offline y perfil G3 real acotado | Reserva encoded/scan/prune; G3 verifica backup/restore29 envelopes, retención y conflicto ante DELETE suprimido, con cleanup de infraestructura terminado. Límites del perfil en recepción27sept. |
| R2.1 | Diseño aceptado offline tras review | Diseño8.28: mapa público/experimental/interno, resultado/errores/contexto/eventos y ADR paused común con IDs/progreso/outcomes. Pausa sólo diseñada para R4/R5; no runtime C7. |
| R2.2 | Base aceptada offline tras review | Envelope1/continuation2/accounting1/Server snapshot3, rechazo historia tool sin marker y binding/proyección/codec preservados; ningún hueco nuevo de formato demostrado ni bump preventivo para native. |
| R2.3 | Aceptada offline tras revalidación independiente2026-09-26 | Diseño8.29 y preparación native tras hook preadmisión; Ecto final, guards y sobre intactos. Review task_f955b8e8ea60/ctx_cd5ed6947704 cierra P2 sin P1/P2 pendientes: compile71/focal32 seed92624, fixture anterior1/3→actual3/3; coordinador17/17 seed37556 e identidad93/253 exit0. Owner suite707/0/28 y consumidor80/0/0 fijo; TARf6b549f5/source7eb34210. Gate_60c09b5f327e aceptado; registro docs/archive/2026-09-26-r2-output.md. No G2/G5 limpio/C7. |
| R3.1 | Base aceptada offline gate_115377365ca5 | Diseño8.30 namespace/identidad/eventos/topics; review task_529ac64dfe7e sin P1/P2 sobre TAR29e35296/source643ade77, compile73/focal38/probes5/snippets9 independientes. Owner718/0/28 y consumidor91/0/0 fijo; nuevo delta R3.4 requiere otra review. |
| R3.2 | Base aceptada offline gate_115377365ca5 | Secuencias/ownership y smoke16 namespaces/48 terminales/16 queue_full aceptados. Cola volátil, steer siguiente run, caller timeout no cancela. R3.4 añade ACK y migra race con barrera de recepción antes de terminal, no fake ACK ni no-op después del terminal. |
| R3.3 | Aceptada offline, incluido delta contable R3.4 | Scope/admisión/ancestros/quality/restore; Usage y costes acotados, ledger de errores y replay contable corregidos sin repricing. Review task_d3420f865920 cierra cuatro P2 sobre source05a02459/TAR8775e665. |
| R3.4 | Aceptada offline tras revalidación independiente2026-09-26 | ADR8.32, snapshot4/omitted-v1 y ACK; cuatro P2 cerrados en source05a02459/TAR8775e665: compile74/probes6/focal85 independientes, owner suite755/0/28 y consumidor128/0/0 fijo. Gate_1a7cfef26f1f autoriza integración R4; evidencia y límites en docs/archive/2026-09-26-r3-retention.md. Sin hard RAM predecode ni G2/G5 limpio/C7. |
| R3.5 | Aceptada offline gate_115377365ca5 | Store.scoped/codec key-payload namespace/kind/ID, nil legacy, single-writer/refs/restore y aislamiento A/B aceptados en review fresca. Store/RuntimeIdentity/Session sin delta en R3.4; no CAS/C7. |
| R3.6 | Aceptada offline gate_115377365ca5 | Receta pública Local/Phoenix adapter/eventos/abort/jobs-checkpoint sin dependencia obligatoria; snippets9/9 owner e independientes. No aceptación de backend Phoenix/jobs externo ni replay OTP/PubSub durable. |
| R2.4 | Aceptada offline tras review | Rojo público antes del fix: identidad before-tool universal, callable preIO, contexto correcto y fallo previo not_executed; batch/outcomes/autoridad/IO incierto conservados. Diseño8.27. |
| R2.5 | Aceptada offline tras review | Selección ejecutable por request, preparación previa, DI aislada y secuencia exacta hooks; before/post errores conservan límites confirmados. after_model mantiene transformación confiable preadmisión. |
| R2.6 | Aceptada offline tras review | Defaults tools/JSON false, texto básico sin profile operativo; custom/Test declaran sólo tools implementadas. Consumidor público Model/tool positivo/negativo/error posterior pasa63/0/0 desde TAR6e0585bc con grafo fijo copiado, no nueva resolución/G5 completo. R2.3 native sigue unidad separada. |
| R0.1 | Verificada | HEAD7f25b33 + WIP documental/manifiesto (14 modificados, 8 untracked) preservado sin reset/stash/clean; nominal1.3.0; lock37 líneas sha256 `f99728b5…`. Registro en `docs/archive/2026-09-21-r0-baseline.md`. |
| R0.2 | Verificada | Prefijo de environment.md con tooling aislado existente; Hex2.5.1/Elixir1.20.0/OTP29.0.5 efectivos, exit0; sin reparar el Hex compartido ni config global; cero builds concurrentes sobre este repo. |
| R0.3 | Verificada | Compile forzado75 fuentes exit0; suite seed37556 **655/0/28** (excluidos:22proveedores+6Postgres); formato y `git diff --check` exit0. Baseline nuevo sobre `7f25b33`, no la cifra histórica de la auditoría. |
| R0.4 | Verificada (preparación) | Registro fechado sólo en checkout + lista única preparada y entregada al coordinador (providers R8.1, Postgres sintético R8.2, Opik R7.3, CI/publicación). Ningún acceso externo autorizado; destinos concretos pendientes. |
| R1.1 | Verificada (frontera offline) | ReqLLM1.24.0 y mínimo1.18 por `llm_db`; review fresca recibida. Evidencia inicial pre-Mint en `docs/archive/2026-09-21-r1-1-reqllm.md`; follow-up Mint1.10.1 autorizado y verificado con bytes nuevos en `docs/archive/2026-09-21-r1-buffered.md`. Sin Jido/SQL/SDK; no cierre R1. |
| R1.2 | Buffered parcial aceptada offline; review fresca recibida | Review Astra `task_16e800274a86` acepta subset buffered sin P1/P2 concretos pendientes; P2 deadline revalidado independientemente. TAR51f36adc, compile79/suite715/0/28 son evidencia de esa unidad, no del stream nuevo. Registro: `docs/archive/2026-09-22-r1-envelope.md`; dictamen resumido en el registro R1.4. G2/R1 completo siguen pendientes. |
| R1.3 | Perfil mínimo aceptado offline; dictamen final recibido | Chat explícito codec2/envelope1: gates de lógica/IDs/orden/JSON/Server/compaction e historia no versionada reutilizados; nuevo oráculo continuation ligada a provider/model/endpoint preIO. Suite755/0/28 y review fresca ctx_c6cf985f5f8c:4/4 nuevos, identidad runtime/TAR y sin P1/P2 runtime; corrección de esta tabla cerrada sobre TARd2bfe978. Google/Anthropic/Responses tools siguen cerrados; no G2 ni aceptación por catálogo. |
| R1.4 | STREAM PARCIAL offline aceptada2026-09-25 | Review fresca `task_dbfcf7b3c823`,123 casos propios/0 fallos y53 focales coordinador. Perfil Chat explícito process_stream público, frontera buffered común, guardian/registro/ACK/close y límites64KiB/1MiB/4096; compile80/suite735/0/28. Registro histórico conserva los dos P2 y sus correcciones/revalidación en `docs/archive/2026-09-22-r1-stream-adapter.md`. No G2 ni R1 completa. |
| R1.5 | Aceptada offline; dictamen final fresco recibido | Diseño8.25: Usage.accounting v1, ModelProfile.accounting_quality, strict/estimated con bound ancestral, Server snapshot3, cobertura dimensional/coste independiente y metadata no aditiva. Review `task_5b79c7a35e0c`:173/173 exit0 sin P1/P2 concretos pendientes sobre TAR3c7867ad; coordinador40 exit0. Compile80/suite751/0/28 seed37556 y consumidor48/0/0 fijo copiado, no G5 nuevo. Registro `docs/archive/2026-09-25-r1-qualified-accounting.md`; recepción documentada en el registro de composición. |
| R1.6 | Perfil mínimo aceptado offline; dictamen final recibido | Settings/precedencia/auth/gateway, retries0/no redirects/repairfalse y strict no cualificado preIO conservados y reejecutados; nuevo oráculo tool_choice auto/required según params/Ecto y native preIO. Suite755/0/28 y review4/4 nuevos sin P1/P2 runtime; cierre documental TARd2bfe978 confirmado. No knob público adicional ni aceptación native R2.3. Evidencia actual `docs/archive/2026-09-25-r1-qualified-composition.md`; suite691/opciones12 permanecen históricas. |
| R1.7 | Composición mínima aceptada offline; dictamen final recibido | Dos nuevos escenarios ReqLLM stock TCP: tools/delegación/Ecto retry/hooks/Server stream/Session/ETS/savefailure/retry/restore/OTel; efecto1, denegación ancestral0, contadores host exactos, normalized/estimated y sin replay al guardar/restaurar. Suite755/0/28, consumidor50/0/0 fijo copiado (no G5), review4/4 e identidad runtime/TARd2bfe978 confirmadas; matriz y límites en `docs/archive/2026-09-25-r1-qualified-composition.md`. No C7/G2. |
| R1.8 | Perfil mínimo aceptado offline; dictamen fresco recibido2026-09-26 | Diseño8.26 y propuesta aceptada antes de retirada:9 módulos duplicados retirados, resolve/1–2 stock/spec/custom/Test y auth por instancia, guards intactos.88 tests legacy retirados con oráculos reubicados,13 nuevos: compile71/focal48+36/suite680/0/28 seed37556 exit0; snippets8/8 y probe público14 invariantes. Review `task_a7e85474a9ef` acepta TAR6a2eb6aa, compile71 y focal6/6 propios/owner, sin P1/P2 concretos pendientes. P2 de prosa cerrado: siblings wire borrados stock no son detectables; calls inválidas visibles invalidan batch0efectos. Cierre documental26Sep preserva AST funcional y tests/config/mix/lock; nuevo TAR y gates se identifican en `docs/archive/2026-09-25-r1-retirement.md`, sin atribuir review de esos nuevos bytes. No G2/R1 completo/C7. |

**Registro histórico previo al dictamen R1.4 del2026-09-25:** sin delta runtime, compile80, suite735/0/28,
focal53/53 (incluidos ambos probes del reviewer anterior) y formato exit0 con
tooling aislado existente y seed37556. Evidencia nueva `r14-recovery-*`, separada
de la ejecución previa; review independiente de recuperación `task_dbfcf7b3c823`
pendiente. Artefacto/grafo fijo y límites constan en el registro R1.4.

**Aceptación fresca R1.4 recibida2026-09-25:** review `task_dbfcf7b3c823`,
123 casos propios/0 fallos, y53 focales del coordinador exit0: STREAM PARCIAL
offline `chat_tools_v1`, sin P1/P2 concretos pendientes en ese alcance. TAR
`12e46f416f40fa4f73f3fe8dd8eca513d9061087b131ed2c29a68c8fccd62128`,
smoke46/0/0 con grafo fijo copiado (no G5 nuevo); compile80/suite735/0/28
son la evidencia R1.4, no una verificación R1.5. El estado anterior se conserva
como registro de la recuperación previa al dictamen.

**R2 base reanudada y verificada por owner (2026-09-26):** misma task/dispatch,
pausa de transferencia levantada por msg_5df327664b3d. Compile forzado71, focal98,
suite687/0/28 seed37556, formato/snippets8/8/ExDoc y consumidor63/0/0 exit0;
evidencia, rojos e identidad artefacto final frente al TAR runtime probado en
`docs/archive/2026-09-26-r2-base.md`. Review fresca recibida task_28d681ef6334:
compile71/focal54/probes6 seed82619 exit0, sin P1/P2; coordinador focal38 exit0.
Acepta TAR482e26a3/source1eefe618, no bytes posteriores. Siguiente: R2.3 separada. No cerrar
R2 completa sin ella. R1 mínimo offline aceptado se reutiliza; G2 sigue en R8.
R3/R4/R5/C7 no iniciados por este dispatch. Mantener guards, sin reauditar R0/Jido
ni atribuir cifras históricas a nueva candidata.

```text
ID y estado: pendiente | en curso | bloqueada | verificada
Objetivo y contratos afectados:
Revisión/estado WIP, versión y lock:
Decisión y cambios (rutas):
Pruebas: comando, runtime, seed, exit, pass/fail/excluded:
Escenario/oráculo y controles negativos relevantes:
Revisión fresca cuando corresponda:
Artefactos/hashes y limitaciones:
Bloqueo exacto y forma de desbloquear, si existe:
Siguiente unidad ejecutable:
```

No persistir sólo paths temporales que puedan desaparecer: conservar resumen,
comandos, hashes y decisiones en repositorio; logs grandes al archivo fechado.
Al cambiar de contexto actualizar [handoff](handoff.md), detener recursos propios
y dejar identificado lo que falta, sin prometer ejecución fuera de una sesión activa.

## 6. Correspondencia histórica y estado de planificación

| Plan anterior | Ubicación nueva |
|---|---|
| H1 alcance/contratos | Alcance v2, R0 y R2; evidencia H1 conservada en archivo |
| H3.0 ReqLLM | R1 |
| H2 observabilidad | R7.1–R7.3 + aceptación R8 |
| H3 providers/Store | R4 y R8.1–R8.2 |
| H4 consumidores | R8.3, con ejemplos desde R2/R3/R6/R7 |
| H5 candidata/CI | R8.5–R8.6 y R9.1 |
| H6 revisión/publicación | R9.2–R9.4 |
| C7 antes diferido | Incluido por decisión expresa; R4/R5 |

**Registro2026-09-21:** roadmap detallado preparado por petición del usuario;
C7 incluido tras aclaración. Todas las fases runtime están pendientes. Baseline
histórico en [estado](../status.md); ninguna cifra antigua acepta ReqLLM, C7 o v2.

**Registro2026-09-21 (activación):** mandato activado por dispatch Orca; R0.1–R0.4
verificadas sobre HEAD `7f25b33` con WIP intacto (evidencia en
`docs/archive/2026-09-21-r0-baseline.md`). Baseline reproducido655/0/28
seed37556 en Elixir1.20/OTP29 con prefijo aislado; sin cambios de fuentes, deps ni
lock. Siguiente: R1.1.

**Registro R1.1:** ocho dependencias añadidas al lock; ninguna previa actualizada.
API host buffered probada con transporte sintético. Gap de presencia de uso
demostrado por API pública (ausente/parcial/cero indistinguibles); resolver en R1.5
sin parsers privados. Retry429 exige `max_retries:0`, no basta `retry:false` en
opciones Req. Mint raíz1.10.0 tiene advisory CVE-2026-82672 corregido en1.10.1;
propuesta mínima documentada para seguimiento, no actualización a ciegas.
Revisión fresca de R1, streaming y aceptación externa permanecen abiertas.

**Follow-up posterior R1.1/R1.2:** autorización Mint recuperada; floor y lock a
Mint1.10.1, sólo esa dependencia actualizada. Focal TCP13 y consumidor nuevo9 pasan;
suite final adapter672/0/28 sin instrumentación. Dos rojos anteriores de readiness
100ms se conservan: diagnóstico75/84ms no cerró causa y no se amplió timeout.
Review R1.1 `task_aa5983de6b0e` recibida; no equivale a review final R1.4–R1.6.

### Verificación de la preparación del plan

Unidad documental del 2026-09-21, sin cambios en `lib/`, dependencias o versión:

- 57 subunidades únicas, 10 escenarios y 6 gates; referencias de IDs y C7 coherentes.
- 200 enlaces locales en 34 Markdown correctos, incluidos los archivos históricos movidos.
- Formato de `mix.exs`, ExDoc con warnings-as-errors y `git diff --check` correctos.
- Snippets existentes 7/7, seed 0, Elixir 1.20/OTP29 sobre BEAM existentes; comprobación
  documental, no una nueva aceptación runtime ni de las funciones planificadas.
- Preview local nominal 1.3.0 con 97 archivos: bytes coinciden con el checkout,
  documentos vigentes incluidos y prompts/archivo excluidos. No publicación.

Artefactos temporales: `/tmp/opencode/exagent-v2-plan-docs` y
`/tmp/opencode/exagent-v2-plan-preview.tar`. Comprobadores de esta unidad:
`/tmp/opencode/exagent-release-doc-check.py` y
`/tmp/opencode/exagent-v2-plan-check.py`. No son requisitos del consumidor.

### Replanteo documental verificado — 2026-09-22

Diseño8.22 y normas activas actualizados; síntesis durable de investigación con
permalinks/versiones en framework-direction§9, comparación previa delimitada como
histórica y relevo checkout-only `docs/prompts/continue-v2-reqllm.md` preparado.
La implementación autorizada se retoma en otra Task tras revisión fresca.
No se cambió runtime/tests/config/deps/lock/CI/guards ni nominal; C7 permanece.

- `python /tmp/opencode/exagent-v2-plan-check.py`: exit0, **57 IDs únicos**, A1–A10
  y G1–G6 conservados; referencias y alcance preparados coherentes.
- `python /tmp/opencode/exagent-release-doc-check.py`: exit0, **222 enlaces locales
  en40 Markdown**. Primer intento exit1 por ancla nueva Jido/ReqLLM; se corrigió
  el encabezado a Jido-ReqLLM, sin cambiar checker ni ocultar fallo.
- Con prefijo aislado de environment, `EXAGENT_OFFLINE=1 MIX_ENV=dev mix docs
  --no-compile --warnings-as-errors --output /tmp/opencode/exagent-stock-replan-docs`:
  exit0; generó HTML/Markdown/EPUB y anunció compilación incremental de1 archivo
  pese a `--no-compile`. Sin edición de fuentes runtime ni instalación de tooling.
- `git diff --check`: exit0. Prompts quedan fuera de extras ExDoc y se citan como
  paths checkout-only; no se cambió mix para indexarlos. No suite runtime repetida,
  nuevo TAR ni aceptación de proveedor/DB/backend por esta unidad documental.

Los criterios afectados quedan **reabiertos**, no verificados por prosa. El
baseline691/0/28 y SHAs/TAR previos siguen históricos; la próxima evidencia runtime
debe empezar por el gate del sobre R1.2, no R0/Jido de nuevo. Detalle de entrega
temporal en `/tmp/opencode/exagent-jido-reqllm-replan/DOCS-DELIVERY.md`; las decisiones,
fuentes y siguiente acción necesarias para retomar están en estos documentos.
