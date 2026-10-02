# ExAgent v2 — continuación nativa

## PAUSA EXPLÍCITA DEL USUARIO — prevalece sobre el historial inferior
- Usuario pide parar implementación y revisar eficiencia/cuota/orquestación.
- NO lanzar workers/reviewers/tests ni nuevas unidades sin acuerdo posterior.
- Ningún hijo ni check propio activo. Último reviewer exhaustion terminó/liberó.
- Último REPORT46f134395da2e096a43d83f3ea5ed601e26b9354788f367e2f0052ab33beefa9
  leído/cotejado; padre7/7fuentes y rerun7pass/54.0s/exit0 (mismos4+3review) en
  /tmp/opencode/exhaustion10-parent-q2xfd2m9/. Evidencia interna favorable; no producto.
- No nueva implementación despachada tras ese rerun. WIP preservado sin commit.
- Diagnóstico de método y propuesta: tasks/orchestration-efficiency-pause.md.
- Este CURRENT acumuló495líneas antespausa: resumen NOdepurado, estadosACTIVO viejos
  inferiores son históricos y NO reflejan propiedad vigente. Compactación pendiente.

## Proyecto, autorización y ownership
- ROOT `/home/kukapu/dev/projects/exAgent`; padre `ses_f190856acffeP1Xq65aTlOgwFx`.
- HEAD7f25b336924d97baf1d4aa18898ec8db32385940, WIP amplio preservado; nada committed.
- Handoff usuario `docs/prompts/continue-native-2026-09-28.md` leído íntegro; ejecución
  nativa sin Orca. Usuario autoriza paralelismo independiente, no infra/publicación.
- Usuario reafirma continuar y objetivo v2 semana siguiente; no fecha garantizada ni
  promesa de ejecución autónoma fuera runtime. Comunicar capacidades/riesgos, no jerga.
- ReqLLM stock; sin fork/vendor/parser privado ReqLLM/Jido. Sin paid/SQL/global/
  consumidores/commit/push/bump/publicación. Secretos nunca en artefactos.
- No tocar BEAM ajenos3339/2963360/4019033. ROOT build exclusivo worker Frame9 abajo.
- Padre único escritor memoria; receipt docs terminado/liberado. Un build owner
  por árbol. No compilar fuentes/deps compartidas concurrentemente.
- Perfiles especializados fallaron Agent not found; usamos general con rol explícito.
- Prefijo `docs/development/environment.md`, EXAGENT_OFFLINE=1 MIX_ENV=test,
  MIX_BUILD_PATH absoluto ROOT `_build/test`, WA48seed37556 timeout≥600000.

## Frentes activos (no duplicar ni consultar progreso)
- Receipt documental `ses_f1764b8b8ffeFmJQ76mYXbw2AC` TERMINADO/ACEPTADO: padre
  leyó diff4docs, cotejó4hashes/REPORTf19314cd y diffcheck0. Docs libres.
- Researcher R6 `ses_f17647cb9ffe43JupmF1SYBPc6` TERMINADO; padre contrastó código.
  Autoriza subset final+control Frame8 (prefix→text/output y currentbatch sin replay),
  consumidor específico/counters/autoridad; mandato completo `tasks/next-r6-frame8.md`.
  Intención worker fresco exclusivo ROOT/build/docs4, padre status/memoria.
- Worker R6 `ses_f17600f05ffefYLYFRRlGSOR6x` TERMINADO: REPORT74024782 en
  /tmp/opencode/r6-tools-f17600f0/ leído/cotejado, source12/12 padre OK.
  FULL1568/28/716.8s exit0 cotejado tras fix causal test-only MCP;37focalMCP/formato/
  diff0, compile107 y261R6 anteriores runtime intacto.12paths delta/históricos intactos.
  ROOT/build libre; recepción de review y aceptación abajo.
  Mandato completo/historia tasks/next-r6-frame8.md; padre memoria/status.
- Reviewer R6 TERMINADO `ses_f16f667b3ffeVVx4WXVIaBLcXi`, favorable50distintos;
  REPORT326c054b cotejado, padre12hashes+3probes exit0/9.3s. Unidad final/control
  ACEPTADA offline acotada, ROOT libre. Docs5 receipt aceptado SHAe0eee00e,
  padre diff completo/source5/5/diffcheck0, sin FULL por prosa.
- Intención worker docs5 y researcher siguiente unidad sólo lectura en paralelo;
  tasks/next-r6-frame8.md y tasks/after-final-control.md. Sin implementación nueva aún.
- Docs receipt TERMINADO `ses_f16ec197dffeYJvOUwshL7p35M`, docs libres.
- Researcher `ses_f16ebe088ffeZilejsB5AdssPR` TERMINADO: recomienda secuencia
  Npasos mismo intento sin resume multileaf. Padre contrasta singleton/refund;
  contrato concreto recibido/APROBADO, incluido OutputResolution partición+huérfanos
  contrastado padre. Intención worker secuenciador Frame9 durable mismo intento,
  sin resume activo multileaf; mandato `tasks/sequence-frame9.md`. Researcher terminado.
- Worker Frame9 `ses_f16e08477ffev68BeeJBJvUqnS` TERMINADO sin implementación ni
  bloqueo causal; REPORTb183f5c9 cotejado, padre380archivos producto baseline intactos.
  /tmp/opencode/sequence-frame9-f16e0847/ guarda draft NO candidato. ROOT/build libres.
  Cambio estrategia: fase1 vertical persistencia+transiciones+pruebas A→B→C por seams,
  fase2 API/proyección/global FULL. Mismo contrato, no modos duplicados; task ampliada.
  Intención worker fresco fase1, no aceptación Frame9 todavía.
- Worker fase1 `ses_f16d8c612ffexlyE34pl0m2iC1` TERMINADO parcial preparatorio:
  REPORT728ddedb en /tmp/opencode/sequence-frame9-f16d8c61/ leído/cotejado padre8hashes.
  Frame validator9/evidencia leaf+global,31tests nuevos; owner523focales/compile107.
  NO producer9/Writer/transiciones/A→B→C real aún, sin bloqueo causal. ROOT libre.
  Intención worker fresco completa vertical preservando delta8; focales mínimos primero,
  no repetir523 por cada hito. Mandato sequence-frame9.md ampliado, fase2API después.
