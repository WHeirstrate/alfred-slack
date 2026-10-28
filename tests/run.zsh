#!/bin/zsh --no-rcs
# Offline end-to-end tests: refresh -> cache -> search, against fixtures.
# curl and security are replaced by the doubles in tests/bin; nothing here
# touches the network or the real Keychain.
#
#   zsh tests/run.zsh

emulate -L zsh
root=${0:A:h:h}
scripts=$root/src/scripts

export FAKE_STATE=$(mktemp -d)
export alfred_workflow_data=$FAKE_STATE/data
export PATH=$root/tests/bin:$PATH
trap 'rm -rf -- "$FAKE_STATE"' EXIT

pass=0 failed=0
check() {  # check DESCRIPTION COMMAND...
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    (( ++pass ))
  else
    (( ++failed ))
    print -r -- "FAIL: $desc"
  fi
}
search() { "$scripts/search.zsh" "$1" }
titles() { search "$1" | jq -r '.items[].title' }
first_arg() { search "$1" | jq -r '.items[0].arg' }

# --- No token ---------------------------------------------------------------
check "search without token offers token item" \
  test "$(search jer | jq -r '.items[0].variables.action')" = token
"$scripts/refresh.zsh" >/dev/null 2>&1
check "refresh without token fails closed" \
  test "$(jq -r .error "$alfred_workflow_data/status.json")" = no_token
check "search after no_token refresh shows only the error" \
  test "$(search jer | jq -r '.items[0].title')" = "Slack token problem"

# --- Token handling ---------------------------------------------------------
print -r -- 'not-a-token' | "$scripts/token.zsh" set --stdin >/dev/null 2>&1
check "malformed token is rejected" test ! -e "$FAKE_STATE/keychain"
print -r -- 'xoxp-1111-2222-abcdef' | "$scripts/token.zsh" set --stdin >/dev/null 2>&1
check "token stored via stdin" test "$(cat "$FAKE_STATE/keychain")" = 'xoxp-1111-2222-abcdef'
check "token set clears stale auth status" test ! -e "$alfred_workflow_data/status.json"
rm -f "$alfred_workflow_data/status.json"

# --- Excess scopes ----------------------------------------------------------
FAKE_SCOPES=users:read,chat:write "$scripts/refresh.zsh" >/dev/null 2>&1
check "token with write scope is refused" \
  test "$(jq -r .error "$alfred_workflow_data/status.json")" = excess_scopes
check "no cache written with excess scopes" test ! -e "$alfred_workflow_data/cache.json"

# --- Successful refresh (with one 429) --------------------------------------
out=$(FAKE_429_ONCE=users.list FAKE_SCOPES=identify,users:read,channels:read,groups:read,mpim:read,im:read \
  "$scripts/refresh.zsh" 2>/dev/null)
check "refresh succeeds after a 429" test "$(jq -r .ok "$alfred_workflow_data/status.json")" = true
check "refresh prints summary" test "${out[1,22]}" = "Slack cache refreshed:"
check "users.list was paginated" grep -qx 'users.list.page2' "$FAKE_STATE/calls.log"
check "users.list retried after 429" test "$(grep -cx users.list "$FAKE_STATE/calls.log")" -ge 2
check "cache is mode 600" test "$(stat -f %Lp "$alfred_workflow_data/cache.json")" = 600
check "data dir is mode 700" test "$(stat -f %Lp "$alfred_workflow_data")" = 700
check "cache holds no email or job title" \
  sh -c "! grep -q -e should-not-be-cached -e SecOps '$alfred_workflow_data/cache.json'"
check "token never written to data dir" \
  sh -c "! grep -rq xoxp- '$alfred_workflow_data'"

# --- Search -------------------------------------------------------------------
check "accent-insensitive person match" test "$(titles jerome | head -1)" = "Jérôme"
check "person with DM opens the DM channel" \
  test "$(first_arg jerome)" = 'slack://channel?team=T0001&id=D0001'
check "person without DM opens user link" \
  test "$(first_arg 'ana lima')" = 'slack://user?team=T0001&id=U0005'
check "Slack Connect person via IM is found" \
  test "$(search zoe | jq -r '.items[0].icon.path')" = icons/connect.png
check "Slack Connect DM opens in my team" \
  test "$(first_arg zoe)" = 'slack://channel?team=T0001&id=D0002'
check "Slack Connect person from shared channel, non-Latin name" \
  test "$(titles 山田 | head -1)" = "山田 健二"
check "group chat shows member names" \
  sh -c "'$scripts/search.zsh' ana | jq -e '.items[] | select(.title == \"Jérôme, Ana Lima\")'"
check "channel by word inside name" test "$(titles incidents | head -1)" = "#secops-incidents"
check "fuzzy match" test "$(titles gnrl | head -1)" = "#general"
check "multi-word any order" test "$(titles 'lima ana' | head -1)" = "Ana Lima"
check "bots excluded by default" sh -c "! '$scripts/search.zsh' deploy | jq -e '.items[] | select(.title == \"Deploy Bot\")'"
check "deleted users excluded" sh -c "! '$scripts/search.zsh' gone | jq -e '.items[] | select(.title == \"Gone Person\")'"
check "refresh command item" test "$(search refresh | jq -r '.items[0].variables.action')" = refresh
check "empty query shows overview" test "$(titles '' | head -1)" = "Search Slack"
check "internal fields stripped" sh -c "! '$scripts/search.zsh' jer | jq -e '.items[] | select(has(\"k\") or has(\"tk\"))'"

# --- Bots opt-in --------------------------------------------------------------
include_bots=1 "$scripts/refresh.zsh" >/dev/null 2>&1
check "bots included when enabled" test "$(titles deploy | head -1)" = "Deploy Bot"

# --- Action guard -------------------------------------------------------------
check "open refuses non-slack links" \
  test "$(action=open "$scripts/action.zsh" 'https://evil.example')" = "Refusing to open an unexpected link."

print -r -- "$pass passed, $failed failed"
(( failed == 0 ))
