# Estado actual y recapitulación

**Base revisada: cierre de consolidación del 2026-09-10.** El framework tiene una
base local ampliamente verificada. La aceptación de sistemas externos y la
publicación de la major siguen abiertas. La versión nominal del checkout es
**1.2.0**, pero contiene cambios incompatibles destinados a una major posterior.

## Qué hemos consolidado

| Área | Resultado vigente |
|---|---|
| Core y streaming | Un loop para sync, `stream_text` y stream público; resultado completo o RunError con progreso, historial y modelo conocidos. |
| Tools | Validación JSV antes de efectos, permisos sobre la tool efectiva, JSON portable, outcomes de batch y retries explícitos. Ecto valida el output final. |
| Delegación | Scope compartido, admisión atómica, autoridad de ancestros y contabilidad por identidad sin sumar dos veces los hijos. |
| Runtime y snapshots | Ownership y cancelación, checkpoint confirmado, estado dirty y retry sólo de save; snapshots v2 con lectura v1 validada y policy confiable. |
| Protocolos | Streaming/SSE y MCP con límites, fragmentación Unicode, terminales y cleanup comprobados localmente. |
| Observabilidad | OTel opcional y app-owned, contenido off, redacción previa, processor acotado; OTLP nativo realmente decodificado en loopback. |
| Aceptación | Consumidores de bytes TAR, tres runtimes, escenarios compuestos, secuencias con oráculos independientes, evals y medidas finitas. |

Durante la noche se añadieron **40 tests raíz**. Las correcciones de biblioteca
se centraron en compilar correctamente el processor con SDK opcional en Elixir
1.17 y 1.20. También se corrigieron supuestos de fixtures, dos snippets README y
el runner de aceptación: selectores Mix heredados, destinos con enlaces, warnings
por fase y colisión entre el grafo y su diagnóstico. No se presentan esas
correcciones de tooling como bugs del loop de agentes.

## Evidencia de la base

| Runtime | Compile forzado | Correctos | Fallos | Excluidos |
|---|---:|---:|---:|---:|
| Elixir 1.20.0 / OTP 29.0.5 | 73 fuentes | 619 | 0 | 28 |
| Elixir 1.18.4 / OTP 28.0 | 73 fuentes | 619 | 0 | 28 |
| Elixir 1.17.3 / OTP 27.3.4.17 | 73 fuentes | 619 | 0 | 28 |

Seed `37556`; warnings-as-errors para el proyecto. En los tres runtimes:
C0 **14/14** invariantes, snippets **7/7** y probe R3 aislado **1/1**. Los tests
excluidos son proveedores reales y Postgres, no aceptación implícita de esos sistemas.

- Paquete: **72/72 contratos runtime** en doce consumidores sin symlink al checkout.
  Once pasan también strict; el exporter/OTP29 conserva **exit 1** por nueve
  warnings de gproc. No quedan warnings propios de ExAgent en esos consumidores.
- OTLP compuesto: **68 spans en 11 POST** inspeccionados, con uso por request,
  jerarquía, cancelación, checkpoint, privacidad y aislamiento de contexto.
- Carga: **4.000 runs medidos correctos** y **12.200 spans locales** sin pérdida
  normal; la saturación separada admite 32 spans y descarta 610 de forma observable.
  Son medidas sintéticas con definiciones reutilizadas, no latencia de LLM ni SLO.
- N14 concluyó **sin optimización nueva**: la medición no identificó un hotspot
  causal que justificara alterar la base o retirar controles.

El [procedimiento de verificación](development/verification.md) mantiene los
comandos actuales. El registro completo está en
[la evidencia histórica de consolidación](https://github.com/akorda-software/exagent/blob/main/docs/archive/2026-09-consolidation/action-plan.md).
Los artefactos `/tmp/opencode/exagent-night-final-verification.*` y el TAR
`exagent-night-final-reviewed-preview.tar` pertenecen a esa aceptación anterior;
la reorganización documental produce un artefacto local distinto.

## Límites que no debemos perder de vista

1. **HTTP nativo OTel no certificado para una VM longeva:** el exporter 1.10.0
   conserva perfiles/átomos y puede dejar solicitudes TCP tras timeout/shutdown.
   Su callback exitoso ignora `partial_success` y convierte booleanos en strings.
   La [guía de observabilidad](guides/observability.md) delimita lo probado.
2. **Backend por elegir:** el usuario confirmó instancias de Opik existentes;
   faltan destinos, acceso e histórico. Partir de ellas y comparar la información
   recuperada en API/UI antes de justificar un cambio a Langfuse u otra opción.
3. **C8 externo abierto:** proveedores/modelos, Postgres, Dragonex y WhoamAI necesitan
   aceptación propia. Las fixtures de paquete no son esas aplicaciones.
4. **C7 condicionado:** aprobación diferida persistida no está implementada ni forma
   parte implícita de la base verificada. Snapshot no equivale a replay de efectos.
5. **Tooling del host:** un bootstrap nocturno sobrescribió accidentalmente el Hex
   compartido por heredar `MIX_ARCHIVES`. Se contuvo y corrigió el runner; la
   reparación del Hex compartido sigue pendiente de autorización. Los gates
   finales utilizaron tooling aislado. Véase [entorno](development/environment.md).

## Situación de trabajo

Todo sigue como WIP, incluidos los untracked, sobre HEAD
`c08125be71eada363d08ca463cc7df2ea7855e4a`. No se hizo commit, merge, bump, publicación,
despliegue ni modificación de consumidores. La ejecución Orca nocturna terminó:
16 Dispatches, 15 workers distintos cerrados; sus handles no se reutilizan.

La prioridad inmediata es mantener la documentación ordenada y después cerrar
[el plan de backend y paquete](development/roadmap.md), con sus gates explícitos.

## Reorganización documental verificada — 2026-09-10

Las guías vigentes, arquitectura, roadmap y relevo están ahora bajo `docs/`;
los cinco registros grandes de la ejecución anterior se conservaron en el archivo.
Se actualizaron las referencias, los lectores de snippets y el manifiesto.

- Suite nativa de esta unidad: **619 correctos, 28 excluidos**, seed `348677`.
  La matriz1.18/1.17 de arriba sigue siendo evidencia de la consolidación anterior;
  no se repitió ni se atribuye como nueva verificación de esta organización.
- Snippets: **7/7**, seed0; **120 enlaces locales** comprobados en20 Markdown.
- ExDoc y formato global pasan con los nuevos grupos/rutas; no hay colisión entre
  el README raíz y el índice documental.
- Preview con91 archivos: documentación vigente incluida, `docs/archive/` excluido.
  Los cuatro consumidores nativos pasan **24/24 contratos runtime**. None/API/SDK
  pasan strict; exporter mantiene el exit1 conocido por nueve warnings gproc.
- El control de aislamiento pasa con el nuevo manifiesto, sin instalar nada en
  esa comprobación ni modificar el tooling compartido.

Las salidas temporales están en `/tmp/opencode/exagent-docs-reorganized/` y
`/tmp/opencode/exagent-night-package-docs-reorganization/`. La versión y los
contratos runtime no cambiaron. El siguiente trabajo es confirmar el entorno
autorizado para la comparación de backend, siguiendo su plan específico.
