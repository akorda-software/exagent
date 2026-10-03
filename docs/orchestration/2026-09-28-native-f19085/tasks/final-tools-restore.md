# Restore con tools finalizadas: análisis previo

Base: cadena output atestada N aceptada (ficha leaf-restore-next e informe review).
Siguiente frontera útil: historia con efectos tool ya finalizados y/o batch actual
con todos sus resultados final confirmados. No confundir raw con final ni repetir
hooks/permisos/callables sobre efectos ya confirmados, ni volver a sumar usage.

Intención general researcher sólo lectura sin shell/build/edits/delegación. Precisar
evidencia de cada estado y contrato de consumo; elegir unidad coherente que resuelva
restauración tras efectos confirmados sin ampliar a incertidumbre/pausa/delegación.
Explorar prefijo final y batch final actual juntos si comparten seam/contrato; separar
si hay diferencia causal. Conservar omisiones, negativas y límites. Padre decide
antes de habilitar guards. No nuevo motor/token/formato por comodidad ni replay.

Entrega: propuesta accionable con rutas/líneas, tabla fronteras/evidencia/callbacks,
gaps reales vs hipótesis, matriz finita causal/VM/CAS/ACK/crash/retención/authority/
ledger, API/errores/compatibilidad y mínimo delta. Fuentes propias, no docs externas.

General researcher `ses_f18615a66ffePadeAQMynlHFmD` terminado sólo lectura.
Padre contrastó Outcome49–67, reducción retries ExAgent2131–2164, Frame498–580 y
test continuation_runtime1250–1323: final/succeeded no demuestra continuable;
after-hook fatal puede conservar exactamente ese resultado. Raw legacy no se
traslada a composición. Batch actual permanece bloqueado.

## Decisión: diagnóstico causal antes de habilitar prefijos

Candidata de implementación: prefijo tools final ya consumido por request posterior
confirmada → output actual success/retry o texto terminal text/tool. Request posterior
atestigua decisión continuable/postbatch; batch actual NO. No implementar aún.

Gaps inferidos NO demostrados: ScopeLedger valida coherencia interna pero podría no
ligar cardinalidad histórica batch a response; tool_retries parece validado sólo en
forma; contribuciones tool con usage pueden perder consumo si se borra ledger.
Antes de abrir guard: probes auténticos decode+CAS para mutaciones coordinadas de
batch/counts, usage/contribution y tool_retries. No exigir usage cuando es nil.
Examinar si retry? de control puede inferirse de datos existentes o es ambiguo
(status por sí solo NO demuestra procedencia); no inventar reconstrucción.

Owner diagnóstico general: sólo escritura externa /tmp/opencode, producto/docs/tests
repo inmutables. Build ROOT exclusivo. Fixtures reales por Writer/ETS y resultados
raw→final/predispatch/múltiples calls mismo nombre/orden/retry reset si necesario.
Probar controles positivos registros intactos, negativos que ya rechazan, exacto
delta para aceptados inesperados, decode y transición CAS con fila observada.
Separar integridad de record vs ataque que reescribe coordinadamente TODA evidencia;
Store/CAS confiables no son firma. No afirmar exploit con guard actual intacto.
Probar también test existente final/succeeded+hook fatal para bloqueo batch actual.

Entregar informe temprano recuperable, fuentes/hashes intactos, comandos/logs/exits,
probes reejecutables y tabla demostrado/rechazado/ambiguo. Recomendar corrección
compartida mínima sólo si datos suficientes; si evidencia faltante, proponer contrato
versionado con necesidad causal, sin editar formato ni levantar guards. No FULL:
diagnóstico focal WA48 seed37556/offline/prefijo environment/build absoluto. No
serialización/relajar timeouts/configglobal/pagos/SQL/consumidores/delegar/commits.

General diagnóstico `ses_f185cb0f5ffeMaPeFsbUYaTG3Z` TERMINADO, ROOT libre.
REPORT `/tmp/opencode/final-tools-diagnostic-f185cb0f/REPORT.md` leído y cotejado:
SHAb79f96117c3bef00d5cf93f68eb16892c16fff8ab13730405bff0da2d7230f22.
baseline.json=after.json SHAd636ed53b379e3117507b70ef6201e89c4c0101b7f564306a056a13dba0ca93e;
fuentes9/9 intactas. Padre lee logs/exits:38pases diagnósticos/3excluidos (no fixes),
red-final0/3pases38excluidos exit2; focal hook fatal1pase. Sólo BEAM3ajenos.

## Hallazgos demostrados y cambio de estrategia

- Borrar/reducir batch histórico junto con counts root/leaf y scope hijo coherentes
  pasa decode y CAS step_output/outcome Model. Historial/effects/request_data intactos.
