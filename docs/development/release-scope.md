# Alcance de ExAgent v2.0.0

**Decisión2026-09-21, replanteo aprobado2026-09-22 (diseño8.22).** El usuario pide una base general propia
para aplicaciones Elixir y confirma incluir aprobación humana persistida (C7).
La estrategia es ExAgent sobre una release oficial ReqLLM stock, sin fork,
vendoring, patch, monkeypatch, parser wire privado ni runtime Jido. El número objetivo es
**2.0.0**; la versión del checkout sigue en1.3.0 hasta el paso autorizado de release.

Este documento define el producto. [Roadmap](roadmap.md) mantiene tareas/estados;
[aceptación](production-acceptance.md) define pruebas y evidencia. El alcance H1
anterior queda en `docs/archive/2026-09-release-scope.md` como historial.

## 1. Qué significa estar listo para producción

La v2 debe cubrir llamadas simples, agentes con tools y output tipado, conversación
con streaming, coordinación/delegación, aprobación persistida y composición acotada,
con operación y recuperación documentadas. Las aplicaciones pueden combinar estos
contratos e incorporar sus propios modelos/tools/stores/policies.

«Cualquier escenario» se traduce en **amplitud de composición y extensibilidad**,
no en afirmar compatibilidad universal de modelos, despliegues, permisos externos,
modalidades o cargas. Se publicará una matriz que diferencie soporte aceptado,
limitado y no verificado. No se atribuyen a OTP rollback ni exactly-once de IO.

## 2. Capacidades comprometidas

Todo lo siguiente es alcance objetivo, no afirmación de que ya esté implementado.

| Capacidad | Resultado esperado de v2 | Verificación principal |
|---|---|---|
| Modelos | ReqLLM principal, specs fuera de catálogo y extensiones custom sin depender de Jido | R1/R8.1 |
| Ejecución | Un contrato de run/stream, outputs completos o error con progreso, límites y cancelación | R2/R3 |
| Tools | Sobre obligatorio genérico candidato, validación local del objeto semántico y args efectivos antes de efectos; DI, autoridad ancestral, outcomes/retries explícitos | R1.2/R2/R3/R5 |
| Output | Ecto validado, modo tool y JSON Schema nativo explícito en combinaciones aceptadas | R2/R8.1 |
| Contenido | Texto; imagen, thinking y continuación sólo en perfiles cualificados sin pérdida de datos requeridos | R1/R2/R8.1 |
| Uso/coste | Contadores host exactos y admisión atómica; tokens/cache normalizados o reportados, coste estimado con calidad/procedencia/disponibilidad, sin doble conteo ni promesa de factura | R1/R3/R5 |
| Runtime | Server opcional, requests correlacionadas, colas acotadas, ownership y lifecycle de conversación | R3 |
| Contexto | Historia canónica, proyección/compaction e invariantes call/result | R3 |
| Coordinación | Participantes humanos/agentes, Session single-writer, turnos/handoff y delegación | R3/R6 |
| Store | Snapshots y continuación; ETS efímero, Postgres durable opcional, capabilities/CAS y migración | R4/R8.2 |
| C7 | Pausa antes de una tool, decisión persistida, resume con autoridad vigente y revisión reclamada atómicamente | R5 |
| Composición | Secuencia, routing, fan-out/fan-in acotados; parciales y continuación de pasos definidos | R6 |
| MCP | Cliente stdio y remoto Streamable HTTP sobre adapter/dependencia mantenida; misma frontera Tool | R7/R8 |
| Observabilidad | OTel opt-in, privacidad, recursos acotados y Langfuse/Opik igualmente cualificados por transporte nativo, API y UI del perfil A10 (mandato2026-10-02) | R7/R8 |
| Integración app | Recetas Phoenix/PubSub y jobs; retrieval externo como tool/Capability | R7/R8.3 |
| Distribución | Paquete mínimo instalable, grafos opt-in, CI portable, docs y guía1.x→2.0.0 | R8/R9 |

La mayoría del core/runtime ya tiene una base implementada; ReqLLM, C7 y las
extensiones nuevas necesitan implementación y aceptación propias. No hay que
reescribir lo que ya satisface el contrato para cerrar una fila.

## 3. Fronteras de responsabilidad

