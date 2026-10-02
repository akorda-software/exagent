# ExAgent — Principios y decisiones de diseño

> Referencia de principios y decisiones. Para el mapa vigente, empieza por
> [Arquitectura actual](overview.md); para prioridades, consulta la
> [hoja de ruta](../development/roadmap.md).
>
> Las secciones 3–7 conservan el contexto arquitectónico original. Sus etiquetas
> «NUEVO»/«futuro» y comparativas no describen el estado actual. Las decisiones
> posteriores de la sección 8, las guías y el [estado verificado](../status.md)
> prevalecen sobre esas descripciones históricas.
> La decisión **8.22 (2026-09-22)** sustituye los requisitos de fidelidad raw,
> presencia de uso y cota predecode como objetivos de ReqLLM en8.15–8.18.
> Conserva sus reproducciones y guards como estado runtime, no como aceptación
> del nuevo contrato. C7 y los contratos de autoridad/recuperación permanecen.

## Coste de normalización JSON y canonicalización (2026-10-02; CI030)

**Problema demostrado:** el CI completo descubre vencimientos durante pruebas
de continuación. En una reproducción acotada de Frame10, 81 ACK implican unas
385 mil canonicalizaciones y 15 millones de construcciones de JSON Pointer.
La normalización construía rutas escapadas para cada valor válido; canonical
volvía a codificar y decodificar el árbol ya normalizado antes de ordenarlo y
codificarlo otra vez. El coste afecta cualquier consumidor de estas primitivas.

**Decisión/beneficio:** la normalización conserva segmentos de ruta y construye
el mismo Pointer sólo al informar un error. Canonical normaliza, ordena las
claves y usa el encoder estricto de Jason una vez. El árbol normalizado contiene
sólo escalares JSON, listas propias y mapas con claves UTF-8 únicas: ordenar sus
pares no introduce duplicados. Se conservan rechazo de colisiones, structs,
términos opacos y UTF-8 inválido; el validador de objetos ordenados externos
`JSON.encoded_result` permanece intacto, incluido el gate de argumentos ReqLLM.

**Alternativas/impacto/migración:** subir leases o serializar pruebas ocultaría
el coste; una caché introduciría identidad e invalidación innecesarias. Esta
optimización conserva bytes canónicos v1, distinción 1/1.0, orden de arrays,
errores/Pointers, digests y formatos persistidos. No cambia límites, reservas,
timeouts, autoridad ni codecs; los registros existentes no necesitan migración.

**Verificación:** comparación diferencial de 1.015 entradas contra la fuente
anterior, con casos inválidos, Unicode, escapes y números extremos; regresiones
de codec y argumentos. El mismo escenario perfilado de 81 ACK baja de 27,205 a
18,968 segundos en la copia privada con dos schedulers y tracing. Esa medición
no garantiza una latencia de producción ni sustituye la suite remota integrada.
El estado de CI y sus límites quedan en la hoja de ruta y verificación.

## Slot portable de tools Frame10 (2026-10-01; implementación)

**Problema demostrado:** los defaults ordinarios asignaban un slot de1MiB a cada
tool. Frame10 reserva cuatro proyecciones JSON con escape máximo6×:24MiB por call,
antes de ejecutar una sola tool, frente al registro máximo8MiB. Las regresiones
SequenceRun de tools, accounting y C7 fallaban `record_limit` antes del callable.

**Decisión/beneficio:** Frame10 intersecta el slot determinista de payload/historia
con un techo portable64KiB por tool. Conserva las cuatro reservas independientes,
metadata, cleanup, admisión exacta y registro8MiB.24×64KiB=1.5MiB por call; cinco
calls vivos necesitan7.5MiB más metadata. El techo **no garantiza admitir cualquier
batch/profundidad**: el historial y otras reservas pueden impedir su admisión.
Runtime y transición CAS derivan la misma cota, persistida en `tool_return_bytes`;
restore conserva esa cota y las intersecciones de autoridad sin ampliarla.

**Alternativas/impacto:** reducir el default público a64KiB limitaría también texto
ordinario; aumentar el registro rompería el bound; repartir el saldo por orden de
terminación daría cotas distintas según scheduling. El nuevo techo sólo afecta
Frame10 experimental. `ExAgent.run` ordinario y lifetimes7/8/9 conservan sus slots,
y `max_payload_bytes:1MiB` sigue aplicando a las otras fronteras. Una tool durable
que excede el slot produce marker/error fatal, sin truncación ni callback replay.
Se comprueban tanto el término retenido como sus bytes canónicos `Outcome` sin
usage: el envoltorio portable también debe caber. Exactamente65536 bytes se retienen;
65537 producen marker con bytes/límite y bloquean el wrapper. El uso observado se
mantiene aparte y nunca se cobra dos veces por el raw, wrapper o delegado.
Consumidores que necesitan retornos grandes deben guardar el recurso externamente
y devolver una referencia portable acotada. No hay migración automática de datos.

**Omisión tipada:** un paso de secuencia puede confirmar el output omitido y cerrar
el cursor, igual que9, pero la API devuelve error de checkpoint y no ejecuta el
sucesor. Un delegado omitido no puede completar como raw válido del padre; ese guard
permanece. Verificación/red-green y límites se registran en R6 al cerrar la vertical.

## Delegación ejecutable y cierre causal Frame10 (2026-10-01; integración)

**Problema/beneficio:** los validadores CAS10 anteriores no ejecutaban la composición
desde callbacks reales. El productor y restore comparten ahora el árbol, autoridad,
admisión y journal originales: una secuencia puede delegar, drenar trabajo admitido,
pausar con varias aprobaciones y continuar desde bytes en una VM nueva. El catálogo
explícito enlaza definition/policy/model_ref antes del loader. Finales históricos no
cargan ni repiten el Model ni los efectos ya confirmados.

**Quiescencia/ACK:** el Writer registra sus workers y espera DOWN antes de emitir
pause o failed desde el owner. Un ACK perdido conserva el token exacto y bloquea IO;
`retry_checkpoint` sólo confirma el mismo comando, nunca ejecuta callbacks. Recover
es explícito y fenced. Un raw delegado confirmado antes de admitir su wrapper puede
continuar; un wrapper admitido cuyo control falta conserva incertidumbre. Dos
reanudadores compiten por una sola claim CAS, no por callbacks duplicados.

**Cierre de errores:** los controles fatales confirmados de tool, retención,
accounting rechazado o preparación host seleccionan el frontier por orden estructural.
Los efectos ya admitidos drenan antes del cierre; conservan fuente, raw, observación,
subtotal y contadores exactos. El host previo al efecto nunca inventa una tool intent.
El accounting rechazado conserva su marker y disponibilidad parcial sin sumar uso
inválido. No se admite failed por un string de error, un Model sin confirmar o un
efecto incierto; esos guards, la recuperación explícita y su falta de refund siguen.

**Resultado delegado grande:** node_complete comprueba la proyección raw contra el
slot persistido del padre. Si no cabe, confirma failed con un error y marker derivados
de la respuesta Model y la historia text/typed exactas, no de un resultado omitido o
preimagen ausente. Mantiene esa historia y el uso confirmado; el padre recibe un raw
fatal canónico y no ejecuta su wrapper. La evidencia comprueba hash, estado Model,
posición, attestation typed y límite. No permite fallos NODE/root genéricos.

Si el resultado cabía en el slot persistido pero el host reduce su cota al restaurar,
la prevalidación del raw precede al callback wrapper. Se asienta un final omitido y
control fatal usando las fases CAS ya existentes, conservando raw, efecto, child
completed y ledger históricos. No cambia el slot persistido ni permite replay.
La admisión durable del wrapper y el check de deadline siguen siendo previos; si
se pierde su ACK, los guards de incertidumbre siguen activos. Tampoco un mensaje
de error ordinario cambia retry=true: sólo accounting rechazado fuerza retry=false.

**Alternativas/impacto/migración:** cerrar ante cualquier excepción fabricaría
certeza; reejecutar automáticamente callbacks podría duplicar efectos. Se conserva
la diferencia entre fallo confirmado e IO incierta. Los permisos actuales intersectan
la autoridad original; una denegación de una call ask aprobada se registra como
no-efecto con su binding exacto. Frame10 es el nuevo productor de composición para v2;
restore7/8/9 mantiene sus certificados sin migración, nuevos modos o ampliación de
límites. Cualificación externa, router/fan-out/fan-in y otros cierres Model/root
quedan separados. Evidencia acumulada y límites en R6; ninguna publicación.

## Reserva composicional exhaustion10 (2026-09-29; aceptación interna recibida2026-10-01)

La review demostró que `max(success, failed + exhaustion)` no cubre copias
terminales junto a reservas success de siblings todavía pendientes. La candidata
Record calcula para cada alternativa A `A + sum(max(E_i - a_i, 0))`: E_i son las
copias terminales completas de un nodo pendiente; a_i es exclusivamente su slot
retirado en esa alternativa. Es el máximo sobre todos los subconjuntos de nodos
que pueden agotarse, no préstamo entre siblings. Raw/outcome se cuentan completos
sin descontar además los créditos de resultados; frontier/control/recibos conservan
su contabilidad independiente. No sumamos todas las reservas sin crédito propio:
esa alternativa conservadora rechazó un escenario existente de8MiB.

Impacto: admisión más temprana de record_limit donde antes se confirmaba una
respuesta imposible de terminar. Mismo esquema/Retry terminal, sin migración,
límites mayores ni truncamiento. Fuente±1 del probe ahora rechaza antes en−1 y
cierra en exact/+1. El original histórico sigue rojo porque su control
«roomy» usa el coste posterior del sink como presupuesto de una fuente nueva,
menor que la reserva corregida. Padre autorizó sólo una copia nueva con límite roomy
Record.max_bytes() y etiqueta correspondiente: fuente/sink y assertions±1/refund
intactos. Copia2/2 verde; no aumenta límites de producción ni modifica el original.

Matriz permanente10 casos: ocho variantes source±1 con descriptores pequeños/65536,
preimagen ausente/histórica exacta,0/1/3 retries,0/1/3/6 siblings,1/2/3 agotamientos,
éxito previo plain/typed y settled, Unicode/control/nested escaping, IDs/recibos512,
límites tool256/4096/65536 y ambos órdenes de agotamiento. Coste bytes+reserva no
crece por atestación terminal/finish ni consumo success ya atestado; otros nodos/
calls permanecen intactos salvo outcome parental propio. Dos negativos mantienen
rechazos de corrupción y raw que excede su bound (incluso con checkpoint roomy).
Fuente/sink original868234/866148; mixed1243401 y step230768. Gates10 nuevos,
69 existentes seleccionados y10 oracle/legacy; compile118WA/formato/diff0.
Es evidencia CAS sintética, no aceptación independiente/productor10/VM/R6.

## Output exhaustion CAS10 (2026-09-29; aceptación interna recibida2026-10-01)

El runtime ordinario añade el último Retry diagnóstico al agotar output_retries sin
incrementar used; el certificado anterior contaba todos los Retry como permisos de
continuación. Se conserva OutputResolution1 (`decision=retry`, mismas claves): sólo
en contexto real10, la atestación de la respuesta Model actual confirmada, descriptor/
fingerprint exactos, N permisos históricos consumidos y used=limit=N puede terminar
el nodo. La misma CAS añade sus partes una vez, conserva respuesta/contadores/uso,
marca failed con error portable canónico y selecciona fatal NODE; si es delegado,
materializa además raw parental canónico sin ejecutar/inventar wrapper. El último
Retry certificado es evidencia de validación fallida, **no permiso de otra IO**.
Sólo esa entrada terminal queda fuera del contador, nunca un offset global.

Selección CALL/NODE por ruta estructural confirmada; nodo antes de sus propias calls,
sin llegada/IDs aleatorios. Fatal cierra nuevas admisiones; outcomes/wrappers previamente
admitidos y agotamiento de una respuesta ya confirmada pueden drenar. Preparing,
wrapping y efectos running/unknown impiden finish; un failed genérico no obtiene
certificado. Finish existente conserva raw, hijos completed, parciales, cualificación
de uso y Scope2; aplica refund del claim vigente una vez, sin nueva aritmética.

La reserva antes de validar una respuesta agotada cubre atestación e historia:
descriptor máximo existente65536 (o preimagen histórica del mismo fingerprint),
diagnóstico acotado por reason4096 considerando su codificación previa y escapes,
sibling stubs de identidades ya conocidas, raw/control delegado y recibo propio.
Estas copias pertenecen a la alternativa failed, no al resultado exitoso simultáneo.
Un child agotado ya no puede iniciar wrapper/consumo parental: se retiran sólo sus
slots futuros, conservando bytes materializados. Frontier y control final siguen
independientes; nodo terminal gasta un recibo propio. No límites mayores ni garantía
para payload arbitrario que exceda las cotas/admisión CAS.

Alternativas rechazadas: enum exhaust/version nuevos, request sucesora ficticia,
incrementar used al fallar, inferir agotamiento del texto/status, borrar evidencia o
ejecutar validadores al decode. Beneficio: cierre failed verificable sin habilitar
retry/IO ni perder el diagnóstico original. Legacy7/8/9, productores y restore siguen
intactos; sin migración, publicación o nueva API. Pruebas real-CAS sintéticas en R6
implementation; no callbacks/VM/quiescencia viva ni aceptación producto10/R6.

## Crédito de control final/recibos CAS10 (2026-09-29, revisión pendiente)

Problema reproducido: con recibos escapados máximos, call_wrap admitido en el máximo
de prefijos reales1378383 no podía guardar un fatal legal de4096 bytes JSON; exigía
1382090, sin IO/contribuciones intermedias. El allowance fijo16384 seguía cobrado
además del control materializado. No demuestra un defecto de max(success,cancel).

Record separa4116 bytes de ese allowance por call: crecimiento máximo de
`{"retry":false,"error":<4096 bytes>}` desde null. Se reserva fuera de las alternativas
terminales, y sólo su crecimiento JSON materializado recibe crédito. No se acredita
raw/control, frontier, resultados, siblings ni historia futura por esos mismos bytes.
El allowance restante12268 y los cuatro slots de resultados conservan su función;
un control nil gasta0, retry true es un byte menor. No límites mayores ni truncamiento.

La variante child demostró además un recibo sin consumir: a diferencia de effect,
child/host no tienen raw_or_future que libere el recibo de finalización. Al settled
se gasta uno de sus ocho recibos propios, sin crédito adicional para effect. La
resolución confirmada gasta uno de los dos recibos del batch; consumo libera el pool
restante, no resta esos créditos otra vez. La rama exitosa conserva capacidad para
settlement/resolution/consumption con returns4096 y recibos máximos.

Beneficio: el wrapper admitido puede persistir su final legal sin volver a pagar
evidencia ya guardada. Alternativas rechazadas: aumentar límites, reducir returns,
omitir evidencia, relajar guards o elegir el threshold después del sink. Mismo
Record2/Frame10 experimental, legacy7/8/9 intacto y sin migración/API nueva. Pruebas
CAS/roundtrip y fuente±1 en R6 implementation; no callbacks/VM/productor10 ni cierre
R6. Otros orígenes fatal/recovery permanecen cerrados; revisión independiente pendiente.

## Cierre failed de call-fatal confirmado CAS10 (2026-09-29, revisión pendiente)

Problema demostrado: el fatal final ya confirmado cerraba nuevas admisiones pero
carecía de consumidor terminal. `finish` interno10 ahora cierra esa frontera con
owner/fence/epoch vigentes: exige todos los efectos confirmados/no unknown y ningún
call preparing/wrapping. Los efectos/Model y wrappers previamente admitidos drenan
por sus operaciones existentes; no se autoriza otro Model/batch/dispatch/wrapper.
Es certificado de fases persistidas con entradas trusted sintéticas, **no prueba
de inventario de PIDs, worker drain vivo ni promesa de preempción atómica**.

En la misma CAS, calls no settled pasan a blocked conservando binding/source/raw,
observaciones y outcomes; settled/final/control e hijos completed no se reescriben.
Sólo nodos no terminales elegibles pasan a cancelled, conservando frame/snapshot y
el error portable seleccionado por orden estructural confirmado. Un hijo cancelled
no fabrica ToolReturn ni outcome externo not_executed. Un completed requiere su raw
parental atómico, incluso blocked. Preparing/wrapping/efecto running o unknown
impiden cierre/refund; el registro previo sigue inspeccionable. Orígenes failed-child
todavía no admitidos permanecen cerrados, nunca se convierten en cancelled.

Raíz cursor/state failed + frontier quiescent conserva el error exacto y todos los
resultados parciales confirmados en los nodos completed. No consume un batch/Model
ficticio, no proyecta raw como éxito final ni avanza el prefijo. Reutiliza únicamente
Budget.refund/confirm_refund del claim vigente y libera ownership una vez; no cambia
aritmética, Scope2, costes, cobertura nil ni contribuciones históricas. Get devuelve
status failed y el record data-only; delete terminal respeta cutoff y retención;
reset_snapshot sigue rechazado para snapshot estructural, no crea historia agente.
Composition.resume10 continúa cerrado, incluso terminal; no RunError público10 aún.

Capacidad antes de admisión: se reserva el máximo entre copias de cierre exitoso
tool/output y copias de cancelación (error JSON≤4096 por nodo y crecimiento de estados),
dos destinos mutuamente excluyentes. Recibos y frontier se reservan separadamente,
sin doble crédito de resultados ya materializados. Failed no puede consumir después
historia/output, por lo que libera slots futuros, sin borrar evidencia real. No
garantía universal de capacidad para toda contribución/callback posterior admitida.

Alternativas rechazadas: borrar incertidumbre, fabricar returns/consumo, relajar
guards globales, reembolsar delegados o habilitar restore10 parcial. Mismos formatos
experimentales, sin migración7/8/9 ni nuevo motor/ledger/API de reconciliación. Fatal
raw/host/root/node, exhaustion/output_failed/retention-fatal, recovery/uncertain,
cancel/expire generales y productor10/VM/R6 siguen pendientes y cerrados. Evidencia
real Store CAS/roundtrip y límites en R6 implementation; requiere review acumulada.

## Fatal de control final CAS10: incremento parcial (2026-09-29, anterior al cierre)

Problema: el guard global impedía confirmar el error definitivo de un wrapper ya
admitido. `call_settle` ahora persiste resultado/control/fuente y cierre de frontier
en la misma CAS; el certificado selecciona sólo controles finales confirmados,
ordenados por step/delegate-call path, request step y posición original del call.
No deduce errores desde status/texto ni usa llegada, IDs aleatorios o orden de mapa.
La selección puede cambiar al confirmar otro wrapper previamente admitido; el cierre
no se reabre. Approval-drain cede ante fatal sin publicar approvals ni refund.

Tras cierre sólo se admiten `outcome` de intents existentes y `call_settle` de
wrapping existente, con owner/fence/epoch vigentes. No nuevos Model, batch, dispatch,
before/after hooks, pausa ni éxito. Raw, observaciones, accounting y child completed
se conservan; final wrapper puede diferir de raw. Una callback ambigua sigue marcada,
sin replay/reconcile implícito. Esto no demuestra preempción ni worker drain vivo.

Se reserva una proyección adicional de frontier antes del batch: error JSON≤4096,
tres IDs≤512 bytes con escape máximo y metadata/epoch. Al materializarla se acredita
sólo su tamaño, sin crédito doble contra slots tool/output. Puede rechazar admisiones
antes que el subset anterior; no cambia límites ni borra evidencia. No garantiza toda
secuencia de callbacks/contribuciones en el límite mínimo del batch.

Alternativas descartadas: aceptar errores sin cierre atómico, cerrar sólo después
de consumir batch, fabricar ToolReturns o habilitar failed sin certificado. Mismo
esquema experimental10, sin migración7/8/9 ni productor10. **Pendiente** fatal raw/host,
orígenes root/node, output_failed/exhaustion, resolución fatal consumible, blocked y
cancelación estructural, failed terminal/refund/fachada y capacidad de esos cierres.
No es cierre de fatal10/R6. Tests CAS trusted sintéticos y límites en R6 implementation;
revisión independiente pendiente.

## Cierre exitoso estructural CAS10 (2026-09-29, revisión independiente pendiente)

`step_output`10 consume la respuesta final del step activo y conserva su snapshot,
historia, input/link y resultado portable, avanzando a between_steps o completando
raíz atómicamente. Texto se deriva de la respuesta Model confirmada; output tipado
consume la atestación success existente. No se acepta resultado libre en el comando.
El último step libera ownership y aplica Budget.refund/confirm_refund existentes
una sola vez al saldo del claim actual; no cierra Scope con aritmética nueva ni
reembolsa cada delegado. Scope2/authority/usage y recibos históricos se conservan.

El certificado global revisa todos los nodos, no sólo la hoja seleccionada: terminal
exige descendientes completed y batches consumidos/resueltos, sin raw/wrapping,
approval activa ni efectos inciertos. Cursor completed y estado completed coinciden.
El input raíz y prefijo confirmado no se reescriben. El siguiente input identity
se vincula al output previo; un mapping host conserva su input atestado y versión
del binding sin ejecutar su función en decode. Esto es trusted-producer attestation,
no prueba criptográfica de snapshots arbitrarios ni prueba semántica del callback.

Problema/beneficio: el subset CAS anterior cerraba delegados pero no podía avanzar
steps ni representar el éxito raíz. Se reutilizan Frame10/Record2/OutputResolution1,
sin nuevo esquema, modo o ledger. Se descartan insertar journals finales, simular
versiones/contextos, reejecutar mappings y activar un restore10 parcial. Reservas
typed previas se conservan; respuesta plain reserva copia result y recibo antes de
su ACK, incluyendo delegado raw residual sin doble crédito. No garantiza capacidad
para IO posterior, nuevas contribuciones o wrappers arbitrarios.

`Continuation.get` inspecciona el terminal data-only. **Composition.resume10 sigue
cerrado por CompositionRestore**, incluso completed: la fachada con binding de
definición y proyección pública es un consumer seam pendiente, no una autorización
para activar runtime10. No catálogo/deadline/claim/callback en lectura Record/get;
la futura fachada debe conservar definition binding requerido. Legacy7/8/9 intactos,
sin migración automática, bump o publicación. Fatal/exhaustion/outputfailed,
cancel/expire/uncertain/recovery10 siguen rechazados. Pruebas CAS no son VM/hooks
reales/quiescencia viva/SQL/R6; gates y limitaciones en R6 implementation.

## Reserva de consumo output10 (2026-09-29, corrección pendiente de revisión)

La review reprodujo dos ACK de atestación acotada que después no podían consumir
history/result bajo el mismo checkpoint_limit, sin IO intermedio. Record reserva
ahora sólo los slots pendientes del output actual en cursor response: tamaño JSON
del string parts para su copia en history, crecimiento result sobre null y crecimiento
canónico raw/outcomes/observación para un delegado succeeded. Estos últimos descuentan
exactamente los mismos dos créditos que libera la reserva tool al materializarse;
no se prestan esos bytes a history/result. Los mapas singleton acotan puntuación y
claves escapadas. El resto de slots tool futuros y su holgura permanecen intactos.

Cada output pendiente añade un recibo al horizonte existente (IDs escapados máximos,
contadores y timestamp acotados). Al consumir desaparecen ese recibo y las copias
pendientes, que pasan a bytes reales; entries históricas no vuelven a cobrarse. El
horizonte no aumenta por consumir: revision+steps conserva su cota y el incremento
unitario del contador/cursor cabe en la holgura existente. Ninguna evidencia se borra.

Beneficio: rechazar output_resolution antes de ACK si no cabe su consumo obligatorio,
no bloquear después. Se descartan reducir arbitrariamente el payload, subir el límite,
truncar evidencia o rechazar todo output. Corrección del subset10 no publicado, sin
migración7/8/9 ni cambios de productores/accounting; no promete capacidad universal
para nuevas contribuciones, IO o transformaciones wrapper arbitrarias. Oráculos reales
CAS verifican límites derivados±1, escapes JSON, recibos máximos, siblings/replay,
consumo y wrapper admitidos; no aceptan producto10/VM/R6. Gates en R6 implementation.

## Output tipado/retry CAS10 interno (2026-09-29, pendiente de revisión)

El guard global rechazaba todas las output resolutions aunque sus helpers ya
describían response suspendida y retry consumido. Se integra ese contrato en las
operaciones reales: `output_resolution` atesta el resultado trusted del productor;
`output_consume` añade exactamente sus parts e incrementa output_retries_used sin
crear request; `node_complete` de delegado consume success y confirma child+raw
canónico en una CAS. La siguiente request sólo se admite con frontier abierto.
No se ejecutan validadores/hooks durante transición/decode, ni se reconstruye su
semántica desde args originales. La atestación no autentica snapshots arbitrarios.

El certificado global correlaciona cada entrada con Model confirmado, descriptor/
fingerprint, identidad, hash, posición e historia completos, límite y contador de
retries; rechaza orphans, consumo duplicado y mezcla con batch de la misma request.
Contribuciones Model/tool permanecen en Scope2, sin repricing ni contribución nueva
por retry-consume, terminalchild, raw, wrapper o settle. Success tipado conserva el
resultado validado por el productor, que puede diferir de los argumentos Model.

Alternativas descartadas: convertir status para reutilizar legacy, request sucesora
ficticia, ejecutar callbacks al decode o validar sólo helpers sin consumidor CAS.
Beneficio: detener admisiones durante approval-drain sin perder retry confirmado,
decidir/reclaim y continuar una sola vez con evidencia persistida. Mismos formatos
OutputResolution1/RequestData2/Frame10, nueva operación interna de consumo; no modo
público, auto-upgrade7/8/9 ni bump. Productor9 y motores legacy intactos. Exhaustion/
fatal sin certificado global, rootterminal, recovery/uncertain/cancel/expire y output
omitted continúan rechazados: no se inventa pausa/éxito ni se borra progreso.

Verificación con entradas trusted sintéticas y Store ETS/CAS+roundtrip cada ACK;
no acredita hooks reales, inventario de workers, VM10/SQL ni producto R6. Resultados
y delta exacto en R6 implementation; requiere revisión independiente.

## Accounting CAS10 interno (2026-09-29, pendiente de revisión)

El guard global de usage no nulo impedía conservar contribuciones Model/tool aun
con fuente y operación correlacionadas. Las operaciones CAS10 ahora escriben juntas
respuesta/Outcome, observación tool y operación Scope2, y proyectan la suma ancestral
en snapshots. Model conserva usage de su respuesta; ToolReturn omite usage por su
contrato de historia, por lo que `outcome` tool acepta un input trusted opcional
`usage` y lo conserva en la observación y ledger existentes. No se cambia el codec
Outcome/Message ni los formatos Usage/Scope2. Wrapper, consumo, recibos y retorno de
delegado no contribuyen otra vez. No se ejecutan estimadores históricos: costes y
calificación se propagan tal como los aporta la contribución, sin repricing ancestral.

La completitud10 usa disponibilidad, no la presencia de subtotales enteros. Los
certificados legacy conservan su regla anterior. El seam autorizado de ScopeLedger
decodifica nil con su decoder existente antes de Usage.sum: ausencia produce cobertura
unavailable/partial, no cero. Las proyecciones vacías/enteramente ausentes de snapshot
conservan su representación previa; al haber uso observado manda la suma del ledger.

Requests/batches se admiten una sola vez; token/coste se comprueban retrospectivamente
con UsageLimits y límites efectivos persistidos en cada ancestro. Un resultado ya
admitido puede superar el umbral, pero no autoriza otro efecto. Accounting inválido,
retenido o que no cabe rechaza la CAS sin mutar la fila; no fabrica éxito/fatal ni
borra progreso previo. Capacidad JSON incluye los créditos de cierre y recibos previos:
no se promete que toda contribución válida en su límite individual quepa en toda fila.

Se descartan ignorar usage, nil→zero, reejecutar callbacks y un ledger alternativo.
Beneficio: conservación verificable de disponibilidad/calidad/procedencia/coste y
contadores host separados. Extensión interna10 no publicada; sin migración7/8/9 ni
version bump. Evidencia:26 casos nuevos realETS/CAS con inputs sintéticos, no productor/
VM10. Tras autorización puntual se actualizó sólo el antiguo rechazo Model no nulo:
commit con operación/counters exactos y cero observado distinto de nil; el rechazo
wrapper permanece intacto. Regresión235 y2 probes separados pasan; compile112WA,
formato/diff verdes. Históricos rojos preservados; detalle en R6 implementation.
Output resolutions/retry, rootterminal, uncertain/fatal/cancel/expire siguen cerrados.

## Correcciones causales CAS10 (2026-09-29, pendientes de revisión independiente)

La revisión bloqueante reprodujo cuatro defectos dentro del subset: nuevo Model
sobre historial omitted, final child unknown tratado como resuelto, reserva raw
cobrada otra vez al materializarse y rechazo host post-hook contrastado con args
originales. Se corrigen sin abrir productor10 ni recovery: admisión y certificado
global exigen contexto realmente ejecutable; final unknown rechaza conservando
wrapping/raw/child, sin final/refund inventado. El fallo malformed/schema observado
lo atesta la transición fenced desde preparing: descriptor existente, identidad/hash
original y status/retry/control canónicos; no recalcula args anteriores al hook ni
inventa binding efectivo. Hash/coherencia no prueban autenticidad de un host arbitrario.

La reserva conserva cuatro slots de6×tool_return_bytes más16384 por call y cleanup/
receipts aparte. Descuenta sólo materialización JSON demostrable de raw.result,
call.result y leaf.outcomes: tamaño JSON de cada string menos4 (null), limitado
individualmente a6×limit. El slot futuro de history y toda holgura fija permanecen;
no se descuenta crecimiento ajeno ni se reduce coeficiente/aumenta checkpoint_limit.
Cuando consume, la historia ya está dentro del tamaño real de la fila. Alternativas
descartadas: borrar evidencia para continuar, recovery implícito, rebajar reservas
sin prueba o deducir el motivo post-hook desde args originales.

Beneficio: fail-closed para contextos/incertidumbre fuera del subset, y capacidad
ya admitida utilizable para cierre acotado. Formato interno10 no publicado, sin API,
auto-upgrade ni cambio de contratos7/8/9; filas10 antes toleradas con nueva request
inexecutable o final unknown ahora rechazan. No migración reparadora de evidencia.
Oráculos realETS/CAS y roundtrip, límites JSON/retorno±1 y controles de identidad en
los tests frame10_causal_controls/frame10_closure_control; resultados y límites en
R6 implementation. Revisión independiente requerida, no aceptación del producto.

## Checkpoint interno Frame10: operaciones CAS (2026-09-29, pendiente de review)

El nuevo consumidor es **Store.transition**, no Writer ni Composition: construye
Record2/Frame10 desde create, con owner/attempt/fence/epoch y operaciones estrechas.
Admite B→D, sibling settled y dos asks, suspensión/pausa, decisiones públicas
parciales y reclaim/frontier_open. Cada ACK del test pasa encode/decode. La evidencia
de entrada es trusted/sintética; no prueba inventario de workers, quiescencia BEAM,
resolver host, SQL ni productor/VM10. Los productores y restore7/8/9 siguen intactos.

Problema demostrado: RequestData1 guarda sólo el hash del descriptor y no permite
seleccionar exactamente inputD desde args con prompt_arg no-default. RequestData2,
seleccionado sólo con contexto estructural10 interno, añade tool_descriptors con
la preimagen exacta del fingerprint existente. Mismas claves tools/descriptors,
digest verificado; delegation sólo presente cuando existe, nunca null añadido.
Descriptor1 conserva refs/prompt_arg portable. No se resuelven módulos/callbacks al
decode y el hash no concede permiso de ejecución. Se descartan inferir args.prompt,
usar child.link.input inexistente y consultar catálogos vivos desde Record.decode.
Legacy RequestData1 conserva bytes/contrato; migración direccional experimental,
sin auto-upgrade, modo público nuevo, bump ni publicación.

Raw/effect/observación y final/outcomes se confirman juntos. Child completed→raw
es una CAS; call_wrap debe confirmarse antes de call_settle, que puede atestar Y
aunque raw/child.result sea X, sin reejecutar hooks. Source/binding/raw/terminalchild
no se mutan. Recibos idempotentes nunca habilitan otra fase. Host unknown/decode/
schema usa binding null y nombre/hash originales; permission_denied preparado
conserva su proyección. Reasons se reciben en la operación de fallo, no se deducen
del error portable colapsado. Capacidad o CAS fallida conserva el baseline, no
fabrica settled/not_executed. Reservas conservadoras de cierre incluyen preimagen,
receipts y expansión de retornos; 8MiB/checkpoint_limit son techos, no capacidad
prometida. Budget mantiene su aritmética y refund sólo al confirmar pause.

**Subset, no cierre completo del mandato:** uso externo no nulo, output resolutions
(incluido retry), terminal raíz, recovery de callbacks y fatal/output_failed siguen
rechazados globalmente. Contadores host sí son exactos; ausencia de uso no equivale
a coste cero. Hooks/retention con control fatal rechazan sin falsa pausa/refund.
Los certificados de output/source anteriores siguen disponibles, no se relabelan
como operaciones aceptadas. Integrar estos pendientes y quiescencia real es requisito
antes de productor10 completo. Verificación:113 focales (14 nuevos),207 regresiones
legacy; detalle y errores históricos en R6 implementation y REPORT externo.

## Incremento interno Frame10: fuente de delegado (2026-09-29, anterior al checkpoint CAS)

El probe del journal demostró dos razones originales distintas con el mismo error
portable y distintos ToolReturn legacy. Frame10 elige explícitamente una proyección
**lossy**: hijo failed con error válido no nil produce identidad exacta del call
padre, status failed, content=error.message, usage=nil, sin payload_omitted nuevo;
control conserva retry=false y el error completo (code/details/omitted). El helper
`ToolEvidence.child_raw10/2` usa el encoder actual. El futuro productor10 y restore
deberán compartirlo, nunca combinar reason_msg(original) con message persistido.
No recupera información descartada ni ejecuta callbacks/Retention.reason.

Beneficio: bytes deterministas desde una sola fuente portable. Alternativas
descartadas: fingir reconstrucción inyectiva o introducir una segunda autoridad raw.
Success conserva output exacto; omitted success y cancelled no fabrican retornos.
El certificado SOURCE no afirma que output hijo sea el resultado final del padre:
schema/afterhooks y atestación final pertenecen a fases posteriores.

Es preparación interna para el formato10 no publicado, sin migración automática
7/8/9 ni cambios a error/1/delegación ordinaria. Su futura admisión requiere gates
de producto separados; no hay bump/publicación. Tests sintéticos verifican conversión,
links, bytes/control y ausencia de efectos/accounting ficticios, no productor/VM/CAS.
Host sólo admite aquí la variante permission_denied observada en
execute_effective_call: denied, mensaje exacto, retry=false/error=nil, pre_dispatch.
No prueba autoridad actual ni permite deducir otros errores desde su status.
Los demás caminos predispatch y los certificados de wrapper/fatal siguen pendientes.

## 1. Visión

ExAgent aspira a ser una biblioteca/framework de agentes de propósito general
para Elixir: conectar la mayoría de proveedores relevantes, crear agentes con
poca configuración, invocar tools y componer flujos desde una llamada sencilla
hasta sistemas con estado, streaming y coordinación multi-agente.

El objetivo es una base de alta calidad que pueda mantenerse y ampliarse durante
años sin rediseñar continuamente sus contratos. Ser completo no significa
incluir todas las funciones en el núcleo ni prometer que todos los proveedores
ofrecen las mismas capacidades. La complejidad adicional debe ser opt-in.

Debe ser a la vez:

- **Ergonómico como pydanticAI** — tools con schema derivado del tipo, output
  estructurado con changesets, dependencias tipadas, capabilities/hooks.
- **Robusto al operar** — supervisión, telemetría, límites de uso y ownership
  explícito de tareas y conversaciones.
- **Idiomático del BEAM** — aislamiento y coordinación mediante procesos OTP
  cuando el caso lo requiere, manteniendo la definición de agente separada de
  una ejecución o proceso concreto. Delegar como tool también es composición
  válida; la recuperación de efectos necesita contratos adicionales a OTP.

ExAgent es **agnóstico**: no asume ningún dominio. El caso motor (una partida
de D&D en Phoenix con DM + bots + humanos en tiempo real) es el banco de
pruebas, pero el diseño sirve para soporte multi-agente, pipelines de
investigación, editores colaborativos, etc.

Las aplicaciones del autor, incluida WhoamAI, son bancos de pruebas, no la
especificación de la librería. Una solución específica se queda en la aplicación
salvo que revele una necesidad general y encaje en las capas de ExAgent.

## 2. Principios

1. **Core y runtime por capas** (inspirado en Pi). `ExAgent.run/3` es one-shot
   y no exige un Server conversacional; puede utilizar tareas para tools y
   ownership. Sobre él, capas opcionales: Server → Session → Store, usando
   sólo las que el consumidor necesita.
2. **Definición distinta de proceso.** Un agente es configuración reutilizable.
   Runs, conversaciones y coordinadores pueden tener owners supervisados con
   responsabilidades distintas. Reiniciar uno no revierte ni deduplica efectos
   externos; delegación como tool y mensajería OTP son técnicas complementarias.
3. **Ergonomía pydanticAI**. Deps (DI) tipadas vía `RunContext`, `deftool` que
   deriva JSON Schema de anotaciones `::`, output estructurado vía Ecto con
   retry, capabilities como middleware, `UsageLimits`.
4. **Agnóstico y componible**. Session = "interacción con estado coordinada
   entre participantes", no "partida". Model/Store/Compaction/PubSub y policies
   tienen contratos intercambiables; Tool agrupa schema y callable.
5. **Event-driven para tiempo real**. Cada capa emite eventos tipados (text
   deltas, tool calls, run steps, lifecycle) por PubSub. Cualquier UI
   (LiveView, CLI, channel) se suscribe. Convergencia de Pi + opencode + alloy.
6. **Sin dependencias forzadas**. DB-free por defecto (como hoy). Phoenix,
   Oban, Postgres, Redis son adaptadores opt-in, nunca requeridos.

### 2.1. Política de evolución y compatibilidad

**Dirección acordada con el autor el 2026-09-05:** construir ahora una base muy
sólida para poder ser más consistente después. La compatibilidad es una
preferencia de diseño importante, no una prohibición absoluta de mejorar un
contrato defectuoso.

Las aplicaciones conocidas del autor todavía no están en producción, lo que
permite afrontar ahora correcciones estructurales con menor coste de migración.
Eso no permite asumir que ningún consumidor externo de Hex dependa del contrato
publicado. Las versiones 1.x ya publicadas siguen sujetas a SemVer.

- **Preservar por defecto.** Preferir cambios internos o aditivos que resuelvan
  bien el problema sin alterar contratos válidos. No renombrar firmas, opciones
  o resultados por gusto, ni reorganizar capas sin un beneficio concreto.
- **Corregir la base cuando compense.** Aceptar cambios incompatibles si eliminan
  inconsistencias, problemas de seguridad, costes operativos o limitaciones
  generales que una solución compatible mantendría o agravaría. Una arquitectura
  más simple y coherente puede justificar una migración puntual.
- **No añadir deuda de compatibilidad sin necesidad.** Un alias, adaptador o modo
  anterior puede facilitar una migración real; debe tener alcance y criterio de
  retirada. No duplicar permanentemente dos semánticas solo por evitar reconocer
  una ruptura, ni eliminar compatibilidad barata y útil por principio.
- **Diseñar para extensiones previsibles, no hipotéticas.** Nuevos proveedores,
  tools o stores deben encajar mediante contratos pequeños y explícitos.
  No convertir cada diferencia de proveedor en una condición del loop central
  ni introducir un framework dentro del framework para usos sin evidencia.
- **Reconocer todos los contratos observables.** Compatibilidad incluye firmas,
  defaults, resultados y errores, esquemas JSON, eventos y su orden, historial,
  snapshots y semántica de cancelación, reintentos y uso. Mantener la aridad no
  basta para considerar un cambio compatible.
- **Comunicar y versionar.** Documentar impacto y migración antes de publicar;
  usar deprecación gradual cuando sea práctica y una major cuando cambie un
  contrato estable de forma incompatible. No publicar cambios estructurales
  silenciosamente como patch ni usar la fase temprana como excepción a SemVer.

### 2.2. Qué justifica un cambio de contrato

Antes de implementar una ruptura, dejar una decisión breve en este documento
con estos puntos; trasladar la migración y el impacto publicado al changelog:

1. **Problema demostrado:** caso reproducible, inconsistencia o limitación
   concreta. Separar lo observado de una hipótesis sobre rendimiento o uso.
2. **Beneficio general:** qué mejora para ExAgent y sus consumidores, no solo
   para la aplicación que motivó el cambio.
3. **Alternativas:** por qué una corrección interna, extensión compatible o
   adaptador no resuelve suficientemente el problema; coste de mantenerlo.
4. **Impacto y migración:** qué contratos cambian, qué consumidores conocidos
   los usan y qué deben hacer. Considerar datos persistidos y efectos externos.
5. **Evidencia:** regresión del problema, tests de contrato y escenarios de
   integración. Si cambia un adaptador, comprobar su backend real cuando sea
   necesario y registrar lo que no se haya podido verificar.
6. **Salida estable:** versión prevista, documentación y criterio para considerar
   cerrado el cambio. Evitar encadenar rupturas pequeñas del mismo concepto
   por no haber revisado antes sus relaciones con las demás capas.

No hace falta una propuesta extensa para cada bugfix. La profundidad de la
justificación y la verificación debe ser proporcional al impacto del cambio.

### 2.3. Base sólida antes de estabilizar

La fase actual prioriza consolidar lo existente antes de multiplicar funciones.
Estos son criterios de cierre, no garantías que ya se hayan demostrado:

- **Contratos coherentes entre capas:** mensajes, outputs, llamadas y resultados
  de tools, errores, uso, eventos e historial tienen significado explícito y
  no cambian accidentalmente al pasar del core al Server o a una Session.
- **Integración de proveedores extensible y honesta:** contrato común pequeño,
  capacidades y restricciones documentadas por backend. Distinguir soporte de
  texto, tools, streaming y salida estructurada; rechazar o explicar una
  capacidad no soportada, nunca degradarla en silencio. Compartir adaptadores
  compatibles donde tenga sentido sin ocultar particularidades necesarias.
- **Tools fiables:** argumentos y resultados validados, identidad de llamadas
  coherente, errores y permisos explícitos, cancelación y reintentos definidos.
  Un fallo no debe repetir silenciosamente un efecto externo; la app sigue
  siendo responsable de la idempotencia y seguridad de sus propias tools.
- **Operación acotada:** propiedad de tareas, cleanup, backpressure, límites de
  contexto/uso y observabilidad comprobados. Medir memoria, concurrencia y
  latencia en escenarios representativos antes de prometer eficiencia.
- **Ergonomía validada:** ejemplos mínimos ejecutables para crear un agente,
  cambiar de proveedor y llamar tools, además de escenarios con estado. Probar
  consumidores de distintos dominios para no diseñar únicamente para un juego.
- **Evolución verificable:** matriz de pruebas offline y de proveedores reales,
  migración de aplicaciones conocidas revisada, cambios de snapshots/eventos
  versionados cuando corresponda, documentación que distingue soporte probado,
  limitaciones y objetivos futuros.

Al cerrar esta consolidación, los contratos públicos revisados pasan a ser una
base estable. Las mejoras posteriores deben preferir extensiones y adaptadores,
con deprecaciones planificadas cuando hagan falta. Estabilizar no significa
congelar el producto ni prometer que nunca habrá otra major: significa reducir
las rupturas estructurales a decisiones excepcionales y bien justificadas.

### 2.4. Investigación de consolidación (2026-09-08)

La revisión de implementación, frameworks/harnesses y observabilidad está en
[la investigación archivada](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/research.md).
Distingue evidencia local, fuentes externas,
limitaciones y propuestas pendientes de decisión con el autor; no introduce
contratos nuevos ni autoriza una reescritura o migración de consumidores.

Puntos a resolver antes de estabilizar: paridad del loop entre sync/stream,
validación y autoridad de tools, uso y efectos parciales, alcance de presupuestos
y permisos en delegación, recuperación y observabilidad desacoplada. La
instrumentación neutral OpenTelemetry se implementó y verificó posteriormente
en C6 (8.6–8.7). Langfuse/Opik como destinos de referencia todavía requieren
aceptación práctica; no hay una plataforma elegida.

Las afirmaciones históricas de este documento sobre proceso por agente,
superioridad frente a Python/TS y equivalencia entre snapshots y durabilidad no
deben interpretarse como garantías verificadas. La investigación propone separar
definición, ejecución, conversación y coordinación, y distinguir recuperación de
estado de reanudación segura de efectos externos. El mapa usa históricamente
`Provider`, pero el behaviour publicado actual se llama `ExAgent.Model`.

El autor ha pedido concretar el plan antes de implementar. El orden operativo,
dependencias y criterios de cierre están en
[el plan histórico de consolidación](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/action-plan.md)
(2026-09-09). Preparar este plan no fija
nuevas firmas, el destino de observabilidad ni el alcance final de reanudación;
esas decisiones se resuelven en las unidades indicadas.

Preferencia del autor aclarada el 2026-09-09: priorizar funciones sin licencia
comercial a calidad comparable; aceptar funciones avanzadas comerciales si una
mejora relevante de observabilidad lo justifica. La selección final exige la
prueba de C6; esta preferencia no autoriza compras ni fija un backend obligatorio.

## 3. De qué nos inspiramos (comparativa)

| Fuente | Qué tomamos de ella |
|---|---|
| **pydanticAI** | Estructura del `Agent` (instructions/tools/output/deps/model/settings/capabilities), `RunContext[deps]`, `UsageLimits`, delegación con usage compartido, taxonomía de los 5 niveles de complejidad, `agent.iter()` (iterar el grafo nodo a nodo). |
| **alloy** | Agente como GenServer supervisado, async dispatch vía PubSub, **context compaction** summary-based, **cost guard** (`max_budget_cents`), **prompt caching**, memory primitive como behaviour, telemetría por capa, `until_tool` para output estructurado. |
| **normandy** | Coordinación multi-agente reactiva (`race`/`all`/`some`), **sesiones distribuidas en tiers**, guardrails (admission control), MCP/A2A, circuit breakers, batch. |
| **Pi Agent** | **Separación de capas** (ai / agent-core / AgentSession / SessionManager / Runtime), `AgentState` explícito, **eventos** (`subscribe`), **árbol de sesiones** con branching/fork/clone, steer/followUp mid-stream, ResourceLoader. |
| **opencode** | **Primary vs subagents**, **permissions** `allow`/`ask`/`deny` con globs (human-in-the-loop), config de agente (mode/steps/task-permissions), **sesiones como árbol** (revert/unrevert), patrón server+SDK+SSE, compaction como agente oculto del sistema. |
| **Anthropic SDK / tool-use** | Loop canónico (tool_use → ejecutas → tool_result → repite; `stop_reason`), `strict:true`, distinción client/server tools. Tu `run/3` ya lo implementa. |

## 4. Mapa de módulos

```
ExAgent (lib)
│
├── Núcleo funcional — EXISTE
│   ├── ExAgent.run/3 · run!/2 · run_stream/3        one-shot: model ⇄ tools
│   ├── ExAgent.RunContext[deps]                     DI + usage + messages + tool info
│   ├── ExAgent.Tool · ExAgent.Tools (deftool)       JSON schema derivado del tipo ::
│   ├── ExAgent.Schema · OutputSchema                Ecto → JSON schema + validate + retry
│   ├── ExAgent.Message · Part                       request/response/usage, serializable
│   ├── ExAgent.ModelSettings · UsageLimits          temperature; límites tokens/requests/tool_calls
│   └── ExAgent.Capability · Capabilities            middleware componible (hooks before/after)
│
├── Layer 1 — Agente con estado — NUEVO
│   └── ExAgent.Server          GenServer supervisado
│         · chat/3 · stream/3 · send_message/3 (async → evento)
│         · AgentState: agent + history + usage + model + status + pending
│         · emite eventos (text_delta · tool_call_finished · run_finished)
│         · steer/2 · abort/1   (cancelar o encolar follow-up)
│
├── Layer 2 — Sesión / Coordinación — NUEVO (agnóstico)
│   ├── ExAgent.Session         GenServer
│   │     · lifecycle: new/join/leave/start/turn/pause/resume/close
│   │     · participantes: humanos + pids de ExAgent.Server (vía Registry)
│   │     · turn policy (behaviour): round_robin · initiative · supervisor · custom
│   │     · shared_state: struct app-defined (Ecto) — "el mundo"; tools acceden vía deps
│   │     · broadcasts SessionEvents por PubSub
│   └── ExAgent.Coordination
│         · delegation_tool  (pydanticAI: agent-as-tool, usage compartido)
│         · handoff          (trivial: mensaje entre procesos)
│         · (futuro) race/all/some
│
└── Cross-cutting — behaviours / adaptadores
    ├── ExAgent.Store           behaviour  ·  snapshots · ETS (dev) → Postgres (prod)
    ├── ExAgent.Model           behaviour  ·  ReqLLM stock | Test | custom
    ├── ExAgent.PubSub          behaviour  ·  None | Local Registry | Phoenix.PubSub | custom
    ├── ExAgent.Compaction      behaviour  ·  summary-based; se engancha como capability
    ├── ExAgent.Permissions     (futuro)   ·  allow/ask/deny + approval human-in-the-loop
    └── ExAgent.Telemetry       EXISTE     ·  eventos en todas las capas
```

## 5. Los 5 niveles de complejidad (pydanticAI) y cómo los cubre ExAgent

ExAgent debe servir para cada nivel sin que el superior contamine al inferior:

| Nivel | pydanticAI | ExAgent |
|---|---|---|
| 1. Agente único | `Agent.run()` | `ExAgent.run/3` (one-shot, sin procesos) |
| 2. Delegación (agent-as-tool) | tool que llama a otro agent, `usage` compartido | `ExAgent.Coordination.delegation_tool/2` |
| 3. Hand-off programático | código de app encadena agents | app code entre `ExAgent.Server` (procesos) |
| 4. Graph / FSM de control | `pydantic-graph` (lib aparte) | `ExAgent.Session` + `TurnPolicy` (FSM sobre participantes) |
| 5. Deep agents | planning + files + delegation + sandbox + durable | Session + compaction + delegation + approval + Store durable |

Estos niveles no fuerzan una forma de ejecución. La mensajería y supervisión OTP
facilitan ownership e aislamiento en Elixir; otros lenguajes también ofrecen
procesos y runtimes durables. Session/Store no sustituyen un motor de replay de
efectos, y agent-as-tool puede usar tareas supervisadas perfectamente válidas.

## 6. Modelo de eventos (convergencia Pi + opencode + alloy)

Regla central: **eventos y telemetry no son lo mismo**.

- `ExAgent.Event` es el contrato de UI/runtime. Lo consumen LiveView, CLI,
  Channels, logs de producto, tests de flujos y cualquier proceso interesado.
- `:telemetry` sigue siendo observabilidad técnica. Lo consumen métricas, OTel,
  dashboards y alertas. Puede emitirse en paralelo, pero no sustituye al evento.

Un evento es un envelope versionado y serializable:

```elixir
%ExAgent.Event{
  version: 1,
  id: "evt_...",
  seq: 12,
  type: :tool_call_finished,
  source: :run,
  occurred_at: ~U[...],
  run_id: "run_...",
  request_id: "req_...",
  agent_id: "agent_...",
  session_id: nil,
  participant_id: nil,
  payload: %{},
  metadata: %{}
}
```

Terminología fija:

- **run**: una invocación completa del loop (`ExAgent.run/3`) para un prompt,
  incluyendo retries y tool calls hasta producir output final o error.
- **run step**: una request al modelo + su response + el batch de tools que esa
  response dispare.
- **session turn**: turno de un participante dentro de `ExAgent.Session`. No se
  usa `turn` para pasos internos del loop, para no mezclarlo con D&D/soporte.

Eventos previstos:

```
:run_started · :run_finished · :run_failed
:run_step_started · :run_step_finished
:message_created
:text_delta · :thinking_delta
:tool_call_started · :tool_call_finished
:usage_updated
:server_request_queued · :server_request_cancelled
:approval_requested
:compaction_started · :compaction_finished
:session_started · :participant_joined · :participant_left
:session_turn_changed · :shared_state_updated · :session_closed
```

Transporte: `ExAgent.PubSub` es un behaviour pequeño, no una dependencia.

- `:none` / `ExAgent.PubSub.None`: default sin side-effects.
- `ExAgent.PubSub.Local`: PubSub local con `Registry` de claves duplicadas.
- `ExAgent.PubSub.Phoenix`: adaptador opcional que llama a `Phoenix.PubSub`
  dinámicamente si la app lo tiene instalado.
- `custom`: cualquier módulo que implemente `broadcast/3` y, si aplica,
  `subscribe/2`.

Los mensajes publicados usan la forma `{:exagent_event, %ExAgent.Event{}}`.
Topics recomendados: `"exagent:agent:<agent_id>"` y
`"exagent:session:<session_id>"`.

## 7. Cómo encajan dominios concretos (demuestra agnosticidad)

- **D&D (caso motor).** DM = `ExAgent.Server` con tools de DM; bots = `Server`
  con tools de jugador; la partida = `Session` (initiative order = TurnPolicy,
  mundo = `shared_state` Ecto). La `Session` es el único writer del mundo; los
  tools reciben en `deps` un servicio/ref de sesión y piden cambios mediante la
  API de la Session. Humanos = LiveView publicando acciones a la Session; tiempo
  real vía PubSub.
- **Soporte multi-agente.** Supervisor = `Session` con TurnPolicy
  supervisor-driven; especialistas = `Server`; handoff = delegación; guardrails
  = capabilities.
- **Pipeline de investigación.** `Session` lineal/ramificada; cada paso un
  `Server`; compaction entre pasos; resultado estructurado (Ecto).
- **Chat asistido simple.** Solo nivel 1: `ExAgent.run/3` + tu propio store.
  No pagas la complejidad de Session.

## 8. Decisiones de diseño clave (con rationale)

### Corrección G3 de ACK de borrado Postgres — 2026-09-27

El probe real G3 sobre la fuente3108b3b demostró `transition(delete)` exitoso con
`record: nil` aunque RLS conservaba la fila; el control independiente con trigger
`BEFORE DELETE RETURN NULL` observa la misma frontera. El adapter ignoraba el
resultado efectivo de DELETE. Para confirmar la eliminación exige ahora
`DELETE ... RETURNING key` con exactamente la clave física esperada, siguiendo el
patrón de UPDATE existente. Cero filas devuelve `{:error, :conflict}` y provoca
rollback; los errores SQL originales se conservan. No se identifica la causa como
RLS porque cero filas también puede proceder de un trigger.

El beneficio general es que un ACK no afirma una eliminación inexistente.
Alternativas descartadas: aceptar cualquier respuesta SQL exitosa mantiene el
defecto; releer o modificar políticas añade IO o altera autoridad sin necesidad.
No cambia Store, schema, codecs ni política de retención. El consumidor debe tratar
conflict como fallo de persistencia y resolver su configuración/estado, sin asumir
borrado ni reintentar efectos. Ausencia previa sigue `:not_found`; replay válido de
receipt sigue sin escribir. No se inventa idempotencia después de borrar evidencia.

Regresión pública Repo scripted: rojo10/12 (falso ACK y SQL sin RETURNING), después
41/41 en SQL/Store/cleanup/retention, seed37556. Recepción coordinada posterior
`msg_8249d33f7914`: worker G3 importó únicamente Postgres4b89 y revalidó los probes
EXACTOS RLS456aff0b y trigger/controls ef48bbd9, rojo exit2→verde exit0; la fila
bloqueada permanece con error y el control positivo borra. Primitivos8 y C7runtime3
también verdes según ese reporte. Informe G3 completo y review independiente del
delta/C7 siguen pendientes; esta recepción limitada no declara G3 total aceptado.
Recepción final posterior `msg_12a78ba009d5`: G3 acepta el fix y el perfil real
PostgreSQL17.11 READ COMMITTED; informe identificado y cleanup en
`../archive/2026-09-27-external-gates-receipt.md`. No es aceptación C7 independiente
ni de todo despliegue SQL. Corrección del contrato experimental de la futura major,
sin bump/publicación aquí.

- **Alloy/Normandy son referencias, no dependencias runtime por defecto.** Se
  toman sus técnicas (event envelopes, backpressure, compaction, stores por
  tiers, circuit breakers), pero ExAgent no debe wrappear otro framework salvo
  que un adaptador opt-in lo justifique.
- **DB-free, behaviours everywhere.** El framework no posee DB ni cola. Store,
  PubSub, Compaction son behaviours. Evita acoplar a Postgres/Oban/Phoenix
  (lección de alloy y del README actual).
- **Server = conversación con estado; Session = coordinación.** `ExAgent.Server`
  conserva history/usage/model y ejecuta runs. No decide turnos entre
  participantes ni conoce `shared_state`. Eso pertenece a `ExAgent.Session`.
- **Session = FSM sobre participantes.** No es "una partida"; es una máquina de
  estados genérica coordinando N participantes con una política de turnos. Un
  `TurnPolicy` behaviour permite round-robin, initiative, supervisor, o custom.
- **Session es single-writer del `shared_state`.** Los tools nunca mutan el
  mundo directamente. Reciben deps de dominio que llaman a la Session, que
  serializa la actualización, emite `:shared_state_updated` y mantiene invariantes.
- **Coordinación por composición.** Mensajería entre owners y delegación como
  tool cubren necesidades distintas. Elegirlas por el flujo y sus garantías,
  sin mantener la delegación como una API de segunda categoría.
- **Eventos como contrato de UI.** Phoenix no es requerido: el contrato son
  eventos tipados sobre PubSub. LiveView es un adaptador más.
- **Store persiste snapshots, no procesos vivos.** No se incluye el modelo vivo,
  pids ni closures de tools. Se persisten ids, history, usage, metadata y datos
  rehidratables con una plantilla confiable. JSON rechaza valores opacos, pero
  no detecta ni redacta secretos que la app haya introducido como strings.
- **Backpressure antes que magia.** `send_message/3` debe devolver `:busy` o
  `:queue_full` de forma explícita. Las colas infinitas son un bug de producto.
- **El run pertenece al Server.** Un guardián por ejecución monitoriza al dueño
  y al worker; al morir el Server cancela el run incluso ante `:kill`, y termina
  al completar, abortar o fallar el worker. La cancelación es asíncrona y no
  revierte efectos externos ni alcanza procesos desligados creados por la app.
  Los permisos, aprobación y estimador de coste se conservan también en cola;
  el Server sigue controlando los identificadores internos y el canal de eventos.
- **Un único contrato de schema basado en Ecto.** Se prioriza la mantenibilidad
  a largo plazo frente a conservar dos ramas para una discrepancia entre el
  schema generado y su changeset. `OutputSchema.json_schema/1` conserva su firma
  original; no se añaden modos, opciones ni campos al agente. Los requeridos
  declarados se respetan incluso vacíos. Los opcionales admiten nulo sin debilitar
  las restricciones reflejadas; `embeds_many` sigue siendo array, nunca nulo.
  Los campos requeridos no admiten nulo, pero sus embeds pueden contener campos
  opcionales: la misma regla se aplica recursivamente a todos los niveles.
  Sin changeset se conserva el fallback que requiere todos los campos. La
  reflexión carga el módulo antes de comprobar sus callbacks para no confundir
  un módulo aún no cargado con uno sin changeset.
- **Cambio observable exige major y migración explícita.** Conservar las firmas
  y resultados no vuelve compatible el nuevo JSON Schema de `final_result`.
  La próxima publicación que lo incluya requiere una major posterior a 1.x;
  este trabajo no cambia versión ni publica. Los consumidores deben declarar
  campos obligatorios mediante `validate_required/2` (embeds con
  `cast_embed/3` y `required: true`), revisar supuestos de presencia/nulos y
  snapshots, y probar el soporte de `anyOf` y las restricciones strict del
  backend real. Los tests offline solo comprueban el payload emitido. La
  reflexión sobre atributos vacíos no representa perfectamente validaciones
  custom o condicionales: el changeset real sigue siendo la autoridad final,
  con los mismos resultados de validación y mecanismo de reintentos.
- **Correcciones de contratos existentes, no nuevos defaults.** El reenvío de
  permisos, aprobación y estimador del Server corrige opciones ya soportadas por
  el run; la cancelación del worker restaura su pertenencia al Server. OpenAIChat
  reenvía el `extra` ya existente para opciones de proveedor (razonamiento o
  selección de herramienta), pero reserva modelo, mensajes, herramientas y modo
  de streaming; los ajustes tipados explícitos prevalecen. Omitir esas opciones
  o dejar `extra` vacío conserva los defaults previos. Las opciones suministradas
  dejan de ignorarse; los runs huérfanos dejan de continuar en segundo plano.
- **Sin motor de graphs genérico al inicio.** La Session + TurnPolicy cubre el
  caso de uso sin la complejidad de un `pydantic-graph` completo. Se evaluará
  si un dominio lo justifica.
- **Conformidad explícita por provider.** Validación local y restricciones strict
  del backend son contratos distintos. No anunciar strict por defecto ni forzar
  tool_choice sin que el adapter lo implemente y su aceptación esté verificada.

### 8.1. C2.1: admisión de tools ante permisos inválidos (2026-09-09)

Primera corrección acotada durante C0, antes de la revisión transversal completa
de C1. Se aplica la excepción del plan para defectos urgentes reproducidos.

- **Problema demostrado:** `new!(default: :approve)` acepta una acción que no
  pertenece a `:allow | :ask | :deny`. `resolve/3` la conserva y el loop solo
  bloquea `:deny`, por lo que ejecuta la tool. Un typo en `:default`/`:rules` se
  ignora y un callback `:approve` no invocable deja pasar `:ask`. El probe de C0
  registró un efecto con acción inválida; las nuevas regresiones dieron 8 fallos.
- **Beneficio general:** una configuración inválida no amplía accidentalmente la
  autoridad de una herramienta, tanto en one-shot como mediante Server.
- **Decisión:** `Permissions.new!/1` valida opciones, forma de reglas y acciones;
  rechaza entradas inválidas con `ArgumentError`. `decide/2` convierte una acción
  seleccionada desconocida en `:deny`; `resolve/3` solo autoriza `:allow` o un
  callback de aridad 1 que devuelve exactamente `:approve`. El loop requiere
  autorización positiva `:allow`, no solamente ausencia de `:deny`.
- **Alternativas:** validar solo el constructor deja expuestos structs públicos
  construidos/modificados directamente; corregir solo el loop oculta typos de
  configuración. Cambiar el default válido a `:deny` ampliaría la ruptura a todos
  los consumidores y no es necesario para este defecto.
- **Impacto/migración:** las configuraciones válidas conservan defaults, orden y
  globs; sin permisos se mantiene `:allow`. Corregir nombres de opciones y usar
  acciones átomo válidas. `:approve` es un retorno del callback, nunca una acción
  de regla/default. Las entradas inválidas antes aceptadas o fallidas con otra
  excepción ahora se rechazan/deniegan explícitamente. No cambia la forma del
  resultado de un run, sus eventos o snapshots; no se añade modo de compatibilidad.
- **Verificación:** nueve tests nuevos, incluidos constructor/resolución y contador
  de efectos en core/Server. Suite offline: 319 correctos, 28 excluidos; compilación
  forzada de 52 archivos con warnings como errores correcta. El probe pasa de un
  efecto a cero. No se atribuye a esta corrección la
  herencia de autoridad de delegados, la paridad de streaming ni un sandbox.
- **Salida estable:** C2.1 cerrada con sus regresiones; C1 y el resto de C2 siguen
  abiertos. Se registra como corrección de entradas fuera del contrato tipado,
  sin alterar defaults válidos. El paquete conjunto sigue requiriendo una major
  por los cambios de schema ya documentados; esta unidad no cambia la versión.

### 8.2. C1/C2: validación local de schemas de tools (2026-09-09)

El autor delega las decisiones técnicas y la implementación al coordinador de
Orca; los contratos se documentan y revisan independientemente antes del cierre.
Decisión implementada y comprobada en el primer gate offline; el cierre final y
sus límites se registran en ROADMAP:

- **Problema:** C0 demuestra que un argumento `"bad"` ejecuta una tool cuyo schema
  exige un entero. Publicar el schema al proveedor no valida el efecto local.
- **Decisión:** usar JSV 0.22.x como validador JSON Schema, detrás de helpers de
  `ExAgent.Tool`, sin exponer sus errores o structs como contrato público. Compilar
  una vez y reutilizar el validador cuando no cambie el schema; rechazar schemas
  inválidos antes de invocar tools. El core conectará la preparación al comienzo
  del run, antes de solicitudes al modelo, y la validación a cada invocación.
- **Entrada:** aceptar keys de mapa átomo/binario de las APIs existentes, comparar
  su representación JSON sin colisiones y conservar los argumentos originales
  para la closure. No convertir strings numéricos, crear átomos, aplicar defaults
  ni ejecutar casts. Rechazar valores no JSON y claves ambiguas átomo/binario.
- **Frontera del schema:** usar resolvers locales/embebidos, sin HTTP/file resolver;
  impedir refs a módulos y extensiones de casting ejecutables de JSV antes de
  compilar. Esto también afecta schemas recibidos por MCP. Debe comprobarse con
  pruebas que ninguna función local es llamada durante validación de un schema
  no confiable. Un schema inseguro/incompatible se rechaza, nunca se debilita.
- **Resultado:** comprobar serialización JSON antes de incorporar un tool return;
  no agregar un segundo sistema de output schema ni exigir Ecto para cada tool.
  El output estructurado final conserva Ecto como autoridad.
- **Alternativas:** escribir un validador parcial propio crea semánticas incompletas
  y deuda de mantenimiento; confiar en el proveedor mantiene el defecto; Ecto
  exclusivamente no cubre schemas externos de MCP. JSV requiere Elixir ~> 1.15,
  compatible con el mínimo ~> 1.17 declarado aquí. Se acepta una dependencia local
  justificada; no otro runtime de agentes.
- **Impacto/migración:** argumentos antes aceptados fuera de schema y resultados
  no serializables dejan de ejecutarse/aceptarse silenciosamente. Revisar schemas,
  claves y datos en tools manuales, macros y MCP; declaraciones válidas conservan
  el callable. Este cambio observable pertenece a la major pendiente y debe tener
  una única semántica, no un flag permanente para desactivar validación.
- **Revisión y evidencia:** un spike inicial usó 0.20; se adoptó 0.22 por los fixes
  upstream de recursión/regex. Cinco hallazgos independientes se reprodujeron en
  ambas versiones y se corrigieron; 25 regresiones Tool pasaron aisladamente y
  el primer gate conjunto dio 516 tests correctos, 28 excluidos. Incluyen controles
  positivos de callbacks JSV y cero invocaciones a través de la frontera segura.
  Fuentes: [JSV](https://hexdocs.pm/jsv/0.22.0/JSV.html) y
  [resolvers](https://hexdocs.pm/jsv/0.22.0/resolvers.html).
- **Correcciones acotadas:** mediante la extensión pública de vocabularios se
  corrigen igualdad numérica recursiva de uniqueItems y longitud por puntos de
  código Unicode; los demás keywords se delegan a JSV. Retirar ese adaptador
  cuando upstream pase las mismas regresiones. Los resultados se codifican y
  decodifican como objetos ordenados para detectar JSON inválido/keys duplicadas,
  incluso en Fragment, conservando el valor original y sus encoders válidos.
- **Límites explícitos:** se admite un único dialecto efectivo draft7 o 2020-12
  por documento; mezcla de dialectos se rechaza, no se interpreta como el padre.
  El preflight de referencias es conservador entre recursos. Defaults inertes se
  omiten sólo de la proyección privada de build para evitar que JSV los escanee
  como schemas, pero los referenciados se conservan íntegros y pueden mantener
  restricciones upstream. No se cambia el schema publicado ni se aplican defaults
  a argumentos. Validar un encoder no garantiza que un encoder con estado repita
  los mismos bytes en otra llamada; callbacks locales no están en un sandbox.

### 8.3. C1: ejecución, errores y recuperación coherentes (2026-09-09)

Decisiones técnicas del coordinador bajo la autonomía delegada por el autor,
contrastadas por dos workers Astra de diseño. Implementación y aceptación se
registran aparte. El primer gate C2-C5 pasó 516 tests offline y las siete
reproducciones C0; revisión final y mediciones posteriores siguen en ROADMAP.

**Problemas y beneficio.** C0 reproduce seis gaps todavía abiertos entre tools,
streaming, delegación y persistencia. Una misma ejecución debe conservar output,
historial, estado Model y uso aunque falle o se consuma como stream. La recuperación
de conversación no debe confundirse con replay seguro de efectos externos.

1. **Definición y runtime.** `%ExAgent{}` es definición reutilizable; run es una
   ejecución; Server es owner opcional de conversación; Session coordina roster,
   policy y shared_state. Delegación como tool y procesos supervisados son
   composiciones compatibles, no una jerarquía de superioridad entre lenguajes.
2. **Error con progreso.** Mantener `{:ok, result}` / `{:error, reason}` en la
   frontera, usando `%ExAgent.RunError{reason: causa, partial: result}` para fallos
   operacionales del loop. Conservar los campos de éxito y añadir identidad/status
   y completitud de uso donde haga falta. El parcial lleva último historial/modelo
   confirmados; texto incompleto de una request queda separado, no como respuesta
   ejecutable. La causa mantiene las categorías anteriores, sin otro modo legacy.
3. **Un loop.** `run/3`, `run/3` con `stream_text: true` y `run_stream/3` comparten
   validación, hooks, límites, tools y finalización. El stream público conserva
   `{:delta, text}` y `{:result, result_completo}` en éxito; en fallo emite un único
   `{:error, RunError}`, nunca otro pseudoresultado exitoso. Deltas son provisionales
   de todas las requests; output proviene del resultado final validado.
4. **Model streaming.** Los adapters devuelven deltas y un terminal
   `{:response, response, final_model}` o error. El dispatcher difiere la llamada
   hasta consumir; ausencia de terminal es error, no éxito vacío. Todos los
   adapters propios migran juntos; los custom tienen una migración explícita.
   Un puente bajo demanda posee worker/transporte y los cancela al detenerse o
   morir el consumidor. Cada enumeración es una nueva ejecución. Suspensión sin
   halt y transporte push requieren límites explícitos, no promesas de detección
   automática de abandono ni de backpressure por usar Enumerable.
5. **Tools y efectos.** Resolver nombre/argumentos efectivos después del hook
   previo; identidad no puede mutar. Aplicar schema y permisos a esa misma tool.
   Recoger todos los outcomes del batch antes de decidir fallo y preservar cada
   resultado/uso. ToolReturn añade estado legible por máquina, incluyendo denied,
   validation_error, failed, unknown y not_executed. Validación y ModelRetry
   explícito pueden pedir corrección; una excepción/timeout de ejecución no
   provoca retry automático de un efecto incierto. Toda llamada de una respuesta
   completa obtiene resolución; la ausencia de resultado no demuestra rollback.
6. **Árbol de ejecución.** La delegación del framework comparte una admisión
   serializada de requests/tools y consumo reconciliado por identidad, con
   restricciones locales adicionales. Políticas descendientes se intersectan:
   una regla hija no elimina deny/ask del padre. `max_steps` sigue siendo local;
   los límites de request del scope abarcan el árbol. Tokens/coste son consumo
   conocido y pueden sobrepasarse por operaciones en vuelo; sin estimador no
   se puede tratar un presupuesto monetario como coste cero. No sumar dos veces
   usage del delegado. IO o llamadas fuera del scope hechas por la app no se
   contabilizan ni restringen mágicamente.
7. **Historial y contexto.** Historial autoritativo conserva eventos de conversación;
   compactación produce proyección para la request, preservando instrucciones y
   parejas call/result. `new_messages` es sufijo real. No ejecutar tool calls de
   una respuesta truncada ni reejecutarlas al restaurar el historial.
8. **ACK y Store opt-in.** Sin Store, confirmación terminal es de memoria. Con Store,
   chat/transición confirma éxito después de save `:ok` de la revisión completa;
   la admisión async sigue siendo cola volátil. Fallo save conserva estado/output
   y devuelve `%ExAgent.CheckpointError{operation, reason, result, revision}`.
   Mientras esa revisión esté sucia, nuevas mutaciones se bloquean; `checkpoint/1`
   reintenta sólo guardar, no tools/model/change_fn. Read/health siguen disponibles
   si el adapter no bloquea. Save síncrono bloqueado no se convierte en durable
   por matarlo; el timeout de IO corresponde inicialmente al adapter.
9. **Terminal runtime.** Server integra progreso de éxito/error, intenta checkpoint
   y emite un terminal propio, sin duplicar el terminal temprano del core. Preserva
   output JSON y Usage.details sin serializar el modelo vivo en PubSub. Abort vs
   resultado se resuelve por el primer mensaje decisivo del owner; late events no
   contaminan el siguiente run. Emisión única del owner vivo no garantiza entrega
   a cada suscriptor ni terminal después de su muerte.
10. **Restore y Session.** Sólo not_found permite arrancar nuevo. Snapshot inválido,
    futuro, id/policy incorrectos o error de load fallan explícitamente sin
    sobrescribir datos buenos. Escribir formato revisado y leer v1 válido mediante
    migración acotada para consumidores 1.x. Policy se reconstruye sólo desde el
    módulo confiable configurado, no elegido por bytes persistidos. Session guarda
    una transición completa por take_turn; join repetido actualiza ref/metadata
    sin duplicar roster; cambios de kind se rechazan. Paused sin actor se resuelve
    al resume; done/closed no resucitan por join. Handoff usa callback explícito
    de policy, conservando cursor; custom sin soporte devuelve error sin mutar.
11. **MCP.** Pending tiene timer y monitor del caller; response/error/timeout/death
    cierran una sola vez y limpian recursos. Timeout retorna error, no replay;
    transporte cerrado vacía pending y no vuelve ready por respuestas tardías.
    La cancelación local no afirma que el servidor remoto haya revertido el efecto.

**Alternativas descartadas:** conservar el loop textual separado, añadir un flag
permanente para resultados parciales, sumar límites después de fan-out, fusionar
globs con last-match para herencia y ocultar save fallido con ACK positivo. Tampoco
se añade un motor universal de workflows o exactly-once para resolver estos casos.

**Impacto/migración:** major conjunta para patrones de error (`error.reason` y
`error.partial`), terminal de adapters custom, semántica agentic del stream,
retries explícitos de tools, autoridad descendiente, ACK con Store y snapshots.
Los callers de checkpoint fallido deben usar `checkpoint/1`, no repetir el prompt
o change_fn; las apps siguen siendo responsables de la idempotencia externa.
Runtime y modelos vivos pueden contener credenciales y nunca se vuelcan completos
en snapshots/trazas. El lector v1 responde a datos reales 1.x y se retirará sólo
con una deprecación futura anunciada; no es un segundo modo de ejecución.

**Aceptación:** regresiones de los probes C0, paridad sync/stream, batches con
éxitos y fallos, cancelación/owner death, competencia por presupuesto, restore
inválido y Store fallido con retry de save sin repetir efectos; revisión Astra
independiente y suite offline. Provider/Store reales y comparación OTel se
verifican por separado. No cambiar versión ni publicar durante esta ejecución.

### 8.4. C3: consolidar adapters propios antes de adoptar ReqLLM

Evaluación acotada el 2026-09-09: ReqLLM proporciona streams de eventos, metadata
separada y cierre explícito mediante StreamResponse. Es una opción válida para
un adaptador futuro, pero no elimina el trabajo de traducir mensajes, uso,
errores y ownership al contrato de ExAgent.

El inventario read-only confirma un consumidor concreto: WhoamAI usa directamente
`OpenAIChat.Config`, `encode_tools/1`, `to_openai_messages/1` y `parse_body/2` dentro
de un adapter que reserva/liquida coste antes de validar output y desactiva retries
HTTP. Dragonex usa OpenRouter y el adapter OpenCode de los commits remotos.

**Decisión de este ciclo:** conservar y consolidar estos adapters y helpers
públicos, incorporar manualmente el adapter OpenCode ya existente sin bump/merge
y corregir el transporte/ensamblado streaming bajo la nueva frontera Model.
Adoptar ReqLLM ahora introduciría a la vez otro contrato de transporte, stream y
metadata sin prueba de equivalencia de esos consumidores. No se duplica un
segundo backend ReqLLM especulativo ni se declara incompatible la biblioteca:
su adopción se reabre con un adaptador estrecho y evidencia que reduzca realmente
responsabilidad propia sin perder contratos.

La comparación fue de documentación/API y consumidores, no un benchmark o una
aceptación de ReqLLM en ExAgent. La primera implementación C3 debe verificar
laziness, cancelación, consumo lento, límites en bytes y framing SSE/JSON de los
adapters actuales. Fuentes: [host integration](https://github.com/agentjido/req_llm/blob/main/guides/host-integration.md)
y [stream migration](https://github.com/agentjido/req_llm/blob/main/guides/streaming-migration.md).

### 8.5. C3: mínimos del decoder HTTP (2026-09-09)

Al cerrar documentación, Hex señaló advisories en los locks heredados de Mint
1.9.0 y HPAX 1.0.3. Son relevantes para el transporte, no una advertencia genérica:
Mint acumulaba un chunk HTTP completo antes de entregarlo al callback, haciendo
ineficaz el límite de bytes de ExAgent durante un chunk enorme sin terminar.

**Reproducción:** un servidor TCP local anuncia un chunk de 256 MiB y entrega
sólo 128 bytes. Con límite de respuesta 64 bytes, Mint 1.9.0 acaba en timeout,
no en el límite de ExAgent. No se generan grandes asignaciones para probarlo.

**Decisión:** exigir Mint >=1.10 y HPAX >=1.0.4 dentro de sus rangos 1.x, además
de Req/Finch, y actualizar esos locks. Un lock local no protege consumidores de
Hex, por lo que el mínimo debe estar en el manifiesto. Sin overrides ni fork.
Estas versiones incluyen límites/streaming de chunks y correcciones de parser
HTTP/HPACK necesarias antes del callback. Restricciones de aplicación más bajas
deben actualizarse; es parte de la major pendiente.

La dependencia Postgrex sólo de tests se actualiza a 0.22.4 para retirar los
advisories de stream/comments y Notifications del entorno de desarrollo. Esas
funciones no se usan en Store; no se afirma explotación ni se añade SQL al core.
La aceptación de Postgres real continúa pendiente.

**Verificación:** regresión TCP anterior, suite/matriz offline y construcción de
docs después del cambio. Fuentes:
[chunks](https://api.osv.dev/v1/vulns/EEF-CVE-2026-56810),
[líneas HTTP](https://api.osv.dev/v1/vulns/EEF-CVE-2026-82728),
[HPACK](https://api.osv.dev/v1/vulns/EEF-CVE-2026-58226).

### 8.6. C6: observabilidad opcional y frontera de exportación (2026-09-09)

Decisión técnica del coordinador bajo la delegación del autor. Implementación
neutral verificada offline; aceptación y límites en ROADMAP y ACTION_PLAN9.
Esta decisión no selecciona una plataforma ni certifica un backend externo.

- **Problema demostrado:** `Telemetry` conserva cuatro fronteras históricas y
  `RunEvent` es un canal explícito de estado rico. Ninguno permite por sí solo
  reconstruir spans de requests, delegaciones y checkpoints con contexto entre
  procesos. Exportar indiscriminadamente eventos/resultados expondría contenido
  y objetos runtime que pueden contener credenciales.
- **Beneficio general:** correlacionar operaciones de una app BEAM mediante OTel
  nativo, conservando el mismo core y permitiendo cambiar el transporte/destino
  sin incorporar una plataforma de observabilidad a la biblioteca.
- **Contrato aditivo elegido:** configuración `observability:` opt-in mediante
  `ExAgent.Observability.OpenTelemetry.new/1`; aplicación a definición/run y
  runtime opcional. La aplicación configura API/SDK, tracer provider, recurso y
  exporter. ExAgent no reemplaza el tracer global ni instala servicios. Contexto
  explícito efímero en límites de Tasks, GenServers y colas; siempre restaurar el
  contexto del proceso al acabar la operación. No persistir contexto en snapshots.
- **Fronteras:** un span por run/request/tool/delegación/compaction/checkpoint,
  preservando identidades existentes y lazy streams. El span de generación acaba
  antes de hooks posteriores/tools. Cancelación debe cerrar operaciones poseídas
  sin depender exclusivamente del `after` de un proceso que puede morir por kill.
  No spans por token ni uno que cubra toda la vida de un Server.
- **Uso:** `gen_ai.usage.*` corresponde a cada request, con cache cuando existe.
  Totales inclusivos del árbol quedan bajo atributos propios diferenciados; no
  volver a sumarlos como otra generación. Coste es el ya observado/reconciliado,
  sin reinvocar el estimador ni fabricar cero cuando es desconocido. Sampling no
  convierte la traza en un ledger. El perfil GenAI propio se versiona y referencia
  una revisión externa concreta, pues esas convenciones son mutables.
- **Privacidad:** contenido desactivado por defecto. El opt-in requiere redactor
  explícito fail-closed y límites previos a atributos/exportación. No volcar model,
  deps, configuración, claves, metadata arbitraria o errores crudos; emplear la
  proyección segura de categorías. No copiar baggage como atributos. El redactor
  no autoriza exportar razonamiento oculto o datos que el proveedor no devuelve.
- **Operación:** exportar fuera del run, con admisión acotada y descarte/fallo
  observable. La auditoría del SDK1.7.0 confirmó que su BSP comprueba
  `max_queue_size` periódicamente, sin cota dura ni contadores de las pérdidas
  requeridas, y no limita el tamaño de cada batch. Se implementa por ello
  `ExAgent.Observability.BoundedProcessor`, extensión opt-in del behaviour público,
  conservando tracer/exporter nativos y elección de provider en la app. La cota
  incluye spans pendientes/en vuelo; cantidad de spans no equivale a bytes de
  un exporter arbitrario. Un `force_flush` asíncrono no es ACK de recepción.
- **Alternativas:** exportar todo PubSub o hacer HTTP desde telemetry mezcla
  contratos, privacidad y latencia; fijar un SDK de Langfuse/Opik acopla el core.
  Duplicar permanentemente el runtime de tracing carece de justificación: preferir
  la API nativa y extensiones acotadas sólo para gaps comprobados.
- **Impacto/migración:** opt-in aditivo, sin nuevos defaults de ejecución ni formatos
  de snapshot. La app aporta sus dependencias/configuración de observabilidad y
  decide qué contenido redactado permite. La major pendiente por C1-C5 permanece;
  esta unidad no cambia versión ni publica. Producto/datasets/scores/prompts y la
  migración de históricos quedan separados del transporte OTLP.
- **Verificación prevista:** exporter local, árbol/IDs, error/retry/cancelación,
  tools paralelas y delegado, checkpoint confirmado/fallido, aislamiento entre
  requests, secretos sintéticos, exporter lento/caído, saturación y overhead.
  La comparación API/UI de Langfuse/Opik exige acceso autorizado y el mismo
  escenario; no se cierra ese gate con HTTP200 ni con tests offline.

Cortes auditados: API1.5.0/SDK1.7.0/exporter1.10.0 en
[`9f0511e`](https://github.com/open-telemetry/opentelemetry-erlang/tree/9f0511e705f18e4b3cc1767b42367ba49e02455a).
Perfil GenAI contra
[`b5d8440`](https://github.com/open-telemetry/semantic-conventions-genai/tree/b5d8440f6f126738fd50f927752cd669772c517b),
que usa `cache_write.input_tokens` y todavía no publica schema URL. No emitir
simultáneamente la denominación antigua para fingir compatibilidad. La omisión
de uso GenAI agregado en run es una decisión de este perfil, no una prohibición
normativa de OTel. La auditoría identificó además metadata Logger residual tras
`otel_ctx.detach`; restaurar también esas claves, preservando metadata ajena.
Los errores retornados por exporters y una respuesta OTLP exitosa no demuestran
recepción durable ni ausencia de rechazos parciales. Processors/exporters ajenos
aportados por la app conservan sus propias garantías de I/O, logging y cleanup.

### 8.7. C6: integración opcional, terminación y límites de privacidad

La primera implementación compiló 72 archivos y pasó 27 tests focales tras corregir
dos fixtures. Dos revisores Astra frescos identificaron fronteras adicionales;
sus fixes pasaron la aceptación final: 579 tests correctos y 28 excluidos en ambos
runtimes, tres consumidores limpios y el probe determinista R3. ACTION_PLAN9
conserva comandos, semillas y límites; la comparación externa permanece pendiente.

- **Compilación opcional, problema demostrado:** un consumidor temporal con API y
  SDK propios compila ExAgent antes del SDK; el processor queda permanentemente
  `sdk_unavailable` por su selección de record en compilación. Los consumidores
  sin SDK también revelaron un warning de acceso a un tuple inválido en la rama
  ausente. **Decisión:** declarar SDK opcional y `runtime: false` en todos los
  entornos, en lugar de sólo en tests, y compilar una rama ausente correcta. La
  arista garantiza el orden cuando la app aporta SDK sin imponerlo al consumidor
  básico ni arrancarlo globalmente. Forzar manualmente recompilaciones en la app
  es un workaround frágil, no la configuración pública. Verificar tres consumidores:
  sin OTel, API sola y SDK nativo, además del proyecto raíz.
- **Ownership y flush:** la reproducción aislada mostró que un exporter que
  atrapa exits conserva el worker y su ETS tras matar al manager. Es un proceso
  propio, no un hijo desligado de terceros: requiere vigilancia independiente de
  callbacks. Una barrera de scheduling en copia en memoria reprodujo la pérdida
  de flush entre selección vacía y reset del bit. Corregir esa sincronización sin
  convertir cada span/flush en otro payload ilimitado. Mantener descarte sin replay,
  capacidad en vuelo y contadores diagnósticos, no una promesa de recepción durable.
- **Terminal sintetizado:** el progreso previo a admitir una request puede decir
  completo/coste cero conocido. Al abortar o perder el worker, el Server no puede
  certificar que ese subtotal siga completo. Corregir conservadoramente el terminal
  sintetizado, preservando subtotales conocidos y sin reinvocar el estimador, para
  que retorno, Event y traza expresen la misma incertidumbre. Los parciales recibidos
  normalmente del core conservan su información confirmada. Una divergencia sólo
  en la traza ocultaría el problema a otros consumidores. Es un ajuste observable
  de completitud de la major pendiente; nunca interpretar un subtotal parcial como
  factura final ni cero consumo por falta de informe.
- **Contexto y contenido:** restaurar Logger al salir no basta si el contexto
  adjuntado está vacío: las claves propias previas también deben desaparecer
  durante el callback. Preservar metadata ajena. Los enteros arbitrariamente grandes
  no pueden consumir un presupuesto fijo de 16 bytes antes del redactor; verificar
  admisión escalar realmente acotada, con casos pequeños y controles positivos,
  sin alterar la validación de tools ni aplicar coerción.
- **Credenciales y bootstrap:** el SDK/OTP guarda los argumentos originales del
  child spec antes de entrar en el processor; puede imprimirlos en informes de
  supervisión. `format_status` propio no elimina esa copia. El contrato exige
  opciones de bootstrap no secretas y resolver credenciales dentro del exporter
  desde entorno/configuración de app. La receta OTLP usa opciones vacías y headers
  externos a `processors:`. No se introduce un filtro Logger global ni un detector
  ficticio de secretos arbitrarios; se documenta y prueba la frontera concreta.

**Migración y beneficio:** ninguna dependencia de tracing/SQL es obligatoria y no
se cambia el provider global. Las aplicaciones que opten por OTel reciben un orden
de compilación fiable y una configuración de credenciales explícita; las que
consumen cancelaciones deben respetar completitud desconocida. No cambian schemas,
historial ni snapshot version. La aceptación incluye regresiones de las fronteras,
matriz offline y ejemplos, con límites externos separados en ROADMAP/ACTION_PLAN.
El processor custom se justifica por gaps concretos del SDK 1.7; reconsiderarlo si
upstream ofrece admisión/counters/lifecycle equivalentes y pasa estas regresiones,
con migración/deprecación en vez de mantener dos implementaciones por inercia.

### 8.8. N01–N03: native OTLP acceptance and lifecycle ownership (2026-09-09)

- **Demonstrated problem:** real exporter1.10/SDK1.7/API1.5 loopback tests show
  boolean attributes converted into strings, successful `partial_success` bodies
  ignored, and native HTTP profiles retained after normal shutdown. A processor
  timeout kills its own exporter worker but does not cancel the native TCP request.
  Stopping the profile alone also leaves the active OTP29 handler/socket alive.
- **Decision/general benefit:** persist local wire/failure/lifecycle probes using
  the official protobuf codec, with explicit callback counters and ownership
  barriers. The exporter is test-only; host applications still select and own
  their transport. Qualify the HTTP recipe rather than claim cleanup or faithful
  delivery from a green HTTP status. OBSERVABILITY7 records the measured contract.
- **Alternatives:** a global before/after profile diff cannot establish ownership
  in a concurrent application. Private PID-derived names, killing shared inets,
  a vendor patch or a second OTLP client would hide ownership defects and expand
  this framework's responsibilities. A bounded disposable-VM diagnostic cancels
  observed requests before removing its own profiles, but cannot reclaim atoms
  or serve as a universal application adapter.
- **Observable impact/migration:** no new production API, snapshot or ledger
  semantics. `exported` means successful exporter callback, not remote accepted
  spans; the observed native exporter cannot report OTLP partial rejection through
  that callback. Consumers of the preview must not infer network cancellation from
  processor timeout/shutdown. General HTTP lifecycle needs upstream fixes or an
  independently accepted isolated exporter boundary. The pending major remains
  unversioned/unpublished; no new compatibility mode is introduced.
- **Verification:** four compiled isolated-VM tests pass (seed576860); initial
  integrated native gate583/28, seed280424. Seven error cases count actual model
  calls/effects and use a blocked real HTTP request as causal barrier. Three direct
  and three processor lifecycle cycles preserve unrelated/default profiles and
  distinguish native atoms/resources from seven tracked ExAgent-owned processes.
  This closes local characterization, not general native cleanup, gRPC or platform
  API/UI acceptance. Independent review and later night gates are in ACTION_PLAN10.

### 8.9. N06: optional SDK compilation on the declared minimum

The frozen-package matrix on Elixir1.17.3/OTP27.3.4.17 reproduced a compiler warning
in `BoundedProcessor.start_link/1` only when SDK records were absent. Its constant
`with` match was tolerated by newer compilers. Consumer-level warnings-as-errors
did not retrospectively reject dependency compilation, so acceptance now checks
that phase's warnings explicitly.

The initial private-helper fix passed 36 minimum-runtime consumer contracts, but
N18's clean Elixir1.20 consumer inferred that helper's constant false return and
reported another impossible `with` match. Final selection therefore happens at
compile time around `start_link/1` itself: absent SDK returns `sdk_unavailable`,
while the SDK-present branch retains the original validation/start path. Its
private validation/default helpers are compiled only where reachable, avoiding
unused-code warnings in older compilers. Loading SDK later still cannot bypass
missing compiled records. There is only one active SDK lifecycle implementation.

Suppressing diagnostics, runtime-only availability and disguising a constant to
evade compiler inference were rejected. No API/default/migration/minimum change
is needed. Isolated actual compilation has zero diagnostics on1.17 and1.20, and
the SDK-present processor passes16 tests; N18 repeats the real TAR consumer matrix
after this final change. Earlier595/28 and the initial TAR are historical gates,
not the final matrix. Detailed red/green evidence remains in ACTION_PLAN10.

### 8.10. Auditoría de testing: fidelidad de IDs en mensajes (2026-09-10)

- **Problema demostrado:** un roundtrip público `Message.to_json/from_json` pierde
  los IDs no nulos de `Part.Text` y `Part.Thinking`, aunque conserva contenido y
  firma. Las fixtures anteriores de igualdad usaban `id: nil` y no discriminaban
  esa pérdida. La reproducción sobre BEAM del baseline devuelve error con IDs
  sintéticos distintos; se trata de un defecto del codec, además del gap del test.
- **Decisión y beneficio general:** conservar esos IDs como campos opcionales en
  el codec. El lector admite datos anteriores sin ID y el escritor no añade una
  key nula a los mensajes que no lo tienen. La identidad suministrada por un
  adapter/consumidor sobrevive a la persistencia y reanudación del historial.
- **Alternativas:** rebajar «lossless» a comparar sólo longitudes/IDs nulos oculta
  pérdida de datos públicos. Un codec paralelo o una nueva versión completa de
  snapshot para un campo opcional no aporta una frontera necesaria aquí.
- **Impacto y migración:** cambia el JSON emitido sólo cuando existe ese ID;
  lectores anteriores lo ignoraban. Leer snapshots antiguos sigue produciendo
  `nil` donde no se guardó un ID; no se reconstruyen IDs perdidos. No cambia la
  omisión documentada de `ToolReturn.usage`, el modelo vivo ni snapshot v2.
  El conjunto de consolidación sigue destinado a una major; no se cambia versión
  ni se publica durante la auditoría.
- **Verificación:** reproducción negativa antes del fix; regresión con igualdad
  de conversación y JSON crudo, IDs distintos, contenido/firma y datos legacy sin
  ID. La aceptación compilada y revisión independiente se registran en
  [auditoría de testing](../development/testing-audit.md).

### 8.11. Auditoría: preservar datos antes de validar/admitir (2026-09-10)

**Problema demostrado.** La auditoría readonly encontró cuatro fronteras sin
oráculo equivalente. Reproducciones offline sobre el baseline compilado usan
adapters Req sintéticos, schema público validado por JSV/Ecto, JSON-RPC MCP local
y callbacks de delegación que consumen sus datos. Los 45 casos temporales producen
24 controles correctos y 21 fallos; son cuatro familias de defectos, no 21 bugs.

| Frontera | Observación negativa | Decisión autorizada |
|---|---|---|
| Usage de OpenAI/Anthropic | Omitir un contador o enviar usage vacío se transforma en cero, complete/known; bajo presupuesto se ejecutan una tool y una segunda request. | Conservar `nil` por dimensión no reportada, tanto omitida como explícitamente nula. Cero explícito sigue siendo conocido; el scope conserva subtotales y decide admisión con sus flags. No inferir consumo desde total/cache. |
| Reflexión OutputSchema | Enum integer/boolean se convierte en strings; exclusión deja pasar valores prohibidos, arrays reciben minLength/maxLength y `is` se omite. | Conservar tipos JSON nativos, mantener mapeo de enums átomo a string y aplicar minItems/maxItems a arrays, minLength/maxLength a strings, incluido `is`. |
| MCP → Tool | `inputSchema: false` y su alias se sustituyen por object permisivo, produciendo `tools/call`. | Seleccionar por presencia, con nombre estándar prioritario; conservar `false` para la frontera Tool que ya soporta schemas booleanos. Fallback sólo cuando faltan ambas keys; datos presentes incompatibles no se vuelven permisivos. |
| Delegación | El builder recibe contexto/args correctos, pero una key átomo válida se busca dos veces como string y el hijo recibe prompt vacío. | Buscar la key JSON equivalente ya presente, sin crear átomos ni alterar los args originales del builder; conservar rechazo previo de colisiones. |

**Beneficio general y alternativas.** La biblioteca no debe perder información
antes de las fronteras que deciden permisos, coste, output y ejecución. Modificar
los fixtures para esperar cero/strings/prompt vacío ocultaría el problema;
desactivar validación, reconstruir uso hipotético o añadir modos legacy duplicaría
semánticas incorrectas. Se corrigen los adaptadores mínimos y se conserva la
responsabilidad de JSV, Ecto y ExecutionScope.

**Impacto y migración.** Usage sin una dimensión deja de certificar consumo/coste
completo y puede bloquear operaciones posteriores bajo presupuesto. Consumidores
deben respetar `usage_status`/`cost_status`, no convertir `nil` en factura cero.
Cambian los schemas emitidos para las validaciones descritas: revisar snapshots
de payload y compatibilidad del backend real. La reflexión sigue siendo aproximada
para validaciones custom/condicionales y conteos de texto distintos de JSON Schema;
no se promete equivalencia universal con un changeset. Specs MCP incompatibles
dejan de recibir defaults permisivos; la opción `prompt_arg` sigue siendo string,
y se preserva la representación átomo/string ya admitida en argumentos.

Estas correcciones pertenecen al contrato conjunto de la major pendiente; no hay
nuevo modo, versión ni publicación. No se autorizan aquí nuevos proveedores,
aprobación persistida, sandbox ni replay de efectos.

La revisión independiente reprodujo dos aristas del primer fix: `true`/`false`
como nombres de miembros Ecto.Enum son strings publicados, distintos de un field
booleano nativo; y `is`/min/max deben intersectarse, también entre llamadas de
validación, no sobrescribirse según su orden. La corrección final consulta el tipo
Ecto del field y conserva bounds acumulados, incluidas contradicciones que deben
seguir sin admitir valores. Cinco regresiones nuevas discriminan estos casos.

**Verificación exigida.** Trasladar las reproducciones a regresiones mantenibles,
incluyendo positivos de cero explícito, schemas string/object y keys string;
comprobar sync/stream, efecto remoto local observado y datos entregados al hijo.
El control MCP de casts/refs ya rechazaba correctamente y debe conservarse.
Compilación y gates integrados con warnings-as-errors, revisión fresca y límites
se registran en [la auditoría](../development/testing-audit.md). Ninguna VM directa
contra BEAM previos sustituye la aceptación compilada de los cambios.

### 8.12. Alcance de la salida pública y consumidores (2026-09-16)

El usuario decide posponer C7 y priorizar la trayectoria/mantenibilidad de ExAgent
como paquete Hex general. Dragonex y WhoamAI se adaptarán a los contratos finales,
sin condicionar esta salida. La aprobación síncrona actual permanece; no se añade
una continuación persistida ni se interpreta un snapshot como replay.

El problema de planificación es convertir necesidades de aplicaciones particulares
o funciones futuras en condiciones indefinidas para estabilizar el framework.
La decisión mantiene fronteras pequeñas y generales: se acepta el paquete con
consumidores representativos y las integraciones reales pertinentes. Adaptar primero
las apps o añadir C7 ahora ampliaría el alcance sin un requisito de esta versión.

No cambia un contrato runtime en esta unidad ni exige migración adicional. La
consolidación sigue destinada a una major; la adaptación posterior de apps deberá
seguir la guía y demostrar su propia aceptación. Los criterios y evidencias H1–H6
se mantienen en [roadmap](../development/roadmap.md) y las capacidades incluidas
en [alcance de la versión](../development/release-scope.md).

### 8.13. Dirección propia y adopción de ReqLLM (2026-09-21)

**Contexto del usuario:** las apps actuales son pruebas de concepto y no deben
condicionar el paquete. Se busca una base reutilizable para futuras aplicaciones
Elixir, con control de evolución y contratos sólidos. El usuario solicita integrar
ReqLLM y delega la valoración técnica de alternativas; no exige poseer toda la pila.

**Problema y beneficio:** mantener codecs/transporte y ampliar proveedores propios
consume esfuerzo que puede concentrarse en ejecución, tools y recuperación.
ReqLLM1.24.0 documenta una frontera estable de una interacción, dejando loop,
aprobaciones y persistencia al host. La recomendación es continuar ExAgent sobre
esa frontera, sin dependencia del runtime Jido, con extensiones de provider cuando
hagan falta. Detalle y fuentes en [dirección del paquete](../development/framework-direction.md).

**Alternativas:** Jido/AI permite adoptar una plataforma amplia; LangChain, Nous
y Ash AI son opciones reales, con distintos compromisos. La elección propia se
justifica por la API/control buscados y la separación de responsabilidades, no por
ausencia de alternativas, superioridad universal ni coste hundido de las apps.

**Impacto previsto:** un adapter ReqLLM principal bajo Model sustituirá transporte
duplicado tras aceptación. No se mantendrán dos backends generales permanentes.
Revisar mensajes/metadatos de continuación, disponibilidad del uso, retries, límites
del stream, opciones de proveedor y ownership de spans antes de fijar la migración.
Los helpers de wire publicados que se retiren requieren migración y major; las
apps del autor no imponen conservarlos. No se cambian firmas/defaults en esta unidad.

**Verificación y salida:** H3.0 en el roadmap integra y verifica todas las rutas
pertinentes, incluidas Server/Session/delegación y consumidores del paquete. La
inspección detecta diferencia de uso ausente/cero y cotas de chunks/bytes; no hay
todavía aceptación runtime del adapter. H2/H3 reales y H4/H5 aceptarán la nueva
frontera. C7 permanece diferido; una dependencia nueva no reanuda efectos.

Esta dirección supera la retención temporal de adapters de 8.4: su razón histórica
se conserva, pero deja de ser una prohibición de adopción. No se añade dependencia,
bump o publicación en la unidad de decisión.

### 8.14. Plan v2.0.0 y C7 incluido (2026-09-21)

El usuario solicita un roadmap detallado para implementación iterativa hasta v2.0.0
y, al resolver expresamente la contradicción con el alcance anterior, **elige incluir
aprobación humana persistida y continuación acotada**. R0–R9 sustituyen H1–H6/H3.0;
el aplazamiento de C7 en8.12/8.13 es histórico y deja de regir el alcance objetivo.

- **Problema:** los snapshots y la aprobación síncrona no permiten liberar el
  proceso, reiniciar y decidir después qué tool exacta ejecutar. Composición y
  providers nuevos necesitan contratos consistentes, no promesas de producción
  derivadas de un test offline o de un catálogo.
- **Beneficio general:** biblioteca propia sobre ReqLLM, capas opt-in, control de
  efectos y ejecución pausada recuperable; consumidores mínimos de varios perfiles.
  Transiciones explícitas, ownership, historia/proyección y claims son patrones
  útiles de Jido, sin una dependencia de su runtime ni copia de todo su sistema.
- **Alternativas:** conservar C7 diferido no satisface el alcance confirmado;
  guardar un callback/proceso no ofrece continuidad portable; adoptar un workflow
  engine universal amplía responsabilidades innecesariamente. Composición acotada
  y operaciones Store atómicas permiten una frontera más pequeña.
- **Impacto previsto:** nuevas capacidades Store/CAS, datos de continuación,
  estados/eventos de pausa, autoridad sobre llamada efectiva y reconciliación de
  efectos inciertos; integración ReqLLM y migración de helpers propios. R2/R4/R5
  deben fijar firmas/schemas y migraciones con evidencia antes de implementarlos.
  Este plan no publica tales contratos ni los da por terminados.
- **Límites:** no exactly-once externo, replay arbitrario, sandbox ni scheduler
  distribuido. Providers, runtime/DB y carga se cualifican por perfiles/combinaciones.
  La app sigue aportando identidad/autorización del humano e idempotencia externa.
- **Verificación:** [matriz A1–A10/G1–G6](../development/production-acceptance.md),
  gate por subunidad, revisión fresca en fronteras críticas y candidata de bytes
  identificados. Fallos de acceso dejan gate pendiente, no pase ficticio.
- **Salida:** alcance v2 y mandato de ejecución preparados. Versión nominal1.3.0
  intacta, sin implementación ni publicación en esta unidad. R9 separa candidata
  aceptada, autorización para versionar/publicar y comprobación de Hex2.0.0.

### 8.15. R1.1: frontera host Model/ReqLLM (2026-09-21)

**Problema y beneficio:** los codecs/transporte propios duplican responsabilidad
de modelos. La frontera host V1 pública de ReqLLM permite delegar una interacción
sin ceder el loop, autoridad, aprobación, validación Ecto, límites, herramientas,
persistencia ni decisión de continuar de ExAgent. R1.1 acepta la dependencia y
esa frontera; no introduce todavía un adapter ni certifica el catálogo.

**Decisión:** incorporar `req_llm ~> 1.24.0` desde Hex (referencia estable actual
1.24.0), acotando inicialmente actualizaciones a patches. Usar `ReqLLM.model/1`
con specs explícitas, `generate_text/3` o `stream_text/3`, proyecciones públicas
de `Response`, y `Context.append_tool_exchange/3`. Los callbacks Model conservan
su contrato actual; un adapter futuro devolverá datos ExAgent y modelo final,
sin persistir structs upstream ni llamar `ReqLLM.ToolCall.execute/3`.

**Alternativas:** un segundo loop Jido o backends generales permanentes duplican
ownership; un fork amplio o parsers privados contradicen el beneficio buscado.
Model custom y Test siguen siendo extensiones válidas. Los adapters actuales se
retiran sólo tras paridad de R1.7/R1.8, no por añadir esta dependencia.

**Riesgos que la instalación no resuelve:** streaming debe abrir al consumir,
elegir una sola vista y cerrar handles incluso ante halt/owner death; el watermark
de chunks no acota bytes. La probe de API pública confirmó usage ausente, parcial
con sólo completion_tokens2 y cero explícito proyectados al mismo mapa de ceros,
tanto en `Response.usage/1` como `call_metadata/1`. El criterio original de exigir
presencia fiel o bloquear R1.5 queda sustituido por8.22: métricas orientativas
con procedencia sin inventar observación ni heurística cero=desconocido.
R1.6 debe deshabilitar o contabilizar
retries de transporte y proteger auth/opciones; ExAgent sigue decidiendo cada
invocación y efecto. La probe ya demuestra que `req_http_options: [retry: false]`
no basta: upstream sustituye ese valor; `max_retries: 0` público impide nuevas
requests en el error429 probado. Las firmas/thinking/IDs se preservan en R1.3.

**Impacto y migración:** nueva dependencia obligatoria de modelos, con grafo
transitivo que debe verificarse desde consumidor; sin Jido, SQL o SDK OTel
obligatorios. ReqLLM inicia su supervisor/Finch y carga `.env` por defecto;
hosts que administran credenciales deben configurar `config :req_llm,
load_dotenv: false` antes de arrancar (así lo hacen los tests). Sin cambio de
firmas ni selección automática del nuevo backend en esta subunidad; los floors
Mint/HPAX permanecen. Nominal1.3.0 no es autorización de publicar la major.

**Mínimo efectivo:** ReqLLM1.24.0 exige `llm_db >=2026.9.3`; tanto2026.9.3
(metadata Hex) como2026.9.4 resuelto (`mix.exs:12`) exigen Elixir `~>1.18`.
Por evidencia de grafo, el coordinador autoriza elevar ExAgent a `~>1.18`,
alinear CI/README/alcance y exigir migración de hosts1.17. Sustituye la decisión
provisional de conservar1.17 pendiente por falta del tooling; no se eleva por
warnings ni conveniencia. Bajar ReqLLM perdería la frontera host elegida;
overrides/fork o ignorar el requisito fingirían soporte. Se verifican pares
existentes1.18.4/OTP28.0 y1.20.0/OTP29.0.5, no cada patch ni OTP27; evidencia
histórica1.17 permanece con su fecha.

**Verificación R1.1:** llamada real a API pública ReqLLM con transporte
sintético, sin callback de tool ejecutado ni follow-up automático; errores y
proyecciones observables. Consumidor mínimo de bytes TAR con resolución propia,
grafos/runtimes efectivos y gates del checkout registrados en roadmap; no supone
aceptación live, R1 completo ni G5. Fuente de contrato:
[guía host V1](https://hexdocs.pm/req_llm/1.24.0/host-integration.html).

### 8.16. Follow-up R1.1: Mint HTTP/1 framing (2026-09-21)

Hex/CNA identifican CVE-2026-82672 en Mint1.10.0 del baseline: aceptar sufijos
inválidos en chunk-size puede desincronizar respuestas con origen atacante,
intermediario estricto y conexiones reutilizadas. Afecta la garantía general de
asociar datos a la request correcta, no sólo un diagnóstico del compilador.
El coordinador autorizó corregir exclusivamente Mint a1.10.1 y elevar floor a
`~>1.10 and >=1.10.1`; se conserva HPAX y el resto del lock. Alternativas de
parchear parser privado o desactivar pools globales duplicarían responsabilidad.
Migración: hosts fijados1.10.0 actualizan lock; no cambia API ExAgent. Verificación:
fixture real loopback por StreamTransport rechaza suffixes inválidos, control
positivo de extensión válida, suite offline y consumidor nuevo. Evidencia previa
a este cambio no acepta los bytes posteriores.

### 8.17. R1.2–R1.3: adapter buffered y continuación portable (2026-09-21)

**Problema:** la frontera host probada no está conectada a Model/run y los mensajes
actuales no retienen metadata de contenido/tool ni reasoning_details. Conservar
sólo texto/tool args pierde firmas/IDs necesarios en un siguiente turno.

**Decisión:** `ExAgent.Models.ReqLLM.new/1` recibe spec de catálogo o explícita,
credencial/base URL por instancia y opciones acotadas. Una `generate_text/3` por
operación con `max_retries:0`; tools upstream llevan un callback inerte, nunca el
callable ExAgent. El loop sigue validando/autorizando/ejecutando. Opciones HTTP y
provider permitidas explícitamente, reservadas rechazadas antes de IO. Streaming
se rechaza hasta R1.4, y output nativo permanece R2.3, sin falsa paridad.

**Datos:** Text/Thinking/ToolCall añaden `metadata` JSON portable; Response añade
`continuation` opcional, versión1, con provider/model/endpoint resueltos, metadata
de mensaje y reasoning_details portables. No se guarda Response/Context upstream,
provider_meta completo, config/credenciales ni callbacks. Codec conserva esos
campos y valida versión/datos; ausencia sigue leyendo históricos. Rehidratación
usa sólo structs públicos construidos por código confiable y un vocabulario fijo
de claves, nunca módulos/átomos elegidos por datos. Continuación se liga al modelo
y destino: cambiar proveedor/modelo/gateway rechaza en vez de reenviar una firma.

Imagen de entrada usa `User.content` con mapas JSON tipados `text`, `image_url`
(URL) o `image` (base64 + media_type); requiere modalidad image declarada en spec.
Vídeo/audio/files y partes desconocidas rechazan antes de IO; salida inesperada
rechaza antes de efectos de tools. Texto, thinking/signatures, tool IDs/metadata
y datos reasoning expuestos por upstream se preservan sin parsers wire propios.

**Alternativas:** persistir estructuras ReqLLM acopla snapshots a upstream;
guardar respuesta wire demanda parsers propios; desechar metadata rompe el turno
siguiente. Campos aditivos con schema propio conservan contratos existentes y
sirven a proveedores nuevos. Snapshots actuales siguen usando codec de mensajes;
downgrade a lectores anteriores puede perder estos campos y no acepta continuación.

**Limitación temporal explícita:** stock1.24.0 destruye presencia de uso, confirmado
por review fresca R1.1. Este adapter devuelve uso desconocido, nunca cero inventado;
budgets monetarios fallan cerrados. Es estado runtime temporal, no el objetivo
revisado de R1.5 en8.22 (host exacto y métricas orientativas); no se exige ya
extensión upstream para recuperar presencia perdida. No se importa el
spike ni se parsea wire privado. Identidad se toma del modelo resuelto, no de
provider inferido por un decoder con el ID sin catálogo.

**Migración/verificación:** nueva ruta opt-in mientras R1.8 conserva wrappers
existentes; retirada tras paridad, no modo dual permanente. Regresiones verticales
Model/run con ReqLLM real/transporte sintético, efectos contados, fallo sin replay,
codec/snapshot y segundo turno inspeccionado; consumidor TAR de API ExAgent.

**Resultado y bloqueo:** Chat tools/batch/Ecto e imagen declarada, firma Anthropic
tras snapshot y reasoning cifrado Responses con `store:false` pasan offline.
Stock Google pierde thoughtSignature de functionCall antes de exponer ToolCall;
por autorización expresa se rechazan temporalmente tools Google/Vertex (también
output tool) antes de IO. Se conserva prueba de pérdida stock y guard cero IO.
R1.3 quedó parcial/bloqueada;8.22 cualifica capacidades por perfil, excluyendo paths
con pérdida. Otras modalidades Google no se certifican sin su prueba.
R1.5 runtime sigue stock/unknown hasta integrar el nuevo contrato orientativo;
spike aislado todavía no es dependencia ni API aceptada.

### 8.18. Review buffered y gate R1.4: límites seguros (2026-09-21)

**Problemas demostrados:** review fresca del TAR61eaffda encontró (A1/P1)
`arguments:"[]"` convertido a `"{}"` por stock buffered con metadata vacía,
permitiendo un efecto de tool object-compatible; (A2/P1) bloque Anthropic
redacted_thinking borrado antes de exponer mensaje/continuación; (A3/P2) profile
thinking true pese a capability false. Reproducción root confirma los tres.
El decoder+builder stock pierde información; ExAgent no puede reconstruirla con
las APIs públicas actuales. Preservar sólo lo que llegó no acepta esa frontera.

**Decisión autorizada:** todas las tools y output Ecto vía tool del adapter ReqLLM
se rechazan antes de IO; también toolcalls no solicitadas e historial con calls.
No se altera custom Model, Test ni providers legacy. Anthropic con thinking
explícito, capability reasoning no explícitamente false, o historial Response se
rechaza antes de IO; thinking visible inesperado también falla. El profile sólo
declara thinking para OpenAI con capability enabled y sin supported:false.
Es guard temporal, no fix upstream ni aceptación R1.2-tools/R1.3 completa.
El alcance final revisado está en8.22, sin levantar esos guards. Se mantiene texto/imagen y reasoning-only Responses
en las rutas probadas; datos JSON/snapshot propios siguen portables.

Alternativas descartadas: parser wire privado, inspeccionar raw provider_meta
eliminado, tratar cada `{}` como inválido o aceptar datos reparados silenciosamente.
El criterio original de exigir raw público se sustituye por el gate semántico del
sobre en8.22; bloques requeridos perdidos mantienen el perfil cerrado hasta release
oficial fiel cualificada. Fork/path/patch quedan fuera del plan aprobado.
Migración temporal: usar rutas ya aceptadas para tools o esperar la frontera fiel;
las regresiones demuestran guard ceroIO/efectos y controles válidos custom/Test.

**R1.4 bloqueada en el corte2026-09-21; criterio reabierto por8.22:** loopback real por `stream_text/events/close` demuestra apertura
ansiosa upstream (envoltura lazy posible), vista única, terminal incompleto visible
y cleanup socket/metadata ante close/halt/owner kill. Pero no hay presupuesto
público de bytes predecode: frame256KiB llega intacto y frame incompleto512KiB no
se corta en la ventana2s. Watermark es de chunks, no bytes, y los kwargs documentados
finch_name/high_watermark/metadata_timeout fallan validación provider stock. No se
integra streaming ni otro transporte/SSE/fork; `request_stream` sigue unsupported.
Medición acotada, no afirmación de memoria infinita ni auditoría de todo upstream.
Un evento finish con razón incomplete y tool_call inválida no permite efectos.

**Verificación:** reproducción roja/verde de guards, suite offline nueva,
consumidor de bytes nuevo textual+guard/custom y probe streaming acotada. R1.6
opciones/settings textuales continúa siendo trabajo independiente; R1.7/R1.8
no podían cerrar paridad bajo aquel criterio. La salida vigente es R1.2 gate del
sobre y contratos operativos/de uso/perfiles de8.22, todavía sin pases nuevos.

### 8.19. R1.6 textual: precedencia y fuente de instrucciones (2026-09-21)

**Problemas reproducidos:** el adapter aceptaba `http_options.receive_timeout`
pero siempre lo sustituía por60s cuando settings.timeout era nil. Además prefijaba
params.instructions a mensajes que ya contenían esas instrucciones: duplicaba el
primer turno y podía reinsertar contenido excluido por una proyección de hooks.

**Decisión/beneficio general:** precedencia única `ModelSettings.timeout` no nil,
después default HTTP por instancia, finalmente60000ms. La opción se envía una sola
vez como receive_timeout de ReqLLM, sin duplicado en req_http_options. Sigue siendo
inactividad de transporte, no deadline total. No se introducen campos nuevos ni
se cambia semántica de ModelSettings para los otros providers.

Los mensajes seleccionados por core/capabilities son la fuente de instrucciones,
como en los encoders legacy: params.instructions es metadata de definición, no
un segundo prompt que el adapter pueda insertar. Request.instructions/Part.System
explícitos del historial siguen codificándose. Alternativa fallback «si no hay
System» descartada: reinsertaría contenido que un hook retiró deliberadamente.

**Impacto/migración:** el default HTTP por instancia ahora funciona y los system
prompts no se duplican. Clientes directos de Model deben incluir instrucciones en
messages; core y Server ya lo hacen. No se restablece extra wire libre, auth por
instancia permanece protegida y guards de fidelidad intactos. Verificación: API
ReqLLM real con transporte sintético inspecciona payload/opciones, defaults,
precedencia, auth/gateway separados y cero IO para opciones inválidas; escenario
textual con hooks/compaction y checkpoint verifica que proyección no altera historia.

### 8.20. Req compatible con el transporte buffered real (2026-09-21)

R1.6 loopback real demostró que ReqLLM1.24 genera `finch: [name: ..., pool_timeout: ...]`,
pero Req0.6.1 del lock pasa esa lista como nombre a Finch0.22 y falla en
Registry.lookup antes de conectar. El adapter sintético no ejercía esa frontera;
la resolución limpia anterior a Req0.7.4 tampoco aceptaba el lock raíz.

Con autorización expresa se eleva requisito a `~>0.7.4`, actualizando sólo Req y
dependencias estrictamente exigidas por resolución. API `finch: options` llegó
en0.7.0;0.7.4 es el patch concreto validado, con fixes de params/redirect posteriores.
No se afirma que sea el primer patch que soportó la API. Req0.7.4 exige Elixir1.15,
por debajo del mínimo1.18 existente; se mantienen floors Mint/HPAX.

Beneficio: funcionar por HTTP real y proteger consumidores nuevos, sin shim
privado ni doble transporte. Alternativas descartadas: mantener lock roto conocido,
recortar la lista Finch perdiendo pool_timeout, o parchear callbacks privados.
Migración: hosts fijados a Req0.6 actualizan; adapters-función de tests siguen
funcionando pero0.7 emite deprecaciones que se registran sin ocultar. No corrige
ningún gap de args/bloques/bytes/usage ni autoriza publicar ExAgent.

Verificación: loopback buffered/timeout/redirect/retry real en raíz, suite offline,
focales y consumidor nuevo. Se conservan rojos0.6.1 y diferencia de grafos.

### 8.21. Presupuesto total por instancia, separado de receive (2026-09-21)

R1.6 demostró por HTTP trickle que `ReqLLM.generate_text/3` admite un presupuesto
total50ms independiente de receive500ms (termina≈51ms), y por callback bloqueada
que puede detener su Task propia. El adapter no exponía ese control: la necesidad
concreta de acotar una operación buffered justifica `total_timeout` por instancia,
autorizado por el coordinador. Positivo en ms o nil (hereda default upstream,
normalmente infinity), sin nuevos campos globales ModelSettings ni pool knobs.

Se traduce sólo al keyword público homónimo ReqLLM; no a receive_timeout ni a una
deadline de todo el agente. Timeout total vuelve como RequestError saneado con
reason `{:timeout, :total}`, sin body/key. Invalididad, extra/reservados y valores
de otros tipos rechazan antes de IO. No promete deshacer efectos ni cancelar
descendientes arbitrarios creados por código host.

Alternativas: renombrar receive sería falso; usar sólo configuración global pierde
aislamiento por instancia; un watchdog/transport propio duplicaría ownership.
Migración aditiva: nil conserva comportamiento previo, un entero acota esa llamada.
Verificación por Model/run con HTTP real retenido, una request, cierre del socket,
error/uso desconocido y controles negativos; no afecta guards de tools/metadata.

### 8.22. ReqLLM oficial sin fork: contratos cualificados y gate del sobre (2026-09-22)

**Decisión de diseño aprobada por el coordinador bajo el encargo del usuario.**
Esta unidad es documental: no cambia guards, código, dependencias ni aceptación.
El usuario autorizó también implementación posterior, en otra Task tras revisión.
Leer el relevo no activa ese trabajo. Evidencia y fuentes versionadas en
[dirección §9](../development/framework-direction.md#9-investigación-jido-reqllm-del-2026-09-22).

**Problema demostrado.** ReqLLM stock1.24.0 transforma argumentos JSON no-objeto
en objeto vacío, borra presencia de uso y ciertos bloques de continuación, y no
ofrece cota dura de RAM/bytes antes de decode. La revisión de Jido AI2.3.0 y main
confirma que su normalización tampoco recupera esos datos; su token de continuación
no reemplaza CAS ni no-replay. Los resultados previos691/0/28 son históricos.
No se ejecutó una prueba del sobre en esta decisión.

**Beneficio y límite.** Conservar un Model mínimo y runtime propio, delegando
transporte/codecs a una **release oficial stock de ReqLLM**, permite retirar
responsabilidad duplicada sin mantener fork, vendoring, patch, monkeypatch,
parser wire privado, SSE propio ni runtime Jido. No se adopta main ni un spike.
Un perfil que necesita información perdida permanece cerrado antes de IO.

**Tools: primera hipótesis a probar en R1.2.** Anunciar para cada tool un sobre
obligatorio genérico `{"arguments": objeto_lógico}`: objeto exterior, única
propiedad `arguments` requerida y `additionalProperties:false`; dentro se conserva
el schema lógico soportado. `{"arguments":{}}` permite una tool vacía legítima;
`[]` normalizado a `{}` carece del campo y debe fallar. No es una reparación
upstream ni una promesa de fidelidad de bytes raw/duplicados que el decoder perdió:
el contrato valida el **objeto semántico recibido**. Invalidez explícita, JSON
truncado y terminal incompleto nunca se reparan a válidos. No usar defaults para
el sobre ausente, coerción ni fallback al wire previo.

La frontera valida sobre y schema lógico localmente, expone args lógicos a hooks
y revalida los efectivos antes de permisos y efecto; identidad no muta, hooks no
amplían autoridad, callbacks ReqLLM son noop y sólo ExAgent ejecuta. El sobre no
autoriza casts/defaults nuevos ni cambia Ecto como autoridad final. Un schema mapa
con `compiled:nil` en ReqLLM.Tool no equivale a validación JSON Schema local.

**Schemas e historia.** No anidar S ciegamente: `#`, `$defs`/refs relativas, `$id`,
anchors, `$dynamicRef` y refs externas pueden cambiar de raíz/resolución. Elegir
un subconjunto representable explícito, con rechazo antes de IO, o una transformación
pequeña demostrada; no construir preventivamente un rewriter JSON Schema general.
Probar required/optional/defaults, additionalProperties, boolean schemas, anidación,
arrays/enums/nulls y strict del payload efectivo, sin convertir opcionales en
obligatorios silenciosamente. Versionar proyección wire/codec y migración de
historia/snapshots; preservar orden, IDs, metadata permitida y sobre exactamente
una vez en el segundo turno. No envolver retroactivamente llamadas inválidas para
convertirlas en válidas, ni adivinar versión de historia por su forma. La política
de migración/rechazo de datos anteriores se fija antes de levantar guards.

**Uso y límites.** Separar contadores exactos HOST de requests/intentos/tools y
admisión atómica por identidad de métricas de proveedor: tokens/cache normalizados
o reportados, coste estimado y su calidad/procedencia/disponibilidad. Cero normalizado
no es cero observado; tampoco se infiere unknown por ser cero. No reconstruir
presencia inexistente ni facturación. Conservar unidades USD/céntimos, semántica
cache/reasoning, snapshots acumulativos y no doble conteo entre evento/terminal,
restore o descendientes. Falta de contabilidad no bloquea ejecución ordinaria por
sí sola cuando hay límites host; un solicitante de límite estricto dependiente de
datos ausentes recibe rechazo explícito, nunca degradación silenciosa a best-effort.
Umbrales estimados pueden frenar admisiones futuras y excederse con operaciones
en vuelo; no son saldo reservado ni techo de factura. R1.5/R3.3 fijan nombres,
errores y migración de Usage/UsageLimits/OTel antes de integración.

**Streaming.** Una vista y una interacción, lazy en la frontera ExAgent, terminal
completo válido antes de efectos, cleanup de transporte/metadata en éxito, halt,
excepción, timeout y muerte del owner. `process_stream/2` con callbacks y Response
final es candidato preferido por evitar otro materializador provider-aware; gates
pueden elegir `events/1` si ofrece mejor frontera pública. No mezclar vistas ni
reenumerar. Stock `process_stream` hace `Enum.map`: coste O(respuesta), sin hard
RAM predecode y sin promesa similar para buffered. Esa renuncia **no** elimina
deadlines, admisión/concurrencia, queues y retención propia postdecode acotadas en
chunks/bytes, máximo de salida solicitado, medición con consumidor lento ni cleanup.
Documentar historia canónica y asignaciones previas al umbral; no anunciar
backpressure end-to-end ni opciones que stock rechaza.

**Perfiles.** Mínimo inicial obligatorio: Chat-compatible sin reasoning ni features
provider-native, con tools/Ecto-tool/stream en combinación exacta modelo/endpoint/API
y configuración cualificada. Model custom, specs fuera de catálogo y gateway por
instancia conservan extensibilidad. Responses/Anthropic/Google son capacidades por
combinación probada, no cuatro familias obligatorias para cerrar R1 por catálogo.
Excluir antes de IO los paths que pierden metadata; `reasoning.enabled:false` no
prueba ausencia de bloques requeridos. No fallback silencioso de proveedor/modelo.
G2 live sigue requerido para lo anunciado, igual que G3–G6 para sus perfiles.
ReqLLM commit `3536ff94ce050cea15aaf285ad2c6bfeac6809bc` sobre Anthropic es pista
para futura release oficial, **no** fix publicado/adoptado ni aceptación Google.

**C7 intacto.** Persistir llamada lógica exacta, args efectivos, versión de
definición/codec y outcomes; claim atómico, autoridad vigente al restaurar y
no replay de pasos confirmados. Crash entre efecto y save conserva incertidumbre;
ni lease expirado ni token firmado autorizan repetir. R4/R5 no se rebajan.

**Alternativas.** Esperar releases oficiales es válido para capacidades excluidas;
exigir raw/presencia/cota dura de toda operación bloquearía el producto y ya no es
el contrato aprobado. Prohibir todas las tools que acepten `{}` pierde tools vacías
y defaults legítimos; no es la vía elegida. Copiar reparación Jido, retirar guards
sin gate, mantener fork o dos transportes generales contradice la decisión.

**Impacto y migración.** Major conjunta: envelope wire y codec/history versionados,
semántica/calidad de Usage y presupuestos explícitos, límites operativos del stream,
capacidades cualificadas y retirada del transporte/helpers duplicados en R1.8.
Los consumidores revisarán snapshots, tools/schema strict, exportación OTel,
unidades y requisitos de límites estrictos. No conservar legacy general permanente;
un puente necesita consumidor real y criterio de retirada. Los guards actuales y
el unknown/fail-closed temporal describen sólo implementación presente, no el objetivo.

**Verificación/salida.** Gate stock real + transporte sintético de R1.2 antes de
levantar guards: negativos no-objeto/truncados/sobre inválido, controles positivos
vacío/no vacío, cero/una ejecución, IDs, schema/strict, history/codec/output y
autoridad. Buffered y una vista stream; después R1.3–R1.8 y R2–R9 con A1–A10/G1–G6.
Los criterios afectados se reabren, no pasan por cambiar prosa; ver
[aceptación](../development/production-acceptance.md) y el prompt checkout-only
`docs/prompts/continue-v2-reqllm.md`. Si el gate exige fork/API privada/rewriter
general o permite un efecto inválido, parar esa opción y conservar el guard.

### 8.23. R1.2 buffered: sobre lógico versionado, subset inicial (2026-09-22)

**Unidad en implementación; revisión fresca y aceptación final pendientes.** El
gate inicial stock `generate_text`/`process_stream` discrimina argumentos inválidos
de vacío/no vacío válido con cero/una ejecución. El sobre evita que `[]`→`{}`
autorice una tool vacía; no reconstruye bytes ni claves duplicadas perdidas.

La capacidad de instancia `tool_profile: :chat_tools_v1` exige OpenAI con metadata
explícita `extra.wire.protocol: "openai_chat"`, tools enabled y reasoning disabled;
no infiere API por nombre. Strict tools true y provider options adicionales se
rechazan. Es cualificación del protocolo/configuración, no un backend legacy nuevo.
Sin perfil, el guard sigue rechazando tools. ReqLLM recibe callbacks noop,
`strict:false`, `json_repair:false` y `max_retries:0` protegidos. Stock omite el
campo wire `strict` cuando es false: se prueba esa ausencia y el schema íntegro,
modo no-strict de Chat; no se atribuye un campo false que no envía. No hay G2 live.

El helper `lib/exagent/models/req_llm_envelope.ex` transforma schemas raíz `type:object` o
booleanos, sin refs/identificadores/dialecto explícito: rechaza `$ref`, `$defs`,
`$id`, anchors/dynamic y cualquier keyword fuera del subset antes de IO. Recursión
sólo por posiciones schema conocidas, no por defaults/enum/const. Permite
properties/patternProperties/dependentSchemas, additionalProperties/items/contains/
propertyNames/not/if/then/else, anyOf/allOf/oneOf/prefixItems y constraints escalares
de tipos/rangos/longitud/items/propiedades, enum/const/required/format; anotaciones
title/description/default/examples/deprecated/readOnly/writeOnly son inertes.
JSV/Tool valida schema y datos, sin insertar defaults ni coerciones. El dominio
lógico ya exige objeto: raíz true se anuncia como type:object y false sigue false.
Ecto genera embeds inline; no necesita un rewriter de refs. Strict no se habilita
convirtiendo optional en required.

La respuesta canónica contiene args lógicos mapas y metadata
`arguments_codec: "exagent.arguments/1"`. Continuation v2 añade el mismo codec,
con target provider/model/endpoint. Proyección valida schema actual y ambos markers
antes de envolver exactamente una vez. Historia de tools sin versión, args string,
schema incompatible o markers alterados rechaza; el codec JSON sigue leyendo v1
textual, pero no migra llamadas antiguas por inferencia. Snapshots/compaction usan
el codec de mensajes y preservan los markers. Hooks ven args lógicos validados y
se revalidan efectivos antes de permisos; este perfil liga ID, nombre y metadata
de llamada, manteniendo sustitución legacy/custom previa fuera de este contrato.

Alternativas descartadas: envolver toda historia antigua legitimaría argumentos
inválidos; mover schemas con refs cambiaría raíz; un rewriter general/fork excede
la frontera. Impacto major: adoptar el perfil explícito y reiniciar o migrar fuera
de banda conversaciones con tools antiguas, conservando outcomes para no replay.
No se añade C7, stream ExAgent ni nueva contabilidad en esta unidad; uso sigue
unknown. Verificación integrada, oráculos y límites se registran en roadmap.

**Corrección de ownership autorizada tras rojo nuevo.** El gate TCP con tool JSON
completo dentro de HTTP incompleto rechazó timeout sin efectos, pero owner kill
con total_timeout finito dejó socket abierto más de1500ms. Stock TimeoutBudget
usa async_nolink con el temporizador en el caller: la muerte de éste pierde el
cancel. No se modificó upstream. El boundary buffered común del adapter ahora
usa un guardian host con monitor del caller, worker enlazado y handshake previo
a IO; deadline constante y cleanup al recibir resultado, excepción, timeout o
DOWN del caller. No accede a supervisor/PIDs privados ReqLLM. Se propaga el
contexto OTel mediante los helpers existentes y se conserva una sola interacción.
`total_timeout:nil` hereda explícitamente `Application.get_env(:req_llm,
:total_timeout,:infinity)` sin cambiar config global; un valor de instancia manda.
El backend recibe `total_timeout: :infinity` interno, y la duración la impone el
host. Es un cambio de lifecycle también para texto ReqLLM, sin afectar Model
custom/Test/legacy. No cubre procesos descendientes arbitrarios que un callback
externo cree; no añade streaming ni garantía de RAM predecode.

**P2 de revisión fresca, reproducido y corregido:** un guardian suspendido podía
aceptar un resultado terminado después del deadline porque los mensajes pendientes
ganan a `receive after 0`. El worker ahora marca tiempo monotónico al terminar
Backend/contexto y el guardian exige `completed_at < deadline`, incluso si su timer
no pudo ejecutarse a tiempo. Resultado tardío implica timeout y cero efectos;
resultado terminado a tiempo puede entregarse después si el guardian estaba
suspendido. El contrato limita finalización de la interacción, no garantiza
scheduling realtime ni una hora absoluta de entrega. La regresión fuerza ambos
órdenes y conserva reap, IDs y conteos; el presupuesto del run sigue separado.

### 8.24. R1.4: stream cualificado, ownership y retención postdecode (2026-09-22)

**Problema y beneficio.** El sobre buffered aceptado parcialmente en revisión fresca
`task_16e800274a86` permite reutilizar la misma validación al completar un stream.
ReqLLM stock1.24 ofrece `process_stream/2`, callbacks y Response final: evita un
materializador provider-aware propio y mantiene una sola vista. La integración usa
`stream_text/3` y `StreamResponse.close/1` públicos, sin parsers/transportes propios,
fork ni manipular handles privados. El guard sólo se abre para `chat_tools_v1`
(diseño8.23), con la misma historia/Envelope/traducción buffered y callbacks tool noop.

**Ownership.** Ninguna request antes de enumerar. Un guardian host monitoriza al
enumerador; productor enlazado espera handshake antes de crear y consumir backend.
Registra el StreamResponse público con ACK antes de callbacks. Si muere el caller
antes de ese registro, terminar el productor usa el lifecycle enlazado ordinario
de upstream: el gate mata owner durante un callback público de telemetry previo
al retorno de stream_text y observa cierre TCP. Durante registro se prueba metadata
DOWN, productor/guardian DOWN y socket cerrado. Después, el guardian conserva la
capacidad pública de close. No depende de un `after` ejecutado por un proceso muerto.
Usa shutdown con gracia finita100ms, luego kill y reap si el productor atrapa exits,
y close idempotente; se propaga
el contexto OTel con helpers actuales. No posee descendientes arbitrarios de callbacks.

Cada delta exige la siguiente demanda para liberar el productor. Sólo Response
completa, traducida y validada autoriza loop/tools; deltas son provisionales.
Errores de args, length/filter/incomplete/unknown/EOF/timeout/cancel no autorizan
efectos aunque el JSON tool esté completo. No se presenta un terminal exitoso por
agotar el enumerable. Halt abandona consumo; no puede entregar un evento al caller
que ya no enumera. Resultado completo se sella monotónicamente antes de entrega,
exigiendo `completed_at < deadline`, como el guardian buffered revisado.

**Perfil operativo predeclarado.** Máximo4096 chunks públicos;65.536 bytes por
chunk y1.048.576 sumados, medidos con external_size **postdecode**, no heap/RAM.
El callback aborta antes de admitir/reenviar el chunk que excede el umbral, pero
éste y frames previos pueden estar ya asignados upstream. process_stream retiene
O(respuesta); las colas y acumulador ReqLLM pueden adelantarse al callback. No se
anuncia backpressure end-to-end ni cota upstream de bytes. Por interacción propia:
una delta sin ACK (hasta el umbral de chunk) y, al vencer el plazo, un terminal de
error; materialización admitida acotada por bytes/chunks más overhead de listas,
traducción/validación y copias temporales. La Response canónica y los snapshots
contienen historia previa: el límite no borra ni acota retrospectivamente input,
historia, resultados de tools o datos que el consumidor decida conservar.

Max_tokens solicitado: fallback4096 sólo si nil; explícito fuera de1..4096 rechaza
preIO, sin clamp. Total_timeout stream nil=60.000ms; explícito1..300.000ms, límite de
este perfil, no de todo el framework. Incluye espera por consumidor lento. Buffered
mantiene nil heredado del default público (normalmente infinity); paridad se compara
con configuración efectiva igual. Receive sigue precedencia existente. HTTP adapter
inyectado se rechaza en stream porque esa opción buffered no representa su transporte.
Admisión/concurrencia agregada usa ExecutionScope existente: la app fija
max_concurrent_requests/request_limit/deadline del scope; no hay techo global nuevo
ni contabilidad de tokens/coste nueva. Una enumeración directa Model es una operación;
múltiples enumeraciones independientes requieren admisión externa si se desea límite
global. R1.5 continúa unknown, requests host exactas y retries upstream0.

**Corrección compartida demostrada.** Con guardian de RunStream suspendido, una
respuesta Test de100 palabras encolaba203 snapshots crecientes: el ACK de deltas
no acotaba esa otra cola. Ahora cada progreso exige ACK con identidad propia; el
guardian reemplaza un snapshot actual, no acumula un backlog. El worker también
queda enlazado además de monitorizado: muerte anormal del guardian no deja un worker
esperando ACK. Monitor/trap_exit conserva parciales ante fallo del worker. Cancel
no interpreta un ACK obsoleto como permiso para avanzar. notify_progress propaga la
misma cancelación reservada que emit; tras cancel no encola otro snapshot que espere
ACK del guardian ya cerrando. Esto conserva el unwind/finalizador de Model custom;
el reap forzado existente sigue acotando código que no coopera. Es una frontera común necesaria, cubierta
con Test y ReqLLM, sin otro modo legacy. Cambia timing/backpressure de progreso;
contenido, orden y terminal público siguen el contrato existente.

**Alternativas/migración/verificación.** events seguido de to_response consumiría
dos vistas; reconstruir llamadas desde eventos copiaría materialización que stock
ya provee. Callbacks sin ACK o sólo contar chunks no acotan bytes ni snapshots.
No se eligen esas alternativas. Activar perfil explícito, revisar límites y distinguir
defaults buffered/stream; consumidores sólo confirman el terminal, no deltas. No se
migran datos adicionales: codec2/envelope1 sigue igual. Tests usan JSON/SSE loopback
real, fragmentos de argumentos, positivos/negativos, herramientas/Ecto, registro,
deadlines en cola, owner/guardian death, consumidor lento y concurrencias1/8. Umbral
de observación finita productor4MiB y cleanup2s, fixture≤2MiB; no prueba OOM ni SLO.
Registro de comandos/medidas y revisión fresca pendiente en roadmap; G2 live,
R1.5, C7 y aceptación R1 completa permanecen pendientes.

### 8.25. R1.5: contabilidad cualificada y admisión retrospectiva (2026-09-25)

**Aceptada offline en dictamen fresco final R1.5 (173/173, TAR3c7867ad).** La API pública stock normaliza
ausencia/parcial/cero indistinguibles; descartar todo uso pierde métricas útiles,
pero tratarlo como reporte íntegro inventa presencia. Usage añade `accounting`
separado de details: mapa JSON allowlisted versión1 con source, quality,
availability por dimensión, provider_presence unknown, semánticas input/reasoning
y cost estimado en cents con subtotal/availability. Valores cero son válidos.
Helpers comunes en Usage, sin jerarquía ni segundo motor. No sumar versiones,
precios o flags. Model vivo sin marker es reported al host por contrato, no prueba
wire; datos persistidos sin marker son legacy_snapshot/unknown conservando valores.

Schema implementado con claves string: version1; source=model/req_llm/aggregate/
legacy_snapshot; quality=reported/normalized/mixed/unknown; provider_presence=unknown;
input_semantics=inclusive/exclusive_cache/unknown; reasoning_semantics=
included_in_output/separate/unknown; availability tiene input/output/cache_read/
cache_write/reasoning con available/unavailable/partial. cost exige cents y
subtotal_cents numérico no negativo o nil, source=req_llm/estimator/aggregate/mixed/
unknown, quality=estimated y availability. Rechaza claves desconocidas, versión
futura, available sin valor y tipos inválidos; no atomiza bytes ni vuelca metadata.
Los helpers internos quedan en Usage (`@doc false`), sin nuevo módulo público,
replace engine ni capa de wrappers. Message.new_response y el core califican
reportes vivos; la respuesta canónica incluye la estimación ya calculada del ledger,
sin invocar el callback de nuevo al serializar ni al observar.

**P2 fresco y corrección causal:** sumar todo número de details sumaba version y
price; además atom/string y cache_read_input_tokens se mantenían como dimensiones
duplicadas. La agregación de varias contribuciones conserva sólo total_tokens,
cached_tokens, cache_creation_input_tokens y reasoning_tokens no negativos enteros.
Canoniza aliases existentes (cache_read_input_tokens/cached_input,
cache_creation_tokens/cache_creation y reasoning) una vez por contribución; clave
string prevalece sobre atom y alias canónico sobre alternativos. Metadata arbitraria
se conserva por operación/historia pero se omite al agregar, incluso si coincide:
es asociativo, y un conflicto no reaparece tras tercer fold o restore. No registry
público ni maquinaria de conflictos. Migrar consumidores que sumaban detalles
arbitrarios a su propia agregación explícita. Regresiones incluyen las6 del reviewer.

UsageLimits.accounting es strict por defecto y estimated opt-in. Strict exige
reporte suficiente para el umbral retrospectivo, nunca factura ni techo externo;
stock normalized rechaza preIO cuando hay límites métricos. Custom nil/parcial
rechaza antes de efectos posteriores para las dimensiones exigidas. Estimated
requiere request_limit finito efectivo (incluidos ancestros), admite subtotales
con datos/precio ausentes y revisa en siguiente admisión; en vuelo puede exceder.
La política de un hijo nunca rebaja al padre. Ordinary host-only sigue operativo.
ModelProfile.accounting_quality (:unknown por defecto, :reported o :normalized)
declara el contrato conocido para preflight genérico; core no ramifica por proveedor.
Un límite estimated requiere bound en el scope métrico o sus ancestros, nunca se
certifica un presupuesto agregado ilimitado por sumar bounds locales de hijos.
La validación strict considera sólo dimensiones solicitadas: input reportado con
output ausente puede satisfacer input_tokens_limit, manteniendo usage_status partial.

request_count son intentos Model admitidos y tool_calls reservas/admisiones de
batch, no HTTP exacto custom, despachos, éxitos o efectos. Identidad y admisión
ancestral siguen atómicas; no nuevo ACK/despacho ni ledger durable C7. Finalized
es independiente de cobertura: terminal nil sella, acumulativo reemplaza,
duplicado idéntico es idempotente y contradicción rechaza sin recalcular precio.

estimate_cost conserva aridades/precedencia: unknown/error explícito no cae a
upstream. Sin callback, total público ReqLLM válido es estimación USD convertida
una sola vez a cents; total_cost precede cost.total, sin sumar aliases/breakdowns.
Ausencia no es factura0, no tabla propia ni preflight con uso cero inventado.
cost_status known significa estimate disponible, acompañado de quality estimated;
cost_cents nil con cobertura incompleta, subtotal preservado en accounting.cost.
Cobertura de coste es independiente de tokens: un total público válido puede
estar disponible sin contadores. Terminal nil conserva precio previo como subtotal
parcial, sin reestimarlo; duplicados conservan también el resultado de validación.
Specs con pricing por componentes deben declarar USD: moneda ausente/desconocida
o distinta no se convierte a cents. La API pública sin override de pricing usa su
contrato USD documentado; no se interpreta cost legacy como tabla propia.

Snapshot Server v3 evita borrado silencioso por lectores antiguos; lectores v1/v2
califican legacy unknown. Continuation2/envelope1 permanecen: su contrato no cambia.
Session snapshot2 no almacena Usage/history, sólo coordinación/policy: no necesita
bump. Restore no recalcula
historia ni crea operaciones nuevas. Output/eventos/Server/OTel preservan calidad;
una generación por operación, subtotales separados y etiquetas allowlisted.

Alternativas descartadas: parser wire/fork, cero=>unknown, presencia inferida,
accounting dentro de details (merge numérico destruiría version), otro runtime o
pricing engine. Migración major conjunta: revisar accounting, optar por estimated
con request_limit para stock y actualizar lectores snapshot; sin bump aquí.
Gates exigidos: transporte stock sintético buffered/TCP stream, sparse/zero/custom,
ancestros/retries/ledger, codec viejo/nuevo/corrupto, restore y OTel privado;
focales/suite offline y smoke TAR fijo, revisión fresca posterior independiente.

### 8.26. R1.8: backend único y resolución (2026-09-25)

**Decisión propuesta antes de retirar y aceptada por coordinador; implementada,
perfil mínimo aceptado en revisión fresca sobre TAR6a2eb6aa, recibida2026-09-26.** El inventario
concreto vive en `docs/archive/2026-09-25-r1-retirement.md`. Los cuatro wrappers
anteriores y cinco módulos wire permiten eludir los guards cualificados ReqLLM y
duplican ownership, parsers y contabilidad. Su coexistencia permanente contradice
8.22; retirarlos permite una sola frontera de integración mantenida y extensiones
Model públicas independientes.

`Model.resolve/1` conserva structs custom y `test`/`test:label`. Strings de catálogo,
mapas explícitos y tuplas stock pasan por `ReqLLM.model/1`; un `%LLMDB.Model{}` es
spec, no implementador Model. `resolve/2` recibe opciones de instancia del
único constructor `Models.ReqLLM.new/1` para credenciales, endpoint y perfil. No
selección automática de tools por nombre/prefijo: `tool_profile: :chat_tools_v1`
sigue explícito y la misma validación actual exige metadata/capacidades efectivas.
Un string válido no certifica tools/stream, ni habilita un proveedor no cualificado.

Credenciales explícitas por instancia; no nueva lectura automática de entorno.
La app puede usar `System.fetch_env!` al construir. `:api_key` conserva precedencia
aislada; `:auth_token` sólo para Anthropic se traduce mediante opciones
públicas stock `auth_mode: :oauth, access_token: token`, sin archivos OAuth ni
refresh implícitos. Token explícito prevalece sobre api_key como en el wrapper
previo; el gate TCP comprueba headers reales, ausencia de API key con Bearer,
ausencia de subscription, precedencia y secretos omitidos en error/Inspect/history.
No claves de entorno implícitas, archivos OAuth ni refresh.

OpenAI y Anthropic usan specs stock exactos. OpenRouter catálogo conserva provider
OpenRouter y sus guards; el gateway Chat requiere una spec OpenAI explícita con
ID exacto, base_url y metadata Chat elegidos por consumidor (sin reescritura oculta).
OpenCode Go/Zen no tiene alias stock actual: rechazo explícito con migración
a spec/endpoint/auth documentados; plan Go y Zen nunca se intercambian. ZAI sí
resuelve stock `:zai`, incluso fuera del catálogo, y ya no es alias Anthropic:
la ruptura se documenta con ruta explícita al endpoint Anthropic anterior. No se
bloquea un proveedor stock válido sólo por prefijo. Anthropic
texto inicial sin reasoning puede cualificarse; tools/stream/continuación que
pierden información permanecen cerrados. Native JSON sigue R2.3.

Alternativas descartadas: aliases permanentes sin consumidor externo demostrado,
fallback legacy, inventar metadata Chat a partir de un slug y exponer headers
arbitrarios que sobreescriban auth. Los callers propios se migran al constructor
único, sin wrappers provisionales. Es ruptura major2 conjunta, nominal1.3.0 intacta;
codec2/envelope1/continuation2/snapshot3/accounting1 y lectores legacy unknown no
cambian. Las llamadas antiguas inválidas no se legitiman al migrar transporte.

**Hallazgo P2 de review R1.8 y límite explícito.** La prosa inicial de migración
prometía no saltar ninguna entrada tool wire inválida. Stock1.24 elimina siblings
id-only, null o function-name sin args/ID; Response.tool_calls/error/provider_meta/
message.metadata/call_metadata públicos son iguales al control válido sin sibling.
Reproducción TCP conserva un efecto de la única llamada válida autorizada. No hay
señal pública para rechazar todo ese batch sin bloquear también el control válido;
no se añade parser/fork. Según8.22 se validan todas las llamadas **semánticas
expuestas**, no entradas borradas upstream. No se anuncia conservación de aquella
garantía raw ni contadores host de intentos wire perdidos. Calls visibles con JSON
truncado/sobre ausente/schema inválido siguen invalidando el batch completo con
cero efectos; control con permiso deny produce cero aun si el sibling desaparece.
No se rebajan guards/autoridad ni se ejecuta la entrada inválida perdida. Matriz
durable `req_llm_loss_boundary_test` y registro fechado conservan rojo y controles.

Salida: cero referencias runtime a retirados, resolución/custom/specs/auth probados,
oráculos preservados por API ReqLLM/ExAgent, suite offline y TAR smoke del grafo
afectado; review fresca independiente recibida sin P1/P2 concretos pendientes.
El cierre documental26Sep conserva funciones/guards; no es otra revisión de runtime.
No cierre G2/R1/C7 por este ADR.

### 8.27. R2 base: identidad, selección y capacidades explícitas (2026-09-26)

**Problema demostrado antes del cambio.** Tres regresiones públicas nuevas
(`r2_base_contract_test`, seed37556, 0/3) muestran que un hook custom/Test cambia
el nombre y ejecuta otra tool, que una tool retirada de los parámetros de request
sigue ejecutándose desde el inventario del agente, y que un Model sin `profile/1`
anuncia tools y JSON como soportados. El primer intento de fixture tenía aridad
incorrecta (takes_ctx por defecto true); la reproducción corregida conserva los
efectos y outcomes reales en `/tmp/opencode/exagent-r11/r2-base-red.log`.

**Decisión y beneficio.** La identidad de una call admitida (ID, nombre, kind y
metadata) es inmutable para before_tool_execute en cualquier Model. Sólo args
pueden transformarse y se revalidan antes de autoridad/efecto. La selección de
function_tools de cada request es la lista efectiva ejecutable, preparada antes
de IO; un inventario más amplio no autoriza tools omitidas. La selección y los
callables son configuración confiable de la app, nunca del LLM. ModelProfile
declara soporte extra sólo mediante true explícito; defaults tools/JSON false
significan no negociado, no una prueba de imposibilidad del backend. Texto básico
sin profile sigue operativo; streaming continúa exigiendo su callback público.

**Alternativas e impacto.** Conservar la excepción custom fragmenta la autoridad
y rompe correlación call/result. Filtrar únicamente schemas enviados no limita
efectos. Defaults permisivos equivalen a certificar una extensión desconocida.
No añadimos registry, jerarquía de capacidades, segundo plugin system ni un modo
legacy. Ruptura conjunta v2: hooks que redirigían nombres deben seleccionar tools
antes de request o usar un callable dispatcher explícito con identidad propia;
custom Models que sí implementan tools declaran supports_tools:true y demuestran
su contrato. JSON no se declara por pasar Ecto-tool. Fixtures existentes de batch
conservarán efectos/errores/orden usando nombres originales efectivos y hooks de
args, con pruebas negativas separadas de sustitución. No cambia versión nominal.

**Verificación/salida.** Regresiones públicas sync/stream de identidad y selección,
negativo preIO y texto positivo de Model sin profile; gates core/tool/schema/event,
suite offline y consumidor externo Model/tool del TAR fijo. R2.3 nativo permanece
separado. Codec/envelope/continuation/accounting y guards aceptados no cambian.

**Dos huecos adicionales reproducidos en R2.5.** El before-tool recibía contexto
con tool_name/tool_call_id nil, aunque el callable posterior los tenía; ahora ambos
reciben identidad/retry de la misma call inmutable. Una excepción before-tool se
clasificaba unknown como si hubiera IO; el boundary de ese hook ahora produce
not_executed y tool_hook_failed, sin retry automático. Excepciones del callable
y timeouts en vuelo conservan unknown; el after-hook sigue preservando el efecto
confirmado. Rojo focal4/6 seed37556 en `r2-hooks-red.log`; no promesa de rollback.
Además, callable nil/aridad incompatible alcanzaba el modelo: rojo6/7 en
`r2-callable-red.log`. La selección ejecutable ahora exige función de aridad2 con
takes_ctx:true o aridad1 con false, antes de IO; error invalid_tool_callable con
nombre. Tool.prepare continúa sirviendo para schemas/proyección sin callable
(incluida output tool interna); sólo la admisión ejecutable exige esa función.
Migración: corregir takes_ctx/call de definiciones inválidas, no añadir callbacks
ficticios para schemas que no deben ser herramientas ejecutables.

### 8.28. R2.1: superficie pública y pausa coherente (2026-09-26)

**Mapa de estabilidad para la major, todavía no publicada.** Estable significa
contrato que v2 pretende mantener con SemVer, no aceptación externa universal.
C7 aún no implementado es alcance pendiente, no experimental para eludir aceptación.

| Superficie | Clasificación y frontera |
|---|---|
| ExAgent.new/run/run_stream/run_child | Pública estable: definición reutilizable, ejecución/DI/settings por run; run_child fija ancestros. No serializar definición/callables. |
| Result map, RunError, CheckpointError | Públicos estables: output completo al éxito; error conserva progreso/uso/modelo confirmado. Retry-save no es retry-run ni borra efectos. |
| Message.Request/Response, Part.*, codec, Usage | Públicos estables en subset cualificado: IDs, orden, args lógicos, outcomes/calidad; continuación JSON versionada, no structs ReqLLM persistidos. |
| Model/Profile/RequestParameters/Settings | Extensión pública estable: Response y siguiente modelo por interacción, stream opcional lazy con terminal único. Soporte extra explícito. Átomos native/prompted/auto no prometen implementación. |
| Tool.new, Tools/deftool, validación/definition, RunContext | Públicos estables: schema lógico, DI/contexto; prepared_validator y execution_scope opacos. |
| Capability | Hooks públicos estables ordenados, módulo o struct. Selección pre-request: model, settings, params.function_tools, request_messages; deps confiable de app. Identidad/scope/ledger/prepared_tools internos, no sustituibles. |
| Server, Session, snapshots, Store, PubSub, Event, policies | Públicos existentes con ampliaciones R3–R5 pendientes; Store actual single-writer snapshots no claims/CAS, PubSub avisos no cola durable. |
| RunEvent/on_event, on_progress | Bridge interno/avanzado de runtime con datos vivos, no envelope portable; Event/Server para integración serializable. Uso previo sigue funcionando, no nuevo bus. |
| ExAgent.Run, Capabilities, operaciones ExecutionScope, SnapshotData, ErrorProjection, helpers ReqLLMEnvelope/Buffered/Stream | Internos aunque accesibles: no compatibilidad de campos/funciones privadas; usar dispatchers/codecs públicos. |
| Perfiles/integraciones no cualificados | No soportados/no verificados; experimentales sólo si expresamente identificados. Catálogo/callback ausente no convierte desconocido en sí. |

**Hooks y datos.** before_model selecciona por request; request_messages proyecta
sin alterar historia y se limpia al aceptar respuesta. after_model puede transformar
la respuesta/batch antes de admisión de tools: identidad única, tamaño, schema y
autoridad se aplican al batch efectivo. before_tool recibe una call ya admitida y
sólo modifica args, sin sustituir identidad. Hooks son Elixir confiable, no sandbox
contra código host malicioso que haga IO propio. Fallo pre-request conserva cero
intentos; post-request conserva respuesta/uso/modelo confirmados; cada call tiene
outcome y no hay retry automático de IO incierto.

**R2.2 sin cambio de formato.** Reutiliza diseño8.23–26: envelope1 sólo wire,
args canónicos con marker, continuation2 ligada al target, accounting1 y Server
snapshot3. Lectores v1/v2 conservan uso legacy unknown; calls ReqLLM sin marker
rechazan, no se envuelven para legitimarlas. Migración fuera de banda sólo de
datos cuya validez/target pruebe la app, preservando IDs/outcomes/no-replay; nueva
conversación es opción explícita. Proyección/compaction/restore conservan estos
datos. No mensaje opaco ni bump preventivo para R2.3 sin requisito nativo real.

**Pausa futura: diseñada, no implementada.** La aprobación callback actual bloquea
memoria y Session.pause sólo frena turnos: ninguna es un run durable suspendido.
Mantenerlas como C7 fingiría recuperación. Se extenderá el mismo result map con
status paused, output:nil, progreso y referencia versionada a continuación.
Sync devolverá `{:ok, result}` y stream `{:result, result}` con status paused,
significando suspensión confirmada, no éxito final. Server conservará el resultado
y publicará run_paused, no run_finished. No se implementan estas ramas ahora.
Sólo después de ACK Store confirmado; sin Store capaz, rechazo pre-efecto.
El stream termina y resume abre otra enumeración correlacionada.

run_id identifica la ejecución lógica y permanece al continuar; attempt_id
distinguirá ownership/reanudación (campo nuevo a concretar en R4), model_request_id
cada intento Model, tool_call_id cada call. request_id de Server identifica la
solicitud del caller, no la aprobación. Continuation/approval tendrán IDs propios,
revisión CAS y versión de definición/codec; decisión repetida idéntica idempotente,
opuesta/revisión obsoleta conflictiva. Rehidratar definiciones/deps confiables,
nunca scope/funciones/modelo con credenciales serializados.

Persistir un frame con respuesta lógica, orden del batch, args efectivos validados,
definición/policy/decisión y outcome por call; no repetir pasos confirmados. La call
pendiente no es ToolReturn exitoso ni unknown de IO: su estado pendiente vive en
continuación separado de historia cerrada. Tras crash, IO sin confirmación queda
incierto y necesita reconciliación/retry explícito, nunca replay por lease expirado.
Antes de paused, recolectar/finalizar trabajo propio hasta frontera acotada sin
workers huérfanos. R4 decide schema/atomicidad/fencing; R5 prueba reinicio y dos
resumers con autoridad vigente y contadores restaurados sin doble suma.

**Compatibilidad, alternativas y verificación.** No PausedResult paralelo, excepción
de control normal ni callback bloqueante vendido como persistencia: un estado del
resultado común evita divergencias. Consumidores futuros deberán discriminar status
en vez de asumir ok=output final y aceptar run_paused; hoy no reciben ese estado.
No firmas nuevas resume/approve antes del Store atómico. ADR no acepta C7: faltan
A6/A7, R4/R5 y R2.3 para cerrar R2. Reusar pruebas actuales de error/progreso/stream
y snapshots, no una pausa simulada para declararla implementada.

**Extensiones R2.6.** Model posee una interacción, Tool callable/schema, Capability
selección/transformación confiable, Store IO confirmado/codec portable, PubSub
broadcast/subscribe con error explícito, policy transición de Session. Callback
opcional ausente significa no soportado o noop documentado; snapshot jamás implica
CAS. Mantener behaviours sin jerarquía adicional; R4 negociará atomicidad cuando
exista esa operación. La app selecciona módulos/config confiables; bytes guardados
no eligen implementadores arbitrarios. Consumidor externo prueba Model/tool con
positivo y negativo preIO, grafo fijo y sin APIs privadas; no cambiar Store/PubSub/
policy para llenar una unidad ya satisfecha por sus contratos existentes.

### 8.29. R2.3: output nativo explícito y autoridad Ecto (2026-09-26)

**Problema demostrado y beneficio.** `output: ModuloEcto` siempre crea una tool;
`ModelRequestParameters.output_object` estaba sin uso y ReqLLM rechaza native.
El gate público stock1.24 (`req_llm_native_gate_test`) demuestra formato nativo
con `generate_text`/`stream_text`, schema efectivo sin alterar required/defaults,
sin tools sintéticas ni reparación. Amplía extracción tipada sin confundir soporte
de tools con JSON Schema. Stock stream expone objetos JSON como contenido público
`:object`, mientras buffered conserva texto; no se promete identidad de bytes.

**Decisión previa a estabilizar.** Añadir `ExAgent.new(output: ModuloEcto,
output_mode: :native)`, conservando default `:tool`. Params lleva `output_object`
separado y ninguna final_result tool. JSON se decodifica estrictamente como objeto,
se valida el schema anunciado y después el changeset real (autoridad final,
incluidas reglas no reflejadas). Fallos de validación usan el retry correctivo host
existente, con nueva request contabilizada e historia de texto/Retry; nunca reparar
la respuesta inválida ni repetir automáticamente efectos. El terminal válido sigue
siendo condición previa; deltas son provisionales.

ReqLLM requiere `output_profile: :chat_json_schema_v1` explícito además del perfil
Chat-tools ya cualificado: mismo destino/protocolo, no reasoning, no strict. Usa
únicamente `provider_options.response_format` público con `strict:false` y schema
reference-free compartido con el sobre. Se conserva optional, null y defaults
inertes exactamente; refs/raíz/keywords no representables rechazan antes de IO.
No adopta strict auto ni anuncia soporte por catálogo. El objeto público stream
se representa como texto JSON canónico sólo para native; no parser wire ni segundo
consumo/acumulador. Contenido/continuación restante conserva guards y codec2.

**Alternativas.** `generate_object` auto puede escoger tool/strict y reescribir el
schema; no satisface separación explícita. Un nuevo backend o cambio global de
defaults sería innecesario. Interpretar cualquier texto como JSON rompería agentes
textuales; aceptar objeto sin changeset eludiría reglas Ecto. No crear otro result
struct ni bump de historia: el nativo se representa con partes Text existentes.

**Migración y verificación.** Adición opt-in para major prevista, nominal intacto.
Consumidores existentes conservan Ecto-tool; custom Models sólo reciben native si
declaran supports_json_schema_output:true. Perfil no cualificado rechaza, nunca
fallback. Gate2/2 inicial con controles inválidos buffered/TCP, después integración
vacío/embeds/null/condicional/retry/agotamiento/historia/uso y negativos preIO,
consumidor TAR y review fresca antes de aceptación. Stock omite la opción false de
parallel_tool_calls en su precedencia: no se anuncia esa garantía. G2 live sigue
pendiente; evidencia y limitaciones en el registro R2.3 del checkout.

**Refusal y semántica pública.** Gate stock compara respuesta válida con la misma
respuesta más refusal wire: `Response.refusals`, contenido/objeto, finish_reason,
metadata/provider_meta/output_items son iguales en buffered y stream. Un refusal
habitual sin contenido válido falla; un refusal perdido junto a JSON válido puede
producir output validado localmente. Coordinador confirmó continuar bajo8.22/8.26,
sin prometer reconstruir señales borradas; se rechaza cualquier refusal expuesto.
Esta limitación se explicita en README/migración y exige revisión fresca del oráculo,
no parser privado ni reparación. Combinación function_tools verificada TCP con
efecto único, retry Ecto y continuación en las tres superficies.

**Corrección P2 de review fresca: configuración efectiva preadmisión.** El probe
público independiente reprodujo schema inválido seleccionado por
`before_model_request`: custom Model recibía dos requests y podía ejecutar una
tool antes de `output_retries_exhausted`. Preparar sólo al finalizar confundía un
error de configuración con datos corregibles del modelo; el rechazo del adapter
ReqLLM no protegía la frontera Model genérica.

El core prepara el schema native efectivo después del hook y antes de admitir
cada request, reutilizando el validador Tool/JSV privado mientras el schema no
cambie. `RunError.reason` es `{:invalid_output_schema, errors}` para un schema
inválido, con los diagnósticos normalizados de Tool; objeto/configuración native
malformado o `output_tools` no vacío devuelve `:invalid_output_configuration`.
No hay retry de configuración ni nueva request/efecto para ese paso. El parcial
conserva progreso anterior si el hook cambia la configuración en pasos posteriores.
Sólo datos JSON/schema/Ecto inválidos devueltos por el modelo usan retries; Ecto
del agente sigue siendo autoridad final. El cache no viaja al Model ni al historial.

Validar sólo la definición no cubre hooks; delegar a cada adapter duplica semántica
y deja custom expuesto. Migración: corregir schema/inventario en el hook, manejar
el error de configuración en lugar de esperar retries del modelo. Controles
públicos cubren tres superficies, cero requests/tools, cambios de schema por paso,
schema válido y retries de datos; los gates ReqLLM y Ecto existentes se conservan.
La corrección queda pendiente de revalidación por la misma review independiente.

### 8.30. Identidad de consumidor en runtime y snapshots (R3, 2026-09-26)

**Problema demostrado por inspección:** Server/Session cargan Store exclusivamente
por agent_id/session_id y Event publica en un topic formado sólo con ese ID.
Dos consumidores con el mismo ID y backend/PubSub compartido seleccionan la misma
conversación y el mismo canal. Crear un átomo por tenant o exigir una tabla/proceso
por consumidor no es una solución general. Las policies, single-writer y refs
confiables existentes se conservan.

**Decisión previa al código, coordinada con R4:** identidad conceptual única
`{namespace, kind, logical_id}`. Server/Session reciben `namespace` de la app:
nil (legacy) o string UTF-8 no vacío. El helper interno RuntimeIdentity codifica
`exagent.scope.v1:` + base64url sin padding de JSON `[namespace, kind, logical_id]`.
Kinds sólo agent/session; no se convierte input a átomos. Topic reutiliza ese
codec, con prefijo de tipo existente. Event añade namespace explícito; IDs locales
siguen locales y se interpretan junto al namespace. Run/emitter IDs mantienen su
generación e identidad viva; claims/attempts durables pertenecen a R4/R5.

`Store.scoped(store, namespace)` produce un descriptor único Store.Scope; el
dispatcher adapta los callbacks snapshot existentes, sin cadenas de wrappers.
Al guardar sustituye sólo el ID externo por la clave compuesta; al cargar exige
struct/tipo, codec y clave exactos antes de devolver el ID lógico. Namespace nunca
se toma de metadata/LLM/snapshot para elegir la autoridad del runtime. List y
delete se restringen al mismo espacio; nil excluye entradas scoped de sus listados.
No hay fallback hacia claves legacy ni dual-write. No cambia el codec de historia
ni la versión interna de snapshot: su campo ID conserva un string portable.

**Alternativas/compatibilidad:** callbacks con scope nativo ahora romperían todos
los Stores snapshot sin aportar atomicidad; el descriptor conserva ETS/Postgres y
los Stores custom públicos probados por consumidores y fixtures. R4 añadirá sus
operaciones atómicas con scope estructurado y una ruta explícita, sin adaptar CAS
con load/save. La compatibilidad snapshot vive mientras esos callbacks sean
soportados; se retira sólo con la retirada/migración de sus consumidores.

**Impacto/migración major:** nil conserva claves/topics existentes excepto IDs
que empiezan por `exagent.scope.v1:`, ahora reservados y rechazados antes de IO.
Esos IDs deben renombrarse explícitamente; pasar una conversación legacy a un
namespace requiere exportar/validar/importar datos, nunca búsqueda automática.
Subscribers scoped usan Event.agent_topic(id, namespace)/session_topic(id,
namespace); consumers agrupan por namespace+ID. La app sigue resolviendo refs,
autenticación, ownership de procesos y autorización; esto no impide invocar el
backend directamente ni añade claim distribuido.

**Verificación prevista:** mismo ID en A/B/nil, IDs con delimitadores y prefijos,
JSON/restore con refs confiables, list/delete aislados, payload/key mismatch,
topics/eventos y smoke de16 namespaces con cola saturada; secuencias existentes
para lifecycle/terminal/cleanup. Aceptación y límites se registran en roadmap§5.

### 8.31. Admisión de payloads Server (R3 parcial, 2026-09-26)

**Problema:** max_pending sólo cuenta entradas; una cola de dos entradas puede
retener prompts/deps arbitrariamente grandes. La historia canónica append-only
no se reduce por compaction. **Decisión mínima autorizada:** opciones Server
max_input_bytes (1MiB), max_pending_bytes (8MiB), max_history_bytes (8MiB), enteros
1..64MiB. Se mide `:erlang.external_size` sin compresión: `{prompt, opts}` para
entrada, `{prompt, opts_con_request_id}` por pendiente, historia para admisión.
Incluye términos deps/callbacks como representación externa Erlang, no JSON ni
RAM viva/recursos referenciados. Es comprobación postmaterialización del término
del caller, no protección del mailbox ante productores arbitrarios.

Antes de iniciar/encolar, exceso input/history devuelve error explícito con bytes
y límite; cantidad o bytes de cola devuelve queue_full sin admitir. Bytes se
liberan al desencolar; health los expone. Una entrada ya admitida se revalida al
ejecutar porque la historia puede crecer mientras espera: fallo terminal sin
request/efecto, no desaparición silenciosa. Restore sobre umbral falla startup.
No truncar historia ni confundir caller timeout con cancelación. Aumentar límites
explícitamente dentro del techo o externalizar referencias/payloads es migración.

**Límite de esta decisión:** no acota la respuesta/tool result del run actualmente
en vuelo ni convierte snapshots en streaming. R3.4 permanece parcial hasta
decidir/demostrar una frontera de salida propia que preserve los efectos
confirmados; límites R1 stream64KiB/1MiB/4096 se conservan. Un guard sólo al run
siguiente no se anuncia como cota total de retención. No nuevo ContextLimits ni
alteración del core por esta decisión. Gates exacto/uno más, bytes en cola y
liberación/deadline, más secuencias existentes.

### 8.32. Retención propia postdecode y efectos con payload omitido (R3.4, 2026-09-26)

**ADR escrito antes de implementar y shape aprobada por coordinación; nueva
implementación bajo verificación, review independiente pendiente.**
La reproducción pública se volvió a ejecutar con el runner aislado (label
`r34-output-gap-repro`, exit0): una tool devuelve65536 bytes después de un efecto;
Server configurado con max_history_bytes1024 conserva68792 bytes, hace dos requests
y devuelve éxito. El control sólo protege la admisión siguiente. El core publica
Response antes de after_model y envía el ToolReturn íntegro antes de after_tool;
limitar únicamente Server o el valor individual deja esas copias y los agregados
sin protección. El bridge core→Server tampoco espera confirmación de consumo.

**Beneficio/alternativas:** una frontera común del loop cubre sync, stream_text,
run_stream y Server sin otro framework ContextLimits. Rechazar sólo al guardar
perdería la evidencia de efectos; truncar strings silenciosamente inventaría un
resultado; rollback/retry no revierten IO. Se descarta asumir que Usage custom es
pequeño: por decisión coordinada, también se comprueba y se marca su omisión.

**API y unidad:** `max_payload_bytes` P por definición/run, default1MiB,
y `max_history_bytes` H, default8MiB, enteros1..64MiB. Server transmite el mínimo
entre su H y el de la definición como
restricción propia, no ampliable por chat opts. Son bytes externos Erlang sin
compresión (`:erlang.external_size`), no tokens, JSON, factura ni RAM. P mide
Response/ToolReturn completos, no sólo content; H mide historia canónica completa.
La proyección compactada no libera historia. Entrada inicial/historia restaurada
y proyección tras hooks se comprueban antes de request/tool admission. La historia
confirmada no se elimina para acomodar nuevos datos.

Antes de aceptar una Response con calls se exige espacio para la Response y una
reserva de resultados de todas las calls. La reserva permite conservar IDs/nombres,
status y omisión aun si todas terminan con payload enorme. Si no cabe, cero tools
admitidas. Se resta de H el tamaño de historia+Response+Request de resultados
vacío y se divide el resto entre todas las calls, con slot máximo P. Cada slot
debe alojar el ToolReturn marker con IDs/nombre más4096 bytes de Usage y128 de
margen para números/status/overhead. La suma conservadora de tamaños individuales
incluye un byte de versión EFT por slot; no depende del orden de llegada ni descarta outcomes
confirmados cuando un hermano agota el presupuesto. Un error detiene el loop tras
recoger el batch admitido; timeout conserva confirmados y los demás quedan unknown.

**Shape:** Response y ToolReturn añaden `payload_omitted`, nil o mapa
JSON validado `{"version":1,"boundary":...,"bytes":N,"limit":L}`. Una Response
rechazada antes de efectos se conserva sólo como diagnóstico acotado, sin contenido
ni continuación ejecutable; nunca se ofrece como respuesta completa. ToolReturn
mantiene identidad y status real (succeeded/failed/unknown/etc.), `content: nil`
y marker cuando no se retiene el valor. Si sólo se omite Usage, el contenido que
cabe se conserva y el marker tiene boundary usage. La presencia del marker invalida el uso
del contenido como resultado, no el efecto. RunError terminal
`{:retention_limit_exceeded, %{boundary: ..., bytes: N, limit: L}}` no contiene el
original; no retry correctivo ni otra request tras omisión. Se revalida después
de hooks sin borrar la confirmación previa si el hook falla o infla el resultado.
Incomplete/unknown no se convierten en completos por caber dentro del límite.

**Accounting/control:** Usage tiene un límite postdecode fijo de4KiB para el
registro por operación. Si excede, se retienen únicamente las dimensiones/coste/
calidad/availability canónicas que quepan y un marker versionado de omisión;
details arbitrarios se omiten explícitamente. Una dimensión numérica que no cabe
se vuelve nil/unavailable (o partial si existe subtotal anterior), jamás cero.
Los contadores HOST permanecen exactos; no repricing ni doble suma de hijos.
El original tampoco entra en Scope, errores, progress, eventos ni snapshots.
Scope comprueba también la combinación de snapshots parciales de la misma request;
no basta que cada actualización individual quepa. También comprueba el agregado
Scope/Server y los costes del estimador dentro del resumen completo4KiB, no sólo
el tamaño de cada número. Al omitir se priorizan input/output/cache_read/cache_write/
reasoning, total y coste; cada dimensión se conserva si cabe con su availability
original, sin confundir aliases canónicos con metadata arbitraria. Server conserva
el output/efecto del run confirmado pero devuelve error si su agregado excede;
su Usage marcado bloquea nuevas admisiones hasta reconciliación explícita/reset.
Esto requiere pruebas focales de R1.5 y codec de omisión; accounting v1 y
continuation2 no cambian de significado. Los datos de control/error tienen una
reserva finita de65536 bytes separada de H. Los errores conservados se limitan
a4096 bytes; mayores se sustituyen por el error de retención con cifras, sin causa
original. El resultado publica `retention.version:1`, `measurement:
:erlang_external_term`, `history_bytes` y `data_bytes` exactos (EFT de Map.take
output/messages/new_messages/pending_response/usage), más P/H/control_reserve_bytes.
Esa proyección satisface **2H+P+65536**; no significa total≤H. Una Response parcial
stream añade overhead fijo a sus P bytes de texto. Event exporta cifras con
allowlist y representa el error con boundary/bytes/limit, no como término opaco.

**Perfil y límites de responsabilidad:** definiciones, modelo vivo stateful,
deps/callbacks y recursos de app no forman parte de la métrica de datos públicos;
no se promete sandbox del código confiable. Sí quedan dentro historia, output,
pending response, usage, error y payloads de progreso/evento. Bridges propios
usan confirmación correlacionada para no acumular snapshots con consumidor lento.
PubSub/subscribers externos son propiedad de app. La cota de copias propia debe
enumerar loop/batch/Scope/RunStream/Server y serialización; no llamar RAM a la suma
de bytes externos. R1 conserva una vista stock, chunks64KiB/total1MiB/4096 y cleanup;
el objeto upstream ya decodificado y la devolución de una tool pueden materializarse
antes del check. Esa limitación no permite retener el original rechazado.

**Copias del perfil:** los frames protect/try pueden conservar estados de pasos
anteriores; con S pasos, no se promete una sola copia H. Cada estado del loop
guarda una historia H y una proyección≤H; cada
snapshot público puede serializar hasta2H por messages/new_messages aunque BEAM
comparta listas/binaries. RunStream conserva una última proyección y un evento
pendiente; el ACK de progreso existente se conserva. Server ahora confirma por
GenServer.call el consumo de progreso/evento/delta antes de producir el siguiente,
por lo que una suspensión del owner bloquea su worker. Batch usa C tasks simultáneas
(default Task.async_stream: schedulers_online), cada una con contexto/historia H;
el conjunto de slots de resultados confirmados/finales tiene suma≤H por vista.
Scope guarda registros de operaciones, no sólo un agregado: cada Usage por
operación≤4096; su número depende de requests/batches admitidas y, en delegación,
de los nodos del perfil. La cota se expresa con esas concurrencias/conteos, no como
memoria universal independiente del escenario. Resultados entregados a callbacks/
caller, mailboxes PubSub y definiciones/modelo vivo son propiedad de aplicación.
El perfil medido usa identidades confiables cortas, sin delegación,3×8 streams;
máximos/cleanup en el registro R3.4. El margen para Event con duplicación/escapes/
envelope es16×(2H+P+65536), contrastado con tamaño EFT, no RSS.

**Migración major:** manejar error terminal y marker de payload antes de consumir
content; externalizar resultados grandes mediante referencias o configurar límites
finitos mayores. No reejecutar efectos por faltar su payload. JSON/snapshot deben
preservar el marker y rechazar versiones desconocidas. Server snapshot pasa a4
con lectores1/2/3 y rechaza marker Usage declarado en versiones anteriores. Un
lector snapshot3 rechaza4 en lugar de borrar la omisión. Message JSON emplea
discriminadores `tool_return_omitted_v1`/`response_omitted_v1` para datos omitidos:
los lectores anteriores también rechazan esos nodos en un historial suelto. Usage
añade marker opcional en su mapa; accounting1/continuation2 permanecen intactos.
Restore no
ejecuta tools y revalida presupuesto antes de admitir otra interacción. Native
Ecto, envelope y continuation guards siguen intactos. Una admisión inicial que no
puede añadir el prompt conserva la historia previa que sí cabe. Hooks proyectan
request_messages o transforman la última Response antes de efectos; no pueden
borrar/modificar historia ya confirmada para liberar espacio.

**Oráculos previos:** exacto/+1 para P/H/Usage y reserva, cero efectos antes de
admisión, un efecto confirmado sin replay, batch con varios oversized/completados/
timeout, inflación after-hooks, input/history/compaction/restore, error sin original,
paridad de cuatro superficies y roundtrip de marker. Consumidor lento y carga
finita usarán umbrales escritos antes de ejecutar; gates foundation se reutilizan.
Aceptación R3.4 requiere implementación, evidencia de tamaños/copies/cleanup y
review independiente. Esta propuesta no cierra R3.4 ni amplía R4/C7.

**Bugfix de review R3.4 (2026-09-26):** los probes independientes demostraron cuatro
incumplimientos de este contrato: causas monitor de210KB publicadas por RunStream/
Server, error de estimador210KB retenido como `record_result` del ledger, un hook
que inyectaba `pending_response`210KB en datos públicos y nil omitido convertido en
el string `"nil"` por JSON. Se reutiliza `Retention.reason/1` antes de publicar el
crash o enviar el resultado contable al ledger; los duplicados devuelven el mismo
resultado acotado sin recalcular precio. `pending_response` es estado interno
confirmado del runtime, no una segunda Response transformable: se restaura desde
ese estado al validar hooks, manteniendo la transformación legítima de la última
Response. El nodo omitted-v1 codifica su content:nil como JSON null; el codec
legacy permanece igual. Son correcciones de8.32, no otra versión ni contrato.
Limitar sólo la proyección final dejaría el original retenido en Scope/bridges;
validar la Response canónica sin normalizar el pending paralelo dejaba el escape.
No cambia status, partial, resultados confirmados, disponibilidad/calidad ni el
subtotal host del último progreso ante muerte abrupta; no se inventa contabilidad
posterior a ese progreso. No hay migración adicional: conservar marker y evitar
replay sigue siendo obligatorio. Doce regresiones permanentes y los seis probes
independientes verifican límites, controles pequeños, duplicados/no repricing,
cleanup, transformación válida y roundtrip snapshot4; revalidación independiente
aceptada sobre source05a02459/TAR8775e665 en el registro R3.4.

### 8.33. Primitivas de continuación por registro (R4)

**Problema demostrado:** Store guarda snapshots por sustitución incondicional;
dos owners pueden guardar la misma revisión y un ACK perdido no identifica la
operación confirmada. Un snapshot no demuestra permiso para repetir una tool.
**Beneficio:** una unidad atómica con snapshot existente, ejecución y receipts
permite al futuro R5 reclamar progreso e inspeccionar incertidumbre sin procesos.

**Decisión:** callbacks opcionales capabilities/load_record/transition/scan_records;
Store.Scope proporciona namespace confiable y kind/id usan RuntimeIdentity. JSON
record_version1 contiene snapshot validado por sus lectores existentes, ejecución
mínima/referencias/progreso JSON, revisión CAS independiente y receipts. Cada
comando incluye record_id de lifetime generado por host: no inferir create de una
referencia vieja. Start de datos permite nueva ejecución tras terminal, preserva
revisión/fence y proyección terminal en receipts; no ejecuta ni reanuda un run. Reducer
cerrado, pequeño y sin callbacks ejecutables; claims cambian owner/attempt/fence y
no reinician progreso. Persistir begin_effect antes de IO y outcome después; lease
expirado permite recuperación, jamás replay. Un marker sin outcome exige estado
uncertain y reconciliación explícita. Actor/payload/revisión esperada se ligan al
operation_id mediante canonical JSON v1 (objetos ordenados; 1 distinto de1.0).
El host autoriza actores; estos bytes no autorizan ni resuelven módulos/secretos.

**Representación:** una fila key/data que puede contener snapshot legacy
o envelope, nunca dos copias autoritativas. Callback recibe key estructurada;
adapter usa codec R3. Loads legacy también rechazan envelope para impedir que un
Server aún no integrado ejecute desde su snapshot; list legacy los omite. Lectura
explícita load_record es inspección, no permiso. Mutaciones legacy rechazan envelope
bajo la misma exclusión.
ETS serializa en su owner; Postgres bloquea fila en transacción, create usa unique
key y DO NOTHING RETURNING. Sin false CAS load+save, tabla por frame, event sourcing
ni motor de jobs. DDL es propiedad de app; G3 real permanece bloqueado.
Consumidor concreto de compatibilidad: framework evals usa tid ETS sin GenServer.
Conserva snapshots-only mediante CAS legacy acotado, nunca declara continuación;
se retira sólo al retirar explícitamente esa API de snapshots con migración.

**Tiempo/retención:** UTC ms dentro del lock gobierna deadline/expiry/lease, nil
expiración admitido. Progreso de tiempo activo/presupuestos se conserva al claim;
el futuro R5 debita tiempo activo sin contar espera humana. Límites8MiB/256effects/
1024receipts rechazan exceso y no expulsan evidencia activa. Admisión reserva
receipts/bytes para cierre mínimo y reconciliación; no promete que cualquier futuro
payload quepa. Cancel de datos con intento en vuelo produce uncertain. Sólo terminales pueden
borrarse; borrado por namespace devuelve progreso, exige quiescence host y no
promete atomicidad global. Un lifetime borrado no puede ser reutilizado por el host;
anti-reuso histórico sólo cubre evidencia retenida, no historial eterno tras borrado.

**Impacto/migración:** API experimental aditiva para v2; snapshots-only conservan
lectores y rechazan continuación antes de efectos. Snapshot legacy no se convierte
en ejecución automáticamente. Importar con writers parados, backup, validación de
identidad y configuración explícita; jamás fallback tras corrupción. Dirty/retry es
un seam opt-in de datos independiente del RuntimeCheckpoint actual, sin cambiar
Server/Session/run. R5 integra pause/decision/resume, autoridad/config y contabilidad.

**Verificación:** matriz previa en `docs/development/r4-implementation.md`, carreras
con barreras, crash intent/efecto/save, ACK perdido, owner obsoleto, corrupción,
límites y namespace. SQL fixture sólo verifica protocolo; G3 permanece pendiente.
La integración sobre R3.4 conserva íntegros Snapshot4, omitted-v1, Usage marker,
accounting1, continuation2 y envelope1; usa lectores públicos sin duplicar codecs.
Gates nuevos y revisión integrada se registran en
`docs/archive/2026-09-26-r4-integration.md`; no equivalen a C7 implementado.

#### Corrección P2 de reserva (2026-09-26)

**Problema reproducido antes del cambio:** el Store público admitía un create a
`max_bytes - 4224` con continuation_id/run_id válidos de512 bytes U+0001. Cancel
mínimo fallaba `record_limit`, dejando ready; el control ASCII cancelaba. La
reserva fija ignoraba que JSON expande esos IDs hasta3072 bytes y los duplica en
cada receipt. También claimed sin efectos reservaba sólo un receipt, insuficiente
para recover→cancel al límite de cardinalidad.

**Decisión y prueba de cota:** reservar `n = pendientes + 1 + claimed?1:0` pasos
(terminales0). Cada paso cobra un objeto singleton receipt codificado con los IDs
reales de ejecución, IDs nuevos actor/operación de512 U+0001 (máximo JSON6×),
digest64, attempt_id null y los nombres más largos de cleanup/state de9 bytes.
La revisión del receipt usa `revision+n`; el contador fence usa su anchura en
`fence+n`. Se añaden128 bytes por paso para crecimiento de estado, campos owner
a null, marcador outcome mínimo `{status, data:null}`, running→confirmed y
crecimiento decimal de revisión, más19 para updated_at. Un outcome mínimo usa el
status conocido real (hasta validation_error), nunca sustituye un outcome mayor.
Los IDs owner/attempt ya están cargados en el registro admitido; cleanup los
libera y no los duplica en receipts. Claim sí persiste attempt_id y pasa admisión
completa antes de confirmar. No hay reducción de IDs, intents, args u outcomes.

Cada paso cleanup consume al menos una reserva; los horizontes revision+n y
fence+n no aumentan, ni los IDs de ejecución cambian. Por ello la nueva entrada y
su crecimiento caben en la reserva liberada y la restante sigue siendo suficiente.
Recover sin efectos conserva un paso para cancel/expire; cancel/recover con
efectos conserva reconciliación por pendiente y cierre. Outcome conocido permite
finish; unknown libera owner y conserva reconciliación. Mantener snapshot/progress
no crecientes y outcomes mínimos es la garantía, no payloads futuros arbitrarios.

**Dominio temporal aplicado:** todos los UTC ms del envelope/comando/reloj están
entre0 y9223372036854775807 inclusive (signed64 no negativo, compatible con el
bigint de reloj SQL). Un reloj fuera de dominio devuelve invalid_time antes del
reducer; deadline/expiry/lease y registros fuera de dominio se rechazan por sus
validadores actuales sin write. No se finge cota para enteros futuros ilimitados.
Revision/fence siguen enteros exactos sin wrap/reset y reservan crecimiento decimal.

**Alternativas/impacto/migración:** aumentar4224 por otra constante sin medir IDs
repite el defecto; ampliar8MiB, truncar datos o ignorar errores viola el contrato.
La API R4 aún no publicada conserva schema1/errores, con admisión más estricta:
puede rechazar registros antiguos cercanos al cap, claimed con1023 receipts o
timestamps fuera de dominio. No hay coerción/fallback ni migración automática de
esos datos: validar backups antes de importar; una copia experimental afectada
necesita remediación explícita por su host con writers detenidos, sin perder
evidencia. No se declara compatibilidad de importación con registros que violan
la reserva corregida. Verificación causal y fronteras públicas en
`test/exagent/continuation_cleanup_test.exs`; evidencia en
`docs/archive/2026-09-26-r4-cleanup-reserve.md`. Review aislada cierra P2 en sourceb3498467;
la aceptación integrada, G3 y C7 son gates separados.

### 8.34. Aprobación persistida en el loop existente (R5, 2026-09-26)

**Dirección aprobada antes de runtime; implementación en curso, no aceptación C7.**
El callback ask actual bloquea un proceso; el batch sólo recoge ToolReturns y la
delegación trata cualquier ok como output final. Añadir paused sólo a Permissions
perdería el cursor, permitiría a Server drenar otra solicitud y no sobreviviría una
VM nueva. La solución extiende el mismo loop/result y la fila atómica R4 con frames
data-only; un writer efímero serializa transitions y desaparece al esperar al humano.
La propuesta concreta, firmas previstas, tabla de estados y oráculos están en
[implementación R5](../development/r5-implementation.md).

**Primer contrato R5.1.** El reducer añade pending/denied y pause/decide. Pause
requiere owner/fence/lease, ningún efecto unresolved y mapa de aprobaciones exactas.
Cada aprobación version1 liga ID, run/call/tool, args efectivos, schema hash,
definition/policy y digest canónico; decisión almacena actor host/UTC. Aprobar una
de varias mantiene pending hasta aprobar todas. Denegar termina el run como denied,
sin inventar ToolReturn exitoso ni deshacer hermanos confirmados. Cancel/expire
cierran pending; expire exige deadline/expiry UTC alcanzado. Claims sólo desde ready.
El snapshot4/record1 y los codecs anteriores se mantienen; progreso R5 identificado
por sus versiones se valida, nunca se interpreta como código o autoridad.

`Continuation.get/2` consulta; `decide/4` recibe store scoped, id, approve/deny/
cancel/expire y opts host con lifetime/revisión/operación/actor y authorize obligatorio.
Approve/deny además exige approval_id y payload_hash. La autorización ocurre antes
de Store mutation; el reducer liga actor/payload/revisión al receipt, no autentica al
humano. Decisión idéntica con operación idéntica es idempotente; opuesta o payload/
actor cambiado conflictúa, revisión vieja con operación nueva conflictúa. El ACK
prueba commit, no permiso de ejecutar. Expiry nil explícito es válido.

**Tiempo/autoridad/recuperación.** Restore exige definición/deps/modelo/policy host
y autoridad ancestral original intersectada con actual. Modelo stateful e inventario
seleccionado por hooks requieren datos/codec host explícitos y fingerprints; no
sustituirlos por la plantilla actual silenciosamente. Camino run_child sin descriptor
durable rechaza antes de su IO; delegation_tool conserva un descriptor confiable.
Contadores host y ledger cualificado se restauran por identidad sin repricing ni
doble suma. Cada intento debita conservadoramente saldo activo antes de IO; sólo
checkpoint confirmado devuelve remanente medido. Crash anterior a checkpoint pierde
reserva, no reinicia saldo. UTC transcurre en espera humana, tiempo activo no.

Begin_effect confirmado + revalidación evitan despacho conocido obsoleto; no pueden
impedir pérdida de fence entre ACK y API externa. Ese caso es incierto, con journal/
reconciliación, nunca exactly-once ni retry por lease. Cota/reserva R4 se revisa para
pending/decisiones/cierre; outcomes grandes no borran intents ni autorizan replay.

**Alternativas/impacto/migración.** Callback bloqueado, replay del prompt, otro motor
de workflows y filas separadas por frame no satisfacen el objetivo de recuperación
acotada. La major añade status paused al resultado común; consumidores discriminan
status en vez de asumir ok=output. run! actualmente extrae output, por lo que paused
debe producir error explícito en esa conveniencia, documentado antes de habilitarlo.
Server guarda en la misma fila, bloquea cola durante pendiente y stream termina;
resume abre nuevo intento correlacionado. Session.pause sigue controlando turnos,
no se confunde con aprobación. No publicación/bump ni durabilidad SQL demostrada.

**Oráculos.** Primero API administrativa+CAS con actor/args/hash/revisión, competencia,
nil expiry, reserva exacto/+1 y cierre. Después API run/resume real con diarios y
barreras, VM nueva desde bytes con fixture disco test-only, batch/delegación y
contabilidad/cleanup, muerte de owners/ACK perdido/dirty/reconciliación, Server y
stream. R5 no se acepta por reducer verde; revisión fresca y gates integrados siguen.

#### Payload de checkpoint y retención C7 (dirección aprobada, verificación pendiente)

El comando dirty incluye historia/frame, por lo que no es metadata de control.
Meterlo en64KiB limitaría artificialmente C7; guardarlo fuera del resultado perdería
el retry one-shot al terminar su proceso. Se añade `max_checkpoint_bytes` J,
entero1..8388608 EFT, default8388608. Se mide el **token entero** (versión,
namespace/id, revisión esperada y comando exacto), no sólo payload/command. Store
se recibe por separado en `Continuation.retry_checkpoint/2`; nunca va en token.
`continuation_checkpoint` forma parte de `retention.data_bytes`, con cifra propia
checkpoint_bytes/J. La cota pública C7 se extiende a **2H+P+J+65536**; la ejecución
ordinaria conserva2H+P+65536. Reason sigue≤4096 y eventos sólo llevan ref/cifras.
No se serializan handles, deps ni callbacks. La app mantiene secret-free los datos
que selecciona su codec host; JSON no detecta secretos introducidos como strings.

EFT y JSON son presupuestos separados: el token≤J puede fallar todavía el cap
record JSON8MiB, su reserva cleanup y las cardinalidades R4. Antes de IO, el writer
serializado proyecta el comando begin_effect exacto mediante el reducer puro y un
outcome mínimo para **todos** los intents propios en vuelo. Comprueba token EFT y
Record encode+reserva JSON. La proyección no concede un claim: Store aplica después
CAS dentro del lock; una carrera administrativa invalida la revisión y frena IO.

La reserva conserva IDs reales, status más largo y marker de omisión, y carga por
tool en vuelo una Usage de reserva con4096 bytes de control en details en su
contribución al ledger. El codec Message existente no serializa Usage contribuida
dentro de ToolReturn: ese uso vive en el ledger, sin cambiar omitted-v1 ni duplicarlo
en el historial. Se reserva también
aggregate snapshot y cambio de uso modelo; el mínimo modelo necesita Response
omitida con uso y no un modelo vivo serializado. La reserva es deliberadamente
conservadora: Usage real ya está limitada a4096 EFT, mientras los4096 caracteres de
control del placeholder se expanden6× en JSON, más los campos canónicos y el escape
adicional del historial JSON embebido. IDs/revisión/fence/receipts se miden o reservan
con las reglas R4, sin expulsar evidencia. La prueba exacto/+1 debe mostrar tanto
token envuelto como JSON+reserva y decisiones concurrentes; no se acepta una suma
de subtotales que omita alguna copia o slot.

Tras un efecto cuyo outcome no cabe, preservar status/IDs/Usage con omisión explícita
`boundary: checkpoint` (omitted-v1/snapshot4 conservados) y error terminal; ausencia
de content no convierte un efecto confirmado en unknown. Modelo sin estado/frame
representable se expone para reconciliación, sin sustituirlo por la plantilla ni
repetir su IO. Fallo de persistencia conserva un único comando/token exacto≤J para
retry; retry no entra al loop ni interpreta un receipt viejo como permiso nuevo.

Copias propias: writer tiene un record R y un comando dirty≤J; las capturas y
serialización son postmaterialización, no cota hard RAM. R se mide en EFT aparte:
JSON≤8MiB **no** demuestra R≤8MiB EFT. Hay un mensaje síncrono por cada una de C
tasks activas y uno por root; cada mensaje puede referenciar el estado acotado del
run, como en8.32. Scope conserva N operaciones de Usage≤4096 más identidades;
restaurarlas no repricia ni duplica hijos. Frames protect/try de S pasos y callbacks
host mantienen las mismas salvedades de8.32. La aceptación requiere medición de R,
copias/tamaños propios y cleanup, no sólo el bound del resultado público.

#### Vertical root bajo revisión, todavía no C7 completo

La implementación parcial añade run/resume/resume_stream con writer efímero,
snapshot4+frame1 root+ledger1 y consulta/decisión/retry/recover/reconcile por Store.
Los tests públicos cubren proceso terminado durante espera, VM nueva desde bytes,
batch con hermano confirmado, dos resumers, ACK perdido antes/después del efecto,
tiempo activo conservador y contabilidad sin repricing. Delegación durable,
Server/Session y aceptación integrada siguen pendientes; el árbol no se aplana en
un subtotal raíz para simular que ya funciona. run_child durable sin descriptor se
rechaza antes de IO del hijo en este estado intermedio.

`Model.validate_resume/4` es un callback opcional para ejecución ordinaria pero
obligatorio para C7: preflight sin IO de historia/codec/binding con modelo e
inventario host. Sin callback, modo durable rechaza antes de Model/tool IO. Test
acepta el historial lógico común; ReqLLM reutiliza exactamente configuración,
schemas, options y context del adapter stock, terminando antes de invoke. No añade
parser wire ni segundo backend. El codec host dump/load de modelo sigue siendo
explícito; no se serializa el struct completo. Restore comprueba fingerprints de
tools/output, referencias y límites, conserva opciones de Regex de las restricciones
originales y rechaza estado desconocido/omitido. La extensión es aditiva: Models
externos ordinarios siguen funcionando; para C7 deben implementar este preflight.

El claim R5 admite restricciones UTC/activas adicionales que sólo estrechan las
guardadas. El saldo activo ya gastado se descuenta antes de estrechar el límite;
un claim debita todo el saldo disponible. Refund mide tiempo monotónico del intento
y el reducer cobra también la espera de persistencia hasta el reloj UTC del lock;
repetir un receipt no vuelve a cobrarla. Durante pending confirmado no hay débito.
run_id se conserva y cada claim crea attempt_id nuevo expuesto en el resultado.

#### Correcciones de review raíz: bindings y frontera confirmada

Los probes públicos independientes sobre source6a65 mostraron cuatro P2: el hook
podía cambiar1→1.0 bajo una aprobación del entero; cursor/outcome corruptos podían
saltar una tool; el fingerprint native intentaba codificar el módulo Ecto; y límite
actual de tools0 no invalidaba una reserva histórica1. La reproducción owner
conserva cinco rojos (dos del grupo frame) y controles positivos antes del cambio.

La aprobación se compara por digest canónico completo reconstruido, no igualdad
numérica coercitiva. La reserva histórica se valida sin debitarla otra vez contra
los límites actuales de todos los ancestros. Native fingerprint usa schema/config
JSON, nunca el módulo ejecutable, y la validación local se prepara antes de consumir
una Response restaurada. Ecto sigue siendo autoridad final y sus retries consumen
requests nuevas; el probe de recovery native antes excluido se reactiva.

El cursor debe concordar con historia abierta/cerrada, batch reservado, aprobación
aún no resuelta y operación Model confirmada. El journal Model liga índice de
historia, paso, respuesta y estado JSON del modelo mediante hashes; un frame no
puede fabricar un resultado sólo porque su ID parezca conocido. Cada outcome de
tool se liga en ambos sentidos a intención, call hash original, schema, args
efectivos/aprobación cuando corresponda, status y hash del resultado retenido.

Se conservan las dos fronteras R3: resultado raw confirmado antes del after-hook,
y resultado final después. `runtime_outcome_version:1` lleva fase explícita
raw/final, raw_hash y result_hash; igualdad de hashes no implica finalización.
`finalize_call` sólo actúa desde raw confirmado con owner/fence vigente y conserva
intención/status/raw_hash. Fija result_hash y frame en la misma transición atómica;
otra transformación con operación nueva se rechaza y sólo el replay exacto del
receipt es idempotente. Si el owner muere, se reutiliza el último resultado
realmente confirmado y retenido (raw o final), sin repetir efecto ni after-hook.
Omisión sigue siendo explícita, no un resultado completo inventado.

Para resoluciones sin despacho existe `resolve_call`: crea evidencia pre_dispatch
confirmada para denied/validation_error/not_executed; unknown conserva incertidumbre
cuando no hay prueba de no-despacho. Nunca sobrescribe un intent running/confirmed
ni admite succeeded/failed fabricados. No añade Store callback, tabla o motor.
La reserva distingue runtime model/tool de datos R4 genéricos: incluye crecimiento
de hashes/fase, longitud de finalize_call y dos receipts para tool running (raw y
final). El horizonte baja en cada confirmación; datos genéricos R4 mantienen su
reserva anterior. Exacto/+1 de bytes JSON y cardinalidad, con actor escapado, prueba
que raw→final→finish cabe sin expulsar identidad ni resultado previo.

Migración de este prototipo aún no aceptado: frames/outcomes anteriores sin prueba
coherente se rechazan al reanudar, no se adivinan ni reejecutan. Snapshot4,
omitted-v1, accounting1, continuation2 y envelope1 mantienen sus versiones. La
evidencia final/revalidación vive en el registro R5; estos fixes no aceptan el árbol,
Server/Session completo, SQL durable o C7 integral.

#### Continuación del árbol: dirección aprobada, implementación no aceptada

El relevo de la raíz corregida demuestra una frontera concreta: `Scope.export`
rechaza más de un nodo y `Frame.restore` sólo rehidrata la raíz. Quitar ese guard
aplanaría permisos, presupuestos y costes de ancestros; repetir la callable de
delegación perdería la distinción entre trabajo confirmado y pendiente.

La extensión aprobada conserva el loop, writer y fila CAS únicos. El formato de
árbol usará **frame_version2/scope_version2**, rechazados por lectores root-only.
El lector de frame1/scope1 se conserva sólo para la raíz parcial ya aceptada y sus
checkpoints existentes: valida primero todos sus bindings originales; no interpreta
campos de árbol en un registro antiguo. No se añade un modo público alternativo;
el escritor de árbol emite únicamente la versión nueva. Snapshot4, omitted-v1,
accounting1, message continuation2 y envelope1 no cambian.

El ledger2 identifica nodos por run_id/parent_run_id y cada operación por su nodo
y tipo/ID; guarda Usage ya cualificado **por ancestro**, no subtotales de hijos
sumados otra vez. La restauración exige el árbol confiable reconstruido completo,
IDs únicos, un único root, sin ciclos/huérfanos, y correspondencia exacta de padres.
Los contadores se contrastan con operaciones y reservas de batches. Restaurar no
invoca estimadores ni debita reservas otra vez; las restricciones originales y
actuales de todos los ancestros se intersectan antes de nuevas admisiones.

`delegation_tool` tendrá descriptor host opt-in con builder/opts y referencias/
codec de hijo; bytes guardados contienen sólo identidad/fingerprint/args efectivos.
El builder rehidrata configuración, nunca se repite la callable padre. Una
delegación es cursor compuesto con journal enlazado a su hijo, no un efecto externo
confirmado inventado. La raíz publica paused sólo al recolectar todos sus workers
y recibir ACK; dirty/incertidumbre prevalecen. Las reservas J, JSON y receipts
incluyen todos los nodos y slots en vuelo antes de IO.

Server mantiene pending/dirty/uncertain sin drenar cola ni borrar evidencia al
reset/cancel. Session conserva por separado su control de turno y la referencia
pendiente del participante, contrastada con la fila autoritativa al restaurar;
no promete transacción entre ambas filas. Reconcile de modelo valida respuesta,
estado portable y perfil antes de efectos. Retry explícito conserva el intent
incierto original, enlaza un intento nuevo y entrega la clave de idempotencia host
a la callable/proveedor; esa clave no demuestra deduplicación externa.

La migración major conserva status paused como no-final. La verificación exigida
incluye hijo ask+hermano confirmado, cambios de todos los ancestros, no repricing,
corrupción de grafo, cancel/restart, incertidumbre Model y los límites del árbol.
Esta dirección y el trabajo preparatorio no levantan el guard root-only ni aceptan
C7: el gate público integrado y la revisión independiente siguen pendientes.

**Reset conversacional atómico.** El oráculo Server terminal→reset reprodujo
`atomic_record_required`: el WIP llamaba al writer legacy sobre un envelope. El
comando `reset_snapshot` usa la misma revisión CAS y sólo se admite en estados
completed/denied/expired/cancelled sin efectos inciertos. Conserva íntegra execution
(incluidos frames/efectos) y receipts, cambia el snapshot vacío con revisión nueva
y no ejecuta un run. Un fallo retiene el token exacto y bloquea mutaciones/cola
hasta retry de persistencia; un receipt repetido no reinicia ejecución. El modelo
confirmado se conserva igual que en reset ordinario. No convertir el envelope en
snapshot legacy ni borrar/recrear el lifetime: ambas alternativas perderían
evidencia. La API reset mantiene :ok tras ACK y CheckpointError ante fallo; pending,
dirty e incertidumbre rechazan reset. El probe de restart verifica bytes vacíos y
el siguiente run, no sólo el estado en memoria.

**Terminal con historia abierta (decisión del relevo).** Deny/cancel/expire pueden
terminar el run mientras su snapshot contiene calls pendientes. Server expone
`health.status: :reset_required`, conserva cola y rechaza nuevas ejecuciones hasta
reset explícito terminal. Reset abandona la historia conversacional, no borra el
journal ni fabrica ToolReturns para cerrar un batch. Tras ACK de reset puede
drenarse la cola retenida; tras reinicio se deriva el bloqueo de la fila, no de
PubSub. Las colas siguen siendo volátiles. Dirty/uncertain jamás se convierten en
reset elegible. Se descarta cierre automático inventando outcomes.

**Session opt-in (firma aprobada; integración parcial bajo verificación).** Configuración host
`continuations: %{participant_id => %{store: scoped_store, id: agent_id}}`, sin
inferir Server de Participant.ref. `Session.continuation/2` consulta autoridad y
`Session.complete_turn(session, participant_id, reference, change)` completa
explícitamente un turno tras terminal sin unresolved. Ref versionada liga
participante, namespace/id y record_id/run_id/revisión exactos; identidad consumida
es lifetime+run, no revisión (reset no autoriza consumir dos veces). El snapshot
nuevo persiste sólo refs acotadas, jamás Store/callbacks; lectores legacy explícitos.
Se escribe Session snapshot3 con bindings; sin ellos se conserva writer2 y lectores
1/2. Máximo64 bindings, IDs EFT≤512, refs EFT≤4096 y entradas EFT≤8192; una identidad
consumida por binding sustituye la anterior sólo al completar el nuevo run actual.
No se promete deduplicación después de borrar evidencia. V3 exige guard data y
coincidencia exacta de bindings host, para que omisión/downcast no elimine bloqueo.
Consultas pre-callback y pre-commit comprueban turno/autoridad; discrepancia bloquea
sin repetir change. El callback es cálculo puro host, no exactamente-una-vez de
efectos ni garantía ante muerte VM. Entre lectura final y save Session hay una
ventana de reconciliación entre filas; restore vuelve a consultar, no CAS global.
Paused/error/dirty opt-in no sustituyen shared_state ni avanzan; sin binding los
mapas genéricos conservan semántica ordinaria. End_turn/handoff/leave no permiten
saltarse bloqueo, incluso ref local ausente tras crash. Session.pause sigue siendo
control independiente del turno. Estos contratos requieren sus pruebas antes de
afirmar implementación, y no se estabilizan sólo por esta decisión.

#### Follow-up de review Session y abort de Server (en verificación)

El probe independiente de Session mostró que, tras consumir runA, un RunError de
un intento nuevo bloqueaba una llamada pero refresh borraba el error al consultar
el terminal viejo A. Se reprodujo1/2 antes de corregir. Refresh sólo puede limpiar
indisponibilidad transitoria tras lectura válida; result_not_final, identidad
cambiada y cambio durante callback permanecen. Una indisponibilidad posterior no
sustituye un diagnóstico conocido. Se conserva el control positivo: reset de la
misma ejecución consumida no permite consumirla otra vez, pero sin un error nuevo
no impide control de turno ordinario.

`Session.reconcile_turn/3` es reconocimiento **host explícito de un diagnóstico
local**, no reconciliación de efectos externos. continuation/2 devuelve witness
versionado≤8192 EFT ligado a participante/binding, ID de diagnóstico único,
Session/revisión y referencia Store exacta. Sólo libera error local cuando la fila
actual es terminal sin unresolved y ya está consumida por esta Session. Dos
lecturas contrastan el witness. No ejecuta callbacks, no cambia shared_state,
current ni consumed, ni avanza. Dirty/pending/ready/claimed/uncertain/missing o
identidad cambiada no se liberan. Un witness del errorA no reconoce errorB aunque
la fila Store siga igual. Snapshot conserva diagnostic_id dentro del cap por
binding; el prototipo anterior sin error se normaliza a diagnostic_id:nil, pero
un error antiguo sin identidad se rechaza para remediación explícita. La app
autentica esta acción; no acredita ausencia de IO ajeno ni exactly-once. El retry
de save sigue siendo exclusivamente persistencia.

Abort Server presentó tres rojos públicos: pending quedaba pending, un efecto en
vuelo quedaba claimed, y Writer sobrevivía ownerkill dentro de un callback Store.
Writer queda enlazado al root; Server registra su PID mediante ACK efímero antes
de cualquier dispatch Store y confirma cleanup antes de cancelar. La identidad de
registro no se persiste. Dos probes adicionales con Store de commit diferido fuera
del writer demostraron que **matar al writer no cancela un create/start ya enviado**:
ambos commits podían llegar después de que abort consultase ausencia/terminal viejo.

La barrera aprobada usa la misma fila: `create_cancelled` sólo absent crea un
terminal cancelado, nunca ready, con frame `abort_frame_version:1` no ejecutable,
run_id y modelo portable previamente confirmado/host. No fabrica efectos, uso ni
approvals. El lector terminal valida refs/modelo y siguientes runs usan start
normal; resume/claim de ese terminal no se habilitan. `fence_admission` sólo sobre
terminal elegible conserva snapshot, ejecución/efectos/lifetime y añade una única
identidad de admisión abortada más receipt/revisión. Un create/start tardío conserva
expected/lifetime inmutables y falla contra esa barrera, sin reread/retry de IO.
Si la admisión ganó, Server relee y cancela sólo el run objetivo; un run ajeno no
se cancela por aproximación. Contención de datos tiene intentos finitos; ACK
incierto conserva token exacto y bloqueo, nunca :ok deducido de not_found.

J/JSON/1024 se aplican también a comandos de barrera; no expulsar evidencia para
hacerlos caber. Un create_cancelled incluye ya su receipt y es terminal sin deuda
cleanup; fence_admission es mutación opcional terminal y puede rechazar por cap.
Alternativa descartada: precrear/reclamar todo el loop dentro de Server ampliaría
su responsabilidad y duplicaría preparación. La extensión mínima conserva root/
writer/Store y no promete cancelación transaccional de APIs externas. Pruebas
antes/después commit, orden inverso, restart, ACK perdido y muerte Server siguen
siendo obligatorias antes de aceptar esta frontera; los primeros39 verdes locales
no demostraban el caso de commit remoto tardío.

**Retirada de participante con binding.** El probe público posterior reprodujo
leave aceptado seguido de snapshot3 imposible de restaurar con roster/bindings
vacíos. El binding no puede simplemente borrarse: olvidaría consumed mientras el
run aún es actual. En opt-in, leave devuelve `:continuation_binding_retained` si
la fila sigue presente; pending/uncertain/dirty continúan bloqueados. Sólo ante
ausencia confirmada sin pending/error local se separan roster y binding juntos.
Leave no borra Store ni crea un run. Quiescencia y borrado terminal explícito son
acciones host existentes; como en R4, después de borrar evidencia no se promete
deduplicación histórica. Un fallo de lectura o cambio de identidad no es ausencia.
Ordinary leave conserva su contrato. Se descarta añadir otro estado de roster
retirado/cleanup para resolver esta frontera de binding finita.

#### Integración del árbol R55 (2026-09-27, revisión pendiente)

El primer vertical integrado conserva un solo loop, writer efímero y registro CAS.
El escritor emite frame2/scope2 también para una raíz sin hijos. `children` identifica
cada nodo por run_id, padre, request/call, refs host, cursor/historia/modelo/inventario,
resultado y journal delegado. Los frames locales reutilizan los campos del codec de
nodo1; no son filas independientes ni autorizan a un lector root1 a interpretar un
árbol. El lector root1 se prueba contra bytes realmente emitidos por Frame/Writer de
la fuente aceptada f394, sin fabricar un downcast del escritor nuevo. Snapshot4,
message continuation2, accounting1, envelope1 y omitted-v1 siguen intactos.

El descriptor host reconstruye el hijo sin llamar la callable padre. La Response
padre retenida se contrasta con el journal Model y el hash de la call original;
args efectivos y fingerprint se revalidan contra definiciones host. Resultado del
hijo y ToolReturn del padre permanecen separados, con frontera raw/final y hashes
coherentes: después de raw confirmado no se repite efecto, hijo ni after-hook. Las
copias de Response/resultado necesarias para la relación padre-hijo cuentan dentro
de los límites del registro y del token, incluso al avanzar la historia padre.

Un rojo público mostró que `checkpoint` root-only rechaza correctamente mientras
un hermano mantiene IO en vuelo. Se añade **node_checkpoint**, limitado a un hijo
identificado y al owner/fence/lease actual: conserva snapshot raíz, otros nodos y
efectos, admite proyecciones del ledger compartido y valida el enlace al padre.
**delegation_outcome** confirma raw/final de un hijo completado y su resultado padre
en la misma revisión; no inserta un falso efecto externo running. Se conserva
`no_running` para checkpoint, pausa y finish raíz. Serializar admisiones Model/batch
en el writer evita capturar contadores de otro nodo antes de identificar su cursor.
Se descarta relajar indiscriminadamente checkpoint o aplanar la contabilidad.

Antes de rehidratar configuración se valida el grafo/ledger completo. Restore une
Scopes confiables, intersecta permisos/límites actuales y originales y revalida
reservas históricas de cada batch sin segundo débito. Requests propias del cursor
no se confunden con totales ancestrales. Los precios guardados por ancestro se
restauran sin estimador; sólo requests nuevas usan el precio actual. El deadline
UTC persistido de un hijo procede de su restricción explícita, nunca del lease o
saldo activo efímeros heredados: la espera humana no convierte el lease viejo en
un deadline permanente. El saldo activo de la fila sigue conservador ante crash.

Reservas proyectan los Model/tools en vuelo, copias de Usage por ancestro/nodo,
respuestas mínimas, resultado delegado/omisión, journal padre y receipts restantes.
Cada hijo aún no iniciado reserva un slot de efecto; continúan los caps256/1024 y
JSON8MiB, junto a J sobre el token completo. Un resultado hijo pos-hook que no cabe
se retiene como omisión explícita y bloquea resume, no se reconstruye ejecutando el
hook. Materialización y handles host siguen las salvedades de retención anteriores;
estas proyecciones no prometen hard RAM predecode.

Evidencia inicial: público hijo pendiente+hermano confirmado, dos hijos/profundidad2,
colisiones de call ID, precios por ancestro, límites intermedios/raíz, corrupción
bidireccional, espera más allá del lease, dos resumers y muerte de owner con
reconciliación tool en el nodo correcto. Focal integrada raíz/Scope/Server/Session:
81 pases, seed37556, exit0. La matriz de fallos/cotas y la revisión independiente
continúan; Model incierto/retry explícito y distribución no quedan aceptados por
este vertical. No bump/publicación ni cambio de ReqLLM stock.

#### Recuperación Model y retry explícito R55 (2026-09-27, revisión pendiente)

**Corrección causal de review del árbol.** El probe independiente conservó journal
Model y approval de un hijo pero eliminó nodo/ledger de forma internamente coherente;
resume repitió la primera request del hijo. Owner reprodujo3/4 antes del fix. La
validación ahora recorre también journal/approvals→nodo/request/ledger, no sólo la
dirección contraria. Un contexto virtual de hijo conserva su raíz confiable mediante
un campo interno no representable en JSON, nunca mediante una bandera persistida
que pueda desactivar validación. Probe exacto4/4 y regresión permanente verifican
rechazo preIO; no equivalen a revalidación independiente, actualmente bloqueada.

**Model confirmado por el host.** `Continuation.reconcile_model/5` recibe Response
efectiva pos-hook y `model_data` portable, más agente/config/codec confiables del nodo.
Comprueba refs, historia, inventario, roundtrip del codec, perfil/output y
`Model.validate_resume` antes de escribir; no llama Model ni after-model. Una
respuesta faltante no se infiere de la plantilla. Permite recuperar tanto un intent
incierto como un resultado conocido cuyo estado portable no quedó disponible.
Usage se sustituye por identidad de operación, sin nuevo request ni repricing de
datos confirmados. Coste faltante sigue unavailable/partial; evidencia contable
opcional exige exactamente los ancestros del request y las mismas métricas base.

**Decisión de riesgo explícita, confirmada por coordinador.** Hay dos conceptos:
incertidumbre activa que bloquea cursor, y evidencia histórica incierta retirada
de ese bloqueo sólo por autorización host inequívoca. `get/2` devuelve bindings en
`retryable_effects`. `retry_effect/4` exige ese binding, actor/authorize, operación,
revisión y `accept_duplicate_risk: true`, junto a key host no secreta ASCII visible
de1..512 bytes. El enlace conserva literalmente intent/outcome originales e identifica
el nuevo efecto. Se liga al receipt exacto de autorización, incluyendo namespace,
lifetime/run/nodo/efecto, intent hash, actor, revisión y key; ciclos, huérfanos,
cambio de key de una cadena ya keyed o mutación del enlace se rechazan.

La decisión no ejecuta IO. Resume necesita claim y begin_effect ACK frescos; el
replay de un receipt nunca los sustituye. Model persiste frame/contador/intent en
una sola transición extendida begin_effect, evitando un estado intermedio ambiguo
de request admitida sin intent. Su input efectivo portable (proyección, instrucciones,
settings de generación, inventario y fingerprints) queda en el intent, medido con
el resto de R/J/JSON. Esto puede agotar antes la cota en historias grandes; no se
evacúa evidencia para admitir más IO. Retry restaura ese input sin repetir
before-model; timeout/deadlines siguen sujetos al Scope. Root1 conserva su lector
y migra a frame2 antes de nuevas mutaciones del runtime.

Cada retry Model consume una request nueva. Cada retry Tool reserva un sub-batch
de una call contra todos los ancestros, identificado en `scope2.retry_batches`;
no vuelve a debitar el batch histórico. La Usage de cada intento contribuido tiene
identidad propia; una contribución anterior no observada permanece desconocida,
sin estimador ni coste cero inventado. `effect_attempts` cuenta intents de despacho
confirmados del host, no prueba ejecución externa. Activo gastado y expiry no se
reinician por aceptar riesgo. La fila sigue acotada por nodos/efectos/receipts/J/JSON.

La key se entrega en `RunContext.idempotency_key` (tools con contexto) y
`ModelRequestParameters.idempotency_key`. ReqLLM stock usa la opción pública
`req_http_options.headers` para `Idempotency-Key`, sólo en el perfil cualificado
Chat. TCP sintético prueba buffered/stream reales; otros perfiles y caracteres de
control rechazan preIO. No se afirma que el proveedor deduplique, especialmente si
el intento original no llevó key. No hay retry por lease ni fallback de transporte.

Resultados, consulta y eventos terminales exponen `historical_uncertainty` acotada.
El original no se convierte en succeeded/reconciled por éxito del nuevo intento.
Start/prune no pueden eliminar esa evidencia por accidente: requieren el ACK host
adicional `acknowledge_history/3`, ligado al hash del conjunto retenido y
`allow_evidence_deletion: true`. Reconoce permiso de eliminación futura, no la
resolución del efecto, y no borra por sí mismo. Se conserva la salvedad R4 de
deduplicación después de borrar evidencia.

Alternativas descartadas: reutilizar receipt/lease para reejecutar, marcar el efecto
original como exitoso, reconstruir input con hooks o cambiar su payload bajo la
misma key. Impacto major: campos aditivos en parámetros/contexto/resultados/query y
nuevas operaciones administrativas; callbacks ordinarios conservan key nil.
Migración y alcance están en la guía. Evidencia owner: Model2, retry/HTTP9,
compileforce91 y **suite908/0/28 seed37556 exit0** en el checkpoint a371.

**Gates posteriores, sólo tests/fixtures/docs:** dos VMs reconstruyen árbol depth2
desde bytes, con11 entradas de journal una vez y precios10→43. Compuestos Server
stream/cola/eventos, Session/restart/turno único, deny/cancel/reset y native por nodo
con retry Ecto pasan. Dos Models hijos inciertos se reconcilian separadamente. Cota
J pública72268/J−1 antes de Model hijo; JSON+cleanup y1024receipts exactos, incluidos
crecimiento de autorización retry y before/after ACK de nuevas transiciones.
Compile92/suite921/0/28 y consumidores candidato mínimo6/runtime106/extensible30/
SQLoptin12 pasan;117 módulos por perfil proceden sólo del TAR. Son grafos copiados,
no resolución limpia/G5 ni SQL/G3 real. La matriz owner archivada separa evidencia,
rojos de fixtures y límites. Review integrada sigue bloqueada; no C7 aceptado.

### 8.35. Admisión de argumentos finales sobre ReqLLM stock (2026-09-27)

**Problema demostrado y autorización.** La API pública Model sobre TCP stock1.24
rechaza como `invalid_tool_arguments` un sobre final válido cuando el primer delta
contiene `""` o `{`, aunque los controles nombre-solo/JSON completo funcionan.
ReqLLM conserva `invalid_arguments`/`unparseable_arguments` del fragmento inicial;
su contrato público no demuestra que sean invalidez terminal normativa. La
aclaración contractual fechada en el archivo conserva evidencia e interpretación
corregida. El usuario autorizó adaptar la admisión sin fork ni upgrade; el
coordinador confirmó la política fail-closed de errores explícitos antes del cambio.

**Contrato host elegido.** Se consume una sola Response final materializada por
`process_stream/2`. Los dos flags son diagnósticos conservados, no un veto autónomo:
la admisión exige JSON final estricto, sobre obligatorio, JSV lógico y exterior,
terminal válido, identidad y autoridad existentes. Cualquier valor **no nil** en
`:error` **o** `"error"` de `ToolCall.metadata/1` rechaza `invalid_tool_arguments`,
incluyendo `args_lost`, `missing_fragments`, errores desconocidos, `false` y `""`.
Las dos claves se comprueban independientemente; nil en una no oculta la otra.
Es política ExAgent, no una atribución de intención normativa a ReqLLM. El accessor
stock devuelve mapa y normaliza metadata de otra forma a `%{}`: no prometemos
recuperar una forma perdida por ese accessor ni inspeccionamos campos privados.
Metadata adicional debe seguir siendo JSON portable; el rechazo existente de datos
no portables permanece. No se borran diagnósticos para maquillar historia o trazas.

**Beneficio/alternativas.** Fragmentación normal deja de decidir arbitrariamente
la ejecutabilidad de la misma llamada lógica. Validar sólo el mapa final o usar
`ToolCall.resolve` con schema raw no detecta fallback con pérdida: JSON completo
seguido de whitespace o basura puede conservar un mapa válido con `args_lost`.
Rechazar sólo ese tuple permitiría errores explícitos desconocidos portables; se
elige fail-closed sin otro modo configurable. No necesitamos resolver dos veces,
ejecutar callbacks stock, reconstruir wire ni añadir otro materializador.

**Impacto/migración.** Cambio de admisión de la major en preparación: una llamada
final válida con flags históricos puede ejecutarse; pérdida explícita ahora devuelve
`invalid_tool_arguments` de forma directa en vez del rechazo incidental de metadata
tuple no portable. Consumidores no deben usar esos flags como oráculo de resultado
final. Codec2/envelope1, args lógicos, Ecto, hooks/permisos efectivos, C7/CAS/Scope,
límites J/JSON/retención y cleanup permanecen. No se migran snapshots ni se repiten
efectos; nominal1.3.0 y lock stock1.24 se conservan.

**Verificación requerida.** Rojo público previo y verde con mismas identidades;
positivos nombre/vacío/prefijo/completo/buffered, historia exactamente un sobre,
efectos contados, Ecto y aprobación/reanudación; negativos JSON/schema/pérdida,
errores explícitos/alias, terminal/IDs/autoridad y cleanup. Review fresca y G2 live
recalifican esta admisión por separado; la suite offline no acepta proveedores.

### 8.36. Explicit non-reasoning execution and persisted Model binding (2026-09-27)

**Approved before implementation; scoped offlineb609 accepted after fresh review.** The
public stock1.24 option experiment (16 attempts/9 TCP/7 pre-IO failures) demonstrates
that truthful reasoning-capable OpenAIChat models can request `reasoning_effort:none`
without a new provider or parser. Canonical max_tokens triggers a stock rewrite
warning rejected by on_unsupported:error; the public max_completion_tokens provider
option avoids that warning. Luna motivates the case; no model ID is hardcoded.
Mandatory-reasoning models and targets without explicit none support stay excluded.

**Instance contract.** `reasoning_mode: nil | :none` is explicit; nil preserves
existing behavior. None requires the existing qualified OpenAIChat/tools profile,
truthful reasoning.enabled=true, effort.supported=true with `"none"` among values,
and thinking.disable_supported=true. Trusted hosts project current catalog evidence
into these capabilities; optional reasoning alone is insufficient, and mandatory
reasoning must never be projected as disable-supported. Effective supports_thinking
is false. Exposed reasoning content/details remain rejected, including native+tools.

For none, ModelSettings.max_tokens remains the only output-limit authority:
1..4096, default4096, mapped internally to public provider_options.max_completion_tokens.
The canonical key is omitted; no arbitrary provider options, raw overrides, hidden
retry or on_unsupported downgrade. Temperature must be nil; explicit values reject,
not disappear. Invalid mode, incompatible profile/capabilities and settings fail
pre-IO. Ordinary nil-mode defaults are unchanged.

**History and persisted binding.** None responses write message continuation v3,
with top-level reasoning_mode="none" and unchanged envelope1. Readers1/2 remain;
none never adopts older response history by inference, and changing mode/target or
current capabilities rejects before IO/effects. A response marker alone cannot bind
an uncertain first request without history. Therefore an optional generic no-IO
`Model.continuation_binding/1` returns `{:ok, portable_json}` or an error; absent
callbacks default to `{:ok,nil}`. Values are limited to4096 JSON bytes after normalizing
keys; exceptions/invalid values become invalid_model_continuation_binding and overflow
model_continuation_binding_too_large. No full value/config is placed in errors/events.

ReqLLM nil mode returns nil; none returns a deterministic versioned binding of the
effective target, profiles, mode and relevant current capabilities, excluding auth,
secrets, counters and irrelevant effort-list order. This is an opt-in stronger
configuration guarantee, not a retroactive defect claim about app codecs. Bindings
are checked against the current trusted template before app-codec load and against
its returned model afterwards: a codec cannot hide a changed target/mode/capability.
All nodes, approve/resume, reconciliation/retry and pre-first-response uncertainty
use existing restore/admission boundaries; no independent execution engine is added.

**Versioning and budgets.** New captures use Frame3, each node containing model_binding;
root frames retain children and Scope2, child frames retain their local Scope1 data.
Legacy root1/tree2 is readable only when the current binding is nil; a binding-aware
model rejects missing legacy evidence as continuation_model_binding_changed.
Abort2 similarly adds binding to the non-executable abort frame; abort1 reads only
with current nil binding. Snapshot4, scope formats and envelope1 remain unchanged.
Binding bytes count in existing aggregate J/JSON and per-tree cleanup reservations;
4096B/+1 and exact aggregate boundaries need tests. Data-only retry_save replays its
original command exactly: it does not rewrite old frames or call Model/callbacks.

**Alternatives/migration.** A mandatory ReqLLM-specific app codec would couple Frame
to a provider and could be bypassed by a codec reconstructing a changed template;
an optional generic binding callback is smaller and reusable. Hiding mode in generic
metadata or downcasting versions would let old readers silently discard the new
contract. Old readers must reject Frame3/Abort2/continuation3; existing nil-bound
legacy data is read deliberately, never used to infer a none execution. Consumers
enabling none need current capability evidence, absent temperature and updated
readers; apps still own codecs/refs/auth and side-effect reconciliation.

**Required evidence.** Public stock TCP/settings/tool/Ecto/native/history plus
zero-effect capability/reasoning/terminal/loss negatives; persisted approval and
first-request-uncertain mode/endpoint/target changes with an empty app codec;
matching positives, legacy custom/root1/tree2, child bindings, abort/reset and
binding/aggregate budget/retry-save boundaries. New freeze, fresh review and live
G2 are separate from accepted admission2a74/TAR3c180 and cannot reuse their verdicts.

### 8.37. Public incomplete terminal takes precedence over projection failure (2026-09-27)

**Scoped offline acceptance:** independent review/coordinator accepted source dda4
with focal55, independent16 TCP and native guards; portable qualification tooling
is a separately reviewed scope. No live Luna terminal is inferred by this receipt.

**Causal evidence/approval.** A six-request stock TCP comparison exposes finish
length and normalized usage with truncated tool arguments/args_lost, while ExAgent
classified only invalid_tool_arguments and lost the terminal classification. A
valid-arguments length control already returned incomplete_response:length and a
validated partial; tool_calls+truncated must still reject invalid_tool_arguments.
This reproduces a host error-priority problem, not proof about every live response.
The Luna live length-stream case remains unqualified: a separately authorized stock
diagnostic returned tool_calls and cannot establish the original response's finish.

**Narrow approved contract.** Any public final finish other than stop/tool_calls
has primary reason `{:incomplete_response, finish}`. The adapter attempts its
existing complete translation once under all schema/metadata/identity/profile guards:
on success, retain the existing validated partial response and qualified usage;
on failure, partial_response is nil, as already allowed. Never infer length from an
argument error, canonicalize invalid calls, strip flags, fabricate usage or introduce
an accounting-only response/new omission marker. Successful finishes use unchanged
normal admission. One public stock materialization and zero incomplete effects remain.

**Impact/migration/alternatives.** Consumers observing invalid_tool_arguments for a
genuinely incomplete terminal must now handle incomplete_response with possibly nil
partial. Usage remains unavailable from an unprojectable partial, rather than an
invented zero. Partial data has its existing error-data semantics; no new guarantee
of executable-history reuse is introduced. A new semantic omission codec or general
error framework was rejected as unnecessary to correct priority. No codec/schema/
snapshot/budget change. Tests preserve exact length-valid/truncated, tool_calls-
truncated, filter/unknown, effect counts, single terminal and cleanup; new delta
review is required and an old live red is not relabeled green by synthetic evidence.

### 8.38. R6: composición host durable sin modelo raíz (2026-09-27)

**Aceptación vigente (2026-09-29):** recuperación acotada `Composition.resume`
aceptada offline: ready9 empty/between/input sin operaciones propias y terminal
texto sin tool-history propia/typed-succeeded admitido; completed data-only.
Incluye fixes P1/P2 y guard post-ACK/observability descritos abajo. Owner FULL1733/
28excluidos/967.8s exit0, review fresca29(2+10+17)+113+3observability favorable y
padre identidad6/6 más mismos15probes/12.6s exit0, no15casos nuevos. Identidades y
recepción en [implementación R6](../development/r6-implementation.md).
Finito abandonado sigue agotado; ilimitado recuperable bajo límites vigentes.
Nuevas autoridades lógicas no capturan lease/budget; deadlines antiguos persistidos
no se amplían. Sin replay/repricing del prefijo, cambio de formato ni migración.
Contadores host exactos y uso normalizado/estimado mantienen distinta cualificación.
No batch/output-retry activo multileaf, raw/uncertain, C7 composiciones, delegación,
router/paralelo, R6 general ni SQL/live/producción; no preempción atómica de callbacks
iniciados. MCP SDK/R7/A9/G4 independientes. Los pendientes inferiores son históricos;
sus rojos P1/P2, harness y sampling10ms no se reinterpretan como pases.

**ACK de intent y dispatch (2026-09-29; aceptado en el subset anterior).** Dos probes
independientes retienen el ACK real de `begin_effect` hasta vencer presupuesto o
lease: el timeout calculado antes del journal permitía entrar en Model después
de expirar. La comprobación tras la respuesta llegaba demasiado tarde. El loop
revalida el Scope efectivo original∩actual∩intento después del ACK y de callbacks
de observabilidad, inmediatamente antes del dispatch buffered/stream. Reduce el
timeout al restante del mismo deadline; no vuelve a admitir ni renovar la reserva.
Un ACK confirma el intent, no concede autoridad temporal nueva. Si ya expiró,
RunError conserva el parcial y el intent durable sin outcome, refund o replay.

Beneficio: la espera de persistencia no amplía permiso de IO. Se descartan checks
sólo pre-ACK/postrespuesta y reiniciar el timeout. Bugfix del motor compartido,
sin API/formato/migración; consumidores siguen manejando `deadline_exceeded` y
recuperación explícita de incertidumbre. No promete preempción atómica de callbacks
ya iniciados. Regresiones cubren run/resume/stream, expiración budget/lease y timeout
restante positivo. Tools mantienen su timeout de tarea ya existente: expiración
con ACK retenido impide callable en los seis casos probados, y tres controles
positivos sí lo ejecutan; no se atribuye a tools un defecto no reproducido.
Evidencia, rojos conservados y gates finales en R6 implementation: FULL1733pases/
28excluidos/967.8s exit0, compile107WA/formato/diff0; aceptación aparte.

**Corrección de review P1/P2 (2026-09-28; hito previo a aceptación).** El review
reprodujo IO de A tras retener `on_writer`601ms con reserva600ms: restore calculaba
`now + reserved_ms`, mientras el descriptor normal usaba `Writer.started_at`.
Writer fija ahora un único deadline monotónico al ACK fresco, con el mismo origen
que elapsed/refund y la intersección lease/TTL/deadline persistidos. Activa y sucesores
usan ese valor; owner, codec/preparación y preflight revalidan al salir antes de
admitir la siguiente fase/IO. No se interrumpe ni revierte un callback ya iniciado.
ACK retenido sigue limitado por lease/TTL/autoridad; el presupuesto activo empieza
al recibir ese ACK, no se reinicia al preparar la hoja. CAS/fencing no sustituye
el control de presupuesto elapsed. Autoridades antiguas y budget abandonado intactos.

El segundo caso aceptaba claves root con valores inválidos y consumía el claim
antes de que Authority.intersect lanzase una excepción. Resume reutiliza antes de
CAS el validador estructural de Scope que run ya aplicaba: mismas razones
`invalid_usage_limits`/`invalid_execution_scope_options` en RunError, sin mutación.
También conserva `structural_scope_requires_model_aware_estimator` para estimador
de aridad1, sin invocarlo; la validación genérica no estructural permanece intacta.
No valida contenidos de permisos con reglas nuevas ni usa rescue/refund reparador.
Beneficio general: admisión temporal coherente y errores conocidos antes de adquirir
autoridad durable. Se descarta reconstruir la reserva, confiar sólo en lease o
compensar claims inválidos. Bugfix experimental, sin cambio de formato ni migración
de datos; consumidores deben manejar RunError y contabilizar preparación dentro
del presupuesto del intento. Rojo3/10→verde10/10 de probes intactos y regresiones
permanentes, incluido rojo→verde del estimador estructural; gates finales/limitaciones
en R6 implementation. Cierre worker2026-09-29: FULL1716pases/28excluidos/948.9s,
exit0, compile forzado107WA/formato/diff exit0 y fuente runtime/tests296/296
intacta tras FULL. Review fresca requerida; estos gates no son aceptación.

**Recuperación experimental implementada (2026-09-28; hito previo a review).**
`Composition.resume(definition, reference, opts \\ [])` continúa el mismo journal
con un claim/attempt nuevo y un único Writer/Scope. Referencia plana exacta con
version===1, id/record_id/revision/run_id y attempt_id opcional de correlación;
no token ni refresh silencioso. Opciones estrictas idénticas a run. El host debe
llamar recover administrativo explícitamente tras vencer el lease. Presupuesto
finito abandonado sigue agotado; no refund/reset ni ampliación de TTL/autoridad.

Problema demostrado: el ejecutor durable podía producir un prefijo confirmado pero
no continuar su sufijo. Se reutilizan loop, CAS y ScopeLedger exacto, frente a replay
global o un ledger paralelo. Empty/between/input confirmado, texto terminal seguro
sin tools propias y typed-succeeded actual admiten recuperación Frame9 multileaf.
Prefijos completed pueden contener tools/retries; no codecs, Model, callbacks ni
repricing históricos. El helper Scope instala atómicamente nodos cerrados no
estructurales, sin handles/monitores ejecutables; IDs/owner/raíz/árbol exactos.
Sólo raíz y activa aportan deadlines de admisión; un deadline histórico cerrado no
impide el sufijo. El lease/budget del intento se comprueba en Writer y no se captura
como deadline lógico raíz de nuevas ejecuciones. Autoridades antiguas conservan su
significado; no se reinterpretan filas previas para ampliar permisos.

Claim ACK precede callbacks/codec/mapping/IO. Input confirmado no se remapea; mapping
sin checkpoint puede repetirse y debe ser puro. Claim ACK perdido devuelve baseline
preclaim, token real y subtotal partial. Tras claim sólo ACKs recibidos, nunca lectura
Store para simular progreso. El deadline raíz actual participa en el CAS; un ACK
recibido tras vencer lease/TTL/deadline activo no autoriza callbacks nuevos, aunque
el claim confirmado sí forme parte del parcial. Completed es data-only sin claim/Scope/callbacks, incluso
con tiempos pasados mientras Store conserve la fila. Errores mantienen las fases
open/prepare/mapping/execute/checkpoint y output omitido no se presenta como éxito.
API aditiva experimental para major pendiente, sin formato/migración ni publicación.
C7/delegación/raw/uncertain/output-retry o batch activo multileaf siguen cerrados;
subsets singleton7/8/9 conservados. Evidencia nueva en R6 implementation, separada de
la aceptación previa de run; no aceptación automática de recovery ni R6 general.

Verificación owner final:33casos nuevos; FULL1706pases/28excluidos/933.0s exit0,
compile forzado107WA y formato. Incluye corrección temporal probada rojo→verde
con Store CAS/ACK retenidos. Requiere revisión independiente del delta integrado.

**Base aceptada (2026-09-28, anterior a resume):** `Composition.run/3` secuencial durable aceptado
offline con un único Scope/Writer/claim/presupuesto, mapping confirmado y refund
raíz sólo final. Inspección completed multileaf data-only; lifetimes7/8 y subsets
single-leaf9 conservados. Review favorable y probes padre recibidos; evidencia
exacta en [implementación R6](../development/r6-implementation.md). No restore
activo multileaf, C7 de composiciones, raw/uncertain, delegación, router/paralelo,
R6 general ni producción. Los hitos preparatorios inferiores conservan su fecha.

**Corrección causal Frame9 (2026-09-28, aceptada offline).** Dos reproducciones
independientes mostraron admisión de B confundida con mapping y pérdida del Writer
en un caller trap-exit escapando como excepción de acceso a mapas. El descriptor
conserva la razón acotada de Scope/cuota/deadline/capacidad; sólo fallos genuinos
del mapping/normalización/retención del input son `invalid_composition_input`.
Deadline previo y posterior al mapping informa `prepare`, sin adjuntar B.
La proyección distingue los errores de ambas lecturas Writer y de apertura:
`continuation_owner_lost` devuelve RunError con el último record efectivamente
recibido, token nil y usage partial. Si sólo falla pending, el record recibido
antes sigue siendo confirmado; si no hubo ninguno, el prefijo es desconocido/vacío.
No se consulta Store ni se reconstruyen tokens desde outputs vivos; tampoco se
cancela, reembolsa o repite IO. El caller sin trap-exit conserva la muerte enlazada.
Beneficio: diagnóstico operacional fiel y parciales verificables. Se descarta
rescue global y lectura Store-only porque ocultarían bugs o inventarían ACKs.
Impacto/migración: bugfix de API experimental para la major pendiente, manejar razones originales
de admisión en lugar de invalidinput; sin cambio de formato ni migración persistida.
Regresiones cubren quota/deadline vs mapping, razones grandes, pérdida en apertura,
mapping/Model B y ambas lecturas separadas. El probe original conserva su rojo4/5;
sólo una copia autorizada corrige la razón esperada. Review y padre verificaron
esa copia y dos probes terminales, sin ampliar la aceptación a R6 general.

**Frame9: API experimental aceptada offline (2026-09-28).** El seam interno
obligaba al host a poseer Scope/Writer y podía confundir un resultado vivo con un
checkpoint confirmado. `Composition.run(definition, input, opts)` añade la entrada
experimental durable, fail-fast, sin otro motor. `continuation` es obligatorio;
kind/composition/definition se derivan del host y las contradicciones rechazan.
`root_options`, `step_options` por ID, `observability` y `trace_context` son las
únicas opciones superiores. Duplicados, IDs/claves desconocidos e inyección de
scope/historia/identidades/frames/continuación interna rechazan antes de IO.

Un único Scope/Writer/claim recorre la definición mediante el loop existente.
El resultado y token se capturan antes del cleanup en `after`, también al fallar
create/claim. OTel existente recibe span raíz sin Model ficticio y hojas hijas;
el attempt se obtiene del claim confirmado (receipt al quedar released).
No se persisten contextos ni se suman métricas de generaciones como otro consumo.

Proyección común con inspección completed: raíz sin modelo ni historia viva,
steps ordenados con input/output/omisión/historia confirmados; contadores/usage
del ledger ancestral, sin sumar snapshots hoja. Accounting rechazado conserva
partial; fallos execute/checkpoint se proyectan conservadoramente como subtotal
partial, nunca como actividad completa. `RunError.partial` mantiene output raíz
nil, error_step_id/error_phase y estados not_started/running/completed confirmados.
El último output omitido es error público aunque el cursor durable sea completed.
Retención/token usan mecanismos existentes; retry del token sólo escribe Store.

Impacto/migración: API experimental aditiva para la major pendiente, configuración
Writer explícita; sin migración persistida ni nueva API resume. La inspección
interna completed devuelve ahora el mismo resultado ampliado. Se descarta un modo
efímero alternativo, sumar resultados vivos y cancelar/refund para fingir terminal.
Pruebas nuevas incluyen API texto/typed/tools, parciales y ACK, VM data-only,
tracing y owner kills. La matriz de capacidad añade límites públicos Writer±1,
JSON completo+cleanup±1 y token±1 sobre comandos de secuencia reales. Receipts
adicionales proceden de node_checkpoint CAS, no de mapas fabricados. OutputA
consume una reserva: el predecesor sobrelleno se rechaza antes del cierre, que
sigue cabiendo en el horizonte exacto. Cancel de intentB conserva incertidumbre
y presupuesto sin refund; no inventa outcome para aparentar cierre. Metadatos
inertes acotan los probes de bytes; no son un nuevo productor/API de payload.
Gates y recepción independiente se detallan en implementación R6.

**Frame9: vertical durable aceptada offline (2026-09-28).** Nuevas
raíces usan9; lectores y escrituras de lifetimes7/8 conservan su versión. El mismo
Writer/Scope/Store ejecuta ahora A→B→C mediante el seam `run_composition_step/4`.
Descriptor/ticket ligan PID, revisión e índice; attach añade una hoja y consume el
ticket antes de CAS. Mapping recibe únicamente outputs portables confirmados por
step ID. Entre pasos conserva claim, lease y presupuesto; sólo la última hoja
reembolsa desde el claim raíz y libera ejecución. Record exige terminalidad iff.
Frame/Transition preservan hojas completadas y ligan node_id a la hoja activa.
Productor, accounting partial y reservas reconocen9 explícitamente; las reservas
de nuevas hojas incluyen el prefijo retenido sin reescribir snapshots completados.

Restore activo N>1 rechaza por cardinalidad del binding antes de claim/callbacks;
completed multi es data-only validado con binding/policy host exactos. Ask y
delegación estructural permanecen fail-closed. No hay opción pública de versión,
relabel de fixtures ni migración de datos. Beneficio: ejecución durable secuencial
sin motor/ledger alternativo ni outputs vivos como autoridad. La API/proyección/tracing
se integran arriba; la aceptación incluye revisión y probes padre, no sólo focales.
Evidencia, matriz y límites en implementación R6; R6 general sigue abierto.

**Histórico Frame9: hito preparatorio de validación (2026-09-28).**
El singleton actual no representa prefijos A→B→C; además, comprobar toda la
evidencia output/tool contra cada hoja rechaza evidencia válida de sus hermanas.
El contrato aprobado conserva las claves raíz8 en9 y añade el cursor
`between_steps`: children es el prefijo exacto del binding, con índices enteros,
refs/enlaces exactos, anteriores completed y una última hoja running o completed.
Una omisión permite cerrar la hoja pero bloquea sucesora; nil portable es válido.
La validación Frame9 es explícita, sin degradar el frame completo a singleton7/5.
Scope/authority cubren exactamente raíz y hojas; la raíz no tiene IO propio.

Este hito implementa sólo esa validación estructural y particiona evidencia por
hoja conservando cobertura global de modelos/tools/output, requests host únicos
y call IDs de proveedor reutilizables. Filtrar sin cobertura global perdería
huérfanos; duplicar el motor o inferir outputs vivos contradice la continuación
confirmada. Los tests de estructura no sustituyen Record/evidencia/transiciones.
El productor sigue en8 y Record/Writer todavía no admiten lifetimes9: no es una
opción de ejecución ni una migración habilitada. La integración pendiente debe
conservar lifetimes7/8, reservas, autoridad, refund raíz único y ACK antes de IO.
Sin bump/publicación ni nueva API; aceptación del secuenciador pendiente.
Evidencia owner:31 pruebas nuevas y focal523 WA48seed37556, exit0, detalladas en
implementación R6. El grafo de evidencia compuesto en tests usa hojas reales
independientes; **no demuestra A→B→C bajo un Writer** ni restore multileaf.

**Restore Frame8 final/control (2026-09-28, aceptado offline acotado).** Dos
fixtures Writer8 auténticas reproducen `unsupported_composition_boundary` para
prefijo consumido→texto y batch actual resuelto. El consumidor selecciona primero
cursor/request actual; una atestación histórica no elige la rama actual. Sólo una
hoja, sin approvals, planes, incertidumbre ni delegación. Todos los batches deben
tener observaciones aceptadas y control final; los prefijos deben ser continuables.
El batch actual consume returns confirmados ordenados, con el reductor existente
desde el contador anterior y contraste del postcontador persistido. Rehidrata
tool_calls del prefijo y suma el batch actual una vez. Fatal portable (incluido
agotamiento seguido de success) permanece fallo; no reconstruye excepciones BEAM.

Esto permite recuperar trabajo confirmado sin repetir permisos/hooks/callables,
settle, resolución ni contribuciones históricas. Scope2 sigue siendo fuente de
accounting cualificado, sin repricing. Nueva IO sí requiere autoridad original∩actual,
admisión/deadline vigentes y los seis contadores runtime-owned entre hooks. Menores
quotas no invalidan cierre/fatal histórico. Selección efímera protege fail ante
stubs contradictorios hasta append exitoso. No nuevo formato/API/migración: legacy7
con tools permanece bloqueado. Se descartan replay de batch y saved→false/nil por
perder control. Configuración host/fingerprint/Model.validate_resume siguen activos
también para fatal tipado: errores de preparación conservan evidencia y pueden
preceder su consumo. Matriz99casos y focal261pases, con comandos/identidad en
implementación R6. Ambos negativos obsoletos fueron actualizados con autorización;
el FULL posterior detectó una assertion ajena MCP sobre motivo DOWN. Bajo autorización
se corrigió sólo su oracle y se añadieron dos regresiones de orden; runtime intacto.
FULL owner final1568pases/28excluidos/716.8s exit0, separado de review50casos
distintos (43focales+3probes independientes+4adyacentes), sin P1/P2 reproducible.
Padre cotejó source12/12 y reejecutó los3probes intactos WA48seed37556, exit0/9.3s;
acepta sólo single-leaf Frame8 final/control y prefijos continuables. Informes y
hashes en [implementación R6](../development/r6-implementation.md). No nueva
transición terminal para un fatal restaurado. Raw, uncertain, no-control,
rejected/omitted, legacy7 con tools, approval/retry-plans, delegación/A→B y R6
general siguen fuera; no cualificación SQL/cloud/live.

**Productor Frame8 accounting/control (2026-09-28, aceptado offline).**
La unidad añade `tool_batches` a las nuevas raíces, con límites por
request, observaciones independientes del ledger anteriores a retención y control
postsettle. Raw, observación y Scope se confirman juntos antes del ACK; el control
posterior no ejecuta ni contribuye otra vez. Usage inválido/omitido/noportable debe
rechazarse antes de aplicar external, conservando diagnóstico durable y subtotal
aceptado con proyección inequívocamente partial. No se modifica Scope2 para ocultar
omisión. Message/Outcome1/RequestData1/Record2 conservan sus formas.
Beneficio: cerrar los gaps de evidencia sin inferir datos desde hashes que omiten
usage ni reconstruir control desde statuses. Legacy7 mantiene su versión durante
su lifetime; no migración/relabel ni modo público adicional. Nuevas raíces sin tools
conservan las fronteras aceptadas. El productor por sí solo no habilitó restore
con tools; la excepción final/control aceptada se delimita arriba.
La ficha exacta está en `../orchestration/2026-09-28-native-f19085/tasks/tool-evidence-producer.md`.
Preflight detectó una discrepancia de alcance: `CompositionRestore.boundary/1`
rechazaba toda versión distinta de7 antes de clasificar completed/input/response;
ese módulo no figuraba en la lista runtime autorizada al owner. Se pidió incluir
únicamente su discriminación7/8, preservando guards de tools/prefijos/batches.
Padre autorizó explícitamente ese seam7/8; bloqueo resuelto. Completed continúa
data-only, incluso con efectos históricos, sin convertirlos en permiso de ejecución.

Forma exacta: mapa digest([run_id,request_id])→batch
`{run_id,request_id,limits,observations,resolution}`. Limits nombre→
`{schema_hash,max_retries}` captura antes de tareas; observations effect_id→
`{origin,presence,usage,application}` distingue ausencia de observación, nil explícito,
Usage cualificado y omitted/rejected. Application es none, contributed con complete
e ancestors, o rejected con PortableError. Complete preserva el predicado histórico
de tokens enteros; no equivale a availability ni factura. El helper crea recibo desde
input antes de ledger, sin autoatestación por export. Scope2 conserva sólo subtotales
aceptados; la negativa de Frame8 impide proyectarlos como completos.

Resolution nula o `{calls,settle_error}`; calls ordenadas contienen únicamente
effect_id/result_hash/retry/error. El reductor aplica límites capturados, consume
errores retry permitidos y conserva primer fatal aunque success borre un contador.
PortableError exacto code/message/details/omitted, UTF8 message≤512bytes y JSON≤4096;
mensajes fijos no serializan excepciones/configuración. CAS de control no cambia
Scope/outcomes/historia/modelo; validación común exige finals y observaciones exactas.
Cambios de evidence rechazan también en otros comandos, no sólo tool_resolution.
Writer7 se retira al expirar los lifetimes existentes, sin modo público nuevo.
Review independiente95 casos (55productor+33contrato+7probes), padre7probes intactos,
WA48seed37556 exit0; source19/19 cotejado. FULL1409/28 sigue evidencia owner.
Matriz, rojos, reservas e identidad en implementación R6. Sólo productor/validator8:
no reinterpreta usage/retry legacy ni habilita restore tools, A→B o cierre R6.

**Contadores runtime-owned ante hooks Model (2026-09-28, aceptados offline).**
Review124focales+8probes, padre8probes intactos WA48 exit0;15/15hashes y delta cotejados.
Informe/identidad en roadmap§5; aceptación de productor, no legacy/restore/R6 completo.
El diagnóstico final-tools demuestra reset before y contaminación after de
tool_retries sobre runs reales; el siguiente callback recibe el valor alterado.
Se preservan exactamente tool_retries, output_retries_used, run_step, tool_calls,
max_steps y agent.output_retries después de CADA capability Model, antes del
siguiente callback, captura, admisión e IO. Escrituras ignoradas restaurando los
valores confirmados; sin API de override ni error nuevo. Beneficio general: hooks
observan el progreso real y no recargan límites del loop. Normalizar sólo al final
de retained_transform deja contaminada la cadena; congelar agent entero impediría
selecciones legítimas. Mantener overrides requeriría un contrato durable adicional
sin consumidor demostrado. Hooks siguen siendo host confiable, no sandbox.
Impacto incompatible para callbacks que escribían esos campos: major pendiente,
configurar límites al iniciar y retirar dichas escrituras. Modelo, settings, tools
seleccionadas (incluido max_retries), proyección y respuesta válidos siguen libres.
Mapas genéricos conservan su contrato, sin campos inventados ni reparación de
callbacks inválidos. No cambia formato/lector/guard: el legacy persistido sigue
ambiguo y esta protección del productor no prueba integridad CAS de retry/usage.
Verificación owner: cuatro rojos causales antes del fix; matriz44 y focal371 WA48
exit0, compile forzado101/formato0. before/after×seis campos, cadena módulo/struct,
retries/reset, agotamiento, persistencia real directa/composición y transformaciones/
errores. FULL1354pases/28excluidos WA48seed37556 exit0,482.0s; evidencia owner separada
de la review recibida. Detalle en implementación R6.

**Integridad histórica batch/usage (2026-09-28, batch aceptado offline; usage bloqueado).**
Review141focales+4probes, padre4probes intactos WA48 exit0 y manifiesto13/13 cotejado;
identidad en roadmap§5. No aceptación de usage/retry/restore ni R6 completo.
Decode y CAS reales de outcome Model/step_output aceptaban borrar/reducir batches
y sus counts, o contribuciones tool14/22→0/0 o2/2, conservando journal e historia.
Frame estructural liga batches a las calls de cada response consumida por
run/request; output_resolution y siblings virtuales no admiten batches.
Beneficio: decode y todas las transiciones comparten integridad referencial.
Alternativas descartadas: validación sólo en output_resolution, repricing o nuevo
formato; no resolverían el vínculo común preservando datos válidos. Impacto:
bytes estructurales inconsistentes antes tolerados rechazan invalid_step_evidence;
sin migración de datos válidos ni cambios Record1/agentes/raw/retry plans.
**Usage bloqueado:** la premisa del diagnóstico de que result_hash cubre usage es
incorrecta. ToolReturn.usage se excluye explícitamente de Message.to_json; Outcome
usa esa misma codificación y el decoder devuelve nil. Historial/request_data/hashes
no prueban nil/non-nil ni cantidad/procedencia individual; snapshot sólo agrega.
Comparar ledger contra sí mismo no permite detectar borrado coordinado. Se requiere
decidir evidencia persistida por contribución antes de anunciar ese chequeo; no se
introduce formato/token ni se adivina cantidad. No repricing ni obligación para nil.
tool_retries legacy no se deriva de statuses: hooks Model
podían transformarlo bajo el contrato anterior. Guards restore intactos.
Verificación: rojo batch original corregido; usage/retries permanecen rojos conocidos.
Regresiones CAS/decode/atomicidad, controles
nil/quality/múltiples requests y gates completos; review recibida según cabecera.

**Cadena Model confirmada con atestación actual
(2026-09-28, aceptada offline).** Review208focales+7probes, padre7probes intactos
WA48 exit0, manifiesto17/17 y delta cotejados; identidad en roadmap§5, owner FULL1287
separado. No cierre R6/SQL/live. El guard response1 impedía
restaurar cadenas de corrección output ya confirmadas aunque Frame y OutputResolution
validan historia, posición, contador y ledger multipaso. CompositionRestore selecciona la
atestación success/retry del request ACTUAL tras N respuestas Model confirmadas,
sin batches ni efectos tool previos. Retries anteriores y siblings atestados sólo
son historia; pueden incluir Retry sin call, no una atestación obligatoria por paso.
Reusar claim/autoridad/consumo/Writer existentes, sin revalidar argumentos históricos,
reiniciar contadores ni repricing. Configuración host retry compara sólo descriptor
actual; los históricos siguen ligados a sus propias requests. Success data-only.
Alternativas descartadas: habilitar response2/3 por separado, replay general o segundo
validador en el clasificador. Extensión interna aditiva sin formato/token/migración;
cotas generales existentes, sin límite N artificial. Texto multipaso sin atestación,
batches incluso finalizados, incertidumbre, pausa/delegación y A→B quedan fuera.
El rojo causal previo al runtime rechazó cinco fronteras reales con
`unsupported_composition_boundary`. La matriz owner134/0 cubre VM/CAS/ACK/múltiples
interrupciones, evidencia histórica y límites exactos; gates y criterios en
implementación R6. La aceptación tiene review propia, no se deriva de gates response1.
Record.validate sigue siendo el único validador de evidencia antes de clasificar:
todos los efectos deben ser Model confirmed/succeeded/state_available, operaciones
Model, sin batches/retry_batches/outcomes/tool_retries/approvals/plans. Se exige
historia ejecutable y última Response actual; el contador existente incluye Retry
sin call, no se infiere de N ni del número de atestaciones. CallID repetido en requests
distintos es legítimo. Success consume datos; retry conserva configuración host
postclaim/cache/fingerprint/Model y admisión nueva actual∩original. ACK sólo Store;
intent sin outcome sigue uncertain, outcome actual sin atestación sigue bloqueado.
Una atestación posterior confirmada sí es restaurable; completed sigue data-only.
El delta runtime es sólo CompositionRestore; Frame/Writer/OutputResolution/Scope/
Authority/Record y los consumidores ExAgent permanecen intactos. No migración.

**Primera atestación retry confirmada (2026-09-28, aceptada offline).**
Revisión fresca167focales+5probes, padre5probes intactos, WA48 exit0; hashes11/11
y delta cotejados. Evidencia e identidad en roadmap§5, sin cierre R6/SQL/live.
El rojo causal
rechazaba `unsupported_composition_boundary` con una atestación real recuperada.
Sólo response1 sin otros efectos, con evidencia exacta y autoridad original.
Se consume el Retry histórico sin
repetir su validación, pero una request NUEVA requiere configuración host ejecutable:
reflexión/changeset vacío después del claim, comparación exacta del descriptor y
fingerprint, bindings y admisión actual∩original. No módulos seleccionados por JSON
ni garantía de identidad semántica si código/schema conserva sus refs.
La configuración se prepara una vez por intento en estado efímero interno, no
opciones caller; callbacks puros pueden repetirse en otro intento. La reflexión
puede llamar changeset vacío, nunca args1. Se conservan Model.validate_resume y
bindings pre/postcodec. Agotamiento conserva output_retries_exhausted con diagnóstico
portable Retry.content, no errores Ecto reconstruidos. Partes/contador se confirman
junto al intent Model nuevo mediante el Writer existente, sin checkpoint/token/
formato intermedio. Repricing sólo de operaciones nuevas, nunca de historia.
ACK retry sigue siendo sólo persistencia; intent sin outcome conserva incertidumbre.
La protección fail contra stubs contradictorios se elimina tras append exitoso,
antes de respuestas futuras. No arrastra una selección histórica a response2.
En esta primera unidad, restore de request2/response2/retry2/success2 pendiente seguía rechazado (ampliación atestada arriba), aunque el loop
vivo pueda continuar y completed/token step_output sigan siendo data-only. No
promesa de recuperación general después de la segunda respuesta, A→B o R6 completo.
Alternativas descartadas: revalidar args históricos, ejecutar tools inertes como
configuración futura o crear un motor/checkpoint paralelo. Propuesta interna
aditiva de la major pendiente, sin migración/publicación. Runtime acotado a ExAgent
y CompositionRestore; Writer/Frame/Scope/Authority/Record intactos. Matriz permanente
en `composition_output_retry_restore_test.exs` y evidencia owner en
`/tmp/opencode/output-retry-20260928-f18f527a/REPORT.md`:58casos nuevos, focal297,
compile101 y FULL1211pases/28excluidos WA48 seed37556 exit0. Diseño aprobado en la ficha
`../orchestration/2026-09-28-native-f19085/tasks/output-retry.md` del checkout.

**Consumo output succeeded (2026-09-28, aceptado offline).**
Revisión independiente109focales+5probes, padre5probes intactos, exit0; hashes11/11
cotejados. Owner FULL1153/0/28 WA48/compile100/formato0 separado. Informe y límites
en roadmap§5; no cierre R6 ni cualificación SQL/live.
El guard anterior rechazaba incluso una salida Ecto ya validada y confirmada.
Revalidarla al restaurar repetiría tanto el changeset real como el changeset vacío
de reflexión llamado por output_config. Se añade únicamente Frame7 ready/response1,
una hoja running, un Model confirmed/succeeded/state_available y una operación,
con una atestación output1 succeeded portable del request actual. Record valida
primero posición, selección, descriptor/fingerprint y partes/hashes; la etiqueta
succeeded sola no concede autoridad. Sin tools ejecutadas/batches/retries/approvals.
Siblings de la misma respuesta se consumen en el orden exacto ya atestado, no se
ejecutan. Finish nil/stop/end_turn/tool_calls; no terminal fallido.

Binding host versionado (incluido output_ref) y perfil tipado/tool se validan sin
callbacks antes del claim. El descriptor persistido se convierte exactamente a
params descriptivos con tools inertes, sin resolver módulos desde JSON. Ambos
sitios de preparación evitan output_config para una selección efímera interna,
no una opción caller. Después del claim se conservan codecs, preparación de tools
host y Model.validate_resume/fingerprint; sólo el ganador reconstruye. No se
promete identidad del código/schema actual si el host no cambia sus referencias
versionadas, ni se introduce una API alternativa de descriptor host.

append_returns/succeed/Writer.finish consumen parts/result confirmados sin Ecto,
reflexión, Model request, after_model, mapping ni otra output_resolution. Se devuelve
el mapa JSON portable, no el struct vivo; el recorrido vivo conserva su tipo.
Omisión atestada devuelve composition_output_omitted antes del claim. Si sólo la
copia terminal excede capacidad, persisten marker medido y error de retención
existentes; completed no rescata otra copia. Un límite de historia menor que las
partes atestadas devuelve error con historia confirmada, sin inventar stubs
contradictorios ni desbordar otra vez al construir el error.

Alternativas rechazadas: reejecutar validadores, inferir módulos desde datos,
relajar guards para raw/retry/general o añadir un motor/token/formato. Extensión
interna aditiva de la major pendiente, sin migración, bump ni publicación. Scope,
floors, budget, deadlines y CAS no cambian; no repricing/doble suma. Matriz y gates
owner en implementación R6; aceptación independiente limitada a esta frontera,
sin A→B, SQL/live ni R6 completo.

**Slice textual aceptado offline2026-09-28:** reviewer169/0 WA48 con matriz final37,
padre37/0; owner FULL1125/0/28 separado. Identidad/evidencia en roadmap§5.
No atestaciones ejecutables, restore general, A→B ni SQL/live.
Problema demostrado: input0 no permite cerrar una
primera respuesta textual ya confirmada tras perder el owner. Se habilita sólo
Frame7 ready, una hoja response/run_step1, un Model confirmed/succeeded portable
y una operación Scope2, sin tools/retries/atestaciones. Perfil host text/tool y
fingerprint textual se comprueban data-only antes del claim y codecs. Se consume
la respuesta en prepare_run/handle_response/succeed, no por replay ni cierre nuevo.
Scope restaura precios y contribuciones una vez; no request ni repricing histórico.
Alternativas rechazadas: quitar el guard de efectos indiscriminadamente o añadir
otro motor/token/formato. Cambio interno aditivo, sin migración/publicación; legacy
y floors conservan sus contratos. Codecs/binding/registro son reconstrucción
permitida sólo para el ganador CAS, no garantía global de cero callbacks. Matriz
y evidencia en roadmap§5; atestaciones/A→B quedan fuera. La frontera exige historia
ejecutable input+response, texto no vacío y finish nil/stop/end_turn; no calls,
returns, Retry, batches, planes, outcomes ni approvals. Pruebas de VM nueva JSON,
ACKs, CAS, corrupción y límites cubren este slice, no restore general.
Los límites de admisión no vuelven a cobrar historia: request_limit1 consumido
permite cerrar sin request ficticio; tampoco se rechaza retrospectivamente una
contribución por estrechar el presupuesto de nuevos efectos. Deadline, reserva
activa y retención de consumo siguen comprobándose. Los estimadores actuales no
recalculan precios/uso histórico. Un codec no determinista no puede convertir
estado confirmado distinto en un cierre válido.

**Restore input0 aceptado offline (2026-09-28).** Review integral más corrección
del floor actual:171pases independientes; padre46pases, owner FULL1088/0/28 WA48.
Recepción e identidad en roadmap§5. Sólo input0 y completed data-only; no restore
general ni aceptación de las fronteras todavía rechazadas.
Frame5/6 conservaban contabilidad pero no la autoridad original: reconstruir desde
options actuales podía ampliar permisos/límites. Frame7 es el único nuevo writer
estructural (empty/running/completed), con autoridad efectiva capturada del Scope
raíz al create y de la hoja al step_input; el original es inmutable. Record2,
snapshot de identidad composition1, hoja Frame3 y ledger Scope2 no cambian.
Readers4–6 siguen; restore rechaza `composition_authority_missing`, sin migración
inferida. No se acepta un ledger como sustituto de permisos. Uso se intersecta
campo a campo (strict prevalece); políticas son conjunciones, no reglas concatenadas;
concurrencia usa mínimo. Deadline lógico UTC se separa de lease/budget del intento.

Seam interno `ExAgent.resume_composition_step(definition, reference, opts)`:
`:continuation` contiene Store/ID/referencias/lease y `:root_options` las restricciones
actuales de la raíz; las demás opciones son las actuales de la hoja. Reference liga
ID, record_id y revision. Preflight data-only valida binding, autoridad y retención.
Sólo ready, input confirmado request/run_step0, cero efectos/operaciones, una hoja
se ejecuta: claim CAS fresco antes de codec/registro y mismo loop/Writer/Scope.
No vuelve a mapear input. Claimed exige recuperación administrativa explícita tras
lease; abandonar una reserva no la devuelve ni recarga presupuesto. Completed sólo
devuelve `%{status: :completed, output: portable}`; omisión devuelve
`{:error, {:composition_output_omitted, marker}}`, sin claim ni callbacks.
Errores de preflight son tuplas; errores del loop conservan RunError. Otras fronteras
rechazan `composition_not_ready`/`unsupported_composition_boundary` antes de callbacks.
No empty, response, raw, atestación pendiente, aprobación, reconcile, A→B o delegados.
Alternativa descartada: ampliar resume agente/relajar Record2 o reejecutar history.
Es contrato interno de major pendiente, no publicación ni restore general. Los gates
y evidencia actual se registran en implementación R6: owner compile99/formato0,
focal123/0 y FULL1072/0/28 WA48 seed37556. Revisión fresca obligatoria.

**Recepción2026-09-28:** PASO ÚNICO aceptado offline tras revisión integrada y
fix de cardinalidad Frame6 en Record.tree_children. Review72/0 con siete probes
intactos; padre35/0, owner FULL1043/0/28 WA48. Reservas y límites exactos conservados.
Evidencia identificada en roadmap§5. No restore ejecutable, A→B, SQL/live ni R6
completo; los pendientes de review de los hitos inferiores son históricos.

**Unidad contractual de evidencia (2026-09-28, aceptada en el alcance anterior).** La revisión
posterior reprodujo dos regresiones: reserva de dos tools running con current
sintético incoherente, y output tipado confundido con dispatch. Un negativo nuevo
reproduce además Retry con call_id fabricado. No se relajan guards ni se conceden
excepciones por nombre/status: cada resolución de call tiene procedencia.

Se introduce Frame6 sólo para el contenedor estructural con `output_resolutions`;
Frame3 de hoja y Frame5 sin output siguen sin campos nuevos. Cada atestación
output_resolution_version1 liga run/request, descriptor portable (preimagen del
output_fingerprint de RequestData), primera output call y conjunto/orden exacto
de siblings, decisión succeeded/retry, bytes/hash de partes y resultado portable
o marcador de omisión. Se emite tras validación host, nunca por dispatch ficticio.
La transición `output_resolution` añade una entrada inmutable y conserva snapshot,
hoja y journal: ese intermedio explícito sólo permite la respuesta confirmada aún
sin sus returns. El siguiente request/finish exige los bytes atestados en historia;
decode no ejecuta Ecto, hooks o codecs. J/JSON/token acotan descriptor, partes y
resultado. Legacy Record1/Frame1–4 y Frame5 válidos sin output conservan lectores;
no se inventan atestaciones para datos viejos incompletos ni se borra historia.

La reserva continúa validando current y comando: sólo hermanos running pasan a
confirmed en la copia junto con sus outcomes; target permanece running sin su
resultado futuro hasta aplicar el payload. Ningún cambio llega al Scope/Store real.
Alternativas rechazadas: permitir returns sin journal por llamarse final_result,
tratar validation_error como pre-dispatch, omitir current_valid o copiar el frame
futuro completo. Descriptor output-tool limitado a65536 bytes JSON, comprobado con
params efectivos antes de admitir el request Model (el input puede estar ya
confirmado y no se borra). Native/text sin output tools no adquieren ese límite.
La atestación y sus partes/resultados cuentan en J/JSON/token/cleanup ordinarios;
no son una segunda reserva ni un segundo motor. El contador output_retries de
Frame6 coincide con Retry históricos, incluyendo Retry de texto sin call.

Si el resultado validado no es portable, la atestación conserva el marcador y el
cierre guarda esa misma omisión. Si cabe en la atestación pero duplicarlo al cerrar
excede J, el hijo puede omitir su copia: el marker se mide sobre el valor portable
atestiguado, conservado e inmutable. No es permiso de replay ni una salida inventada;
la API conserva el error de retención/omisión. Estas dos fronteras son comprobables
sin codecs. Es evolución interna explícita aún sin publicación; matriz y evidencia
owner en implementación R6; aceptación independiente acotada según cabecera.

**Corrección residual paso→hoja (2026-09-28, revisión pendiente).** Los probes
demostraron que emparejar call/return no prueba ejecución: una respuesta Model
confirmada permitía inventar un ToolReturn, y modificar un return histórico pasaba
decode. Frame5 ahora liga returns históricos y outcomes intermedios al journal por
nodo/request/call, schema/call hash, status y result hash, en ambas direcciones.
Un outcome confirmado requiere bytes correspondientes; un return requiere outcome
confirmado. Se conservan resultados pre-dispatch (denegados/no ejecutados), errores
y marcadores de retención verificables aunque no ejecutables. La reserva de capacidad
usa hashes de sus propios resultados sintéticos, sólo en su proyección de validación.
No basta validar finish: la misma evidencia rige CAS y Record.decode.

Un fallo de codec/capacidad después de join dejaba una hoja vacía huérfana. Writer
retira sólo esa adhesión antes de registrar el nodo o preparar el write; Scope exige
padre/token exactos, cero contadores/operaciones/retries y ningún descendiente.
No retira input confirmado, pending/dirty ni nodos con efectos; no hay rollback de
ledger, autoridad o contabilidad. Owner death conserva el mismo límite. Alternativa
descartada: resetear Scope o liberar sólo el ticket, que pierde evidencia o deja el
huérfano. Es corrección del formato interno no publicado: sin migración de datos
válidos, schema bump ni API run/resume; bytes falsificados antes tolerados rechazan.
Regresiones permanentes y evidencia owner en implementación R6; aceptación
independiente y expansión R6 siguen pendientes.

**Hito interno paso único (2026-09-28), no cierre secuencial.** Sobre la raíz vacía
aceptada y el fix de preflight del padre, <code>ExAgent.run_composition_step/4</code> (doc false)
admite exactamente una definición de un paso mediante un Writer estructural vivo.
No es Composition.run/resume ni un modo público de saltarse validadores. Writer
verifica binding host antes de mapping/codec/model, serializa un ticket host efímero,
confirma input y enlace con `step_input` y sólo después entrega al loop retenido
existente la hoja con Scope hijo. No inventa request/call del padre; Frame3, codec
Model y ServerSnapshot de la hoja se conservan. Autoridad/admisión son las del mismo
Scope ancestral y el root sigue con cero operaciones propias. Lease/deadline/budget
de raíz estrechan el deadline de la hoja; terminar usa el refund de Budget existente.

Frame4 tenía un contrato **exactamente vacío**, no campos opcionales de ejecución.
Se conserva su lector y su rechazo de hojas. Frame5 añade el contenedor ejecutado:
cursor running/completed y children con enlace exacto kind=step, step_id, index0 e
input confirmado. Referencias definition/policy/model/output coinciden con el binding
de la raíz. Sólo un paso/una hoja están habilitados; delegation y variantes futuras
se rechazan explícitamente, no se traducen a calls falsas. Record2/execution2 y el
snapshot raíz de identidad composition1 permanecen iguales: no bump cosmético de
su forma ni reinterpretación de Frame1–3. Frame5 habilita operaciones existentes
del loop más `step_input`/`step_output`, con validación de enlaces inmutables en cada
CAS y ledger↔journal en ambas direcciones, hashes de response/model y snapshots.

Output/cursor terminal se confirman tras la hoja; ACK perdido conserva el comando
data-only y no vuelve a ejecutar la hoja. Resultado no representable usa la omisión
explícita acotada del cierre de hijo existente; no permite replay. JSON/J, token y
reserva cleanup siguen activos; no se suma usage de snapshot sobre el ledger.
La alternativa de run_child efímero y Store por hoja se descarta porque no confirma
el input antes de IO ni conserva un único diario. La API interna es aditiva para la
major pendiente; ningún consumidor ni versión publicada cambia en esta unidad.

`Writer.step_status/3` valida y clasifica bytes como empty/input_confirmed/running/
completed contra configuración confiable, sin codec/mapping ni IO. **No reanuda**
una hoja interrumpida: Frame5 no se abre como Frame4 vacío. Falta persistir el piso
de autoridad/límites raíz y rehidratarlo junto con hojas antes de ofrecer ejecución
desde bytes en otro owner/VM. No usar el ledger como autoridad por omisión. Ese
pendiente, A→B y delegado ask/resume no quedan aceptados por el oráculo de paso único.
Evidencia propia y delta contra la raíz aceptada en el hito de implementación R6.

**Propuesta concreta previa a implementación; no aceptación runtime.** Primera
vertical: secuencia A→B, con delegado de B que pausa. Router y paralelo continúan
pendientes; este ADR no cierra R6. El detalle operativo y los gates están en
[implementación R6](../development/r6-implementation.md).

**Hito constructor implementado, separado del runtime:** `Composition.new/1`,
`binding/1` y `validate_binding/2` validan sin callbacks. Se emite exclusivamente
`composition_definition_version:1`, kind sequence, ID/version, pasos ordenados y
fingerprint SHA256 del JSON canónico existente. Cada paso liga definition/policy/
model_ref/output_ref e input_kind/input_version. Codecs y agentes sólo viven en la
definición host; model_ref versiona también el codec host. El límite es255 pasos,
referencias/IDs/versiones≤512 bytes UTF-8 y binding completo≤65536 bytes JSON.
No se han añadido run/resume ni frames ejecutables de hojas. Record2/Frame4 tienen
ahora el subset de apertura vacía descrito abajo; el protocolo secuencial restante
sigue siendo propuesta, sin bump de los writers legacy.

**Seam de Scope implementado (2026-09-28), no secuencia durable:**
`ExecutionScope.start_structural/2` crea una raíz host sin Model. El mismo ledger
admite hojas y agrega uso/restricciones ancestrales; la raíz rechaza admisión de
requests/tools/retries y contribuciones propias. El marcador es exclusivamente
estado confiable, no una opción pública de bypass ni autoridad recibida por JSON.
Scope2 permanece intacto: su restore verifica que ninguna operación pertenezca a
un nodo host estructural. Raíces agente legacy conservan operaciones propias.
Scope1 root-only no se usa como fallback estructural. El estimador raíz debe ser
nil o aridad2; uno aridad1 necesita una identidad Model inexistente y se rechaza.
Esto evita tanto el Model ficticio como duplicar el motor de contabilidad. API
interna aditiva de la major en preparación, sin migración de bytes legacy. Ocho
tests nuevos cubren loops hoja reales, carrera por presupuesto, precios/JSON y
rechazo atómico al importar operaciones raíz; suite971/0/28 WA seed37556. No es
evidencia del protocolo Writer/CAS/input/output/pausa de composición aún pendiente.

**Problema demostrado por inspección.** `ExAgent.run_child` no admite continuación
arbitraria. Frame3 identifica cada hijo mediante request/call/respuesta del padre;
Writer.config exige model_ref/model_codec y Writer.open captura un estado de agente.
Record.snapshot selecciona Server.Snapshot para toda fila de tipo agent. Una raíz
de composición no tiene ninguno de esos objetos: inventarlos falsearía journal,
historia y contabilidad. Tampoco basta encadenar dos runs durables independientes:
el cursor, el mapping y la autoridad ancestral quedarían fuera de su CAS común.

**Apertura estructural vacía implementada (2026-09-28).** Un rojo de Writer.config
sin model_ref/codec demuestra la frontera; Writer.open admite ahora configuración
interna kind:composition y definición host, con run_id/input/Scope estructural.
Valida configuración, binding, input y capacidad create+claim (incluyendo reserva
cleanup) antes del callback de registro del owner. Usa el mismo Writer,
Checkpoint, Transition, tabla/kind agent, CAS y receipts; no engine adicional.
Record2 contiene execution2 kind composition sin request_id/model_ref. Snapshot
composition1 contiene composition_id/run_id/binding/revision0, sin historia/Model.
Frame4 exige exactamente frame_version/kind/cursor/run_id/binding/input/scope:
kind sequence, cursor empty y Scope2 con sólo raíz y cero operaciones/batches.
Su binding coincide con snapshot, run_id y referencia definition. Datos persistidos
no reconstruyen autoridad ni callbacks: reclamar exige de nuevo definición host,
input idéntico y Scope estructural host vacío.

Se reservan y **rechazan**, no se simulan, children/step links, inputs mapeados,
outputs, approvals, efectos, cursor de hoja y terminación completed. Transition
sólo permite claim/recover/cancel/expire/delete después de create. Writer rechaza
operaciones de ejecución; ningún leaf loop puede entrar con este formato.
Los límites/autoridad del Scope host no se restauran desde esta primitiva; no hay
seam de hojas ni secuenciador. Record1/Frame1–3 siguen iguales y snapshot/restore
de agente rechazan Record2. Beneficio: persistencia y ownership reales sin Model
falso; alternativa descartada: Server.Snapshot ficticio o segundo Store/engine.
Contrato experimental aditivo para la major pendiente; sin migración automática,
bump ni publicación. Evidencia y límites en implementación R6; no cierra A8/C7
composición ni demuestra A→B.

**Decisión propuesta.** Composition es una definición host acotada, no un Model ni
un segundo motor de efectos. `new/1` valida una secuencia ordenada de pasos con ID
único, agente y referencias host versionadas. `run/3` recibe definición/input/opts;
`resume/2` recibe definición/opts con la misma configuración de continuación. Las
hojas entran en el loop existente mediante un seam interno; la raíz posee el mismo
Writer/CAS y Scope ancestral. No usa tools sintéticas para seleccionar pasos.

Resultado `{:ok, result}` con status completed/paused y `{:error, RunError}` con
progreso parcial siguen el contrato común. La raíz tiene model:nil y ninguna
historia propia; resultados/historias se consultan por step_id en orden declarado,
no concatenando conversaciones. Output terminal es el último output; parciales
mantienen explícitos los pasos confirmados. El ledger ancestral es la única fuente
del total: nunca sumar otra vez los subtotales presentes en esos resultados.

**Formato propuesto.** Record2 discrimina ejecución agent/composition; Record1 y
Frame1/2/3 conservan lectores y no reciben campos silenciosos. Composition usa un
snapshot de composición version1 sin modelo ni mensajes raíz y un Frame4 con
kind=sequence, definición ID/version/fingerprint, cursor, input inicial, inputs y
outputs confirmados, enlaces de pasos y Scope ancestral. Los nodos hoja conservan
sus datos Frame3. Un enlace step identifica padre/step_id/índice/input confirmado;
un enlace delegation conserva íntegramente el binding request/call existente.
La ausencia de model_ref sólo es válida en la ejecución composition discriminada.
No se traduce un árbol delegado legacy a secuencia por inferencia.

Definiciones, mapping y sus versiones proceden del host confiable. El fingerprint
canónico cubre orden, IDs, referencias de agentes/policy/modelo/output y versiones
de mapping; no hashes de funs ni resolución de módulos desde JSON. Cambiar código
sin cambiar la versión declarada viola el contrato host: el fingerprint no puede
demostrar identidad semántica de una función. ID/version/fingerprint se contrastan
antes de codecs, mapping, claim o IO de hojas. Autoridad actual se intersecta con
la original, nunca se recupera del payload como autoridad nueva.

**Fronteras de confirmación.** Confirmar output A antes de mapear B; confirmar el
input mapeado y su enlace antes de cualquier request B. ACK perdido mantiene el
comando exacto y sólo permite retry de persistencia. Resume no recalcula mapping
confirmado ni repite hojas terminadas. Un crash anterior al commit de un mapping
puro puede requerir recalcularlo: no se promete exactly-once para callbacks host
arbitrarios y el mapping no puede producir efectos externos. Pausa sólo se devuelve
tras ACK y quiescencia de todas las tareas propias; no se libera un owner dejando
un Writer separado activo. Incertidumbre de efectos conserva las reglas C7.

Grafo↔journal se valida en ambas direcciones: cada operación debe pertenecer a una
hoja existente y cada cursor/request/batch debe justificar sus operaciones; la raíz
estructural no tiene operaciones Model/Tool. Restore conserva contribuciones y
precios históricos por identidad, sin segundo débito/repricing. Inputs, outputs,
enlaces, resultados y tokens cuentan en J/JSON y en reservas cleanup antes de
admitir efectos; un resultado irrepresentable bloquea, no habilita replay.

**Alternativas e impacto.** Se descartan Model ficticio, tool orchestration falsa,
Store por paso y replay global. Un wrapper efímero sería desechable y no satisface
A8. La API es aditiva en la major en preparación; Record2/Frame4 exigen lectores
nuevos, sin bump/publicación ahora. Server/Session no ganan composición por aceptar
una fila agent: deben rechazar explícitamente un snapshot de composición. Su
integración queda fuera de esta vertical. Los lectores anteriores y sus fixtures
siguen siendo gates obligatorios; no migración automática de procesos vivos.

**Salida estable.** API pública A→B/delegado, restart de VM desde bytes, decisiones
host, dos resumers con barreras, autoridad/admisión compartida, ACK perdido, límites
exactos/+1 y corrupción bidireccional; suite offline warnings-as-errors y review
independiente. SQL A8/live son gates externos separados. El constructor/binding
tiene pruebas focales; ninguna garantía de ejecución/pausa/restart de composición
está implementada o verificada todavía.

### 8.39. OTel: pausa durable, identidad de intento y accounting (2026-09-28)

**Problema demostrado:** `{:ok, %{status: :paused}}` cerraba el span como succeeded;
faltaban attempt_id y referencia durable para distinguir pausa e intentos. Beneficio:
correlación de fronteras confirmadas sin persistir handles efímeros ni datos privados.

Paused cierra span y watcher existentes sin status OTel error. Resume conserva run_id
y record_id de lifetime, con nuevo attempt_id/span. `exagent.attempt_id` usa el bound
de labels existente. `exagent.continuation.{version,id,record_id,run_id,revision,attempt_id}`
proyecta sólo referencia pública validada por Event: mapa plano sin `__struct__`,
versión entera exactamente1; IDs UTF-8 del alfabeto permitido, máximo256bytes.
Referencia inválida se omite completa sin perder IDs válidos independientes del
resultado. Version/revision son enteros. Actor/token/record/payload/extras no se
recorren ni exportan. No se promete admitir cualquier término como resultado/usage.

Alternativas descartadas: succeeded oculta pausa, error inventa fallo, exportar el
record amplía datos privados y reabrir spans persistidos contradice handles efímeros.
No se inventan spans administrativos approve/deny/recover: requieren productor propio.
Sin métricas nuevas: request_count/tool_calls son admisiones host acumuladas lifetime,
no efectos ni deltas por intento (pausa1/1 con cero efectos; resume2/1 con un efecto).
No sumar snapshots entre intentos ni run totals con generaciones/hijos. Quality/source/
availability y coste estimado en cents permanecen: cero normalizado disponible con
provider_presence unknown; cache exclusive incompleta no inventa total inclusive,
subtotal parcial no es total.

Impacto/migración para major pendiente, sin bump: dashboards deben reconocer paused
como terminal del intento, no completion durable, y correlacionar run_id/attempt_id/
continuation.record_id. Sin migración persistida ni cambios Event/C7/accounting.
Verificación privada aceptada: owner145focales; reviewer145+9oráculos, padre9 intactos.
El P2 previo (struct Access y versión1.0) conserva rojo7/9 y verde9/9 en fix-validation;
14regresiones permanentes en los dos archivos nuevos. Integración ROOT y gates se
registran en roadmap, separados de esa aceptación privada. No cierre R7/G4, transporte
OTLP/backend ni SQL/cloud; Langfuse sólo referencia provisional, no elección final.

### 8.40. MCP Streamable HTTP: transporte opt-in y autoridad host (2026-09-28)

**Problema demostrado:** Client sólo ofrecía stdio; un servidor remoto no podía
usar la misma frontera Tool. La preflight también demostró que métricas públicas
de Finch no certifican HTTP1-only y que closures con distintos endpoint/principal
pueden compartir fingerprint de continuación. Ninguno se convierte en garantía.

**Decisión y beneficio general:** añadir `transport: :streamable_http` con URL y
Finch app-owned, usando APIs públicas stock Finch0.22. La app debe configurar pools
HTTP1-only y capacidad para requests concurrentes y control; no se detecta HTTP2 de
forma confiable. Se conserva Client como owner de admisión, IDs, deadlines absolutos,
generaciones y replies; workers/guardians acotan IO y cleanup fuera del GenServer.
Alternativa descartada: un adapter que materializa SSE antes de los límites host.
No se añade pipeline Req con redirects/retries ni se modifica ReqLLM.

MCP2025-06-18, handshake confirmado antes de ready, sesión acotada, JSONRPC IDs
exactos y JSON/SSE incremental terminal-aware. El primer terminal detiene parsing
y control: sufijos no invalidan resultados, independientemente de la segmentación.
Framing/errores/límites preterminales siguen rechazando. Retención host postdelivery
acotada, no hard RAM upstream/predecode. Timeout/desconexión dejan efecto incierto;
sin replay automático. Session404 invalida pending/generación; `reconnect/1` hace
handshake nuevo explícito. Close intenta DELETE acotado y para incluso con error.

**Impacto y migración:** extensión opt-in para la major pendiente, stdio sin migración.
Consumidores HTTP deben supervisar/configurar su Finch HTTP1-only, dimensionar pools
y manejar errores explícitos, incertidumbre y posible error de close. Discovery
conserva schema para validación/autoridad Tool; paginación y contenido no textual
rechazan, sin pérdida silenciosa. `call_tool/3` directo es IO, no autorización.
Sin migración persistida ni cambio de versión nominal. Binding durable C7 de destino/
principal, OAuth, reconnect/replay SSE y otras versiones MCP no están cualificados.

**Verificación y salida:** privado aceptado121focales+6+2review/padre8; patch exacto
ffb311e8 integrado sobre ROOT Frame8+OTel previamente aceptado (review c58bcc93,
9+69 independientes; FULL1423/28 del integrador anterior). Gates nuevos y review
integrada MCP se registran en roadmap, sin confundir copias. La recepción posterior
acepta interop local con SDK oficial Python `mcp2.2.0`: stdio `2024-11-05` y HTTP
`2025-06-18`, JSON/SSE × session/stateless, tools textuales mediante Client/Tool y
permisos reales. Owner y reviewer ejecutaron los mismos cinco casos sin skips;
no son diez casos distintos ni un rerun padre. Procedencia/SDK sin parches y cleanup
verificados; cinco módulos MCP ROOT/copia byte-idénticos cotejados por el padre.
El harness sigue privado, pendiente de integración portable. Los límites65KiB/
pending4/tools4 son sólo HTTP; stdio usa defaults8MiB/128, sin prueba de estrés.
No cualifica OAuth/TLS, cancel/reconnect/chaos, C7 binding endpoint/principal,
protocolo2026, otros SDK, multileaf ni SQL. R7.4/A9/R7/G4 y R6 completos abiertos.
Informes y hashes de esta evidencia separada en el roadmap.
Opciones, errores, límites y propuesta histórica en
[implementación MCP](../development/r7-mcp-implementation.md).

### 8.41. C7 de secuencia: primer batch todo-pending (2026-09-29)

**Aceptado offline acotado2026-09-29.** Owner FULL1790/28excluidos/1121.2s exit0;
review independiente favorable271existentes+7propios, compile108WA/formato global/
diff0, identidad15+303; padre15hashes y helper/copia con roundtrip, mismos7probes
7pases/13.2s exit0. Los57casos owner son43+14, no reruns. Informes/SHA, log padre y
recepción causal de los dos antiguos negativos en [implementación R6](../development/r6-implementation.md).
No aceptación general R6, mixed/raw/delegación/router/paralelo, SQL/live/producción
ni binding MCP endpoint/principal. Siguiente unidad sólo investigación; históricos
y provenance intactos, recepción documental posterior a los bytes revisados.

**Problema demostrado:** una secuencia A→B→C podía confirmar A, pero el primer
batch de B con permisos ask fallaba antes de guardar approvals. Tool resolution
exigía outcomes finales inexistentes y Record2 no admitía pending/denied; eliminar
sólo el guard de pausa habría guardado un snapshot de hoja como raíz y omitido el
dispatch autenticado de `decide/4`.

**Decisión y beneficio:** extender explícitamente Record2/Frame9 con approvals
formato1 y estados pending/denied, usando el mismo Writer, reducer, Scope y APIs
`Continuation.get/decide` y `Composition.resume`. La pausa raíz conserva exactamente
runtime, snapshot estructural y efectos del checkpoint batch confirmado; agrega
bindings efectivos post-hook y devuelve el saldo del intento completo. B permanece
running en disco. El resultado proyecta paused, output nil, A completed/B paused/C
not_started, referencia de revisión ACK, intento confirmado, checkpoint/error nil.
El bucle se detiene antes de ejecutar C. Sin ACK, sólo parcial confirmado y token
real de Store, nunca pausa anticipada ni revisión inventada.

La certificación compartida en Frame exige primer batch propio, calls funcionales
únicas, reserva exacta, cobertura calls↔approvals, ausencia de efectos/observaciones/
contribuciones/resolución propia, retry-plan o control mixto. Writer sólo omite la
escritura de tool_resolution con todos los resultados pending y controles false/nil,
sin settle_error; revalida al pausar, incluyendo Scope exportado. No fabrica control
final. Las tareas de tools se admiten independientemente: un sibling allow **puede
efectuar IO** antes de descubrir mixed. Ese batch falla cerrado preservando efectos
e incertidumbre, sin pausa ni refund. No se promete barrera preadmisión global.

Cada approval se liga a tool/schema seleccionado, run/request/call y refs; args son
los efectivos, no se comparan con el original del modelo. Requested revision debe
ser old+1 y quedar respaldada por receipt pause de ese lifetime. La validación global
preserva filas legítimas con efectos aprobados parciales; no las confunde con una
frontera restaurable. Sólo `decide` cambia una decisión y conserva el resto: parcial
pending, último approve ready, deny terminal. Pending/denied resume rechaza antes de
claim/callbacks; denied se inspecciona con `Continuation.get`.

Restore approved certifica el batch sin efectos, restaura su reserva **local de
bytes** y utiliza la reserva durable existente, sin readmitir contadores. La proyección
de capacidad usa los argumentos aprobados. El motor revalida args/policy/model/schema
actuales; deny vigente prevalece y puede producir outcomes denied y continuar
texto/C sin ejecutar tools B: no equivale al deny administrativo terminal.
Approvals históricas quedan inmutables y permiten
sufijos seguros. Espera humana no consume active budget, pero TTL/deadline lógico
siguen vigentes; nuevo claim reserva sólo saldo y el cierre raíz devuelve una vez.
Claims finitos abandonados agotan saldo; deadlines persistidos antiguos no se amplían.

**Alternativas descartadas:** Frame10, ledger paralelo, snapshot de hoja en raíz,
child paused persistido y un modo duplicado de Approval. La compatibilidad del formato
experimental es direccional: lectores nuevos conservan7/8/9 anteriores; lectores viejos
rechazan las nuevas filas C7 Record2. Consumidores de la major pendiente deben manejar
paused y consultar/decidir explícitamente antes de resume; no hay migración automática,
bump ni publicación. No se habilita restore general mixed/raw/delegación.

**Uso host con las APIs existentes:**

1. `ExAgent.Coordination.Composition.run(definition, input, opts)` requiere definición
   confiable y configuración `:continuation` existente. Tras `{:ok, result}` con
   `result.status == :paused`, conservar `result.continuation`: referencia pública
   exacta con version/id/record_id/revision/run_id/attempt_id; no contiene approvals.
2. `ExAgent.Continuation.get(store, result.continuation.id)` devuelve
   `{:ok, %{status: status, record: record, ...}}`. Consultar
   `record["execution"]["progress"]["approvals"]` para IDs/payload_hash y
   `record["revision"]`.
3. `ExAgent.Continuation.decide(store, id, :approve, opts)` (o `:deny`) requiere
   `record_id`, `revision`, `operation_id`, `actor`, `authorize`, `approval_id` y
   `payload_hash`. El callback confiable `authorize.(actor, decision, target)` devuelve
   `{:ok, actor_id}`; el modelo no autoriza decisiones. Usar nueva revisión confirmada
   y operation_id para la segunda decisión; reintentar ACK perdido con exactamente
   las mismas opciones/operation_id. Las decisiones sólo persisten datos.
4. Consultar de nuevo; sólo ready permite
   `ExAgent.Coordination.Composition.resume(definition, reference, opts)`, con la
   referencia exacta actualizada a la revisión confirmada y configuración host
   confiable. Resume adquiere nuevo claim; pending/denied rechaza antes de callbacks.
   Denied se inspecciona con get, no mediante un resultado success de resume.
   Un token `Continuation.retry_checkpoint/2` sólo reintenta persistencia; no resume.

**Verificación/salida:** VM BEAM nueva A una vez, dos decisiones y B→C; matriz de
ACK/CAS, presupuesto, corrupción, límites públicos±1 y reserva JSON/receipts en
`sequence_approval_test.exs`. Gates e identidad en R6 implementation y REPORT del
worker; revisión independiente y aceptación acotada recibidas según cabecera.

Ampliación owner de matriz: el parser de token limita bytes Erlang antes de Store;
esa cota es distinta de canonical-command/JSON+cleanup del CAS. Tokens de prueba
rellenados hasta ±1 pueden llegar al Store y ser rechazados como comando inválido:
no prueban un commit sobredimensionado. Los tokens originales sí hacen commit/replay
sin ejecutar tools. Tras approvals, refs/policy incompatibles rechazan preclaim;
schema y binding Model actuales se comprueban en preparación postclaim y fallan sin
efectos nuevos, conservando approvals. Barreras de observabilidad en ambas tools
aprobadas y en el siguiente Model prueban expiración budget/lease sin nueva IO y
controles puntuales con cinco requests/tres tools, sin segunda reserva de batch.
Esta ampliación sólo añadió tests; por sí sola no aceptaba C7/R6. La recepción
posterior acepta únicamente el subset anterior. Callbacks ya iniciados no tienen
garantía de preempción; JSON+cleanup es capacidad separada del parser de tokens.

### 8.42. Evidencia resuelta de la hoja activa de secuencia (2026-09-29, aceptada offline acotada)

**Subset activo Frame9 aceptado offline; R6 general pendiente.** La última aceptación
sellada en `sequence-active-evidence.md` recibe esta unidad después de8.41. El rechazo
incondicional de tools propias/approvals históricas impedía recuperar B tras resolver
su batch, aunque los consumidores single-leaf ya podían consumir esa evidencia.

`CompositionRestore` ahora clasifica una vista privada por run activo: effects,
operations/batches/retry_batches, tool_batches, output_resolutions y approvals.
No construye un Frame/Record singleton ficticio. Record.validate global y ausencia
global de Retry.plans preceden la selección; calls/reduce_resolution reciben siempre
el Record original. Helpers reciben child explícito; wrappers legacy conservan la
exigencia de approvals vacías. La frontera allpending aprobada se reconoce primero.

Fuera de ella, cada approval propia debe estar aprobada y ligada por su digest
run/request/call a exactamente un batch propio, con llamada existente y resolución
completa. Todo el batch exige efectos canónicos tool confirmed/final, status distinto
de pending/unknown, result_hash concordante y accounting none/contributed sin omisión.
La validación global conserva binding/receipt/revision/args efectivos; current-deny
predispatch no añade igualdad ficticia de args dispatch. Las approvals describen
historia resuelta: no autorizan otra request aunque call ID y args sean iguales,
ni se eliminan para pasar guards. Current allow no supera original ask: se conserva
original∩current y la nueva request pasa por admisión normal.

Tools se clasifican antes que output. Se reducen requests propios ordenados desde
cero y se contrasta tool_retries; el batch actual queda fuera del conteo de prefijo.
Se devuelven los consumidores existentes de tool history/batch/output retry/success,
sin duplicar contadores. Fatal actual mantiene error operativo sin Model/C/refund
inventado; fatal histórico rechaza globalmente. Preparación typed host conserva
precedencia. Completed approvals no imponen requisitos a between/input ya admitidos.

**Beneficio/alternativas/migración:** recuperación útil A→B→C reutilizando el loop,
Writer y Scope existentes. Se descartan records falsos, filtros que oculten errores
globales, borrar approvals y formatos/ledgers nuevos. API y persistencia no cambian;
host sigue usando recover explícito y referencia exacta. No migración ni ampliación
de deadlines antiguos. El cambio es aditivo en la superficie experimental de la major
pendiente; no habilita mixed/raw/administrative retry plans/delegación.

**Evidencia histórica del checkpoint:**25 casos nuevos y dos negativos antiguos específicamente
autorizados ahora positivos. Recorrido con dos VMs reales, approvals públicas,
efectos históricos únicos, contadores6/3 y coste58 con estimadores nuevos sólo para
requests nuevos. Matriz restante, logs/identidad y estado de FULL/review en
[R6 implementation](../development/r6-implementation.md). Este checkpoint no cierra
la unidad completa ni R6.

Ampliación de matriz de la misma unidad:30 casos nuevos, runtime sin cambios frente
al checkpoint. Autoridad refs/policy preclaim frente a schema/Model binding postclaim,
args efectivos/current-deny consumidos, contribuciones tool cualificadas exactas,
observability Model/tool con expiración real y positivos, ownership/fencing y límites
activos JSON+cleanup/receipts/history/checkpoint/parser separados. La API conserva
el rechazo de retry administrativo estructural; no hay productor nuevo ni datos
fabricados. Excepción tool conserva dispatch unresolved, no outcome confirmado.
FULL integrado único1845pases/28excluidos/1410.3s exit0; compile109WA/formato/diff0,
306/306fuentes intactas. Recepción posterior: review favorable40existentes+4propios,
identidad9+306; padre9hashes/copia roundtrip y mismos4probes4pases/16.7s/exit0.
Owner55=25+30; no sumar reruns. Informes/SHA/log en R6 implementation. Owner54/55
rojo,4focales correctivos y FULL verde siguen separados. Review original3/4 por
oráculo allow sobre ask conserva su fallo; copia corregida4/4 sin source fix.

**Uso host vigente:** usar la misma `Composition.resume/3` con configuración actual
y referencia exacta tras recover administrativo explícito; conservar approvals y
evidencia persistidas, no recrearlas para autorizar nuevas calls. El consumidor
reanuda B y luego C sólo si corresponde; fatal actual retorna fallo operativo sin C
ni refund final, sujeto a la prioridad de preparación typed host. Contadores host
exactos y contribuciones históricas no se redebitan/reprecian; tokens/coste
normalizados o estimados mantienen su calidad, no se convierten en factura provider.
Sin migración de API/formato ni bump. Legacy7/8/single9 y C7 allpending permanecen.
ETS y ficheros entre VMs no certifican durabilidad SQL. Token parse inflado no prueba
commit CAS válido oversized; capacidades JSON+cleanup/receipts/history/checkpoint
separadas. Callbacks iniciados sin preempción atómica. Mixed/control parcial/raw/
uncertain, retry estructural administrativo, delegación, router/paralelo y R6 general
siguen fuera, igual que SQL/live/producción. Próximo trabajo: investigación sólo
lectura de delegación+C7 quiescente/mixed-control, no implementación activada.

### 8.43. MCP: binding de destino y principal para C7 (2026-10-01)

**Problema demostrado.** Dos `Client.tools` reales sobre HTTP, con idéntico
nombre/schema y distintos endpoints o principales host, producían la misma huella.
Una aprobación persistida podía terminar ejecutando el segundo endpoint. El
callable captura un PID/configuración que el descriptor anterior no representaba;
nombre/schema no demuestran la identidad del efecto remoto.

**Decisión y beneficio.** `Tool.execution_binding` es metadata privada del adapter,
separada de `Tool.definition/1`. MCP la construye desde referencias confiables
explícitas del host: `continuation_binding: %{endpoint: reference, principal:
reference}`, con cada referencia `%{"id" => id, "version" => version}` no secreta.
El descriptor exacto version1 liga adapter MCP, transporte, revisión y ambas
referencias. HTTP añade SHA256 de la URL pública efectiva canónica, discriminando
destinos aun si se reutiliza por error la referencia endpoint. Sólo normaliza host
sin distinción de mayúsculas, puerto por defecto y path vacío `/`; no hace DNS ni
equipara rutas distintas. HTTP bound rechaza userinfo/query/fragment antes del
handshake. Stdio usa la referencia host de endpoint para identificar semántica de
command/args/env y confirma que la revisión respondida coincide antes de initialized.

Las referencias no autentican al peer ni prueban que las credenciales pertenezcan
al principal. Es responsabilidad host asegurar esa asociación y versionar cambios
semánticos, especialmente command/args/env de stdio. No se infiere principal de
headers ni de hashes de credenciales. Credenciales, URL literal, command/args/env,
Finch, PID, referencias de proceso y session IDs quedan fuera del descriptor.
Rotar credenciales del mismo principal reconstruye Client/Tool con las mismas
referencias y mantiene la huella; cambiar principal, destino, transporte, revisión
o referencia cambia la huella y restore rechaza antes de nueva IO de modelo/tool.

**Alternativas.** Inspeccionar captures/PIDs no da identidad durable y expone datos
efímeros. Incluir secretos o sus hashes impide rotación y no autentica un principal.
Añadir datos a description/schema altera el contrato del modelo. Confiar sólo en
un endpoint ID no detecta reutilización accidental para otra URL. Duplicar approvals
crearía otro circuito de autoridad. Se conserva el mismo fingerprint canónico,
Store, decisión, claim y revalidación existentes; RequestData2 acepta el descriptor
privado opcional exacto y sigue validando su preimagen y digest.

**Impacto y migración.** Uso ordinario MCP sin binding permanece disponible.
Protocol/Client marcan ausencia de referencia `:unbound`; al seleccionar la tool
para ejecución persistida se rechaza `:tool_continuation_binding_required` antes
de Model/tool IO. El error puede producirse tras la creación/claim inicial de la
fila vacía, conforme al orden existente de selección; no prueba ausencia de Store
IO ni inventa un terminal. Binding explícito inválido falla startup con
`:invalid_mcp_continuation_binding`; stdio con revisión distinta falla
`:mcp_protocol_binding_mismatch`. Target/principal cambiado en restore conserva
`:continuation_tools_changed`. Host no debe borrar la metadata para eludir el gate.

Las huellas de tools locales con binding nil y los descriptors locales/legacy
conservan exactamente su preimagen anterior. Pausas MCP históricas sin binding
confiable no se amplían ni se reetiquetan silenciosamente: reconstruir el nuevo
binding cambia la huella, por lo que se necesita iniciar otra ejecución y obtener
su aprobación explícita. Para HTTP durable mover auth de query a headers y declarar
referencias estables; el HTTP ordinario conserva su soporte de query. Extensión para
la major v2 pendiente, sin bump ni publicación ni migración de filas existentes.

**Verificación acotada.** Reproducción roja real Client/tools más rechazo de retarget
persistido; focales de endpoints/principals, rotación, schema/autoridad, protocolo
stdio, metadata/digest corruptos, URI alias y huella local idéntica. Cinco VMs nuevas
producen pause/get/decide, rechazan target y principal distinto sin modificar bytes
aprobados, y reanudan una vez con credenciales rotadas, modelo2/tool1 y un efecto TCP.
El Store de fichero es un fixture de un escritor, no SQL/durabilidad distribuida.
La recepción privada no cualifica la candidata integrada ni C7 multileaf/cloud/
producción; requiere la única revisión de integración. Guía de consumo en
[binding MCP durable](../development/mcp-continuation-binding.md).

### 8.44. R6: router confiable y fan-out/fan-in durable acotado (2026-10-01)

**Problema demostrado.** La secuencia10 impone un prefijo y un fatal global.
Reinterpretarla como paralelo no representa dos ramas activas independientes ni
permite conservar una rama fallida mientras otra delega y espera aprobación.
Crear registros independientes pierde admisión/contabilidad ancestral atómica y
la pausa quiescente común. A8 exige ambos hechos en el mismo journal.

**Decisión y beneficio.** `ExAgent.Coordination.Flow.new/run/resume` define una
composición plana `kind: :router | :parallel`. Sus ramas usan los mismos descriptors
de hoja, referencias confiables y codec explícito que `Composition`. Cada rama
recibe el input raíz; su loop original puede ejecutar tools o delegar. Un router
elige un ID declarado mediante `select` host con `select_version` obligatorio.
Paralelo selecciona todas las ramas. `merge` opcional requiere `merge_version` y
recibe outcomes JSON ordenados por definición, nunca por orden de terminación.
Por defecto devuelve esa lista. Selector y merge son callbacks host **puros**;
los efectos externos pertenecen a tools con intent/outcome, autoridad y C7.
Una versión identifica el código confiable: el host debe cambiarla al cambiar
semántica; el digest no demuestra identidad de captures ni ejecuta callbacks.

La identidad portable propia `flow_definition_version: 1` liga ID/version,
kind, ramas, versiones host, políticas y cotas. `Record2/execution2` conserva el
journal existente; `Frame11` discrimina exclusivamente Flow. Retiene fases
idle/selecting/running/merging/completed/failed, selección ordenada, fallos
canónicos por rama y resultado/omisión raíz. Hojas Frame3, tool phases, preimágenes
Model/output y authorities Scope2 se reutilizan. El root no tiene Model,
intent/usage ficticios ni tool request inventada. Validación global comprueba
topología, selection, binding, fuente original, ledger, markers y límites antes
de cualquier claim o efecto. No convierte ni reetiqueta filas9/10.

**Políticas y ciclo de vida.** `failure_policy: :fail_fast` es el default; detiene
nuevas admisiones al primer fatal confirmado por orden estructural y drena lo ya
admitido. Una rama hermana drenada no recibe un fatal inventado: conserva raw y
fuente, y sólo el owner raíz puede cerrar failed después de todos sus workers
DOWN y del certificado global de efectos conocidos. `:collect` conserva cada
fallo confirmado en su rama, continúa las demás y permite un resultado completed
con outcomes failed/completed. El fatal local se deriva del Record original,
incluido agotamiento de retry ordinario confirmado por su reducer canónico.
Errores Model/root sin certificado y efectos sin resultado permanecen inciertos;
ninguna política los convierte en failed conocido ni habilita replay/refund.

Una aprobación abre el drain común: no se arrancan ramas en cola, las admitidas
terminan su trabajo conocido y root pausa sólo tras ACK de estado y todos DOWN.
C7 usa los mismos `get/decide/claim/recover` y hashes/policies actuales∩originales.
Partial approve sigue pending; dos resumers de la misma revisión sólo permiten un
ganador CAS antes de codec/IO. Ramas completed/failed históricas son datos y no
cargan codec ni repiten callbacks/Model/tools. Resume reconstruye sólo las hojas
running/suspended y sus delegados, una vez, desde JSON y host confiable nuevo.

El drain admite el batch derivado de una respuesta Model **ya confirmada** de otra
rama, aun si llega después del ask hermano. No inicia ramas sin nodo: un worker
registrado que alcanza DOWN antes de attach conserva not_started para después
de aprobar. Si se pierde un ACK de call_wait/node_suspend o del batch hermano,
recover explícito conserva el drain y sus fuentes; ready termina sólo las ramas
adjuntas pendientes y publica la pausa común antes de iniciar la cola. Un ask ya
persistido sigue pending sin inventar otro permiso. Model en vuelo/control sin
resultado permanecen uncertain y no autorizan esa reanudación ni refund.

Los plazos actuales de rama sólo limitan ramas seleccionadas que todavía pueden
ejecutar (incluidas las aún sin nodo); ramas descartadas o terminales son datos.
Root se comprueba siempre antes de un claim ejecutable. El claim intersecta su
plazo absoluto, y un ACK tardío revalida root/ramas activas antes de Scope,
resolver/codec y dispatch. El plazo efectivo de cada nodo se comprueba antes y
después de su codec. Se conserva el claim confirmado, sin refund o token de ACK
perdido fabricados, cuando el plazo ya venció.

Selector y merge tienen ACK de admisión **previo** al callback y ACK de resultado.
ACK perdido sólo admite retry del mismo comando; no prueba permiso de dispatch.
ACK tardío comprueba de nuevo el deadline actual antes del callback. Crash entre
admisión y resultado requiere recover explícito y queda uncertain, aunque el host
callback fuese puro; no se deduce resultado ni se vuelve a ejecutar. Crash tras
resultado confirmado de D y antes de admitir wrapper B sí puede recuperar ready
y consumir ese raw conocido. Active budget reserva el claim completo: pause/fin
conocidos devuelven sólo saldo confirmado; espera humana no lo consume y un claim
abandonado no recibe refund. Exact host counters cuentan intentos admitidos,
incluidos denied host outcomes; contador de callbacks/efectos externos es distinto.

**Cotas y capacidad.** Hay1..32 ramas y1..32 workers de rama concurrentes
(`max_concurrency`, default4). Cada resultado de rama y el merged tienen límites
JSON separados1..65,536 bytes (`max_branch_result_bytes`/`max_result_bytes`, ambos
default64KiB). Un batch de32 resultados64KiB no tiene garantizado caber en el
merged default64KiB ni en el journal8MiB: merge debe reducirlos o devuelve marker
y error de host conocidos; no se truncan. JSON exact/+1 se prueba en ambas
fronteras. Typed no portable conserva el marker checkpoint de su atestación
original; collect falla esa rama sin fabricar valor o repetir validación.

La reserva añade slots propios de outcomes/fallures futuros y merge, sobre la
reserva10 existente, sin tomar créditos de siblings. Los resultados ya son JSON
values acotados: no se multiplican otra vez como strings que contienen JSON.
Punteros fatales permiten escaping de tres IDs512bytes y errors≤4116bytes;
copias node/call terminales siguen en su pool original. Selección y merge guardan
su horizonte de recibos ACK y las ramas no resueltas su cierre. Una definición
de32 ramas vacía admite esos slots dentro de8MiB antes de Model IO; cada posterior
efecto sigue sujeto a capacidad exacta,255nodes/depth16 y256effects. Bounds
persistidos se revalidan al restaurar, sin ampliarlos. Payload ordinario1MiB,
slots tool durable64KiB, límites globales/cleanup/receipts y legacy permanecen.

**Alternativas e impacto.** No se añade graph DSL, scheduler distribuido, Flow
anidado, input mapping de grafos, Model supervisor ficticio ni otro circuito de
approvals. Un nuevo formato explícito evita que un lector10 acepte semántica de
paralelo por accidente. Es extensión para la major pendiente: usuarios existentes
mantienen Composition y sus filas9/10. Para adoptar Flow, construir la nueva
definición con las referencias de hoja, callbacks puros versionados y continuation
scoped; iniciar una fila nueva, sin migración silenciosa. `.branches` expone por
orden `{id,status,output,output_omitted,error}`; `.steps`, parcial, continuidad,
usage cualificado y contadores compartidos conservan la forma común. El estado
completed de collect no significa que todas sus ramas hayan tenido éxito.

**Observabilidad y verificación.** Cada rama usa run/Model/tool originales bajo
su root Flow. Delegación durable abre un único span tool→delegation→child sólo al
ejecutar/reanudar, y completed data-only no abre otro. El plugin público
`examples/flow_pipeline.exs` produce router + paralelo2 con D:7requests,
3intentos tool,2efectos y17spans nativos (18con parent aplicación); sin duplicar
accounting. Matriz causal incluye concurrencia real/desorden, authority, ACK
before/after/late, race CAS, C7/mixed/delegados, source/markers/typed, failed/unknown
drain, active budget y tres escenarios de VM sólo JSON. Logs, comandos/hashes,
regresión10/9 y estado de la revisión única en [R6 implementation](../development/r6-implementation.md).
Esta evidencia offline no prueba SQL/A8, provider/backend live ni el paquete
candidato; esos gates tienen recibos propios. Sin bump, commit o publicación.

### 8.45. Parche oficial Mint y floor de consumidores (2026-10-01)

**Problema demostrado y beneficio general.** El lock raíz conserva Mint1.10.1.
El CNA de sus mantenedores publicó el2026-09-28 tres vulnerabilidades que afectan
a versiones anteriores a1.10.2: framing de respuestas HTTP/1
([CVE-2026-94194](https://cna.erlef.org/cves/CVE-2026-94194.html)), amplificación de
headers HTTP/2 decodificados
([CVE-2026-91043](https://cna.erlef.org/cves/CVE-2026-91043.html)) y buffering de un
frame HTTP/2 antes de comprobar su tamaño declarado
([CVE-2026-92103](https://cna.erlef.org/cves/CVE-2026-92103.html)). Son problemas del
transporte compartido por consumidores, independientes de la aplicación ejemplo.
La versión oficial1.10.2 fue publicada el2026-09-29; el TAR verificado tiene SHA256
`3171931320e7abc6164093aa49e3b5f20dcd079b6dce4be23947dd1e42dbb68b`.

**Decisión y alternativas.** Elevar el floor directo existente a
`~>1.10 and >=1.10.2` y actualizar sólo el tuple Mint del lock raíz. HPAX1.0.4,
ReqLLM1.24 y los demás entries se conservan. Finch0.22 permite este parche mediante
su requisito vigente. Cambiar sólo el lock dejaría consumidores Hex sin protección;
Mint1.11 también corrige los advisories, pero introduciría cambios de transporte
adicionales sin necesidad. No se añade override, fork, patch, parser ni runtime.

**Impacto observable, SemVer y migración.** No cambia API, schema, eventos,
snapshots ni lifetimes de ExAgent. Resoluciones con pins Mint≤1.10.1 ahora rechazan;
el host debe actualizar su constraint y lock. Es un floor de seguridad de la
consolidación pendiente, sin bump o publicación por este trabajo. Un lock ya
instalado no se actualiza automáticamente. Los límites host postdecode y guards
inciertos siguen necesarios; el parche no certifica RAM dura predecode upstream.

**Verificación y límites.** El resolver oficial produjo el tuple; no se importa
su actualización incidental de HPAX. Una copia física post001+006 con el parche
ejecutó timeout/cancel HTTP reales, stream/tool envelope y handshake MCP HTTP:
14pases/61excluidos,7.2s exit0. Recibo017 conserva comando, tooling, fuentes y lock
`33a222bfe0df7fffcd78af2d0a7bcc61c0a762255fd05f690492da6433e7f2bc`.
Las exclusiones no son aceptación. Esa copia es anterior a los fixes009; la suite
integrada y los consumidores de la candidata tienen evidencia propia. Los fixes
upstream se atribuyen al release oficial, sin auditoría nueva de exploits HTTP/2
ni prueba de proveedor pago en este focal.

### 8.46. Aceptación equivalente Langfuse/Opik y proyección opcional (2026-10-02)

**Problema demostrado:** la fuente pública de Opik consume atributos de span,
regenera IDs UUIDv7 y envía atributos desconocidos a `input`. Una simple sustitución
del endpoint no preserva la ubicación de diagnósticos/recursos esperada por A10.
El usuario requiere ahora igual profundidad de aceptación en ambos backends;
la aceptación anterior de una sola referencia no cumple ese mandato.

**Decisión y beneficio general:** mantener OTel neutral en el core. La receta
experimental aislada propiedad de la aplicación admite un módulo opcional
`:request_profile` con `project/1` sobre el mapa del converter público stock,
antes de sus cotas de spans/ETF y del cliente gRPC generado oficial. Su ausencia
conserva la identidad. El perfil concreto Opik utiliza el prefijo público
`opik.metadata` para conservar los escalares nativos y recursos, sus tipos y
correlación; las inferencias proyectan modelo/provider/uso sin sumar padres.
No modifica IDs/parentage/nombres/tiempos/estados, no captura contenido y no añade
argumentos ficticios para forzar el tipo tool. Los tools se diagnostican como
`general` mediante sus atributos de operación/estado.

**Alternativas:** atributos Opik en el core acoplan toda aplicación al backend;
inventar contenido o reemplazar IDs nativos cambia lo observado; un parser/encoder
privado rompe el mandato stock. Un Collector contrib con transformación añade
otro binario/perfil que este escenario no necesita. El callback de aplicación
reutiliza el converter oficial y las fronteras de ownership ya aceptadas.

**Impacto y migración:** extensión aditiva de una receta opcional, sin cambio de
contrato del runtime, snapshot/C7, default SDK o dependencia de biblioteca. Las
aplicaciones que no suministran el módulo mantienen la ruta previa. Este perfil
admite expansión hasta64atributos y65,536ETF por traza antes de escribir; cada
lote conserva8spans/65,536ETF y el preflight HTTP opaco. No es una garantía de RAM
predecode ni retención durable cloud. Una nueva instancia/perfil requiere su
propia aceptación; el código público fijado no identifica el build Cloud.

**Verificación requerida:** controls offline que rechacen mapeos incompletos,
tipos false/int incorrectos, IDs/parentage/estados/privacidad/unidades alterados;
preflight de la candidata física y una ola nativa Opik de18+15spans/cincoPOST;
lectura independiente de33spans y sus dos trazas, seguida de UI autenticada.
Las pruebas y recibos de ambos backends son separados; ACK/API no aceptan UI
ni factura. Estado y limitaciones en [evaluación](../development/backend-evaluation.md)
y [roadmap](../development/roadmap.md).

El preflight descubrió además un fallo de la receta IPC: con el IO por defecto,
la cabecera packet4 de longitud29917 (`00 00 74 dd`) espera más bytes como UTF-8;
la cabecera22447 sí se consume. El control aislado reproduce el fallo sin SDK,
backend ni payload privado. El worker configura su propio IO como binario/Latin1
antes de leer; mantiene safe ETF, las cotas y el cliente stock. Es una corrección
del framing interno de la receta, no un parser OTLP ni cambio de SDK/global.
La fuente anterior y sus recibos se conservan; las cabeceras y el A10 completo
deben verificarse sobre la derivada corregida antes de la nueva ola cloud.

**Resultado observado:** candidata025 pasa33spans/cinco lotes nativos y API
33/33,667atributos/12modelos, incluyendo correspondencia UUID/edges/recursos/
tipos/uso/privacy. Opik guardó el primer lote8 de las olasHTTP500ms/1s aunque
el Collector perdió el ACK; la segunda registra timeout explícito. Un fixture
con respuesta700ms reproduce el fallo500ms y pasa con3s. El perfil cualificado
admiteHTTP3s/RPC3.5s/VM5s/export20s/owner28s y conserva Collector30s/stop2s,
dos trazas/cincoPOST/batch8/64KiB, sin retry o queue. Son cotas del perfil de
aplicación, no cambios al default de biblioteca ni garantía de latencia. No ampliar
el guard del launcher para cubrir un perfil mal combinado. Rojo/ACK perdido se
preserva y no se infiere ausencia de escritura. La UI autenticada posterior
acepta12casos/248atributos y siete vistas reales inspeccionadas con los mismos
oráculos que Langfuse: pausa/resume, IDs, retries, usage/quality/source/cents y
privacy. Fuente/recibo UI e0a9be73…3e0f9 en OPIK-ACCEPTANCE del checkout.
Fallos intermitentes de navegación/captura y recortes físicos quedan declarados;
IDs/cents exactos se cotejan en líneas renderizadas y selección URL. No se
certifica estabilidad de UI ni se sustituye UI por API. Revisión024 única0P1/2P2: ejecución
real de driver/helpers y cleanup API corregidos por el dueño con fronteras
causales, sin segunda revisión. El delta de plazos tiene evidencia propia.

### 8.47. Subtotal conocido ante usage terminal incompleto (2026-10-02)

**Problema demostrado:** un Model custom con streaming entrega usage acumulado
completo valorado en11cents y termina con un usage no nil sin métricas. El Scope
preservaba los tokens pero borraba el precio anterior. Con accounting estimado y
presupuesto10cents admitía un efecto y otra petición; un delegado fallido perdía
el mismo subtotal en su ancestro. Los contadores host seguían siendo exactos.

**Decisión y beneficio:** conservar el precio anterior por descriptor sólo si la
nueva muestra carece de evidencia suficiente para esa fuente de precio. El coste
resultante conserva subtotal11 con disponibilidad parcial y `cents` nil; la
admisión estimada puede detenerse con esa evidencia conocida. Una nueva estimación
explícita, incluido cero o unknown/error con métricas utilizables, tiene precedencia.
No cambiar el guard del estimator de aridad1 entre identidades de Model distintas.

**Alternativas:** borrar el precio pierde evidencia de presupuesto; sumar muestras
duplica usage acumulado; recalcular métricas ausentes las presenta como observadas.
La corrección reutiliza el ledger y la calificación actuales sin otra representación.

**Impacto, migración y verificación:** bugfix del contrato acumulativo de Model,
sin cambio de API, defaults, esquema persistido o dependencias. No exige migrar
snapshots ni configurar otra fuente de precio. Tres oráculos fallan sobre026;
cinco casos causales y25 adyacentes pasan en la corrección privada integrada con
SHA idéntico. Nil y cero completo conservan su comportamiento. El stock ReqLLM
actual no emite esa muestra intermedia: no atribuirle el trigger ni invalidar G2/G4
anteriores. Evidencia y límites en el registro crítico027 del checkout.

### 8.48. Aprobaciones previas durante otra ronda de Flow (2026-10-02)

**Problema demostrado:** dos ramas pausan y reciben aprobación. Al reanudar, A
consume su primera aprobación y abre un nuevo ask mientras B todavía debe consumir
la anterior. La frontera pasa a draining/approval y call_prepared rechazaba B al
exigir open. El record válido queda bloqueado también después de recover público;
el efecto ya confirmado de A se conserva. Una sola ronda no expone este caso.

**Decisión y beneficio:** en Frame11 permitir preparar una llamada ya aprobada
durante draining por aprobación, únicamente sin fatal confirmado. Mantener rama
running, autoridad/binding exactos y guards de owner, intento, fence, epoch,
lease y ACK. Permite drenar ramas admitidas sin bloquear nuevas rondas, ni crear
aprobación para otra llamada. Current deny, pending/closed/suspended y fatal
continúan rechazando; Frame9/10 conservan sus guards.

**Alternativas:** serializar aprobaciones impone una barrera nueva al paralelo;
recrear permisos cambia evidencia histórica. El delta conserva el drenaje de R6.

**Impacto, migración y verificación:** bugfix de transición sin formato/API nuevo
ni migración JSON. Un record auténtico previo se restaura y completa en otra VM:
5requests/3tools, sólo2 efectos nuevos, sin repetir Model o efecto confirmado.
Ocho casos finales pasan con warnings-as-errors, incluyendo rondas, deny, binding,
fatal, ACK incierto y delegado; las fuentes integradas coinciden con sus SHA.
Las intent inciertas siguen bloqueando resume y no reciben refund de presupuesto.
No prometer revivir records expirados o agotados. El helper final sólo cambió
formato/alias después del restore observado: esa ejecución conserva su identidad
previa, separada de la matriz final. Recibos y limitaciones en revisión027.

### 8.49. Instrucciones canónicas en hojas de coordinación (2026-10-02)

**Problema demostrado:** los E2E reales de router, paralelo y Composition fallan
con invalid_record antes de admitir el primer Model. El loop incluye las
instrucciones del agente como partes System antes de User en la primera Request;
el certificado de evidencia de la hoja exigía una lista con sólo User. Las
pruebas anteriores con templates sin instrucciones no exponían la contradicción.

**Decisión y beneficio:** aceptar exclusivamente un prefijo de partes System
seguido de una única parte User, cuya entrada continúa ligada exactamente al
paso/delegación y run_id. El codec de mensajes conserva y valida las instrucciones;
RequestData y la evidencia posterior mantienen sus hashes y correlaciones.
Secuencia, router y fan-out pueden usar los mismos templates instruidos que el
loop ordinario. Un System posterior al usuario, dos User o partes de otro tipo
siguen rechazándose. No ampliar permisos, Model/root guards ni ejecución terminal.

**Alternativas:** quitar instrucciones o moverlas al texto del usuario altera su
semántica y oculta el defecto; aceptar cualquier conjunto de partes debilita el
binding del input. El cambio corrige la comprobación sobre el formato vigente.

**Impacto y migración:** bugfix del certificado, sin API, schema/versiones, defaults
ni dependencia nuevos. Los records válidos anteriores mantienen su significado;
no hay datos previos que migrar, pues la escritura con ese prefijo se rechazaba.

**Verificación:** stock con clave sintética y callback que bloquea antes de IO
reproduce invalid_record con instrucciones; sin ellas alcanza el callback. El
parche permite ambos, sin HTTP. Tres regresiones API prueban secuencia/router/
paralelo, dos instrucciones conservadas, counters y lectura completed sin IO,
además de corrupciones con segundo User/System tardío. Pasan exit0 sin warnings;
45 casos adyacentes pasan y se conservan los fallos iniciales del fixture nuevo.
Las repeticiones real13–15 se registran por fuente en la aceptación028, sin
contar la preparación offline como aceptación de proveedor.

## 9. Estado actual y no-goals

**Hecho (núcleo funcional):** loop, backend ReqLLM stock cualificado, Model custom/Test,
deftool, output estructurado Ecto, streaming lazy, capabilities, UsageLimits,
telemetría, serialización de history.

**No-goals explícitos (al inicio):**
- No motor de graphs/FSM genérico tipo pydantic-graph.
- No MCP server propio (sí client en fases tardías).
- No A2A entre nodos distribuidos hasta que Store Postgres lo habilite.
- No RAG/embeddings/vectores dentro del core (vivirá como capability opcional).
- No persistir credenciales, pids, refs ni captures de funciones en Store.

Ver la [hoja de ruta vigente](../development/roadmap.md) para las próximas unidades
y [estado](../status.md) para la última aceptación. Los números de tests de las
decisiones anteriores son evidencia de su fecha, no nuevos resultados.
