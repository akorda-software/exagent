# ReqLLM 1.26 — actualización autorizada, 2026-10-02

Base Git a63ccb7f78c436e577c53092b7a5cc016906a617; rama codex/v2-candidate-029.
El usuario solicita actualizar de 1.24 a 1.26 y validar todo localmente. Mantener
ReqLLM oficial stock, guards, una revisión como máximo y la cadencia funcional.
Commit/push/PR autorizados previamente; sin bump/tag/merge/Hex ni cambios globales.

## Delta

- Requisito `req_llm ~> 1.26.0`; lock 1.26.0 y catálogo requerido llm_db 2026.9.8.
  Otras entradas del lock raíz conservadas. `deps.update` propuso cinco upgrades
  transitivos innecesarios; se restauraron las entradas compatibles y `deps.get`
  verificó la resolución mínima. No se parchea código upstream.
- Runtime ExAgent conserva implementación y contratos; sólo cambia el moduledoc
  del adapter. 1.26 preserva Anthropic `redacted_thinking` como `provider_block`:
  la nueva caracterización exige el contenido exacto, guard thinking sin IO y
  rechazo explícito del bloque no cualificado en vez de perderlo al continuar.
- Nueva regresión pública de cache read/write separada, input inclusivo y
  reasoning ya incluido en output, conservando calidad normalized/presencia
  unknown. No se habilita thinking ni se convierte el accounting en observado.
- Entry G2 exige 1.26.0 antes de Model IO y escribe la versión runtime real en el
  manifest. El primer intento conservado falla en el pin 1.24 antes de crear
  artefactos/admitir requests; no consume inferencia ni se borra su log.
- Diseño/migración/changelog/estado distinguen esta fuente de las aceptaciones 1.24.

## Evidencia recibida

| Gate | Resultado y frontera |
|---|---|
| Focal stock inicial | 116/117; caracterización Anthropic obsoleta, fallo conservado |
| Focal corregido | 19 pases / exit 0; cache nuevo y rechazos Anthropic precisos |
| C0/snippets/processor/evals/load 1.20 | Seis comandos exit 0 / cero warnings de compilación; 17 probes documentales y un processor pasan |
| G2 real 1.26 | 14/14, 17 requests / 3 efectos, 18.65 s; GPT-4o-mini/OpenRouter, chat_tools_v1/native schema |
| G2 presupuesto | Cap de 20 requests / USD 0.50; 17 admisiones / USD 0.425 reservado; factura no observada |
| PG 17.4 actual | 14 fases pasan, 68.39 s; restart/lostACK/two-resumers/Flow/recovery/backup, cleanup e hijos cerrados |
| App offline | Copia privada Phoenix: 15 pases / 18 live excluidos; compile estricto pasa |
| App real 1.26 | 18/18 en una ola, 35.67 s, 36 admisiones / USD 0.90 reservado; grupos cerrados y fuente intacta |
| App original | 57 fuentes verificadas byte a byte; sin cambios/commit ni copia de credenciales |
| Consumidores limpios | 8 grafos × 7 contratos: 56 pases, cero fallos/exclusiones/skips; 46 comandos únicos exit 0 |
| Diagnóstico estricto | Ambos runners exit 1 sólo por warnings: TOML 15 en 1.18; TOML 19 + WebSockex 19 en 1.20, más gproc 9 en exporter |
| FULL 1.20 | 2.177 pases / cero fallos / 28 exclusiones; 1.999,3 s; rutina de nueve fases exit 0, total 2.052,50 s |
| FULL 1.18 original | 2.176 pases / un fallo / 28 exclusiones; 2.013,4 s; runner exit 1, fuente/fallo conservados |
| Corrección ownership | 12 casos + control de arranque lento pasan por runtime, 0,7 s; readiness 152 ms / cancelación observada 0 ms |
| ExDoc final | Exit 0, cero warnings; 116 HTML / 5.138 targets, 114 Markdown / 811 targets, 114 EPUB / 2.837 targets; cero enlaces/anchors/recursos locales rotos |
| TAR final | 167 archivos exactos; metadata y las 91 fuentes lib/mix idénticas al TAR de los consumidores; sólo seis documentos cambian |
| Metadata final | Ambos runtimes cargan el proyecto empaquetado sin ExDoc ni diagnostics; dependencia `~> 1.26.0`, nominal 1.3.0 intacto |

