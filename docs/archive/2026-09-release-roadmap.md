# Hoja de ruta: salida a producción de ExAgent

> **Archivado el 2026-09-21.** Plan H1–H6 sustituido por el
> [roadmap v2](../development/roadmap.md). Conserva evidencia y decisiones de su
> fecha, incluido C7 entonces diferido; no es un mandato activo.

**Plan H1–H6, acordado el 2026-09-16.** Esta página es la fuente única del estado
de los hitos. [Estado](../status.md) conserva la aceptación técnica; el
[alcance de la versión](2026-09-release-scope.md) recoge las decisiones de producto.

**Dirección del usuario:** construir un paquete Hex general, coherente y mantenible
a largo plazo. Dragonex y WhoamAI se adaptarán después a ExAgent; sus estructuras
actuales no condicionan esta versión ni bloquean su salida. **C7 queda pospuesto.**

**Aclaración 2026-09-21:** el usuario prioriza su base general para futuras apps y
solicita integrar ReqLLM. La [dirección recomendada](../development/framework-direction.md) es
ExAgent propio sobre ReqLLM, aprovechando patrones externos sin adoptar otro runtime.
La prioridad local pasa a **H3.0**: integrar la frontera de modelos antes de ampliar
features o cerrar la instrumentación de generación. Implementación pendiente.

## Tablero y orden de ejecución

| Hito | Resultado | Estado | Dependencia para cerrar | Evidencia o siguiente paso |
|---|---|---|---|---|
| H1 | Alcance, contratos y política de compatibilidad definidos | **Cerrado — 2026-09-16** | Base actual y decisiones del usuario | [Alcance](2026-09-release-scope.md) contrastado y documentación verificada; evidencia al final de esta página. |
| H2 | Observabilidad utilizable de extremo a extremo | Pendiente | H1; H3.0 para cerrar generación sobre ReqLLM | Ruta de transporte y backend; evitar duplicar spans con la nueva frontera. |
| H3 | Proveedores y persistencia reales aceptados | Pendiente; H3.0 siguiente | H1; integración ReqLLM y entorno real de prueba | Adapter común y contratos primero; matriz real y Store Postgres después. |
| H4 | Paquete validado en consumidores representativos | Pendiente | H1 y resultados H2/H3 pertinentes | Aplicaciones mínimas independientes instalando el TAR, sin adaptar aplicaciones del usuario. |
| H5 | Experiencia pública, compatibilidad y candidata pulidas | Pendiente | H2–H4 | Guías finales, CI real y paquete candidato reproducible. |
| H6 | Revisión final y publicación de la major | Pendiente | H1–H5; publicación autorizada | Revisión del delta, candidato aceptado y publicación explícita. |

Ruta principal: **H1 → H2/H3 → H4 → H5 → H6**. H2 y H3 son independientes tras
definir el alcance; la preparación de consumidores y guías puede avanzar sin
esperar a todos sus resultados. Un bloqueo externo no impide trabajo local útil.
Se cierra cada hito por evidencia de su resultado, no por iniciar tareas ni por
sumar tests. Preparar este plan no certifica producción ni publica el paquete.

La actualización del 2026-09-21 añade H3.0 dentro de H3. La investigación de
transporte/backend H2 puede continuar en paralelo, pero su aceptación de spans
de generación debe incluir el adapter finalmente adoptado.

## H1. Alcance y contratos de la versión

**Objetivo:** saber qué vamos a entregar, qué garantías asumimos y qué queda fuera.

- [x] Recuperar base real: `7f25b33`, nominal1.3.0, árbol limpio al comenzar el plan.
- [x] Contrastar capas/contratos implementados, adapters, permisos, manifiesto y CI.
- [x] Acordar con el usuario C7 diferido y diseño del paquete independiente de sus apps.
- [x] Definir alcance, límites, objetivos de compatibilidad y consumidores genéricos.
- [x] Verificar el conjunto documental y registrar el cierre del hito.

**Cierre:** [alcance](2026-09-release-scope.md) coherente con diseño y código, decisiones
de producto resueltas, siguientes aceptaciones asignadas a H2–H6 y documentación
comprobada. Se fijan objetivos y contratos de partida, no se anticipa el resultado
de las pruebas externas. Un defecto posterior puede justificar un cambio documentado.

## H2. Observabilidad utilizable en producción

**Objetivo:** una configuración OTel opcional, reproducible y operable, sin acoplar
ExAgent a una plataforma ni hacer que el backend afecte indebidamente al agente.

- [ ] Elegir una ruta de transporte/ownership que resuelva o delimite con evidencia
  los problemas funcionales conocidos del HTTP nativo; preferir componentes existentes.
- [ ] Verificar tipos, jerarquía, uso/coste, privacidad, caída/lentitud y recuperación
  de recursos desde la frontera de ExAgent, con procesos y datos sintéticos acotados.
- [ ] Concretar instancia, versión y acceso al entorno Opik existente; comprobar
  información recuperada en API/UI. Comparar alternativas si hay carencias relevantes.
