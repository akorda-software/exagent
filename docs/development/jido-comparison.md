# Auditoría comparativa: ExAgent y Jido

**Corte histórico: 2026-09-21. Evaluación técnica/estratégica, no mandato activo.**

> **Decisión posterior2026-09-22:** ExAgent propio sobre ReqLLM oficial stock,
> sin fork ni runtime Jido; [diseño8.22](../architecture/design.md) y
> [síntesis versionada](framework-direction.md#9-investigación-jido-reqllm-del-2026-09-22)
> sustituyen la recomendación/prueba pendiente de este corte. Jido AI2.3.0
> (`2f83b922…`) declara ~>1.14 pero su lock fija **1.17.1**; main inspeccionado
> (`05ac7051…`) fija **1.22.0**. La referencia1.14.0 de abajo no era el lock real.
> La investigación nueva constata normalización inválido→vacío y ausencia de
> garantías equivalentes de presencia, hard RAM y C7; no se reejecutaron tests.
> El sobre obligatorio es hipótesis con gate previo a retirar guards, no solución
> heredada de Jido. Las secciones siguientes conservan intacto su corte histórico.

> **Aclaración posterior del usuario, el mismo día:** la prioridad es su paquete
> general para futuras apps, sin restricciones de las pruebas de concepto actuales;
> solicita adoptar ReqLLM. La [dirección del paquete](framework-direction.md)
> actualiza la recomendación y el siguiente paso. La evidencia técnica de esta
> comparación conserva su alcance y sus versiones.
> El [roadmap v2](roadmap.md) posterior incluye C7 por confirmación expresa;
> las menciones H1–H6/C7 diferido de este informe describen el corte auditado,
> no el nuevo compromiso de implementación.

## 1. Conclusión ejecutiva

**Jido es una alternativa real para los casos de uso planteados. ExAgent no es
redundante en todos sus contratos, pero sí comparte una parte importante de sus
funciones con el ecosistema Jido.**

La comparación útil es ExAgent frente a **Jido + Jido AI + ReqLLM**, añadiendo
adaptadores cuando el caso necesita SQL, MCP u observabilidad. `jido` por sí solo
no es un sustituto del loop LLM de ExAgent.

Recomendación:

1. No ampliar ExAgent para competir con todo el ecosistema Jido.
2. Conservar provisionalmente el núcleo existente por sus contratos de ejecución,
   Ecto, autoridad/presupuesto compartidos y checkpoint confirmado.
3. Antes de invertir en más infraestructura propia, hacer una prueba comparativa
   finita que mida cuánto código propio exige cada opción.
4. Dar prioridad a evaluar **ReqLLM detrás de `ExAgent.Model`** como vía para
   reducir mantenimiento de proveedores. Es una hipótesis por verificar, no una
   integración aceptada ni una revocación de la decisión de diseño 8.4.
5. Si los requisitos reales se satisfacen con Jido y una capa pequeña de aplicación,
   adoptar Jido y retirar progresivamente el framework duplicado. El trabajo ya
   invertido no es razón suficiente para mantener dos implementaciones.

Si el objetivo principal fuese lanzar aplicaciones nuevas, partiría de evaluar
Jido/ReqLLM antes de crear un framework propio. Para justificar ExAgent como
producto Hex independiente, su valor debe ser más preciso que «agentes en Elixir»:
**ejecución LLM tipada y controlada, con contratos coherentes entre run, stream,
delegación y persistencia, y runtime opcional.**

## 2. Alcance y calidad de la evidencia

| Componente | Corte examinado | Evidencia |
|---|---|---|
| ExAgent | HEAD `7f25b336924d97baf1d4aa18898ec8db32385940`, nominal 1.3.0, con cambios documentales/manifiesto preexistentes | Estado y alcance vigentes, diseño, código de Session, ExecutionScope, permisos, coordinación y checkpoint. |
| Jido | Hex 2.3.1; tag `v2.3.1`, commit `b1b5a5b8542a7a4d6ea10e9c6c39d5b6b285f606` | Metadata Hex, documentación versionada, fuentes del tag, persistencia y patrones runtime. |
| Jido AI | Hex 2.3.0; tag `v2.3.0`, commit `2f83b922edcca3deb9e92b6391d198a0c14f5da3` | Metadata Hex, documentación versionada, código de ReAct, output, cuotas, efectos y tokens; lectura de tests. |
| ReqLLM | 1.14.0 como referencia publicada del rango requerido | Metadata Hex y README del tag; no auditoría completa de adapters/transporte. |
| Extensiones | `jido_otel` 1.0.0, `jido_ecto` 1.0.0 y estado de `jido_mcp` | Documentación publicada y metadata Hex. |

Jido AI 2.3.0 declara `jido ~> 2.3`, `req_llm ~> 1.14` y `jido_action ~> 2.3`.
Por tanto, Jido 2.3.1 encaja en el rango declarado. No se resolvió/compiló un
consumidor completo con esas versiones: compatibilidad declarada no equivale a
aceptación integrada. Los rangos admiten versiones posteriores; un spike debe
guardar su lock exacto.

Esta auditoría incluye **dos comprobaciones ejecutadas del módulo real de cuotas**
de Jido AI, sin dependencias ni proveedores, descritas en §10. El resto es
inspección documental y de código; leer un test no demuestra que haya pasado aquí.
No se ejecutaron las suites completas, proveedores, SQL ni aplicaciones consumidoras.
Los 655 tests correctos/28 excluidos de ExAgent son evidencia histórica del
2026-09-10, no un resultado nuevo de esta comparación.

## 3. Qué se parece y qué cambia de modelo mental

Ambos separan definición de agente y proceso, aprovechan OTP, admiten tools,
eventos y persistencia opcional. No sería correcto defender ExAgent alegando que
Jido obliga siempre a levantar un GenServer: Jido tiene `cmd/2` sobre datos y
Jido AI ofrece un runtime ReAct independiente del AgentServer.

| Capa | ExAgent | Ecosistema Jido |
|---|---|---|
| Definición | `%ExAgent{}` reutilizable | Módulo/struct `Jido.Agent`; `Jido.AI.Agent` para LLM |
| Unidad de trabajo | Tool con callable, schema y contexto | `Jido.Action` con schema, `run/2` y resultados/efectos |
| Loop LLM | `run/3` y `run_stream/3` | `Jido.AI.Reasoning.ReAct`; estrategias adicionales |
| Estado conversacional | `ExAgent.Server` | `Jido.AgentServer` + estrategia/contexto AI |
| Coordinación | Session, participantes y TurnPolicy | Signals, FSM, hijos, InstanceManager y Pods |
| Proveedores | Model + adapters propios | ReqLLM |
| Persistencia | Snapshots de Server/Session | Checkpoint + journal Thread; tokens de continuación ReAct |

Jido es una plataforma de agentes y automatización más amplia. ExAgent está más
centrado en el contrato de una ejecución LLM y en coordinación por turnos.

Un Pod no equivale a una Session: conserva topología y ownership de un equipo;
no aporta por esa sola abstracción roster humano, iniciativa y autoridad de turno.
Un journal tampoco equivale a deduplicación de efectos externos.

## 4. Matriz funcional

«Adaptar» significa trabajo viable sobre APIs existentes; «no equivalente» no
significa imposibilidad de implementarlo ni defecto del otro proyecto.

| Necesidad | ExAgent actual | Jido y extensiones examinadas | Evaluación |
|---|---|---|---|
| Chat, tools y streaming | Implementados en un loop común | ReAct con tools, eventos y ejecución standalone | Solapamiento alto. |
| Output estructurado validado | Ecto/changeset, schema derivado y retry | `Jido.AI.Output`: Zoi o JSON Schema, validación y reparación | Ambos lo tienen. La diferencia es Ecto y la semántica, no «JSON sí/no». |
| Variedad de proveedores | Dos protocolos propios y wrappers/gateways | ReqLLM documenta 21 integraciones en 1.14.0, incluidas Google, Azure y Bedrock | Ventaja clara de amplitud para ReqLLM; catálogo no certifica cada operación/modelo. |
| Tiempo real y LiveView | Event versionado + PubSub opt-in | Signals, Phoenix.PubSub y streams por request | Ambos encajan; hay que adaptar eventos/correlación. |
| Equipos y jerarquía | Delegación + Session | Hijos, Pods, particiones, reconciliación, activación lazy | Jido cubre más infraestructura general de equipos. |
| Turnos humanos/bots | Roster y políticas ya implementados | Coordinador propio usando FSM/actions/signals | Viable, pero no sustitución directa de Session. |
| Presupuesto por árbol | Admisión compartida, ancestros, reconciliación por identidad | Plugin de cuotas por scope/ventana a partir de señales de uso | No equivalente; ver §5.1. |
| Permisos y aprobación | `allow/ask/deny`, callback síncrono e intersección de ancestros | Allowed tools, request transformer, guardrail y políticas de efectos | Hay controles; no se identificó el mismo contrato completo de autoridad heredada. |
| Reintentos de tools | Corrección explícita; fallo incierto no autoriza retry automático | Retry de errores clasificados retryable, configurable | Revisar defaults e idempotencia; ver §5.2. |
| Guardar conversación | ETS/Postgres opt-in; ACK tras save y estado dirty | ETS/File/Redis, storage extensible, `jido_ecto`; hibernate/thaw | Ambos persisten, con semánticas distintas. |
| Continuación de un run | No incluida; C7 pospuesto | Tokens ReAct `start/continue/collect/cancel` | Ventaja funcional Jido, sin asumir exactly-once o aprobación humana durable. |
| Compactación | Proyección de request y Summary; conserva historia canónica | Thread canónico + Context; operación replace con razón compaction | Hay base comparable; no se verificó equivalencia con la política automática de ExAgent. |
| Observabilidad | OTel opcional; privacidad y límites propios; H2 abierto | Observe, `jido_otel`, OTel de ReqLLM | Jido tiene integración; falta comparar jerarquía/privacidad/coste de extremo a extremo. |
| MCP | Cliente stdio propio integrado con Tool | Ruta de ecosistema en transición: ExMCP/Jido Connect | No contar `jido_mcp` como dependencia vigente recomendada. |
| Infraestructura mínima | Sin SQL/Phoenix/OTel obligatorios; Ecto sí es dependencia | Core sin DB obligatoria, pero Phoenix.PubSub es dependencia no opcional | PubSub no obliga a una aplicación web Phoenix. |
| Elixir mínimo declarado | `~> 1.17` | Jido 2.3.1 y AI 2.3.0: `~> 1.18` | Una adopción completa cambia el mínimo. |
| Licencia | MIT | Apache-2.0 en paquetes examinados | Ambos permiten uso comercial sin comprar licencia de estos paquetes. |

Fuentes: [Jido][jido], [Jido AI][ai], [runtime standalone][react],
[ReqLLM][reqllm], [almacenamiento][storage], [contexto][context].

## 5. Diferencias de contrato decisivas

### 5.1. Cuota por ventana no es admisión atómica por árbol

En Jido AI, `Plugins.Quota.handle_signal/2` consulta `Store.status/3` antes de
aceptar señales de consulta. `ai.usage` llama después a `Store.add_usage/3`.
El incremento ETS es atómico, pero la consulta no reserva capacidad.

La caracterización ejecutada muestra que, con límite de una request, dos
consultas previas al registro de uso observan ambas capacidad disponible.
Tras registrar ambas operaciones, el contador indica dos requests y exceso de
cuota. El control positivo confirma que 20 incrementos concurrentes se contabilizan
correctamente. **El problema comparativo no es pérdida de incrementos.**

ExAgent comprueba/admite requests y batches contra todos los ancestros mediante
un owner compartido y reconcilia uso por identidad. Tokens/coste pueden sobrepasar
un umbral por operaciones en vuelo; tampoco es un presupuesto monetario exacto.

Implicación: para un SaaS con reservas de saldo, límites entre agentes y facturación,
el plugin Jido no reemplaza automáticamente esa lógica. Un ledger transaccional
de aplicación sigue siendo necesario para facturación real con cualquiera.

Código: [plugin de cuota][quota-plugin], [store de cuota][quota-store],
`lib/exagent/execution_scope.ex`, `lib/exagent/coordination.ex`.

### 5.2. Reintentar un error y repetir un efecto no son lo mismo

El Config ReAct fija `tool_max_retries: 1` por defecto. El runner reejecuta una
tool si `Error.retryable?/1` lo autoriza; la normalización contempla timeouts como
retryable. Los tests leídos distinguen errores retryable/no retryable.

ExAgent exige retry correctivo explícito y conserva outcomes de efectos inciertos.
Para tools con escrituras, una configuración inicial comparable en Jido tendría
que revisar `tool_max_retries: 0`, los retries HTTP y los de la propia acción.
Esto puede ser una adaptación pequeña; no justifica por sí solo otro framework.
No se reprodujeron aquí efectos duplicados ni se afirma que todo timeout se reintente.

Código: [Config][config-source], [Runner][runner-source], [Error][error-source].

### 5.3. Persistencia y continuación tienen garantías diferentes

ExAgent con Store confirma la operación después de guardar; si save falla,
preserva resultado/revisión, bloquea nuevas mutaciones y permite reintentar sólo
el guardado. Eso está implementado en `RuntimeCheckpoint` y `Session`.

Jido separa journal y checkpoint; hibernate guarda primero las entradas y después
el checkpoint. InstanceManager añade persistencia al hibernar por inactividad.
También hay garantías write-through específicas, por ejemplo para cron dinámico.
No se debe extrapolar ese caso a un ACK durable de cada respuesta ReAct.

El runner ReAct declara que no persiste por sí mismo fuera de los tokens que
posee el caller. `continue/3` puede restaurar tools pendientes, lo que ofrece
una capacidad que ExAgent no tiene. La aplicación debe almacenar el token,
coordinar quién lo consume y manejar fallos entre efecto y checkpoint.

`cancel/3` emite **un token nuevo** marcado cancelado: el código inspeccionado no
mantiene un registro global de revocación del anterior ni de consumo único.
Por tanto, no equivale a cancelar cualquier copia o cualquier ejecución activa.
La restauración de una request con stream interrumpido, por su parte, se documenta
como fallo `:stream_interrupted`, no reanudación del stream anterior.

No hay evidencia aquí para afirmar que ninguna de las dos opciones proporciona
exactly-once externo o aprobación humana persistida completa.

Fuentes: [Storage][storage], [Persist][persist-source], [lifecycle][lifecycle],
[Token][token-source], `lib/exagent/runtime_checkpoint.ex`.

### 5.4. La política de efectos de Jido tiene una frontera concreta

Jido intersecta políticas de agente/estrategia para restringir StateOps y
Directives retornados. Sus actions también pueden hacer HTTP, SQL o archivos
directamente. Filtrar un efecto retornado no deshace ese IO previo.

Hay selección de tools y un preflight de guardrail antes del batch en el runner;
sería incorrecto decir que Jido carece de autorización. Lo no demostrado es una
equivalencia con `allow/ask/deny` y toda la cadena de ancestros de ExAgent.
Ninguno convierte código de tools confiable en un sandbox.

### 5.5. El contrato de stream necesita prueba de compatibilidad

En el tag AI examinado, `Runner.build_stream/4` llama a `start_task` antes de
construir `Stream.resource`; merece verificar cuándo comienza el IO respecto
a la enumeración. Su guía de requests también explicita que los sinks pid no
ofrecen backpressure. ExAgent promete construcción lazy y ownership acotado.

Es una observación de código para el spike, no un benchmark ni una reproducción
runtime de fuga. Hay tests upstream de halt/cancel y respuestas incompletas:
su existencia merece reconocimiento, aunque no se hayan ejecutado en esta auditoría.

## 6. Aplicación a nuestros casos de uso

### Dragonex: DM, bots y humanos en tiempo real

**Viable con Jido.** Un coordinador conserva mundo y turnos; DM/bots usan AI agents;
humanos envían señales desde LiveView. Pods pueden gestionar el equipo y sus
identidades durables. Las tools piden mutaciones al coordinador single-writer.

Trabajo de aplicación: iniciativa/roster, reglas de aceptación, acciones humanas,
eventos de UI y persistencia de transiciones antes del ACK cuando sea requisito.
ExAgent ya aporta parte de esa coordinación mediante Session/TurnPolicy.

La complejidad real del juego permanece en la aplicación en ambos casos. La
decisión depende de si Jido elimina más infraestructura que la coordinación y
migración que obliga a escribir. No hay un impedimento arquitectónico evidente.

### WhoamAI: llamada acotada y salida estructurada

El inventario histórico guardado describe `run` síncrono, output Ecto, una request,
sin retries de output y adapter propio con admisión/liquidación de coste antes de
validar. Es contexto fechado; no se volvió a inspeccionar esa aplicación.

**Viable con ReqLLM, posiblemente sin el runtime Jido.** La app puede pedir salida
estructurada, validar con su changeset y conservar su servicio de reserva/coste.
Jido AI añade valor si evoluciona hacia un loop agentic, pero su plugin de cuotas
no sustituye las reservas de saldo descritas.

Este caso es una razón fuerte para evaluar una base menor que un framework completo,
no una prueba de que WhoamAI deba migrar inmediatamente.

### Soporte multi-agente

**Buen encaje en Jido.** Routing por signals, especialistas como hijos/agents,
plugins y estado por usuario/equipo son capacidades alineadas con ese escenario.
Escalado humano, permisos y transiciones durables siguen siendo requisitos de app.
ExAgent tiene ventaja si se necesitan exactamente su Session y scope compartido.

### Investigación y edición colaborativa

**Buen encaje estructural en Jido** para pipelines/equipos, acciones, FSM y
estrategias de exploración. Tener ToT/GoT/otras estrategias no demuestra mejor
calidad de respuestas ni menor coste: eso necesita evaluaciones del caso concreto.

### Chat sencillo o extracción

Ambos son suficientes. Si no hacen falta delegación, estado o control de tools,
ReqLLM directo puede bastar. Éste no es un caso diferenciador fuerte para ExAgent.

## 7. Madurez y coste de mantenimiento

- Jido tiene más superficie reutilizable: runtime, actions, signals, providers,
  plugins y extensiones. También introduce más conceptos y paquetes que cualificar.
- La consulta GitHub del 2026-09-21 muestra actividad reciente y contribuciones
  externas, pero concentración del core en Mike Hostetler; AI tiene además una
  contribución sustancial de Pascal Charbon. No equivale a garantía empresarial.
- `jido_ecto` 1.0.0 está publicado, pero su documentación versionada dice
  **alpha-quality** y desaconseja producción. También conserva una instrucción de
  instalación anterior a la publicación. Versiones y badges no bastan para madurez.
- Hex marca las versiones de `jido_mcp`, incluida 2.0.0, como deprecadas y remite
  a ExMCP/Jido Connect. La API Hex `packages/jido_connect` devolvió 404 en esta
  consulta: no se contabiliza como sustituto publicado y aceptado sin investigar
  su distribución y API concretas.
- Jido sí tiene OTel. No obstante, cambiar framework no prueba que desaparezcan
  problemas de exporter/SDK ni acepta automáticamente Opik/Langfuse.
- ExAgent dispone de evidencia local detallada, pero H2–H6 siguen abiertos.
  Su suite offline no demuestra mayor fiabilidad en proveedores reales que Jido.
- Mantener adapters propios exige perseguir cambios de proveedor; mantener un
  wrapper sobre Jido exige seguir también sus modelos de estado, eventos y errores.
  Un wrapper sólo ahorra trabajo si permite retirar responsabilidades de verdad.

Fuentes: [Jido Ecto][ecto], [Jido OTel][otel], [estado MCP en Hex][mcp].

## 8. Opciones estratégicas

| Opción | Qué ganamos | Qué seguimos pagando | Dictamen |
|---|---|---|---|
| ExAgent independiente y expansión general | Control completo | Providers, runtime, storage, tracing, MCP, documentación y aceptación propios | No recomendable como competencia generalista sin consumidores que lo justifiquen. |
| ExAgent enfocado + ReqLLM | API/contratos propios y mayor amplitud de proveedores | Adaptación de mensajes, errores, uso, streaming y lifecycle | Mejor hipótesis de evolución incremental; requiere demostrar ahorro. |
| Migrar aplicaciones a Jido/ReqLLM | Reutilización amplia y menos infraestructura propia | Migración + coordinación/policies de aplicación que falten | Preferible si la prueba muestra una capa pequeña y sin pérdida de requisitos reales. |
| ExAgent como fachada completa de Jido AI | Posible continuidad de nombres | Dos semánticas de runtime, eventos, snapshots y errores | No adoptar por defecto; riesgo alto de mantener ambos frameworks bajo una fachada. |
| Usar sólo componentes Jido acotados | Aprovechamiento selectivo | Traducción en cada frontera incorporada | Válido por necesidad concreta, no para sumar dependencias preventivamente. |

No se recomienda una reescritura por comparación de README ni continuar por coste
hundido. El criterio económico es **coste futuro del gap + mantenimiento + migración**,
frente al coste de seguir poseyendo y cualificando ExAgent.

## 9. Prueba de decisión propuesta

Unidad separada y acotada, antes de nueva expansión del framework. Dos consumidores
sintéticos independientes, sin empezar migrando las aplicaciones existentes:

1. **Perfil WhoamAI:** una petición, JSON validado por Ecto, reserva/liquidación,
   output inválido y uso ausente. Comparar ExAgent, ReqLLM directo y, sólo donde
   aporte valor, Jido AI.
2. **Perfil Dragonex/soporte:** coordinador, humano, dos agentes, streaming,
   tools que mutan un diario de efectos, cambio de turno y checkpoint/restore.

Casos discriminantes, primero con modelo/transporte sintético:

| Prueba | Qué debe observarse |
|---|---|
| Dos hijos compiten por una única request disponible | Admisión acorde con el requisito, uso compartido sin doble cómputo. |
| Padre deniega tool que el hijo intenta habilitar | Cero efectos; política efectiva verificable. |
| Tool produce efecto y luego devuelve error/timeout | Número de efectos conocido; ningún retry implícito indeseado. |
| Tool termina pero falla el save | ACK correcto; recuperar sin repetir la tool. |
| Consumidor no enumera, consume lento o hace halt | Momento de inicio, buffers y cleanup observados. |
| Caída/restauración con pending tools | Sin confundir snapshot/continuación con deduplicación externa. |
| Output inválido y uso incompleto | Validación final, coste desconocido y liquidación coherentes. |
| Traza con delegado, tools y error de checkpoint | Jerarquía y uso recuperables; contenido según política. |

Medir código propio de integración y de dominio por separado, necesidad de APIs
privadas/fork, recursos poseídos, claridad de errores y deuda de migración. No
usar sólo líneas de código ni número de tests como puntuación de calidad.

**Regla de decisión:**

- Si Jido/ReqLLM cumple los requisitos necesarios con configuración y una capa
  pequeña sobre APIs públicas, favorecer su adopción y una retirada planificada
  de ExAgent, respetando consumidores y SemVer.
- Si requiere reconstruir scope, autoridad, ACK durable y runtime parcial,
  conservar ExAgent enfocado; evaluar qué responsabilidad de providers puede
  delegarse a ReqLLM sin duplicar permanentemente dos backends.
- Si un requisito sólo existe por una abstracción de ExAgent y no aporta valor a
  las aplicaciones, reconsiderarlo antes de exigirlo al competidor.

Después bastaría una matriz real pequeña y autorizada de modelos y SQL para las
opciones finalistas. El spike no necesita convertirse en otra auditoría exhaustiva
de dependencias. Esta propuesta no cambia por sí sola los hitos H1–H6.

## 10. Evidencia ejecutada y límites de verificación

Caracterización aislada del `Jido.AI.Quota.Store` real del tag AI 2.3.0:

- Dos checks de cuota previos a registrar uso no reservan una request: confirmado.
- Veinte incrementos concurrentes se acumulan en 20 requests/40 tokens: confirmado.
- Resultado: **2 tests correctos**, seed 0, Elixir 1.20.0/OTP29, sin Mix, mocks,
  instalaciones de dependencias, red de proveedores ni escritura en bases de datos.

Artefacto temporal: `/tmp/opencode/exagent-jido-quota-characterization.exs`.
Fuente cargada desde `/tmp/opencode/exagent-jido-audit-ai-2.3.0`.
La prueba es sobre el contador, no una ejecución integrada de AgentServer/ReAct.
Una primera ejecución emitió un warning de locale por el entorno vacío; la
repetición con `LC_ALL=C.UTF-8` conserva el resultado sin ese warning.

```bash
env -i LC_ALL=C.UTF-8 \
  PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin \
  EXAGENT_OFFLINE=1 MIX_ENV=test \
  elixir /tmp/opencode/exagent-jido-quota-characterization.exs
```

Para reproducir sin el artefacto temporal: cargar `lib/jido_ai/quota/store.ex`
del commit fijado; hacer `reset(scope)`, dos `status(scope, %{max_requests: 1,
max_total_tokens: 10}, 60_000)`, dos `add_usage(scope, 6, 60_000)` y otro status.
Los primeros estados tienen cero requests y `over_budget?: false`; el último,
dos requests, doce tokens y `over_budget?: true`. Como control, otro scope recibe
20 llamadas concurrentes `add_usage(scope, 2, 60_000)` y acaba con 20/40.

Documentación local: 156 enlaces relativos en 28 Markdown correctos,
`mix format --check-formatted mix.exs`, ExDoc con `--warnings-as-errors` y
`git diff --check` correctos. ExDoc generado en
`/tmp/opencode/exagent-jido-audit-docs`, con el informe registrado en sus extras.
No hay nueva aceptación runtime de ExAgent, Jido completo,
ReqLLM, SQL ni OTel. No se atribuyen mejoras de rendimiento o calidad LLM.

## Fuentes primarias

Las referencias de código fijan commit; las de HexDocs fijan versión. Las APIs de
paquete y datos GitHub son observaciones a la fecha de la auditoría.

[jido]: https://hexdocs.pm/jido/2.3.1/readme.html
[ai]: https://hexdocs.pm/jido_ai/2.3.0/readme.html
[react]: https://hexdocs.pm/jido_ai/2.3.0/standalone_react_runtime.html
[reqllm]: https://github.com/agentjido/req_llm/blob/v1.14.0/README.md
[storage]: https://hexdocs.pm/jido/2.3.1/storage.html
[context]: https://hexdocs.pm/jido_ai/2.3.0/thread_context_and_message_projection.html
[lifecycle]: https://hexdocs.pm/jido_ai/2.3.0/request_lifecycle_and_concurrency.html
[quota-plugin]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/plugins/quota.ex#L135-L172
[quota-store]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/quota/store.ex#L15-L108
[config-source]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/config.ex#L117-L122
[runner-source]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/runner.ex
[error-source]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/error.ex#L176-L183
[persist-source]: https://github.com/agentjido/jido/blob/b1b5a5b8542a7a4d6ea10e9c6c39d5b6b285f606/lib/jido/persist.ex
[token-source]: https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/token.ex#L50-L87
[ecto]: https://hexdocs.pm/jido_ecto/1.0.0/readme.html
[otel]: https://hexdocs.pm/jido_otel/1.0.0/readme.html
[mcp]: https://hex.pm/api/packages/jido_mcp

- [Metadata Jido 2.3.1](https://hex.pm/api/packages/jido/releases/2.3.1).
- [Metadata Jido AI 2.3.0](https://hex.pm/api/packages/jido_ai/releases/2.3.0).
- [Metadata ReqLLM 1.14.0](https://hex.pm/api/packages/req_llm/releases/1.14.0).
- [Contribuidores Jido](https://github.com/agentjido/jido/graphs/contributors).
- [Contribuidores Jido AI](https://github.com/agentjido/jido_ai/graphs/contributors).
- ExAgent: [arquitectura](../architecture/overview.md), [diseño](../architecture/design.md),
  [alcance](release-scope.md), [estado aceptado](../status.md).
- Inventario histórico de consumidores: `docs/archive/2026-09-consolidation/night-handoff.md`,
  sección 7; utilizado como contexto, no como nueva aceptación de las aplicaciones.
