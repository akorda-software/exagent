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
| Guards de publicación de docs | 17 pruebas offline pasan; historias Git reales, CLI autenticado y controles de readback |
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

HexDocs inserta un bloque de analytics en HTML y añade nofollow al enlace exacto
de ExDoc en el footer. La comparación pública normaliza sólo esas dos
transformaciones; cualquier otra diferencia falla. Esto se coteja con el index
y tres páginas del artefacto real y sus respuestas públicas originales.
Markdown y sidebar se comparan sin normalización. No afirmar igualdad raw del HTML.

Recibos privados: `.exagent-local/docs20261004/final-commands.json`, logs finales,
`final-source-identity.json`, `guards-17-final.log`, `quoted-doc-negative.log`,
`api-final-commands.json` y logs `*-opik-final.log`. FULL, SQL, proveedores y servicios mantienen sus recibos
anteriores; este delta no los repite ni reabre R9.

## Distribución

Primer envío: commit `4a933cc50f9c6b0fa193ab3e7986deb7f504c82e`,
[run37199064798](https://github.com/akorda-software/exagent/actions/runs/37199064798).
Guard, build, links, artefacto y publicación pasan. El readback falla por
un nofollow añadido al enlace ExDoc del footer; los diffs de las tres páginas
confirman únicamente esos9bytes tras quitar el analytics ya conocido.
El índice, Markdown y sidebar ya coincidían. El negativo remoto se conserva.

Con la normalización exacta corregida, lectura pública local del artefacto remoto:
7entradas coinciden y checksum del TAR intacto, exit0. No se relabela el job rojo;
un nuevo envío desde main debe acreditar el workflow completo en verde.
Recibos: `workflow-run01.json/log`, `*.html.diff`, `run01-corrected-readback.json`.

Segundo intento: commit `c96adafed2b5fab0aa7faae7feffc40a3b5c76ac`,
[run37199832107](https://github.com/akorda-software/exagent/actions/runs/37199832107).
Se detiene en lectura pública de GitHub: HTTP403rate limit. No compila ni publica.
La consulta pasa a `gh api` con GH_TOKEN automático/read-only únicamente en ese
paso; Hex no recibe ese token. Se verifica el despacho CLI y siguen pasando
los guards offline. Recibos `workflow-run02.json/log`. Nuevo envío pendiente.

La receta de VM explicita batch de8 o menos y timeout de4s para deadline2s,
dejando margen de1.5s para closure/receipt; el ejemplo directo de256 no se copia
sin ajustar. Generación estricta y4208/516/2519destinos siguen sin errores.
El paquete existente debe conservar SHA256
`c0402a9146b84d1e6f4a2fc04069502aa99e67e43809ccb1b8aca844a2d3be5d`.

## Distribución cerrada

Tercer envío desde main, commit `1fe5e006fd6ab68941c6865ecb6add95db9f3c70`:
[run37200325267](https://github.com/akorda-software/exagent/actions/runs/37200325267)
completado success. Job11:55:00–11:56:48UTC. Guard autenticado, compile, ExDoc,
links, artefacto, publicación sólo de docs y lectura pública pasan. El tag original
57c43a7 y SHA256 del paquete permanecen intactos. La consulta local autenticada
también pasa usando el config existente de gh; el XDG privado de tooling no
incluía ese login y se conserva su fallo local, sin modificar config global.

La lectura del job coteja índice, welcome, índice de tareas, agentes, llms,
README y sidebar con el artefacto retenido. Una lectura local posterior consulta
202 entradas HTML/Markdown/llms/sidebar:201 coinciden byte a byte tras las dos
transformaciones conocidas. api-reference difiere únicamente por rel=nofollow
añadido al enlace externo de MCP; texto, estructura y destino son idénticos.
No se trata esa transformación de HTML como un cambio de contenido del manual.
EPUB se valida localmente; no se afirma igualdad raw del binario publicado.
Las antiguas URLs roadmap, r4-implementation, production-acceptance y
execution-flow devuelven404 con la versión actual. Recibo `removed-pages.json`.

Recibos privados finales: `workflow-run03.json/log`, `github-artifact-final`,
`documentation-final.json`, `metadata-authenticated-final.log`,
`public-all-pages.json` y `api-reference.html.diff`.
El manual queda disponible en [HexDocs](https://hexdocs.pm/exagent/2.0.0/),
con [guía para agentes](https://hexdocs.pm/exagent/2.0.0/agents.html).
README y notas de GitHub apuntan a los contratos de uso actuales. Sin pendiente
de publicación, nuevo tag, bump, suite FULL o aceptación externa por este delta.
