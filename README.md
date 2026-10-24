# iris

A command-line tool for reading email over IMAP. It lists a mailbox one page
at a time and shows a full message as Markdown. iris only reads: it opens
mailboxes read-only and never marks a message as read.

Made for Gmail, iCloud Mail, and Zoho Mail. It has not yet been tested
against a live server.

## Install

Build from source (macOS 15 or later, Swift 6.3 or later):

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
  (UID, date, sender, subject).
- `iris show`: one full message as Markdown. HTML mail is converted to
  Markdown; MIME parts, quoted-printable, base64, charsets, encoded headers,
  and `format=flowed` text are decoded. Also as JSON, or as the raw `.eml`
  source.

## Usage

```sh
iris accounts
iris check --account work

iris list                          # newest 25 messages in INBOX
iris list --page 2 --limit 50
iris list --mailbox "[Gmail]/Sent Mail" --format json

iris show 4821                     # the message with UID 4821, as Markdown
iris show 4821 --body text         # the plain-text part instead of the HTML
iris show 4821 --format raw > message.eml
```

List commands take `--format table|json|jsonl|id`. UIDs belong to one
mailbox, so pass the same `--mailbox` to `iris show` that you passed to
`iris list`. Hints and errors go to stderr, so stdout is safe to pipe.

## Development

See [AGENTS.md](AGENTS.md) for the architecture and how to add a command.
Future work is in [plans/roadmap.md](plans/roadmap.md).
