# Retrieval como Tool de la aplicación

La receta [external_retrieval.exs](https://github.com/akorda-software/exagent/blob/main/examples/external_retrieval.exs) usa las
APIs públicas de ExAgent y una función de búsqueda inyectada. No añade una base
vectorial, un cache global ni una dependencia de servicio al core.

La aplicación autentica al caller y entrega `deps: %{space: space, search: search}`.
`search.(space, query, limit)` devuelve `{:ok, hits}` o `{:error, reason}`. Ese
adapter debe aplicar el espacio en su base de datos/servicio; ExAgent no puede
reemplazar la autorización de ese origen. El modelo sólo puede enviar `query`.
Los argumentos con un selector de espacio adicional se rechazan antes del IO.

Cada búsqueda admite hasta tres resultados. Un resultado contiene sólo
`reference` (1..512 bytes UTF-8) y `text` (hasta2048 bytes UTF-8), con referencias
únicas. Datos mal formados o mayores se rechazan enteros. El cliente externo
debe acotar sus propias descargas y decodificación: la validación posterior no
promete una cota RAM previa a recibir esos datos.

Los pasajes llegan como `ToolReturn` en la historia canónica. No se convierten en
instrucciones system, permisos, actor de aprobación ni credenciales. Las reglas
de autoridad del run siguen siendo responsabilidad del host. Los errores del
origen, incluidas excepciones, throws y exits capturables del callback, se
proyectan a `retrieval_unavailable`; no se copian respuestas privadas,
headers ni configuración de la conexión al resultado o al mensaje de error.

El script contiene comprobaciones deterministas de dos espacios, conteo de
llamadas al origen, roles, argumentos inválidos, tamaño, deps ausentes y cuatro
formas de error con un sentinel privado. Cada fallo ejecuta una búsqueda, sin
retry, y conserva los contadores sin incluir su detalle en ToolReturn/RunError. Puede
ejecutarse en un consumidor extraído del paquete con:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/external_retrieval.exs
```

La receta pasó sus comprobaciones en VM desechable sobre el build estable del
2026-10-01 (exit0, sin Mix/red/credenciales); log en
`/tmp/opencode/exagent-v2-codex-t6qgpstl/package-portability/retrieval.log`.
Faltan la ejecución sobre el TAR candidato y la revisión de integración antes
de aceptar R7.6. No cualifica un servicio de búsqueda
real ni resistencia de un modelo a prompt injection; demuestra la frontera host
y los roles que el framework conserva.
