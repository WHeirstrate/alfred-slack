# Turns the raw Slack lists gathered by refresh.zsh into Alfred items.
#
# Inputs (via --slurpfile / --arg):
#   $users    workspace members from users.list
#   $ext      users resolved with users.info (mostly Slack Connect)
#   $convs    conversations.list (public, private, mpim, im)
#   $members  {conv, user} pairs for group chats and shared channels
#   $team     my team ID, $self my user ID, $bots 1 to include bot users
#
# Every item keeps Alfred's fields plus:
#   type  person | connect | bot | group | channel | private | shared
#   k     raw searchable names (folded copies are added by refresh.zsh)
#   r     tie-break rank, higher sorts first

def channel_link($id): "slack://channel?team=\($team)&id=\($id)";
def user_link($id): "slack://user?team=\($team)&id=\($id)";

def display:
  if (.display_name // "") != "" then .display_name
  elif (.real_name // "") != "" then .real_name
  else .name end;

def names: [.display_name, .real_name, .name] | map(select(. != null and . != "")) | unique | join(" ");

def item($type; $icon; $rank):
  . + {type: $type, icon: {path: "icons/\($icon).png"}, r: $rank,
       variables: {action: "open"}, text: {copy: .arg, largetype: .title}};

$users as $u
| $ext as $x
| (($u + $x) | map({key: .id, value: .}) | from_entries) as $by_id
| ($u | map({key: .name, value: .}) | from_entries) as $by_handle
| ($convs | map(select(.is_im and (.is_user_deleted | not)))
   | map({key: .user, value: .id}) | from_entries) as $dm
| ($members | group_by(.conv) | map({key: .[0].conv, value: map(.user)}) | from_entries) as $mm

| [
    # People: workspace members, plus Slack Connect users we share something with.
    ( ($u[] | select(.deleted | not) | select($bots == 1 or (.is_bot | not))),
      ($x[] | select(.deleted | not) | select($bots == 1 or (.is_bot | not))) )
    | . as $p
    | (if .is_bot then "bot"
       elif (.team_id // $team) != $team then "connect"
       else "person" end) as $type
    | {
        uid: "u:\(.id)",
        title: display,
        subtitle: ([
            (if .id == $self then "You"
             elif $type == "connect" then "Slack Connect"
             elif $type == "bot" then "Bot"
             else "Person" end),
            (if (.real_name // "") != "" and .real_name != ($p | display) then .real_name else empty end),
            (if (.name // "") != "" then "@\(.name)" else empty end)
          ] | join(" · ")),
        arg: (if $dm[.id] then channel_link($dm[.id]) else user_link(.id) end),
        k: names
      }
    | item($type; if $type == "bot" then "person" else $type end; 3)
  ]
  + [
    # Group chats: show resolved member names instead of mpdm-a--b--c-1.
    $convs[] | select(.is_mpim)
    | (.name | sub("^mpdm-"; "") | sub("-[0-9]+$"; "") | split("--")
       | map($by_handle[.].id // .)) as $from_name
    | (($mm[.id] // $from_name) | map(select(. != $self))) as $ids
    | ($ids | map(($by_id[.] // {name: .}) | display)) as $labels
    | {
        uid: "g:\(.id)",
        title: ($labels | join(", ")),
        subtitle: "Group chat · \($ids | length + 1) people",
        arg: channel_link(.id),
        k: ($ids | map(($by_id[.] // {name: .}) | names) | join(" "))
      }
    | item("group"; "group"; 2)
  ]
  + [
    # Channels (public, private, shared).
    $convs[] | select((.is_im or .is_mpim) | not)
    | (if .is_ext_shared then "shared" elif .is_private then "private" else "channel" end) as $type
    | {
        uid: "c:\(.id)",
        title: "#\(.name)",
        subtitle: ([
            (if .is_private then "Private channel" else "Channel" end),
            (if .is_ext_shared then "Slack Connect" elif .is_shared then "Shared" else empty end),
            (if .num_members != null then "\(.num_members) members" else empty end),
            (if .is_member then empty else "not a member" end)
          ] | join(" · ")),
        arg: channel_link(.id),
        k: (.name + " " + (.name | gsub("[-_.]"; " ")))
      }
    | item($type; if $type == "shared" then "connect" else $type end; if .is_member then 1 else 0 end)
  ]
