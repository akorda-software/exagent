# Unidad preparada: observabilidad de la v2

**Estado: preparada.** Activar sólo por encargo específico o como unidad R7 del
mandato `docs/prompts/implement-v2.md`. Leer este archivo no activa orquestación.
El antiguo prompt con H2/Orca obligatorio está archivado en
`docs/archive/2026-09-backend-evaluation-prompt.md`.

1. Leer AGENTS, estado, roadmap R7/R8, alcance y matriz de aceptación A10/G4.
2. Seguir `docs/development/backend-evaluation.md` y la guía de observabilidad.
3. Partir de Opik existente, confirmado por el usuario. Pedir únicamente destino,
   versión/proyecto y acceso sintético que aún falten. No leer históricos reales
   ni crear/reconfigurar servicios sin alcance autorizado.
4. Resolver primero el transporte y ownership con fixtures locales. Aceptar después
   datos recuperados por API/UI; HTTP200 no demuestra diagnóstico útil.
5. Ejercitar ReqLLM, delegación, uso desconocido/cache, errores, checkpoint y C7:
   pausa/reanudación correlacionadas sin mantener un span vivo durante la espera.
6. Mantener instrumentación opcional/app-owned, contenido off y redacción previa;
   no doble generación entre ReqLLM y ExAgent ni replay por fallo del exporter.
7. Comparar otro backend sólo ante carencias relevantes y acceso autorizado. Preferir
   más funcionalidad sin licencia comercial a calidad equivalente; no autoriza compras.
8. Registrar gates verificados/bloqueados en el único roadmap, versión exacta y
   límites en la guía. No iniciar otra auditoría de dependencias ni copiar un cliente OTLP.

La ejecución puede ser de un agente; delegación/orquestación sólo según autorización
vigente. C7 **sí pertenece** al nuevo alcance de v2. Preparar este plan no certifica
providers, DB, backend ni una release.
