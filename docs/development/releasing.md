# Publicar ExAgent en Hex

La versión2.0.0 ya está publicada: [release](https://github.com/akorda-software/exagent/releases/tag/v2.0.0),
[Hex](https://hex.pm/packages/exagent/2.0.0) y [recibo](../orchestration/2026-10-01-v2-codex/RELEASE-PUBLICATION.md).
Por decisión
2026-10-04 se trabaja directamente en `main`: commit/push de cambios verificados,
sin una PR obligatoria. Publicar una release estable en GitHub activa la subida
a Hex. El usuario configuró `HEX_API_KEY` en GitHub el2026-10-04. El job de cada
release comprueba la publicación y sus bytes públicos; tener el secreto guardado
por sí solo no acredita autenticación. Las pruebas aceptadas conservan sus recibos.

## TOTP y la clave de publicación

Sí se puede automatizar manteniendo el segundo factor de tu cuenta. Hex distingue
el login OAuth interactivo, que puede pedir TOTP al escribir, de una clave de API,
que no pide TOTP en cada publicación. Al crear o gestionar la clave desde la web
sí puede pedir el segundo factor. Véanse la
[documentación de autenticación](https://hex-core.hexdocs.pm/hex_core.html) y el
[anuncio oficial de Hex2.4](https://hex.pm/blog/hex-v24-released).

Preparación única, desde tu navegador:

1. En [las claves de Hex](https://hex.pm/dashboard/keys), crear una clave llamada
   `exagent-github-release` desde la cuenta propietaria del paquete.
2. Seleccionar el permiso del paquete **exagent**, dominio `package`, recurso
   `hexpm/exagent`. No hace falta una clave con escritura para toda la cuenta.
   Este permiso permite publicar paquete y docs; el recurso está limitado al
   paquete existente. Hex comprueba también la propiedad. El
   [contrato oficial de permisos](https://github.com/hexpm/hexpm/blob/main/lib/hexpm/accounts/key_permission.ex)
   describe estos recursos.
3. Guardarla en el repositorio GitHub como secreto de Actions **`HEX_API_KEY`**:
   [configuración de secretos](https://github.com/akorda-software/exagent/settings/secrets/actions).
   También sirve `gh secret set HEX_API_KEY --repo akorda-software/exagent`, que
   solicita el valor por entrada interactiva. No copiarlo a un archivo del repo.
4. Si la clave tiene caducidad, renovar ese secreto antes de la siguiente release.
   La clave no se guarda en las notas, los artefactos ni el código.

La clave sólo se entrega al paso que escribe en Hex. La ejecución manual de
preview no la recibe. No se automatiza el generador TOTP ni se desactiva2FA.
El comando stock es `mix hex.publish --yes`, con `HEX_API_KEY` en el entorno;
publica paquete y documentación. Véase
[Hex publish](https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html).

## Actualizar únicamente HexDocs

Para corregir el manual de una versión publicada, comitear los cambios verificados
directamente en main y ejecutar **Update published HexDocs**:

```bash
gh workflow run documentation.yml --repo akorda-software/exagent --ref main -f tag=v2.0.0
```

Este flujo manual sí escribe documentación. El preview manual de `release.yml`
continúa sin publicar. No crear otro tag, cambiar versión ni sustituir el paquete.
`python3 bin/docs-release-check v2.0.0 --prepare` permite comprobar el delta local:
analiza fuente Elixir sin evaluar el código del tag y compara AST ejecutable,
specs, proyecto/dependencias, configuración, ejemplos e inventario. Sólo permite
prosa y funciones de configuración de ExDoc. Su modo prepare no autoriza escritura.

El job exige checkout limpio de main y una release estable activa en GitHub/Hex.
La consulta de GitHub usa `gh api` con el token automático de lectura del job,
evitando el límite anónimo. El check local requiere `gh` y su login ya configurado;
`--prepare` no consulta redes. Las lecturas de Hex no reciben ese token.
Compila, genera ExDoc estricto y verifica HTML, Markdown, EPUB y ausencia de
planes/historia de desarrollo en las páginas públicas. Conserva páginas y las
identidades del tag y del commit documental. Sólo el paso `hex.publish docs --yes`
recibe la clave. La lectura pública exige los mismos bytes para entradas y sidebar,
normalizando sólo el bloque exacto de analytics y el nofollow del enlace ExDoc
que HexDocs añade en HTML,
con reintentos de propagación, y que el TAR existente conserve su checksum.
Las suites largas y los proveedores pagados no se vuelven a ejecutar por prosa.

Las páginas públicas usan links de fuente al commit documental. El tag conserva
las fuentes originales del paquete; la equivalencia AST permite mejorar sus
moduledocs sin alterar el comportamiento publicado. Nunca se usa `--replace`.

## Lanzar la versión oficial

1. Antes de cerrar el commit de release, validar los cambios localmente.
   `./bin/check` es la rutina completa; un delta causal posterior conserva el
   alcance y los bytes de la referencia anterior y verifica sus contratos
   afectados. Para versión/prosa/workflow, ejecutar guards, formato, docs y TAR.
   Documentar qué pruebas cubren cada fuente. No reabrir R9 ni añadir proveedores
   pagados a la publicación.
2. Mantener alineados `@version` en `mix.exs`, el encabezado de release en
   `docs/changelog.md`, las guías de instalación y el footer. Para esta salida
   están preparados como2.0.0. Comprobar localmente:

   ```bash
   python3 test/support/release_workflow_test.py
   python3 bin/release-check v2.0.0 --prepare
   ```

   `--prepare` valida metadatos; no demuestra un tag ni autoriza publicar.
3. Comitear y pushear la preparación directamente en `main`. La versión
   oficial debe incluir el workflow y corresponder a un commit ya integrado.
4. Crear un tag `v2.0.0` sobre ese commit y pushearlo, sin mover un tag existente.
   Un push del tag por sí solo no publica en Hex.
5. Opcional: ejecutar **Publish official release to Hex** desde Actions, indicando
   el tag. La ejecución manual compila y prepara los artefactos, sin publicar.
   Equivalente: `gh workflow run release.yml --repo akorda-software/exagent --ref main -f tag=v2.0.0`.
6. Publicar en GitHub una release para ese tag, con **prerelease desactivado**.
   Publicar una release borrador dispara entonces el flujo automáticamente.
   Las notas propuestas están en
   [el borrador de v2](https://github.com/akorda-software/exagent/blob/main/.github/release-notes-v2.0.0.md).

El workflow escucha `release: published`; omite borradores/prereleases y rechaza
tags con sufijos o versiones no canónicas. La selección del tag pasa por una
variable de entorno, sin interpolar su texto dentro de código shell. Comprueba
tag exacto, versión, notas, introducciones actuales y pertenencia a `origin/main`.
Ver [eventos release de GitHub](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release).

## Qué comprueba GitHub

Elixir1.20.0/OTP29.0.5 y Hex2.5.1, dependencias según lock sin actualizar,
compilación estricta del paquete, ExDoc estricto, enlaces HTML/Markdown/EPUB,
build Hex y controles de aislamiento del TAR. Conserva paquete, SHA256, commit y
documentación como artefacto. Las actions quedan fijadas a commits concretos.

Las suites largas permanecen locales. `CI` sigue siendo manual y separado de
este workflow. Los warnings externos siguen visibles, con el diagnóstico estricto
rojo ya documentado; no se introduce una supresión ni un override upstream para
publicar. El usuario acepta esa deuda en los perfiles cualificados actuales.
La publicación no ejecuta las pruebas pagadas, SQL ni Langfuse/Opik otra vez.

Tras subir, descarga el TAR público y exige igualdad byte a byte con el retenido.
Comprueba también que responde la página de docs para esa versión. Esto verifica
distribución; no constituye una nueva aceptación universal de runtime o backends.

## Reintentos y recuperación

Nunca se usa `--replace`. Si el TAR no existe, el paso publica paquete y docs.
Si ya existe y coincide exactamente, sólo publica docs; permite recuperar un
fallo posterior a la subida del paquete. Si difiere, se detiene sin sobrescribir.
Un error de red o HTTP distinto de200/404 también detiene la escritura.

Si falla la lectura pública inmediatamente después de subir, comprobar primero
el estado de Hex y la propagación de docs; un fallo del job no despublica un
paquete ya aceptado. Se puede reintentar el mismo workflow y commit. Para un
paquete con bytes distintos hace falta investigar y decidir una versión nueva,
no mover el tag ni forzar una sustitución.

La autenticación y la publicación real se comprueban en el job de la release
oficial. Los controles locales no se presentan como una ejecución remota de
GitHub ni como una publicación en Hex.

Verificación de la preparación2026-10-03:17 controles offline de guards Git y recuperación
contra un servidor loopback pasan; el CLI de publicación se sustituye por un
recorder, sin escribir en Hex. Actionlint1.7.12 acepta el workflow. Compilación
estricta dev/test,18 ejemplos documentados, ExDoc y enlaces, build repetible e
aislamiento del TAR pasan. Un consumidor limpio instalado de2.0.0 pasa8contratos;
su diagnóstico agregado conserva exit1 por38warnings stock. Las94fuentes de
biblioteca y el lock eran idénticos al FULL aceptado; no se repitió aquella suite.
Los deltas de envelope y retención del2026-10-04 cambian dos fuentes y pasan
159focales juntos en14,3s. El FULL anterior y su TAR no se presentan como nuevas
pruebas de esos deltas. La preparación está integrada directamente en main;
GitHub marcó la PR1 integrada al recibir el push, sin un merge adicional.
El [recibo de preparación](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/RELEASE-PREPARATION.md)
conserva identidades y alcance de artefactos.
