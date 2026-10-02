# Dirección del paquete: ExAgent sobre ReqLLM

**Dirección actualizada el2026-09-22; investigación inicial del2026-09-21.**
ExAgent conserva runtime propio sobre una release oficial **stock** de ReqLLM,
sin fork/vendor/patch/monkeypatch/parser wire privado ni runtime Jido. La decisión
aprobada y su migración están en [diseño8.22](../architecture/design.md).

**Plan detallado posterior, mismo día:** [R0–R9](roadmap.md) concreta esta dirección.
El usuario confirmó incluir C7 en v2; su aplazamiento anterior queda sustituido.
El [alcance](release-scope.md) y la [aceptación](production-acceptance.md) prevalecen
para prioridades y compromiso de release.

**Ejecución posterior R1:** dependencia ReqLLM1.24.0 verificada, adapter Model
buffered con aceptación textual parcial tras review. Tools stock y continuación
Anthropic/Google están bloqueadas por pérdida de datos; faltan límite público
predecode y presencia fiel de uso. Los guards siguen siendo el estado runtime.
El alcance objetivo ahora admite métricas orientativas y límites operativos:
**R1.2 comienza por el gate del sobre obligatorio**, todavía hipótesis sin probar.
No exigir un fork para conservar garantías sustituidas ni levantar guards por prosa.
El mínimo efectivo es1.18 por
`llm_db` obligatorio (diseño8.15). Los hallazgos de investigación de abajo
conservan su fecha y no sustituyen el estado/evidencia del roadmap.

## 1. Decisión vigente

**Continuar ExAgent como biblioteca propia de agentes, con ReqLLM como integración
principal de modelos, sin depender del runtime de Jido.** Reutilizar componentes
especializados y patrones demostrados; mantener pequeño el código cuyo
comportamiento debemos controlar y verificar nosotros.

El criterio cambia respecto a la [comparación inicial](jido-comparison.md):

- El usuario busca su base habitual para aplicaciones Elixir a largo plazo,
  no diferenciar un producto comercial frente a Jido.
- Las aplicaciones actuales son pruebas de concepto, no restricciones de diseño
  ni razones para mantener helpers de transporte que ya no aporten valor general.
- Se acepta invertir cómputo/tokens para obtener una buena base y delegar el
  criterio técnico. Eso no hace rentable cualquier abstracción o auditoría.
- Interesan capacidad de extensión, consistencia y coste futuro de cambio; no
  poseer cada línea de HTTP, schemas, colas o exportación de trazas.

La recomendación tiene confianza razonable como dirección arquitectónica; **no
demuestra que ExAgent sea más fiable, barato o completo que todos los competidores**.
Adoptar Jido también es viable. Si la prioridad fuese minimizar mantenimiento de
biblioteca propia, elegir un framework existente sería la preferencia inicial.
Aquí el control de la API y su evolución tienen valor explícito para el usuario.

## 2. Sí existen alternativas en Elixir

No hay que justificar ExAgent suponiendo que el ecosistema está vacío. Se
examinaron versiones publicadas a la fecha, documentación y fronteras relevantes:

| Opción | Valor principal | Encaje con este objetivo |
|---|---|---|
| **Jido 2.3.1 + Jido AI 2.3.0** | Runtime OTP, signals/actions, equipos, persistencia y loop AI | La alternativa examinada más fuerte para adoptar una plataforma amplia. También adopta su modelo de coordinación/estado y su ciclo de evolución. |
| **LangChain Elixir 0.14.1** | LLMChain, tools, contexto, callbacks, modelos, evaluación de trayectorias y OTel | Candidato válido para aplicaciones LLM. No promete paridad con LangChain Python/TS ni es automáticamente LangGraph. La operación durable más amplia necesita composición adicional. |
| **Nous 0.17.1** | Ergonomía tipo PydanticAI, Ecto, tools, hooks, equipos, workflows, memoria y evals | Competidor cercano a la visión de ExAgent. Su amplitud merece consideración, pero no se verificaron todas sus garantías. Hay diferencias reales entre superficies: `run_stream` no ejecuta tools; `run(stream: true)` sí. |
| **Ash AI 1.1.0** | Acciones Ash como tools, autorización del dominio, prompt actions, MCP y loop | Excelente si la aplicación ya se modela con Ash. Adoptar Ash como requisito de toda app sólo por agentes añade un compromiso mayor del necesario aquí. |
| **ReqLLM 1.24.0 directo** | Interacción con modelos, schemas, streaming y proveedores | Suficiente para muchas llamadas simples. Es también una base reutilizable debajo de ExAgent; no aporta por sí solo el runtime de agentes. |