- Worker continuación fase1 TERMINADO `ses_f16bf3ff7ffeayJNWPOMncd55d`, realA→B→C
  con mismoWriter/Scope; REPORTa8127711 en /tmp/opencode/sequence-frame9-f16bf3ff/.
  Padre leído/hash+19/19fuentes cotejados; owner546focales(23nuevos+31previos),
  compile107/formato/diff0. Sin FULL/matrizcompleta/aceptación, ROOT libre.
  Intención worker fresco fase2API/proyección/cleanup/tracing +matriz pendientefase1
  y FULL integrado final. Task sequence-frame9.md final detalla pendientes.
- Worker fase2 `ses_f168b0f9bffeT4znovKZuzKdLT` ERROR cuota; usuario pide continuar.
  Padre confirma0builds propios y384archivos producto intactos vs fase1; sin cambios
  fase2 observados. Intención reanudar MISMA sesión una vez sin cambiar modelo;
  si cuota persiste reportar bloqueo, no retries/agents evasivos. No acceptanceFrame9.
- Fase2 `ses_f168b0f9bffeT4znovKZuzKdLT` TERMINADA/liberada: API/proyección/cleanup
  integrada, REPORTecf6ace5 en /tmp/opencode/sequence-frame9-phase2-f168b0f9/ leído,
  padre24/24hashes OK. Owner576focales/compile107/formato/diff0; FULL1651/1652
  28excluidos FALLA ausenciaAPI obsoleta. No contabilizar como verde.
  Padre autoriza sólo refute→assert run/3 en composition_definition_test:40,
  mantener refute resume/2. Intención worker fresco matriz±1 real+FULLintegrado,
  luego review acumulada; no aceptaciónFrame9/R6. ROOT/build libres.
- Worker matriz final TERMINADO `ses_f1651f1d0ffeNsrcyqLTsMLi7U`, ROOT/build libres.
  REPORT5da2073b en /tmp/opencode/sequence-frame9-boundaries-f1651f1d/ leído/hashOK,
  padre26/26fuentes+FULLlog/exit0:1664passed/28excluded/880.9s. Owner112focales,
  compile107/formato/diff0;12casos límites reales, runtime intacto. No aceptación aún.
  Intención reviewer fresco acumulado26 exclusivo ROOT/build, sin editar fuentes.
- Reviewer secuencia TERMINADO `ses_f162c6b48ffeNAxPaQ5CaaH7MN`, ROOT/build libres.
  REPORT9b0ac3bc /tmp/opencode/sequence-review-unique/ leído/cotejado y probehashOK.
  243existentes pasan;5propios3pasan2P2: admisión cuota mal phase/reason, WriterDOWN
  trap_exit causa excepción en vez RunError. No corrupción/duplicateIO alegada.
  Aceptación retenida; intención worker fixes causales+regresiones+FULLfinal,
  después review independiente y probes padre. Detalle en task secuencia.
- Worker fixes TERMINADO `ses_f161dcf80ffe8GfWNzvLC0VVj1`, ROOT/build libres;
  REPORT1903a2f0 /tmp/opencode/sequence-fix-unique/ leído/hashOK, padre26/26fuentes
  y FULL1673/28/885.2s exit0 cotejados. Owner62focales+compile107/formato/diff0.
  Originalprobes4/5: línea200 exige razón obsoleta. Padre inspecciona contradicción
  y autoriza COPIA nueva sólo expectativa razón exacta; original inmutable.
  Intención reanudar reviewer independiente para delta8+5probes corregidos,
  no aceptación aún ni afirmar original5verde. Detalle task secuencia.
- Reviewer fixes TERMINADO `ses_f162c6b48ffeNAxPaQ5CaaH7MN`, favorable62+5+2;
  REPORT8472c7a0 en /tmp/opencode/sequence-fix-review-unique/ cotejado padre.
  Padre26/26hashes+probe exactdiff OK; parent-final-seven-f19085 rerun7/7/3.3s exit0.
  Secuencia durable API ACEPTADA offline acotada; ownerFULL1673/28 identidad verificada.
  No active multileaf restore/C7composiciones/rawuncertain/R6general/producción.
  Intención receipt docs5 secuencia+MCPinterop; research siguiente recuperación sólo
  lectura independiente. ROOT/build libres; runtime sin nuevo mandato por ahora.
- Receipt docs5 TERMINADO/ACEPTADO `ses_f15fb2c8dffeWPZ3fuvPBklQd1`: padre diff441
  completo/REPORT90fc409e/hash5/diffcheck0 cotejados, docs5libres. Artefactos
  /tmp/opencode/receipt-sequence-unique/. Frases históricas C7pendiente en status
  requieren etiquetado futuro sin confundir recepciónR5 con C7composiciones abierto.
  researcher recuperación `ses_f15faf5beffezbXpL2ireiG0tP` entregó propuesta sólo lectura.
  Padre memoria/lectura, no builds concurrentes ni implementación nueva autorizada.
- Recuperación dirección aprobada: prefijo confirmado+input+terminaltexto/typed,
  seam nodos históricos cerrados, presupuesto finito abandonado NO recuperable.
  Padre contrastó Budget/CompositionRestore; `tasks/sequence-recovery.md` recoge
  contrato preliminar/matriz. Intención aclaración API/recover/helper mismo researcher,
  sin implementación hasta receipt docs liberado y contrato concreto.
- Aclaración researcher TERMINADA `ses_f15faf5beffezbXpL2ireiG0tP`; contrato sellado
  tasks/sequence-recovery.md: resume referencia pública estricta, recover explícito,
  helperScope cerrado atómico, prefix/input luego terminaltexto sin toolhistorypropia/
  typedSucceeded; no budgetreset/formato nuevo. Docs5libres y sinbuilds activos.
  Intención worker fresco ROOT/build/docs4 exclusivo, dos checkpoints útiles mismoAPI;
  padre status/memoria. Sin aceptación recuperación todavía.
- Worker recuperación TERMINADO `ses_f15f35afcffefZ5e1rROp5cvLV`, ROOT/build libres.
  REPORT4962b65b /tmp/opencode/sequence-recovery-f15f35af/ leído/cotejado padre,
  source12/12 y FULLfinal1706/28/933.0s exit0 cotejados;33nuevos,compile107/formato0.
  Temporal fix/root logical authority vs lease sólo nuevasfilas, antiguas intactas;
  NO aceptación aún. Intención reviewer fresco12delta/semántica temporal/probespropios,
  ROOT/build exclusivo checks, padrestatus/memoria. Detalle task sequence-recovery.
