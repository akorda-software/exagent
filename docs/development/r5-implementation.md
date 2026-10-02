# R5: propuesta de continuación del loop existente

Dirección R5.1 aprobada por coordinación el 2026-09-26 antes de cambios runtime.
No certifica C7. La tabla de estado sigue siendo roadmap§5.

**Extensión estática aprobada2026-09-27:** diseño8.36 añade el callback opcional
genérico `Model.continuation_binding/1` (JSON portable≤4096B, nil si ausente), Frame3
y Abort2. Nuevas capturas guardan model_binding por nodo; restore compara plantilla
actual antes de cargar codec y modelo reconstruido después. Así una primera request
incierta sin historia también queda ligada a configuración estática opt-in. Root1/
tree2/abort1 antiguos sólo admiten binding actualnil. Reintentos data-only conservan
comandos/versiones exactos; no invocan callback ni migran datos. Scope2/Snapshot4 y
reservas J/JSON permanecen y cargan esos bytes. Las descripciones Frame2 inferiores
son el diseño previo, no autorización de ignorar el binding nuevo. Aceptación de
esta subunidad se registra por fuente nueva, separada de C7/admisión ya aceptados.

## Problema demostrado y decisión mínima

`ExecutionScope.authorize/3` resuelve ask llamando un callback vivo y transforma
todo lo demás en deny. `execute_function_tools/2` recoge exclusivamente
ToolReturns y la delegación extrae output de cualquier `{:ok, result}`. Por ello
un estado paused no puede añadirse sólo a Permissions: se perdería el cursor del
batch/hijo y Server emitiría run_finished y drenaría su cola. R4 ya proporciona
CAS/receipts/fences, pero no contiene frames del loop ni decisiones de aprobación.

Extender el mismo loop con un cursor data-only y un writer efímero por árbol
durable. El writer serializa comandos R4, no posee otro motor de ejecución ni
permanece vivo esperando al humano. Cada llamada al modelo/tool que posea el run
durable se registra antes de IO; un outcome confirmado se guarda antes de avanzar.
El owner continúa únicamente con un ACK fresco ligado al intento/fence vigente.
Un receipt antiguo recupera evidencia, nunca concede IO.
Esto impide despachar con obsolescencia conocida, no cierra la ventana entre
revalidación y llamada externa: perder fence en esa ventana conserva incertidumbre
y exige journal/reconciliación; no se promete fencing de una API externa arbitraria.

## API propuesta (un contrato de resultado)

- `ExAgent.run(agent, prompt, continuation: config, ...)`: opt-in Store atómico,
  `config` host con `store` scoped, `id`, `definition`, `policy`, `model_ref`,
  `durability`, `deadline_at`, `expires_at` (nil explícito válido),
  `active_time_limit_ms` y `lease_ms`. Referencias son `{id, version}` de datos;
  modelo, deps, callbacks, permisos y credenciales siguen en agent/opts confiables.
  Un Store snapshot-only o config inválida falla antes de Model/tool IO.
- `ExAgent.Continuation.get(store, id)` devuelve proyección de estado consultable.
- `ExAgent.Continuation.decide(store, id, decision, opts)`: decision approve/deny/
  cancel/expire, con record_id, revision, approval_id, payload_hash, operation_id,
  actor y callback host `authorize` obligatorio. Ningún actor viene del LLM.
- `ExAgent.resume(agent, reference, opts)` y `resume_stream/3`: reference identifica
  store/id/lifetime/revisión; configuración ejecutable y referencias actuales deben
  venir de agent/opts host. No nueva llamada al modelo antes de resolver el frame
  pendiente. run_id estable, attempt_id nuevo, request_id lógico conservado.
- `Continuation.recover/3`, `reconcile/5`, `retry_checkpoint/2`: recuperación
  administrativa autenticada; reconcile acepta evidencia/outcome host, y un retry
  de efecto exige decisión explícita e idempotency key de aplicación. Retry de
  checkpoint sólo repite el comando CAS exacto y nunca entra al loop.
- Éxito común `{:ok, %{status: :paused, output: nil, continuation: ref, ...}}`
  después del ACK de pausa y quiescencia. `run!/3` no convierte paused en nil como
  si fuera output final: error explícito de uso de esa conveniencia.

Los nombres finales se fijan en ADR8.34 antes de estabilizar y se prueban mediante
API pública. Los helpers internos no crean un segundo result struct.

## Datos y máquina de estados

