# C7: matriz owner de implementación y verificación — 2026-09-27

**No es aceptación independiente ni publicación.** Task `task_b368f714cfd3`,
dispatch `ctx_4950569ad27e`, Astra LOW confirmado por coordinador. R6–R9 no se
iniciaron. Nominal1.3.0, HEAD7f25b33, lockc20a0cb9 y ReqLLM stock1.24 intactos.

## Matriz de entrega

| Frontera | IMPLEMENTADO | VERIFICADO por owner | PENDIENTE REVIEW / externo |
|---|---|---|---|
| Árbol durable | Frame2/Scope2, descriptor host, único loop/writer/fila CAS | Hijo pending+hermano confirmado, dos hijos/profundidad2, call IDs iguales, contadores y precio10→43 sin repricing | Review integrada bloqueada por proveedor; no aceptación C7 |
| Integridad/autoridad | Grafo y journal/approval/ledger bidireccionales; refs, schema y restricciones originales+actuales | Probe independiente exacto reproducido3/4 rojo→4/4 owner; regresión permanente, corrupción, presupuestos raíz/intermedios, deny ancestral | Dictamen independiente sobre fix y recuperación nuevos |
| Persistencia entre VMs | Datos portables, definiciones/deps/codecs reconstruidos por host | Dos VMs nuevas, fixture disco single-writer:3 hijos/depth2, journal11 entradas una vez; nil expiry y no lease convertido en deadline hijo | No Postgres real, aislamiento distribuido ni G3 |
| Lifecycle integrado | Root paused sólo tras ACK/quiescencia; Server/Session conservan semánticas cerradas | Stream y request/run correlacionados, cola retenida, restart Server+Session, turno una vez, deny/cancel/reset y native por nodo con retry Ecto contado | Revisión integrada; no nueva garantía entre filas |
| Model incierto | Reconcile de respuesta efectiva/estado portable/perfil/output sin Model/hook replay | Owner death, estado no representable pos-hook, negativos de actor/refs/codec/profile; dos Models hijos inciertos reconciliados separadamente | Servicios/modelos externos sólo según matriz G2 |
| Retry explícito | Original literalmente incierto, enlace al receipt, actor/revisión/key, nuevo claim/intent ACK | Tool/Model, key entregada, input proyectado conservado, CAS concurrente, stale/key/hash/args1≠1.0, corrupción, segundo crash, budget/expiry | No deduplicación externa inferida de la key |
| Contabilidad/retención histórica | Reserva nueva por retry, identidad de contribución, unknown preservado, riesgo visible y ACK de eliminación futura | Intent counts, coste parcial sin reprice, start/prune bloqueados antes de ACK; original no reescrito como éxito | No exactly-once ni garantía tras borrado explícito de evidencia |
| Cotas | Token J completo, JSON+cleanup8MiB, cardinalidades/receipts/slots | J72268 acepta/J72267 bloquea antes de Model hijo; JSON8351498+37110 y retry8368280+20328; receipts1019+5=1024 y horizonte adicional de retry | Mediciones postmaterialización, no hard RAM upstream |
| Ventanas de fallo | Retry de checkpoint sólo datos, raw/final y node finish preservados | Before/after ACK en node_checkpoint/delegation_outcome raw/final/Model begin; receipt antiguo no despacha Model, requiere decisión explícita | Store fixture, no certificación de SQL/transacciones externas |
| Distribución | Paquete115 archivos, grafos mínimo/runtime/extensible/SQL opt-in separados | Candidato03c25214:6/106/30/12 tests exit0;117 módulos proceden de cada TAR/build privado; fixed copied graph | Sin resolución limpia ni CI remota/G5 limpio; sin SQL real |

## Gates e identidad

Registro detallado, rojos y fuente previa: `docs/archive/2026-09-26-r5-tree-progress.md`.
Checkpoint a371/manifestf4e4 conserva producción verificada con suite908; desde él
sólo se añadieron pruebas/fixtures y documentación. Último gate integrado:
`r55-final-compileforce-01` **92 fuentes exit0** y `r55-final-suite-01`
**921 pasados/0 fallos/28 excluidos**, seed37556,180.2s ExUnit,181.004s runner.

Gates focales posteriores a a371:

- `r56-tree-new-vm-01`:9/9. El prefijo es iteración de evidencia, no fase R6.
- `r55-gates-tree-runtime-01`:2/3 y exit3: fixture Ecto derivaba Jason.Encoder
  después de consolidación. Movida a test/support, sin cambiar producción,
  aserciones ni timeouts; `-02`:3/3 y `-03`:4/4 exit0.
