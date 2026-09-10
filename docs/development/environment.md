# Entorno local y tooling

Esta página describe el entorno de desarrollo observado en este workspace, no
requisitos para todos los consumidores del paquete. Las versiones aceptadas están
en [estado](../status.md); los gates, en [verificación](verification.md).

## Incidente pendiente de reparación

Durante el bootstrap nocturno se heredó `MIX_ARCHIVES` aunque `MIX_HOME` apuntaba
a `/tmp`. Un worker sustituyó el Hex2.5.1 compartido de Elixir1.20 por BEAM que no
cargaba en OTP29. Fue una escritura accidental fuera del alcance. Se detuvo, se
corrigió el runner y se verificó después con entornos aislados.

El archivo afectado pertenece a:
`/home/kukapu/.local/share/mise/installs/elixir/1.20.0/.mix/archives`.
No se encontró una copia previa exacta y **no se ha reparado el Hex compartido**.
Su reparación requiere autorización explícita. No ejecutar `mix local.hex --force`
contra un entorno heredado para intentar resolverlo silenciosamente.

## Trabajar sin depender de ese Hex

En este host se verificó el siguiente prefijo por comando. El PATH directo evita
un shim `erl` que puede reactivar mise y sobrescribir los overrides:

```bash
env -u MIX_EXS -u MIX_PATH -u MIX_INSTALL_RESTORE_PROJECT_DIR \
  PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin \
  MIX_HOME=/tmp/opencode/exagent-native-otlp-mix \
  MIX_ARCHIVES=/tmp/opencode/exagent-native-otlp-mix/archives \
  EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
```

Es tooling temporal ya preparado, no una instalación global. Comprobar que los
paths sigan existiendo y que el proceso hijo observe las versiones/destinos
esperados. Los artefactos `/tmp` pueden desaparecer; entonces preparar tooling
oficial de nuevo, sólo en un destino aislado autorizado y después del preflight.

## Aislamiento para matrices

El runner `test/support/package_acceptance.exs` fija selectores de proyecto,
homes/archives, cachés y paths de dependencias/build. Comprueba el entorno efectivo
dentro del hijo antes de CLI y usa un directorio nuevo real, hijo directo de
`/tmp/opencode`, con prefijo `exagent-night-package`.

- No compartir fuentes compilables/cachés Rebar entre runtimes concurrentes sólo
  porque `MIX_BUILD_PATH` sea distinto.
- No leer ni volcar `.env`, credenciales o capabilities en informes. Los drivers
  finales usaron un conjunto explícito de variables, no una copia del entorno host.
- No compilar fuentes compartidas mientras otro autor las está editando.
- No usar `--no-compile` como aceptación de fuentes cambiadas.
- Mantener el historial de fallos y distinguir diagnósticos del proyecto, de
  dependencias y logs operacionales esperados.

Los toolchains adicionales de la noche viven en
`/tmp/opencode/exagent-night-package-toolchain/`: Elixir1.17.3 y OTP27.3.4.17, con
orígenes oficiales y hashes registrados. No se modificó mise global ni los runtimes
del host para instalarlos. Los builds finales separados están en
`/tmp/opencode/exagent-night-final-n18/{native,118,117}/`.
