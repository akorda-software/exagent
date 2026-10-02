# Relevo preparado: continuar v2 con ReqLLM oficial stock

**Contexto histórico:** entrada vigente `docs/prompts/continue-native.md` y método
`docs/development/execution-flow.md`. Las «primeras acciones» y revisiones fechadas
inferiores no reinician R1/R4/R5 ni añaden rondas al trabajo actual.

**Preparado2026-09-22; no se activa por lectura ni por contexto de una Task.**
El usuario autorizó continuar la implementación, pero la Task documental que
prepara este relevo termina antes: revisión fresca y nueva Task de implementación.
Cuando se encargue ejecutar este prompt, implementa el alcance R0–R9 desde el
estado real hasta candidata aceptada o bloqueo sin trabajo independiente viable.
Si el dispatch limita la tarea, respeta ese límite. Habla en español.

## 1. Primera acción concreta: Task R5/C7 fresca tras cierre R4

Recepción documental posterior al freeze: coordinador msg_57de32de8f89 acepta
R4.1–R4.6 offline sobre sourcecdd2a042/TARac544712/manifest1488bbd6. Review final
independiente compile80/focal33/snippets9/deltas279/TAR103 exit0, sin P1/P2 concreto;
P2cleanup/P3guías cerrados. Artefactos inmutables, esta recepción no está en ellos.
R5/C7 está autorizado como siguiente Task con contexto fresco después del cierre
y cesión de ROOT/docs/builds por owner R4, no como expansión de esa Task.

R4 integrada y verificada owner: compile80/focal121/seam3/suite803/0/28 seed37556;
formato/snippets9/ExDoc/links/plan exit0. Identidades y distribución en
`docs/archive/2026-09-26-r4-integration.md`. Revalidación independiente recibida;
no reimportar ni reauditar R0–3. Leer este relevo no sustituye el Dispatch R5 fresco.

R3.4 source05a02459/TAR8775e665 aceptados tras cierre independiente de cuatro P2
por task_d3420f865920 (compile74/probes6/focal85). Gate_1a7cfef26f1f abre integración
del delta R4 corregido sourceb3498467/deltab5052dbb, con owner exclusivo ROOT.
Preservar Snapshot4/omitted-v1/accounting1/continuation2/envelope1 y ADR8.32;
fusionar ADR8.33/docs y exigir pruebas/review del artefacto integrado nuevo.
R5/C7 no se activa en esta integración; gates externos continúan abiertos.

### Contexto histórico de la unidad R3 parcial

R3 parcial verificada owner task_d50e5f22ec68: diseño8.30/31 namespace y admisión
Server por bytes, receta pública; compile73/focal122/suite718/0/28 seed37556,
snippets9/9 seed0 y formato exit0. Freeze/gates en
`docs/archive/2026-09-26-r3-runtime.md`. Review independiente pendiente.
R3.4 salida ABIERTA por acuerdo expreso: repro tool65536B→historia68792B con
límite admisión1024/efecto1; no anunciar cota actual. Nueva unidad fresca core
postdecode requiere ADR propio antes de cambiar outcomes/omisión/error terminal.
No reabrir R2/R1 aceptadas ni iniciar R4/C7 automáticamente.

### Base recibida R2

Task task_9db4ebef2186 / ctx_364b1ec146e6 implementó y verificó diseño8.29:
native explícito separado, Ecto final, retry contable e historia sync/stream,
combinación tools y límites semánticos refusal stock documentados. Compile71,
suite699/0/28 seed37556, snippets8/8 y consumidor75/0/0 de grafo fijo copiado;
freeze y gate documental final en `docs/archive/2026-09-26-r2-output.md`.
Estas cifras iniciales quedan sustituidas por el cierre R2.3: suite707/0/28,
consumidor80/0/0 fijo, TARf6b549f5/source7eb34210 y review task_f955b8e8ea60
sin P1/P2 pendientes (compile71/focal32 seed92624; fixture1/3→3/3).
Coordinador17/17 e identidad93/253 exit0; gate_60c09b5f327e aceptado.
Task task_d50e5f22ec68 inicia sólo R3.1–6: matriz criterio/evidencia/hueco,
reutilizar runtime existente y consultar cambios Store compartido antes de editar.
No activar R4/R5/C7 por leer este prompt ni repetir R2/R1 aceptadas.

