# Elección y aceptación del backend de observabilidad

**Mandato vigente 2026-10-02:** el usuario exige que **Langfuse y Opik queden
igual de validados**. Esto sustituye el criterio anterior de elegir sólo un
backend de referencia. Ambos deben demostrar el mismo escenario A10 con fuente
de candidata identificada: exportación nativa real, lectura API completa y
diagnóstico en UI autenticada de árbol, reintentos, checkpoint, pausa/resume,
correlación, contadores, calidad/procedencia/unidades y privacidad. Las diferencias
de IDs, tipos y presentación se registran mediante una correspondencia comprobada;
no se rebaja un oráculo para declarar equivalencia. Langfuse conserva su aceptación;
Opik cualifica transporte nativo y API33/33,667atributos y12modelos/uso;
la UI autenticada verifica los mismos12casos/248atributos que Langfuse y siete
vistas reales inspeccionadas. G4 ampliado aceptado en el perfil A10 finito.
La navegación/captura del navegador sigue inestable; no se certifica su
disponibilidad. Recibos,
plazos y fallos preservados en el registro de aceptación del checkout
`docs/orchestration/2026-10-01-v2-codex/OPIK-ACCEPTANCE.md`.

La pasada crítica027 posterior incorpora controles causales del arnés para
descendientes, rollback de secretos privados y contenido Opik inesperado. Limitar
la privacidad observada anteriormente a campos esperados/input-output/sentinels;
la nueva frontera ante metadata/error_info extra se verifica offline, sin nueva
ola cloud ni inferir que los datos aceptados contuvieran esos extras.

La preparación Opik024 reutiliza el A10 nativo y una proyección opcional propiedad
de la aplicación: conserva cada atributo/booleano/recurso como metadato mediante
el prefijo documentado `opik.metadata`, deriva la correspondencia UUID desde la
fuente pública fijada y comprueba las dos trazas completas. Los tools con contenido
off se representan como `general`; operación y estado siguen siendo verificables
en metadatos. Receta y controles del checkout:
`test/support/langfuse_acceptance/OPIK.md`. Ni ese mapeo ni los controles offline
aceptan el build cloud o la UI antes de observarlos.

**Estado2026-10-02:** Langfuse es la referencia cualificada del perfil A10
native→Collector→cloud. La pareja flow/recovery de candidata019 tiene33/33
observaciones verificadas por API,667atributos y12modelos/uso, parentage/estados
y privacidad. Una ola de cinco POST; la lectura final sólo tres GET/734ms, sin
repetir productor/SDK/Collector. G4 UI aceptado mediante inspección autorizada
de la sesión autenticada del usuario:12observaciones/248atributos coinciden y
cinco capturas muestran estados, IDs y costes estimados. Recibo a2058c08…d8f3.
ACK, API y UI no certifican retención durable o factura. Recibos/identidad y límites en
[roadmap](roadmap.md). Sin decisión de despliegue.

**Comparación histórica2026-09-27: APIs aceptadas; Langfuse referencia provisional.**
Ambos proyectos cloud autorizados recuperan74 spans/15 trazas sintéticas. Langfuse
conserva IDs OTLP y tipos tool/agent con el perfil neutral; Opik regenera IDs y
requiere correlación adicional. En esa fecha UI y ruta nativa estaban pendientes;
la cualificación posterior se registra arriba y no altera aquellas trazas.
Recepción, identidades y límites en
`../archive/2026-09-27-external-gates-receipt.md`; estado único en roadmap§5.

**Implementación recibida2026-10-01:** la instrumentación nativa ya distingue
`paused` y publica el intento y la referencia de continuación, con pruebas
deterministas sync/stream/Server. Esa corrección posterior no actualiza las trazas
cloud de la comparación histórica. La pareja019 posterior cualifica el escenario
compuesto y los intentos de pausa/resume por API y la inspección UI posterior;
no reimplementar esos atributos
por leer el diagnóstico fechado de abajo.

Esta página desarrolla **R7.1–R7.3/A10/G4** del [plan de producción](roadmap.md). Se busca una
integración de referencia general del paquete, sin depender de la migración de
Dragonex/WhoamAI. Empezar por transporte/configuración local; el acceso al backend
es necesario para cerrar su aceptación, no para realizar esa preparación.

**Ampliación histórica autorizada 2026-09-27:** evaluar **Langfuse y Opik** como alternativas
para G4 y elegir la integración de referencia por evidencia. No se exige migrar ni
certificar ambos para cerrar el gate en aquel alcance; el mandato del2026-10-02
supersede esa exención. Se mantienen los datos sintéticos y la
preservación de cualquier histórico existente.

Se evaluaron únicamente los proyectos sintéticos autorizados exagent en Langfuse
EU y Comet Cloud/Opik. Los builds cloud no se exponen en las APIs consultadas;
ningún histórico ajeno se inspeccionó. La disponibilidad de otras instancias Opik
no implica permiso para modificarlas o leer datos reales.