La revisión de Jido fue más profunda en la unidad anterior; las otras alternativas
tienen revisión de encaje y documentación, con comprobación puntual de código de
Nous. No son cinco certificaciones de producción ni una búsqueda exhaustiva de Hex.

Dos precedentes reducen el riesgo arquitectónico de la elección:

1. LangChain publica `ChatReqLLM`, conservando el loop y la ejecución de tools en
   LangChain mientras delega modelos en ReqLLM.
2. Ash AI 1.1.0 utiliza ReqLLM en sus operaciones LLM y documenta la migración desde
   LangChain. Adoptar ReqLLM no implica adoptar Jido.

## 3. Por qué elegir esta combinación

**Control útil:** poseer la semántica de run, tools, permisos, uso, eventos y
recuperación permite una interfaz propia coherente entre aplicaciones.

**Reutilización útil:** providers, autenticación, codecs y protocolos cambian con
frecuencia. Delegarlos a una biblioteca especializada evita mantener en paralelo
un catálogo y un cliente por servicio.

**Coste del acoplamiento:** una dependencia acotada bajo Model tiene menos puntos
de contacto con las apps que un runtime completo cuyos eventos, datos persistidos
y coordinación atraviesan la arquitectura. La diferencia es de superficie, no
«dependencias buenas» frente a «dependencias malas».

**Límite de la independencia:** código propio también tiene bugs y migraciones;
una dependencia open source puede extenderse, fijarse a una versión o sustituirse.
No hay evidencia de que Jido vaya a romper nuestros usos. Tampoco hay garantía de
que una API propia nunca necesite una major. La mejor protección es un límite
pequeño, contratos observables y actualizaciones verificables.

**Economía real:** los tokens abaratan producir código, no eliminan el coste de
entenderlo, integrarlo, probar fallos y mantenerlo. ExAgent merece inversión si
reduce el código y las decisiones repetidas en futuras apps. No la merece si
se convierte en un proyecto indefinido de perfección antes de poder usarlo.

No se exige reproducir cada detalle accidental de ExAgent en otra biblioteca ni
conservarlo en la siguiente major. Antes de proteger un contrato se debe explicar
qué necesidad general satisface. Los contratos publicados conservan SemVer.

## 4. Arquitectura objetivo

```text
Aplicación Elixir / Phoenix / worker
                │
     API pública pequeña de ExAgent
                │
       Ejecución y tools tipadas
       permisos · uso · eventos
                │
          ExAgent.Model
           ├─ adapter ReqLLM ── proveedores estándar y custom
           ├─ modelo Test
           └─ implementación propia cuando el protocolo lo justifique

Capas opt-in sobre la misma ejecución:
  conversación / coordinación / Store / observabilidad / integraciones
```

### Lo que debe poseer ExAgent

- Un único loop para sync y stream, resultado validado o fallo con progreso.
- Tools, validación local, inyección de dependencias y autoridad efectiva.
- Admisión atómica y contadores host exactos; reconciliación sin doble conteo,
  métricas de proveedor con calidad/procedencia y coste estimado explícitos.
- Eventos de ejecución y ownership de tareas/cancelación.
- Contexto/historial, conversación y coordinación opcionales.
- Contrato de persistencia y recuperación, con límites expresados sin confundir
  estado guardado con deduplicación de IO.
- Una experiencia sencilla de instalación, diagnóstico y testing para el consumidor.

