# ExAgent v2 — relevo tras pausa expresa del 2026-09-27

## Activación y pausa

El usuario ordenó dejar finalizar lo que estaba en marcha y **no iniciar nada más**
antes de resetear contexto. Este archivo conserva el estado; **leerlo no levanta la
pausa**. Reanudar sólo si el nuevo mensaje del usuario lo activa expresamente.
El smoke online final anunciado, pero aún no iniciado, se canceló en esta sesión.

La implementación v2 y las autorizaciones de pruebas/publicación siguen concedidas
para una reanudación, condicionadas a sus gates. El proyecto NO está terminado ni
publicado. No interpretar «complete» en nombres de artefactos como cierre R0–R9.

## Recuperación de Orca

- Repositorio: `/home/kukapu/dev/projects/exAgent`.
- **MISMO Run:** `run_37f56dd0d992`; no crear otro por pérdida de contexto.
- Runtime: `2759e8ef-16ca-4be7-a2b3-be0d711a1e29`.
- Último coordinador: `term_f5881fea-4d1f-47be-b87f-3aeb206faa0a`, generación3.
- Workspace: `83438294-6397-425c-a0b2-8def0a505dda::/home/kukapu/dev/projects/exAgent`.
- Consultar Run/flota/mailbox y cabecera de `ORCA_CHECKPOINT.md` antes de actuar;
  el checkpoint contiene la confirmación final de cierre y cesión del último owner.
- Todos los intentos nuevos deben usar Tasks/workers **Orca**, contexto fresco y
  `openai/gpt-6-astra` **LOW efectivo verificado**. Seleccionar el modelo no fija
  necesariamente la variante. Un único owner por área/fuentes/builds.
- La excepción manual `xai/grok-4.7 xhigh` correspondió exclusivamente al reviewer
  C7 `task_0ee986f3992e / ctx_7c85ffbff803`, ya completado. No extenderla ni reutilizar
  su Dispatch/capability. Los recursos `user_takeover` pueden seguir visibles idle;
  eso no significa que tengan trabajo pendiente. No forzar cierre.

Último owner: `task_730426cd2919 / ctx_0c683a93c818`, terminal
`term_3b4a3583-327a-414c-9dd7-3bd2a09f27f9`. Entregó la finalización, informó cero
procesos/builds propios activos y confirmó worker_done/cesión en `msg_05932ac806eb`,
recibido/ACK. Consulta final completa:62Dispatches, **ninguno abierto**. Su recurso
quedó retained/user_takeover al intentar release, sin cierre forzado. Confirmar
estado actual en Orca tras reset; no retomar un Dispatch completado.

## Fuente y paquete finales de esta unidad

Artefactos inmutables, cotejados por el coordinador (tres SHA y fuente324/324):

| Artefacto | Ruta | SHA256 |
|---|---|---|
| Fuente324 | `/tmp/opencode/exagent-complete-source.tar.gz` | `ef308d7ee531cfa0b0039c6cdcf282a4e72e06e7a4c29657adb6fa3620f23db2` |
| Manifest | `/tmp/opencode/exagent-complete-manifest.json` | `c9a5d9bbee446765f582934132e35acc6ad1224c92bf2d7f020b8254d0314a34` |
| TAR115 | `/tmp/opencode/exagent-complete-package.tar` | `2fbf1311aa9409d6aa4d969f12287cd337e5bb27f5a414862e8a6f7124b34e06` |

Runtime/tests/config/mix son iguales al freeze terminal revisado `dda4e60a…`;
posteriormente se consolidaron ocho documentos y siete archivos de tooling.
Owner: compile93, **suite offline947/0/28**, warnings-as-errors, snippets9,
formato/ExDoc/links/plan verdes; última distribución con consumidores fresh de
grafo fijo mínimo6/adapter63/extensible32/SQL15 y117 módulos por perfil, exit0.
No llamar esos consumidores una nueva resolución limpia ni SQL real.

