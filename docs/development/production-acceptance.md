# Matriz de aceptación de ExAgent v2.0.0

**Especificación de aceptación, no resultados obtenidos.** El [alcance](release-scope.md)
define las promesas; el [roadmap](roadmap.md) contiene tareas/estados. Los escenarios
de esta página son oráculos de producto reutilizables, no otra suite upstream.
Los criterios fueron revisados2026-09-22 según diseño8.22; el mínimo R1 recibió
posteriormente aceptación offline junto a R2 base y R2.3 tras review independiente.
Consultar roadmap§5/estado para evidencia vigente, sin convertir esta
especificación ni cifras históricas en aceptación de G2–G6 o de C7 pendiente.

## 1. Reglas de evidencia

Cada ejecución registra revisión/WIP o hash de fuentes, lock, runtime, modelo y
endpoint cuando corresponda, configuración relevante, comando, seed, exit code,
pass/fail/excluded y artefactos. Datos sintéticos y credenciales fuera de informes.

Separar cuatro niveles:

1. **Declarado:** documentación/catálogo dice que la capacidad existe.
2. **Implementado:** hay código integrado para ofrecerla.
3. **Aceptado offline:** frontera ejercitada con oráculo local y datos/efectos reales.
4. **Aceptado externo:** el backend/modelo/DB concreto y el consumidor del artefacto
   han ejecutado el escenario pertinente. Sólo esto certifica esa integración.

No extrapolar desde un modelo a todo el proveedor ni desde ReqLLM al adapter ExAgent.
No contar exclusiones, skips o un callback mockeado como pases del sistema externo.
Un test verde que no comprueba el efecto o el dato relevante no acepta el contrato.

Las ventanas de fallos y concurrencia se fuerzan con barreras/control de mensajes,
diarios y confirmaciones observables; evitar sleeps como prueba de orden. Los
oráculos deben distinguir el defecto: por ejemplo, dos resumers que nunca coinciden
no aceptan CAS y una tool simulada sin efecto observable no acepta ausencia de replay.

## 2. Escenarios funcionales obligatorios

Reusar `test/exagent`, fixtures TAR y probes existentes. Añadir escenarios cuando
la nueva funcionalidad o frontera no tenga oráculo; no duplicar casos nominales.

| ID | Perfil y estímulo | Oráculo exigido | Responsables |
|---|---|---|---|
| A1 | One-shot + tools + Ecto; sobre válido/vacío e inválido en sync, stream_text y stream público | Gate de sobre/schema/strict/history abajo; output lógico/IDs/outcomes/uso con calidad equivalentes; cero efectos inválidos, un efecto por control válido; deltas provisionales | R1/R2 |
| A2 | Stream fragmentado, truncado, lento, abandonado y owner muerto; imagen sólo donde cualificada | Lazy host; terminal válido antes de efectos; EOF/length/filter/unknown/timeout/cancel nunca ejecutan tools parciales; close de transporte/metadata y límites propios postdecode medidos, sin promesa hard RAM predecode | R1/R3 |
| A3 | Dos hijos compiten por una request, tool denegada por ancestro, usage ausente/parcial/cero normalizado y petición strict | Admisión host atómica exacta; cero efectos denegados; sin doble uso ni cero observado inventado; ordinary execution con límites host continúa sin accounting, strict dependiente de datos ausentes rechaza explícitamente | R2/R3 |
| A4 | Dos callers/conversaciones/namespaces, colas saturadas, steer y eventos tardíos | Orden y correlación; busy/queue_full explícitos; ningún historial/dep/efecto cruzado; recursos propios liberados | R3 |
| A5 | Tool produce efecto; save falla; nueva mutación y retry de checkpoint | Error de checkpoint con output/revisión; mutación bloqueada; un efecto y ninguna segunda llamada a modelo/tool al guardar de nuevo | R4 |
| A6 | Pausa antes de tool, reinicio VM, approve/deny/expire/cancel y dos resumers; codec/historia versionados | Llamada lógica efectiva/definición/codec exactos persistidos; cero efecto previo; claim único; payload/versión/revisión obsoleta rechazan o migran explícitamente sin crear aprobación; permisos actuales aplican | R5 |
| A7 | Crash tras claim, durante tool y tras efecto antes de save; owner antiguo responde | No se declara rollback ni éxito ficticio; estado incierto recuperable; stale owner no confirma; reconciliación/retry explícito probado | R4/R5 |
| A8 | Secuencia/router/fan-out, una rama falla y otra pausa con delegado | Merge determinista, parciales/availability conservados, admisión host y umbrales estimados diferenciados; resume sin doble uso, replay ni huérfanos | R6 |
| A9 | Tool MCP por stdio y Streamable HTTP; schema no representable, args inválidos, timeout, desconexión/late reply y approval | Rechazo de schema antes de IO al modelo; misma validación lógica/efectivos/autoridad/C7; invocaciones remotas contadas, cleanup y sin promesa de rollback | R7 |
| A10 | Traza compuesta con paralelo, delegado, retry correctivo, checkpoint fallido, pausa y resume | Árbol/intentos correlacionados; host exacto separado de uso normalizado/estimado con calidad/procedencia/unidades; sin duplicación, datos privados ausentes y pérdidas observables | R7/R8 |