Task `task_f4d76a03826d`, mismo dispatch `ctx_61707a7c0be0`, reanudada tras relevo
autorizado: R2.1/2/4/5/6 con diseño8.27–28, siete oráculos nuevos, compile71,
suite687/0/28 seed37556 y focal98 exit0. Consultar roadmap§5 y registro
`docs/archive/2026-09-26-r2-base.md` para evidencia consumidor/TAR y estado final.
Review Astra task_28d681ef6334 aceptada sin P1/P2 sobre TAR482e26a3/source1eefe618:
compile71/focal54/probes6 seed82619 y coordinador focal38 exit0. Consumidor63/0/0
fijo y suite687 se reutilizan sólo en frontera intacta; no repetir R0/R1 ni
reiniciar el mapa ya escrito. Task task_9db4ebef2186 inicia R2.3 native separada;
R2 quedó aceptada posteriormente según cabecera; Store/C7 runtime no se activan por este relevo.
Paused es sólo diseño para R4/R5; after_model transforma antes de admisión,
before_tool conserva identidad universal. Lo siguiente es contexto histórico R1.

Actualización2026-09-26: R1.4 recibió aceptación fresca STREAM PARCIAL offline;
R1.5 aceptada por `task_5b79c7a35e0c`,173/173 exit0, TAR3c7867ad y consumidor48/0/0
fijo copiado. R1.3/6/7 mínimo `chat_tools_v1` ahora verificado por owner con
compile80/suite755/0/28 seed37556; cuatro oráculos nuevos y runtime intacto.
Review final recibida4/4, identidad TARd2bfe978 y corrección documental cerrada.
R1.8 implementada por task_51127c5dd54e, compile71/suite680/0/28 offline; review
`task_a7e85474a9ef` acepta TAR6a2eb6aa, P2 documental cerrado, sin P1/P2 pendientes.
El cierre documental26Sep preserva AST funcional y tests/config/mix/lock; identidad,
gates nuevos y alcance de reutilización de evidencia constan según roadmap§5 en:
`docs/archive/2026-09-25-r1-retirement.md`. No reactivar retirada ya ejecutada.
No inferir G2/C7/R1 completo; no repetir R1.4/R1.5 aceptados. La antigua siguiente
acción R2.1 ya avanzó en la Task arriba; seguir el estado único de roadmap§5.
La recuperación siguiente conserva contexto anterior, no el primer paso actual.

Tras recuperar checkout/ownership/entorno, lee el estado final de R1.4 en roadmap
y el registro `docs/archive/2026-09-22-r1-stream-adapter.md`: implementación
stream cualificada y gates/revisión fresca que allí consten, sin inferir aceptación
por este prompt. R1.2 buffered ya recibió review parcial offline, P2 corregido;
no rehacer su gate ni R0/R1.1/Jido. Si R1.4 está aceptada, siguiente unidad R1.5;
si sigue pendiente de review/gate, completar sólo lo pendiente bajo el dispatch.
El resto de este prompt conserva criterios del mandato, no autoriza ampliar una Task.

Lecturas de recuperación, una vez y enfocadas:

1. AGENTS, docs/README, status, handoff y roadmap§5: son el estado real/único tablero.
2. Diseño2.1–2.3 y8.22, release-scope, production-acceptance (A1–A10/G1–G6 y gate
   inicial R1.2), changelog/migración; framework-direction§9 contiene la síntesis
   durable/versiones/permalinks, no hace falta el informe temporal de investigación.
3. Environment/verification y las fuentes/tests de la frontera elegida.

Comprueba HEAD/diff/untracked, lock, runtime efectivo, tooling aislado y builds
concurrentes sin exponer secretos. Base anterior: HEAD7f25b33 + WIP,
nominal1.3.0, ReqLLM1.24.0 stock, Req0.7.4/Mint1.10.1/Finch0.22 raíz;
691/0/28 y los hashes/TAR del relevo son **históricos**, no pases nuevos.
Preserva WIP de usuario y otros owners. Reusa tests/reproducciones existentes.

## 2. Decisión cerrada y fronteras que sí deben implementarse

- **Sólo release oficial stock ReqLLM** por API pública. Sin fork/vendor/patch/
  monkeypatch/parser wire privado, SSE/transporte paralelo ni runtime Jido. No
  adoptar main o spike usage; una futura release se cualifica, no se presume.
- ExAgent posee loop, Model mínimo, herramientas, DI, validación JSV/Ecto,
  hooks/permisos, contadores host, eventos, historia, Store y C7. ReqLLM hace una
  interacción y sus tools llevan callbacks noop; nunca ejecuta nuestros callables.
- Primer perfil obligatorio: Chat-compatible sin reasoning ni features provider-native,
  tools/Ecto-tool/stream, modelo/endpoint/API/config exactos todavía por cualificar.
  Mantener Model custom, specs fuera de catálogo y gateway por instancia. No imponer
  Responses/Anthropic/Google como cuatro familias obligatorias para cerrar R1;
  aceptar sólo combinaciones demostradas, sin pérdida ni fallback silencioso.
