# Ownership de observabilidad — 2026-10-03

Encargo: explorar si la instrumentación ReqLLM permite simplificar la propia
antes de publicar. Evaluación sobre HEAD `a91840a83285bc8c7a4ab6691fcb88b6ef79ec75`,
ReqLLM1.26.0 stock, OTelAPI1.5/SDK1.7. No cambio de runtime/lock/SDK/exporter,
consumidores, versión, tag, merge o publicación. Sin revisión independiente nueva
ni repetición FULL/G2/G3/G4. La revisión R9 anterior permanece cerrada.

## Resultado

[Comparación completa](../../development/backend-evaluation.md#reqllm-and-exagent-instrumentation-ownership)
y [configuración de uso](../../guides/observability.md#reqllm-and-one-owner-for-request-spans).
Recomendación: ExAgent como único productor de spans para sus ejecuciones.
ReqLLM es suficiente para diagnóstico de peticiones standalone y aporta detalle
de cliente/métricas. No observa la ejecución del framework. Delegar sólo generación
puede ser útil; requiere ownership público y conservar identidad, aceptación
Model frente a éxito proveedor, uso cualificado, cancelación, privacidad y custom
Models. No se implementa otro modo ni se atribuye al usuario una decisión nueva.

## Pruebas

Entorno aislado físico Elixir1.20.0/OTP29.0.5; dotenv deshabilitado;
`EXAGENT_OFFLINE=1 MIX_ENV=test`, `--warnings-as-errors --seed 37556`.
Clave sintética, HTTP/SSE loopback y SDK nativo; sin proveedor o backend cloud.

| Ola | Resultado | Explicación |
|---|---|---|
| bridge-01 |0/4,exit2|Fixture usaba tag interno text_delta y asumía claves string/input GenAI siempre presente.|
| bridge-02 |2/4,exit2|Tags/claves corregidos; input GenAI tiene distinta disponibilidad sync/stream en este modelo dinámico.|
| bridge-03 |4/4,exit0|Matriz sync/public stream × ReqLLM attach off/on, expectativas ajustadas al contrato.|
| integration-01 |32/32,exit0,8.1s|Nueva matriz + OpenTelemetry + accounting projection; SDK/handlers restaurados.|

El check atraviesa APIs públicas/adapter/ReqLLM real y una respuesta válida fija.
Una petición HTTP en cada caso. ExAgent-only:run→model/2tokens output;
ambos:run→model→ReqLLM/4tokens si se suman generaciones. Resultado siempre
1request/0tools/3input/2output. Trace ID/parentage y ausencia de sentinels
prompt/output/clave verificados. No se deduce doble petición o cargo cloud.
No se cambian fuentes de biblioteca ni guards para pasar los nuevos controles.

Test SHA256 `802c96cee805c6efe06d63e87ebba8eaef559e8c80ec7cadd171917c689d9904`.
Logs y resumen privado en `.exagent-local/prepublish-20261003/`; resumen SHA256
`d65a2b92416a46e4b6886820b3bf43e241924a053cfd273a8f4256963eb6d8b7`.

## Documentación y paquete

Whitespace/formato0; ExDoc estricto0; enlaces0:
117HTML/5218targets,115Markdown/855targets,115EPUB/2884targets; errors=[];
build/isolation0. TAR SHA256
`19dfe27c3b6ff78cb3a494e3213f074b15a9f01eb0120d39f1d3cd8a97c1f2ab`.
168ficheros exactos del checkout; mismo metadata,90lib+mix.exs frente al TAR
E2E-COMPLEX. Sólo siete páginas cambian. Tests/evidencia/archivos privados fuera
del paquete. El lock coincide byte a byte con HEAD. Las pruebas nuevas no se
presentan como nueva suite completa ni como aceptación ReqLLM/híbrida en cloud.

Langfuse y Opik conservan la misma aceptación A10 del perfil ExAgent. Una
sustitución de productor/perfil necesitaría cualificar las fronteras afectadas
en ambos. Pendientes de publicación registrados en status: política strictdeps
upstream, versión/notas/tag y pipeline Hex autorizado por separado.
