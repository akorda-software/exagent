# Relevo: evaluación del backend de observabilidad

Eres el coordinador de la siguiente unidad de ExAgent. Trabaja en
`/home/kukapu/dev/projects/exAgent`, habla en español y lee este documento COMPLETO
antes de asignar trabajo. Es un mandato para ejecutar una nueva sesión, no para
volver a redactar otro plan. Si recibiste un Dispatch de worker, cumple sólo tu
Task: este archivo no te autoriza a tomar el mando.

## 1. Objetivo y dato nuevo del usuario

Continuar la evaluación del backend y mejorar su integración con el paquete,
manteniendo ExAgent como framework general, provider-extensible y desacoplado del
panel elegido. **El usuario confirmó que ya tiene algunas instancias de Opik.**
Partir de ellas; no volver a preguntar si existe Opik ni asumir que empezamos de cero.
Todavía no conocemos ubicación, versiones, proyectos, acceso ni histórico a conservar.

Langfuse OSS era candidato provisional para una integración nueva, no una decisión.
Con Opik existente, conservarlo como punto de partida hasta demostrar una ventaja
relevante de cambiar. A calidad comparable se prefieren más funciones sin licencia
comercial; una ventaja demostrada puede justificar funciones avanzadas comerciales.
No preguntar otra vez esa preferencia ni confundirla con autorización de compra.

Resultado buscado: una ruta de observabilidad comprobada, comparación basada en
tareas reales y una decisión sustentada, o una aceptación parcial con los accesos
que faltan claramente delimitados. HTTP200, capturas bonitas o contar funciones
en una web no bastan para elegir.

## 2. Recuperar contexto vigente

Lee, en este orden:

1. `AGENTS.md` y `docs/README.md`.
2. `docs/status.md` y `docs/development/handoff.md`.
3. `docs/development/roadmap.md` y `docs/development/backend-evaluation.md`.
4. `docs/architecture/overview.md` y `docs/architecture/design.md`, especialmente
   2.1–2.3 y 8.6–8.9.
5. `docs/guides/observability.md`, `docs/guides/migration.md` y `docs/changelog.md`.
6. `docs/development/environment.md` y `docs/development/verification.md`.

El archivo bajo `docs/archive/2026-09-consolidation/` contiene historia cerrada,
no otra lista de tareas activas. Consultarlo sólo para evidencia concreta. No
reactivar C1–C5 o N01–N18 ni repetir toda la investigación del ecosistema.

Base de referencia, a contrastar con el checkout real:

- 619 tests correctos y28 excluidos en Elixir1.20/OTP29,1.18/OTP28 y1.17/OTP27
  durante el cierre nocturno, seed37556. La reorganización documental repitió
  el nativo:619/28, seed348677, snippets7/7 y consumidores24/24 runtime.
- El paquete conserva nominal1.2.0, con contratos incompatibles para una major
  posterior. No es una release1.x publicable.
- HEAD de referencia `c08125be71eada363d08ca463cc7df2ea7855e4a`; mucho WIP y
  untracked válido. No confundir lo no commiteado con código descartable.
- Instrumentación OTel neutral, SDK app-owned y processor acotado implementados.
  La aceptación local ya cruzó el exporter nativo y decodificó protobuf oficial.
- El exporter1.10 HTTP convierte booleanos en strings, ignora successful
  partial_success y puede retener perfiles/átomos/solicitudes después de timeout
  o shutdown. Cleanup de procesos ExAgent no demuestra cierre TCP remoto.
- El warning estricto gproc/OTP29 está separado de los contratos runtime que pasan.
  No ocultarlo mediante una allowlist o un upgrade sin motivo demostrado.

## 3. Orca obligatorio y autoridad nueva