- Reviewer recuperación TERMINADO `ses_f15ae7eb3ffejXlv2w6V3C6nyW`, ROOT/build libres.
  REPORT55ffa3b3 /tmp/opencode/sequence-recovery-review-unique/ leído/cotejado.
  BLOQUEA P1 budgetreset tras on_writer permiteIOtardío; P2 invalidrootopts consumeclaim
  y raises.410existingpass;10probes7pass3fail para2hallazgos, fuenteintacta reviewer.
  Intención workerfixes causal mismoallowlist5+regresiones+FULL, luego review/probes;
  no aceptación recuperación. Detalle task sequence-recovery.
- Worker fixes recuperación TERMINADO/liberado `ses_f159fe367ffeYG4Cyd6O3xpAfh`.
  REPORT84489d3b en /tmp/opencode/sequence-recovery-fix-f159fe36/ leído/cotejado;
  padre10/10hashes+FULLlogexit0:1716/28/948.9s. Owner74focalfinal/10probes/3mismos
  causales/compile107/globalformat/diff0. Handoff intermedio ocupado ya resuelto.
  Intención reviewer independiente revalidafixes, ROOT/build libres hasta despacho.
  No aceptación recuperación; padre status/memoria.
- Reviewer fixes recuperación TERMINADO `ses_f15ae7eb3ffejXlv2w6V3C6nyW` libre.
  REPORT3face376 en /tmp/opencode/sequence-recovery-fix-review-f15ae7eb/ leído/hashOK.
  OriginalP1/P2 corregidos74+10pass, pero P1residual ACKintent tardío permite ModelIO
  trasbudget/lease (2reprosrojos). No aceptación. Intención workerfresco boundaryfix+
  audittool/stream, mismoallowlist salvobloqueocausal, FULLfinal/review después.
- Worker intentfix `ses_f156f2e15ffeyvcuFkfInGGySp` ERROR invalid_encrypted_content,
  NO reanudar. /tmp/opencode/sequence-intent-fix-unique/ baseline/reportmin+logs existen.
  Padre coteja baseline: existente cambiado sólo ExAgent; nuevo sequence_intent_dispatch
  test observado. green-causal14pass/11.5s exit0, parcial NOgatefinal. ps0buildpropios.
  Intención workerfresco recupera delta/tests sinrollback y completa mismomandato;
  no aceptación recuperación. Padre status/memoria.
- Worker intentfix recuperación TERMINADO `ses_f15689208ffek6qoTSmtVUmGN1`, ROOT libre.
  REPORTe959dc11 /tmp/opencode/sequence-intent-fix-recovery-unique/ leído/cotejado,
  padre6/6hashes+FULL1733/28/967.8s exit0. Owner17dispatch/113focal/10previos/2causales
  verdes; runtime1ExAgent+testnuevo+docs4. Intención reviewer independiente revalidación
  residualP1, no aceptación aún. Padrestatus/memoria.
- Reviewer intentfinal `ses_f15ae7eb3ffejXlv2w6V3C6nyW` ERROR invalid_encrypted_content,
  NO reanudar. REPORTparcial19líneas sequence-intent-final-review-f15ae7eb leído;
  audit/probes/gates pendientes, no aceptación. Padre ps0buildpropios/sólo3ajenos.
  Intención reviewerFRESCO completa residualP1 con artefactos nuevos, sin fuentesedits.
- Reviewer fresco TERMINADO `ses_f154c1659ffet0cQp28plp7Y7B`, favorable29+113+3;
  REPORT4e55a342 sequence-intent-review-fresh-f154c165 leído/cotejado padre.
  Padre6/6hashes+copyprovenance OK, /tmp/opencode/recovery-parent-3_d5tlzx/ parent-final
  15/15/12.6s exit0(mismos2+10+3), lateACK0requests/revisionintacta. RECUPERACIÓN
  ACEPTADA offline contratoacotado; ownerFULL1733/28/967.8s separado. R6general/C7
  composiciones/rawuncertain/activebatchretry multileaf/producción abiertos.
  Intención receipt docs5 y researcher C7composición sólolectura; ROOT/build libres.
- Receipt recuperación TERMINADO/ACEPTADO `ses_f15442e4dffe26sIxWaXLuJ4Is`, docs5libres.
  REPORTd05e1be2 receipt-recovery-unique leído/hashOK, diff274 completo/hash15cd97a3,
  padre5/5hashes+diffcheck0. C7antiguostatus etiquetadohistórico, sin nuevosgatesruntime.
  ResearcherC7 `ses_f1543ed1fffeoUXKt6gtEqUyjR` entregó sólolectura: allpendingC7 viable,
  extensiónRecord2 necesaria sin Frame10; padrecontrastó Writerpause/Transitiondispatch.
  Padre memoria/lectura; no builds activos ni implementaciónC7 despachada.
- DirecciónC7 aprobada tasks/sequence-approvals.md; faltan pausedresult/evoluciónvalidada/
  autoridadactiva vs attemptdeadline y seams pendientes antesmandato. Intención aclaración
  mismoresearcher sólolectura; sin implementación todavía.
- AclaraciónC7 TERMINADA `ses_f1543ed1fffeoUXKt6gtEqUyjR`; contrato SELLADO tasks/
  sequence-approvals.md allpending/despuésconcurrencia (no barrera batchatómica),
  Record2extension/Frame9, pausedprojection/halt/2decisions/raízrefund/readyresume.
  Autoridadleaflogical ya separada, no cambiosBudgetScopeLedgerAuthorityStore.
  Allowlist6 explícita y matriz/compatdireccional; intención workerfresco ROOT/build/
  docs4 exclusivo, checkpointVMfuncional luego FULLfinal/review. No aceptaciónC7.
- Worker C7 TERMINADO `ses_f153afdabffeCWAJLIl1zOU81y`, ROOT/build/docs4 libres.
  REPORT10184e17 /tmp/opencode/sequence-approvals-f153afda/ leído/cotejado padre,
  hashes15/15+FULLcola1776/28/1098.2s; owner43new/compile108/formato/diff0.
  VerticalVM2approvals funcional, NOaceptación: codec±1/postapprovalbindings/obsdelay
  pendientes. Intención workerfresco cierre matriz+provenanceoldtests+FULLfinal;
  reviewtotal después. Padrestatus/memoria; no otros hijos activos.
- Worker matrizC7 TERMINADO `ses_f14f3b0f0ffes6e6QdF5m6ke2H`, ROOT/build libre.
  REPORTe8fc58f6 sequence-approvals-matrix-f14f3b0f leído/hashOK, padre15/15fuentes+
  FULLcola1790/28/1121.2s;14newtests runtimeintacto. Oldtestsdiff2 leídos completos,
  recepción causal aprobada AHORA (no autorizaciónprevia inventada). NoaceptaciónC7.
  Intención reviewerfresco acumulado15, solo checksROOT/build; padrestatus/memoria.