**ExAgent:** loop, resultado, tool runtime, autoridad y admisión del trabajo que
posee, eventos, datos de continuación y contratos de recuperación.

**ReqLLM:** interacción de modelo, transporte, codecs, normalización y capacidades
de proveedor. No ejecuta el loop ni autoriza tools de ExAgent.

El sobre `{"arguments": objeto_lógico}` es la primera vía a verificar, no una
mitigación aceptada. ExAgent valida sobre/schema original, luego revalida args
efectivos tras hooks y autoriza; callbacks upstream noop. No promete raw que
ReqLLM pierde ni repara invalidez explícita/truncación. Schema no representable
(refs/raíz/strict incluidos) rechaza antes de IO, sin rewriter general preventivo.

Streaming tendrá una única vista, lazy host, terminal válido antes de efectos y
cleanup incluso ante owner kill. **No hard RAM predecode upstream**, sí admisión,
concurrencia/deadlines y retención/queues/chunks/bytes propios postdecode acotados
y medidos; documentar coste O(respuesta), buffered e historia canónica. La falta
de cota predecode no autoriza memoria propia infinita ni abandonar cleanup.

Uso normalizado no demuestra presencia: cero normalizado no es cero observado,
ni cero implica unknown. La ejecución ordinaria puede continuar limitada por
contadores host aunque falte accounting; límites strict que dependen de datos
ausentes rechazan explícitamente, sin degradarse a estimados. Los umbrales de
tokens/coste estimados frenan admisiones futuras con posible exceso en vuelo;
no son saldo transaccional ni factura. Conservar unidades, availability al
persistir, reconciliación por identidad y OTel sin volver a sumar hijos.

**Aplicación:** autenticación del humano, permisos de negocio/tenant, credenciales,
tools de dominio, idempotencia externa, elección y operación de DB/colas/backend.
El framework recibe contexto confiable y aplica su contrato; no inventa identidad
del aprobador a partir del texto del modelo.

**Stores/adapters:** garantías de IO y atomicidad declaradas. Un Store de snapshots
sin CAS/transacción no anuncia soporte de continuación concurrente. ETS no persiste
tras reiniciar la VM; Postgres sólo se acepta después de comprobarlo realmente.

## 4. Recuperación y aprobación: alcance exacto

1. Conversación guardada y run pausado son entidades distintas. Mantener una
   conversación no implica que existan pasos pendientes reanudables.
2. Una aprobación se liga a tool/args efectivos, IDs, versión/revisión y contexto
   de autoridad. No puede convertirse en una aprobación genérica reutilizable.
3. ACK de pausa/decisión durable exige persistencia confirmada. Un evento perdido
   se recupera consultando estado; PubSub no es la fuente de verdad durable.
4. Dos consumidores no reclaman simultáneamente la misma revisión. Un owner antiguo
   no confirma estado nuevo con resultados tardíos. La recuperación de efectos
   in-flight conserva incertidumbre y requiere reconciliación o retry explícito.
5. Reanudar reconstruye definiciones y deps confiables, revalida restricciones y
   contabiliza lo ya consumido. No serializa funciones, procesos ni SDK handles.
6. Pausa en delegación/batch/composición debe conservar pasos confirmados y alcanzar
   una frontera acotada sin dejar tasks propias ejecutándose tras devolver paused.
7. Stream pausado acaba; resume abre otro stream correlacionado. Expiración, denegación,
   cancelación y cambios de definición tienen errores/resultados documentados.

Los nombres y schema definitivos se deciden en R2/R4/R5 con evidencia. No se promete
retomar una instrucción Elixir arbitraria ni deduplicar una API externa sin soporte
de idempotencia de la aplicación/proveedor.

## 5. Estabilidad y migración

- API pequeña estable; superficies experimentales identificadas explícitamente.
  Experimentación no se usa para eludir contratos centrales anunciados como v2.
- Conservar semánticas válidas donde sea práctico; corregir ahora los problemas
  demostrados de mensajes, errores, defaults, snapshots y lifecycle conjuntamente.
- Migración documentada de helpers de provider retirados, Model custom, settings,
  eventos/resultados pausados, Usage/UsageLimits/OTel, sobre/schema y versión de
  codec/historia/Store. Nunca envolver llamadas históricas inválidas para hacerlas
  válidas, ni fallback automático al wire anterior. No mantener dos modos
  generales de ejecución para evitar reconocer una major.