- Paths que pierden metadata necesaria siguen cerrados antes de IO. Un flag
  reasoning.enabled:false no prueba que no llegarán bloques requeridos. Commit
  Anthropic3536ff94 posterior a1.24.0 sólo guía seguimiento de una release oficial;
  no está adoptado/publicado en la versión actual ni demuestra resolver Google.

### Gate: datos, schema, proyección y cero efectos

Inspecciona las fronteras existentes `models/req_llm.ex`, Model/Message/codec,
Tool/Schema/OutputSchema, hooks y tests ReqLLM. Crea el mínimo cambio/fixture
necesario para probar la hipótesis, conservando cierre del perfil general hasta
aceptación. No mockees la feature ni reemplaces ReqLLM por un Model falso para
declarar este gate verde. El transporte puede devolver bytes sintéticos y observar
payloads; usa un diario/contador real para efectos y callback noop como control.

Sobre conceptual obligatorio: objeto exterior con única propiedad `arguments`
requerida, `additionalProperties:false`, cuyo valor es el schema lógico de objeto
soportado. Tool vacía legítima: `{"arguments":{}}`. El schema no se debilita para
adaptarlo: anunciar al proveedor no reemplaza validación local.

1. **Negativos buffered y una vista stream:** `[]`, `[{}]`, `null`, string, número,
   boolean, `{}`, JSON truncado, `{"arguments":[]}`, missing/extra outer keys:
   cero efectos. Preserva/rechaza señales de invalidez expuestas por upstream;
   no repair, casts lista→mapa, defaults del sobre, Map.get fallback ni wire previo.
2. **Controles positivos:** exactamente un efecto para vacío válido y otro objeto
   válido no vacío, IDs preservados y outcome correcto. No basta bloquear todo.
3. **Validación/autoridad:** valida envelope y schema lógico, entrega args lógicos
   a hooks, revalida los efectivos antes de permisos/callable. Identidad inmutable,
   ancestros no ampliados. ReqLLM.Tool.validate_input con compiled:nil no acredita
   JSON Schema. No prometas bytes raw ni claves duplicadas que stock perdió:
   valida el objeto semántico recibido, sin legitimar invalidez explícita/truncación.
4. **Schema/raíz:** required/optional/defaults, additionalProperties, anidados,
   arrays/enums/nulls, boolean schemas. `#`, `#/$defs/...`, `$id`, anchors,
   `$dynamicRef`/refs externas pueden cambiar significado al anidar: fija subset
   representable y rechaza lo demás antes de IO, o demuestra adaptación pequeña.
   No rewriter general preventivo ni resolución remota/file de schema.
5. **Strict:** inspecciona payload efectivo stock por perfil, required y
   additionalProperties de objetos anidados. No optional→required ni aplicar
   defaults nuevos silenciosamente. Si no es representable, falla explícitamente.
6. **History/codec:** segundo turno modelo→tool→modelo, sobre exactamente una vez,
   IDs/orden/resultados/metadata permitida intactos. Hooks/aprobación ven args
   lógicos. Versiona wire/codec/snapshot/restore/compaction y define migración o
   rechazo de historia anterior; nunca envolver una llamada histórica inválida para
   hacerla válida, inferir versión ambiguamente ni fallback wire viejo.
7. **Output:** final_result/Ecto-tool usa el mismo sobre validado; vacío válido,
   embeds/nulls, inválido y retry contabilizado. Ecto sigue autoridad final;
   structured output nativo es contrato separado por perfil.
8. **Terminal/cleanup:** incomplete/length/filter/unknown, EOF, timeout y cancel no
   ejecutan tools parciales ni presentan output completo; success/halt/exception/
   owner kill cierran transporte/metadata y recursos propios. Lazy host y una sola
   enumeración. Si sólo buffered pasa, registra aceptación parcial, no R1 completo.

Conserva/añade regresiones que distingan la causa y positivos. Documenta API y
migración antes de estabilizarlas. Solicita revisión fresca de R1 según roadmap;
sólo habilita perfiles cuyo gate haya pasado, nunca todos por catálogo.

## 3. Continuidad al pasar el gate

No termines en el spike. Integra el resultado R1.2 y continúa R1.3–R1.8 con sus
dependencias, después R2–R9 (R0 ya recuperado), conservando57 IDs y un tablero.
Unidades independientes pueden avanzar ante bloqueo externo preciso.

### Streaming R1.4

Prueba primero **process_stream/2 con callbacks y Response final**, candidato por
menor materializador provider-aware propio. Puedes elegir events/1 público si los
gates demuestran mejor frontera; documenta por qué. Nunca mezcles vistas ni events
seguido de to_response. Stock process_stream hace Enum.map y retiene O(respuesta).

