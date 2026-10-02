# Pausa y diagnóstico de eficiencia

**Decisión posterior2026-10-01:** el usuario solicita aplicar la simplificación,
como máximo una revisión y avance por código funcional. Política vigente en
`docs/development/execution-flow.md`; entrada `docs/prompts/continue-native.md`.
La pausa y propuestas inferiores son históricas, no prohibición de esa continuación.

Aplicado: entrada única continue-native, política execution-flow, instrucciones
locales AGENTS/roadmap y caminos de testing/review/relevo/R9 alineados. CURRENT507→70
líneas, historial anterior preservado intacto. Verificación estática exit0: producto
345/345sin cambios,97links locales,5/5entradas antiguas redirigidas y gitdiffcheck0;
snapshot `/tmp/opencode/exagent-flow-simple-mcermh9s/`. Sin reviewer/tests nuevos
para esta documentación ni cambios globales de EL LISTO. Próximo owner sólo runtime.
Despacho realizado: worker `ses_f096d6e80ffeGp4D5XyTe19uA0`, ROOT/build/docs causales
exclusivos, padre memoria; primer checkpoint código ejecutado real. Sin researcher
ni review intermedia. Resultado todavía pendiente; no nuevo hito funcional aceptado.

Usuario solicita parar implementación por consumo percibido del40% de cuota y
casi24horas, y revisar método. Son cifras reportadas por usuario; no hay medición
independiente de cuota/tokens/tiempo facturado disponible aquí. No ejecución nueva.

## Observaciones respaldadas
- CURRENT antes pausa:495líneas/39905caracteres/71sessionIDs distintos mencionados.
- structural-delegation:799líneas/56077caracteres/27sessionIDs mencionados.
- schema-proposal:358líneas/24602caracteres.21archivos memoria enrun.
- Cifras de sesiones son referencias en documentos, NO llamadas facturadas ni agentes
  simultáneos. No permiten atribuir porcentajes de coste por fase.
- Secuencia repetida: worker parcial→cotejo/report→review→hallazgo→workerfix→review→
  rerunpadre. Repetida para pequeñas ampliaciones internas, productor10 aúnOFF.
- Revisiones sí encontraron defectos reales: historialomitted, unknownchild,
  capacidadwrapper/output/exhaustion y contadores/evidencia. No suprimir controles.
- Capacidad de cierre tuvo varias correcciones por representación materializada y
  reservas coexistentes. Se habilitaron estados gradualmente sin cerrar primero
  un modelo composicional completo, generando rework de la misma preocupación.
- Allowlist demasiado rígida generó handoffs por ScopeLedger decoder nil, RequestData
  y expectativas de tests antiguas. Varias eran dependencias previsibles o permisos
  que el padre podía acotar dentro de la unidad, no decisiones del usuario.
- Encargos monolíticos agotaron contexto; reacción posterior excesivamente fragmentada
  produjo muchos incrementos inactivos y nuevas lecturas, sin vertical live/VM.
- Memoria y mandatos largos/repetitivos elevan carga de contexto; CURRENT dejó de
  funcionar como resumen actual y pasó a ser historial. Error del coordinador.

## Propuesta, NO autorización de ejecución
1. Compactar estado actual a<=100líneas, archivar historial intacto; un mapa claro
   de componentes implementados, habilitados, verificados y pendientes.
2. Definir un próximo objetivo funcional demostrable, no otra unidad de validadores:
   delegación real→pausa→decisiones→nuevaVM→retorno sin repetición. Determinar su
   ruta crítica y fallos que deben soportarse antes de activarlo; sin guards falsos.
3. Un dueño de la vertical con permisos causales sobre código/tests/docs acotados;
   escalamiento sólo cambios reales de contrato/seguridad/alcance, no cada fichero.
4. Pruebas focales durante implementación; revisión independiente acumulada en la
   frontera funcional. Una regresión integrada al estabilizar, no grandes selecciones
   en cada microhito. Rerunpadre sólo para riesgos no cubiertos/procedencia dudosa.
5. Presupuesto de ejecución acordado y checkpoint de resultado/coste; máximo orientativo
   una implementación+una revisión, corrección acotada y pausa si reaparece mismo
   problema estructural. No ciclos ilimitados sin resultado usable.
6. Paralelizar sólo frentes verdaderamente independientes; no añadir agentes para
   aparentar velocidad. No cambiar modelos sin petición explícita.
7. Medir progreso por capacidades habilitadas y evidencia, no testcounts/documentos.

El60–65% comunicado anteriormente fue estimación subjetiva, no cálculo de entregables
ponderados. No utilizarlo como métrica de avance ni previsión de esfuerzo restante.
La conversación actual queda en pausa para decidir método; nada de esta propuesta
activa automáticamente implementación ni cambios de configuración de EL LISTO.
