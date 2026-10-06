# Contribuir

¡Gracias por el interés! El proyecto es pequeño y de un solo fichero de lógica, así que contribuir es fácil.

## Requisitos del entorno

- macOS (usa `terminal-notifier` y `launchd`, que solo existen en macOS)
- `gh` autenticado (`gh auth login`)
- `terminal-notifier`, `jq`, `python3`

## Ejecutar en local

```bash
# Ejecución única con un directorio de estado temporal (no toca ~/.pr-watcher):
PR_WATCHER_DIR="$(mktemp -d)" ./pr-watch.sh
```

La primera ejecución establece la línea base en silencio; la segunda (sin cambios) debería notificar "Sin novedades".

## Regla importante: compatibilidad con bash 3.2

`launchd` ejecuta el script con `/bin/bash`, que en macOS es **bash 3.2**. No uses
características de bash 4+ (arrays asociativos, `mapfile`, `declare -n`, `readarray`, etc.).
En particular, con `set -u` el idiomá seguro para arrays opcionales es
`${arr[@]+"${arr[@]}"}`, no `"${arr[@]}"`.

## Estilo

- Sigue el estilo existente (2 espacios de indentación en `jq`, variables en mayúsculas).
- Mantén la lógica en `pr-watch.sh`; `make-icons.py` solo genera los iconos; `install.sh` solo instala.
- La configuración se expone como variables de entorno con prefijo `PR_WATCHER_` (documentalas en el README si añades alguna).

## Pruebas

```bash
# Sintaxis
bash -n pr-watch.sh install.sh

# Lint (ShellCheck)
shellcheck pr-watch.sh install.sh
```

El CI ejecuta ShellCheck en cada PR.

## Proceso

1. Abre un issue describiendo el cambio si es una funcionalidad nueva.
2. Haz fork, crea una rama y el PR contra `main`.
3. Explica en la descripción qué cambia y cómo probarlo.
4. El CI debe pasar (ShellCheck).

## Cómo funciona (resumen)

1. `pr-watch.sh` consulta por GraphQL tus PRs abiertas (`is:pr is:open author:@me`) con reviews y comentarios.
2. Guarda en `state.json` los IDs ya vistos.
3. En cada ejecución difa contra ese estado y emite un evento por novedad.
4. Notifica con `terminal-notifier`; al pinchar se abre la URL de la PR.