- [ ] Dejar receta recomendada, configuración mínima y límites de operación.

**Cierre:** resultado extremo a extremo demostrado en un backend de referencia,
comportamiento de fallos/cleanup registrado y guía utilizable por cualquier
consumidor. No basta HTTP200 ni el contador de callbacks `exported`.
Detalle técnico: [aceptación del backend](../development/backend-evaluation.md).

**Siguiente paso local:** contrastar las rutas/configuraciones disponibles con los
límites ya reproducidos y seleccionar una prueba finita. El acceso al backend
sólo bloquea esa aceptación externa, no la investigación/configuración local.

## H3. Proveedores y persistencia reales

**Objetivo:** distinguir adapters implementados de combinaciones realmente aceptadas.

### H3.0. Integrar ReqLLM como backend principal — pendiente, siguiente

- [ ] Resolver dependencia y toolchain en entorno aislado; usar1.24.0 como referencia
  examinada y registrar la versión/lock efectivamente cualificados.
- [ ] Implementar un adapter Model común para sync/stream, mensajes, tools, output,
  opciones, errores y uso, siguiendo las fronteras de [dirección](../development/framework-direction.md).
- [ ] Resolver uso ausente frente a cero, límites de stream y datos de continuación
  con APIs públicas/extensiones acotadas; documentar cualquier cambio de contrato.
- [ ] Verificar loop, delegación, permisos, compaction, Server/Session, checkpoints
  y ownership/cancelación mediante las regresiones y consumidores pertinentes.
- [ ] Retirar transporte/adapters duplicados del candidato cuando exista sustitución
  aceptada; documentar migración de helpers públicos y excepciones justificadas.

**Cierre H3.0:** ReqLLM realmente utilizado en las rutas aceptadas, integración
verificada, menor responsabilidad propia y un contrato coherente. Añadir una
dependencia o pasar un hello-world no cierra esta unidad. La aceptación real de
proveedores/DB siguiente sigue siendo necesaria.

### H3.1. Aceptación externa

- [ ] Fijar modelos, endpoints, versiones y presupuesto de una matriz pequeña por
  protocolo soportado; añadir gateways cuando se declare su compatibilidad real.
- [ ] Verificar texto, tools, streaming y output Ecto donde correspondan; errores,
  límites y uso desconocido con efectos observados, sin repetir efectos por fallo final.
- [ ] Aceptar Store Postgres en una base de prueba: save/load/restore, errores y
  recuperación, junto a los lectores de snapshots soportados.
- [ ] Publicar matriz de capacidades aceptadas, limitaciones y combinaciones no verificadas.

**Cierre:** evidencia de proveedores y DB reales, versiones/alcance reproducibles y
regresiones de ExAgent corregidas. Una exclusión offline ni un flag ModelProfile
equivalen a aceptación. Llamadas pagadas y DB requieren su alcance autorizado.

## H4. Consumidores representativos del paquete

**Objetivo:** comprobar ergonomía y contratos públicos con instalaciones reales del
TAR, sin diseñar para un dominio de aplicación. Reutilizar las fixtures existentes
cuando cubran la frontera; ampliar sólo ante un hueco demostrado.

- [ ] Consumidor básico: instalación mínima, tools, output Ecto y streaming.
- [ ] Consumidor con estado: Server/Session, eventos, checkpoints y restauración
  por APIs públicas, con errores y ausencia de replay observados.
- [ ] Consumidor extensible: Model propio y contratos de uso/errores; integración
  opcional de Store/PubSub cuando se ejerza esa extensión.
- [ ] Verificar grafos none/API/SDK/exporter y configuración de H2; garantizar que
  una aplicación básica no necesita SQL, Phoenix o una plataforma de trazas.

**Cierre:** aplicaciones mínimas independientes usan la misma candidata y sus
flujos están comprobados sin rutas al checkout ni APIs privadas. Fricciones resueltas
en la API general o explicadas en la guía. La adaptación posterior de Dragonex,
WhoamAI y otras apps es una unidad separada; no es condición para cerrar H4.

## H5. Pulido público y candidata de release

**Objetivo:** que un usuario externo pueda instalar y mantener el paquete con la
documentación publicada, sin depender del contexto de este proyecto.

- [ ] Quickstart breve, ejemplos completos y configuración/errores comprensibles.
- [ ] Guía de migración revisada contra los contratos finales y versiones soportadas.
- [ ] Reconciliar matriz de CI, runtimes declarados y combinaciones verificadas;
  ejecutar CI real del candidato y hacer portable el gate de consumidores necesario.
- [ ] Revisar manifiesto, archivos, dependencias opcionales y resolución desde un
  consumidor limpio; guardar revisión, lock, hashes y diagnóstico por fase.
- [ ] Revalidar los consumidores afectados de H4 sobre el artefacto final y fijar
  el candidato (commit/artefacto identificado) que pasará a H6.

**Cierre:** candidata reproducible, documentación y CI verificadas, sin defectos
propios bloqueantes conocidos; advertencias externas clasificadas por origen e
impacto. El objetivo no es cero warnings en todos los internals upstream.

