# Hoja de ruta vigente

Actualizada tras la auditoría de testing del 2026-09-10.
La [recapitulación](../status.md) contiene el estado aceptado; esta página contiene
las próximas unidades, no un diario de cada intento de test.

## Auditoría cerrada; continuidad del desarrollo

El usuario da por cerrada la auditoría de testing. La prioridad vuelve a los
resultados funcionales de ExAgent descritos abajo, con las regresiones pertinentes
en cada unidad. Los puntos P2 del informe orientan ese trabajo; no forman otra
oleada automática de auditoría ni deben completarse todos antes de avanzar.

Req/gproc quedan como seguimiento externo de menor prioridad: sus warnings se
registran, pero no justifican testear sus internals ni bloquean por sí solos el
desarrollo. Véase el [criterio de verificación](verification.md). Una segunda
revisión se activará cuando el alcance del paquete esté terminado y se solicite
su revisión final; la nota está en `docs/prompts/testing-review-final.md`.

## Prioridad: observabilidad utilizable y paquete coherente

| Unidad | Resultado buscado | Dependencias y cierre |
|---|---|---|
| Documentación | Índice y guías actuales bajo `docs/`, histórico fechado, enlaces/ExDoc/paquete coherentes. | **Cerrado:** suite619/28, snippets7/7, enlaces/ExDoc y paquete24/24 runtime; [evidencia de esta unidad](../status.md). |
| Calidad del testing | Proteger los contratos de ExAgent y su integración con un coste razonable. | **Auditoría cerrada:** [inventario, cambios y puntos futuros](testing-audit.md), dos reviews frescas,655/28 en1.20/29 y1.17/27 y paquete24/24runtime. Tests de cada cambio durante desarrollo; segunda revisión al terminar el paquete. |
| Tooling local | Recuperar la comodidad del entorno del host. | Reparar el Hex compartido sólo con autorización explícita; el entorno aislado permite continuar entretanto. |
| Transporte OTel | Una ruta de operación fiable, con límites de delivery/cleanup honestos. | Resolver o aceptar una alternativa comprobada a los límites HTTP de exporter1.10; no ocultarlos con otro cliente improvisado. |
| Backend de referencia | Elegir por calidad de diagnóstico, funciones y operación, partiendo de las instancias Opik confirmadas por el usuario. | Seguir [el escenario y criterios](backend-evaluation.md); falta concretar destino/acceso e histórico, no volver a preguntar si existe Opik. |
| Paquete | Consumidores simples y opt-in reproducibles, documentación vigente y manifest correcto. | TAR24/24runtime verificado; repetir grafos pertinentes ante cambios de integración y para el candidato final. Warnings Req/gproc registrados como seguimiento externo, sin prioridad automática sobre funcionalidad. Revisar bootstrap CI y conservar nominal1.3.0 hasta autorización de release. |
| Aceptación real C8 | Proveedores/modelos, Store Postgres y migración de consumidores. | Alcance y credenciales autorizados; preservar admisión, coste, retries y efectos de cada aplicación. |
| Aprobación diferida C7 | Decidir si entra una continuación persistida acotada. | Decisión de alcance independiente; no añadir API parcial ni motor de replay por completar una lista. |
| Major | Publicar una base coherente con migración y SemVer. | Contratos revisados, gates aplicables cerrados y autorización explícita de versión/publicación. |

## Decidido y ya entregado

- C1–C5 y C6 neutral consolidados offline, con OTLP loopback y límites externos
  separados. La base nocturna pasó619 tests en tres runtimes.
- Schema JSV y output Ecto, loop común, scope, checkpoint/restore y canales de
  observabilidad conservan los contratos de [diseño](../architecture/design.md).
- N01–N18 local terminó con revisiones frescas; N14 decidió no optimizar sin
  evidencia causal. No repetir ese backlog como si siguiera pendiente.
- Auditoría de testing: base70archivos/648casos revisada íntegramente; final77archivos/
  683casos, sin objetivo numérico. Cerrados gaps de oráculos/ownership y fronteras
  reproducidas de uso/schema/MCP/delegación/codec. El backlog P2 contrastado permanece
  explícito en la auditoría; no son features automáticamente autorizadas.
- Langfuse/Opik todavía no está elegido. Mayor cobertura sin licencia comercial
  se prefiere a calidad comparable; una ventaja relevante demostrada puede
  justificar funciones avanzadas comerciales. Esa preferencia no autoriza compras.

## Política de cierre

Cada unidad deja problema/evidencia, decisión, cambio, verificación y limitaciones.
Un test offline no cierra un backend real, y una bandera verde no borra warnings,
exclusiones o efectos desconocidos. Las instrucciones de Git, autorización y WIP
siguen en `AGENTS.md` y en el [relevo](handoff.md).

El detalle de fases originales, C0–C8 y N01–N18 permanece en el archivo del checkout
`docs/archive/2026-09-consolidation/`; es historial, no otra fuente de prioridades.
