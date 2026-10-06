#!/usr/bin/env bash
#
# gh-pr-watcher — revisa las PRs abiertas que has creado y te notifica (macOS)
# aprobaciones, cambios solicitados y comentarios nuevos desde la última ejecución,
# además de las PRs que esperan tu revisión (nuevas y las que siguen pendientes).
#
# Dependencias: gh, jq, terminal-notifier, python3 (para los iconos, opcional).
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ---- Configuración (se puede sobreescribir con variables de entorno) ----
PR_WATCHER_DIR="${PR_WATCHER_DIR:-$HOME/.pr-watcher}"       # estado e iconos
START_HOUR="${PR_WATCHER_START_HOUR:-9}"                    # avisar desde esta hora
END_HOUR="${PR_WATCHER_END_HOUR:-19}"                       # avisar hasta esta hora (excluida)
FILTER_OWN="${PR_WATCHER_FILTER_OWN:-1}"                    # 1 = ignorar tus propios comentarios/reviews
FILTER_BOTS="${PR_WATCHER_FILTER_BOTS:-1}"                  # 1 = ignorar cuentas de tipo Bot
COMMENT_LEN="${PR_WATCHER_COMMENT_LEN:-200}"                # longitud máx. del resumen del comentario
REVIEW_REMINDER="${PR_WATCHER_REVIEW_REMINDER:-1}"          # 1 = recordar las PRs que siguen pendientes de tu revisión
NOTIFY_GAP="${PR_WATCHER_NOTIFY_GAP:-60}"                   # segundos entre notificaciones de una misma ejecución
# ------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOUR=$(date +%H); HOUR=${HOUR#0}
if (( HOUR < START_HOUR || HOUR >= END_HOUR )); then
  exit 0
fi

DIR="$PR_WATCHER_DIR"
STATE_FILE="$DIR/state.json"
LATEST_FILE="$DIR/latest.json"
REVIEW_STATE_FILE="$DIR/review-state.json"
LOG_FILE="$DIR/pr-watch.log"
ICONS="$DIR/icons"
mkdir -p "$DIR" "$ICONS"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

for dep in gh jq; do
  command -v "$dep" >/dev/null 2>&1 || { log "ERROR: no encuentro '$dep'. Instálalo antes."; exit 1; }
done
TN="$(command -v terminal-notifier || true)"
[[ -n "$TN" ]] || { log "ERROR: no encuentro 'terminal-notifier' (brew install terminal-notifier)."; exit 1; }

# Iconos de estado: se generan la primera vez (con python3) si no existen.
if [[ ! -f "$ICONS/approved.png" || ! -f "$ICONS/none.png" || ! -f "$ICONS/review.png" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/make-icons.py" "$ICONS" >>"$LOG_FILE" 2>&1 || true
  fi
fi

GRAPHQL_QUERY='
query($q: String!) {
  search(query: $q, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        url
        number
        title
        repository { nameWithOwner }
        reviews(first: 20) { nodes { id state body author { login __typename } } }
        comments(first: 30) { nodes { id body author { login __typename } } }
        reviewThreads(first: 20) { nodes { comments(first: 20) { nodes { id body author { login __typename } } } } }
      }
    }
  }
}'

LOGIN=$(gh api user --jq '.login' 2>>"$LOG_FILE") || { log "ERROR: no pude obtener el login (gh auth login)."; exit 1; }