### Lo que conviene delegar

- Providers/protocolos al adapter ReqLLM y sus extensiones públicas.
- JSON Schema a su validador; Ecto continúa como autoridad de output donde se usa.
- Base de datos, PubSub, jobs y backend de trazas a componentes especializados.
- Integraciones de dominio y herramientas concretas a la aplicación o a extensiones.

Un único paquete de entrada puede dar una experiencia coherente sin implementar
internamente cada subsistema. RAG, voz, imágenes, sandbox, cron y workflows
durables no tienen por qué incorporarse todos al núcleo para que éste sea útil.

## 5. Integración ReqLLM: diseño y trabajo necesario

Referencia: **ReqLLM 1.24.0**, commit
`fd9e079fddf253e9b719b2d2c6920f4306592809`, instalada en el checkout. El análisis
inicial citaba1.14.0 como referencia del rango, **no como lock de Jido AI**:
el tag2.3.0 fija1.17.1 y main inspeccionado1.22.0 (fuentes en§9).
Una actualización exige release oficial y nueva cualificación de fronteras.

ReqLLM documenta una interacción por invocación; el host posee orquestación,
aprobación, tools, persistencia y decisiones de continuar. Ese límite encaja con
`ExAgent.Model` sin insertar otro loop de agentes dentro del nuestro.

| Frontera | Decisión objetivo / comprobación necesaria |
|---|---|
| Resolución | Un adapter común para proveedores ReqLLM; specs explícitas para modelos ajenos al catálogo. Mantener identidad real de provider/gateway y configuración por instancia. |
| Buffered | `generate_text/3` retorna una respuesta que se traduce al contrato Model; el core conserva la decisión de continuar. |
| Streaming | Lazy host, una vista, terminal válido antes de efectos y cleanup incluso ante owner kill. Preferir evaluar process_stream con callbacks/Response final; límites propios postdecode medidos, no hard RAM predecode upstream. |
| Tools | Primero gate del sobre obligatorio `{arguments: objeto}` con callback noop; validar sobre/schema lógico y efectivos tras hooks antes de autoridad/efecto. Preservar IDs/outcomes, sin prometer raw perdido. |
| Output | Mantener validación Ecto y retries contabilizados. El modo tool actual se migra primero; output nativo se negocia explícitamente cuando se implemente, no se infiere de flags existentes. |
| Uso/coste | Separar requests/intentos/tools exactos del host de tokens/cache normalizados/reportados y coste estimado con calidad/procedencia. Cero normalizado no es observado; conservar availability/snapshots, unidades y no doble conteo. Ordinary execution con límites host no se bloquea sólo por accounting ausente; strict dependiente de datos ausentes rechaza explícitamente. |
| Opciones | Separar ajustes comunes de opciones documentadas del provider/transporte. No traducir ciegamente el actual `extra` de wire JSON a otro nombre con semántica diferente. |
| Errores/retries | Normalizar causa sin filtrar secretos; explicitar retries de transporte, salida y tools, contabilizando intentos. No activar fallbacks que repitan efectos inadvertidamente. |
| Historial/metadatos | Conservar firmas de thinking, IDs y metadatos de continuación necesarios sin persistir objetos vivos/credenciales. Rechazar modalidades no representables en lugar de descartarlas. |
| Capacidades | No convertir cobertura del catálogo en soporte universal de tools/stream/output. Las capacidades nativas y las tools locales tienen distinta autoridad. |
| Observabilidad | Elegir quién produce el span de generación y correlacionar request IDs; evitar duplicar spans/uso por instrumentar ExAgent y ReqLLM a la vez. |
| Server/Session/Store | Ejercitar las mismas ejecuciones mediante runtime, delegación, compaction, checkpoint y restore; no basta una llamada textual aislada. |

### Hallazgos concretos que impiden tratarlo como cambio mecánico