El lock raíz SHA256 es
`99d00de1a1f9e89e20b1efac3da25e72b932f8f6a36790e4e1acb5d9fb14188d`.
G2 fingerprint de lib/config/mix/lock/README:
`034a3cfadcccde6b6bd57ba82db8c60584a3ff87e429088fbb60764c1c08462a`;
manifest SHA256 `117c7bb612bc4ea722b8ba034baa9c467f753269e789e641c3abd1f6d0ed72cc`.
SQL: /tmp/exagent-pg-ty5s9z5u/report.json,
SHA256 `e35800570480f4bcb26a0efca39136de0afb8723838e23982291def33a6e368d`.
App: consumer-live/wave-01/receipt.json; fixture/admission/source/log separados.

TAR de cualificación de consumidores: 167 archivos exactos al checkout al crearlo,
SHA256 `5c9d69435688412256a4c9fe9fa2c537e07d8b0c40a02f2591ecace677d66c5b`.
Sin lock de entrada, cada grafo resuelve sus dependencias en fuentes/deps/build/
tooling físicos privados. Ambos usan ReqLLM 1.26.0; las warnings permanecen como
fallo estricto independiente de los contratos. Runners: 109.86 s en 1.18 y
137.02 s en 1.20, con dos schedulers por instancia. Recibos `consumers118/`,
`consumers120/`, `package-matrix.json` y `package-versions.json`.
TAR final SHA256:
`2dd7db51fff9da3908a1ca46e8daedd42f642bd8884198c4917971646ed1b733`.
El readback comprueba los 167 archivos contra el checkout, metadata idéntica y
las 91 fuentes lib/mix idénticas al TAR de consumidores. Sólo cambian README,
changelog, roadmap, status, verificación y migración para actualizar resultados
y referencias vigentes. README es un delta sólo documental del fingerprint G2;
no se renombra aquel manifest. Probes de metadata finales pasan
en ambos runtimes sin ExDoc; aislamiento pasó en la rutina con el TAR cualificado.
Recibo `final-tar-source.json`; preview local actualizado con el sitio generado.

## Fallo de readiness y corrección causal

La suite 1.18 falla antes de matar al owner: `assert_receive {:tool, worker}` usa
el default de 100 ms. No falla la aserción de cancelación. El test usa TestModel,
sin ReqLLM ni proveedor. Doce focales del fichero sin modificar pasan aislados:
el fallo de la ejecución async completa permanece en `minimum-suite/test.log`.

Un control privado conserva el mismo flujo y añade un Model válido de 150 ms.
La espera de 100 ms reproduce un fallo; con la barrera de 1.000 ms ya usada por
los tests vecinos, readiness tarda 152 ms y cancelación se observa en 0 ms.
La corrección sólo cambia esa espera/comentario del test; runtime, límites,
concurrencia y `DOWN` de 1.000 ms permanecen intactos. El fichero completo y el
control pasan en ambos runtimes: 13 casos por runtime, sin compiler warnings.

No se repite FULL por este cambio del oráculo, conforme a execution-flow; tampoco
se renombra como verde el recibo FULL 1.18 original. Logs: ownership-unmodified,
readiness-red y ownership-corrected118/120. El primer wrapper del control rojo
esperaba el exit 1 equivocado y sale 76; el log conserva el fallo ExUnit esperado.

Recibos privados bajo `.exagent-local/reqllm126/` y rutina en
`.exagent-local/checks/20261002T221011Z-2496792/`. La copia 1.18 conserva exactamente
las 92 fuentes lib/mix/lock de la raíz. La entrada G2 posterior se valida
separadamente en 1.20; el único test corregido tiene focal propia en ambos.
Probes externos usan la copia 1.20, con su propio build.
El readback de las 377 fuentes de FULL118/harness120 sólo encuentra dos deltas:
la espera de readiness del test y la entrada G2. Ambas tienen la evidencia focal
descrita; ninguna fuente lib/mix/lock difiere de la que ejecutó FULL.

## Límites y continuidad

No se cambia la identidad de CI run03/f69aede, artefactos anteriores, G2/E2E 1.24 o G4 cloud.
Langfuse/Opik conservan su aceptación nativa/API/UI previa: SDK/exporter/bridge
ExAgent no cambian, ni se conecta el puente OTel ReqLLM automáticamente. Los tests
nativos y de accounting se vuelven a ejecutar en FULL; no nueva ola cloud/UI.
MCP/frameworks/carga conservan sus recibos externos donde la frontera no cambia.
Las warnings estrictas upstream y publicación mantienen su estado abierto;
ningún pase offline declara soporte para familias/perfiles que siguen guarded.
