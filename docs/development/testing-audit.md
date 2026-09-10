# Auditoría de valor y cobertura del testing

Auditoría realizada el **2026-09-10** sobre `69c2747`, árbol inicialmente limpio,
nominal **1.3.0**. Mandato: `docs/prompts/testing-audit.md`. El objetivo es confianza
discriminante y mantenimiento razonable; el número de tests no es una meta.

**Cerrada por acuerdo del usuario.** Se retoma el desarrollo de ExAgent, con tests
de sus cambios y contratos. Los warnings externos no mantienen abierta esta
auditoría ni pasan a ser la siguiente unidad de trabajo por sí solos. El criterio
de responsabilidades y frecuencia está en [verificación](verification.md).
La nota `docs/prompts/testing-review-final.md` queda preparada para una segunda
revisión cuando esté terminado el alcance funcional del paquete; leerla no la activa.

## Alcance revisado

Se completaron dos auditorías de sólo lectura, por Orca con `openai/gpt-6-astra`,
antes de editar pruebas. Se leyeron completos **70 archivos raíz**, incluidos sus
helpers y casos excluidos; **19 archivos de soporte, siete templates, 12 ejemplos**,
`test_helper`, configuración, Mix y `.github/workflows/ci.yml`. El inventario de
base contiene **648 casos ExUnit: 620 correctos y 28 excluidos**. Las dos auditorías
atribuyen 403 y 247 casos con dos cruces deliberados (Finch y permisos core/Server):
se descuentan esos cruces, no se cuentan dos veces.

Las mejoras y siete archivos de tests nuevos pasaron revisión independiente fresca:
la superficie final contiene **77 archivos raíz**, 24 soportes, ocho templates y
13 ejemplos. Los inventarios de base se conservan como tales; no se reescriben sus
denominadores históricos con los del resultado final.

El inventario detallado `docs/archive/2026-09-testing-inventory.md` registra
archivos, familias, caminos, oráculos y dictámenes. El registro
`docs/archive/2026-09-testing-audit.md` conserva autoridad, baseline y evidencia
fechada. Ambos están en el checkout, fuera del paquete de uso habitual. Los totales
de secuencias, spans, probes, ejemplos y consumidores no se suman al denominador
ExUnit raíz.

No se auditó íntegramente el código de dependencias ni cada codeblock histórico:
la superficie documental ejecutable revisada son los 16 bloques seleccionados
por el probe y los 12 ejemplos. Proveedores/DB se auditaron en fuente; no hubo
aceptación de sistemas externos, aplicaciones consumidoras ni backend OTel.

## Dictamen por familias

| Contrato/familia | Evidencia y estado de la auditoría | Acción realizada | Limitación |
|---|---|---|---|
| Core, efectos parciales y batches | Las regresiones comprueban seis outcomes por ID, progreso y efecto anterior al fallo. | Conservadas; añadido after-tool efectivo y negativas sin replay. | No rollback ni idempotencia externa. |
| Schemas de tools y output Ecto | Frontera JSV/casts/refs/dialecto/cache sustancial; esquemas publicados exactos son contratos. | Conservadas; corregidos y verificados enums tipados y bounds de longitud. | Reflexión no representa validaciones custom/condicionales completas. |
| Scope, permisos y coste | Journals independientes por identidad/ancestry, autoridad y admisión concurrente. | Conservados; adapters ya no convierten uso ausente en cero conocido. | IO fuera del scope y consumo no reportado no se reconstruyen. |
| Contexto y delegación | Dos tests anunciaban contexto mientras ignoraban `ctx`/args. | Corregidos oráculos y forwarding de keys átomo con datos consumidos por el hijo. | La opción `prompt_arg` sigue siendo string. |
| Proveedores y streaming | La aceptación externa descartaba terminales de error; un test «OpenAI payload» nunca llamaba al adapter. | Oráculo compartido corregido; falso payload retirado con sustituto y mutación independiente. | Los 22 casos reales siguen excluidos. |
| Protocolos, MCP y transporte | SSE/ensamble/Req/TCP/Port/suspensión cubren fronteras diferentes; 12 mocks sin cierre. | Capas conservadas; mocks poseídos/cerrados y schema false preservado antes de efectos. | Cancelación local no demuestra rollback remoto. |
| Server/Session, eventos y cola | `or true`, recepción selectiva presentada como FIFO, stale-message obsoleto y telemetry sin identidad. | Sustituidos por joins reales, journals causales, mensajes vivos y correlación propia. | Terminal único sólo mientras vive el owner. |
| Persistencia y codecs | ACK/dirty/retry-save/v1/v2/policy fría y secuencias tienen oráculos fuertes; algunos roundtrips sólo cuentan. | Comparación de datos/uso y teardown fortalecidos; IDs Text/Thinking corregidos. | Snapshot no es replay; JSON no redacta strings secretos. |
| Store Postgres excluido | Tres expectativas antiguas difieren del dispatcher y `Usage.details` actuales. | Alineadas y contrastadas con tres contratos Repo sintéticos. | Ningún test local certifica Postgres. |
| OTel y processor | Sentinels efectivos y redactor antes de exportar; dos tests de batches sólo contaban. | OTLP/cold SDK/R3 conservados; conjuntos de IDs comprobados sin imponer FIFO. | `exported` mide callbacks; límites HTTP nativo vigentes. |
| Probes, evals y carga | C0 no fallaba por indicador falso; vacíos y pérdidas normales podían conservar verde. | Manifiestos explícitos, negativos vivos y validación de resultados/percentiles. | Smoke de160runs no benchmark ni concurrencia efectiva32. |
| Consumidores TAR y CI | Exit0 sin manifest de seis tests; CI no reflejaba gates offline. | Resultado estructurado y CI finita, con diagnóstico strict visible en TAR nuevo. | Matriz compilada/TAR no se sustituye por suite raíz; strict pendiente. |