- Reviewer C7 TERMINADO `ses_f14cfecdbffesCLr9erQu0d2ij` favorable271+7/compile108.
  REPORT75d0d321 sequence-approvals-review-f14cfe leído/hashOK, padre15/15fuentes+
  /tmp/opencode/sequence-approvals-parent-f19085/parent.log7/7/13.2s exit0(mismos7).
  C7allpending secuencia ACEPTADOoffline acotado, ownerFULL1790/28/1121.2s separado.
  Mixed/raw/delegación/generalR6/routerparallel/SQLliveprod/MCPprincipal abiertos.
  Intención receipt docs5+research siguienteR6 sólolectura; ROOT/buildlibres.
- Receipt C7 TERMINADO/ACEPTADO `ses_f14c34496ffeig1ps6ZMZ8pkd0`, docs5libres;
  REPORTf8946d2b receipt-approvals-3ko1pm2l leído/hashOK, diff288 completo128d9512,
  padre5/5hashes+diffcheck0. Usohostdocumentado/provenance/históricos conservados.
  researcher siguienteR6 `ses_f14c3007bffeDA3qkYE5oQUewY` entregó sólectura.
  Padre memoria/lectura; no builds activos ni nueva implementación despachada.
- Siguiente dirección aprobada recoveryactive final/resuelto+outputretry+approvals
  consumidas sinformatnuevo. Padrecontrastó classifier150–209; task sequence-active-evidence.
  Intención aclaración consumedapproval/fatal/reusehelpers mismoresearcher, sololectura.
  Delegación+C7/mixedcontrol y routingparallel siguenobligaciones posteriores.
- Aclaración activeevidence TERMINADA `ses_f14c3007bffeDA3qkYE5oQUewY` sólolectura;
  contrato SELLADO tasks/sequence-active-evidence: vista privada/originalrecord,
  approvalsconsumidasexactas/fatalactualconsumible vsfatalhistóricorechazo, noformatnuevo.
  Intención workerfresco runtimeprincipalCompositionRestore+2oldtestscausales+newtests/
  docs4, checkpointVMdobleinterrupción luego matrizFULLfinal/review. ROOT/buildlibres.
- Worker activeevidence TERMINADO `ses_f14bc1294ffeCq8m8tiwAuiCAf`, ROOT/build libre.
  REPORT203c8204 /tmp/opencode/sequence-active-evidence-oe6a6hgv/ leído/hashOK,
  padre9/9hashes. Funcional2VM/approvals/toolresolved/outputretry25new;386focales/
  compile109WA/formatdiff0owner, NOfull/aceptación. Runtime sóloCompositionRestore.
  Intención workerfresco matrizpendiente REPORT119–139+FULLfinal sinrestart; taskampliada.
- Worker activematrix TERMINADO `ses_f14965e4affeBEFwj49rcDIGMp`, ROOT/build libres.
  REPORT5da10174 /tmp/opencode/sequence-active-matrix-xzij2ykz/ leído/hashOK, padre9/9+
  FULLcola1845/28/1410.3s.30new/55acumulados/runtimeintacto vscheckpoint,compile109WA.
  Noaceptación: intención reviewerfresco acumulado9/probespropios/focalessinFULLrutina;
  límites retryestructural/unknownintent explícitos task. Padrestatus/memoria.
- Reviewer active TERMINADO `ses_f146616d5ffer1LKkxGHcguHW5`, favorable40existing+4own.
  REPORTed38ec5b sequence-active-review-u4tSrE50 leído/hashOK; padre9/9hashes+
  /tmp/opencode/active-parent-psg836g3/parent.log4/4/16.7s exit0(mismos4), copyroundtrip.
  ACTIVEEVIDENCE ACEPTADO acotado9finalresolved/outputretry/consumedapprovals,
  ownerFULL1845/28/1410.3s separado; mixed/raw/delegación/routerparallel/R6general fuera.
  Intención receipt docs5+researchdelegaciónC7mixed sólolectura; ROOT/buildlibres.
- Receipt active TERMINADO/ACEPTADO `ses_f145c67a0ffeMFQMaTFzwp6EQa`, docs5libres;
  REPORT47c76a10 receipt-active-2ysnwuzs leído/hashOK, diff306 completo7cd50def,
  padre5/5hashes+diffcheck0, no nuevosgatesruntime.
  researcher delegación `ses_f145c1988ffes6uJzDi6LT6lZG` entregó análisis sólolectura.
  Padre memoria/lectura; ningún build ni nueva implementación activa.
- Delegaciónmixed/C7 necesita typedlinks/partialcontrol/quiescence durable, dirección
  aprobada tasks/structural-delegation.md, NOschema/version/implementación sellados aún.
  Intención aclaración exactschema/fatal/hostresolver mismo researcher; receipt docs5
  conserva propiedad. No nuevo scheduler/ledger/Store/ReqLLM ni antiguomixedreinterpretado.
- Aclaración esquema delegación TERMINADA `ses_f145c1988ffes6uJzDi6LT6lZG` sólolectura;
  propuesta concreta tasks/delegation-schema-proposal.md: Frame10typedlinks/partialcall/
  frontier+failedterminal10/hostresolver. Padre aceptaDIRECCIÓN, no runtimeautorizado.
  Intención reviewindependiente esquema/races/consumercompat/reserves antesdespacho;
  docs5/build libres, padre memoria. No implementaciónnueva activa.
- Reviewer diseño `ses_f1451a03affe1LB0QiPylcgij0` dictamen bloqueante8huecosprevios:
  raw/control,atomicbegin,rehydrationrepeatable,liveinventory,fatalorigin,failedfacade,
  resolverexact,terminalinspection. Padre ADOPTA correcciones en schema-proposal final
  que prevalecen. Intención relecturaconsistencia misma sesión sin nuevoauditgeneral;
  todavía NO autorizaciónruntime ni builds. Padre memoria/lectura.
- Relectura diseño TERMINADA `ses_f1451a03affe1LB0QiPylcgij0`: listo con límites,
  sólo conformidad estática. Padre SELLA implementación en structural-delegation.md;
  schema-proposal correcciones finales prevalecen. Intención worker único ROOT/build/
  docs4, checkpoint funcional integrado luego matriz/gates/review; no aceptación runtime.
