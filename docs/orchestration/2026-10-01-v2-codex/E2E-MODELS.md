# Comparación E2E Luna / DeepSeek — 2026-10-03

Encargo explícito: sustituir Mini por GPT-6-Luna en las pruebas del consumidor,
añadir DeepSeek V4.1 Flash y cubrir caminos E2E que faltaban. Comparación cerrada:
los 23 escenarios se ejecutaron por modelo; **Luna acepta 23, DeepSeek 22**.
El caso 08 de DeepSeek permanece rojo y su perfil nativo completo no se acepta.
Sin bump, tag, merge, publicación Hex ni cambio de runtime/lock raíz.

## Perfil e implementación

- `openai/gpt-6-luna` y `deepseek/deepseek-v4.1-flash`, endpoint OpenRouter `/api/v1`.
  IDs y capacidades consultados en el catálogo oficial. El default E2E es Luna;
  IDs desconocidos y ledger de otro modelo rechazan antes de HTTP. Sin fallback.
- ReqLLM 1.26.0 oficial stock, OpenAI Chat, `chat_tools_v1`, `chat_json_schema_v1`,
  `reasoning_mode: :none`. El adaptador emite `reasoning_effort: "none"` y
  `max_completion_tokens: 512`. Descriptor del protocolo efectivo del gateway,
  no cualificación de las APIs nativas ni del razonamiento activado.
- Luna sin temperature/top_p; DeepSeek top_p 0.01 desde la ola05. Las fichas
  oficiales admiten parámetros de muestreo diferentes. No se relajan guards ni
  se añade parser, coerción, fork o código privado de transporte.
- Consumidor autorizado: `../exAgentTest/chat_app`. Nuevo `E2E.Profile`, admisión
  ligada al modelo y selección `--model`/`--cases`. Lock consumer actualizado al
  grafo stock compatible; modelos/clave del `.env` original conservados.
- Casos nuevos 19–23: deny sin efecto/retry; error exacto de herramienta sin replay;
  Server busy/abort y worker cerrado; presupuesto antes de otro Model IO;
  Composition+C7 con extracción/mapper únicos y aprobación duplicada inerte.
- Precommit final exit0: **17 offline pasan, cero fallos, 23 live excluidos**.
  El negativo de marcador rechaza el patrón real de código añadido y un marcador
  alterado; no cuenta como una prueba real adicional del modelo.

## Resultados y presupuesto

| Modelo | Casos ejecutados / aceptados | Requests de casos aceptados | Fase completa | Reserva de fase | Efectos sintéticos aceptados |
|---|---|---|---|---|---|
| Luna | 23 / 23 | 44 | 51 de 60 | USD1.275 de 1.50 | 15 |
| DeepSeek | 23 / 22 | 43 | 54 de 60 | USD1.35 de 1.50 | 15 |

La fase completa incluye todos los diagnósticos y fallos, sin reset ni refund.
105 admisiones totales / USD2.625 reservado; factura observada null. Reserva
operativa de USD0.025/request, no factura ni presupuesto impuesto por OpenRouter.
Entrada lógica 16KiB/10messages, salida 512 tokens, agente 4requests/3tools/4pasos,
retries HTTP/output/tools0. Dueño Linux finito 900s/4MiB, grupos propios cerrados
en las 16 olas, clave ausente de receipts y logs redactados. Fuentes inmutables
durante cada ola. El caso cancelado deja host_tool_calls null porque no existe
resultado público final; su inicio y cierre de worker se observan por separado.

| Modelo / ola | Resultado realmente ejecutado | Admisiones | Exit hijo | Fuente SHA256 (prefijo) |
|---|---|---|---|---|
| Luna01 | 23 pasan, ola completa | 44 | 0 | b75a94e01ab4 |
| Luna02 | 01 pasa, copia explícita | 1 | 0 | 6e440ae679c2 |
| Luna03 | 01/02 pasan, oráculo exacto | 2 | 0 | ffc97075a010 |
| Luna04 | 11/23 pasan, oráculo exacto | 4 | 0 | b65034ed95e0 |
| DeepSeek01 | 01 falla; resto sin ejecutar | 1 | 2 | b75a94e01ab4 |
| DeepSeek02 | 01 falla, diagnóstico | 1 | 2 | 70a07ed7673a |
| DeepSeek03 | 01 pasa / 02 falla | 2 | 2 | 6e440ae679c2 |
| DeepSeek04 | 02 pasa oráculo débil; falso positivo, no aceptado | 1 | 0 | 1b822db61083 |
| DeepSeek05 | 02 pasa con copia explícita/oráculo exacto/top_p | 1 | 0 | ffc97075a010 |
| DeepSeek06 | 01,03–07 pasan / 08 falla | 12 | 2 | ffc97075a010 |
| DeepSeek07 | 08 falla, diagnóstico sin cambio de prompt | 1 | 2 | b92afe7234af |
| DeepSeek08 | 09/10 pasan / 11 falla | 4 | 2 | b92afe7234af |
| DeepSeek09 | 12–22 pasan / 23 falla | 25 | 2 | b92afe7234af |
| DeepSeek10 | 11 falla por instrumentación del consumidor | 1 | 2 | c1897c998d71 |
| DeepSeek11 | 23 falla, diagnóstico del marcador | 1 | 2 | c1897c998d71 |
| DeepSeek12 | 11/23 pasan con copia explícita/oráculo exacto | 4 | 0 | b65034ed95e0 |