- `r55-gates-tree-boundaries-01`:5/5; `r55-gates-node-recovery-capacity-01`:8/8;
  `r55-gates-retry-capacity-01`:7/7, todos exit0.
- J mínimo es calibración black-box por API pública sobre fixture fija, con tamaños
  de todos los tokens realmente enviados a Store (máximo13587B); no suma de payloads.
  Las fronteras JSON/receipts son oráculos de reducer/Store sobre record derivado de
  ejecución pública, distinguidos de admisión/efectos observados.

## Consumidores del candidato

TAR candidato: `/tmp/opencode/exagent-r55-candidate.tar`, SHA256
`03c25214a87c30edbbd82d01cbdac2090e445da6a8ed17e0baa3f15f5c6349d5`.
Directorios privados `/tmp/opencode/exagent-r4-integration-consumer-r55-`
`{minimum,runtime,extensible,sql}`. Cada manifest enumera tests seleccionados,
fixtures y hashes. Toolchain efectivo Elixir1.20/OTP29, +S8:8, allowlist/offline,
homes/archives existentes y caches Rebar por consumidor. No deps.get ni resolución.

| Perfil | Gate | Resultado |
|---|---|---|
| Mínimo | r55-consumer-minimum-tests-01 |6/6 exit0: one-shot/tools/Ecto/stream/ETS/ReqLLM custom/buffered |
| Runtime | r55-consumer-runtime-tests-02 |106/106 exit0: C7/árbol/VM/native/Server/Session/cotas/fallos |
| Extensible | r55-consumer-extensible-tests-01 |30/30 exit0: Model/Tool/Store/PubSub app y recuperación/custom contracts |
| SQL opt-in | r55-consumer-sql-tests-01 |12/12 exit0: adapter real frente a protocolo Repo scripted |

Primer runtime consumer `-01` falló al compilar: el materializador omitió la
fixture `ExAgent.Test.ContinuationFixtures`. Se copió su fuente exacta a lib del
consumidor y se corrigió el materializador; no se alteró el paquete o los tests.
Los cuatro deps.compile fresh salieron0; warnings toml/websockex de Elixir1.20 se
conservan, sin warnings propios al compilar los78 archivos de biblioteca.

Los cuatro `r55-consumer-*-graph-01` verifican117 módulos sólo desde vendor/TAR y
ausencia de dependencias opcionales no solicitadas. SQL opt-in agrega únicamente
ecto_sql3.14.0/postgrex0.22.4/db_connection2.10.2 al grafo; `sql-optin-01` compila
Repo app-owned y valida DDL/capability sin arrancar Repo, conectar ni ejecutar DDL.

## Frontera final

TAR final `/tmp/opencode/exagent-r55-final.tar`, SHA256
`ba17a600c195691062c2529e7bf7f86146b9b198a332735b6b4840f92d0ba3b6`.
`/tmp/opencode/exagent-r55-final-consumer-bytes.json` verifica115/115 archivos
idénticos a ROOT y en cada uno de los cuatro consumidores. Delta frente al candidato:
únicamente diseño/changelog/handoff/r5-implementation/roadmap/migración, seis Markdown;
ningún byte runtime/manifiesto/deps cambió. Los115 miembros excluyen archivo/prompts/tests.

Los tests6/106/30/12 anteriores cualifican esos mismos bytes runtime. Después de
refrescar cada consumidor desde el TAR final: mínimo6 y fronteras7 vuelven a pasar,
igual que los cuatro checks de grafo/procedencia117 módulos, todos exit0. La fixture
de fronteras recibió sólo ajuste de formato de IO.inspect; hashes antes/después en
el manifest del consumidor. No se presenta el refresh documental como repetición
de todas las suites ni como nueva resolución de dependencias.

Gates documentales finales: ExDoc y snippets9/9 exit0; formato tuvo un primer exit1
por esa envoltura de IO.inspect y `r55-final-format-02` exit0 tras corregirla, sin
cambio de aserciones/runtime. Diffcheck exit0, links147/21 sin ausentes, plan57/A10/G6
y membresía real del TAR correctos. El manifest final enlaza fuente, TAR, logs,
fuentes de scripts/fixtures, rojos y reutilización por identidad.

Queda revisión integrada de estos contratos para aceptación C7 y los gates externos
ya declarados. No worker_done/cesión por leer este documento; coordinación por CLI.
