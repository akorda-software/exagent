# Opik A10 — aceptación nativa/API y comprobación UI

Estado2026-10-02: **transporte nativo, API y UI aceptados en el perfil A10**.
Langfuse y Opik pasan los mismos criterios: estados, correlación, reintentos,
uso, calidad/procedencia/unidades y privacidad. G4 ampliado queda cerrado en
ese perfil finito; la disponibilidad del backend o estabilidad del navegador
no forman parte de esta aceptación.

Revisión adicional027 pedida después por el usuario: tres contraejemplos offline
del arnés afectan cleanup de descendientes, rollback del constructor y la
exhaustividad del oráculo de privacidad. La comprobación anterior demuestra los
campos esperados, input/output vacíos y sentinels conocidos; no demuestra rechazo
de cualquier contenido extra en metadata o error_info. El oráculo corregido añade
esas fronteras con controles positivos y negativos. No se ha demostrado contenido
extra ni recursos abandonados en las olas aceptadas, ni se han repetido lecturas
cloud. Los recibos originales permanecen ligados a025; la corrección027 tiene
evidencia offline propia y no convierte esos recibos en ejecuciones de la derivada.

El usuario creó y autorizó una cuenta exclusiva de pruebas, incluida la creación
de proyectos y lectura de sus API keys. Se creó `exagent` en workspace `tehsuso`,
proyecto `01a0fbf6-7f3c-7005-bfe0-77e38d2a5d41`. La clave aportada por el usuario
se guarda sólo en un archivo privado0600; la configuración privada previa de
`akorda` y su histórico permanecen intactos. No se extraen cookies ni tokens de
sesión. No publicar credenciales ni incluirlas en el paquete o evidencia.

Fuente: candidata025 nominal1.3.0, TAR SHA256
`74298f109cb501b7e847dced1be8a4f16bd5ea015fe69da39835e656371400eb`,152miembros.
El delta distribuido ejecutable respecto a023 pertenece sólo a la receta
opcional: hook de proyección pública y IO binario/Latin1 del worker packet4.
Core y lock conservan la fuente cualificada previa. El arnés posterior y los
plazos Opik se identifican separadamente, sin atribuirlos a los bytes revisados.

Recibos bajo `/tmp/opencode/exagent-v2-codex-t6qgpstl/opik024/`:

- Preflight `langfuse-prepare-rz0ani4e/admission.json`, SHA
  `34eea4362c304e126fded1475d3aab5feb77f6ddbeaa77406c27ac5851568b6e`:
  33spans,12requests/6calls lógicas/4efectos sintéticos, cinco envíos loopback.
  ETF proyectado43,882/61,948; HTTP11,076/11,129/15,555/12,256/4,385bytes.
- Controles de oráculo `api-controls03.json`:717. Fronteras posteriores
  `opik-boundary-controls-xp4xa2o9/receipt.json`:29; ejecución de fuente/worker
  antes de claves y cleanup de lector dentro de1s. `packet4-control.json`:9;
  header29917 bloquea UTF8, siete tamaños Latin1 pasan, hijos cerrados.
- Única revisión independiente024:0P1/2P2, `review/REPORT.md` SHA
  `5da0c36462b7df94f333ee087e90f6e684b9e6f7eaf239e5c73f510f32affa3e`.
  El dueño corrige fuente realmente ejecutada y reserva de cleanup con controles
  causales. Sin re-review. Deltas de plazos posteriores fuera de esa revisión.
- Fallos cloud preservados: `opik-wave-abi3wejq/receipt.json` (HTTP500ms) y
  `opik-wave-tzx_7sk4/receipt.json` (HTTP1s). Cada ola se detuvo tras el primer
  lote8 sin ACK; no se reintentó. La primera lectura causal exacta encontró8
  rows coincidentes y0 en la otra traza. El segundo fallo registra timeout1.
  ACK perdido no implica ausencia de escritura ni autoriza éxito ficticio.
- Control causal loopback `collector-latency-control-wopj6bag/receipt.json`:
  respuesta demorada700ms falla con500ms y pasa con3s; no keys/cloud/pago.
- Ola cualificada `opik-wave-w7smi_fb/receipt.json`:5POST/33ACK, Collector
  accepted33/refused0/sent33/failed0, cinco VMs/grupos cerrados y cero logs de
  pérdida. Collector lifetime12,846ms, stop18ms. Identidad1GET/529bytes; lectura
  de las trazas4GET/2786ms, cuerpos863/23,673/859/32,191bytes. API33/33 y todos
  los667atributos nativos, recursos/tipos, padres/estados y12modelos/uso coinciden.