No declarar una nueva ola única 23/23 para DeepSeek. Los casos no afectados se
reutilizan con análisis de delta: lib/config/mix raíz inalterados; opciones Luna
sin cambios; DeepSeek05–12 usa el mismo muestreo; cambios posteriores sólo añaden
diagnósticos y endurecen cuatro caminos de marcador. Esos cuatro tienen su
control real específico. Los excluidos y casos abortados no se suman como pases.
Los receipts rojos conservan `cases_verified:false`; en DeepSeek06/08 también
`ledger_verified:false`: el runner exige al menos una admisión por caso seleccionado,
pero el fail-fast corta esas olas antes de ejecutar todos sus casos. No relabelar
esos indicadores como éxito. Los ledgers de
fase conservan las admisiones/ordinales/reservas previas al HTTP, y los casos
aceptados reconcilian su request_count público con su admisión independiente.

## Fallos observados y límites

1. DeepSeek02 devuelve texto `CHAT_# READY` con finish stop y cero bloques públicos
   reasoning_details en ese diagnóstico. DeepSeek04 genera código Java no pedido
   que contiene STREAM_READY; el substring antiguo lo aceptaba incorrectamente.
   La copia ASCII explícita y `String.trim(output) == expected` exigen el dato
   correcto. DeepSeek11 inserta un delimitador literal de thinking dentro de
   EXTRACT_READY; se conserva el texto diagnóstico, sin quitar tokens o repararlo.
   El control final pasa. Esto no demuestra determinismo ni ausencia universal
   de cómputo interno de razonamiento; los prompts/muestreo son parte del perfil.
2. DeepSeek08 se reproduce dos veces: el resultado Ecto de JSON nativo conserva
   total2.5 y fecha2026-10-02, pero merchant/currency son null. Schema válido no
   demuestra contenido fiel. El prompt/oráculo original se mantiene; no rellenar
   campos ni aceptar este escenario. Texto con output tool y PNG sí pasan en sus
   casos propios, sin certificar el caso nativo por analogía.
3. DeepSeek10 registra un fallo del diagnóstico añadido: el payload terminal
   PubSub contiene contadores acotados, no `messages`. La instrumentación asumió
   el resultado completo y lanzó KeyError. Se corrige pasando sólo output y
   mensajes vacíos al diagnóstico; API/runtime PubSub intactos. Receipt original
   conservado y control final real verde, sin ocultar ese intento.

Navegador JavaScript, reasoning activado, otros endpoints/proveedores, HA,
SQL entre VMs, fiabilidad estadística e invoice no se aceptan con esta matriz.
SQL/ACK tienen G3; G2 Mini, cloud Langfuse/Opik, carga y ocho consumidores TAR
conservan sus receipts propios. No se repiten por este delta. Sin nueva review
independiente; se respeta la revisión máxima única y R9 sigue cerrada.

## Identidad y evidencia

Baseline de biblioteca: `ceebb9e9d19d6afc72551a048c93aea0a97a70ed`.
94 archivos lib/config/mix.exs/mix.lock del checkout coinciden con la copia física
de cualificación. Lock raíz SHA256
`2637e0965ebdb015e04d505757bf0de5649affc35670ee77aa11745ecbbcdaeb`.
38 fuentes ejecutables/test/script/lock consumer coinciden con los bytes probados.
Sus cambios quedan en el WIP/untracked original; su commit no está autorizado.

Artefactos privados: `.exagent-local/luna-e2e20261003/`.
`summary.json` SHA256
`b069f5bba1f806c081e540096b10aeacc02cf97fe292e822dc53303a658d2290`.
Contiene cada caso aceptado, fuentes/receipts/logs por ola y reservas acumuladas.
`runtime-identity.json`, `final-precommit.log` y `source-sync.patch` conservan
comparación de bytes y verificación. Cada ola guarda source/admission/admissions/
cases/receipt; diagnósticos acotados sólo para los fixtures sintéticos.

El [guion de ejecución](../../development/real-consumer-e2e.md) describe IDs,
comandos, selección causal y alcance. Documentación nueva se valida por ExDoc,
enlaces y paquete local; sin repetir FULL ni publicar.

Verificación documental final: ExDoc estricto exit0 en2.441s;117HTML/5199targets,
115Markdown/844targets y115EPUB/2873targets, cero enlaces/anchors/recursos locales
rotos. Build Hex preview exit0 en0.556s; aislamiento exit0 en24.773s.
TAR168archivos exactos al checkout, metadata y91lib/Mix iguales al TAR cualificado
por los ocho consumidores; sólo siete documentos difieren de aquel artefacto.
Tests/archivos privados/orchestration/archive excluidos. SHA256 final
`adffca44289a30c167f9e329795a75dcd1c7e2def6c1030f5782df1cb7102acc`.
`documentation-receipt.json` y `final-tar-source.json` preservan fases y bytes.
