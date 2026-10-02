# Contrato de contadores y control de tools

Researcher previo detectó falta retry?/fatal en Outcome. Diagnóstico real:
`/tmp/opencode/final-tools-diagnostic-f185cb0f/REPORT.md` (leer completo).
Mismos outcomes e historial con request posterior y output atestado conservan
tool_retries effect1/vacío/host-counter4 según hooks Model actuales. No derivable
sólo de statuses. Batch actual final/succeeded puede tener after-hook fatal.

Intención análisis sólo lectura sin shell/build/edits: elegir contrato coherente
para continuation estructural y base general. Preferir contadores runtime-owned
si no hay consumidor demostrado que necesite manipularlos, pero evaluar impacto
de retained_transform/Capability y compatibilidad con formatos existentes. No
imponer contador reconstruido a registros antiguos ambiguos ni duplicar modos
permanentes. Alternativa overrides explícitamente atestados y coste/beneficio.

Requeridos: punto correcto de captura/control posthook; exacta evidencia que permite
reproducir decisión no efectos, preservar retry/fatal/exhaustion/orden/concurrencia;
formato/versionado/legacy/lectura/migración y guards; Surface/API/generic benefit;
matriz causal tests/impacto y orden seguro antes de restore prefijos y batch actual.
No diseñar event sourcing/engine nuevo, no inferir JSON ejecutable/callbacks.

Otro owner corregirá exclusivamente Frame batch/usage con tests/docs y build ROOT.
NO depender de sus cambios en vivo: investigar ExAgent hooks/Capability/Outcome/
Writer y formatos tal como están, citar baseline diagnóstico para Frame. Ninguna
edición/shell/build/delegación por researcher, entregar recomendación al padre.

Researcher `ses_f184e3732ffe4kp6QVdJxp3LLS` TERMINADO sólo lectura, sin tests/edits.
Owner integridad independiente `ses_f184e84d2ffeRaq6x04GgVK59w` tiene ROOT/producto;
no solicitar builds ni editar fuentes/docs mientras trabaja.

## Dirección aceptada por el padre, aún NO implementación

Padre contrastó retained_transform ExAgent1170–1193 y Capability/Capabilities14–32,
85–96. Contadores ya declarados internos, no consumidor local demostrado que necesite
overrides; no asumir ausencia de consumidor externo. Se elige runtime-owned, no API
de override persistido. Impacto/migración major pendiente debe ser explícito.

Primera unidad futura: preservar ante CADA hook Model tool_retries,
output_retries_used, run_step, tool_calls, max_steps y agent.output_retries efectivos.
No congelar agente completo ni settings/model/selección tools/proyección permitidos.
Normalización entre capabilities para que siguiente hook tampoco observe falsos
valores, no sólo al final retained_transform. Restaurar valores runtime confirmados
siguiendo patrón existente, no error nuevo cosmético. Hooks siguen trusted, no sandbox.
Matriz causal before/after×campos, dos capabilities, límites y transforms legítimas.
Esto SOLO cierra mutación del productor, NO valida/migra registros viejos ni abre restore.

Después, resolución durable de control de batch en Writer existente, ligada a
run/request/calls ordenadas/outcomes finales exactos. Outcome1 no inventa retry/fatal.
Captura DESPUÉS de hooks/normalización exits/retención/settle y combinación errores,
ANTES de fail/pause/drive. Necesita controles retry? por call, límites efectivos y
primer fatal en orden calls, reducción puro compartido. Retry seguido success puede
dejar mapa vacío Y fatal; tareas ven mismo contador inicial, no secuencializar IO.
Mapas before/after derivados o contrastados con cadena, no autoridad arbitraria.
ACK sólo comando datos, resolución ausente bloquea, no saved(part,false,nil) legacy.
Error fatal restaurado portable/acotado, no reconstruir excepciones/módulos.

Formato nuevo estructural justificado (candidato Frame8), NO número aprobado a ciegas:
schema exacto de control y propiedad counters; readers legacy intactos, fronteras
aceptadas previas conservadas, tools legacy ambiguas no se vuelven ejecutables.
No relabel Frame7→8 ni modos públicos duplicados. Si cambia RequestData exacto,
versionarlo explícitamente. Outcome/Record pueden quedar iguales si forma no cambia.
Límites tool seleccionados por request: histórico valida con los efectivos originales,
nuevo trabajo actual∩original, sin fijar límite por nombre global accidentalmente.
Detalle final de captura/límites/proyección se contrasta antes del owner correspondiente.

Orden: aceptar fix batch/usage en curso → protección counters ante hooks → evidencia
control versionada con guards intactos → prefijos consumidos → batch atestado
continue/fatal. Raw/pending/incierto/delegación siguen separados. Cada unidad con
rojo causal/compile/focal/fullWA48/formato/review fresca, sin publicar/version bump.

## Ampliación del análisis solicitada tras bloqueo usage

Owner integridad terminó sólo batch. Leer `/tmp/opencode/final-tools-fix-f184e84d/REPORT.md`
SHA9b0f42054e054604c4c60f31b3ad5837e60035ad8c4ce853a3dacf6d44fa3806.
Premisa anterior corregida: ToolReturn.usage no se serializa ni entra hash Outcome;
falta presencia/contenido por call, agregado no basta. Ampliar propuesta control
para evidencia usage antes de habilitar prefijos; investigar captura/contribución
y normalización/final hooks/ancestors exactas, sin repricing ni métricas falsas.
No convertir esto en mero checksum de ledger contra sí mismo; independiente del
valor cuya pérdida queremos detectar. Sólo lectura, sin editar ni builds.
Continuación researcher `ses_f184e3732ffe4kp6QVdJxp3LLS` TERMINADA sólo lectura.

