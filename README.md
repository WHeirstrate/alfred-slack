# Slack Quick Switcher for Alfred

Type `sl` and a name in Alfred and jump straight to that person, group chat or channel in the Slack desktop app.

- **Small and auditable:** about 600 lines of zsh and jq. Read [`src/scripts/`](src/scripts) before you install it.
- **No dependencies:** uses only what ships with macOS (zsh, curl, `/usr/bin/jq`, `security`, `iconv`, `osascript`). There's no Python, Node, Homebrew or Command Line Tools requirement.
- **Read-only:** a Slack *user* token with five read scopes, stored in the macOS Keychain.
- **Offline search:** typing reads a local cache. The network is used only during a refresh, and only to reach `slack.com`.

See [SECURITY.md](SECURITY.md) for the threat model, data flow and how to report vulnerabilities.

## How it works

```
LaunchAgent (daily) ─┐
                     ├─► refresh.zsh ──HTTPS──► slack.com/api ──► cache.json (600)
"sl refresh" ────────┘        ▲                                       │
                              │ token from Keychain                   ▼
                                                      "sl <name>" ─► search.zsh ─► slack:// deep link
```

1. **Refresh** (`src/scripts/refresh.zsh`):
   - Reads the token from the Keychain and calls `auth.test`. It refuses to continue if the token carries any scope beyond the five below.
   - Pages through `users.list` and `conversations.list` (public channels, private channels, group chats and DMs, excluding archived ones).
   - Fetches `conversations.members` for group chats and for shared channels you're in.
   - Resolves the user IDs `users.list` doesn't return (Slack Connect people) with `users.info`.
   - Writes `cache.json` atomically.
   - Respects `Retry-After` on HTTP 429 and backs off on 5xx errors.
2. **Search** (`src/scripts/search.zsh` + `search.jq`):
   - Scores every cached item against the query. A title prefix ranks highest, then a word prefix, then a substring, then all words in any order, then a fuzzy subsequence.
   - Matching ignores accents ("jerome" finds "Jérôme").
   - It matches display name, real name, @handle and channel name.
3. **Open** (`src/scripts/action.zsh`) opens a deep link. It only accepts these two link forms:
   - `slack://channel?team=T…&id=C…|G…|D…` for channels, group chats, and people you already have a DM with
   - `slack://user?team=T…&id=U…` for people you have no DM with yet

## Slack app setup

You need a Slack app installed to your workspace that has a **user token** (`xoxp-…`). Don't use a bot token.

### Option A: from the manifest (one paste)

1. Go to <https://api.slack.com/apps> → **Create New App** → **From a manifest** and pick your workspace.
2. Paste the contents of [`manifest.yml`](manifest.yml) (YAML tab), then **Next** → **Create**.
3. **Install App** → **Install to Workspace** → **Allow**.
4. Copy the **User OAuth Token** (`xoxp-…`).

### Option B: by hand

1. <https://api.slack.com/apps> → **Create New App** → **From scratch**. Name it, for example, "Alfred Quick Switcher".
2. **OAuth & Permissions** → **Scopes** → **User Token Scopes** (*not* Bot Token Scopes). Add:

   | Scope | Why |
   |---|---|
   | `users:read` | List workspace members and look up Slack Connect users |
   | `channels:read` | List public channels and members of shared public channels |
   | `groups:read` | List your private channels and members of shared private ones |
   | `mpim:read` | List your group chats and their members |
   | `im:read` | List your DMs, so a person opens their existing DM |

   Leave **Bot Token Scopes** empty. Don't add `users:read.email` or any `*:history` or `*:write` scope. The refresh will refuse a token that has them.
3. **Install to Workspace** → **Allow**, then copy the **User OAuth Token** (`xoxp-…`).

If your workspace requires app approval, approve it as an admin first.

## Install

1. Download the `.alfredworkflow` from Releases, or build it yourself:
   ```bash
   ./build.zsh --test
   ```
   Double-click `dist/Slack-Quick-Switcher-<version>.alfredworkflow` to import it into Alfred.
2. In Alfred, type `sl token` and press ↩. Paste the `xoxp-` token into the hidden-input dialog. It goes straight into your login Keychain.
3. Type `sl refresh` and press ↩. A notification tells you when the cache is ready.
4. Optional but recommended: install the daily refresh:
   ```bash
   launchagent/agent.zsh install
   ```
   This defaults to 08:30. Change the time with `--at 07:45` and include bot users with `--include-bots`. If the Mac is asleep at that time, the job runs on wake.

## Usage

