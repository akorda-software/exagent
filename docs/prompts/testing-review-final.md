# Nota diferida: revisión de la candidata R9

**Método vigente2026-10-01:** `docs/development/execution-flow.md`. Como máximo una
revisión de esta frontera; no re-review de correcciones ni segunda auditoría de
capacidades aceptadas. Reutilizar su evidencia y concentrarse en integración,
distribución y delta no revisado. El antiguo título «segunda revisión» no añade ronda.

**Estado: preparada, no activa.** Usarla al alcanzar R9 bajo el mandato
`docs/prompts/implement-v2.md` activado, o por encargo específico del usuario,
antes de decidir la publicación. Leer esta nota no inicia trabajo ni reabre la primera auditoría.
«Terminado» se refiere al alcance acordado, no a implementar todas las ideas futuras.

Esta revisión corresponde a **R9.2** de `docs/development/roadmap.md`, sobre la
candidata R9.1. Consultar `docs/development/release-scope.md` y
`docs/development/production-acceptance.md`: **C7 está incluido** por decisión
expresa posterior. R8 verifica consumidores representativos; la adaptación de
Dragonex/WhoamAI no es requisito del release.

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
Usar orquestación nativa y los perfiles disponibles; no activar Orca ni cambiar
modelos por esta nota. Nunca continuar hijos de otro padre.

## Revisión acotada a un resultado útil

1. **Delta desde la primera auditoría:** inventariar funcionalidades, contratos y
   pruebas cambiados o nuevos; señalar las áreas conservadas y la evidencia aún
   aplicable. No reejecutar el antiguo mandato como otra lista de features.
2. **Contratos propios:** revisar caminos de éxito/fallo, efectos y ausencia de
   replay, uso desconocido, hooks, permisos, lifecycle, persistencia y migración
   en las superficies realmente modificadas. Contrastar los puntos P2 anotados
   (Session/callbacks, retries por tool, restore, SDK tardío) con su estado final;
   no presuponer que sigan abiertos ni añadir casos nominales equivalentes.
   Incluir la frontera ReqLLM, negociación de contenido/output, CAS/claim, aprobación
   sobre argumentos exactos, resume con autoridad vigente, efectos inciertos y
   composición pausada. No sustituir la prueba de reinicio por lectura del mismo PID.
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
6. **Entrega:** una revisión independiente del delta de candidata no revisado.
   El implementador corrige su lote y prueba reproducciones/regresiones pertinentes,
   sin otra ronda independiente. Registrar límites y pendientes; no aceptar si
   permanecen bloqueantes ni convertir el cierre en una nueva auditoría.

Empezar por lectura y baseline apropiado. Mantener un owner de builds compartidos,
controles positivos/negativos y comandos offline según la guía. No instalar otra
plataforma de testing, repetir benchmarks completos o reconstruir todas las matrices
por inercia. Aceptación real de proveedor/DB/backend/consumidor requiere su alcance
autorizado; las fixtures sintéticas no la sustituyen. Commit, bump, publicación,
servicios, configuración global y cambios de consumidores conservan sus permisos
separados. Actualizar estado/roadmap con evidencia fechada, sin reescribir el pasado.
