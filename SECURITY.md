# Security

This workflow is designed to be small enough to audit in one sitting. This page states what it can access, where data lives, and what it deliberately does not do.

## Scopes

Only **user token** scopes, all read-only:

| Scope | Used by | Why |
|---|---|---|
| `users:read` | `users.list`, `users.info` | Names and IDs of workspace members and of Slack Connect users you share conversations with |
| `channels:read` | `conversations.list`, `conversations.members` | Public channel names and IDs; members of shared public channels |
| `groups:read` | `conversations.list`, `conversations.members` | Private channels you're in; members of shared private channels |
| `mpim:read` | `conversations.list`, `conversations.members` | Your group chats and their members, to show names instead of `mpdm-…` |
| `im:read` | `conversations.list` | Your DM channel IDs, so a person opens their existing DM |

The token has no write scopes, no message-history scopes, no `users:read.email`, and no bot token.

The token can see names and IDs only. It cannot read messages, files or email addresses, and it cannot post or change anything.

**Enforced at runtime:**
- Every refresh reads the `x-oauth-scopes` header from `auth.test`. If the token has any scope outside the five above, or if the header is missing, the refresh stops, writes nothing, and search shows an error instead of results.
- Even if the app is later given broader scopes, the workflow fails closed rather than quietly using them.

## Where things live

| What | Where | Protection |
|---|---|---|
| Slack token | Login Keychain, service `alfred-slack`, account `slack-user-token` | Keychain encryption; see note below |
| Cache (names + IDs) | `~/Library/Application Support/Alfred/Workflow Data/com.wheirstrate.alfred-slack/cache.json` | dir `700`, file `600`, written atomically |
| Last refresh status | `…/com.wheirstrate.alfred-slack/status.json` | `600` |
| Log | `~/Library/Logs/alfred-slack.log` | `600`; error codes and counts only |
| LaunchAgent | `~/Library/LaunchAgents/com.wheirstrate.alfred-slack.refresh.plist` | contains a script path, no secrets |

**The token is never** written to files, workflow variables, Alfred's configuration, environment variables, logs, command-line arguments, or git:
- It enters the Keychain on stdin (`security -i`), not as an argument visible in `ps`.
- It is read back with `security find-generic-password -w` into a non-exported shell variable.
- It is passed to curl as a config file on stdin (`curl -K -`).

**The cache holds only** for each person: Slack user ID, team ID, display name, real name and @handle. For each conversation: ID, name, type flags and member count. Job titles, emails, avatars, status and presence are discarded before the cache is written.

**Keychain access note:** the item is created by `/usr/bin/security`, which is therefore on the item's access list. Any process running as your user can run `security find-generic-password -s alfred-slack -w` and read the token without a prompt. This is the trade-off for unattended refresh with stock tools. It is the same exposure as any CLI-managed Keychain secret. The mitigation is the read-only scope set.

## Data flow and network

- The only network calls happen in `refresh.zsh`. They go to `https://slack.com/api/{auth.test,users.list,users.info,conversations.list,conversations.members}`, over HTTPS only (`--proto =https --tlsv1.2`, no redirects followed), all as GET requests.
- Search and open make no network calls and never read the token.
- `action.zsh` only opens links matching `^slack://(channel|user)\?team=[A-Z0-9]+&id=[A-Z0-9]+$`.
- No telemetry, no update checks, no third-party hosts.

## Dependencies

There are none beyond the macOS base system: `/bin/zsh`, `/usr/bin/curl`, `/usr/bin/jq`, `/usr/bin/security`, `/usr/bin/iconv`, `/usr/bin/osascript`, `/usr/bin/open`, `/usr/bin/plutil`, `/bin/launchctl`.

The icon generator in `tools/` uses Swift, but it's a development-only tool. Its output PNGs are committed.

## Revoking access

Pick one, from strongest to lightest:
- Uninstall or delete the app at <https://api.slack.com/apps>. This revokes the token immediately.
- As a workspace admin, remove the app under **Manage apps**.
- Locally, run `src/scripts/token.zsh delete` and delete the data directory.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private vulnerability reporting instead: **Security → Report a vulnerability** on <https://github.com/WHeirstrate/alfred-slack>.

Include the affected file and line, the impact, and steps to reproduce. You'll get an acknowledgement within a few working days.