Contrato nuevo: lazy host, terminal válido antes de efectos, deadlines/receive,
concurrencia/admisión y queues/retención propia postdecode acotadas en chunks/bytes,
salida máxima solicitada y medición finita con consumidor lento. **No hard RAM
predecode upstream**, ni para buffered; un frame ya puede estar asignado cuando
salte el umbral. Eso no renuncia a cleanup, cancel, límites propios ni documentar
memoria canónica. No implementar transporte/SSE propio ni knobs que stock rechaza.

### Uso R1.5, scope R3 y OTel R7

Contadores exactos HOST: intentos Model admitidos/tools reservadas, reserva
atómica de capacidad, identidad y no doble conteo. Deshabilita retries invisibles
o contabiliza cada intento de forma demostrada; max_retries:0 es la base probada.

Tokens/cache/coste: métricas normalizadas/reportadas y estimaciones con calidad,
procedencia/disponibilidad explícitas, no factura. Cero normalizado no es observado;
no uses heurística cero→unknown ni parsers por proveedor. Mantén USD↔céntimos,
semántica cache/reasoning y availability en snapshots; evento/terminal/restore/hijos
no se suman dos veces. Define nombres y migración públicos antes de integrar.

Ordinary execution con límites host no se bloquea sólo porque falte accounting.
Quien pide límites estrictos dependientes de datos ausentes recibe rechazo
explícito; no convertir strict a best-effort silenciosamente. Umbrales estimados
pueden detener nuevas admisiones pero excederse en vuelo. OTel refleja calidad y
una generación una vez, con privacidad y subtotales separados.

### C7/R4/R5 y retirada R1.8

C7 permanece requerido: persistir llamada lógica exacta/args efectivos/versión
de definición/codec/outcomes, ACK sólo tras save, claim atómico, autoridad actual
al restore y no replay. Crash entre efecto/save queda incierto; lease/token no
autorizan retry automático. No sustituir por callback bloqueado o snapshot solo.

R1.8 retira adapters/transporte/helpers duplicados tras perfiles requeridos
aceptados, con inventario y migración major. No modo legacy general permanente.
Mantén Model/Test/extensiones públicas; no modificar consumidores reales.

## 4. Gates, stops y permisos

Usa environment/verification con tooling aislado ya disponible. Focales al cambiar
frontera; al cerrar unidad runtime: compilación/formato y
`EXAGENT_OFFLINE=1 MIX_ENV=test mix test`, con comando/seed/exit/pass/fail/excluded.
Revalidar consumidor y gates afectados por schema/transporte/usage; no repetir
matrices por párrafos ni aceptar BEAM antiguos como fuente nueva. G2 live sigue
obligatorio para capacidades anunciadas; G3 SQL/G4 backend/G5 paquete-CI/G6 operación
siguen vigentes. Offline no los sustituye. Revisiones frescas según R1/R4/R5/R9.

**Stop de la opción:** efecto inválido, schema/strict/history no representable,
pérdida de metadata necesaria, cleanup no demostrado, o necesidad de fork/patch/
API privada/parser wire/rewriter general. Mantén guard, guarda caso exacto y
evidencia, acota perfil o espera release oficial según alcance; escala cualquier
recorte adicional no aprobado. No repitas intentos idénticos sin evidencia nueva.

**Permisos:** sin commit/push/PR/tag/bump/publicación, cambio global, reinicios,
consumidores, servicios live/pagados/DB/backend ni lectura/divulgación de secretos
sin autorización expresa específica. Keys presentes no autorizan gasto. Respeta
incidente Hex y ownership exclusivo de archivos/build. Edita manualmente con
apply_patch; no alteres scripts para maquillar checkers ni expectativas para verde.

**Contexto y modelos:** Astra con contexto fresco por defecto; GLM5.3/Grok4.6
para trabajo sencillo delimitado si se autoriza delegación. Reusar contexto sólo
con ventaja clara; fronteras críticas y review requieren frescura. Un coordinador
Orca sigue su skill/autoridad vigente; un worker despachado no delega y se ciñe al
dispatch. Ningún prompt concede permisos nuevos de orquestación por su lectura.

## 5. Entrega verificable

Actualiza sólo el tablero roadmap y relevo/status/contratos pertinentes: ID,
estado real, rutas/diff, comandos/exits, revisión/lock/hash, efectos observados,
límites, revisión fresca y siguiente acción concreta. No marcar verde por replan
ni atribuir691/0/28 al cambio nuevo. Conservar evidencia importante durable;
logs grandes pueden ser temporales con resumen reproducible en repo.

Si falta permiso externo, agrupa destinos/presupuesto/DB/Opik/CI necesarios una
vez y continúa trabajo independiente real. Al terminar, entrega candidata o
bloqueo preciso, nunca «v2 publicada» sin autorización y gate del artefacto final.