Una fila R4 conserva snapshot4 + execution + receipts, sin dual-write. Se añaden
estados pending/denied y comandos pause/decide; ready significa runnable después
de aprobación, claimed conserva ownership y effects.running expresa ejecución de
IO. Estado público distingue pending, approved, claimed, executing, completed,
denied, expired, cancelled, uncertain a partir de esa máquina única.

| Origen | Comando y guard | Destino |
|---|---|---|
| claimed | pause, sin effects unresolved, frame validado y presupuesto retenido | pending; libera owner/fence |
| pending | approve exacto, actor autorizado, no expired | ready; decisión ligada al payload |
| pending | deny/cancel autorizado | denied/cancelled |
| pending/ready | expire, UTC deadline/expiry alcanzado | expired |
| ready | claim CAS, intento nuevo, revalidación host | claimed |
| claimed | begin_effect ACK fresco, fence/lease vigentes | claimed + running intent |
| claimed | outcome confirmado | claimed + confirmed outcome |
| claimed | finish sin unresolved | completed |
| claimed | recover tras lease/cancel | uncertain si intent sin outcome; ready sólo sin IO incierto |
| uncertain | reconcile autorizado con evidencia por efecto | uncertain o ready |

Decisión repetida con mismo operation_id y payload/revisión devuelve receipt;
opuesta, actor distinto o payload cambiado conflictúa. Operación nueva sobre una
revisión vieja conflictúa. Approve no ejecuta nada. Guard de expiry se evalúa dentro
del lock Store. Revalidar permisos actuales también antes de begin_effect.

El vertical raíz inicial usó frame_version1. El escritor integrado R55 usa
frame_version2/scope_version2, conservando sólo el lector de raíces1 válidas;
diseño8.34 recoge la evolución demostrada y la revisión pendiente. Retiene nodos por run_id, parent_run_id y
call_id de entrada, definición/policy/model refs, cursor request/batch/finish,
historia lógica via codec existente, respuesta pendiente, inventario seleccionado
(nombres/schema fingerprints, sin callables), orden de calls, args efectivos,
outcomes confirmados, retries, run_step, límites originales y tiempo activo gastado.
Approval contiene ID, call/run IDs, args lógicos, hash canónico de payload (incluye
schema/definición/policy/ancestría), revisión de solicitud y decisión. Datos omitidos
invalidan la continuación antes de cualquier IO; no se reconstruye un éxito desde
content:nil. Codec envelope1/continuation2/accounting1/omitted-v1 no cambia.

## Autoridad, contabilidad y tiempo

Restore exige plantilla raíz actual y reconstruye hijos por la definición de
delegación confiable, no por nombre de módulo persistido. Cada nodo conserva límites
originales y la autoridad se intersecta con la actual de todos sus ancestros. Los
permisos originales JSON sólo pueden restringir; no suministran callbacks. Se
revalida schema y before-tool sobre el original, comparando args efectivos con el
payload aprobado; un cambio no se ejecuta bajo aprobación antigua. Cambios de
definición/model ref rechazan explícitamente; policy actual puede restringir más.

Scope exporta/importa un ledger data-only por identidad de operación/nodo, con
contadores exactos, Usage cualificado y costes ya calculados. Restore no llama al
estimador ni añade de nuevo un hijo. Las reservas de tools del batch persistido no
se admiten dos veces; nuevos intentos model sí consumen nueva request. No serializar
tokens de scope, pids, refs, monotonic timestamps, closures ni OTel.

Deadline/expiry son UTC ms y transcurren en espera humana. El presupuesto de tiempo
activo guarda milisegundos consumidos y continúa desde ese saldo, sin cobrar la
espera; se combina con el deadline monotónico efímero restante durante cada intento.
No ampliar límites originales al restaurar. La expiración nil es distinta de campo
faltante/config malformada. Lease sólo revoca ownership; no autoriza repetir IO.

Antes de cada intento se carga conservadoramente todo su saldo activo en el mismo
claim persistido. Sólo un checkpoint confirmado del owner vigente devuelve el
remanente medido monotónicamente; un owner muerto sin ese checkpoint pierde esa
reserva (puede agotar su presupuesto), nunca obtiene tiempo gratis al recuperar.
La espera pending no tiene intento ni reserva activa. Un saldo nil explícito no
impone límite activo, pero no desactiva deadline/expiry UTC.

