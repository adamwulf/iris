# iris

A command-line tool for reading email over IMAP. It lists a mailbox one page
at a time and shows a full message as Markdown. iris only reads: it opens
mailboxes read-only and never marks a message as read.

Made for Gmail, iCloud Mail, and Zoho Mail. It has not yet been tested
against a live server.

## Install

```sh
mint install adamwulf/iris@main --force
```

Or build from source (macOS 15 or later, Swift 6.3 or later):

```sh
swift build -c release
.build/release/iris --help
```

## Setup

iris reads its settings from environment variables and from `.env` files. It
reads every `.env` from the current directory up to `/` and merges them key by
key: when two files set a key, the nearer file wins, and the environment wins
over every `.env`. So keys in a parent `.env` (for example `~/.env`) still
apply in a folder that has its own `.env`.

Each account has a name, and its keys have the name in the middle. You can
add as many accounts as you need. In the keys, a name is UPPERCASE letters,
digits, and underscores (`IRIS_work_IMAP_HOST` is ignored); in `--account`
you can type it in any case.

`.env` rules: one `KEY=value` per line; `export KEY=value` also works; `#`
starts a comment (in a value, only after a space, and not inside quotes);
when a file sets a key two times, the last line wins. Quotes keep the text
exactly, with no backslash escapes: put a value that has a `"` in single
quotes, and a value that has a `'` in double quotes.

```sh
IRIS_PERSONAL_IMAP_HOST=imap.gmail.com
IRIS_PERSONAL_IMAP_USERNAME=me@gmail.com
IRIS_PERSONAL_IMAP_PASSWORD=abcdabcdabcdabcd
# IRIS_PERSONAL_IMAP_PORT=993   (optional; 993 is the default)

IRIS_WORK_IMAP_HOST=imappro.zoho.com
IRIS_WORK_IMAP_USERNAME=me@example.com
IRIS_WORK_IMAP_PASSWORD=app-specific-password

# Which account to use when --account is not given.
# Not necessary when only one account is configured.
IRIS_DEFAULT_ACCOUNT=personal
```

Run `iris accounts` to see the accounts and any missing keys, and
`iris check` to log in once and confirm the settings.

### Provider settings

All three need an **app-specific password**, not your normal password.