La ola final ejecuta el arnés sellado `sealed-opik-timeout04/admission.json`, SHA
`6bb111aa92678bada292d51e139e2e5a8c636550998bf77292da3b1d5d61ae13`.
Perfil finito: HTTP3s, RPC3.5s, VM5s, export20s, owner28s, Collector30s/stop2s;
API identidad3s + observaciones7s + cleanup1s por lector. Se conservan32spans
por traza,64KiB, batch8, concurrency1, dos trazas/cincoPOST, sin retry/queue.
El guard30s del launcher no se amplía. La igualdad de aceptación no afirma
igual latencia entre backends. Las tres olas cloud suman7intentos POST/49spans
enviados, incluyendo los fallos; sólo la última constituye aceptación33/33.
Cero requests de proveedores pagados. Sin nueva ejecución de Langfuse o G2.

La proyección app-owned utiliza el mapa del convertidor SDK público y el prefijo
`opik.metadata` documentado. Conserva IDs OTLP nativos y comprueba la biyección
UUIDv7 del backend, no aprende IDs del readback. Modelo `llm`; tools/runs con
contenido off se muestran `general`, operación/estado accesibles en metadata.
Se verifican todos los escalares y recursos, incluido booleano falso. No hay
codec/parser privado, parche upstream, contenido artificial ni coste/factura
inventados. Fuente pública fijada `ada1cc563fe3b4b19364014e5a0d4832ec5ffee2`;
no identifica el build Cloud en ejecución.

Trazas de la ola aceptada:

- [Flow18](https://www.comet.com/opik/tehsuso/projects/01a0fbf6-7f3c-7005-bfe0-77e38d2a5d41/logs?trace=01a0fc15-b00c-7886-bd90-77762fd8b659),
  OTLP `e3a638940e127f829a9b5df6df7a6eb4`.
- [Recovery15](https://www.comet.com/opik/tehsuso/projects/01a0fbf6-7f3c-7005-bfe0-77e38d2a5d41/logs?trace=01a0fc15-cb42-72ff-a573-84929c4a7868),
  OTLP `bb154c8ce17c043a9c0d6bd25315cdac`.

## Aceptación de la interfaz autenticada

Recibo `ui/ui-acceptance.json`, SHA256
`e0a9be73d2553b9164cd7a6163673bcc45e0e8e28c565e7fc305bda030e3e0f9`:
doce observaciones seleccionadas por sus IDs comprobados y248atributos nativos
cotejados contra líneas realmente renderizadas por CodeMirror. Se conservan
snapshots, selección URL, árboles completos de18/15spans y siete vistas reales
inspeccionadas: tres PNG y cuatro impresiones PDF del navegador. Los PDF se
renderizaron con PyMuPDF1.28.2 para inspección; no se reconstruyó la interfaz.

| Caso UI | Evidencia comprobada |
|---|---|
| Run pausado y reanudado | `paused`→`succeeded`, mismo run/record y nuevo attempt;32atributos por observación |
| Modelo con coste conocido | 29atributos:0.03cents, `estimated`/`estimator`, uso `reported`/`model` |
| Run de corrección fallido | 29atributos y error previsto |
| Checkpoint fallido y retry | 9/8atributos, estado/revisión/intento reales |
| Tool de corrección fallida y retry | 12/11atributos, error y reintento correlacionados |
| Tool de aprobación pendiente y reanudada | 12/12atributos, mismo logical tool call |
| Flow paralelo y router | 31/31atributos, seis requests en la rama paralela y una en router |

La privacidad se comprueba también en la UI: contenido desactivado, ningún
sentinel privado ni atributo `exagent.content.*`. Input/Output vacíos son el
resultado esperado de ese perfil. Los14/20tokens son sintéticos de TestModel;
el coste nativo estimado no constituye factura del backend. Tipos visuales
`general`/`llm` y UUIDv7 se corresponden con las identidades/operaciones nativas
verificadas por API y UI, sin forzar contenido artificial para cambiar el tipo.

La captura del usuario confirma los cuatro logs: la pareja aceptada y las dos
olas parciales anteriores. Por sí sola no acepta todos los estados. El agente
continuó sobre la pestaña autenticada usando selección y scroll normales. No
leyó cookies/tokens ni usó respuestas API como prueba visual. Cero nuevos
productores, Collector, modelos pagados o llamadas REST directas en esta fase.

**Limitación observada:** navegar/recargar produce intermitentemente `Network
Error`/`Failed to load the project`; algunas capturas Orca fallan con
`browser_error`. Los diagnósticos y la pestaña nueva sin sesión/imagen vacía se
conservan como fallos, no como evidencia positiva. Las vistas físicas recortan
algunos IDs largos y campos inferiores; sus valores exactos, incluido0.03cents,
se verifican en el DOM real renderizado y la URL seleccionada. El contador11 y
10.433s del recibo parcial05 sólo corresponde a sus dos casos Flow; Recovery y
las vistas tienen recibos separados. No certificar estabilidad de la interfaz
ni repetir productor/API por fallos del navegador. UI, ACK y API no prueban
retención durable, factura, C7 entre hosts ni latencia general.