Model stateful necesita codec host explícito dump/restore de datos JSON ligado a
model_ref y definición. Sin codec sólo se admite modelo con descriptor estable y
sin estado mutable; una transición a estado no representable falla antes de nueva
interacción/efecto. La plantilla no sustituye silenciosamente el modelo confirmado.
Inventario seleccionado por hooks guarda nombres+fingerprints/schema; restore
resuelve en definición/config host (o rehydrator host explícito) y compara exacto.
No repetir before-model para simular selección ni recuperar handles/credenciales
desde bytes. Un camino run_child sin descriptor durable se rechaza antes de su
primer IO; no descubrir la falta después de repetir la callable padre.

## Batch, delegación, Server, Session y stream

Se conserva Task.async_stream/batch existente. Las tasks preparan calls y solicitan
al writer admisión/intent; al pedir ask retornan un estado interno pending, nunca
ToolReturn succeeded/unknown. Hermanos ya admitidos terminan y confirman outcomes;
el parent reúne todo y persiste paused sólo cuando no queda IO propio en vuelo.
Los resultados del batch mantienen orden original, los pendientes viven fuera de
historia cerrada. Al resume sólo se ejecutan calls pendientes y se reutilizan
outcomes confirmados. Fallos inciertos tienen precedencia sobre paused.

`Coordination.delegation_tool` adquiere un descriptor interno de delegación confiable
en la Tool, preservando builder/deps. El cursor del padre conserva la call pendiente
y el nodo hijo; restore invoca el builder confiable para rehidratar, no la callable
de delegación para repetir el hijo. run_child conserva ascendencia y propaga pausa;
no se promete capturar una pila arbitraria de código app alrededor de run_child.
Esta frontera de nodo/cursor será el seam R6, sin añadir composición R6 ahora.

Server integrado usa la misma fila atómica para snapshot y continuación, nunca
RuntimeCheckpoint.save adicional sobre el envelope. status paused bloquea drenado
y mutaciones de conversación; consulta/decisión/checkpoint siguen disponibles.
Resume crea un nuevo worker bajo guardian existente. Session.pause/resume de turnos
no se redefine: expone/consulta la continuación del participante y no avanza un
turno pendiente como si tuviese output final; su snapshot propio sigue su contrato,
sin prometer transacción entre dos conversaciones/filas.

run_paused/approval_requested se publican después de ACK; PubSub es notificación.
El stream termina con result paused, resume_stream es otra enumeración correlacionada
y un intento nuevo; OTel no conserva spans durante la espera humana.

## Dirty/ACK/crashes y verificación

Writer conserva `Continuation.Checkpoint` exacto al fallar Store: ninguna mutación
ni nuevo IO después, error con checkpoint retry token data-only sin secretos.
ACK perdido se resuelve por receipt/lectura actual; retry devuelve estado consultable
y exige resume nuevo cuando corresponde. Crash sin intent puede reclamar tras
recovery; crash con intent sin outcome exige reconciliación incluso si el host cree
que murió antes de la callable. Después de efecto antes de outcome nunca retry
automático. El owner obsoleto no confirma ni despacha después de perder fence.

La última frase significa obsolescencia conocida en la frontera host, con la
ventana externa descrita arriba. Estados pending/denied y decisiones requieren
recalcular reserva R4: se cobra crecimiento de actor/decision/UTC por aprobación y
receipts necesarios antes de admitir pause, con exacto/+1 y cierre al límite.
Frame/outcome mayor que la cota conserva intent incierto y dirty acotado; no borra
IDs/outcomes previos ni reintenta IO para conseguir datos menores.

R5.1 primero cierra schema/transiciones/errores/ADRs con tests reducer/CAS; después
vertical root pause→decide→resume→finish por API, seguida de ledger/árbol/delegación,
Server/Session/stream y escenarios de crash. No se anuncia C7 por una subunidad.
Oráculos: diarios externos y barreras para save antes/después commit, dos decisiones/
resumers simultáneos, ownerkill en tres ventanas, stale owner, payload/policy/schema
cambiados, nil expiry/deadline/tiempo activo, hermano confirmado+hijo pendiente,
omitted history cero IO, stream terminal único/cleanup/colas. Nueva VM desde bytes
usa fixture de disco test-only; no certifica durabilidad SQL real/G3.

Alternativas descartadas: callback bloqueado no sobrevive VM; replay de prompt
duplica efectos; otro workflow engine duplica el loop; guardar cada frame en filas
independientes requiere coordinación/dual-write que R4 evitó. La migración major
requiere discriminar status y configurar Store/plantillas/actor para C7; ejecución
ordinaria conserva su semántica sin Store. Runtime y APIs nuevas requieren review
fresca; freeze vertical parcial sólo con coordinación y R5 restante explícito.
