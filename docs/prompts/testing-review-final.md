# Nota diferida: segunda revisión de testing del paquete

**Estado: preparada, no activa.** Usarla cuando el usuario confirme que el alcance
funcional del paquete está terminado y solicite su revisión final, antes de decidir
la publicación. Leer esta nota no inicia trabajo ni reabre la primera auditoría.
«Terminado» se refiere al alcance acordado, no a implementar todas las ideas futuras.

## Acuerdo que debe conservarse

La auditoría del 2026-09-10 quedó cerrada con mejoras y revisión independiente.
El desarrollo continúa con tests útiles de cada cambio. Nuestra responsabilidad
es comprobar ExAgent y sus garantías de integración; Req, gproc y las demás
dependencias tienen sus propios mantenedores y suites internas.

- No duplicar esas suites ni dedicar la revisión a conseguir cero warnings externos.
- Si una dependencia rompe una garantía de ExAgent, reproducir el efecto en nuestra
  frontera y valorar solución upstream, compatibilidad o limitación documentada.
- Separar éxito funcional, exclusiones y diagnósticos de compilación. Los warnings
  externos conservados no son por sí solos fallos funcionales ni motivos para
  prolongar indefinidamente una auditoría. Tampoco ocultar errores reales.
- No optimizar el número de tests; exigir observación de resultados, efectos,
  identidad y estado según el contrato protegido.

## Recuperar el contexto real

Leer AGENTS, `docs/README.md`, `docs/status.md`, diseño2.1–2.3 y las decisiones
posteriores, roadmap, migración, changelog, `docs/development/testing-audit.md`,
verification y environment. El inventario y registro de la primera auditoría están
en `docs/archive/2026-09-testing-{inventory,audit}.md`.

Comprobar HEAD, WIP, versión, dependencias, runtimes y comandos vigentes; no heredar
655/28 ni un TAR anterior como evidencia del paquete final. Preservar el trabajo
no commiteado y emplear artefactos congelados que lo incluyan si hace falta aislar.
Si se orquesta, cargar `orca-orchestration`, recuperar autoridad/estado y usar Orca
Tasks/Dispatch con `openai/gpt-6-astra`; nunca reutilizar handles cerrados.

## Revisión acotada a un resultado útil

1. **Delta desde la primera auditoría:** inventariar funcionalidades, contratos y
   pruebas cambiados o nuevos; señalar las áreas conservadas y la evidencia aún
   aplicable. No reejecutar el antiguo mandato como otra lista de features.
2. **Contratos propios:** revisar caminos de éxito/fallo, efectos y ausencia de
   replay, uso desconocido, hooks, permisos, lifecycle, persistencia y migración
   en las superficies realmente modificadas. Contrastar los puntos P2 anotados
   (Session/callbacks, retries por tool, restore, SDK tardío) con su estado final;
   no presuponer que sigan abiertos ni añadir casos nominales equivalentes.
3. **Paquete consumidor:** verificar un TAR del candidato real, manifiesto y
   documentación, dependencia opcional/orden de compilación y los grafos/runtimes
   pertinentes. Los tests del repositorio no sustituyen esta frontera.
4. **Coste del testing:** revisar fixtures, duplicados demostrados y probes acoplados
   a versiones. Distinguir regresiones permanentes de experimentos diagnósticos;
   justificar qué ejecutar habitualmente, ante cambios de integración o sólo en
   preparación de release. Antes de fusionar/retirar, identificar sustituto y
   comprobar que discrimina el mismo fallo; preservar oráculos independientes.
5. **Advertencias externas:** comprobar versiones actuales y si upstream resolvió
   Req/gproc. Registrar origen e impacto y una decisión razonada de seguimiento
   o compatibilidad. La funcionalidad y los diagnósticos strict se informan por
   separado, conservando exits reales y sin cambiar floors para fabricar un verde.
6. **Entrega:** corregir problemas de ExAgent justificados por evidencia y revisar
   independientemente los cambios. Dejar una aceptación del candidato, límites y
   siguientes acciones concretas; cerrar la revisión cuando alcance ese resultado.

Empezar por lectura y baseline apropiado. Mantener un owner de builds compartidos,
controles positivos/negativos y comandos offline según la guía. No instalar otra
plataforma de testing, repetir benchmarks completos o reconstruir todas las matrices
por inercia. Aceptación real de proveedor/DB/backend/consumidor requiere su alcance
autorizado; las fixtures sintéticas no la sustituyen. Commit, bump, publicación,
servicios, configuración global y cambios de consumidores conservan sus permisos
separados. Actualizar estado/roadmap con evidencia fechada, sin reescribir el pasado.
