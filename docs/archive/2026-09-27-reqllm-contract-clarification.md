# ReqLLM: aclaración contractual tras G2 — 2026-09-27

## Conclusión que sustituye la atribución anterior

G2 sigue rojo con el adaptador actual. Sin embargo, **no está demostrado que el
caso que lo bloquea sea una violación del contrato de ReqLLM que sólo pueda
resolverse parcheando upstream**. La evidencia demuestra una incompatibilidad
entre nuestra política de admisión y diagnósticos de fragmentos conservados por
ReqLLM. Puede existir una inconsistencia de metadata upstream; su intención final
no está documentada con suficiente precisión en las versiones examinadas.

La anterior expresión «defecto confirmado de ReqLLM; sólo sirve una corrección
oficial» era demasiado fuerte. Los resultados y rojos anteriores siguen siendo
reales; se corrige su interpretación causal, no se los convierte en pases.
Esta investigación no autoriza quitar guards, adaptar el producto, cambiar
dependencias, mantener un fork ni aceptar G2. El usuario decidirá después.

## Recorrido comprobado

1. Un stream Chat-compatible puede empezar con el nombre/ID de una tool y una
   cadena de argumentos vacía o un prefijo como `{`; después llegan los fragmentos
   restantes. Un fragmento incompleto no equivale a argumentos finales inválidos.
2. ReqLLM clasifica ese fragmento como no decodificable y adjunta
   `invalid_arguments` / `unparseable_arguments` y `raw_arguments`.
3. El acumulador reconstruye el JSON final correctamente pero conserva metadata
   del fragmento inicial. `process_stream/2` devuelve una respuesta `{:ok, ...}`.
4. Las APIs públicas stock `ToolCall.resolve/3` y `execute/3` se basan en los
   argumentos finales y la validación de la tool, no vetan por esas dos marcas.
5. ExAgent, en `req_llm_envelope.ex:47–61`, veta primero ambas marcas y sólo después
   validaría el sobre y los argumentos lógicos. Aquí ocurre el rechazo del caso
   original: nuestra política añade una interpretación terminal de esos campos.

No lo causa el sobre ExAgent: el mismo comportamiento aparece con un schema plano
sin cargar ExAgent. Activar `json_repair` tampoco cambia los controles de streaming
probados. Reconstrucción normal de fragmentos y reparación de JSON final son
operaciones distintas.

## Evidencia experimental y contraejemplos

34 requests TCP sintéticas, cero requests a modelos reales: 24 casos stock1.25,
cinco controles stock1.24 sin ExAgent cargado/iniciado y cinco controles de la API
Model completa del ExAgent actual. Fuentes stock/producto inalteradas.

| Caso | ReqLLM stock | ExAgent actual, API Model |
|---|---|---|
| Nombre inicial sin argumentos, después JSON válido | JSON correcto, sin flags; resolve válido | ToolCall lógico aceptado |
| Inicio vacío, después JSON válido | JSON correcto, flags iniciales; resolve/execute válido | invalid_tool_arguments |
| Inicio `{`, después resto válido | JSON correcto, flags iniciales; resolve/execute válido | invalid_tool_arguments |
| JSON completo inicial, después whitespace | Conserva JSON inicial y añade args_lost; resolve/execute válido | invalid_message_or_options |
| JSON completo inicial, después sufijo inválido | Conserva JSON inicial y añade args_lost; resolve/execute válido | invalid_message_or_options |

Stock no ejecuta callbacks automáticamente al consumir el stream; los efectos de
estos probes son contadores inocuos llamados mediante `ToolCall.execute/3`
explícito. Los probes Model de ExAgent prueban traducción, no ejecución del loop.