- Worker delegación ACTIVO `ses_f144a5659ffecDQIhVqtWHjaPi`, ROOT/build/docs4 exclusivos;
  padre status/memoria. Ningún otro hijo activo ni build concurrente autorizado.
- Handoff bloqueo previo sin producto editado: REPORTa1180bab structural-delegation-
  dfTqOja9 leído/hashOK, padrecontrastó OutputResolution231–252. Probe1 diagnóstico,
  no Frame10 integrado; owner430/430 intactos, procesos liberados. Padre AUTORIZA
  OutputResolution versión10 exacta suspended/failed, legacy intacto; task detallada.
  Intención retomar mismo worker/mandato, no aceptación ni checkpoint aún.
- Continuación despachada ACTIVA `ses_f144a5659ffecDQIhVqtWHjaPi`, ROOT/build/docs4
  exclusivos; padre memoria/status. Ningún otro hijo activo.
- Continuación TERMINADA sin producto ni tests nuevos: RESUMPTIONf944e4f1 leído/hashOK,
  owner declara contexto agotado, NO nuevo bloqueo, ROOT/build liberados. Padre cambia
  estrategia a incrementos internos probados/inactivos (task final prevalece), primero
  Frame10 gramática/invariantes sin activar run10 ni modificar legacy. Intención worker
  fresco acotado, no otro encargo monolítico ni rediseño. Sin aceptación Frame10.
- Worker base10 ACTIVO `ses_f1440e432ffeAVZKAr8AaZ4Nw2`, Frame/ToolEvidence/
  OutputResolution/Record validación +tests, ROOT/build exclusivos; productor9 intacto.
  Padre memoria/status, sin otros hijos activos.
- Base10 TERMINADA/liberada: REPORT29b20b91 delegation-frame10-base-bB06qm3T leído,
  padre5/5hashesOK;35grammar+349regresión(owner incl33nuevos)/compile109WA/formato0.
  Runtime3módulos/roadmap/testnew, guardRecord/evidence/transition10 siguen cerrados.
  Baselinecaveat+reconstrucciónhash declarados; NOFULL/VM/aceptación10. Intención review
  breve delta/aislamiento antes journal increment, padre memoria/status.
- Reviewer base10 TERMINADO `ses_f142bfc4effexSSIvBwPKu6RZt`: favorableinterno,
  REPORTa1eb97a3 frame10-base-review-wBAfefda leído/hashOK+padre5/5fuentes.
  Review72+3tests/5gruposprobes, identidad/reconstrucciónexacta; guards10cerrados.
  Intención siguienteworker evidenciajournal/OutputResolution10 inactiva; Record/
  transición/productores10 siguen cerrados. Sin aceptaciónruntime ni FULL.
- Worker journal10 `ses_f1425d5eeffemOwTwPQXMwdeZ8` ERROR invalid_encrypted_content,
  NO reanudar. /tmp/opencode/frame10-journal-jya6y4hV/ baseline sólo, padre431/431
  hashes intactos/sin nuevas rutas/ps0buildpropios. No código/gates nuevos observados.
  Intención worker fresco mismo incremento cerrado, base10 revisada intacta.
- Worker journal fresco TERMINADO `ses_f142303bcffebckNaV0iDmCaOz`, ROOT/buildlibres.
  REPORT4135ceb0 frame10-journal-fresh-iVQZzt8g leído/hashOK, padre6/6fuentes.
  Partialjournal30new/65focal+279legacy/compile110WA owner; evidence/Record/trans10
  aúncerrados, no runtimeaceptado. Intención worker cierre global/fases/childhost/
  retryfatal pendientesREPORT43–46; luego reviewacumulada, no reiniciar.
- Worker cierrejournal TERMINADO `ses_f140becd5ffeMhrOYb50B0EJSD`, libre; REPORТe20d5655
  frame10-journal-complete-FXHNF6xU leído/hashOK+padre6/6.14new/79focal+62legacy,
  compile110WAowner; parcialcertificate aún cerrado. Bloqueo failedchildprojection
  resuelto decisión canónica10 lossyportable en schema-proposal, legacy sin cambios.
  Intención workerfresco child/hostsource acotado, no otra misión cerrar todojournal.
- Worker sources10 TERMINADO `ses_f13fd738effe0Wup43A8pM50ug`, ROOT/build libres.
  REPORTa7ea3ceb frame10-sources-JCYces leído/hashOK+padre10/10.20new/99focal+62legacy,
  compile111WAowner; childraw/source y hostpermissiondeny, globalsiguen cerrados.
  Intención researchacotado hostunprepared/wrapperfinal/cancelledraw→transiciones;
  evitar otra cadena validators sin consumidor. No aceptación runtimeFrame10.
- Research cierrecontrato TERMINADO `ses_f13f3f1b0ffetOYnR0wFenpfeV`, decisiones selladas:
  hostunprepared sinbindingfalso, wrapperfinaltrustedtransition, terminalchildimmutable.
  Intención worker transiciones+Record10 operacionesCASreal nestedpause/decide/claim;
  productores9 intactos, fatal/outputfailed aúncerradospermitidos checkpoint. Task final
  detalla allowlist/guards/pruebas. No runtimeaceptado, ROOT/buildlibres.
- Worker transiciones10 ACTIVO `ses_f13f0613dffegVAIyKiJQiAnFS`, ROOT/build exclusivo,
  allowlist fasevalidación/transiciones+tests/docs4; padre memoria/status.
- Handoff transiciones bloqueadoANTESedits/liberado: REPORTab0a5f9e transitions-WNqvHSI8
  leído/hashOK, padrecontrasta RequestData1 hash-only/Framefingerprint. AUTORIZADO
  RequestData2preimagenexacta sólo10, RequestData1/productor9intactos; schemafinal.
  Intención retomar mismoworker CASintegrado, no aceptación ni checkpoint implementado.
- Continuación CAS TERMINADA `ses_f13f0613dffegVAIyKiJQiAnFS`, ROOT/buildlibres;
  REPORTefb254bb transitions-WNqvHSI8 actualizado leído/hashOK+padre20/20acumulado.
  CASnestedmixed/pause2/decide/reclaim y rawX→finalY operativos inputs sintéticos;
  175final/207legacy/compile112WAowner. Admisión10 sólosubset usageabsent, outputretry/
  terminal/recovery/fatal aúncerrados. Productor9/restore10 sinactivar. Intención review
  acumulada20 antes ampliar, no aceptaciónruntime/VM. Padre memoria/status.
