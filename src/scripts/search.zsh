#!/bin/zsh --no-rcs
# Alfred Script Filter. Reads only the local cache; never touches the network
# or the token.

emulate -L zsh
source "${0:A:h}/lib.zsh"

query=${1:-}

# Emits a single non-actionable or command item and exits.
emit() {  # emit TITLE SUBTITLE ICON [ACTION]
  jq -n --arg t "$1" --arg s "$2" --arg i "$3" --arg a "${4:-}" '
    {items: ([{title: $t, subtitle: $s, icon: {path: $i}, valid: ($a != ""),
               arg: $a, variables: {action: $a}}]
             + (if $a != "token" then [{title: "Set Slack token",
                  subtitle: "Store or replace the xoxp user token in the macOS Keychain",
                  valid: true, arg: "token", variables: {action: "token"},
                  icon: {path: "icons/key.png"}}] else [] end))}'
  exit 0
}

# Fail closed: an auth problem from the last refresh hides all results.
if [[ -r $STATUS_FILE ]]; then
  read -r ok err msg < <(jq -r '[.ok, .error, .message] | @tsv' "$STATUS_FILE" 2>/dev/null)
  if [[ $ok == false ]]; then
    case $err in
      no_token|bad_token|invalid_auth|not_authed|token_revoked|token_expired|account_inactive|excess_scopes|no_scopes|bad_auth)
        emit "Slack token problem" "$msg" icons/warning.png token ;;
    esac
  fi
fi

if [[ ! -r $CACHE_FILE ]]; then
  if token_exists; then
    emit "No Slack cache yet" "Press ↩ to fetch people, group chats and channels now" icons/refresh.png refresh
  else
    emit "No Slack token set" "Press ↩ to store your xoxp user token in the Keychain" icons/key.png token
  fi
fi

folded=$(print -r -- "$query" | fold_lines)
if [[ -n $folded ]]; then
  q=$folded fuzzy=true
else
  q=${(L)query} fuzzy=false
fi

jq -c --arg q "$q" --argjson fuzzy "$fuzzy" --argjson now "$(date +%s)" \
  -f "${0:A:h}/search.jq" "$CACHE_FILE" \
  || emit "Slack cache is unreadable" "Press ↩ to rebuild it" icons/warning.png refresh
