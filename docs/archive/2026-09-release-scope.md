# Alcance de la próxima major

> **Archivado el 2026-09-21.** Sustituido por el
> [alcance v2](../development/release-scope.md); la decisión posterior del usuario
> incluye C7 acotado. Este documento conserva el alcance H1 de su fecha.

**H1 — decisiones acordadas el 2026-09-16.** Base inspeccionada: `7f25b33`,
nominal1.3.0, checkout inicialmente limpio. El estado de los seis hitos se mantiene
únicamente en [roadmap](2026-09-release-roadmap.md); este documento fija su alcance de producto.

## Dirección y decisiones resueltas

1. **Paquete primero.** El usuario prioriza una buena trayectoria y mantenibilidad
   de ExAgent como biblioteca Hex general. Dragonex y WhoamAI se adaptarán después;
   no se investiga ni modifica su código para decidir esta salida. El inventario
   antiguo de migración es contexto histórico, no una especificación del framework.
2. **C7 pospuesto expresamente.** Esta versión conserva `allow/ask/deny` y el
   callback de aprobación síncrono. No promete una ejecución pendiente de aprobación
   recuperable después de reiniciar. El snapshot de conversación no reanuda IO.
3. **Cerrar lo implementado.** Completar integración, ergonomía y aceptación de
   las capacidades existentes; cambios de contrato sólo por problemas demostrados
   y con beneficio general, siguiendo diseño2.1–2.3.
4. **Publicación major.** La consolidación contiene rupturas documentadas. El número
    se fija al preparar H6; escribir este alcance no cambia1.3.0 ni publica nada.
5. **ReqLLM solicitado el 2026-09-21.** Integrar un backend principal de modelos,
   manteniendo el contrato de ejecución en ExAgent. Las apps actuales son pruebas
   de concepto; no condicionan la API futura. H3.0 ejecutará la adopción y retirada
   de duplicación con migración de contratos publicados. Véase [dirección](../development/framework-direction.md).

## Capacidades incluidas y frontera que debe aceptarse

| Capacidad de la versión | Contrato de partida | Aceptación pendiente |
|---|---|---|
| Definición de agente y loop | `run`, `stream_text` y `run_stream` comparten validación, hooks y límites; resultado válido o RunError con progreso conocido. | Proveedores reales H3 y ergonomía H4. |
| Tools y output | Argumentos/schema antes de efectos, outcomes distinguibles y Ecto como autoridad del output; JSON portable. | Casos representativos de proveedor H3 y consumidores H4. |
| Permisos, uso y coste | Tool efectiva, aprobación síncrona, autoridad de ancestros, admisión compartida y uso desconocido distinto de cero. | Uso/error reales H3; escenarios públicos H4. |
| Delegación y compaction | Scope compartido sin doble cómputo; proyección de request separada de historial canónico. | Composición en consumidores H4. |
| Server/Session | Owner de conversación/turnos, eventos, cola en memoria y coordinación; contratos de cancelación/errores explícitos. | Flujos públicos con estado y fallos H4. |
| Store y snapshots | Checkpoint confirmado, retry sólo de save, v2 y lectura v1 admitida; configuración confiable al restaurar. | Postgres real H3; restore de consumidores H4. |
| Model, MCP y extensibilidad | Behaviour Model y terminales tipados; MCP mantiene la frontera de validación Tool. | Adapters/gateways H3 y extensiones públicas H4. |
| Observabilidad | OTel opcional y app-owned, contenido off, redacción previa y recursos propios acotados. | Ruta operable y backend de referencia H2. |
| Distribución | Instalación mínima sin SQL/Phoenix/SDK forzados; documentación y migración públicas. | TAR consumidor H4, CI/candidata H5 y publicación H6. |

Estos contratos ya tienen implementación y evidencia local de la primera auditoría;
«incluido» no certifica todavía todas las integraciones externas. Los puntos P2
del [informe](../development/testing-audit.md) se contrastan al trabajar en su frontera, no como
otra auditoría general obligatoria. No hay que añadir APIs nuevas para llenar filas.

