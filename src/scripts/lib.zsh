# Shared helpers for the Slack quick switcher. Sourced by the other scripts.
#
# Runtime dependencies are limited to what ships with macOS:
# zsh, curl, /usr/bin/jq, security, iconv, osascript, open.

readonly BUNDLE_ID='com.wheirstrate.alfred-slack'
readonly KEYCHAIN_SERVICE='alfred-slack'
readonly KEYCHAIN_ACCOUNT='slack-user-token'
readonly SLACK_API='https://slack.com/api'

# Read-only scopes the token is allowed to carry. refresh.zsh refuses to run
# with a token that has anything beyond this set. "identify" is added to user
# tokens by Slack itself and only exposes the token owner's own identity.
readonly -a ALLOWED_SCOPES=(users:read channels:read groups:read mpim:read im:read identify)

# Alfred exports alfred_workflow_data; the LaunchAgent does not, so fall back
# to the same path Alfred would use.
DATA_DIR=${alfred_workflow_data:-$HOME/Library/Application Support/Alfred/Workflow Data/$BUNDLE_ID}
CACHE_FILE=$DATA_DIR/cache.json
STATUS_FILE=$DATA_DIR/status.json

ensure_data_dir() {
  umask 077
  mkdir -p -m 700 -- "$DATA_DIR" && chmod 700 "$DATA_DIR"
}

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2 }

# Lowercase, strip diacritics (NFD via UTF-8-MAC, then drop combining marks),
# keep [a-z0-9] runs separated by single spaces. One output line per input line.
fold_lines() {
  iconv -f UTF-8 -t UTF-8-MAC 2>/dev/null \
    | iconv -c -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
    | tr 'A-Z' 'a-z' \
    | tr -c 'a-z0-9\n' ' ' \
    | tr -s ' ' \
    | sed -e 's/^ //' -e 's/ $//'
}

# --- Keychain -----------------------------------------------------------------

token_exists() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1
}

token_read() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null
}

token_valid_format() {
  [[ $1 =~ '^xoxp-[A-Za-z0-9-]+$' ]]
}

# Stores $1 in the login keychain. The token is passed to `security` on stdin
# (interactive mode), never as a command-line argument visible in `ps`.
token_store() {
  token_valid_format "$1" || return 1
  print -r -- "add-generic-password -U -s $KEYCHAIN_SERVICE -a $KEYCHAIN_ACCOUNT -l \"Alfred Slack switcher (Slack user token)\" -w $1" \
    | security -i >/dev/null 2>&1
}

token_delete() {
  security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1
}

# --- Slack Web API ------------------------------------------------------------

# slack_get TOKEN_VAR METHOD [key=value ...]
#   Calls https://slack.com/api/METHOD with GET and url-encoded parameters.
#   Prints the JSON body on success. Respects Retry-After on HTTP 429 and
#   backs off on 5xx/network errors. On failure prints the Slack error code to
#   stderr and returns 1. Response headers of the last call are left in
#   $WORK_DIR/headers.txt.
#
#   The token is handed to curl via a config file on stdin (-K -) so it never
#   appears in argv or the environment of child processes.
slack_get() {
  local token=${(P)1} method=$2
  shift 2
  [[ $method =~ '^[a-z]+\.[a-zA-Z]+$' ]] || { log "bad method: $method"; return 1 }

  local -a params
  local kv
  for kv in "$@"; do params+=(--data-urlencode "$kv"); done

  local body=$WORK_DIR/body.json code retry err attempt=0
  local hdrs=$WORK_DIR/headers.txt

  while (( ++attempt <= 8 )); do
    code=$(print -r -- "header = \"Authorization: Bearer $token\"" \
      | curl -sS -K - --get --proto '=https' --tlsv1.2 --max-time 60 \
          -D "$hdrs" -o "$body" -w '%{http_code}' \
          "${params[@]}" "$SLACK_API/$method") || code=000

    case $code in
      200)
        if [[ $(jq -r '.ok' "$body" 2>/dev/null) == true ]]; then
          cat -- "$body"
          return 0
        fi
        err=$(jq -r '.error // "unknown_error"' "$body" 2>/dev/null)
        if [[ $err == ratelimited ]]; then
          sleep 30
          continue
        fi
        print -r -- "$err" >&2
        return 1
        ;;
      429)
        retry=$(grep -i '^retry-after:' "$hdrs" | tr -dc '0-9')
        log "rate limited on $method, waiting ${retry:-30}s"
        sleep $(( ${retry:-30} > 0 ? ${retry:-30} : 30 ))
        ;;
      000|5??)
        log "$method failed (HTTP $code), retrying"
        sleep $(( attempt * 5 ))
        ;;
      *)
        print -r -- "http_$code" >&2
        return 1
        ;;
    esac
  done
  print -r -- "retries_exhausted" >&2
  return 1
}

# slack_paged TOKEN_VAR METHOD JQ_ARRAY_KEY OUT_FILE [key=value ...]
#   Follows response_metadata.next_cursor and appends each element of
#   .JQ_ARRAY_KEY[] as one compact JSON line to OUT_FILE.
slack_paged() {
  local tokvar=$1 method=$2 key=$3 out=$4
  shift 4
  local cursor='' page
  while :; do
    page=$(slack_get "$tokvar" "$method" "$@" limit=200 ${cursor:+cursor=$cursor}) || return 1
    print -r -- "$page" | jq -c --arg k "$key" '.[$k][]?' >> "$out"
    cursor=$(print -r -- "$page" | jq -r '.response_metadata.next_cursor // ""')
    [[ -z $cursor ]] && break
  done
}
