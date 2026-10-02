# Documentación para personas y agentes — 2026-10-02

Objetivo explícito del usuario: páginas de documentación útiles y cuidadas para
personas y agentes. Base Git70c4a0c; rama codex/v2-candidate-029 y PR1 existentes.
No nuevo objetivo runtime, consumidor, revisión independiente o publicación.

## Resultado

- Portada ExDoc con recorridos de aprendizaje/integración y capas opt-in.
- Diez guías: getting started, tools/output, models/limits, runtime/events,
  durability/approvals, coordination, testing, MCP, troubleshooting y agentes.
- Navegación de páginas y módulos por responsabilidad, búsqueda y teclas nativas.
  CSS/recursos locales, temas claro/oscuro y móvil. Guías públicas en inglés;
  mantenimiento en español. No nueva aplicación frontend o servicio externo.
- Estado actual conciso; cuerpo del estado anterior íntegro en el archivo,
  byte-idéntico al blob70c4a0c. Pendientes obsoletos de G4/CI corregidos, sin cambiar
  resultados históricos ni presentar strictdeps como verde.
- HTML/EPUB stock. ExDoc0.40.3 genera Markdown/llms; extensión pública de formatter
  reubica enlaces aplanados, preserva código y marca la candidata sin publicar.
  Referencias API nativas funcionan también en EPUB; pie enlaza llms.txt.
- `bin/check` añade docs-links. Este delta usa sus gates documentales; no se
  vuelve a ejecutar la rutina completa de33m44s ni aceptación paid/SQL/cloud.

## Verificación final

| Gate | Resultado y límite |
|---|---|
| Compile test estricto |4archivos recompilados, exit0/cero warnings; fuentes lib/lock intactas respecto a f69aede |
| Probe desde Markdown real |17casos PASS/0warnings;41selecciones:30bloques ejecutados y11setup parseados,5sustituciones de configuración/modelos declaradas |
| ExDoc estricto |exit0/cero warnings;116HTML/5135targets,114Markdown(incluido llms)/811targets y114XHTML EPUB/2837targets |
| Enlaces/recursos |0links/anchors/recursos locales rotos; no certifica destinos externos |
| Controles negativos |Anchor HTML inexistente, ruta Markdown fuera del sitio y CSS ausente producen exit1; copia restaurada exit0 |
| Navegador Chromium151.0.7922.34 |36vistas:1440claro/oscuro y390móvil, cero overflow, errores JS o HTTP; búsqueda `/`, resultado, CTA por teclado y sidebar móvil pasan |
| Delta final de referencias |Click API nativa y llms.txt pasan; llms distingue candidata v2 sin publicar de1.x |
| TAR leído |167archivos, todos byte-idénticos al checkout; páginas/assets/formatter presentes; archive/orchestration/test/privados fuera |
| Metadata empaquetada |Elixir1.18.4/OTP28.0 y1.20.0/OTP29.0.5 cargan Mix sin ExDoc en el code path, exit0/cero diagnostics |
| Aislamiento de tooling |CLI/selección de proyecto/archivos/symlinks/diagnóstico strict pasan; fake-host intacto |

SHA256 del TAR documental:
`be4b801946d776964746c2d2a11b21e6b15d0246cb1e745a7f872c4dd6f771bf`.
No es el TAR del CI run03 ni de la candidata029. Nominal1.3.0, sin bump/tag/Hex.
Cinco capturas locales inspeccionables; esta aceptación visual no acredita WCAG
formal, compatibilidad universal de navegador o disponibilidad de un hosting.

Recibos ignorados bajo `.exagent-local/`: docs-build.log, docs-compile.log,
docs-probe.log, docs-links.json, docs-link-controls.json, docs-browser.json,
docs-package-readback.json y docs-package-isolation.log. Preview en docs-v2/;
servidor local loopback43607. Claves privadas y tooling compartido no se modifican.

## Continuidad

Revisión crítica027 y final R9 siguen cerradas. Suites completas y cualificaciones
externas mantienen sus recibos previos, no se presentan como reruns de este delta.
G5strict upstream, versionado y publicación siguen abiertos. Antes de publicar,
actualizar los avisos de candidata, estado y source_ref al contrato/version/tag
elegidos; la extensión Markdown requiere el ExDoc dev-only declarado.