- Eliminar/cambiar contribuciones tool usage14/22→0/0 o2/2 pasa mismos caminos.
  Output_resolution rechaza por inmutabilidad específica, no sana el validador común.
- tool_retries alterado pasa; PERO registros reales con mismo historial/outcomes y
  Model2+output atestado dan effect1, vacío o host-counter4 por hooks Model reales.
  retained_transform no protege tool_retries. No deducir contador por statuses ni
  cambiar silenciosamente contrato actual. Tool after-hook no cambia libremente status.
- Ninguna explotación restore demostrada (guards intactos), ni firma ante rewrite total.

## Dos frentes independientes autorizados

1. Corrección acotada de integridad batch/usage: owner producto/build ROOT, preferente
   Frame y tests nuevos; helpers ScopeLedger/Record sólo necesidad causal. Clasificador,
   loops/retry counters y formatos intactos. Preservar raw/legacy/agentes/planes fuera
   del contrato estructural, sin excluir silenciosamente casos válidos. Gate causal
   reproducido antes fix; validación común en decode/CAS con controles reales.
   No repricing: ligar identidad/contenido de usage probado a operaciones/ancestros,
   conservar estimaciones/calidad; nil legítimo no exige contribución. Output siblings
   no admiten batches ficticios. Si falta evidencia para caso anunciado, devolver
   bloqueo antes de adivinar. Corregir dos huecos no acepta restore ni tool_retries.
2. Researcher sólo lectura sobre contrato retry/control: recomendar runtime-owned
   counters preservados ante hooks versus overrides atestados; impacto API/legacy y
   necesidad de formato explícito, punto posthook de garantía. Incluye preparación
   futura batch continuable/fatal pero NO habilitarla. No editar/compilar ni usar shell.

Owner1 escribe fuentes/tests y docs design/changelog/roadmap/r6-implementation;
padre memoria/status. Researcher2 no escribe nada. No solape builds. Artefactos
diagnóstico originales inmutables: probes generan JSON en path fijo, copiar/parametrizar
destino NUEVO antes de repetir para no invalidar manifiesto histórico.
Owner reproduce rojos sólo de batch/usage, rojo retry queda PENDIENTE conocido.
Matriz finita corrupción coordinada/control nil/multi-call/multi-request/siblings/
predispatch/usage quality/ancestors/ACK/reservas, compile/focal/FULLWA48 seed37556/
formato/diff; informe temprano/baseline/delta/hashes y review fresca. No docs/status.

Owner fix integridad `ses_f184e84d2ffeRaq6x04GgVK59w` background ACTIVO, producto/
build ROOT/docs4 exclusivos. Researcher independiente `ses_f184e3732ffe4kp6QVdJxp3LLS`
sólo lectura de contrato counters/control; no tocar sus temas ExAgent/hooks/formatos.

### Recepción parcial owner (sustituye estado activo anterior)

Owner terminado, ROOT liberado. REPORT leído/cotejado:
`/tmp/opencode/final-tools-fix-f184e84d/REPORT.md`
SHA9b0f42054e054604c4c60f31b3ad5837e60035ad8c4ce853a3dacf6d44fa3806.
source.sha25613/13 padre OK; runtime Frame+19líneas y23tests, docs4. Owner compile101/
focal357/FULL1310pases28excluidos478.5s exit0, formato/diff0. Review fresca pendiente.

CORRECCIÓN causal a premisa anterior: ToolReturn.usage no serializado ni incluido
en hashes Outcome (Message448–451/738/818, Outcome.encode). Uso histórico por call
NO recuperable inequívocamente del snapshot agregado. Helper experimental no-op
retirado por owner, ningún cambio de formato/clasificador/hooks/counters. No fix usage.
Rojo externo final1/3pasa: batch corregido, usage/retry rojos conocidos. Integridad
de contribución requiere nueva evidencia durable presencia/contenido cualificado
por run/request/call/attempt, ligada a accounting sin repricing. Researcher debe
incorporarla al contrato control, no repetir falsa inferencia de Usage serializado.
Intención review fresco sólo batch, sin FULL redundante, ROOT exclusivo/readonly.
Revisor `ses_f18362021ffeNTSXG1xs6hn3e7` TERMINADO favorable sólo batch:
141focales+4probes, padre4probes intactos WA48seed37556 exit0,2.1s;13/13hashes cotejados.
Informe `/tmp/opencode/final-tools-review-fresh-20260928/REPORT.md`
SHA54643917143e985b07d8c2ad712890c627a354b48cfb5c456646e73e81b7d301.
Padre recibe BATCH offline, docs5 posteriores; usage/retry rojos y guards intactos.
ROOT libre; siguiente productor counters en tasks/runtime-counters.md, no restore.
