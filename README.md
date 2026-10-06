# gh-pr-watcher

Notificaciones nativas de macOS que te avisan del estado de **tus** pull requests en GitHub: aprobaciones, cambios solicitados y comentarios nuevos. Se ejecuta cada 30 minutos (configurable) y solo avisa de lo nuevo desde la última revisión.

- ✅ PR aprobada (punto verde)
- ⚠️ Cambios solicitados (punto naranja)
- 💬 Comentario nuevo (punto azul), con autor y texto
- 👀 PR nueva pendiente de tu revisión (punto morado)
- ⏳ Recordatorio de las PRs que siguen pendientes de tu revisión (punto morado)

En cada ejecución salen como mucho dos notificaciones: una con las novedades de **tus PRs** (agrupadas por PR si hay varias) y otra con las **PRs pendientes de tu revisión** (las nuevas marcadas con 🆕).
- ⚪️ Sin novedades (punto gris)

Al pinchar la notificación se abre la PR en el navegador (o la lista de PRs pendientes de revisar si hay varias).

## Requisitos

- macOS
- [`gh`](https://cli.github.com/) autenticado: `gh auth login`
- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier): `brew install terminal-notifier`
- `jq` y `python3` (vienen de serie en macOS, pero `jq` puede faltar: `brew install jq`)

> La primera vez que se muestra una notificación, macOS pide permiso de notificaciones para *terminal-notifier*: hay que aceptarlo. Si no lo pide, actívalo en *Ajustes del sistema → Notificaciones → terminal-notifier*.

## Instalación

```bash
git clone https://github.com/<tu-usuario>/gh-pr-watcher.git
cd gh-pr-watcher
./install.sh
```

Esto genera los iconos, crea un agente de `launchd` y lo deja cargado. La primera ejecución solo establece la línea base en silencio; a partir de ahí difa contra ese estado y avisa de lo nuevo.

## Configuración

Se configura con variables de entorno (opcional, todas tienen valores por defecto):

| Variable | Por defecto | Descripción |
| --- | --- | --- |
| `PR_WATCHER_DIR` | `~/.pr-watcher` | Dónde se guardan el estado, los iconos y el log |
| `PR_WATCHER_START_HOUR` | `9` | Hora a partir de la que avisa (0–23) |
| `PR_WATCHER_END_HOUR` | `19` | Hora a partir de la que deja de avisar (excluida) |
| `PR_WATCHER_INTERVAL` | `1800` | Intervalo del agente en segundos (1800 = 30 min). Solo lo lee `install.sh`. |
| `PR_WATCHER_FILTER_OWN` | `1` | `1` = ignora tus propios comentarios/reviews, `0` = los muestra |
| `PR_WATCHER_FILTER_BOTS` | `1` | `1` = ignora cuentas de tipo `Bot` (github-actions, dependabot…), `0` = las muestra |
| `PR_WATCHER_COMMENT_LEN` | `200` | Longitud máxima del texto del comentario en la notificación |
| `PR_WATCHER_REVIEW_REMINDER` | `1` | `1` = en cada ejecución recuerda las PRs que siguen pendientes de tu revisión, `0` = solo avisa de las nuevas |
| `PR_WATCHER_NOTIFY_GAP` | `60` | Segundos de espera entre las dos notificaciones de una misma ejecución (si llegan a la vez, macOS solo muestra la última) |

Ejemplos:

```bash
# Avisar 24 h (sin horario) y mostrar también bots:
PR_WATCHER_START_HOUR=0 PR_WATCHER_END_HOUR=24 PR_WATCHER_FILTER_BOTS=0 ./install.sh
```

Nota: el horario lo lee `pr-watch.sh` en cada ejecución (no `install.sh`). Para cambiar el horario de una instalación ya hecha, edita el agente (`~/Library/LaunchAgents/gh-pr-watcher.plist`) o vuelve a ejecutar `install.sh` con las variables que quieras y luego recarga.

## Uso manual

Para una ejecución puntual (sin agente):

```bash
./pr-watch.sh
```

## Desinstalar

```bash
launchctl unload -w ~/Library/LaunchAgents/gh-pr-watcher.plist
rm ~/Library/LaunchAgents/gh-pr-watcher.plist
rm -rf ~/.pr-watcher
```

## Cómo funciona

1. Consulta por GraphQL todas tus PRs abiertas (`is:pr is:open author:@me`) junto con sus reviews y comentarios.
2. Guarda en `state.json` los IDs ya vistos (reviews y comentarios) por PR.
3. En cada ejecución difa el estado actual contra el guardado y emite un evento por novedad (aprobada / cambios / comentario).
4. Consulta también las PRs abiertas que esperan tu revisión (`review-requested:@me`, incluye peticiones a tus equipos) y guarda en `review-state.json` las ya avisadas: avisa de las nuevas y, en cada ejecución, recuerda las que siguen pendientes.
5. Notifica con `terminal-notifier`; al pinchar se abre la URL de la PR.

## Limitaciones

- macOS no permite cambiar el color de fondo del banner de la notificación; el punto de color se muestra como imagen (`contentImage`).
- El texto del comentario se recorta a `PR_WATCHER_COMMENT_LEN` caracteres porque las notificaciones nativas tienen un tamaño limitado.
- Solo vigila PRs **abiertas**: las que has creado tú y las que esperan tu revisión.

## Licencia

[MIT](LICENSE)
