#!/bin/zsh --no-rcs
# Manage the Slack user token in the macOS login Keychain.
#
#   token.zsh set      prompt for a token (hidden dialog, or hidden terminal
#                      input when run from a terminal), verify it, store it
#   token.zsh set --stdin
#                      read the token from stdin instead (e.g. `pbpaste |`)
#   token.zsh delete   remove it from the Keychain
#   token.zsh status   say whether a token is stored (never prints it)

emulate -L zsh
setopt no_unset
umask 077
source "${0:A:h}/lib.zsh"

prompt_token() {
  if [[ ${1:-} == --stdin ]]; then
    head -n1
  elif [[ -t 0 ]]; then
    local t
    read -rs "t?Slack user token (xoxp-…): " </dev/tty
    print >&2
    print -r -- "$t"
  else
    osascript -e 'activate' -e 'text returned of (display dialog "Paste your Slack user token (xoxp-…). It is stored in your login Keychain only." default answer "" with hidden answer with title "Slack Quick Switcher" buttons {"Cancel", "Save"} default button "Save" with icon note)' 2>/dev/null
  fi
}

case ${1:-} in
  set)
    typeset token
    token=$(prompt_token "${2:-}") || { print -r -- "Token not changed."; exit 1 }
    token=${token//[[:space:]]/}
    if ! token_valid_format "$token"; then
      print -r -- "That is not a Slack user token (it must start with xoxp-). Nothing stored."
      exit 1
    fi
    if ! token_store "$token"; then
      print -r -- "Could not write to the Keychain. Nothing stored."
      exit 1
    fi
    unset token
    # A stale auth error from a previous refresh no longer applies.
    rm -f -- "$STATUS_FILE"
    print -r -- "Slack token saved to the Keychain. Run “sl refresh” to build the cache."
    ;;
  delete)
    token_delete && print -r -- "Slack token removed from the Keychain." \
                 || print -r -- "No Slack token was stored."
    ;;
  status)
    token_exists && print -r -- "A Slack token is stored in the Keychain (service “$KEYCHAIN_SERVICE”)." \
                 || { print -r -- "No Slack token stored."; exit 1 }
    ;;
  *)
    print -r -- "usage: ${0:t} set|delete|status" >&2
    exit 2
    ;;
esac