## H6. Segunda revisión y publicación

**Objetivo:** aceptar y publicar una versión coherente con límites explícitos.

- [ ] Ejecutar la nota `docs/prompts/testing-review-final.md` sobre el delta desde
  la auditoría cerrada y el candidato H5, con revisión independiente de cambios.
- [ ] Resolver hallazgos bloqueantes y revalidar únicamente fronteras afectadas,
  conservando el cierre integrado del candidato que efectivamente se publique.
- [ ] Completar changelog, migración, compatibilidad y decisión de versión major.
- [ ] Con autorización expresa, preparar versión/tag/publicación y comprobar que
  la instalación del artefacto publicado corresponde a lo aceptado.

**Cierre:** revisión final aceptada y versión publicada verificable. Se puede estar
«lista para publicar» con el último paso pendiente de autorización; no se declara
H6 completado sólo por construir un TAR local. C7 y funcionalidades futuras no
se añaden para completar este hito.

## Reglas de seguimiento

- Estados: **pendiente**, **en curso**, **bloqueado** (con dependencia concreta),
  **cerrado** (con evidencia). Registrar aquí fecha, resultado, siguiente acción y
  enlaces; guardar logs largos en el archivo, sin otra hoja de ruta paralela.
- Cada unidad deja problema/objetivo, decisión, cambios, verificaciones y límites.
  Revisar primero lo existente; añadir pruebas por riesgo del cambio. El código
  de dominio queda en consumidores y las extensiones tienen contratos pequeños.
- Un hallazgo nuevo se asigna al hito que protege su contrato. Si altera el alcance
  acordado, documentar decisión y migración; no crecer por abstracciones especulativas.
- La auditoría inicial y N01–N18 están cerrados. Probar ExAgent y su integración,
  no rehacer suites de dependencias. Req/gproc son seguimiento de menor prioridad;
  los problemas funcionales de transporte sí se tratan en H2.
- Usar el entorno aislado mientras la reparación del Hex compartido siga pendiente.
  Git, publicación, consumidores y servicios conservan las condiciones de AGENTS.

## Registro de avance

| Fecha | Hito | Trabajo y evidencia | Próximo paso |
|---|---|---|---|
| 2026-09-16 | H1 cerrado | Base `7f25b33` inspeccionada; C7 pospuesto y paquete independiente de apps por decisión del usuario. Alcance contrastado;150enlaces/27Markdown, snippets7/7 seed0, ExDoc, formato Mix y preview94archivos verificados. | Empezar H2 por la ruta de transporte; concretar acceso sólo para su fase de backend. |
| 2026-09-21 | Evaluación estratégica; sin cierre de hito | [Comparativa Jido](../development/jido-comparison.md): Jido2.3.1/AI2.3.0, fuentes versionadas y dos comprobaciones aisladas del contador de cuotas. Solapamiento funcional alto, diferencias en admisión por árbol, persistencia y efectos; sin aceptación integrada de Jido/proveedores. | Decidir con el usuario una prueba finita de adopción Jido/ReqLLM frente a ExAgent enfocado antes de ampliar capacidades. Recomendación pendiente; H1–H6 conservan su estado. |
| 2026-09-21 | Dirección aclarada; H3.0 priorizado | El usuario solicita ReqLLM y elimina el peso de las apps actuales en la decisión. [Valoración ampliada](../development/framework-direction.md): Jido/LangChain/Nous/Ash AI y frontera ReqLLM1.24.0 inspeccionados; se recomienda ExAgent propio sobre un adapter común. Documentación:171enlaces/29Markdown, formato Mix, ExDoc y diff check correctos. Sin implementación ni aceptación runtime nueva. | Ejecutar H3.0; conservar H2–H6 y C7 diferido. Contratos finales y retirada del transporte propio requieren evidencia. |

Verificación documental de H1 (exit0, entorno aislado según la guía):

```text
python3 /tmp/opencode/exagent-release-doc-check.py
mix format --check-formatted mix.exs
elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs
mix docs --warnings-as-errors --output /tmp/opencode/exagent-release-plan-docs
mix hex.build --output /tmp/opencode/exagent-release-plan-preview.tar
python3 /tmp/opencode/exagent-release-doc-check.py /tmp/opencode/exagent-release-plan-preview.tar
git diff --check
```

ExDoc con MIX_ENV=dev; preview con MIX_ENV=test; offline en ambos. El preview
incluye `release-scope.md`, excluye prompts/archivo y sus94miembros coinciden con
el checkout. El tooling aislado se recompiló desde Hex2.5.1 para OTP29 después de
confirmar que la copia compartida no cargaba; no se reparó el entorno global.
Los paths temporales son artefactos de ejecución, no requisitos del consumidor.

La evidencia técnica de partida sigue en [estado](../status.md): auditoría655/28
en dos runtimes y TAR24/24runtime, con strict externo separado. Son resultados
fechados de la base anterior, no pases anticipados del futuro candidato H5/H6.