## Criterios de consolidación

- Retirar sólo después de identificar contrato, sustituto y comportamiento que
  hace fallar al sustituto. El test ficticio de payload de
   `structured_output_test.exs` fue el caso retirado: lo cubren los bodies reales
  de `output_schema_contract_test.exs`, además del caso válido de output existente.
- Conservar diferencias de core/Server/stream, validación Ecto/JSV, dialectos,
  sync/streaming, fake/Port/TCP, v1/v2/cold policy y none/API/SDK/exporter. Nombres
  parecidos no prueban equivalencia de fallos.
- Consolidar helpers sólo cuando comparten mecánica; no convertir los oráculos
  independientes de secuencias en otra implementación del framework.
- Una mutación del resultado esperado demuestra sensibilidad del comparador;
  una mutación del comportamiento observado demuestra una frontera distinta.
  Registrar ambas con su nombre correcto y hacerlas en copias aisladas.

## Implementación y aceptación

### Cambios implementados

| Decisión | Cambio y garantía observable |
|---|---|
| **Mantener** | Secuencias independientes de scope/Server/Session, tres modos del loop, parser/Req/TCP/Port, v1/v2/policy fría y grafos opcionales de paquete. Protegen fronteras distintas. |
| **Eliminar** | Un falso test de payload OpenAI en `structured_output_test.exs`. En copia de producción, omitir `output_tools` deja verdes sus cinco casos antiguos y hace fallar los dos sustitutos Req de `output_schema_contract_test.exs` (10/10 → 8/10). También se retiró un Agent sin uso de `mcp/protocol_test.exs`; el test puro permanece. |
| **Consolidar soporte** | Los dos loops MCP comparten ownership/teardown en un helper de 46 líneas; conservan handlers de protocolo distintos. Los 12 mocks cierran incluso cuando falla un assert, comprobando DOWN del PID exacto. |
| **Corregir** | Terminales externos, contexto de macro/builder, sumas asimétricas y efecto real antes de deny/stubs; contenido/orden que alimenta resumen; payload completo OpenAI y replay de firma Anthropic. |
| **Corregir runtime** | Join real y handoff propio; orden observado con patrón común; mensajes stale de los cinco handlers vivos; telemetry con identidad/distractor; teardown de owner reiniciado y fidelidad de historial/uso. |
| **Añadir contratos** | After-tool transforma contenido sin falsear identidad/status/uso y sin replay; parsers conservan uso desconocido; MCP conserva schema false; keys válidas llegan al hijo; reflexión Ecto tipada y longitudes; IDs de Message y Repo sintético sin DB. |
| **Endurecer gates** | IDs de batches, manifests no vacíos C0/evals, snapshot tipado observado, carga sin drops normales y percentiles recalculables, seis nombres ExUnit reales sin exclusiones en consumidores TAR. CI offline y artefactos por fase. |

No se fusionaron casos sólo por similitud de nombres. Los candidatos de fusión
opcionales del inventario se conservaron cuando no se completó la demostración
de equivalencia; los falsos verdes y efectos mal observados tuvieron prioridad.

### Bugs de biblioteca frente a pruebas defectuosas

Los fallos de biblioteca se reprodujeron **antes** de corregirlos: uso incompleto
convertido en conocido, schema Ecto contradictorio o debilitado, schema MCP false
permisivo, prompt delegado vacío e IDs Text/Thinking perdidos. Decisión y migración
en diseño8.10–8.11 y la guía de migración. Ecto sigue siendo la autoridad del output;
JSON de snapshots no redacta secretos y no recupera IDs que antes no se escribieron.

La revisión fresca encontró además dos aristas del primer fix de reflexión:
booleanos como nombres de Ecto.Enum y longitudes dependientes del orden/calls.
Un autor distinto añadió cinco regresiones y corrigió la normalización por tipo
y la intersección de bounds. Las contradicciones siguen siendo insatisfacibles,
como en el changeset; no se relajan constraints para obtener verde.

Los `or true`, mocks sin owner, timestamps de fixture asumidos positivos,
recepción selectiva presentada como FIFO y expectativas Postgres antiguas son
defectos de tests/harness. Se registran aparte; no se atribuyen al runtime.

