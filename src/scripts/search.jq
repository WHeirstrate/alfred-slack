# Scores cached items against the query and emits Alfred Script Filter JSON.
#
# Inputs: the cache on stdin, plus
#   $q      folded query ([a-z0-9 ] only), or the raw lowercased query when
#           folding left nothing (e.g. names in non-Latin scripts)
#   $fuzzy  true when $q is safe to turn into a subsequence regex
#   $now    epoch seconds, for the stale-cache warning
#
# Scoring, best first: title starts with query, a word starts with query,
# substring, every query word is a word prefix, every query word occurs,
# characters occur in order (fuzzy).

def cmd($kw; $title; $sub; $icon; $action):
  {uid: "cmd:\($kw)", title: $title, subtitle: $sub, valid: true, arg: $action,
   icon: {path: "icons/\($icon).png"}, variables: {action: $action}, autocomplete: $kw};

def commands:
  [ cmd("refresh"; "Refresh Slack cache"; "Fetch people, group chats and channels from Slack now"; "refresh"; "refresh"),
    cmd("token"; "Set Slack token"; "Store or replace the xoxp user token in the macOS Keychain"; "key"; "token") ];

. as $cache
| ($q | split(" ") | map(select(length > 0))) as $toks
| ($toks | join(" ")) as $qs
| (if $fuzzy and ($qs | length) > 1
   then ($qs | gsub(" "; "") | split("") | join(".*")) else null end) as $re

| (commands | map(select(. as $c | $qs != "" and ($c.autocomplete | startswith($qs)) and ($qs | length) >= 3))) as $cmds

| (if $qs == "" then []
   else
     [ $cache.items[]
       | .k as $k
       | (" " + .k) as $hay
       | (if (.tk | startswith($qs)) then 100
          elif ($hay | contains(" " + $qs)) then 80
          elif (.k | contains($qs)) then 60
          elif ($toks | length) > 1 and all($toks[]; . as $t | $hay | contains(" " + $t)) then 50
          elif ($toks | length) > 1 and all($toks[]; . as $t | $k | contains($t)) then 40
          elif $re != null and (.k | test($re)) then 20
          else 0 end) as $s
       | select($s > 0)
       | {s: $s, r: .r, l: (.title | length), item: (del(.k, .tk, .r, .type))} ]
     | sort_by(-.s, -.r, .l) | .[0:50] | map(.item)
   end) as $hits

| (($now - ($cache.generated_at // 0)) > 3 * 86400) as $stale

| {items: (
    if $qs == "" then
      [{title: "Search Slack",
        subtitle: "\($cache.items | length) people, group chats and channels in \($cache.team_name) — type a name",
        valid: false, icon: {path: "icon.png"}}] + commands
    elif ($hits | length) == 0 then
      $cmds + [{title: "No matches for “\($qs)”", subtitle: "Try fewer letters, or refresh the cache",
                valid: false, icon: {path: "icon.png"}}]
    elif ($cmds | map(.autocomplete) | index($qs)) != null then $cmds + $hits
    else $hits + $cmds end
    + (if $stale then [{title: "Slack cache is more than 3 days old",
                        subtitle: "Press ↩ to refresh now. Is the LaunchAgent installed?",
                        valid: true, arg: "refresh", variables: {action: "refresh"},
                        icon: {path: "icons/warning.png"}}] else [] end)
  )}
