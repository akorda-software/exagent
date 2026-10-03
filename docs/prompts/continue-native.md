# Continuar ExAgent v2 — entrada vigente

Este relevo acompaña la continuación autorizada; leerlo no amplía un encargo.
Usar herramientas/subagentes nativos para orquestación, sin cambios de configuración
global. La inspección del navegador Orca autenticado fue autorizada explícitamente
por el usuario para G4; no autoriza orquestación externa ni mutaciones Git.

1. Leer `AGENTS.md`, `docs/development/execution-flow.md` y
   `docs/orchestration/2026-10-01-v2-codex/CURRENT.md`.
2. Contrastar proyecto, padre, ownership y WIP; no reset/stash/clean, commits,
   publicación, bump ni consumidores. Un padre nuevo no continúa hijos del anterior.
3. Consultar roadmap§2 para el alcance pendiente; diseño2.1–2.3, status/changelog
   y sólo los contratos/fuentes pertinentes al objetivo. No reabrir R0/R1 ni Jido.
4. Estado2026-10-02: delegación10/Flow11, C7 entreVMs, MCP, framework recipes y
   cualificación común están implementados/verificados en sus perfiles. Revisión
   R9 única y UI Langfuse cerradas. El usuario amplió G4 para que Opik quede igual
   de validado: Opik nativo/API33/33 y UI12casos/248attrs aceptados; cerrar
   fuente/evidencia documental si sigue pendiente. Ver OPIK-ACCEPTANCE, sin repetir ondas nativas/API por
   fallos del navegador y manteniendo Langfuse sin reruns.
   Después, CI remoto exacto tras autorización Git. No reiniciar el encargo histórico
   de delegación ni repetir una unidad ya cerrada.
5. Un implementador con permisos causales, focales durante desarrollo y como máximo
   una revisión independiente del objetivo funcional. Corregir su lote con tests;
   no re-review ni repetir los mismos probes desde el padre.
6. Continuar routing/fan-out/fan-in, integraciones y cualificación según dependencias
   reales. No anunciar v2 completa sin su matriz ni prometer una fecha.

Baseline funcional: candidata019 nominal1.3.0,152archivos; FULL2157pases/28excluidos
sin fallos, exit1warnings conservado; fixturefix136focales exit0/0warns. G2mínimo14,
G3real14fases, package56runtimePASS/strictREDdeps, MCP5, frameworks6 yG6finito.
LangfuseAPI33/33 y UI12observaciones/248attrs/cinco capturas aceptados por agente
autorizado en la sesión del usuario. Las correcciones posteriores
incluyen documentación/soporte y dos fixes causales de receta opcional con
identidad propia. Opik suma dos olas fallidas y una cualificada33/33, cero paid;
no repetir G2 ni Langfuse. Los plazos/rojos tienen recibos propios.
Los informes históricos se consultan sólo para una duda concreta de contrato/evidencia.

Pruebas offline con el prefijo aislado de `docs/development/environment.md`,
`EXAGENT_OFFLINE=1 MIX_ENV=test` y un solo dueño del build. No providers pagados, SQL,
secretos ni reparación de Hex/global por este relevo. Preservar procesos ajenos.