- Reviewer CAS10 TERMINADO `ses_f13c08d72ffe8F20va45RMfi4K`, ROOT/buildlibres.
  REPORT03a7694c frame10-cas-review-8Dfp1CQa leído/hashOK:2P1(omittedhistory/unknownchild
  autorizaModelnuevo),2P2(reservacierreinutilizable/hostposthookargswrong).320existing
  verdes no cierran4repros. Intención workerfixes causales mismoallowlist+regresiones,
  reviewdespués. Subset NOaceptado, productor10 sigueoff; padre memoria/status.
- Worker fixesCAS10 TERMINADO `ses_f13ac4b46ffek90Kdhnm5v5954`, ROOT/buildlibres;
  REPORT3eb59edb frame10-cas-fix-42rWnXLi leído/hashOK+padre10/10fuentes.
  Owner333(320+13)/external13mismos/compile112WAformatdiff0; cuatrocausas corregidas
  segúnowner, review pendiente. Intención mismo reviewerindependiente; sin aceptación.
- Reviewer fixesCAS10 TERMINADO `ses_f13c08d72ffe8F20va45RMfi4K`, favorableinterno;
  REPORT38b14cab leído/hashOK+padre10/10fuentes/copyroundtrip3probes. Parent
  /tmp/opencode/cas10-parent-5rn_0jdr/parent.log13/13/13.0s exit0(mismosreview13).
  Cuatrofixes/subsetCAS recibidos INTERNOS, no producto10/VM. Intención accounting10
  no-nil/qualified/ancestral exacto sin modificarledger ni abrir terminal/recovery,
  ROOT/buildlibres; padre memoria/status.
- Worker accounting10 ACTIVO `ses_f1392aa76ffe1RDtPOg2rUA42L`, ROOT/build/docs4
  exclusivos faseacotada; padre memoria/status. Ningún otro hijo activo.
- Accounting10 handoffBLOQUEADO/liberado baseline442restaurado, REPORT6a8fd3f8
  frame10-accounting-xL0zt7od leído/hashOK;2repros nilaggregation, padrecontrastó
  ScopeLedger139. AUTORIZADO decode_usage(nil)existente en agregación, sum/semantics
  intactos; intención mismoworker retoma experimentoauditado+accountingmatrix.
- Continuación accounting ACTIVA `ses_f1392aa76ffe1RDtPOg2rUA42L`, ROOT/build/docs4
  exclusivos; ScopeLedger seam acotado autorizado. Padre memoria/status.
- Accounting handoffTERMINADO/libre REPORT09945e9b accounting-resume-ak7TN45w leído/
  hashOK+padre10/10.28focal pass/regresión234/235 rojo únicamente antiguoModelnilguard.
  Padre inspecciona test170–220 y autoriza Modelcommit+opassert/rename, wrappernegative
  INTACTO. Intención mismoworker cierre gates y luego review, noaceptación aún.
- Cierre accounting TERMINADO `ses_f1392aa76ffe1RDtPOg2rUA42L`, ROOT/buildlibres.
  REPORTbecc7801 accounting-oracle-NGrZ5ydw leído/hashOK+padre11/11fuentes.
  Owner235regresión+2probes/compile112WAformatdiff0; runtimefollowupintacto.
  Intención reviewfresco acumulado11accounting antes aceptacióninterna; productor10off.
- Reviewer accounting TERMINADO `ses_f136d379effehWXsQ5N1KGwAtP`, favorableinterno.
  REPORT641f0436 leído/hashOK;134existing+4probes. Padre11/11fuentes y rerunmismos4
  /tmp/opencode/accounting10-parent-8zlndpu_/parent.log4pass/4.6s/exit0.
  Accounting subset INTERNO recibido; no universalcapacity/VM/producer10.
  Intención worker outputtipado/retry10 CAS+childterminal, root/fatal/recovery aúncerrados.
- Worker outputCAS10 TERMINADO `ses_f13620c40ffe6R4K9SEXFyO7tZ`, ROOT/buildlibres.
  REPORT243efed0 output-cas-2HG3aDNz leído/hashOK+padre9/9. Owner380+final9(overlap6),
  compile113WA/formato/diff0. Output CAS implementado, revisión pendiente; entradas
  trusted sintéticas, producer10/VM/fatal/rootterminal/recovery aúncerrados.
  Intención reviewerfresco delta9 y probes independientes; padre memoria/status.
- Reviewer outputCAS10 TERMINADO `ses_f134b0f45ffeUzBUIXI60v3Ra2`, ROOT/buildlibres.
  REPORT0fbc8574 output-review-lOMWDLo0 leído/hashOK: P2outputACK sinreservacopias,
  2repros60000B bloquean consume/complete.240selectedgreen/3de5probes,445intactos.
  Owner380 no atribuido a bytesfinales. Intención fixRecord/outputreserve acotado,
  testspermanentes y re-review; outputsubset NOaceptado, producer10off.
- Worker outputcapacity TERMINADO `ses_f133e3f53ffeEFZ6KOE3dCCN8Y`, ROOT/buildlibres.
  REPORT78e88cd1 output-capacity-fix-TrWhtkHm leído/hashOK+padre7/7. RuntimeRecordonly,
  owner282/probesoriginal5/5(sealed12overlap)/compile114WAformatdiff0.
  Intención mismo reviewer revalida reserva y fronteras; outputsubset aúnnoaceptado.
- Reviewer outputcapacity TERMINADO `ses_f134b0f45ffeUzBUIXI60v3Ra2`, favorable.
  REPORT5d9a70d3 leído/hashOK+padre7/7fuentes. Padre rerun7/7/14.9s exit0 en
  /tmp/opencode/output-capacity-parent-hwynv_an/ (mismos5+2review). Output/retryCAS
  recibido INTERNO, no producer/VM. Intención cierre exitoso steps/root CAS10,
  fatal/recovery aúncerrados; ROOT/buildlibres, padre memoria/status.
- Worker successTerminal10 TERMINADO `ses_f1323348cffepePO0g3y65fYJT`, ROOT/buildlibres.
  REPORTdca60821 success-terminal-8v_93fvc leído/hashOK+padre10/10. Owner316incl12new
  +7probesprevios/compile115WAformatdiff0. Steps/rootclosed/refundCAS implementados;
  Record/getterminaldataonly, Composition.resume10 aúnCERRADO. Intención reviewer
  fresco globalclosure/prefix/refund/reservas; sinaceptaciónruntime10/VM.
