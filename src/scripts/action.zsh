#!/bin/zsh --no-rcs
# Alfred Run Script: dispatches on the "action" variable set by the Script
# Filter item. Whatever this prints becomes the notification text (nothing
# printed means no notification).

emulate -L zsh
source "${0:A:h}/lib.zsh"
umask 077

arg=${1:-}

case ${action:-} in
  open)
    # Only ever open the two deep-link shapes the cache produces.
    if [[ $arg =~ '^slack://(channel|user)\?team=[A-Z0-9]+&id=[A-Z0-9]+$' ]]; then
      open -- "$arg"
    else
      print -r -- "Refusing to open an unexpected link."
    fi
    ;;
  refresh)
    osascript -e 'display notification "Fetching people, group chats and channels…" with title "Slack Quick Switcher"' 2>/dev/null
    "${0:A:h}/refresh.zsh" 2>>"$HOME/Library/Logs/alfred-slack.log" | tail -n1
    ;;
  token)
    "${0:A:h}/token.zsh" set
    ;;
esac