## Lo decidido

- OTel nativo y configuración de SDK/exporter propiedad de la aplicación.
- Collector opcional; ExAgent no incorpora la plataforma al core.
- Contenido off, opt-in con redactor previo y límites; sin serializar modelos,
  deps, credenciales o baggage en atributos.
- Langfuse y Opik tienen aceptación A10 por transporte/API/UI con las mismas
  fronteras. La comparación API histórica permanece separada. La entrega
  documenta dos integraciones cualificadas, sus recetas
  y diferencias verificadas. No decide un despliegue ni certifica otros perfiles.
- A calidad comparable se prefiere más funcionalidad sin licencia comercial.
  Funciones administrativas comerciales sólo compensan por una ventaja demostrada;
  esa preferencia no autoriza compras ni necesita preguntarse otra vez.

## Pendientes registrados tras la comparación histórica

La lista siguiente conserva el diagnóstico del 2026-09-27. La ruta nativa,
lifecycle acotado, reintentos y atributos de pausa/resume ya tienen aceptación
posterior API/UI en el perfil A10 descrito arriba. No reactivar esas tareas desde
esta lista. Los escenarios cloud no probados conservan sus límites.

1. UI autenticada: localizar error/tool/checkpoint retry, costes cualificados y
   los dos intentos tras restart; registrar pasos y campos, no inferir UI desde API.
2. Ruta directa nativa y lifecycle: la comparación utilizó captura local y relay
   acotado, no certifica operación longeva, partial_success, saturación ni cleanup.
3. Revalidar en API/UI los atributos actuales de paused e intento, junto a la
   correlación de aprobación entre VMs. La comparación histórica observó el gap
   anterior; la corrección offline del core no certifica la presentación cloud.
4. Completar missing/normalized-zero/cache/cancel y presentación del coste estimado
   sin sumar agregados inclusivos ni confundirlo con factura. Builds cloud/planes
   efectivos siguen sin verificación; no inferir funcionalidades por ofertas públicas.

No registrar valores de credenciales aquí. Crear infraestructura, contratar
servicios o cambiar consumidores requiere alcance explícito.

## Gate previo: transporte fiable

El recibo histórico HTTP1.10.0 pierde tipos booleanos. La revisión de
[dependencias](dependencies.md) adopta la release1.11.0, que corrige esa pérdida.
El exporter HTTP sigue ignorando successful `partial_success` y conservando
recursos HTTP/perfiles/átomos en ciertos ciclos.
El processor limita sus propios recursos, pero no corrige ese lifecycle ajeno.
Resolver o verificar una alternativa de transporte/ownership antes de presentar
esa receta como operación longeva aceptada. La
[guía de observabilidad](../guides/observability.md) conserva el detalle.

## Comparación con el mismo escenario

Comparar Langfuse y Opik contra los mismos criterios y registrar la elección.
Reutilizar instancias disponibles; no hace falta desplegar dos plataformas por
rutina ni migrar datos existentes para cerrar el gate de backend.

Reutilizar `test/support/native_otlp_scenario_probe.exs` y los datos sintéticos
de las pruebas. Fijar versiones de las plataformas evaluadas y revisar sus docs/licencias
actuales antes de conectarlas; las fuentes históricas no certifican la versión futura.

| Tarea de diagnóstico | Qué comprobar en API y UI |
|---|---|
| Reconstruir un run | Un span por operación, parentesco, IDs y delegación; sin spans por token. |
| Encontrar fallo/retry | Corrección explícita, tool con efecto previo, error posterior a hook y cancelación parcial. |
| Explicar uso/coste | Requests frente a subtotales inclusivos, cache, datos desconocidos y ningún doble conteo. |
| Recuperación | Primer save fallido y retry-save sin reabrir ni repetir el run. |
| Pausa/continuación | Aprobación persistida, reinicio y nuevo intento correlacionado; sin doble coste ni spans vivos durante la espera humana. |
| Privacidad/contexto | Contenido permitido/redactado y separación de callers; sentinels privados ausentes. |
| Operación | Backend caído/lento, pérdida observable, latencia y recuperación de recursos. |
| Producto y licencia | Funciones realmente usadas, limitaciones OSS, pasos de diagnóstico y esfuerzo de operación. |

HTTP200 y un árbol visual parecido no bastan. Registrar información perdida,
aciertos, pasos/tiempo para localizar cada fallo y límites operativos. La decisión
final debe explicar por qué una opción sirve mejor a esas tareas.

Prompts, datasets, scores, evaluaciones e históricos tienen integración/migración
separada: cambiar endpoint OTLP no los traslada. Después de decidir, actualizar
[estado](../status.md), [roadmap](roadmap.md), guía y aceptación del paquete.