Versión nominal **1.3.0**, ReqLLM oficial **1.24.0**, lock
`c20a0cb90fb5f379d900a080290bdb6dc16c412a76234b5427753d05b39ac48b` conservado.
HEAD histórico `7f25b336924d97baf1d4aa18898ec8db32385940`; WIP extenso preservado.
No commits, push, bump ni publicación en esta sesión. No importar una baseline
antigua, resetear/stashear/limpiar ni sobrescribir el WIP.

Checkpoint y este nuevo relevo son documentación de coordinación posterior al
freeze; no están incorporados retroactivamente al TAR.

## Qué quedó implementado/revisado

1. **C7:** árbol delegado, aprobación/continuación, Server/Session, recuperación
   de Model y retry explícito. Review original cerrada favorable offline; fix SQL
   separado incorporado ahora al paquete final.
2. **SQL:** DELETE confirma sólo la fila efectivamente devuelta; falso ACK bajo
   RLS/trigger reproducido y corregido con los mismos probes sobre Postgres17.11.
3. **Admisión ReqLLM:** los flags históricos de fragmentos no son un veto absoluto.
   Se valida la respuesta final, sobre y schema; cualquier error explícito no-nil
   bajo ambas formas de clave rechaza, incluidos args_lost/fallback válidos.
   No se borran flags ni se parchea ReqLLM.
4. **Modo `reasoning_mode: :none`:** opción explícita para targets con soporte
   declarado, capacidades veraces, sin temperature y con límite host mapeado a
   `max_completion_tokens` público. No razonamiento requerido ocultado para pasar.
5. **Binding persistido:** callback opcional `Model.continuation_binding/1`, JSON
   acotado4KiB, comparación template antes de codec y modelo cargado después;
   Continuation3/Frame3/Abort2 y lectores legacy sólo donde corresponden. Sin motor
   duplicado ni acoplamiento del Frame a ReqLLM. Snapshot4/Scope2/envelope1 conservados.
6. **Terminal fallido:** prioridad de finish público real antes de convertir tools;
   partial legacy sólo si la traducción completa pasa, sino nil. Ningún marcador,
   codec o campo de uso nuevo por este ajuste. No convierte invalidargs en length.
7. **Gate online portable:** `test/support/openrouter_qualification/` y receta en
   `docs/development/verification.md`. Opt-in `--live`, clave privada, directorio y
   ledger nuevos por ola, modelo/perfil explícitos, presupuesto y concurrencia1,
   cero retries. Sin opt-in no lee claves ni hace IO de modelo. No se ejecuta
   automáticamente dentro de la suite offline.

Reviews leídas/aceptadas en sus alcances:

- C7: `/tmp/opencode/exagent-r5-review/final8b3b/REVIEW.md`.
- Admisión: `/tmp/opencode/exagent-final-admission-review/REVIEW.md`.
- None/binding: `/tmp/opencode/exagent-none-binding-review/REVIEW.md`.
- Terminal y herramienta integrada: `/tmp/opencode/exagent-terminal-review/REVIEW.md`,
  SHA `172e303e222cd424d5795050582c966405183ce77c945ad41d0e3021525d2ccf`.

## Corrección importante de diagnóstico

No volver a afirmar «ReqLLM tiene un bug100% confirmado y sólo sirve un fork».
La investigación mostró flags de parseo de fragmentos conservados tras una
reconstrucción válida, APIs stock que aceptan y tests oficiales de esa reconstrucción.
El veto absoluto era nuestra política de admisión, no una exigencia pública demostrada.
La semántica final de esos flags está subespecificada; args_lost es una frontera
distinta y sí impide admitir el fallback. Se adaptó ExAgent, no la dependencia.
Detalle: `docs/archive/2026-09-27-reqllm-contract-clarification.md`.

## Integraciones reales: qué se probó y qué no

| Modelo/perfil OpenRouter | Resultado conservado |
|---|---|
| `openai/gpt-4o-mini`, Chat/tools/native/stream |14/14 sobre2a74; dos controles posteriores sobreb609 también verdes |
| `openai/gpt-6-luna`, None explícito |13/14 sobreb609: texto/tools/Ecto/native/empty y length sync pasan; length_stream NO cualificado |
| `z-ai/glm-5.3-flash`, providerOpenRouter/razonamiento veraz |Un control real de texto buffered pasa; no tools/native/stream cualificados |
| `deepseek/deepseek-v4.1-flash`, mismo alcance de texto |Un control real de texto buffered pasa; no tools/native/stream cualificados |

