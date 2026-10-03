# Aceptación visual A10 — 2026-10-02

El usuario preparó y autorizó la inspección de su sesión autenticada de Langfuse
en el navegador Orca. Esta autorización sustituye la preferencia anterior de
comprobar las trazas sólo desde su navegador; no autoriza commit/push, publicación
ni cambios de configuración global. Se usó una única pestaña del proyecto
`cmujo5tsd08uiad0cqi6bw9ag`, que permanece abierta en Recovery / paused / Attributes.

Resultado: G4 aceptado para la pareja sintética A10 native→Collector→Langfuse.
Flow `2237aa029ba291aa36501dc62bb10b98` y Recovery
`0a56501beec20d4f91f61c85ae157f49` son los mismos IDs de la aceptación API anterior.
La inspección compara 12 observaciones y 248 atributos renderizados con el
manifiesto nativo; cinco capturas nuevas sin modificar fueron inspeccionadas,
además de las dos capturas originales del usuario.

- La pausa muestra `paused` y la reanudación `succeeded`, sin error en esos pasos.
- Ambas conservan `run_2TnVj3ehA-byUySNVOpCvw` y
  `record-WkJfuEn1gl-5xn3lOTqqnQ`. Cambian los intentos de
  `attempt-EzrjbQLeWgkg6CBS3juCbA` a `attempt-XYL517c-xaxkwVnyFWOV9Q`.
- La herramienta aprobable cambia de `pending` a `succeeded`. Los dos spans son
  intentos del mismo call lógico; contar spans no equivale a contar efectos.
- Los errores deliberados de herramienta y checkpoint tienen reintentos exitosos.
  La UI mantiene los tres badges ERROR del escenario de fallos original.
- El árbol de Flow representa router, ramas paralelas y tool→delegation→child.
  El agregado de la rama paralela muestra seis requests; no sumar ese padre como
  otra generación junto a sus hijos.
- Uso `reported`, procedencia `model`/`aggregate`, disponibilidad y unidades son
  accesibles. El modelo `test` muestra coste `0.03` cents, `estimated` y fuente
  `estimator`; no es factura. Los resúmenes14/20tokens son sintéticos de TestModel.
- Content está desactivado: Input null / Output undefined es esperado. No se
  observaron atributos `exagent.content.*` ni los sentinels privados en las vistas.

Recibo final bajo `/tmp/opencode/exagent-v2-codex-t6qgpstl/`:
`langfuse-ui-agent-2026-10-02/ui-acceptance.json`, SHA256
`a2058c08d89b5b1d9f4036e87e9626bbe20cf8988faf47115573a830da99d8f3`.
El recibo incluye hashes de las imágenes, DOM/snapshots y controles. La onda de
12 observaciones utilizó59comandos Orca/24.238s, más dos vistas focales de estado;
la pausa reutilizó el DOM y snapshot previos. Los errores iniciales de captura
Orca y el recibo incompleto se conservan, sin atribuirlos al runtime ExAgent.

No se volvieron a ejecutar Producer, SDK, Collector ni Model; cero consultas REST
directas. La navegación UI sí realiza sus lecturas de backend. No se extrajeron
cookies o credenciales, ni se cerró la pestaña del usuario. Se reutiliza la prueba
API33observaciones/667atributos, recibo `4fb95d1a…6c825`, sin alterarlo.

Los contadores host12requests/6calls lógicas/4efectos tienen evidencia del harness
nativo previo; la UI muestra estados e invocaciones y no demuestra por sí sola
efectos externos únicos, retención durable, facturación o cualquier despliegue.
G4 cerrado en este perfil no cierra CI remoto exacto ni diagnósticos estrictos de
dependencias. Revisión R9 única ya cerrada; no nueva revisión por este registro.
