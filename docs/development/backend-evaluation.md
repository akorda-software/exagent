# Elección y aceptación del backend de observabilidad

**Estado: pendiente.** La instrumentación neutral ya está implementada y el
transporte OTLP se inspeccionó localmente. No hay un backend elegido ni una
comparación API/UI ejecutada. Esta página es el siguiente plan concreto, no una
decisión de despliegue.

**Dato confirmado por el usuario (2026-09-10): ya existen algunas instancias de
Opik.** La siguiente sesión parte de ellas. Faltan destino concreto, versiones,
acceso autorizado e información sobre uso/histórico; su existencia no implica
permiso para modificar todas las instancias ni leer sus datos reales.

## Lo decidido

- OTel nativo y configuración de SDK/exporter propiedad de la aplicación.
- Collector opcional; ExAgent no incorpora la plataforma al core.
- Contenido off, opt-in con redactor previo y límites; sin serializar modelos,
  deps, credenciales o baggage en atributos.
- Langfuse OSS era candidato preferente provisional para una integración nueva,
  no una decisión tomada. Con Opik existente, usarlo como punto de partida y
  preservar cualquier histórico hasta demostrar una ventaja de migración.
- A calidad comparable se prefiere más funcionalidad sin licencia comercial.
  Funciones administrativas comerciales sólo compensan por una ventaja demostrada;
  esa preferencia no autoriza compras ni necesita preguntarse otra vez.

## Información necesaria para la siguiente sesión

1. Dónde probar: instancia existente, alojamiento y versiones disponibles.
2. Cuáles de esas instancias están en uso y qué histórico debe conservarse.
3. Acceso autorizado a un proyecto/entorno sintético, endpoints y credenciales
   configuradas fuera del repositorio y de los argumentos de bootstrap.

No registrar valores de credenciales aquí. Crear infraestructura, contratar
servicios o cambiar consumidores requiere alcance explícito.

## Gate previo: transporte fiable

El exporter HTTP1.10.0 convierte booleanos en strings, ignora successful
`partial_success` y conserva recursos HTTP/perfiles/átomos en ciertos ciclos.
El processor limita sus propios recursos, pero no corrige ese lifecycle ajeno.
Resolver o verificar una alternativa de transporte/ownership antes de presentar
esa receta como operación longeva aceptada. La
[guía de observabilidad](../guides/observability.md) conserva el detalle.

## Comparación con el mismo escenario

Reutilizar `test/support/native_otlp_scenario_probe.exs` y los datos sintéticos
de las pruebas. Fijar versiones de ambas plataformas y revisar sus docs/licencias
actuales antes de conectarlas; las fuentes históricas no certifican la versión futura.

| Tarea de diagnóstico | Qué comprobar en API y UI |
|---|---|
| Reconstruir un run | Un span por operación, parentesco, IDs y delegación; sin spans por token. |
| Encontrar fallo/retry | Corrección explícita, tool con efecto previo, error posterior a hook y cancelación parcial. |
| Explicar uso/coste | Requests frente a subtotales inclusivos, cache, datos desconocidos y ningún doble conteo. |
| Recuperación | Primer save fallido y retry-save sin reabrir ni repetir el run. |
| Privacidad/contexto | Contenido permitido/redactado y separación de callers; sentinels privados ausentes. |
| Operación | Backend caído/lento, pérdida observable, latencia y recuperación de recursos. |
| Producto y licencia | Funciones realmente usadas, limitaciones OSS, pasos de diagnóstico y esfuerzo de operación. |

HTTP200 y un árbol visual parecido no bastan. Registrar información perdida,
aciertos, pasos/tiempo para localizar cada fallo y límites operativos. La decisión
final debe explicar por qué una opción sirve mejor a esas tareas.

Prompts, datasets, scores, evaluaciones e históricos tienen integración/migración
separada: cambiar endpoint OTLP no los traslada. Después de decidir, actualizar
[estado](../status.md), [roadmap](roadmap.md), guía y aceptación del paquete.