Luna length_stream rechazó con invalid_tool_arguments y cero efectos. Una llamada
diagnóstica posterior devolvió ToolCalls+args_lost, NO Length, y no prueba el terminal
original. No se capturó su on_chunk finish. El ajuste posterior de prioridad se
justificó por un caso TCP distinto; no se ha relabelado el rojo live ni hecho retry
hasta verde. El nuevo TAR final NO recibió el smoke live cancelado por la pausa.

Total de la ola nueva:40 admisiones/7 efectos de contadores inocuos/2.37USD de
reserva operativa, bajo5USD/80. Reserva/estimación NO son factura observada.
Evidencia y snapshots por perfil: `/tmp/opencode/exagent-g2-admission-requalification/`.
REPORT final SHA `5b542ee12400c892e87d2a30d0d10f7790ea89b1b635b343e4aef8e6cc82e166`.

G3: perfil Postgres17.11 READ COMMITTED aceptado en escenarios21+VM/reinicioPG/
ACK/red/backup declarados, sin HA/exactly-once/cualquier despliegue. Infra de pruebas
eliminada,5560 liberado, evidencia `/tmp/opencode/exagent-g3-postgres/` conservada.
G4: ambas APIs Langfuse/Opik funcionan,74spans/15trazas sintéticas por backend;
Langfuse referencia provisional por identidad/tipos. **UI y transporte nativo directo
cloud siguen pendientes**, así como gaps de paused/attempt y exporter de R7.
G5: resolución limpia local pasada sobre el paquete histórico identificado; propuesta
de CI privada de cuatro archivos no integrada/ejecutada sobre esta candidata final.

## Autorizaciones vigentes para después de una reactivación

- G2/G3 pruebas reales ampliamente autorizadas; online OpenRouter habitual por
  cambio relevante, modelos baratos indicados y presupuesto operativo explícito.
  Mantener también controles deterministas; no bucles pagados sin finalidad.
- G4 incluye Langfuse y Opik, proyectos `exagent`, workspace/org `akorda`.
- G5 resolución limpia/descargas y CI/Git necesarios autorizados. No modificar
  configuración global ni servicios ajenos por una incidencia compartida.
- R9.4 versionado/publicación autorizados **tras los gates**, no ahora por tener permiso.
- Credenciales están en `.env` local ignorado,0600: OPENROUTER_API_KEY,
  LANGFUSE_BASE_URL/PUBLIC_KEY/SECRET_KEY y OPIK_URL_OVERRIDE/WORKSPACE/PROJECT_NAME/API_KEY.
  Comprobar presencia y usar programáticamente; no Read/cat/envdump/CLIvalores/chat.
  No hacen falta nuevas claves para los resultados pendientes de esta sesión.

## Pendiente al reanudar expresamente

1. Contrastar checkpoint/flota/mailbox y fuente ef308/manifest c9a5/TAR2fbf. No
   reiniciar R0–R4 ni reabrir Tasks completadas. Nueva Task fresca si hay nuevo trabajo.
2. Si corresponde, ejecutar un smoke online mínimo con el runner integrado sobre
   estos bytes, con nueva ola y ledger. No ejecutado en el cierre por orden del usuario.
3. Continuar R6 composición, R7 observabilidad/MCP/recetas y R8–R9 según sus gates.
   Actualizar tabla única de roadmap; no concluir v2 por los paquetes locales.
4. Mantener Luna length_stream como no demostrado hasta evidencia nueva legítima;
   no atribuir a upstream ni maquillar el oráculo. No es permiso para patch/fork.
5. G4 UI/end-to-end, CI remota exacta, matriz/operación restantes y release final
   siguen abiertos. No instalar/implementar/trabajar durante la pausa actual.