### Gate inicial R1.2: sobre obligatorio antes de levantar guards

Usar ReqLLM **stock real**, API pública y transporte sintético inspeccionable;
no mockear Model/feature para declarar aceptada la frontera. Conservar los guards
generales hasta demostrar cada camino a habilitar. El objeto semántico se valida,
no se promete recuperación de raw que upstream borró. Reusar las reproducciones
locales y comparar el payload efectivo, no sólo el schema antes de ReqLLM.

| Frontera | Casos y oráculo |
|---|---|
| Args buffered y una vista stream | `[]`, `[{}]`, `null`, string, número, boolean, `{}`, JSON truncado, `{"arguments":[]}`, campo ausente y claves exteriores extra: cero efectos. `{"arguments":{}}` con tool vacía y objeto no vacío válido: exactamente uno; IDs intactos. Invalidez explícita jamás se repara. |
| Schema y raíz | Required/optional/defaults, additionalProperties, anidados, arrays/enums/nulls, boolean schemas. Probar `#`, `#/$defs/...`, `$id`, anchors/dynamic/refs externas dentro del subset elegido; cualquier caso no representable rechaza antes de IO. Sin resolución HTTP/file ni rewriter general preventivo. |
| Strict y proveedor | Inspeccionar payload stock por perfil exacto, incluida exigencia de required/additionalProperties en anidados. No cambiar opcional→required/defaults silenciosamente; provider strict no sustituye validación local. Chat primero; Responses/otros al cualificarlos, no como prerequisito universal. |
| Historia/codec | Modelo→tool→modelo, sobre exactamente una vez, IDs/orden/resultados/metadata permitida conservados. Hooks/approval ven argumentos lógicos; JSON/snapshot/compaction/restore conservan versión. Historia pre-sobre tiene migración/rechazo explícitos; llamada inválida nunca se hace válida envolviéndola ni hay fallback wire antiguo. |
| Output | final_result/Ecto-tool pasa el mismo sobre: vacío válido, embeds/nulls, inválido y retry explícito contabilizado. Modo nativo es contrato separado, no aceptado por pasar modo tool. |
| Autoridad/C7 | Revalidar schema lógico y efectivos tras hooks; identidad estable y ancestros no ampliados; callbacks ReqLLM noop. Outcome y llamada lógica exacta ligados a definición/codec; claim, revalidación actual y efecto incierto permanecen A5–A7. |
| Terminal/recursos | EOF, truncación, length/filter/unknown, timeout/cancel fallan antes de efectos/output completo; lazy, una vista sin reenumeración, cleanup success/halt/exception/owner kill. Medir buffers propios postdecode y coste de materialización upstream. |