1. **Disponibilidad del uso.** `lib/req_llm/usage/normalize.ex` en el tag convierte
   dimensiones ausentes a cero. Es un comportamiento distinto del contrato actual
   de ExAgent. Un adapter no puede reconstruir presencia a partir del número
   normalizado. La decisión8.22 acepta números normalizados etiquetados y
   estimaciones, no presencia observada ni factura. No requiere extensión/fork;
   no usar heurística cero=unknown ni degradar silenciosamente límites strict.
2. **Memoria de stream.** `StreamServer` ofrece high-watermark de chunks y explica
   que un evento de transporte puede superarlo. Una cota de chunks no equivale a
   límite de bytes de frame/respuesta. Deben caracterizarse los límites públicos
   realmente disponibles y decidir los que asumirá ExAgent.
3. **Consumo único.** `events/1`, `tokens/1` y `to_response/1` consumen la misma
   fuente: no se puede enumerar y después volver a materializar. `process_stream/2`
   da callbacks y respuesta final, pero acumula chunks. Elegir la ruta según
   fidelidad, memoria y cleanup comprobados, no por el snippet más corto.
4. **Contenido y continuación.** El contrato actual de respuesta ExAgent sólo
   representa texto, thinking y ToolCall; ciertos providers incorporan otros
   contenidos/metadatos. Revisar ahora las extensiones necesarias para el alcance
   aceptado, sin publicar una API de «todos los medios» incompleta.
5. **Dependencias reales.** ReqLLM declara Elixir `~> 1.15`; eso no certifica nuestro
   grafo resuelto ni la matriz 1.17/27. Su lock de referencia incluye JSV0.22.0,
   pero se debe resolver y probar el consumidor, no copiar el lock upstream.

Estas observaciones iniciales tienen reproducciones locales posteriores registradas
en roadmap; §9 añade lectura versionada, sin nuevos tests runtime ni auditoría global.

### Proveedores adicionales

Para un endpoint compatible, preferir configuración explícita de modelo/base URL
y credenciales. Para un protocolo distinto, implementar un `ReqLLM.Provider`
externo y registrarlo mediante `:custom_providers` o la API pública; después
proponerlo upstream si tiene valor general. No hace falta esperar una release para
usarlo localmente. Conservar Model como salida para integraciones que realmente
no encajen. No añadir una segunda pila por cada diferencia de autenticación.

### Retirada de código propio

Objetivo final: **un backend principal**, no elegir indefinidamente entre «legacy»
y «ReqLLM». Tras aceptar paridad relevante, retirar de la nueva major los adapters
y el transporte duplicados. Los constructores baratos pueden delegar al adapter
común cuando aporten ergonomía; los helpers de wire publicados necesitan migración
explícita, no compatibilidad permanente dictada por las pruebas de concepto.

## 6. Qué aprender de Jido y otras bibliotecas

| Patrón | Aplicación sensata en ExAgent | Momento |
|---|---|---|
| Estado/transiciones explícitos y efectos poseídos por runtime | Reforzar separación decisión/ejecución en los puntos que dificulten pruebas o recuperación | Durante consolidación donde exista un problema concreto; no reescribir todo como `cmd/2`. |
| Identidad y lifecycle de equipos | Mantener distintos run, conversación, participante y equipo; ownership explícito | Revisar contratos ahora; añadir gestión de equipos cuando exista uso general. |
| Historia canónica y proyección al modelo | Preservar distinción ya existente y datos de continuación | Integración ReqLLM y aceptación de compaction. |
| Plugins con ámbito y ciclo de vida claros | Evaluar límites de Capability antes de añadir un segundo sistema de plugins | Extensión por necesidad demostrada. |
| Tokens/estados de pausa y continuación | Diseñar estados pendientes persistibles y efectos/idempotencia explícitos | R4/R5; C7 incluido por confirmación posterior del usuario, aún sin implementar. |
| Composición de workflows | Secuencia, routing y fan-out/fan-in sobre el mismo run; separar esto de turnos Session | Después de aceptar el núcleo; una Session no debe fingir ser un graph engine universal. |
| Trayectorias y escenarios de evaluación | Inspeccionar tools, outputs, coste y fallos por APIs públicas; aprovechar fixtures existentes | Antes de publicar; sumar pruebas discriminantes, no otra plataforma de evals. |
| API declarativa fácil de adoptar | Ejemplos mínimos y mensajes de error claros; complejidad opt-in | R2/R8/R9, no pulido sólo al final. |