gh api graphql -f query="$GRAPHQL_QUERY" -f q="is:pr is:open author:$LOGIN" \
  --jq '
    .data.search.nodes
    | map({
        key: (.repository.nameWithOwner + "#" + (.number | tostring)),
        url: .url,
        number: .number,
        title: .title,
        repo: .repository.nameWithOwner,
        reviews: [.reviews.nodes[]? | {id: .id, state: .state, body: (.body // ""), author: (.author.login // "unknown"), bot: (.author.__typename == "Bot")}],
        comments: [.comments.nodes[]? | {id: .id, body: .body, author: (.author.login // "unknown"), bot: (.author.__typename == "Bot")}],
        threadComments: [.reviewThreads.nodes[]?.comments.nodes[]? | {id: .id, body: .body, author: (.author.login // "unknown"), bot: (.author.__typename == "Bot")}]
      })
  ' > "$LATEST_FILE" 2>>"$LOG_FILE" || { log "ERROR: falló la consulta graphql."; exit 1; }

REVIEW_QUERY='
query($q: String!) {
  search(query: $q, type: ISSUE, first: 50) {
    nodes { ... on PullRequest { url number title repository { nameWithOwner } author { login } } }
  }
}'

REVIEW_REQUESTS=$(gh api graphql -f query="$REVIEW_QUERY" -f q="is:pr is:open archived:false review-requested:$LOGIN" \
  --jq '[.data.search.nodes[] | {key: (.repository.nameWithOwner + "#" + (.number | tostring)), url, number, title, repo: .repository.nameWithOwner, author: (.author.login // "unknown")}]' \
  2>>"$LOG_FILE") || { log "ERROR: falló la consulta de revisiones pendientes."; REVIEW_REQUESTS=""; }

jq 'reduce .[] as $p ({}; .[$p.key] = { reviewIds: [$p.reviews[].id], commentIds: ([$p.comments[].id] + [$p.threadComments[].id]) })' \
  "$LATEST_FILE" > "$DIR/.state.new.json"

if [[ ! -s "$STATE_FILE" ]]; then
  mv "$DIR/.state.new.json" "$STATE_FILE"
  log "baseline inicializada ($(jq 'length' "$LATEST_FILE") PRs abiertas); sin notificar"
  exit 0
fi

EVENTS=$(jq -c \
  --arg login "$LOGIN" \
  --argjson filter_own "$FILTER_OWN" \
  --argjson filter_bots "$FILTER_BOTS" \
  --argjson comment_len "$COMMENT_LEN" \
  --slurpfile st "$STATE_FILE" '
  . as $latest
  | ($st[0]) as $known
  | def exclude_self: (($filter_own | not) or .author != $login) and (($filter_bots | not) or .bot != true);
  [ $latest[] |
      ($known[.key] // {}) as $prev
      | ($prev.reviewIds // []) as $knownReviews
      | ($prev.commentIds // []) as $knownComments
      | ([ .reviews[] | select(.id as $id | $knownReviews | index($id) | not) | select(exclude_self) ]) as $newReviews
      | ([ .comments[] | select(.id as $id | $knownComments | index($id) | not) | select(exclude_self) ]) as $newIssueComments
      | ([ .threadComments[] | select(.id as $id | $knownComments | index($id) | not) | select(exclude_self) ]) as $newThreadComments
      | ($newReviews | map(select(.state == "APPROVED"))) as $approved
      | ($newReviews | map(select(.state == "CHANGES_REQUESTED"))) as $changes
      | ($newReviews | map(select(.state == "COMMENTED"))) as $reviewBody
      | select((($approved | length) + ($changes | length) + ($newIssueComments | length) + ($newThreadComments | length) + ($reviewBody | length)) > 0)
      | .number as $n | .repo as $r | .title as $t | .url as $u
      | (
          ($approved[] | {type: "approved", pr: $n, repo: $r, title: $t, url: $u, author: .author, body: ((.body // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:$comment_len])}),
          ($changes[]  | {type: "changes",  pr: $n, repo: $r, title: $t, url: $u, author: .author, body: ((.body // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:$comment_len])}),
          ($newIssueComments[] | {type: "comment", pr: $n, repo: $r, title: $t, url: $u, author: .author, body: ((.body // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:$comment_len])}),
          ($newThreadComments[] | {type: "comment", pr: $n, repo: $r, title: $t, url: $u, author: .author, body: ((.body // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:$comment_len])}),
          ($reviewBody[] | {type: "comment", pr: $n, repo: $r, title: $t, url: $u, author: .author, body: ((.body // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:$comment_len])})
        )
    ]
' "$LATEST_FILE" 2>>"$LOG_FILE")

NOTIFIED=0
notify() {
  # macOS solapa los banners de la misma app que llegan a la vez y solo se ve el último.
  (( NOTIFIED++ > 0 )) && sleep "$NOTIFY_GAP"
  local ttl="$1" sub="$2" msg="$3" icon="$4" url="${5:-}" group="$6"
  local img_args=()
  [[ -f "$icon" ]] && img_args=(-contentImage "$icon")
  local open_args=()
  [[ -n "$url" ]] && open_args=(-open "$url")
  "$TN" -title "$ttl" -subtitle "$sub" -message "$msg" -sound Glass -group "$group" \
    ${img_args[@]+"${img_args[@]}"} ${open_args[@]+"${open_args[@]}"} >>"$LOG_FILE" 2>&1 \
    && log "notificado: $ttl | $sub | $msg" \
    || log "ERROR al notificar: $ttl"
}

# Como mucho dos notificaciones por ejecución: novedades en tus PRs y PRs pendientes de tu revisión.
plural() { (( $1 == 1 )) && echo "$1 $2" || echo "$1 $3"; }

n_events=$(jq 'length' <<<"${EVENTS:-[]}" 2>/dev/null || echo 0)
if (( n_events == 1 )); then
  ev=$(jq -c '.[0]' <<<"$EVENTS")
  type=$(jq -r '.type' <<<"$ev")
  pr=$(jq -r '.pr' <<<"$ev")
  repo=$(jq -r '.repo' <<<"$ev")
  title=$(jq -r '.title' <<<"$ev")
  url=$(jq -r '.url' <<<"$ev")
  author=$(jq -r '.author' <<<"$ev")
  body=$(jq -r '.body // ""' <<<"$ev")

  case "$type" in
    approved)
      ttl="✅ PR #$pr aprobada"
      sub="$repo · $author"
      msg="$title"
      [[ -n "$body" ]] && msg="$title — $body"
      icon="$ICONS/approved.png"
      ;;
    changes)
      ttl="⚠️ PR #$pr — cambios solicitados"
      sub="$repo · $author"
      msg="$title"
      [[ -n "$body" ]] && msg="$title — $body"
      icon="$ICONS/changes.png"
      ;;
    comment)
      ttl="💬 Comentario en PR #$pr"
      sub="$repo · $author"
      msg="$body"
      icon="$ICONS/comment.png"
      ;;
  esac
  notify "$ttl" "$sub" "$msg" "$icon" "$url" "pr-watcher-own"
elif (( n_events > 1 )); then
  n_approved=$(jq '[.[] | select(.type == "approved")] | length' <<<"$EVENTS")
  n_changes=$(jq '[.[] | select(.type == "changes")] | length' <<<"$EVENTS")
  n_comments=$(jq '[.[] | select(.type == "comment")] | length' <<<"$EVENTS")
  parts=()
  (( n_changes > 0 )) && parts+=("$(plural "$n_changes" "con cambios" "con cambios")")
  (( n_approved > 0 )) && parts+=("$(plural "$n_approved" "aprobada" "aprobadas")")
  (( n_comments > 0 )) && parts+=("$(plural "$n_comments" "comentario" "comentarios")")
  sub=$(IFS='|'; echo "${parts[*]}" | sed 's/|/ · /g')

  msg=$(jq -r '
    group_by(.pr) | map(
      "#" + (.[0].pr | tostring) + " " + .[0].title + ": "
      + ([ (map(select(.type == "changes")) | length | select(. > 0) | "⚠️ cambios"),
           (map(select(.type == "approved")) | length | select(. > 0) | "✅ aprobada"),
           (map(select(.type == "comment")) | length | select(. > 0) | "💬 " + tostring) ] | join(" "))
    ) | join("\n")' <<<"$EVENTS")

  n_prs=$(jq '[.[].url] | unique | length' <<<"$EVENTS")
  url="https://github.com/pulls"
  (( n_prs == 1 )) && url=$(jq -r '.[0].url' <<<"$EVENTS")

  icon="$ICONS/comment.png"
  (( n_approved > 0 )) && icon="$ICONS/approved.png"
  (( n_changes > 0 )) && icon="$ICONS/changes.png"

  notify "📬 Tus PRs · $(plural "$n_events" "novedad" "novedades")" "$sub" "$msg" "$icon" "$url" "pr-watcher-own"
fi

TO_REVIEW="[]"
if [[ -n "$REVIEW_REQUESTS" ]]; then
  known_reviews="[]"
  [[ -s "$REVIEW_STATE_FILE" ]] && known_reviews=$(cat "$REVIEW_STATE_FILE")
  TO_REVIEW=$(jq -c --argjson known "$known_reviews" --argjson reminder "$REVIEW_REMINDER" '
    map(. + {new: (.key as $k | $known | index($k) | not)})
    | map(select(.new or $reminder == 1))
    | sort_by(.new | not)' <<<"$REVIEW_REQUESTS")
  jq -c 'map(.key)' <<<"$REVIEW_REQUESTS" > "$REVIEW_STATE_FILE"
fi

n_review=$(jq 'length' <<<"$TO_REVIEW")
if (( n_review == 1 )); then
  r=$(jq -c '.[0]' <<<"$TO_REVIEW")
  if [[ $(jq -r '.new' <<<"$r") == "true" ]]; then ttl="👀 Te han pedido revisión"; else ttl="⏳ Pendiente de tu revisión"; fi
  notify "$ttl: PR #$(jq -r '.number' <<<"$r")" \
    "$(jq -r '.repo + " · " + .author' <<<"$r")" \
    "$(jq -r '.title' <<<"$r")" \
    "$ICONS/review.png" "$(jq -r '.url' <<<"$r")" "pr-watcher-review"
elif (( n_review > 1 )); then
  n_new=$(jq 'map(select(.new)) | length' <<<"$TO_REVIEW")
  n_old=$(( n_review - n_new ))
  parts=()
  (( n_new > 0 )) && parts+=("$(plural "$n_new" "nueva" "nuevas")")
  (( n_old > 0 )) && parts+=("$(plural "$n_old" "sin revisar" "sin revisar")")
  sub=$(IFS='|'; echo "${parts[*]}" | sed 's/|/ · /g')
  msg=$(jq -r 'map((if .new then "🆕 " else "" end) + "#" + (.number | tostring) + " " + .title + " (" + .author + ")") | join("\n")' <<<"$TO_REVIEW")
  notify "👀 $n_review PRs pendientes de tu revisión" "$sub" "$msg" \
    "$ICONS/review.png" "https://github.com/pulls/review-requested" "pr-watcher-review"
fi

if (( n_events == 0 && n_review == 0 )); then
  total=$(jq 'length' "$LATEST_FILE")
  sub="$(plural "$total" "PR abierta" "PRs abiertas")"
  [[ -n "$REVIEW_REQUESTS" ]] && sub="$sub · $(jq 'length' <<<"$REVIEW_REQUESTS") pendientes de revisar"
  notify "Sin novedades" "$sub" "Nada nuevo desde la última revisión" "$ICONS/none.png" "" "pr-watcher-none"
fi

mv "$DIR/.state.new.json" "$STATE_FILE"