- Conservar lectores de snapshots válidos ya soportados o justificar un migrador
  explícito. Datos corruptos/futuros fallan sin sobrescribir los buenos.
- La API de aplicación no persiste structs completos de ReqLLM/Jido como si fueran
  nuestro formato estable; sólo datos definidos para esa finalidad.

## 6. Matriz de soporte objetivo

- ReqLLM1.24.0 es referencia investigada; versión/lock finales se fijan en R1/R9.
- Mínimo inicial obligatorio: un perfil Chat-compatible sin reasoning ni features
  provider-native, con tools, Ecto-tool y streaming en modelo/endpoint/API/config
  exactos. Sigue pendiente de gate offline y G2 live; no es soporte anunciado hoy.
- Responses, Anthropic, Google, imagen y output nativo se cualifican por combinación
  probada, no son todas familias obligatorias para cerrar R1. Paths con metadata
  perdida quedan fuera antes de IO; reasoning.enabled:false no demuestra ausencia.
  Ninguna pérdida ni fallback silencioso de modelo/proveedor. Model custom, specs
  fuera de catálogo y gateways por instancia mantienen extensibilidad; el catálogo
  no certifica capacidades. G2 es obligatorio para toda combinación anunciada.
- R1.1 resuelve un mínimo efectivo Elixir1.18 por `llm_db`, obligatorio en
  ReqLLM1.24.0. Sustituye el objetivo inicial1.17/OTP27, con decisión autorizada
  y migración en diseño8.15; targets actuales1.18/OTP28 y1.20/OTP29. Los patches
  realmente ejecutados se registran aparte de los objetivos y la CI remota.
- Un único owner lógico por conversación y claims atómicos de continuación. No
  promesa de cluster activo-activo, failover regional o ejecución distribuida general.
- SQL, Phoenix y OTel opt-in; sin plataforma comercial obligatoria. La app posee
  repositorio, configuración global y servicios. Límites/retención se documentan.

## 7. Fuera de v2.0.0

- Motor de replay universal, exactamente una vez externo, rollback de herramientas,
  scheduler distribuido o persistencia de procesos vivos.
- Copiar Pods/signals/plugins completos de Jido; soporte A2A general o bus nuevo.
- Motor RAG/vector DB propio, memoria semántica universal o knowledge-base de dominio.
- Sandbox/coding agent completo, gestión de entornos OS y catálogo de tools de producto.
- Plataformas propias de evals, prompts/datasets, tracing o facturación.
- Fork/vendor/patch/monkeypatch de ReqLLM, parser wire/SSE/transporte paralelo
  propio para suplir gaps, hard RAM predecode y fidelidad de bytes raw no expuestos.
- Voz/vídeo/realtime bidireccional y todas las modalidades de ReqLLM en el loop común.
  Pueden usarse por composición externa con límites explícitos.
- Adaptación de las apps del usuario y publicación sin autorización separada.

Estas exclusiones no impiden integrar servicios o añadir extensiones posteriores.
Una feature requerida de la tabla no se mueve aquí por dificultad sin decisión
explícita de alcance. La salida estable puede tener límites; no puede tener promesas
centrales que sólo funcionan en el camino feliz.

## 8. Estado y salida

R1–R9 están implementados y aceptados en los perfiles delimitados del
[estado vigente](../status.md), incluida aprobación persistida C7, coordinación,
durabilidad SQL y observabilidad con igual aceptación de Langfuse y Opik.
Los guards de perfiles no cualificados permanecen intactos. El ADR histórico
paused de R2 no representa el estado actual de C7.

Las descripciones objetivo anteriores no sustituyen el tablero único del
[roadmap](roadmap.md) ni los recibos de cada gate. G5 conserva el diagnóstico
estricto rojo de dependencias stock; los contratos funcionales del TAR pasan.
La candidata no es una versión publicada: quedan la decisión explícita sobre
ese diagnóstico y el paso autorizado de versión/notas/tag/Hex. La release será
**publicada** sólo tras verificar el artefacto Hex2.0.0. Los perfiles adicionales
no cualificados y los tests excluidos no se presentan como garantías aceptadas.