Se reutilizan ideas, no se importa por anticipado Pods, un bus nuevo, ocho estrategias
de razonamiento o un DSL general. La ventaja tiene que aparecer en código eliminado,
contratos más claros o capacidades usadas, no sólo en una lista más larga.

## 7. Orden de inversión y criterios para dejar de gastar

El seguimiento operativo se mantiene en [roadmap](roadmap.md), R0–R9;
no se abre otro tablero paralelo. El siguiente orden motivó el plan; éste fija
el alcance final, incluida C7 y composición acotada antes de la release.

1. **Integración ReqLLM completa y acotada.** Resolver las fronteras de §5 y migrar
   el conjunto relevante. Cerrar con escenarios integrados y reducción real de
   responsabilidad propia; no con añadir una dependencia que apenas se utiliza.
2. **Aceptación útil de la base.** Proveedores reales representativos, Store y
   observabilidad; consumidores genéricos para one-shot, agente con tools/stream,
   conversación y delegación. Registrar límites de operación.
3. **Estabilización pública.** Revisar juntos mensajes, errores, eventos, output,
   permisos y snapshots; documentar estable/experimental y migración de la major.
4. **Extensiones con casos concretos.** El plan posterior sitúa continuación/aprobación
   persistida y composición acotada en R4–R6 de v2. Incorporar memoria/retrieval
   mediante recetas de integración, con ownership claro y sin motor propio general.

Para cada unidad: problema, resultado observable, verificación y criterio de
cierre. Una unidad terminada se usa; sólo se reabre con cambios o defectos nuevos.
No presupuestar un número de tokens como garantía de calidad ni prometer «perfecto».
La cobertura amplia se consigue componiendo piezas estables, no anticipando todos
los problemas futuros en una primera versión.

**Cuándo parar una opción de integración:** si exige parsers privados,
cualquier fork/patch o dos runtimes permanentes; si las apps sólo usan llamadas simples;
o si mantener ExAgent ocupa más esfuerzo que las capacidades compartidas que
ahorra. Entonces reducirlo más o adoptar otro framework sería una decisión técnica,
no una derrota. No hace falta repetir esta comparación en cada nueva feature.

## 8. Evidencia y fuentes

Registro de la investigación inicial del2026-09-21: versiones, documentación y
lectura de código, sin proveedores, suites de alternativas ni benchmark. Entonces
ReqLLM no estaba añadida; posteriormente R1.1 sí la integró. Las comprobaciones
documentales siguientes pertenecen a aquella unidad, no a la decisión8.22.

Verificación documental de la unidad:171enlaces locales/29Markdown,
`mix format --check-formatted mix.exs`, ExDoc con `--warnings-as-errors` y
`git diff --check` correctos. No se repite la suite runtime por cambios de prosa.