## Proveedores, modelos y runtimes

- `ExAgent.Model` permite structs de implementadores externos. El resolver actual
  reconoce OpenAI, Anthropic, OpenRouter, OpenCode, el alias Z.AI compatible con
  Anthropic y Test; la identidad del proveedor/gateway debe seguir siendo explícita.
- Los adapters de protocolo actuales son OpenAI Chat Completions y Anthropic
  Messages. Un wrapper o un flag de capacidades no demuestra que todo modelo de
  ese servicio soporte tools, streaming u output estructurado.
- H3 fijará un conjunto pequeño y representativo de modelos/versiones/operaciones
  antes de efectuar llamadas. La matriz publicada distinguirá implementado,
  aceptado en un modelo concreto, limitado y no verificado. No se promete cualquier
  endpoint «compatible». La solicitud posterior del2026-09-21 añade ReqLLM en H3.0;
  los adapters descritos arriba siguen siendo la implementación actual hasta que
  esa integración pase su aceptación.
- Conservar como base `elixir: "~> 1.17"`. Objetivos de cualificación del candidato:
 1.17/OTP27,1.18/OTP28 y1.20/OTP29, con versiones exactas registradas al ejecutar.
  La auditoría más reciente verificó1.17/27 y1.20/29;1.18/28 es evidencia anterior.
- La CI actual usa otras combinaciones1.17/25–26 y1.18/26–27, más harness1.20/29.
  H5 debe reconciliar cobertura, compatibilidad declarada y evidencia real antes
  de publicarlas como soportadas. Este inventario no valida esos jobs ni eleva
  un mínimo de OTP; cualquier cambio de compatibilidad se decide con evidencia.

## Consumidores de referencia

H4 usará aplicaciones mínimas instaladas desde un TAR identificado. Se partirá
de las fixtures `test/fixtures/package_acceptance/` y sus grafos opcionales:

| Perfil | Qué debe demostrar |
|---|---|
| Básico | Instalación, tools tipadas, output Ecto, streaming y errores sin infraestructura opcional. |
| Con estado | Server/Session, eventos, checkpoint y restore por APIs públicas. |
| Extensible | Model propio y composición sin perder estados, uso ni clasificación de errores. |
| Instrumentado | Configuración OTel de referencia, aislamiento y ausencia de dependencia obligatoria para el consumidor básico. |

Son perfiles de aceptación, no cuatro aplicaciones de producto nuevas. La suite
TAR actual aporta6contratos por grafo; H4 evaluará qué cubre y ampliará sólo lo que
falte. La migración de aplicaciones del usuario será posterior y tendrá su propia
revisión de fuentes, datos y aceptación; no se presenta aquí como ya compatible.

## Fuera de esta salida

- C7: aprobación diferida persistida; queda para una versión posterior.
- Motor de workflow/replay universal, exactly-once externo, rollback de IO,
  sandbox o nuevas modalidades/protocolos sin una necesidad general demostrada.
- Dependencia obligatoria de un backend de trazas, framework web o base de datos.
- Adaptación de Dragonex/WhoamAI u otras aplicaciones como condición de publicación.
- Duplicar testing interno upstream o perseguir cero warnings de dependencias.

Los warnings Req/gproc siguen registrados con menor prioridad. Una incompatibilidad
o defecto que afecte a una garantía de ExAgent sí requiere tratamiento en su frontera.
H2–H6 pueden corregir defectos y mejorar ergonomía; añadir una feature de las
excluidas requiere una nueva decisión de alcance, no una casilla tácita de este plan.

## Evidencia utilizada para H1

Revisión de `mix.exs`, `.github/workflows/ci.yml`, `ExAgent.Model`,
`ExAgent.Permissions`, arquitectura, migración y estado aceptado. Se contrastaron
el resolver y la aprobación síncrona con la implementación, y las combinaciones
de CI con los resultados fechados. El usuario resolvió las dos decisiones de
producto: C7 pospuesto y apps adaptadas después. No se han ejecutado proveedores,
DB ni consumidores reales para este inventario de alcance.
