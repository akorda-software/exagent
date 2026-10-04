# Manual público de ExAgent 2.0.0 — 2026-10-04

Encargo: publicar documentación de lo que ofrece la versión y cómo se usa, sin
roadmap ni historia de implementación. Se conserva esa evidencia en el checkout,
fuera de ExDoc. No se cambia versión, tag, comportamiento ni dependencias.

## Contenido

El sitio presenta inicio, guías por tarea, integraciones, referencia y arquitectura.
El índice público y la matriz de capacidades ya no son los registros internos
docs/README.md y docs/status.md. README usa la dependencia publicada, los perfiles
actuales y el reparto de trazas/métricas. Migración describe actualizar una app,
sin planes pendientes contradictorios. Se alinean observabilidad, recuperación,
MCP y recetas; se eliminan fases antiguas de cinco módulos. Event aclara topics
scoped/emitter y TurnPolicy referencia SupervisorPolicy, no un nombre inexistente.

Langfuse y Opik tienen instrucciones OTLP, autenticación, contenido off por defecto
y comprobaciones de jerarquía/atributos/errores. Sus endpoints y headers se cotejan
con la documentación oficial; no se afirma una nueva ola de aceptación cloud.

Las páginas anteriores quedan archivadas en
`docs/archive/2026-10-04-documentation-records/`. Los planes, recibos y prompts
permanecen disponibles para el mantenimiento; ExDoc no los publica.

## Verificación local

Elixir 1.20.0 / OTP 29, tooling privado oficial Hex 2.5.1, dotenv deshabilitado,
offline y copia aislada, sin alterar build compartido/configuración global.

| Comprobación | Resultado |
|---|---|
| Guard del runtime contra tag v2.0.0 | AST ejecutable/specs, proyecto/deps, config, ejemplos e inventarios iguales |
| Guards de publicación de docs | 15 pruebas offline pasan; historias Git reales y controles de readback |
| Ejemplos documentados | 19 casos pasan, incluida la proyección Opik tomada del bloque de la guía; los bloques de deps/Config/MCP externos son syntax-only, no ejecución externa |
| Sintaxis de guías públicas | 61 bloques Elixir y un fragmento de lista válidos |
| Compilación dev/test | Estricta, exit0 en ambos |
| Formato y actionlint | Exit0 |
| ExDoc | HTML, Markdown y EPUB estrictos, exit0 |
| Sitio público | 102 páginas HTML/4208 destinos;100 Markdown/516 destinos;100 EPUB/2519 destinos;0 errores |

Se retiene el negativo del enlace antiguo de tools/output a una sección R2 de
migración; el enlace corregido pasa. El control de macro documentada reprodujo
que quitar atributos dentro de quote escondía un cambio ejecutable; el guard
se limita ahora a atributos de módulo y conserva íntegros los cuerpos de macros.
Ese negativo falla antes de la corrección y el caso pasa después. También se
rechazan fuente/specs/deps/config/examples/version/inventario modificados,
checkout sucio, rama sin integrar, paquete sustituido y páginas obsoletas.

HexDocs inserta un bloque de analytics en HTML. La comparación pública elimina
sólo ese bloque exacto; cualquier otra transformación falla. Esto se coteja con
el index del artefacto de la publicación real y su respuesta pública original.
Markdown y sidebar se comparan sin normalización. No afirmar igualdad raw del HTML.

Recibos privados: `.exagent-local/docs20261004/final-commands.json`, logs finales,
`final-source-identity.json`, `guards-final.log`, `quoted-doc-negative.log`,
`api-final-commands.json` y logs `*-opik-final.log`. FULL, SQL, proveedores y servicios mantienen sus recibos
anteriores; este delta no los repite ni reabre R9.

## Distribución

Preparación local cerrada. Pendiente ejecutar `documentation.yml` desde main,
actualizar sólo HexDocs y registrar commit, job y comparación pública.
El paquete existente debe conservar SHA256
`c0402a9146b84d1e6f4a2fc04069502aa99e67e43809ccb1b8aca844a2d3be5d`.