- [ReqLLM 1.24.0 en Hex](https://hex.pm/api/packages/req_llm/releases/1.24.0).
- [Frontera host ReqLLM](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/guides/host-integration.md).
- [Compatibilidad ReqLLM](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/COMPATIBILITY.md).
- [Providers externos](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/guides/adding_a_provider.md).
- [Normalización de uso](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/usage/normalize.ex#L14-L65).
- [StreamResponse](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/stream_response.ex).
- [Backpressure documentado](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/stream_server.ex#L55-L65).
- [LangChain 0.14.1](https://hexdocs.pm/langchain/0.14.1/readme.html) y [ChatReqLLM](https://hexdocs.pm/langchain/0.14.1/LangChain.ChatModels.ChatReqLLM.html).
- [Ash AI 1.1.0](https://hexdocs.pm/ash_ai/1.1.0/readme.html).
- [Nous 0.17.1](https://hexdocs.pm/nous/0.17.1/readme.html), [workflows](https://hexdocs.pm/nous/0.17.1/workflows.html) y [permisos](https://hexdocs.pm/nous/0.17.1/permissions.html).
- [Nous run_stream](https://github.com/nyo16/nous/blob/81d4dd34b60856c931bd80fef299ad1195681c04/lib/nous/agent_runner.ex#L349-L418).
- [Auditoría Jido previa](jido-comparison.md), [contratos ExAgent](../architecture/design.md) y [alcance](release-scope.md).

## 9. Investigación Jido-ReqLLM del 2026-09-22

Síntesis durable de la investigación readonly y del contraste del coordinador;
no una nueva ejecución de Jido/ReqLLM ni aceptación del sobre. Context7 remitía a
main y se contrastó con tags, blobs y metadata GitHub/Hex. Los tests citados se
leyeron, no se ejecutaron;691/0/28 sigue siendo baseline previo de ExAgent.

### Versiones fijadas y procedencia

| Componente | Corte observado | Alcance |
|---|---|---|
| Jido AI release | v2.3.0, `2f83b922edcca3deb9e92b6391d198a0c14f5da3`, 2026-08-05 | Declara `req_llm ~>1.14`; lock1.17.1, no1.14.0 ni1.24.0. Lock upstream no fija resolución de consumidor Hex. |
| Jido AI main | `05ac705133612e0635fd378d0f814adaedbff5e6`, 2026-09-21, 21 commits posterior | Lock1.22.0; añade interceptores/transformación de definiciones, sin cambio en Turn/ToolAdapter/Usage del diff inspeccionado. No otra release2.3.0. |
| ReqLLM release | v1.24.0, `fd9e079fddf253e9b719b2d2c6920f4306592809`, 2026-09-17 | Última release observada, dependencia stock del checkout. |
| ReqLLM main | `00fc11f271b0a1b43cfcb5063737fbed7bb5511b`, 2026-09-21, 16 commits posterior | Inspección selectiva de continuación/cache/streaming, no dependencia adoptada ni prueba de resolver todos los gaps. |

Fuentes de versiones: [Hex AI2.3.0](https://hex.pm/api/packages/jido_ai/releases/2.3.0),
[mix tag](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/mix.exs#L60-L72),
[lock tag](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/mix.lock#L47),
[lock main](https://github.com/agentjido/jido_ai/blob/05ac705133612e0635fd378d0f814adaedbff5e6/mix.lock#L47),
[release ReqLLM](https://github.com/agentjido/req_llm/releases/tag/v1.24.0),
[diff Jido](https://github.com/agentjido/jido_ai/compare/2f83b922edcca3deb9e92b6391d198a0c14f5da3...05ac705133612e0635fd378d0f814adaedbff5e6),
[diff ReqLLM](https://github.com/agentjido/req_llm/compare/fd9e079fddf253e9b719b2d2c6920f4306592809...00fc11f271b0a1b43cfcb5063737fbed7bb5511b).

### Qué hace Jido y qué no resuelve

- **Host y tools:** [runner](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/runner.ex#L443-L538)
  llama generate/stream y ejecuta actions fuera de ReqLLM;
  [ToolAdapter](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/tool_adapter.ex#L108-L146)
  aporta schema/strict opcional/callback noop. Esto inspira la frontera pequeña,
  no prueba la validación posterior del host.
- **Argumentos:** [Turn1168–1190](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/turn.ex#L1168-L1190)
  convierte strings inválidos/no-objeto y otros tipos a `%{}`. Jido comparte e
  introduce el gap; no hay mitigación secreta para tools que admiten vacío.
  ReqLLM [decoder](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/provider/defaults.ex#L1661-L1690)
  y [builder](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/provider/defaults/response_builder.ex#L298-L332)
  pierden invalidity. No se reprodujo aquí un efecto live Jido.
- **Validación:** ReqLLM [Schema.compile(map)](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/schema.ex#L118-L123)
  devuelve compiled:nil y [Tool.validate_input](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/tool.ex#L290-L335)
  no valida ese schema mapa. No confundirlo con el API separado Schema.validate;
  mantener JSV/Ecto locales. [Proyección OpenAI/Google](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/schema.ex#L608-L676)
  muestra que el payload efectivo cambia por provider: strict no es universal.
- **Continuación:** [Turn](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/turn.ex#L563-L646)
  reduce calls a id/name/arguments; [runner](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/runner.ex#L267-L314)
  proyecta a AI.Context, no conserva todo ReqLLM.Context. El
  [test con stubs](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/test/jido_ai/react/runtime_runner_test.exs#L1627-L1692)
  de reasoning_details no prueba firmas recibidas de backend ni ausencia de pérdidas.
- **Stream:** [Jido arranca Task antes de Stream.resource](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/runner.ex#L71-L103).
  [ReqLLM process_stream422–452](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/stream_response.ex#L422-L452)
  usa Enum.map de chunks; [watermark](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/stream_server.ex#L53-L65)
  no limita bytes predecode. [Terminal Jido](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/runner.ex#L1664-L1684)
  acepta needs_tools antes de revisar razón de fin: no copiar esa política permisiva.
- **Uso y cuota:** [Usage](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/usage.ex#L76-L160)
  normaliza y suma; [normalización ReqLLM](https://github.com/agentjido/req_llm/blob/fd9e079fddf253e9b719b2d2c6920f4306592809/lib/req_llm/usage/normalize.ex#L14-L65)
  borra presencia. [Quota](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/plugins/quota.ex#L135-L172)
  separa check/increment; no reserva atómica por árbol, ledger ni factura.
- **Pausa/output:** [Token](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/reasoning/react/token.ex#L25-L87)
  firmado con TTL/fingerprint no equivale a claim consumido/revocación global.
  [Output](https://github.com/agentjido/jido_ai/blob/2f83b922edcca3deb9e92b6391d198a0c14f5da3/lib/jido_ai/output.ex#L82-L147)
  permite reparación de JSON; no autoriza reparar argumentos para efectos.

### Aplicación decidida y límites de evidencia

Primero probar sobre obligatorio y schema lógico, vacío válido incluido; no afirmar
que evita normalizaciones arbitrarias ni recupera raw, claves duplicadas o metadata.
Los gates args/schema/strict/history/output/autoridad/terminal/live se concretan en
[aceptación](production-acceptance.md). Sin prueba del sobre no se retiran guards.
Un subset de schema no representable rechaza antes de IO: no rewriter general.

Seguir futura release oficial del commit Anthropic
[`3536ff94ce050cea15aaf285ad2c6bfeac6809bc`](https://github.com/agentjido/req_llm/commit/3536ff94ce050cea15aaf285ad2c6bfeac6809bc)
(2026-09-19, PR1034): añade
[provider_block](https://github.com/agentjido/req_llm/blob/3536ff94ce050cea15aaf285ad2c6bfeac6809bc/lib/req_llm/message/content_part.ex#L60-L81)
y [redacted decoder](https://github.com/agentjido/req_llm/blob/3536ff94ce050cea15aaf285ad2c6bfeac6809bc/lib/req_llm/providers/anthropic/response.ex#L223-L263).
**No está publicado en1.24.0 ni adoptado**; claims live del commit son de upstream.
El replay opaco es provider-bound: no aceptar drop al cambiar proveedor. Ni este
diff ni reasoning.enabled:false prueban ausencia de bloques/signatures perdidos,
sparse usage o cota predecode. Los perfiles afectados permanecen excluidos.

Conservar runtime/Model pequeños, contadores host, autoridad, C7 y cleanup;
replantear sólo métricas orientativas, límites operativos y soporte por perfil.
R1.8 retira duplicación tras aceptación del mínimo y migración major; catálogo
no obliga a aceptar todas las familias. Esta síntesis reemplaza la prueba estratégica
pendiente de la comparación histórica: no reauditar Jido ni R0 completo.
