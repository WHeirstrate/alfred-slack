#!/bin/zsh --no-rcs
# Rebuilds the local cache of people, group chats and channels from the Slack
# Web API. Runs from the LaunchAgent (daily) or from Alfred ("sl refresh").
#
# This is the only script that talks to the network, and only to slack.com.
# On success it prints a one-line summary on stdout (used for the Alfred
# notification); diagnostics go to stderr.

emulate -L zsh
setopt no_unset
umask 077

source "${0:A:h}/lib.zsh"

# Workflow variable (Alfred) or env var (LaunchAgent): include bot users.
INCLUDE_BOTS=${include_bots:-${ALFRED_SLACK_INCLUDE_BOTS:-0}}

ensure_data_dir || { log "cannot create $DATA_DIR"; print -r -- "Slack refresh failed: cannot create the data directory."; exit 1 }

write_status() {  # write_status OK ERROR MESSAGE
  local tmp=$DATA_DIR/.status.$$
  jq -n --argjson ok "$1" --arg error "$2" --arg message "$3" \
    '{ok: $ok, error: $error, message: $message, at: (now | floor)}' > "$tmp"
  mv -f -- "$tmp" "$STATUS_FILE"
}

fail() {  # fail ERROR MESSAGE
  write_status false "$1" "$2"
  log "refresh failed: $1 — $2"
  print -r -- "Slack refresh failed: $2"
  exit 1
}

# One refresh at a time (manual + scheduled could overlap).
LOCK_DIR=$DATA_DIR/.refresh.lock
if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
  # Stale lock older than 30 minutes: take it over.
  if [[ -n $(find "$LOCK_DIR" -maxdepth 0 -mmin +30 2>/dev/null) ]]; then
    rm -rf -- "$LOCK_DIR"
    mkdir -- "$LOCK_DIR"
  else
    print -r -- "A Slack refresh is already running."
    exit 0
  fi
fi

trap 'rm -rf -- "${WORK_DIR:-}" "$LOCK_DIR"' EXIT INT TERM
WORK_DIR=$(mktemp -d "$DATA_DIR/.work.XXXXXX") || fail io_error "Cannot create a temporary directory."

# --- Token --------------------------------------------------------------------

typeset SLACK_TOKEN
SLACK_TOKEN=$(token_read) || true
[[ -n $SLACK_TOKEN ]] || fail no_token "No Slack token in the Keychain. Run “sl token” to set one."
token_valid_format "$SLACK_TOKEN" || fail bad_token "The stored token is not a Slack user token (xoxp-…)."

auth=$(slack_get SLACK_TOKEN auth.test 2>"$WORK_DIR/err") \
  || fail "$(tail -n1 "$WORK_DIR/err")" "Slack rejected the token ($(tail -n1 "$WORK_DIR/err")). Run “sl token” to replace it."

# Fail closed if the token carries anything beyond the read-only scope set.
granted=$(grep -i '^x-oauth-scopes:' "$WORK_DIR/headers.txt" | cut -d: -f2- | tr -d ' \r')
[[ -n $granted ]] || fail no_scopes "Slack did not report the token's scopes; refusing to continue."
extra=()
for scope in ${(s:,:)granted}; do
  (( ${ALLOWED_SCOPES[(Ie)$scope]} )) || extra+=$scope