Si buffered pasa pero stream no, la aceptación sigue parcial. Un fallo que exige
fork/patch/API privada/parser wire/rewriter general detiene esa opción y mantiene
el perfil cerrado. El pase offline permite integrar únicamente el perfil probado;
G2 live sigue requerido para anunciarlo, con presupuesto/destino autorizados.

### Aprobación: combinaciones que no deben omitirse

- Sin Store capaz de operaciones atómicas: rechazo explícito de modo durable,
  antes de ejecutar o presentar la petición como guardada.
- Approve repetido y approve/deny concurrentes sobre la misma revisión.
- Cambio de args, definición, versión o policy entre pause y resume.
- App proporciona un aprobador distinto/no autorizado; texto/modelo no eligen actor.
- Muerte del proceso que solicitó la aprobación: consulta y decisión siguen siendo
  posibles por ID sin conservar ese proceso.
- Timeout humano, cancelación y pérdida de PubSub; estado y terminales coherentes.
- Hijo delegado pendiente y hermano ya completado; counters y resultados restaurados.
- Paso externo no idempotente cuyo efecto ya ocurrió: dejar incertidumbre visible,
  no automatizar otro intento para conseguir un resultado final exitoso.

## 3. Gates de release

| Gate | Qué demuestra | Criterio de pase |
|---|---|---|
| G1: integración local | Contratos ExAgent y release stock adoptada | Gate R1.2 y A1–A10 locales pertinentes, focales/suite sin fallos propios, formato/compile/docs; evidencia antigua no acepta contratos replanteados |
| G2: modelos/proveedores | Operaciones reales de cada perfil anunciado | Mínimo Chat-compatible y combinaciones adicionales anunciadas, modelo/versión/endpoint/API/config fijados; sobre/strict/history/tools/Ecto/stream efectivos, límites explícitos |
| G3: durabilidad SQL | Datos y claims sobreviven procesos/VM y fallos DB | Postgres sintético, migraciones/restores, conflictos y A5–A8 pertinentes ejecutados; no sustitución por ETS |
| G4: observabilidad | Transporte y diagnóstico utilizable en Langfuse y Opik | Ambos: OTLP real + API/UI del mismo perfil A10/candidata; calidad/procedencia/unidades del uso sin factura ficticia, privacidad y fallos observados |
| G5: distribución/CI | Usuario externo instala el artefacto correcto | TAR identificado, consumidores limpios, CI remoto exacto y migración de wire/history/codec/Usage/strict y retirada R1.8 coherentes |
| G6: operación/carga | Límites operativos definidos y cleanup | Saturación/admisión, queues/retención propia postdecode en bytes/chunks, deadlines/concurrencia, aislamiento y soak finito; umbrales previos, sin exigir ni prometer hard RAM predecode |

Estos gates pertenecen al contenido final de candidata. Se puede reutilizar evidencia
previa **del mismo código/frontera no afectada**, dejando su revisión explícita;
un cambio de dependencia/transporte/schema reabre sus gates pertinentes. No repetir
todos los benchmarks al corregir una errata.

### G1. Rutina de desarrollo

