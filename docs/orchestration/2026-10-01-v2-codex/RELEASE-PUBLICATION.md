# Publicación de ExAgent 2.0.0 — 2026-10-04

El usuario autorizó tag/release y publicación real, con los cambios integrados
directamente en main. No se movió un tag existente ni se sustituyó un paquete.

| Identidad | Valor |
|---|---|
| Tag oficial | `v2.0.0` |
| Commit del tag y release | `57c43a72885b9fb43c5c9a24333fcaa59d76fc97` |
| GitHub publicado | `2026-10-04T10:20:05Z`, estable, no borrador |
| Hex publicado | `2026-10-04T10:22:36.448978Z`, activo, con docs |
| Job de publicación | `37195029263`, completado, success |
| SHA256 del TAR público | `c0402a9146b84d1e6f4a2fc04069502aa99e67e43809ccb1b8aca844a2d3be5d` |
| Contenido | 175 archivos, 94 fuentes de biblioteca |

[Release oficial](https://github.com/akorda-software/exagent/releases/tag/v2.0.0),
[ejecución](https://github.com/akorda-software/exagent/actions/runs/37195029263),
[paquete](https://hex.pm/packages/exagent/2.0.0) y
[documentación](https://hexdocs.pm/exagent/2.0.0/).

El TAR descargado desde repo.hex.pm es idéntico byte a byte al artefacto retenido
por GitHub. Sus 175 contenidos coinciden con las fuentes del tag. El checksum
oficial de la API Hex coincide con el SHA256 del TAR descargado. La lectura de
HexDocs confirmó la versión servida. Estos controles acreditan distribución,
no una nueva ejecución de pruebas de modelos, SQL o backends de observabilidad.

El TAR preparado localmente tiene otro hash: permisos 0600 frente a 0644 en
algunas copias y distinto orden de inventario/compresión. Sus 175 contenidos
son idénticos; los términos de metadata.config son iguales al normalizar el
orden de archivos. No se presenta ese TAR como idéntico byte a byte al publicado.
El negativo inicial de igualdad local se conserva en el recibo privado.

Evidencia local privada: `.exagent-local/publish20261004/publication.json`,
`workflow.json`, `workflow.log`, `hex-release.json`, artefacto descargado y
comparación de metadata. No contienen la API key. El secreto de GitHub sólo se
entregó al paso de escritura; se mantuvo TOTP de la cuenta sin interacción por envío.

La preparación final pasó compilación, ExDoc estricto, enlaces, build, aislamiento
y metadatos. Las 159 pruebas focales anteriores cubren los deltas de octubre 4;
el FULL 2235/0/28 conserva su fecha y no se relabela como una nueva suite.

## Actualización del manual público

El usuario pidió documentación centrada exclusivamente en funciones y uso de
la versión publicada. Los planes, auditorías y recibos se conservan en el repo,
fuera de los extras públicos de ExDoc. README, guías y referencia de API se
alinean con el contrato actual. Se conserva una copia fechada de las páginas
reescritas en `docs/archive/2026-10-04-documentation-records/`.

`documentation.yml` actualiza únicamente docs para una versión ya publicada.
El guard compara AST ejecutable, specs, configuración, dependencias, ejemplos
y sus inventarios con el tag; sólo permite prosa y configuración de ExDoc.
Los checks de esta actualización y su lectura pública se registran en
DOCUMENTATION-PUBLICATION.md al terminar. No hay bump, tag nuevo ni reemplazo.
