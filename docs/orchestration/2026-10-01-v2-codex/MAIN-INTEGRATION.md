# Integración directa en main — 2026-10-04

El usuario autoriza subir todo a main y continuar sin PR obligatoria. El push
fast-forward de 7f25b33 a cd34397 integra la preparación y la implementación
anterior. GitHub marca PR1 como MERGED automáticamente; el workflow de releases
aparece activo. No se ha creado un tag, publicado una release ni escrito en Hex.

Dos deltas del consumidor se incorporan después: guía backend del envelope y
conservación de la causa RequestError cuando sólo su copia de Response excede
4KiB. El design/changelog documentan los contratos, alternativas y límites.
El segundo aparece mientras se valida el primero; no se atribuye al FULL previo.

## Verificación de esta integración

Fuentes, dependencias, build y tooling propios en
`.exagent-local/main20261004/candidate`; Elixir1.20/OTP29, EXAGENT_OFFLINE=1,
MIX_ENV=test y carga dotenv de ReqLLM deshabilitada. No cambios globales ni pruebas
pagadas, de nube, SQL o de la aplicación consumidora.

- Primer freeze: formato y131 ReqLLM focales pasan,17,3s; no incluye retención.
- Freeze combinado: formato y159 focales pasan,14,3s, seed37556; comando16,220s.
  Son todos los tests ReqLLM de primer nivel y retention_contract_test.exs.
  Los SHA256 de las dos fuentes y tres tests coinciden después con el checkout.
- El primer build de docs/TAR pasa sus comandos, pero la comprobación de identidad
  final detecta Retention cambiado mientras se preparaba. Ese TAR no es el
  artefacto aceptado; el fallo y sus bytes permanecen en el directorio privado.
- Freeze combinado: compilación y ExDoc estrictos, enlaces, Hex build,
  aislamiento del paquete y metadatos de release pasan, exit0 en seis comandos.
  Las175 entradas del TAR, incluidas94 fuentes de biblioteca, coinciden byte a
  byte con la copia comprobada y el checkout. SHA256 del TAR final:
  `59c41d72de780c28fb07d98b4a63e30f8e90c6ba1a24d4c2a9f5b4f21cd3370a`.
  Comandos, hashes de fuentes y artefacto permanecen en el directorio privado.

Los recibos propios del consumidor102/58 y Dragonex23 conservan su autoría y
alcance. El FULL2235/0/28 del3 de octubre es anterior a ambos deltas. No se repite
ni se presenta como aceptación del nuevo código. R9 continúa cerrado.

La publicación requiere HEX_API_KEY, tag y release oficial estable. Un push a
main sólo integra código; el workflow manual sólo hace preview. Ver releasing.md.
