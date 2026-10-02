# Mandato preparado: implementación iterativa de ExAgent v2.0.0

**Método vigente2026-10-01:** `docs/development/execution-flow.md`; estado/entrada en
`docs/prompts/continue-native.md`. Como máximo una revisión por objetivo funcional,
sin re-review ni reruns rutinarios del padre. Los relevos/gates iniciales fechados
inferiores no reinician las fases ya aceptadas.

**Estado: preparado, no activo por su mera lectura.** Se activa cuando el usuario
encarga ejecutar este documento. La sesión que lo redacta sólo planifica. Si se
recibe como contexto de una sub-tarea, se ejecuta únicamente esa sub-tarea.

## Objetivo

Implementa iterativamente el [roadmap](../development/roadmap.md) R0–R9 hasta una
candidata ExAgent2.0.0 aceptada para los perfiles de
[alcance](../development/release-scope.md), o hasta un bloqueo real sin trabajo
independiente viable. Habla en español y entrega evidencia, no sólo otro plan.

Dirección fijada por diseño8.22: ExAgent propio, ReqLLM **release oficial stock**
sin fork/vendor/patch/monkeypatch/parser wire privado, ningún runtime
Jido requerido. **C7 está incluido expresamente**: aprobación humana persistida
y continuación acotada tras reinicio. Las apps actuales son pruebas de concepto;
no condicionan la API ni son objetivos de modificación.

## 1. Recuperar antes de actuar

Leer en orden, evitando releer documentos completos en cada iteración:

1. `AGENTS.md`, entrada nativa/CURRENT, índice y cabeceras vigentes de status/changelog.
2. Tablero del roadmap; release-scope/production-acceptance pertinentes al objetivo.
   No reiniciar R1.2 ni fases aceptadas desde un relevo antiguo.
3. Diseño2.1–2.3 y sólo las decisiones, migración y contratos del objetivo escogido.
4. `docs/development/environment.md` y `docs/development/verification.md`.
5. Fuentes/tests de la unidad escogida; investigación Jido sólo para un patrón
   concreto, no para reabrir la decisión estratégica.

Comprobar Git/HEAD/diff/untracked, versión, lock, runtime efectivo, herramientas
y trabajos concurrentes. La base histórica es7f25b33/nominal1.3.0 con WIP documental;
el checkout al activar puede ser diferente. Preservar todo trabajo previo.
Los655/28 y691/0/28 de septiembre son históricos; no atribuirlos a contratos nuevos o C7.

## 2. Autoridad y límites operativos

Al activarse, este mandato permite implementar biblioteca/tests/docs de las
unidades del alcance y usar tooling temporal aislado. Elegir detalles técnicos
justificados sin pedir aprobación para cada función, test o refactor pequeño.

- No modificar aplicaciones consumidoras, infraestructura compartida o configuración
  global ni reiniciar servicios. Leer la guía del incidente Hex antes de instalar herramientas.
- Commit/push/PR/bump/tag/publicación requieren autorización expresa. Preparar
  código y un preview local no significa que esas operaciones estén autorizadas.
- Llamadas pagadas, DB/servicios reales y backend necesitan destino, scope y
  presupuesto autorizados. No interpretar la presencia de una key como permiso.
- No volcar secretos ni archivos de credenciales. Usar datos sintéticos en aceptación.
- No reducir features/garantías obligatorias por dificultad ni prometer soporte
  universal; elevar un cambio de alcance con evidencia y consecuencias.

Un único agente puede ejecutar el plan. Preferencia expresa: **Astra con contexto
fresco por defecto**; GLM5.3/Grok4.6 para trabajo sencillo delimitado cuando se
autorice delegación, reusar contexto sólo con ventaja clara. Asignar ownership no
solapado y un owner de mix/lock/build; revisar entregas. Un coordinador Orca sigue
su skill/autoridad vigente; un worker despachado no delega ni amplía su Task.

La revisión fresca exigida por el roadmap puede realizarla otro agente/revisor
autorizado o una sesión posterior con contexto limpio. Si falta, registrar el
gate pendiente; no llamar «independiente» a la propia revisión.

## 3. Bucle de trabajo obligatorio

Para cada iteración:

1. **Selecciona** la primera subunidad no aceptada cuyas dependencias estén listas.
   Verifica que no esté siendo editada por otro owner y márcala en curso.
2. **Define salida:** problema, contratos, archivos, oráculo y gate requerido.
   Si ya existe implementación válida, verifica su aceptación y reúsala.
3. **Investiga lo justo:** docs/versiones actuales de la dependencia y código de la
   frontera. Los patrones históricos no tienen precedencia sobre APIs publicadas.
4. **Decide y documenta:** ADR breve para cambios de contrato, migración y resultado
   observable. No publiques firmas nuevas basándote sólo en pseudocódigo del plan.
5. **Implementa** con `apply_patch`, respetando estilo y evitando capas duplicadas.
6. **Verifica** focales y controles discriminantes. Reproduce fallos antes de proponer
   fixes; separa bug propio, fixture defectuosa, dependencia y entorno.