### Evidencia y denominadores

| Gate | Resultado actual |
|---|---|
| Baseline nativo antes de cambios | **73 fuentes**, 620 correctos/28 excluidos, seed37556. |
| Nativo tras fixes de revisión | **75 fuentes**, focal45/45 y suite **655 correctos/28 excluidos**, warnings-as-errors, seed37556; formato global correcto. |
| Harness compilado | 23/23; driver local con seis fases exit0: compile, C0, docs7/7, R3 instrumentado1/1, evals y smoke160. |
| Review runtime/harness fresca | Aprobada; 54+21 casos disjuntos en VMs propias, control rojo del codec antiguo y teardown tras fallo inducido. |
| Review core y delta Reflection | Aprobada; los ocho casos rojos independientes pasan8/8 tras el fix y los contratos23/23. T3 se reprodujo también por el revisor. |
| Mínimo Elixir1.17.3/OTP27.3.4.17 | Build vacío independiente:75 fuentes y dependencias compiladas sin warnings; **655 correctos/0 fallos/28 excluidos**, seed37556. |
| TAR, cuatro grafos nativos | **24/24 contratos runtime**, seis nombres esperados por modo, sin fallos/exclusiones/skips; **los cuatro fallan strict** por diagnósticos de dependencias. Seed771506. |

El TAR runtime verificado tiene93archivos y SHA256
`66b6a5f9402a38a19f06e062382384da031ceec34c4ce419c36654c833f9a600`, de la captura
WIP de09:43:06UTC. El lock es el original de esta sesión. Cada grafo emite una
deprecación de `xref.exclude` de Req0.6.1 en `compile-edge`; exporter añade nueve
warnings gproc/OTP29 en `compile`. El runner devuelve **exit1**: no son warnings
propios de ExAgent ni fallos de sus24contratos, pero tampoco un pase strict.
Las cifras/documentos de cierre posteriores se comprueban como delta documental
del preview, sin volver a atribuirles una matriz runtime diferente.

CI está **configurada y su driver ejercitado localmente**; GitHub remoto no se
ejecutó en esta sesión. El [procedimiento](verification.md) incluye comandos,
validadores de JSON y la frontera manual TAR. El mínimo probado es una combinación
concreta1.17/27, no todas las combinaciones Elixir/OTP permitidas por el manifiesto.

De 648 a **683 casos raíz**: +23 contratos de las cuatro fronteras (incluidos
cinco de review), +5 casos runtime/codec/Repo, +3 harness y +4 netos core
(-1 falso payload, +1 builder, +2 after-tool, +2 controles del oráculo externo).
Son **36 añadidos y uno eliminado**, no una optimización del contador. Las
iteraciones de las tablas y las secuencias no se cuentan como casos raíz nuevos.

Los controles de conducta en copias incluyen omitir output_tools, cambiar contexto,
ejecutar antes de negar, repetir contribuciones, perder contenido/firma, invertir
resumen, suprimir eventos/guards y duplicar IDs de spans conservando counts. Los
negativos de JSON/manifest/oráculo se etiquetan como datos alterados, no como bugs
de producción reproducidos. No se ejecutó un benchmark de rendimiento comparable:
los tiempos de cada gate son registros operacionales, no una mejora de velocidad.

## Puntos para desarrollo y segunda revisión

Son entradas contrastadas para priorizar cuando se trabaje en esas fronteras o
se prepare el paquete final, no tareas obligatorias para prolongar esta auditoría.

1. **P2 propios:** presupuestos/reinicio de retry por tool efectiva; nombres duplicados o
   colisión con `final_result` antes del modelo; headers y settings de adapters.
2. **P2 propios:** callbacks fallidos de Session/TurnPolicy, emitter nuevo tras restore,
   roster vivo incompatible, controles busy de reset/set_model y vida del run
   después del timeout/muerte del caller. Reusar fixtures causales antes de añadir
   otro escenario nominal.
3. **Integración:** SDK cargado tarde sin recompilar el artefacto none/API y cobertura
   adicional de namespaces/listing corrupto. IDs Text/Thinking ya están corregidos;
   la omisión de `ToolReturn.usage` sigue siendo intencional y documentada.
4. **Aceptación externa:** proveedores, Postgres, aplicaciones consumidoras y
   elección de backend OTel con acceso autorizado. Mantener warnings gproc y
   problemas HTTP nativos visibles.
5. **Seguimiento externo, menor prioridad:** revisar Req0.6.1/Mix1.20 y gproc/OTP29
   al actualizar dependencias o preparar la publicación; comprobar si upstream los
   corrigió y evaluar su impacto. Conservar el diagnóstico strict sin duplicar
   suites externas ni cambiar dependencias sólo para borrar warnings. Valorar
   también la portabilidad y frecuencia del gate TAR en CI.
6. **Futuro, no gap de una feature implementada:** C7, replay universal,
   exactly-once, sandbox, nuevas modalidades/protocolos y durabilidad distribuida.
