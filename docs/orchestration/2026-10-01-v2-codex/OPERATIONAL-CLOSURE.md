# Dragonex y cierre operativo — 2026-10-03

El usuario solicita terminar los pendientes e integrar las aportaciones Dragonex
si son generales y compatibles. Se conserva ReqLLM oficial1.26, guards/C7 y R9
cerrada. Commit/push/PR autorizados; Hex/bump/tag/merge no autorizados.

## Resultado funcional

- OpenRouterChat explícito mantiene envelope obligatorio, capacidades veraces,
  routing acotado y presupuesto único. Disabled/none tienen binding estático antes
  del primer request; continuation4 liga historial/ruta/modo. Aprobación y primera
  petición incierta rechazan cambios antes del app codec/claim; OpenAI1–3 permanece.
- Session.StateCodec de host transforma JSON↔estado tipado sin código elegido por
  Store. Identidad/roster/policy/bindings se validan antes del decoder; fallos no
  silencian checkpoint no confirmado. Callback pureza y seguridad del dato son
  responsabilidades del host. La biblioteca no conoce World/Dragonex.
- Métricas por Adapter público único y API experimental0.6: cuatro instrumentos,
 1–32modelos allowlist/other, token input/output y error fijo; segundos/{token} y
  calidad normalizada. Sin IDs/endpoints/contenido, cache propia o SDK implícito.
  Reader/SDK/exporter reales de prueba verifican agregación, cardinalidad y restart.
- Default tracer consulta proveedor público vivo tras SDK restart. Una regresión
  reprodujo la pérdida de spans por cache y exige dos spans después de reemplazar
  el SDK. El host reemplaza sus tracers explícitos; no se toca persistent_term.
- Receta HTTP VM/batch llama callbacks stock publicados y elimina grupo OS/perfil/
  socket/átomos propios tras éxito/error/deadline/owner kill. HTTP2xx conserva
  aceptación de spans desconocida: stock descarta partial_success. Tres ciclos
  sanos, correlación, privacy, URL/headers y POST retenido cualificados localmente.
  gRPC conserva ocho controles,3ciclos y C7; no cambia a default de alto throughput.

## Evidencia y rojos preservados

Artefactos privados: `.exagent-local/closure20261003/`, sin credenciales en Git.
Primero2/10 rojos reprodujeron binding nil y decode antes de policy; corregidos.
El oráculo C7 se corrigió para usar un snapshot3 estructuralmente válido.
El primer child HTTP rechazaba símbolos nativos con safe ETF: el IPC HTTP propio
admite símbolos sólo en su VM efímera,65,536bytes; nunca storage/network ETF.
La URL específica del signal corrige doble suffix; fixture Chat completa incluye
total_tokens. Omitirlo reproduce normalized0 sin inventar accounting observado.
El primer entorno118 perdió su home Rebar aislado: corregido sólo localmente.
Luego17 fallos de spans detectaron cache SDK; regresión causal roja y arreglo público.
La primera rutina FULL fue detenida e invalidada por ese nuevo defecto, no aceptada.

193integrados120 antes del último arreglo;53afectados120 pasan después.
194integrados118 finales pasan,49.5s de tests/51.429s de comando.
gRPC publicado:8controles,3ciclos y C7 pasan,10.138s; recurso propio cerrado.
FULL120:2,235pases/0fallos/28exclusiones,2,001.6s (25.8async/1,975.8sync).
Bin/check2022.222s sale1 en ExDoc: enlace a callback encode/1 sin prefijo c:.
Se conserva el fallo; corregido sólo en prosa, las cuatro fases finales de docs/
enlaces/paquete/aislamiento pasan sin repetir la suite.
Cinco grafos instalados:32contratos none/API/SDK/exporter y6métricas pasan.
Sus diagnósticos tienen38warnings TOML/WebSockex por grafo y9gproc adicional en
exporter; todos los comandos de esos cuatro grafos salen0, agregado strict sale1.
El helper del quinto grafo se movió fuera de test para corregir un aviso1.20;
su fixture de seis casos es idéntica, run corregido0/6pases en0.939s.

## Artefacto final y fases

| Comprobación | Resultado |
|---|---|
| Whitespace/index/formato/harness |0 en la invocación original; harness seis subgates0 sin avisos |
| Suite completa1.20/29 |2,235pases/0fallos/28excl;2,001.6s |
| ExDoc original |1 por referencia function en vez de callback; no aceptada |
| Corrección causal de enlace |ExDoc estricto0 en2.601s; enlaces0 en0.322s |
| ExDoc con estado final |0 en2.490s; HTML/Markdown/EPUB |
| Enlaces finales |0 en0.316s;122HTML/5,453targets,120MD/907targets,120EPUB/3,018targets;0errores |
| TAR final |0 en0.450s;174archivos/94biblioteca, nominal1.3.0 |
| Aislamiento final |0 en22.409s; selectors/tooling/symlinks/diagnósticos, fake-host intacto |

TAR instalado por los cinco grafos:
`dedc62ab64de0a88fb62e7672d1fdec98b7255b705efb95030a62f60117023f5`.
TAR final:
`539d89becf4135c49c56599c9fa60ffc31a78103e0220e658cd1f0e125fdf5d2`.
Los174archivos coinciden con raíz/candidata. Desde el TAR cualificado sólo cambian
nueve documentos; los94lib y29otros inputs empaquetados (examples/Mix) son idénticos.
Los447inputs runtime/test/tooling/config/Mix/lock de FULL siguen idénticos a raíz.
No se atribuye al TAR final una instalación nueva de aquellos38contratos: se
reutiliza su runtime/contrato empaquetado idéntico y se cualifica la prosa final.

No hay una invocación nueva `bin/check` con9exits0: la original sale1 documental
y se conservan los cinco gates iniciales y cuatro fases finales aceptadas.
No se oculta ese exit ni se inicia otra suite por un cambio de enlace/estado.

## Límites que no desaparecen

API0.6 es experimental y necesita SDK/reader/destino del host. No certifica billing,
RAM, entrega ni ingestion métricas Langfuse/Opik. El A10 nativo/API/UI de ambos
conserva su identidad y criterios iguales; no hay nueva ola cloud/paid/SQL.
VM HTTP es baja cadencia,1–8spans/65,536bytes/1VM/Linux/deadline100–5000ms.
Ruta directa stock conserva fuga y aceptación partial desconocida. Native JSON
OpenRouter, reasoning no cualificado y MiMo no se habilitan por esta integración.

Consulta oficial fresh Hex confirma TOML0.7/WebSockex0.5.1/grpcbox0.18 y gproc1.3
excluido por ~>1.2.0. No release compatible elimina hoy sus warnings; diagnóstico
estricto permanece rojo. No fork/patch/override/supresión ni excepción de publicación.
Este bloqueo externo no se marca resuelto por pasar contratos funcionales.
Ver [límites](../../development/known-limits.md) y design8.53–8.54.
