# Preparación de ExAgent2.0.0 — 2026-10-03

El usuario autoriza la salida, acepta conservar los límites externos sin modificar
los proyectos upstream y después pide dejar preparada para mañana la publicación
automática desde GitHub. Se prepara versión/documentación/workflow y commit/push
en la rama actual; no se hace merge, tag oficial, GitHub release ni publicación Hex.

## Resultado y próximo paso

- `mix.exs` declara2.0.0. Guías, instalación, footer y changelog están alineados.
- Workflow `.github/workflows/release.yml`: release publicada estable; la ejecución
  manual sólo prepara artefactos. Guard de tag/version/notas/docs/main y repo dueño.
- Compila y genera docs/TAR; no vuelve a correr las suites largas en GitHub.
- API key limitada a `package:hexpm/exagent`, sólo en el paso de escritura.
  Hex documenta que las API keys no requieren TOTP por publicación. Creación web
  pendiente con el usuario; no se crea clave ni se cambia2FA esta noche.
- Sin reemplazar versiones:404 publica paquete/docs;200 exige identidad del TAR
  y publica sólo docs. Otros HTTP, fallo de red o bytes distintos detienen escritura.
- Readback público exige mismo TAR y documentación con la versión correcta.
- Pendiente para mañana: configurar `HEX_API_KEY`, integrar PR1 en main, tag estable,
  preview opcional y publicación de la release oficial. Ver
  [procedimiento](../../development/releasing.md) y el borrador de notas en `.github/`.

## Verificación nueva, sin envío real

Tooling privado de `docs/development/environment.md`; no modificación del Hex
compartido. Fuente física privada en `.exagent-local/release20261003/candidate`.
API de proveedores/SQL/cloud no utilizada; descargas públicas de tooling y deps.

| Control | Resultado | Alcance |
|---|---|---|
| `python3 test/support/release_workflow_test.py` |17 pasan |11 guards con Git real temporal y6 escenarios del shell real del workflow con CDN loopback/CLI recorder. No envío Hex |
| Actionlint1.7.12 |exit0 |Workflow, expresiones y shell; actions fijadas a SHA oficiales |
| `python3 bin/release-check v2.0.0 --prepare` |exit0 |Metadatos; no acredita tag ni merge |
| Format/locked deps/compile dev |exits0 |Elixir1.20/OTP29; lock intacto, dotenv deshabilitado |
| ExDoc estricto y lector HTML/MD/EPUB |exits0 |123HTML/121MD/121EPUB, cero errores locales en la primera generación |
| Dos builds Hex |exits0, bytes idénticos |175archivos/94fuentes de biblioteca, versión2.0.0 |
| Aislamiento del paquete |exit0,22.161s |Controles de bootstrap/destinos, sin aceptación cloud |
| Compile test y documentation probe |exits0;18pasan |Headings reales actualizados; snippets/syntax gates, sin nuevas pruebas provider |
| Consumidor mínimo desde TAR |8contratos pasan,0fallos/exclusiones/skips |App instalada confirma2.0.0.32.179s; diagnóstico agregado exit1 por38avisos upstream |

Los17 controles incluyen tag estable, mismatch, changelog ausente, introducción/
footer obsoletos, worktree sucio, tag ausente/otro commit, commit fuera de main y
modo metadata-only. El shell real prueba paquete ausente, recuperación de docs
con TAR idéntico, mismatch de bytes, HTTP503, clave ausente y fallo del publisher.
No se prueba autenticación real con una clave ni una ejecución remota de Actions.

Primera TAR2.0.0 instalada:
`825623aee4d1349d708941e87a6ac3c1459b411be9c9c6b6d5030372ee36e2d4`.
TAR final:
`5039c43d1445b7750a0173d8801c5901e89054ffaaf59057b39d5c22ee53ecd2`.
175archivos/94lib, todos idénticos al checkout. Sólo cambia prosa en seis archivos
docs respecto a aquella TAR instalada. ExDoc final exit0/2.440s, lector
exit0/0.325s y build final exit0/0.424s;123HTML/5500targets,121MD/931targets y
121EPUB/3044targets, cero errores. `artifact-final.json` conserva manifiesto y
delta; ninguna TAR se ha publicado.

## Evidencia reutilizada y deuda externa

Todas94fuentes `lib/` y `mix.lock` permanecen idénticas a `fc19683` y al freeze
FULL de2235/0/28. De los447 inputs anteriores sólo cambian `mix.exs` (versión/
footer/extra de docs) y los dos selectores de heading del probe documental.
Workflow/guard/tests de publicación son controles nuevos, verificados arriba.
No se repite FULL, G2/SQL/backend ni la revisión independiente R9.

El consumidor nuevo conserva los38warnings TOML/WebSockex y exit1 del agregado
estricto, aunque todos sus comandos funcionales salen0 y los8contratos pasan.
El gproc de exporter conserva su recibo anterior; no se instala en el perfil mínimo.
El usuario acepta la salida con esta deuda externa. No se oculta el run remoto
anterior rojo ni se convierte en verde mediante overrides/forks/parches.
HTTP nativo directo sigue limitado; la receta VM permanece cualificada.