Un JSON stream truncado puede producir `{}` con `args_lost`. Un schema raw de
ReqLLM no tiene validador local compilado; su ejecución puede admitir ese objeto,
mientras un schema keyword que exige un campo lo rechaza. ExAgent conserva por
ello razones válidas para validar localmente el sobre/schema y rechazar pérdidas.
Además, un fallback puede conservar un objeto **no vacío** que satisface schema:
«el JSON final valida, ignora toda la metadata» tampoco es una regla demostrada.

El error tuple `{:args_lost, ...}` también puede impedir la traducción ExAgent al
normalizar metadata a JSON portable. No inferir seguridad o ejecución únicamente
desde el pequeño predicado que consulta los dos flags.

## Contrato e historia upstream

- `ToolCall.metadata/1` es público, pero no se encontró una promesa versionada de
  que las dos marcas describan obligatoriamente invalidez **final**.
- Los tests oficiales de ambos tags esperan reconstrucción válida desde un primer
  fragmento `{` con `invalid_arguments: true`. No fijan si esa marca debe borrarse
  o conservarse en la metadata final.
- `ToolCall.resolve/3` documenta y aplica decodificación final y validación de tool;
  no incorpora ese veto. Buffered también tiene una ruta explícita de restauración
  de JSON raw que elimina estas marcas para continuar el tratamiento normal.
- PR598 introduce normalización/diagnósticos y conservación del raw para reparación.
  PR718 distingue `args_lost` para consumidores downstream. Ninguna demuestra que
  todo campo con nombre «invalid» sea un error terminal irreversible.

Fuentes versionadas principales:

- [Reconstrucción desde `{`, v1.24.0](https://github.com/agentjido/req_llm/blob/v1.24.0/test/req_llm/provider/chunk_accumulator_test.exs#L213-L234).
- [Mismo control, v1.25.0](https://github.com/agentjido/req_llm/blob/v1.25.0/test/req_llm/provider/chunk_accumulator_test.exs#L267-L288).
- [ToolCall público, v1.24.0](https://github.com/agentjido/req_llm/blob/v1.24.0/lib/req_llm/tool_call.ex#L236-L362).
- [Normalización PR598](https://github.com/agentjido/req_llm/pull/598).
- [Diagnósticos de pérdida PR718](https://github.com/agentjido/req_llm/pull/718).

Pregunta upstream pendiente, no publicada: ¿las marcas son diagnósticos históricos
o deben recalcularse al completar la llamada, y qué señal pública debe distinguir
reconstrucción válida de fallback con pérdida? No asumir intención del mantenedor.

## Decisión pendiente y evidencias

Antes de elegir un fork, evaluar una admisión ExAgent compatible con el contrato
público: diferenciar diagnósticos provisionales de pérdida final, manteniendo
terminal válido, sobre obligatorio, schema/autoridad, identidad y rechazo de
args_lost. Es una propuesta a verificar, no un cambio aprobado ni implementado.

- Auditoría contractual: `/tmp/opencode/exagent-reqllm-contract-audit/CONTRACT.md`,
  SHA256 `0f1de2e1f2ac6de518322447dfcbb5b6b80a4d4a75d43bfda69d10fa26a683e4`.
- Auditoría empírica: `/tmp/opencode/exagent-reqllm-shape-audit/REPORT.md`, SHA256
  `8e942c9085b051ad923682ba8187020355d560343424c3144354e1e586506588`.
- Verificador de observaciones ejecutado por worker y coordinador, exit0:
  `python3 /tmp/opencode/exagent-reqllm-shape-audit/verify.py`.
- Tasks Orca frescas AstraLOW verificadas, read-only sobre ROOT:
  `task_1500e4c8e38b/ctx_090eea1a93b6` (contrato) y
  `task_af14b99cfe7e/ctx_150106d340a1` (pruebas). Ambas entregadas/released.

No nuevo G2 live, patch upstream, guard modificado, código de producto, dependencia
ni publicación en esta investigación. El cambio manual del reviewer C7 a Grok4.7
xhigh es una cuestión independiente; su aceptación no se deduce de estos controles.
