# Arquitectura actual

ExAgent es una definición reutilizable y un conjunto de capas opt-in. No exige
un proceso conversacional, una base de datos o un servicio de trazas para ejecutar
un agente. Los [principios y decisiones](design.md) explican el porqué de los
contratos; la [migración](../guides/migration.md) explica su impacto sobre 1.x.

## Capas y propietarios

| Capa | Responsabilidad | No garantiza por sí sola |
|---|---|---|
| `%ExAgent{}` | Configuración reutilizable: modelo, tools, output, límites, hooks e instrumentación opcional. | Estado mutable compartido entre runs. |
| Run | Loop modelo ⇄ tools, validación, progreso, resultado y uso. | Rollback o idempotencia de IO de aplicación. |
| ExecutionScope | Ancestry, admisión y reconciliación del árbol de delegación. | Control de llamadas que la app ejecute fuera del scope. |
| Server | Owner de conversación, historial/modelo entre solicitudes, cola y eventos. | Cola async durable o terminal después de morir su owner. |
| Session | Participantes, política de turnos y single-writer del estado compartido. | Workflow engine o replay universal. |
| Store | Checkpoints de conversación/coordinación y restauración validada. | Reanudar una tool en vuelo o deduplicar efectos externos. |

```text
Definición de agente
  └─ run / stream_text / run_stream → un loop canónico
       ├─ Model → adapters de protocolo → transporte HTTP acotado
       ├─ Tool → schema + permiso + ejecución + resultado JSON
       └─ run_child → mismo scope, autoridad y presupuesto de ancestros

Server → posee runs y conversación → Store opcional
Session → coordina participantes y transiciones → Store opcional

Event / telemetry / OpenTelemetry → canales distintos, con proyecciones explícitas
```

## Contratos que conectan las capas

- **Resultados:** éxito completo o `RunError` con causa y progreso conocido.
  Deltas son provisionales; el output final proviene del resultado validado.
- **Model:** `ExAgent.Model` es el behaviour de proveedor. Un stream termina con
  `{:response, response, final_model}` o error; EOF incompleto no es éxito.
  Se preservan helpers OpenAIChat usados por adapters de consumidores.
- **Tools:** se valida antes de efectos. El hook previo determina la tool y args
  efectivos, conservando identidad. Denegación, error de validación, fallo y efecto
  desconocido no son el mismo outcome. Sólo `ModelRetry` autoriza retry correctivo.
- **Uso:** admisión por árbol y reconciliación por identidad. Los totales de un
  padre son inclusivos; no se vuelven a sumar sus hijos. Coste desconocido no es cero.
- **Historial:** compaction produce una proyección para la request; no sustituye el
  historial canónico ni convierte una restauración en permiso para repetir efectos.
- **Persistencia:** con Store, el ACK positivo requiere save confirmado. Dirty
  bloquea nuevas mutaciones; `checkpoint/1` sólo reintenta guardar. Sólo not_found
  permite comenzar vacío; datos corruptos/futuros o policy/id incorrectos fallan.
- **Observabilidad:** la aplicación posee SDK/provider/exporter. Contenido off y
  redacción previa al transporte; trazas muestreadas no son un ledger de facturación.

Los mecanismos OTP poseen y limpian tareas/recursos del framework; no deshacen
IO externo. Para detalle y límites comprobados consulta
[estado](../status.md), [verificación](../development/verification.md) y
[observabilidad](../guides/observability.md).

## Extensibilidad

Model, Tool, Store, PubSub, Compaction y TurnPolicy son las fronteras de extensión.
Las particularidades de un producto se quedan en su aplicación. Se conservaron
los adapters actuales tras evaluar ReqLLM: no se reabre esa decisión por moda,
sino ante una integración acotada que demuestre menor responsabilidad sin pérdida
de contratos. Los flags de capacidades no prueban aceptación de cada modelo real.