**Carga la skill `orca-orchestration` antes de asignar trabajo.** Usa únicamente
Orca Tasks/Dispatch/workers, no otra red paralela de subagentes nativos. El usuario
autoriza **`openai/gpt-6-astra` para todos los workers**, incluidos investigación,
implementación, revisión y verificación. No aplicar por defecto el reparto GLM/Muse
de la skill ni cambiar el modelo/configuración global del coordinador.

Descubre desde el terminal actual:

```bash
orca status --json
orca worktree current --json
orca orchestration run-current --json
orca orchestration run-list --json
```

Inspecciona el Run pertinente con run-show, task-list, worker-list y check antes
de enlazarlo o crear uno para esta unidad. El Run nocturno `run_4315531152c9` terminó
16 Dispatches y sus15 workers están cerrados: es sólo un localizador histórico.
No reutilices esos handles, inventes IDs/capabilities, suplantes `--from` ni robes
autoridad a otro coordinador activo. Sin identidad/runtime válidos, registra el
bloqueo; no reinicies Orca para solucionarlo.

La CLI observada requiere crear Task y después worker; redescubrir si cambió:

```bash
orca orchestration task-create --run <run_id> --task-title "Resultado acotado" --spec "Objetivo, ownership, restricciones, aceptación y entrega" --json
orca orchestration worker-start --run <run_id> --task <task_id> --worktree path:/home/kukapu/dev/projects/exAgent --agent opencode --model openai/gpt-6-astra --json
orca orchestration check --run <run_id> --wait --timeout-ms 60000 --json
```

`worker-start --spec` y `worker-list --include-remote` no existían en esta versión;
OpenCode no admitía `--effort` en worker-start. No inventes flags: consulta ayuda
sólo ante incompatibilidad. Confirma modelo/progreso efectivo, no sólo input aceptado.

## 4. Primera oleada pequeña y ejecución

Empieza con **dos frentes independientes**, no una flota por cada subproblema:

1. **Opik existente y criterios:** inventario autorizado de instancias/proyectos,
   versiones, transportes y tareas de diagnóstico, inicialmente sin mutaciones.
   Pide sólo los datos que faltan: destino concreto, acceso de prueba y alcance
   de datos sintéticos/histórico. No pedir claves para escribirlas en documentos.
2. **Frontera local del paquete/transporte:** revisar los límites ya reproducidos
   del exporter y las APIs actuales. Valorar una corrección upstream/configuración
   soportada o extensión estrecha, con prueba local antes de efectos externos.
   No escribir otro cliente OTLP completo ni adoptar otra librería por moda.

Un owner único para `mix.exs`/`mix.lock`, otro para cada área de código; coordinador
para contratos/docs y gates de integración. No compilar fuentes que otro edita.
El segundo frente puede usar un TAR congelado y deps/builds realmente independientes.

Después de la investigación focal, implementar las mejoras justificadas y probar
el escenario común en un proyecto sintético autorizado de Opik. Usar principalmente:

- `test/support/native_otlp_scenario_probe.exs` y los tests de observabilidad;
- `examples/observability.exs` y `examples/framework_evals.exs`;
- el runner de consumidores TAR y sus controles de aislamiento.

Comparar con Langfuse sólo cuando exista un destino/acceso autorizado. No desplegar
una instancia oculta para completar la tabla. Si esa rama está bloqueada, cerrar
la caracterización útil de Opik y continuar mejoras locales; una hipótesis sobre
Langfuse no es una comparación ejecutada ni una justificación de migración.

## 5. Qué debe comprobar la evaluación

- Árbol e IDs por run/request/tool/delegación/compaction/checkpoint; ningún span
  por token y ninguna mezcla de callers.
- Retry correctivo, efecto antes del fallo, error posterior a hook, cancelación
  parcial y retry-save sin repetir modelos/tools.
- Uso/cache/coste por generación frente a subtotales inclusivos, unknown distinto
  de cero y ningún estimador adicional disparado por tracing.
- Contenido off; opt-in redactado antes del transporte. Sentinels introducidos y
  observados realmente en callbacks antes de afirmar que se omitieron del payload.