| Type | Does |
|---|---|
| `sl jer` | Find people, group chats and channels matching "jer"; ↩ opens it in Slack |
| `sl ana bob` | Words in any order: finds the group chat with Ana and Bob |
| `sl refresh` | Rebuild the cache now |
| `sl token` | Set or rotate the Slack token |
| ⌘C on a result | Copy its `slack://` link |
| ⌘L on a result | Show the name in Large Type |

Results show an icon for each type:

| Icon | Type |
|---|---|
| green | person |
| pink rings | Slack Connect person or channel |
| yellow | group chat |
| blue `#` | channel |
| purple lock | private channel |

The keyword and the "Include bot users" option live in the workflow's **Configure Workflow…** panel in Alfred.

### Token management from a terminal

```bash
src/scripts/token.zsh set
```

`token.zsh set` prompts with hidden input. The other forms:

- `pbpaste | src/scripts/token.zsh set --stdin` reads the token from stdin.
- `src/scripts/token.zsh status` says whether a token is stored. It never prints the token.
- `src/scripts/token.zsh delete` removes it.

## How refresh works

- **When:** daily via the LaunchAgent (`~/Library/LaunchAgents/com.wheirstrate.alfred-slack.refresh.plist`), and on demand via `sl refresh`. A lock directory prevents overlapping runs.
- **What it fetches:** see [How it works](#how-it-works).
- **Where it writes:**
  - The cache: `~/Library/Application Support/Alfred/Workflow Data/com.wheirstrate.alfred-slack/cache.json` (directory `700`, file `600`).
  - The outcome of the last refresh: `status.json` in the same directory. Search uses it to fail closed when the token is missing, revoked or over-scoped.
  - The log: `~/Library/Logs/alfred-slack.log`. It contains timestamps, error codes and counts, never the token.
- **Speed:** a refresh of a workspace with a few thousand members takes seconds. Each Slack Connect user and each group chat or shared channel costs one extra call (Tier 4 rate limits), so the first run in a large workspace can take a minute.

Manage the agent:

```bash
launchagent/agent.zsh status
```

The other commands are `launchagent/agent.zsh run` (refresh now through launchd) and `launchagent/agent.zsh uninstall`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "No Slack token set" | Run `sl token` |
| "Slack token problem: … invalid_auth / token_revoked" | The token was revoked or the app was uninstalled. Reinstall the app and run `sl token` |
| "Token has scopes beyond the read-only set" | Remove the extra scopes under OAuth & Permissions, reinstall the app, and store the new token |
| "Slack cache is more than 3 days old" | Check `launchagent/agent.zsh status` and the log |
| `sl token` dialog doesn't appear | Alfred may need permission to show dialogs. Use the terminal method above instead |
| A person opens their profile instead of a DM | You have no DM with them yet. Once one exists, the next refresh switches to opening it |
| Slack Connect person doesn't show up | They only appear once you share a DM, group chat, or shared channel you're a member of with them. Run `sl refresh` |
| Wrong workspace opens | The cache holds one workspace (the token's). Make sure the Slack app is signed in to it |

Full log:

```bash
tail -n 50 ~/Library/Logs/alfred-slack.log
```

## Uninstall

```bash
launchagent/agent.zsh uninstall
```

Then remove the token and the cache:

```bash
src/scripts/token.zsh delete
```

```bash
rm -rf ~/Library/Application\ Support/Alfred/Workflow\ Data/com.wheirstrate.alfred-slack ~/Library/Logs/alfred-slack.log
```

Finally, delete the workflow in Alfred and, at <https://api.slack.com/apps>, uninstall or delete the Slack app. That revokes the token.

## Development

```
src/                    workflow source (zipped as-is into the .alfredworkflow)
  info.plist            Alfred workflow definition
  icon.png, icons/      icons (generated by tools/make-icons.swift)
  scripts/
    lib.zsh             shared: paths, Keychain, Slack API client
    refresh.zsh         Slack API → cache.json
    build.jq            raw Slack lists → Alfred items
    search.zsh/.jq      Script Filter: cache → scored results
    action.zsh          open / refresh / token dispatcher
    token.zsh           Keychain set / delete / status
launchagent/            LaunchAgent template and installer
tests/                  offline end-to-end tests with fake curl/security
tools/make-icons.swift  dev-only icon generator (needs Xcode/CLT; not used at runtime)
build.zsh               lint + package
manifest.yml            Slack app manifest
```

Run the tests:

```bash
zsh tests/run.zsh
```

The tests put fake `curl` and `security` binaries first on `PATH`. They never touch the network or your Keychain.

## License

[MIT](LICENSE)