Usar el prefijo aislado de [entorno](environment.md). El comando base es:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test
```

Para cerrar una vertical runtime, comandos y gates de [verificación](verification.md)
con la cadencia de [ejecución](execution-flow.md): focales durante desarrollo,
compilación con warnings como errores del proyecto, una suite integrada al estabilizar
y formato. No repetir la suite por cada microhito/corrección ni desde el padre.
Los warnings de dependencias se clasifican con su impacto y exit real;
no se ocultan ni obligan por sí solos a mantener internals upstream.

MCP requiere, además de fixtures de fallos, una integración con implementación
independiente mantenida de servidor, datos sintéticos y ambos transportes. Puede
ejecutarse localmente/loopback: no necesita un servicio público de pago. Un servidor
que sólo devuelve los bytes esperados por nuestro cliente no prueba interoperabilidad.

### G2. Matriz real pequeña y discriminante

| Familia | Caso mínimo | Lo que no debe inferirse |
|---|---|---|
| Chat-compatible, mínimo inicial obligatorio | Sin reasoning/provider-native; texto, tools/sobre, Ecto-tool, stream, history y error | Modelo/endpoint/API/config exactos aún por cualificar; no certifica Responses ni todo OpenAI |
| OpenAI Responses, adicional por capacidad | Operaciones anunciadas y continuación con metadatos propios | No exigir toda la familia para cerrar R1 ni admitir tools server-side no seleccionadas |
| Anthropic Messages, adicional por capacidad | Sólo paths sin pérdida de bloques requeridos; tools/uso/cache/stream/continuación que se anuncien | Paths afectados cerrados; reasoning.enabled:false no prueba ausencia y commit3536ff94 aún no es release adoptada |
| Google, adicional por capacidad | Operaciones anunciadas de texto/tools/stream/output nativo/imagen | ThoughtSignature perdido mantiene perfil afectado cerrado; catálogo no certifica operación |
| Gateway/custom | Model externo y spec por instancia ejercitados offline; G2 para endpoint/auth/opciones que se anuncien live | No factura ni capacidad idéntica al upstream, sin fallback silencioso |

Elegir modelos exactos antes de ejecutar. Registrar para cada operación uno de
`aceptada`, `limitada`, `no soportada`, `no verificada`, junto a evidencia y motivo.
No se exige completar todas las filas adicionales para cerrar R1. Una operación
requerida del mínimo necesita combinación compatible explícita; no degradación,
pérdida ni cambio silencioso de modelo/proveedor. Perfil que pueda requerir metadata
que stock pierde se excluye antes de IO hasta ruta pública fiel cualificada.

Coste real requiere presupuesto y concurrencia autorizados. Preparar un runner
con selección explícita que no active tests live accidentalmente. Las credenciales
se pasan por entorno/configuración segura, no se guardan en el manifest del informe.

### G3. Postgres y recuperación

Usar Repo/esquema sintéticos con alcance de migración/cleanup autorizado. Probar
save/load/CAS/claim con al menos dos callers, nueva VM que rehidrata definiciones,
interrupción de conexión/transacción y conflicto de revisión. El diario de efectos
externos debe vivir fuera del proceso que se mata, para observar lo ocurrido.

Guardar plan de migración de snapshots y tablas de continuación, política de
retención y procedimiento de recuperación de datos. Un test que sólo vuelve a
leer el estado del mismo GenServer no demuestra durabilidad.

### G4. Backend

El mandato del usuario2026-10-02 exige **Langfuse y Opik igualmente validados**,
sustituyendo la aceptación de un único backend de referencia. Reutilizar el
escenario A10 y una fuente de candidata identificada; cada backend necesita
recibo independiente de transporte nativo, lectura API completa y UI autenticada.
Una correspondencia de IDs/tipos sólo se admite si demuestra todo el parentesco,
estados y atributos exigidos; documentar diferencias y pérdidas sin ocultarlas.
La aceptación Langfuse ya obtenida se conserva y no acepta Opik por analogía.
Resultado2026-10-02: ambos aceptados en A10,33observaciones/667atributos por API
y los mismos12casos/248atributos en sus interfaces autenticadas. Opik tiene
recibos propios, incluidos fallos de transporte y navegación/captura; no se
certifica disponibilidad del backend o estabilidad de la interfaz.

Seguir [evaluación del backend](backend-evaluation.md). Usar el proyecto autorizado;
comparar alternativas sólo por carencias demostradas. No basta un HTTP200,
callback exported ni captura de un span suelto. Se debe localizar una ejecución,
explicar contadores host, coste estimado/calidad/disponibilidad y diagnosticar
fallo/pausa/reanudación por IDs. No exportar cero normalizado como observado ni
sumar uso agregado como otra generación; snapshots preservan availability.

### G5. Consumidores y runtimes

| Consumidor | Perfil |
|---|---|
| Mínimo | Instalar TAR, one-shot/tools/Ecto/stream sin SQL/Phoenix/SDK |
| Runtime | Server/Session, eventos, colas, delegación y compaction |
| Durable | Postgres, aprobación, dos resumers, recuperación y composición |
| Extensible | Model propio, provider ReqLLM externo, Tool/Store/PubSub custom según capability |
| Instrumentado | Grafos none/API/SDK/exporter y configuración final con backend |

Reutilizar `test/fixtures/package_acceptance/` y su runner; ampliar por fronteras
nuevas y hacer portable el bootstrap en R8.5. Cada grafo declara el conjunto esperado
de escenarios/nombres: no fijar un contador para siempre ni aceptar un exit0 vacío.

Cualificar los pares/patches de Elixir/OTP finalmente declarados y dependencias
resueltas desde consumidor, no sólo el lock raíz. Los objetivos iniciales están en
el alcance. CI offline por defecto; gates live/DB/backend separados y explícitos.

### G6. Perfil operativo finito

Antes de medir, registrar: hardware/VM, concurrencias, tamaño de prompts/respuestas,
tools por batch, profundidad de delegación, tamaño de colas, historia, duración y
repeticiones, exporter/store simulados o reales y umbrales de aceptación.

Punto de partida práctico: escenarios sintéticos con concurrencias1/8/32, oleadas
de creación/cancelación de owners, consumo lento, saturación deliberada y pausa de
muchas ejecuciones. Ajustar la cantidad/duración a una medición útil y acotada;
no gastar llamadas LLM para medir el overhead del framework.

Medidas: completados/errores esperados/inesperados, effects count, p50/p95/p99,
memoria/processes/ETS/FDs antes/durante/después, pendientes, pérdida de eventos/spans
y tiempo de cleanup. Comparar oleadas equivalentes tras cleanup, no una sola foto
de RSS de toda la VM. Una cota en número de items necesita también una política
para bytes grandes.
En ReqLLM se miden retención/queues propias **después de decode**, concurrencia,
admisión y deadlines, más coste O(respuesta) del materializador upstream e historia
canónica. Un frame puede asignarse antes de disparar el umbral: no presentar esto
como hard RAM predecode. Cerrar transporte/metadata y liberar lo poseído sigue
siendo obligatorio; renunciar a aquella garantía no permite buffers propios infinitos.

El pase exige cero violaciones de autoridad/aislamiento, cero repeticiones no
autorizadas de efectos, cero runs propios huérfanos y cumplimiento de los límites
configurados/definidos. Latencias sintéticas no se publican como SLO de LLM. Si una
regresión supera el umbral predeclarado, investigar causa antes de optimizar; no
seleccionar sólo el mejor intento ni rebajar el umbral después para declarar pase.

## 4. Severidad, bloqueos y cierre

- **Bloqueante:** pérdida/corrupción de datos, ampliación de autoridad, efecto
  repetido sin autorización, resultado confirmado sin garantía prometida, fuga
  no acotada, contrato central incoherente o instalación rota en un target declarado.
- **Importante:** fricción pública o diagnóstico que impide un perfil comprometido;
  resolver o acordar explícitamente una reducción de alcance antes de release.
- **Seguimiento:** mejora opcional o warning externo sin impacto funcional demostrado;
  documentar propietario/condición de revisión, no convertirlo en auditoría infinita.

Un acceso ausente produce un gate pendiente/bloqueado, no una certificación basada
en mocks. R9 exige un resumen de todos los gates, límites y como máximo una revisión
de la integración/distribución y delta aún no revisado, reutilizando evidencia válida
de unidades aceptadas. No reabre sus revisiones. `lista para versionar/publicar` y
`publicada2.0.0` son estados distintos.