- Reviewer successTerminal10 TERMINADO `ses_f1301d42affePuJercSlnt6L7x`, favorable.
  REPORT4e861ad9 leído/hashOK+padre10/10fuentes; padre4/4/33.5s exit0 mismosreview
  en /tmp/opencode/success10-parent-mi886fkc/. Successsteps/root CAS recibidoINTERNO,
  publicresume/producer10 aúncerrados. Intención fatal/exhaustion/failedclose10 CAS
  sin recovery ni livequiescence; ROOT/buildlibres, padre memoria/status.
- Worker fatalCAS10 TERMINADO `ses_f12f6024effeuv8S0Q5zgHasOW`, ROOT/buildlibres.
  REPORT886558db fatal-cas-xclmgyda leído/hashOK+padre9/9. Partialcallfataldrain10new,
  selected114/115ROJO oldfixedcapacity1714951; terminal/exhaustion aúnpendientes.
  Padre inspecciona oldtest320–350 y autoriza cálculo threshold+oldlimitnoIOcontrol,
  raw65536±1 yatomicnegative intactos. Intención mismoworker cierregates sinampliar.
- Worker fataloracle TERMINADO `ses_f12f6024effeuv8S0Q5zgHasOW`, ROOT/buildlibres.
  REPORT91a344f5 fatal-oracle-xlzx8r23 leído/hashOK+padre10/10acumulado.
  Owner116/18overlap/legacy4/compile115WAformatdiff0 runtimefollowupintacto.
  Intención workerfresco callfatal→blocked/cancelledeligible→failedroot/refund/facade,
  otrosfatal/exhaustion aúnpendientes; reviewacumulada después, sinaceptaciónfatal.
- Worker failedClose10 TERMINADO `ses_f12d948bbffeB5XuLp6DFtYCSA`, ROOT/buildlibres.
  REPORT95a24abf failed-close-5pbswx2_ leído/hashOK+padre13/13acumuladofatal.
  Owner150incl8new+legacy4/compile115WAformatdiff0. Failedroot/refund/get/delete
  implementados callfatalonly; intención reviewFRESCO acumulado13fatal, noaceptación.
- Reviewer fatalClosure10 TERMINADO `ses_f12bae14bffePHw4aMUpM2Eqs5`, libre.
  REPORT3ae72d20 failed-review-HMGSMUOe leído/hashOK:P1wrapperadmitido1378383 no
  guarda fatal4096 (necesita1382090), boundary1/2exit2;52+4legacygreen no aceptación.
  Intención fix reserva/controlmaterializado/receipt antescallback, no oráculo ampliado;
  re-review luego probespadre. Productor10off, padre memoria/status.
- Worker fatalCapacityFix TERMINADO `ses_f12adf349ffeI89QmVkTF8DGW0`, ROOT/buildlibres.
  REPORT1f1423f2 fatal-capacity-fix-n87qjASq leído/hashOK+padre15/15acumulado.
  RuntimeRecordonly controlcredit/receipts; owner134+legacy4/original2green/compile116WA.
  Intención mismo reviewer revalida delta7 y fatalacumulado15; noaceptación aún.
- Reviewer fatalCapacity TERMINADO `ses_f12bae14bffePHw4aMUpM2Eqs5`, favorableinterno.
  REPORTac8c5370 leído/hashOK+padre15/15; padre4/4/95.2s exit0 mismos2+2review en
  /tmp/opencode/fatal10-parent-b0aqy4er/. Callfatal/failedclosure INTERNO recibido.
  Intención outputexhaustion certificado+nodefatal acotado, otrosfatal/recovery/
  producer10 cerrados; ROOT/buildlibres, padre memoria/status.
- Worker outputExhaustion10 ACTIVO `ses_f127f60b3ffe6h5Dzhy2jnqm8P`, ROOT/build/docs4
  exclusivos exhaustion/nodefatal acotado; padre memoria/status. Ningún otro hijo activo.
- Outputexhaustion handoffBLOQUEADO/liberado sinedits: REPORT56fdef60 g7ghhz5t leído/
  hashOK; padrecontrasta ordinary2697–2713 y AUTORIZA decisionretry terminal10 único,
  appendfinal sinusedincrement, exactsource/counter/nodefailed/frontier certificado.
  Schemafinal detalla exclusión acotada; legacyintacto. Intención mismoworker retoma.
- Continuación exhaustion TERMINADA `ses_f127f60b3ffe6h5Dzhy2jnqm8P`, ROOT/buildlibres.
  REPORT42355950 exhaustion-resume-ccw8mexa leído/hashOK+padre12/12. Owner164incl9new
  +166legacy/compile117WAformatdiff0. Exhaustion/nodefatal implementados, intención
  reviewFRESCO delta12/reservas/counterexception; producer10/recoveryoff, noaceptación.
- Reviewer outputExhaustion10 TERMINADO `ses_f125440e9ffe8uprKa6ZWiUb7R`, libre.
  REPORT2bbfa230 exhaustion-review-b9k4uBqI leído/hashOK: P1composedreserve siblings,
  source837930 admite luego exhaustionrecord_limit;boundary1/2exit2,24+4legacygreen.
  Intención fixRecordcapacity mandatorycopies+remaining siblingreserves; noaceptación.
- Worker exhaustioncapacity handoffBLOQUEADO/liberado `ses_f12481a56ffeWKiq35fMDNikl3`:
  REPORTd5f3a5bb slV6LFp7 leído/hash5/5; candidataRecordsource868234±1 pasa,
  originalroomy sink866148 ahora menor fuente. Padreinspecciona yautoriza COPIA
  líne87maxexistingbudget/label92 sólo, source±1/refund intactos. Intención retoma
  matrizpermanente+gates; noaceptación aún.
- Continuación exhaustionCapacity TERMINADA `ses_f12481a56ffeWKiq35fMDNikl3`, libre.
  REPORT8631112f exhaustion-matrix-60bpPK5e leído/hashOK+padre7/7. Owner10new/69selected/
  10oraclelegacyoverlap/compile118WAformatdiff0; oráculoexactcopy2/2 originalredintacto.
  Intención mismo reviewer fórmulaOwnSlot/composición+exhaustion; sinaceptación aún.
- Reviewer exhaustionCapacity ACTIVO `ses_f125440e9ffe8uprKa6ZWiUb7R`, ROOT/build
  exclusivo checks sinfuentesedits; padre memoria/status. Ningún otro hijo activo.
- Reviewer handoffINCOMPLETO:4/4reproboundarygreen, selecciónactiva+3probespendientes;
  NOreleaseROOT/build ni aceptación. Continuación MISMA sesión despachada para cerrar
  gates/report; propiedadexclusiva retenida, sin nuevos checks concurrentes del padre.