done
(( ${#extra} == 0 )) || fail excess_scopes "Token has scopes beyond the read-only set: ${(j:, :)extra}. Remove them in the Slack app config and reinstall."

TEAM_ID=$(print -r -- "$auth" | jq -r '.team_id')
SELF_ID=$(print -r -- "$auth" | jq -r '.user_id')
TEAM_NAME=$(print -r -- "$auth" | jq -r '.team // ""')
[[ $TEAM_ID =~ '^[A-Z0-9]+$' && $SELF_ID =~ '^[A-Z0-9]+$' ]] || fail bad_auth "Unexpected auth.test response."

log "refreshing workspace $TEAM_ID"

# Only names and IDs are kept from user objects.
USER_FIELDS='{id, team_id, name, real_name: (.profile.real_name // .real_name // ""), display_name: (.profile.display_name // ""), deleted: (.deleted // false), is_bot: ((.is_bot // false) or .id == "USLACKBOT")}'

# --- Workspace members --------------------------------------------------------

slack_paged SLACK_TOKEN users.list members "$WORK_DIR/users.raw" 2>"$WORK_DIR/err" \
  || fail "$(tail -n1 "$WORK_DIR/err")" "users.list failed ($(tail -n1 "$WORK_DIR/err"))."
jq -c "$USER_FIELDS" "$WORK_DIR/users.raw" > "$WORK_DIR/users.jsonl"
rm -f -- "$WORK_DIR/users.raw"

# --- Conversations ------------------------------------------------------------

slack_paged SLACK_TOKEN conversations.list channels "$WORK_DIR/convs.raw" \
    types=public_channel,private_channel,mpim,im exclude_archived=true 2>"$WORK_DIR/err" \
  || fail "$(tail -n1 "$WORK_DIR/err")" "conversations.list failed ($(tail -n1 "$WORK_DIR/err"))."
jq -c '{id, name: (.name // ""), user: (.user // ""),
        is_im: (.is_im // false), is_mpim: (.is_mpim // false),
        is_private: (.is_private // false), is_member: (.is_member // false),
        is_ext_shared: (.is_ext_shared // false), is_shared: (.is_shared // false),
        is_user_deleted: (.is_user_deleted // false), num_members: (.num_members // null)}' \
  "$WORK_DIR/convs.raw" > "$WORK_DIR/convs.jsonl"
rm -f -- "$WORK_DIR/convs.raw"

# Members of group chats, and of shared channels I am in (to find Slack Connect
# people, who are not returned by users.list).
: > "$WORK_DIR/members.jsonl"
jq -r 'select(.is_mpim or (.is_member and (.is_ext_shared or .is_shared) and (.is_im | not))) | .id' \
  "$WORK_DIR/convs.jsonl" | while read -r cid; do
    : > "$WORK_DIR/m.jsonl"
    if slack_paged SLACK_TOKEN conversations.members members "$WORK_DIR/m.jsonl" channel="$cid" 2>"$WORK_DIR/err"; then
      jq -c --arg c "$cid" '{conv: $c, user: .}' "$WORK_DIR/m.jsonl" >> "$WORK_DIR/members.jsonl"
    else
      log "conversations.members $cid: $(tail -n1 "$WORK_DIR/err") (skipped)"
    fi
  done

# --- Resolve unknown users (Slack Connect) ------------------------------------

: > "$WORK_DIR/external.jsonl"
jq -rn --slurpfile u "$WORK_DIR/users.jsonl" \
       --slurpfile c "$WORK_DIR/convs.jsonl" \
       --slurpfile m "$WORK_DIR/members.jsonl" '
  ($u | map({key: .id, value: true}) | from_entries) as $known
  | ([$c[] | select(.is_im and (.is_user_deleted | not)) | .user] + [$m[].user])
  | unique | .[] | select(. != "" and ($known[.] | not))' \
  | while read -r uid; do
      if info=$(slack_get SLACK_TOKEN users.info user="$uid" 2>"$WORK_DIR/err"); then
        print -r -- "$info" | jq -c ".user | $USER_FIELDS" >> "$WORK_DIR/external.jsonl"
      else
        log "users.info $uid: $(tail -n1 "$WORK_DIR/err") (skipped)"
      fi
    done

# --- Build Alfred items -------------------------------------------------------

jq -n \
  --slurpfile users "$WORK_DIR/users.jsonl" \
  --slurpfile ext "$WORK_DIR/external.jsonl" \
  --slurpfile convs "$WORK_DIR/convs.jsonl" \
  --slurpfile members "$WORK_DIR/members.jsonl" \
  --arg team "$TEAM_ID" --arg self "$SELF_ID" \
  --argjson bots "$(( INCLUDE_BOTS ? 1 : 0 ))" \
  -f "${0:A:h}/build.jq" > "$WORK_DIR/items.json" \
  || fail build_error "Could not build the item list (see ~/Library/Logs/alfred-slack.log)."

# Diacritic-free search keys, folded in one pass and zipped back by index:
# two lines per item (title, then all searchable names).
jq -r '.[] | (.title, .k) | gsub("[\n\r]"; " ")' "$WORK_DIR/items.json" \
  | fold_lines > "$WORK_DIR/keys.txt" || true

# k keeps the original lowercased names too, so non-Latin names stay searchable.
jq -n --slurpfile items "$WORK_DIR/items.json" \
      --rawfile keys "$WORK_DIR/keys.txt" \
      --arg team "$TEAM_ID" --arg team_name "$TEAM_NAME" '
  ($keys | split("\n")) as $f
  | {version: 1, team_id: $team, team_name: $team_name, generated_at: (now | floor),
     items: [$items[0] | to_entries[] | (.key * 2) as $i | .value + {
       tk: ($f[$i] // ""),
       k: (($f[$i + 1] // "") + " " + (.value.k | ascii_downcase))
     }]}' > "$WORK_DIR/cache.json" \
  || fail build_error "Could not write the cache."

chmod 600 "$WORK_DIR/cache.json"
mv -f -- "$WORK_DIR/cache.json" "$CACHE_FILE"

summary=$(jq -r '.items | group_by(.type) | map("\(length) \(.[0].type)") | join(", ")' "$CACHE_FILE")
write_status true "" "$summary"
log "refresh ok: $summary"
print -r -- "Slack cache refreshed: $summary"