7. **Integra:** compila/formatea y ejecuta el gate apropiado de la guía. Para runtime
   usa `EXAGENT_OFFLINE=1 MIX_ENV=test mix test`, con prefijo aislado si corresponde.
   No cerrar una unidad por ejecución sobre BEAM antiguos o con tests que no corrieron.
8. **Revisa** el delta y resuelve hallazgos; solicita la revisión fresca en puntos
   exigidos. Repite sólo gates afectados por cambios posteriores.
9. **Registra** resultado, comandos/exits/semilla, revisión/lock, artefactos, límites
   y siguiente acción en roadmap. Actualiza docs públicas/estado cuando corresponda.
10. **Continúa** con otra unidad ejecutable. No termines tras un hello-world si quedan
    rutas del mismo contrato sin integrar o fases independientes pendientes.

Si no se puede terminar una subunidad en el contexto disponible, dejar un checkpoint
de trabajo preciso; no marcarla verificada ni prometer que seguirá ejecutándose
después del turno. Reanudar desde evidencia real, no desde la intención del relevo.

## 4. Precauciones de diseño que deben guiar la implementación

- **ReqLLM:** una request/stream por operación; ExAgent posee loop/tools. Primero
  gate del sobre obligatorio semántico y schema lógico/efectivos tras hooks antes
  de levantar guards; no raw perdido prometido, reparación de inválidos/truncados,
  fallback wire ni historia inválida envuelta a válida. Schema/refs/strict no
  representable rechaza preIO, sin rewriter general preventivo.
- **Uso/stream:** contadores host exactos frente a métricas normalizadas/estimadas
  con calidad/procedencia; no cero observado inventado ni heurística cero→unknown.
  Ordinary execution con límites host continúa sin accounting; strict dependiente
  de datos ausentes rechaza explícitamente. Una vista, lazy, terminal válido,
  cleanup y límites propios postdecode medidos; no hard RAM predecode upstream.
- **Perfiles:** mínimo Chat-compatible sin reasoning/provider-native por cualificar;
  otras familias por combinación probada, sin pérdida ni fallback silencioso.
- **Extensiones:** usar APIs públicas, provider custom registrable y behaviours
  pequeños. Un gap externo se reproduce en nuestra frontera; no rehacer upstream.
- **Persistencia:** CAS/claim reales o rechazo de capability; nunca load+save como
  falsa exclusión mutua. Sólo datos rehidratables desde código confiable.
- **C7:** pausa durable antes del efecto, decisión sobre argumentos exactos, revalidación
  de autoridad y resume de pasos confirmados sin replay. Un efecto incierto se expone;
  ni un lease expirado ni un retry de job prueban que no ocurrió.
- **Composición:** mismo scope/límites/errores; resultados parciales conservados.
  No sumar uso dos veces ni mantener tareas huérfanas tras fallo/pausa.
- **Observabilidad:** una generación contabilizada una vez, contenido off y redacción
  antes de exportar; SDK/exporter y backend propiedad de la app.
- **Simplicidad:** retirar responsabilidad propia sustituida. No añadir estrategias,
  dependencias ni motores generales sólo para competir en número de features.

## 5. Bloqueos y uso eficiente de recursos

Registrar exactamente: ID bloqueado, causa, evidencia, dato/permiso/API que falta y
unidad independiente elegida. Agrupar las necesidades externas en una sola solicitud
precisa; no volver a preguntar hechos ya confirmados, como la existencia de Opik.

No llamar repetidamente a servicios inaccesibles ni repetir dos veces un intento
idéntico sin nueva hipótesis/evidencia. Un mínimo upstream insuficiente se resuelve
con configuración/API pública de release oficial cualificada o escalado/perfil
cerrado; ningún fork/vendor/patch/monkeypatch/parser privado ReqLLM.

La suite offline protege nuestra integración; no certifica G2–G4. Reservar matrices,
soak y revisión transversal para los cambios/gates que los justifican. Mantener logs
largos como artefactos, y en el relevo sólo decisiones, resultados y siguiente comando.

## 6. Entrega de cada sesión

Actualizar `handoff.md` con:

```text
HEAD/WIP y lock efectivo:
Subunidades verificadas y evidencia:
Subunidad en curso, último cambio y prueba pendiente:
Contratos/decisiones nuevas y rutas:
Bloqueos externos y autorización disponible (sin secretos):
Recursos propios activos o cleanup realizado:
Siguiente ID, archivos y comando de verificación:
Estado real: implementación | aceptación parcial | lista para release | publicada:
```

R9 activa la revisión final del delta; no reabre el mandato de auditoría inicial.
Al cerrar gates técnicos sin autorización de release, entregar **lista para
versionar/publicar** con sus pruebas. Tras autorización, cambiar a2.0.0 y verificar
el artefacto final/publicado; no atribuir a éste las pruebas de otro TAR.

**Primera acción al retomar:** preflight breve del checkout y gate **R1.2 del sobre**
según `docs/prompts/continue-v2-reqllm.md`. R0/R1.1 ya tienen evidencia: no repetirlos
completos ni reauditar Jido. Al pasar, continuar R1 restante y R2–R9 por dependencias;
si falla, conservar guards y registrar bloqueo preciso sin fork. La mera lectura
de este mandato como contexto no activa una implementación.
