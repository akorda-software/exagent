# Flujo de ejecución vigente

**Acordado con el usuario el 2026-10-01:** avanzar por capacidades funcionales,
con **como máximo una revisión independiente por objetivo**, sin re-review ni
repetición rutinaria del padre. Esta política sustituye esas cadenas en los
mandatos anteriores; no cambia contratos, alcance de v2 ni gates de producción.

## Un solo recorrido

**Objetivo funcional → implementar y probar → una revisión como máximo →
corregir hallazgos con sus regresiones → registrar resultado → siguiente objetivo.**

| Frente | Regla operativa |
|---|---|
| Retomar | Leer CURRENT vigente, tablero del roadmap y encargo actual. Abrir sólo el contrato/código necesarios; no releer todos los informes históricos. |
| Planificar | Elegir una capacidad demostrable y sus dependencias reales. Sin researcher o propuesta nueva por defecto si el contrato está decidido. |
| Implementar | Un dueño del objetivo, directamente o worker. Puede editar módulos, fixtures y documentación causalmente necesarios dentro del alcance, sin escalar cada archivo. |
| Encontrar un bug | Reproducir el fallo, corregir su causa y ejecutar la regresión afectada. No reiniciar la auditoría ni ampliar la tarea a features especulativas. |
| Probar | Focales según el delta durante desarrollo. Una suite integrada al estabilizar la vertical, no por microhito, recibo documental o cada corrección. |
| Revisar | Como máximo un reviewer sobre el delta funcional acumulado. No reviews por validador, fichero o checkpoint; documentación sin cambio semántico no necesita otra revisión. |
| Corregir findings | El dueño corrige el lote y prueba las reproducciones originales y regresiones afectadas. No devolver al reviewer ni abrir otro. Informar que las correcciones no tuvieron segunda revisión independiente. |
| Cerrar | El padre comprueba delta, salidas e identidad de fuentes; no vuelve a ejecutar los mismos probes/suites. Pendientes reales impiden afirmar cierre, no generan una cadena automática de revisores. |
| Continuar | Actualizar un resumen breve y seguir la siguiente capacidad autorizada. No worker documental separado ni permiso rutinario para actualizar expectativas obsoletas demostradas. |

## Fronteras y presupuesto

- Elegir objetivos como ejecución delegada, pausa/reanudación o routing; gramática,
  reservas y contadores son partes del objetivo, no nuevas rondas de aceptación.
- Un dueño de código/build y, al cierre, un reviewer como máximo. Trabajar directamente
  es válido. Paralelizar sólo frentes independientes con archivos/builds distintos.
- Reutilizar el implementador mientras su contexto sea útil. Un relevo por pérdida
  de contexto continúa el mismo objetivo desde un checkpoint; no reinicia el diseño
  ni recibe una revisión adicional. No cambiar modelos sin petición del usuario.
- Primer checkpoint: código ejecutado por el runtime real, aunque falte completar
  la vertical. No consumir otra sesión exclusivamente en auditar validadores ya sellados.
- Si reaparece el mismo fallo estructural, detener la estrategia y resolver el modelo
  común; no encadenar fix → review → fix. Si no hay avance ejecutable en un despacho,
  informar el bloqueo y replantear antes de gastar otro despacho equivalente.
- Tests pueden repetirse cuando cambian las fuentes o falla una comprobación; esto
  no autoriza reruns ceremoniales. Un fallo temporal requiere causa/evidencia, no
  cambiar guards, serializar la suite o subir límites para fabricar un verde.
- Un oráculo incorrecto puede corregirse con explicación del contrato y negativo
  equivalente; conservar el original y su fallo. No eliminar assertions válidas.
- El padre sólo ejecuta un check adicional si falta evidencia concreta o la identidad
  de fuentes es incierta. La razón y el resultado se registran una vez.
- No inventar consumo de cuota: registrar resultados/tiempo observado disponible,
  capacidades habilitadas y riesgos; no porcentajes subjetivos ni sumar reruns.

## Memoria y evidencia mínimas

- CURRENT de unas 100 líneas como máximo: objetivo, límites, dueño/sessionID,
  capacidades aceptadas, pendientes y siguiente acción. Detalle cerrado al historial.
- Un encargo corto por objetivo; enlazar decisiones vigentes, no copiar mandatos y
  logs completos. Un informe final con delta, comandos/exits, límites y hashes de
  fuentes runtime/tests afectadas. No exigir nuevos sellos por cambios sólo de prosa.
- Registrar intención antes de delegar y sessionID después. Esperar notificaciones;
  no polling. Un handoff con procesos activos conserva ownership hasta cierre real.
- La revisión de candidata R9 cubre integración/distribución y delta aún no revisado;
  no reaudita todas las capacidades aceptadas ni repite reviews de unidades cerradas.

## Protecciones que no se simplifican

Preservar WIP, contratos y negativos de seguridad; autoridad/CAS/ACK, incertidumbre,
cleanup y ausencia de replay. Mantener guards donde no exista evidencia suficiente.
Usar ReqLLM oficial stock y tooling aislado/offline. SQL, proveedores, infraestructura,
publicación, commits, cambios globales y consumidores requieren su autorización.
Un verde offline no certifica producción ni las fronteras externas G2–G6.
