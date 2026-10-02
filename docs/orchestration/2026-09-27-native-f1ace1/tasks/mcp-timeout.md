# Timeout MCP durante gate R6

Suite owner paso R6: dos veces993/994 con MCP.ClientTest140 EXIT timeout;
aislado3/3 y serial994/0/28. Fuente/test MCP no cambió, causa histórica desconocida.

Worker diagnóstico `ses_f1a5120ebffedlkDWUn22Rm9PD`, Astra low, sólo copia
privada /tmp/opencode/mcp-causal-f1a512. Report y proposed.patch leídos por padre.
La fixture controlled_client(timeout:50) comparte50ms initialize/request. Probe
barreado demuestra que respuesta initialize ya encolada, callback retenido100ms,
produce owner DOWN timeout antes de request. Mecanismo real de setup demostrado,
no se afirma cuál scheduler/GC/encoding consumió tiempo en ejecuciones históricas.

Propuesta sólo test: controlled_client() default5000 handshake, sys.get_state ready,
sys.replace_state timeout50, misma petición unanswered/real timer/assertions cleanup.
Sin cambiar API/runtime/timeout petición ni inyectar timer falso. Con mismo retardo
de handshake pasa; retardo callback request observa timer real/cleanup correcto.
Verificación privada:95fuentes compile,3probes,34tests; mutación cancelar timer
real hace fallar test en Task.await2000; revert producto+34verdes. No suite48 propia.
ROOT intacto, sin secretos/global/paid IO, cero procesos propios.

Padre aplicó la propuesta tras cesión del build ROOT. Runtime MCP intacto.
Verificación posterior junto con las correcciones R6 recuperadas:56focales verdes,
incluido MCP; suite habitual max_cases48 seed37556 warnings-as-errors:
1001/0/28,184.8s, exit0. Log en
`/tmp/opencode/exagent-blockers-f1a4bc/parent-full48.log`.
No atribuir el rojo histórico a un episodio concreto de scheduler/GC; el ajuste
separa setup y deadline de la operación realmente probada, conservando50ms.