- Intención worker interoperabilidad MCP SDK oficial en copia MCP privada/build propios,
  sin cambios ROOT/runtime; `tasks/mcp-sdk-interop.md`. Descargas públicas sólo entorno
  privado, IO tests local sintético; no C7 binding aceptado implícitamente.
- Worker SDK MCP TERMINADO `ses_f16da2afdffe69uzS9liYuXrfy`: owner5/5 sin skips,
  SDKPython2.2.0 stdio+HTTPJSON/SSE session/stateless; runtime intacto y procesos libres.
  REPORT727d2a29 en /tmp/opencode/mcp-sdk-interop-G1ERXY8j/ leído/cotejado y selloOK.
  Review y aceptación posterior abajo, sin atribuirle gates generales.
- Reviewer SDK TERMINADO `ses_f16ce6696ffeuZ6bEh9czXXhEZ`, favorable5/5 y
  procedencia/wire/cleanup independiente. REPORTE e52735d5 leído/cotejado padre,
  owner selloOK y5módulosMCP ROOT/copia byte-idénticos. Interop perfiles SDKPython2.2.0
  ACEPTADA acotada, docs/harness recepción pendiente tras ROOT liberado; copia libre.
  No cerrar OAuthTLS/C7binding/cancel/reconnect/A9/R7.4/G4. tasks/mcp-sdk-interop.md.
- No worktrees creados; copias privadas bajo /tmp/opencode.

## Baseline aceptado y evidencia (offline acotada, no R6/R7 completos)
- Unidades previas: output-success ownerFULL1153/28 review109+5/padre5;
  retry1 FULL1211/28 review167+5/padre5; cadenas output N FULL1287/28 review208+7/
  padre7. Detalle tasks/output-retry.md y leaf-restore-next.md; no repetir.
- Integridad cardinalidad batch FULL1310/28 review141+4/padre4, tasks/final-tools-restore.md.
  Usage NO está serializado en ToolReturn/Outcome hash: no reconstruir histórico.
  Diagnóstico original3rojos causales intacto; no restore tools habilitado.
- Counters6 runtime-owned entre cada hook Model aceptado: FULL1354/28 owner,
  review124+8/padre8. tasks/runtime-counters.md, retry-control-contract.md.
- Frame8 productor/validator ACEPTADO: owner ses_f180bea31ffeoAtIjHAo2VyiO2 terminado,
  FULL1409/28/508.2s, compile102/focal88/formato/diff0. REPORT6413ccab en
  `/tmp/opencode/tool-evidence-f180bea3/`;19/19hashes cotejados. Review95 (55+33+7),
  padre7probes exit0/2.5s con nuevos destinos JSON; review ses_f1798e084ffeSdf4vdZdgPyvjA
  terminado, REPORT49eb910f en `/tmp/opencode/frame8-review-20260928-fresh/`.
  Accounting observado antes retención/negativa partial/CAS raw/control/reservas;
  legacy7 lifetime mantiene7, nuevo8. Guards tools/prefix/batches intactos.
  Contrato/evidencia/límites en `tasks/tool-evidence-producer.md`.
- OTel pausa/attempt/reference/accounting ACEPTADO privado tras fix2P2 validación:
  review145+9, padre9; patch5a060902 exacto3paths. Artefactos
  `/tmp/opencode/exagent-r7-worker-O6Cjkklr/`, tasks/r7-observability.md.
- Frame8+OTel INTEGRADO ACEPTADO: integrador FULL1423/28/509.6s/focal476+9,
  compile102/formato/diff0; REPORT2e4c0dd5 en
  `/tmp/opencode/exagent-integration-frame8-r7-xkdxkNR2/recovery/`.
  Review ses_f1779934effepiqEocCDpiVwJH terminado favorable9+69, REPORTc58bcc93 en
  `/tmp/opencode/integration-review-dNfJQyRC/`; padre source completo cotejado.
  Delta3producto+6docs. `tasks/integration-frame8-r7.md`.
- MCP HTTP ACEPTADO privado tras P2 chunking terminal SSE corregido: reviewer
  ses_f179dea7fffeeXpWyv8h7HYGtq terminado121+6+2, padre8probes/397hashes.
  `/tmp/opencode/exagent-r7-mcp-7xhyz66_/artifacts/review-validation/REPORT.md`
  SHA28bd6c20; acumulado9paths patchffb311e8 en artifacts/fix-sse/.
  HTTP1 pool host confiable, MCP2025-06-18, sin replay; C7 target binding/SDKinterop
  NO cualificados. Detalle `tasks/r7-mcp.md` y docs/development/r7-mcp-implementation.md.
- MCP INTEGRADO ACEPTADO por review padre: integrador ses_f17740714ffezzi4IbtcVoZHjp
  terminado, REPORT9b192949 en `/tmp/opencode/exagent-integration-mcp-qlq7ladh/`.
  FULL1467/28/508.9s,121MCP+8probes+69adyacentes, compile106/formato/diff0 owner.
  Padre leyó diff docs completo, cotejó377/377manifest+9rutas privadas exactas y
  ejecutó77casos ROOT exit0/20.9s (parent-review.*). Delta14paths (9patch+5docs).
  Recepción documental aceptada en /tmp/opencode/receipt-mcp-f2mhydav/REPORT.md;
  producto y docs aceptados. tasks/integration-mcp.md.

## Siguientes acciones y restricciones vigentes
1. Recibir implementación/gates secuenciador Frame9; contrastar delta/compatibilidad/
   ownership y fresh review antes aceptar. No volver R0 ni repetir aceptaciones.
2. Mantener abiertos restore tools/raw/incertidumbre/delegación/A→B/router/paralelo,
   C7 binding MCP/SDKinterop, G4 UI/direct native exporter, R8/R9 pertinentes.
- No inferir progreso de summaries ni estado completed con build activo: comprobar
  reporte final/liberación. Esperar notificaciones, no polling.
- Probes históricos escriben JSON fijos: copiar/parametrizar NUEVO destino antes rerun.
- Sesiones dañadas NO reusar: ses_f184e3732ffe4kp6QVdJxp3LLS,
  ses_f17c61409ffeYnC1K5myGjPvvJ, ses_f17bffb92ffe8QCbNB10cam3Hz,
  ses_f178ebb3affeU7OBqIqdJZmFwH. Entregas recuperadas descritas en tasks.
- CURRENT.previous.md conserva estado validado previo a compactación; historial
  adicional está en fichas, no perder rojos ni atribuir FULL owner a reviewer/padre.