| Provider | Host | Username | Password |
|---|---|---|---|
| Gmail | `imap.gmail.com` | the full address | An [app password](https://support.google.com/accounts/answer/185833). It needs 2-Step Verification. |
| iCloud Mail | `imap.mail.me.com` | the name part of the address (`emily`, not `emily@icloud.com`); try the full address if that fails | An [app-specific password](https://support.apple.com/en-us/102654). It needs two-factor authentication. |
| Zoho Mail | `imap.zoho.com` (personal, free organization) or `imappro.zoho.com` (paid organization). Other data centers: `imap.zoho.eu`, `imap.zoho.in`, `imap.zoho.com.au`, `imap.zoho.jp`, and so on. Zoho shows your host in Settings > Mail Accounts. | the full address | An app-specific password if two-factor authentication is on. First turn on IMAP in Settings > Mail Accounts. |

## What works today

- Any number of named accounts in `.env`, picked with `--account`.
- `iris check`: log in and show the server's capabilities and the INBOX count.
- `iris mailboxes`: the mailbox names with their special-use attributes
  (`\Drafts`, `\Sent`, `\All`, ...).
- `iris list`: a mailbox, newest first, one page at a time
  (iris ID, unread, date, sender, subject). Filters: `--unread`,
  `--flagged`, `--from`, `--subject`, `--since`, `--before`.
- `iris show`: one full message, by its iris ID, as Markdown. HTML mail is converted to
  Markdown; MIME parts, quoted-printable, base64, charsets, encoded headers,
  and `format=flowed` text are decoded. Also as JSON, or as the raw `.eml`
  source. Markdown and JSON include a `message:` URL that opens the message
  in Apple Mail.

## Usage

```sh
iris accounts
iris check --account work

iris list                          # newest 25 messages in INBOX
iris list --page 2 --limit 50
iris list --mailbox "[Gmail]/Sent Mail" --format json
iris list --unread                 # only the unread messages in INBOX
iris list --flagged --from jane@example.com --since 2026-10-01

iris show 'work/INBOX/4821'                # one message, as Markdown
iris show 'work/INBOX/4821' --body text    # the plain-text part instead of the HTML
iris show 'work/INBOX/4821' --format raw > message.eml
iris show 'personal/[Gmail]/Sent Mail/77'
```

List commands take `--format table|json|jsonl|id`. Hints and errors go to
stderr, so stdout is safe to pipe.

`iris list` shows `yes` in the `UNREAD` column (and `"unread": true` in
JSON) for a message without the `\Seen` flag. Listing does not change the flag.

### Filters

These `iris list` options show only some messages:

| Option | Shows only the messages that |
|---|---|
| `--unread` | have no `\Seen` flag |
| `--flagged` | have the `\Flagged` flag (starred, in Gmail) |
| `--from <text>` | have the text in the `From:` header, in the name or the address |
| `--subject <text>` | have the text in the subject |
| `--since <YYYY-MM-DD>` | the server received on that day or later |
| `--before <YYYY-MM-DD>` | the server received before that day |

The options combine: a message must match all of them. Paging works the
same, and the next-page hint keeps the filter options.

The server does the matching (IMAP SEARCH), so the details depend on the
server. RFC 3501 says that text matches any part of the header and ignores
case, but some servers match only whole words, and some refuse `--from` or
`--subject` text that is not ASCII. `--since` and `--before`
compare days, not times: the server uses the day it received the message
and ignores the time and the time zone. That day can be different from the
`DATE` column, which shows the sender's `Date:` header.

### Iris IDs

iris names each message with one iris ID, `<account>/<mailbox>/<UID>`, for
example `work/INBOX/4821`. `iris list` shows it (the `IRIS ID` column, the
`irisID` key in JSON, and each line of `--format id`), and `iris show` takes
it, so `iris show` needs no `--account` or `--mailbox`. `iris show` also
shows it: an `Iris ID` line under the date in Markdown, and the `irisID` key
in JSON (`--format raw` is the message source, unchanged). iris never shows a UID
alone: each mailbox has its own UIDs, so the same UID is a different message
in each mailbox and in each account.

The account is the text before the first `/`, the UID is the text after the
last `/`, and the mailbox is all the text between them, so a mailbox name
can have `/` in it (`personal/[Gmail]/All Mail/77`). The account is in
lowercase, and INBOX in any case is `INBOX`. Type other mailbox names as
`iris mailboxes` shows them: some servers open a name in any case, but a name
in a different case gives a different iris ID for the same message.

Always put an iris ID in single quotes on the command line. A mailbox name
can have spaces, which split the ID into two arguments, and `[ ]`, which zsh
reads as a file pattern: `iris show personal/[Gmail]/Drafts/7` fails in zsh
with "no matches found". Double quotes are not enough when a name has `$`,
`` ` ``, or `!`. In a script, pass each iris ID as one quoted value:

```sh
iris list --format id | while IFS= read -r id; do iris show "$id"; done
```

An iris ID stays valid while the message stays in that mailbox. When a
message moves to a different mailbox, it gets a new UID and a new iris ID.

The **message ID** is a different thing: the `Message-ID` header, which the
sender's mail app writes. `iris show --format json` has both, as `irisID` and
`messageID`. The same email can have the same message ID in more than one
mailbox or account, so iris never uses it to find a message.

### Open a message in Apple Mail

When a message has a message ID, `iris show` also gives a `message:` URL that
opens it in Apple Mail: an `Apple Mail` line in Markdown, and the
`appleMailURL` key in JSON.

```sh
open 'message://%3Creply-2@example.com%3E'
```

The URL holds only the message ID. Mail looks it up in the messages it has
downloaded, so the URL works only when the account is also set up in Mail.
When the same message ID is in more than one mailbox (INBOX and Sent, or two
Gmail labels), Mail opens one of the copies.

### Read-only access for agents

`iris ro <command>` runs the same command as `iris <command>`, but only the
read-only commands exist under `ro`: `accounts`, `check`, `mailboxes`,
`list`, and `show`. Commands that change mail (such as drafts, when they
come) are not there, so `iris ro draft ...` fails.

To let an agent read your mail but never change it, allow only that prefix.
For Claude Code, in `.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(iris ro:*)"] } }
```

## Development

See [AGENTS.md](AGENTS.md) for the architecture and how to add a command.
Future work is in [plans/roadmap.md](plans/roadmap.md).