## Resultado usage y dirección recibida

Padre contrastó Message448–451, ExecutionScope166–173, ExAgent2188–2208 y Writer907–927.
usage no serializado, contribute retiene/aplica y puede devolver error que hoy owner
ignora; raw outcome+export scope van en mismo CAS pero sin observación independiente.
No inferir error corregido ni explotación adicional: es necesidad de diseño observada.

Se acepta dirección de UN contrato estructural nuevo con dos momentos:
1. Observación accounting por efecto capturada desde part.usage ANTES de ledger,
   ligada a run/request/call/effect-attempt. Commit junto raw+ledger antes ACK/after-hook.
2. Resolución de control postsettle ligada a observaciones/outcomes, sin duplicar
   contenido ni contabilizar otra vez. Resolución ausente sigue no ejecutable.

Formato exacto/versionado/implementación aún por concretar en unidad posterior.
No modificar Message ni Outcome1 por comodidad; contenedor estructural nuevo candidato
Frame8 puede guardar observaciones y resolución, lectores previos intactos. No
reconstruir observaciones a partir de ledger legacy ni relabelar como evidencia.

Observación distingue no recibida, ausencia explícita nil/predispatch, Usage observado
portable cualificado, evidencia omitida/incompleta. Presencia y origen host distintos
de Usage.accounting.source; no convertir normalizado/estimado en exact. Helper produce
recibo desde input+identidad al construir operación, no export ledger→autoatestación.
Validar ambas direcciones: outcome exige observación; presente exige operación exacta;
nil explícito no op externo; op requiere observación/provisión incertidumbre identificada.
Misma identidad+contenido idempotente, distinto conflicto; final/restauración no contribuye.

Uso observado y proyección por ancestro NO necesariamente iguales: external no ejecuta
estimator padre, priced_usage deja coste unknown; conservar proyección aplicada sin
repricing ni rescatar estimación tool. Complete flag actual basado en enteros no es
availability ni exactitud: preservar contrato y probar partial con enteros/nil/zero.
No alterar completitud global para resolver vínculo evidencia. Scope2 actual rechaza
usage_error: omisión requiere variante diagnóstica bloqueada y reserva mínima propia,
NO quitar marker para hacer válido ledger ni prometer restore de datos omitidos.
Detalle JSON no portable también bloquea/omite explícitamente, nunca módulos ejecutables.

Crash antes commit raw no promete salvar observación RAM; uncertainty/no replay.
Raw confirmado guarda accounting, no decisión de hooks; finales sin control bloqueados.
Cancel/fatal posterior conserva observación; ACK sólo comando existente. Nil en retorno
de hijo no significa subárbol sin gasto; no sumar delegado dos veces, delegación fuera.
Provisión usage incierto exige origen propio/intento antiguo, no fingir retorno tool.

Matriz futura: borrar/cambiar op+ancestros con observación intacta; borrar obs+op dejando
outcome; nil/unknown/zero; quality/source/availability/cost/complete/terminal; identidad
request/call/attempt, hash Message igual y usage distinto; fatal/timeout después raw;
duplicados idénticos/distintos; retención/omisión/reserva±1; CAS/decode/VM/cortes todos
momentos/control retries orden/fatal/reset. Rojos legacy NO se relabelan verdes: nuevos
productores auténticos deben cerrarlos bajo contrato nuevo, legacy tools aún bloqueadas.

Próxima implementación sigue siendo protección acotada de counters cuando libere review
batch; no despachar productor de evidencia hasta concretar schema/proyecciones/retención.

## Siguiente análisis concreto (intención)

Protección counters implementada por owner, review fresca pendiente. Concretar ahora
schema exacto/versionado/control/usage, operaciones atómicas y reservas para unidad
PRODUCTOR de evidencia nueva, manteniendo guards de restore tools intactos. No otra
propuesta genérica: claves/tipos/invariantes/seams/legacy/capacity/errores diagnósticos
y matriz con criterio de cierre para poder despachar implementación. No editar ni
compilar. Readers/formatos previos y fronteras aceptadas no se retiran ni promueven
datos sin evidencia. Definir explícitamente nuevas ejecuciones vs claims de Frame7
existente, sin promoción falsa ni modos públicos permanentes. Dirigir pendiente
omisión usage/Scope2 de manera verificable, sin legitimarlo al borrar marker.
Researcher `ses_f184e3732ffe4kp6QVdJxp3LLS` continuado background ACTIVO sólo lectura;
reviewer counters `ses_f1815c1c6ffe9qBuCLFKjrFFmg` tiene builds, sin edición producto.

### Error de contexto, reemplazo fresco

Última continuación de `ses_f184e3732ffe4kp6QVdJxp3LLS` terminó ERROR
invalid_encrypted_content, sin especificación nueva recibida. NO continuar sesión
dañada. Sus análisis previos están consolidados arriba; no repetir diagnóstico.
Intención researcher general fresco sólo lectura para concretar schema/seams/gates
del productor. Sin source edits/builds ni transferencia de ownership de reviewer.
Researcher fresco `ses_f1812b471ffelGxW9UIiIn2TdQ` background ACTIVO sólo lectura.
