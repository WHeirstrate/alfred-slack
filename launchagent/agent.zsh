#!/bin/zsh --no-rcs
# Install or remove the LaunchAgent that refreshes the Slack cache daily.
#
#   launchagent/agent.zsh install [--at HH:MM] [--include-bots] [--workflow-dir DIR] [--print]
#   launchagent/agent.zsh uninstall
#   launchagent/agent.zsh status
#   launchagent/agent.zsh run        trigger a refresh now via launchd
#
# By default the agent runs the refresh script of the workflow as installed in
# Alfred (located through Alfred's prefs.json), so updating the workflow in
# Alfred also updates what the agent runs.

emulate -L zsh
setopt no_unset

readonly LABEL=com.wheirstrate.alfred-slack.refresh
readonly BUNDLE_ID=com.wheirstrate.alfred-slack
readonly PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
readonly LOG_FILE=$HOME/Library/Logs/alfred-slack.log
readonly TEMPLATE=${0:A:h}/$LABEL.plist.template
readonly DOMAIN=gui/$UID

die() { print -r -- "error: $*" >&2; exit 1 }

find_workflow_dir() {
  local prefs=$HOME/Library/Application\ Support/Alfred/prefs.json
  local current dir
  current=$(jq -r '.current // empty' "$prefs" 2>/dev/null)
  [[ -n $current ]] || current=$HOME/Library/Application\ Support/Alfred/Alfred.alfredpreferences
  for dir in "$current"/workflows/*(N/); do
    [[ $(plutil -extract bundleid raw "$dir/info.plist" 2>/dev/null) == $BUNDLE_ID ]] && { print -r -- "$dir"; return 0 }
  done
  return 1
}

xml_escape() {
  local s=${1//&/&amp;}
  s=${s//</&lt;}
  print -r -- "${s//>/&gt;}"
}

cmd_install() {
  local at=08:30 bots=0 wfdir='' dry=0
  while (( $# )); do
    case $1 in
      --at) at=${2:-}; shift ;;
      --include-bots) bots=1 ;;
      --print) dry=1 ;;
      --workflow-dir) wfdir=${2:-}; shift ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [[ $at =~ '^([01][0-9]|2[0-3]):([0-5][0-9])$' ]] || die "--at expects HH:MM"
  local hour=$(( 10#${match[1]} )) minute=$(( 10#${match[2]} ))

  if [[ -z $wfdir ]]; then
    wfdir=$(find_workflow_dir) || die "workflow $BUNDLE_ID not found in Alfred. Import it first, or pass --workflow-dir."
  fi
  local script=${wfdir:A}/scripts/refresh.zsh
  [[ -r $script ]] || die "$script not found"

  mkdir -p -- "${PLIST:h}" "${LOG_FILE:h}"
  local tmp
  tmp=$(mktemp "${PLIST:h}/.$LABEL.XXXXXX") || die "cannot write to ${PLIST:h}"
  sed -e "s|__REFRESH_SCRIPT__|$(xml_escape "$script" | sed 's/[|&\\]/\\&/g')|" \
      -e "s|__LOG_FILE__|$(xml_escape "$LOG_FILE" | sed 's/[|&\\]/\\&/g')|g" \
      -e "s|__INCLUDE_BOTS__|$bots|" \
      -e "s|__HOUR__|$hour|" \
      -e "s|__MINUTE__|$minute|" \
      "$TEMPLATE" > "$tmp"
  plutil -lint -s "$tmp" || { rm -f -- "$tmp"; die "generated plist is invalid" }
  chmod 644 "$tmp"
  if (( dry )); then cat -- "$tmp"; rm -f -- "$tmp"; return 0; fi

  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
  mv -f -- "$tmp" "$PLIST"
  launchctl bootstrap "$DOMAIN" "$PLIST" || die "launchctl bootstrap failed"

  touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
  print -r -- "Installed $LABEL: daily at $at, running $script"
  print -r -- "Log: $LOG_FILE"
}

cmd_uninstall() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
  rm -f -- "$PLIST"
  print -r -- "Removed $LABEL. (Cache and Keychain item are untouched; see README to remove them.)"
}

cmd_status() {
  if [[ -e $PLIST ]]; then
    print -r -- "Plist: $PLIST"
    print -r -- "Runs:  $(plutil -extract ProgramArguments.2 raw "$PLIST")"
    printf 'Time:  %02d:%02d\n' "$(plutil -extract StartCalendarInterval.Hour raw "$PLIST")" \
                                "$(plutil -extract StartCalendarInterval.Minute raw "$PLIST")"
  else
    print -r -- "Not installed."
  fi
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl print "$DOMAIN/$LABEL" | grep -E '^\s*(state|last exit code|runs) ='
  fi
  [[ -r $LOG_FILE ]] && { print -r -- "Last log lines:"; tail -n 5 "$LOG_FILE" }
}

cmd_run() {
  launchctl kickstart "$DOMAIN/$LABEL" || die "agent not loaded; run install first"
  print -r -- "Refresh started; follow $LOG_FILE"
}

case ${1:-} in
  install) shift; cmd_install "$@" ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  run) cmd_run ;;
  *) print -r -- "usage: ${0:t} install [--at HH:MM] [--include-bots] [--workflow-dir DIR] | uninstall | status | run" >&2; exit 2 ;;
esac