- Secretos fuera de attrs, baggage y opts de bootstrap; los objetos runtime ricos
  no se serializan como telemetría. No prometer sanitizar logs arbitrarios de terceros.
- Backend lento/caído, cola acotada, pérdidas observables y recursos poseídos
  recuperados; respuesta parcial OTLP y ACK durable no son callback exitoso.
- Recuperación de información en **API y UI**, pasos/tiempo para diagnosticar los
  fallos y funciones/licencias realmente utilizadas, con versiones fechadas.

Usa Context7 para APIs/configuración concretas actuales y contrasta el código de
la versión instalada cuando corresponda. Separa transporte, semántica de la UI y
migración de producto: prompts/datasets/scores/históricos no viajan por cambiar URL.

## 6. Límites y supervisión

Preservar todo WIP/untracked y el diseño general. Sin autorización expresa: ningún
commit, bump, push/PR, merge/reset/clean/stash, publish, despliegue, reinicio,
modificación global o cambio de Dragonex/WhoamAI. No tests LLM pagados, DB real,
borrado de históricos ni uso de datos de terceros por este mandato. Tener Opik
existente no autoriza modificar todas sus instancias o leer datos reales sin alcance.
Usar `apply_patch` para ediciones manuales.

El Hex compartido del host quedó incompatible por un incidente anterior. Leer
`docs/development/environment.md`, usar PATH directo y tooling temporal verificado.
No reparar globals ni hacer local.hex sobre entorno heredado. Dependencias/tooling
adicionales necesarios sólo de forma aislada en `/tmp/opencode`, origen comprobado.
Fijar sólo `MIX_HOME` no basta: comprobar `MIX_ARCHIVES`, el selector `MIX_EXS`
y el ejecutable `erl` efectivos dentro del hijo; un shim mise puede alterar el entorno.
Aplicar `systematic-debugging` ante fallos y `verification-before-completion`
antes de declarar una unidad corregida o aceptada.

Procesar correo FIFO, responder preguntas con `reply --id`, ACK cada lote después
de leerlo completo y procesar también lo que devuelve el ACK. Workers leen correo
en checkpoints y antes de worker_done; una entrega por Dispatch y después idle.
Revisiones finales con contexto fresco. Reutilizar sólo contexto útil y handles
vivos verificados; liberar recursos propios finalizados que no se reutilicen.

Si la auditoría de testing está activa en otro chat sobre el mismo worktree,
coordinar ownership y ventanas con su coordinador antes de escribir/compilar.
No tomar su Run. No crear un worktree de HEAD que pierda el WIP actual; una copia
congelada para lectura/consumo sí puede aislar una verificación independiente.

Mantén supervisión hasta cerrar unidades útiles, una pausa o un bloqueo real.
No terminar sólo diciendo que los workers trabajan. Sin acceso externo, registrar
el gate y avanzar lo local; no inventar pruebas externas. Sin trabajo viable
pendiente, cerrar explícitamente, sin prometer continuidad después del turno.

## 7. Entrega y continuidad

Actualizar `docs/development/backend-evaluation.md`, roadmap, status y guía;
si cambia contrato, diseño/changelog/migración con problema, alternativas, impacto
y verificación. Registrar comparación y decisiones en una tabla pequeña, no otro
diario interminable. Logs cerrados al archivo fechado, sin secretos/capabilities.

Entregar: instancias/versiones/alcance probado, criterios de decisión, datos
recuperados/perdidos, cambios del paquete, comandos/entornos/resultados, límites,
gates externos pendientes y estado Git/Orca. La recomendación puede ser conservar
Opik, cambiar o posponer: debe corresponder a la evidencia, no al candidato inicial.

**Primera acción:** leer las guías, recuperar autoridad/estado, concretar acceso a
la instancia Opik y empezar la oleada pequeña. No devolver sólo otra propuesta.
