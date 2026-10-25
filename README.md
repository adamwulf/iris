# iris

A command-line tool for reading email over IMAP. It lists a mailbox one page
at a time, shows a full message, or a whole thread, as Markdown, and saves a
reply as a draft. Reading changes nothing: iris opens mailboxes read-only and
never marks a message as read. The only commands that change mail are
`iris read` and `iris unread`, which mark one message as read or unread, and
`iris draft`, which adds a new draft to the Drafts mailbox. iris never sends
mail: you review and send the draft in your mail app.

Made for Gmail, iCloud Mail, and Zoho Mail. `check`, `mailboxes`, `list`,
`show`, and `thread` were run against Zoho Mail on 2026-10-24; `read`,
`unread`, and `draft` have not run against a real server yet, and Gmail and
iCloud Mail are not checked yet.

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
# The From line of drafts (optional; only `iris draft` reads it).
IRIS_WORK_FROM=Jane Doe <jane@example.com>

# Which account to use when --account is not given.
# Not necessary when only one account is configured.
IRIS_DEFAULT_ACCOUNT=personal
```

Run `iris accounts` to see the accounts and any missing keys, and
`iris check` to log in once and confirm the settings.

`IRIS_<NAME>_FROM` is the From line of the drafts that `iris draft` saves:
`Name <address>`, or the address alone. Reading mail does not need it, so
`iris accounts` does not check it. Without it, `iris draft` uses the username
when the username is an address (for an account that signs in with Google,
the address you sign in as). iCloud's username is not (`emily`, not
`emily@icloud.com`), so an iCloud account needs `IRIS_<NAME>_FROM` to save
drafts.

### Provider settings

All three need an **app-specific password**, not your normal password. A
Gmail account that cannot make one signs in with Google instead (see
[Gmail with OAuth](#gmail-with-oauth)).

| Provider | Host | Username | Password |
|---|---|---|---|
| Gmail | `imap.gmail.com` | the full address | An [app password](https://support.google.com/accounts/answer/185833). It needs 2-Step Verification. Or no password: [sign in with Google](#gmail-with-oauth). |
| iCloud Mail | `imap.mail.me.com` | the name part of the address (`emily`, not `emily@icloud.com`); try the full address if that fails | An [app-specific password](https://support.apple.com/en-us/102654). It needs two-factor authentication. |
| Zoho Mail | `imap.zoho.com` (personal, free organization) or `imappro.zoho.com` (paid organization). Other data centers: `imap.zoho.eu`, `imap.zoho.in`, `imap.zoho.com.au`, `imap.zoho.jp`, and so on. Zoho shows your host in Settings > Mail Accounts. | the full address | An app-specific password if two-factor authentication is on. First turn on IMAP in Settings > Mail Accounts. |

### Gmail with OAuth

Some Google accounts cannot make an app password: Google says "The setting
you are looking for is not available for your account." Such an account
signs in with Google instead (OAuth 2.0, and IMAP `AUTHENTICATE XOAUTH2`).
This has not been tested against a live account yet.

First make your own OAuth client in the Google Cloud console. You do this
once:

1. In the [Google Cloud console](https://console.cloud.google.com/), make
   a new project for iris.
2. Go to Menu > **Google Auth platform** > **Branding** and click **Get
   Started**. Give an app name (such as `iris`) and your email, pick
   **External** as the audience, give a contact email, accept the policy,
   and click **Create**.
3. In **Audience**, keep the publishing status **Testing**. Under **Test
   users**, click **Add users** and add each Gmail address that iris will
   read.
4. In **Data Access**, click **Add or remove scopes**, paste
   `https://mail.google.com/` under **Manually add scopes**, click **Add to
   table**, then **Update**, then **Save**.
5. In **Clients**, click **Create client**, pick the application type
   **Desktop app**, give it a name, and click **Create**. Copy the client
   ID and the client secret right away: Google shows the secret only when
   it makes the client.

Then give the account these keys, with no `_IMAP_PASSWORD`. The username is
the full address you sign in as:

```sh
IRIS_PERSONAL_IMAP_HOST=imap.gmail.com
IRIS_PERSONAL_IMAP_USERNAME=me@gmail.com
IRIS_PERSONAL_GOOGLE_CLIENT_ID=1234-abcd.apps.googleusercontent.com
IRIS_PERSONAL_GOOGLE_CLIENT_SECRET=GOCSPX-...
# The From line of drafts (optional; without it, drafts are from the username).
# IRIS_PERSONAL_FROM=Your Name <me@gmail.com>
```

and sign in:

```sh
iris auth login --account personal
```

iris opens Google's sign-in page in your browser, and writes its URL to
stderr in case the browser does not open. Sign in as the username of the
account. Google warns that it has not verified the app; it is your own app,
so continue, and allow the access to Gmail. The browser then shows "You can
close this window", and iris writes `IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN`
into the `.env` file that has the client ID. (When the client ID comes from
the environment, iris writes no file: it prints the line for you to save.)
Run `iris check --account personal` to test the account.

From then on, each command gets a new access token from Google before it
logs in, `iris draft` too. iris never sends mail, but Gmail's IMAP accepts
only the `https://mail.google.com/` scope, which is full access to the
mailbox.

`iris auth status` checks the Google sign-in of every account that has a
client ID (or one, with `--account`): which keys are set (never their
values), and whether Google still gives an access token. It logs in to no
mail server, and it exits with status 1 when an account is not signed in.

```sh
$ iris auth status
NAME      USERNAME      CLIENT ID  CLIENT SECRET  REFRESH TOKEN  STATUS
personal  me@gmail.com  set        set            set            ok
```

**Sign in again every 7 days.** Google ends the sign-in of an app in
Testing mode after 7 days, and also when you change your Google password.
Then commands say that the Google sign-in has expired: run
`iris auth login --account personal` again. (Publishing the app would end
the 7-day limit, but an app with the Gmail scope then needs Google's
review.)

If Google sends no refresh token, iris says so: remove your app's access at
<https://myaccount.google.com/permissions> and sign in again.

The keys have the account's name in them, so they never collide with the
plain `GOOGLE_*` keys that other tools (such as graham) keep in the same
`.env`. `iris accounts` shows "not signed in" for an account that has a
client ID but no refresh token yet.

## What works today

- Any number of named accounts in `.env`, picked with `--account`.
- Gmail without an app password: `iris auth login` signs in with Google
  (OAuth), and every command then logs in with XOAUTH2. `iris auth status`
  shows which Google accounts are still signed in.
- `iris check`: log in and show the server's capabilities and the INBOX count.
- `iris mailboxes`: the mailbox names with their special-use attributes
  (`\Drafts`, `\Sent`, `\All`, ...).
- `iris list`: a mailbox, newest first, one page at a time
  (iris ID, date, sender, unread, subject). Filters: `--unread`,
  `--flagged`, `--from`, `--subject`, `--since`, `--before`.
- `iris show`: one full message, by its iris ID, as Markdown. HTML mail is converted to
  Markdown; MIME parts, quoted-printable, base64, charsets, encoded headers,
  and `format=flowed` text are decoded. Also as JSON, or as the raw `.eml`
  source. Markdown and JSON include a `message:` URL that opens the message
  in Apple Mail.
- `iris thread`: every message in the thread of one message, oldest first,
  by the iris ID of any message in it. Each message is shown in full, as
  `iris show` shows it, with its own iris ID (a reply you sent shows its
  Sent iris ID). Also as JSON or JSON Lines, or only the iris IDs, which
  downloads no message.
- `iris read` and `iris unread`: mark one message, by its iris ID, as read
  or unread (they add or remove the `\Seen` flag). Each one sets the state,
  so running it again changes nothing. They print nothing when they succeed.
- `iris draft`: save a reply to a message, by its iris ID, as a draft in the
  `\Drafts` mailbox. The reply is Markdown; the draft has it as plain text
  and as HTML, with the original quoted below it. `--all` replies to all.
  iris never sends the draft.

## Usage

```sh
iris accounts
iris check --account work
iris auth login --account personal  # Gmail with OAuth: sign in, about once a week
iris auth status                    # which Google accounts are still signed in

iris list                          # newest 25 messages in INBOX
iris list --page 2 --limit 50
iris list --mailbox "[Gmail]/Sent Mail" --format json
iris list --unread                 # only the unread messages in INBOX
iris list --flagged --from jane@example.com --since 2026-10-01

iris show 'work/INBOX/4821'                # one message, as Markdown
iris show 'work/INBOX/4821' --body text    # the plain-text part instead of the HTML
iris show 'work/INBOX/4821' --format raw > message.eml
iris show 'personal/[Gmail]/Sent Mail/77'

iris thread 'work/INBOX/4821'                 # the whole thread, oldest first
iris thread 'work/INBOX/4821' --format json   # an array of `iris show --format json` objects
iris thread 'work/INBOX/4821' --format jsonl  # the same objects, one per line
iris thread 'work/INBOX/4821' --format id     # only the iris IDs, one per line

iris read 'work/INBOX/4821'                # mark as read
iris unread 'work/INBOX/4821'              # mark as unread

iris draft 'work/INBOX/4821' 'Thanks, that works for me.'   # a reply, as a draft
iris draft 'work/INBOX/4821' -F reply.md --all              # reply to all, from a file
pbpaste | iris draft 'work/INBOX/4821' --no-quote           # from stdin, without the quote
```

List commands (`accounts`, `mailboxes`, `list`, `auth status`) take
`--format table|json|jsonl|id`. Hints and errors go to
stderr, so stdout is safe to pipe.

`iris list` shows `●` in the `UNREAD` column, just left of the subject (and
`"unread": true` in JSON), for a message without the `\Seen` flag. Listing
and showing do not change the flag; `iris read` and `iris unread` do.

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

### Threads

`iris thread <iris-id>` shows every message of the thread that the message
is in: the messages before it and the replies after it, oldest first (by
the `Date:` header, else the date the server received the message). It
takes `--body` like `iris show`, and `--format`:

- `markdown` (the default): each message as `iris show` prints it, with a
  `* * *` line between messages.
- `json`: an array of the objects that `iris show --format json` prints.
- `jsonl`: the same objects, one per line, as the list commands print
  `jsonl`.
- `id`: only the iris ID of each message, one per line, as
  `iris list --format id` prints them. iris finds the thread from the
  headers alone, so this downloads no message: it saves the download time
  (the most for large messages), and it leaves no message out.

iris looks in INBOX, the Sent, Drafts, Archive, and All Mail mailboxes,
and the message's own mailbox. A message is in the thread when it has the
same subject and its `Message-ID`, `In-Reply-To`, or `References` header
links it to another message of the thread. Subjects are compared without
leading `Re:`, `Fwd:`, and `Fw:` and bracketed tags such as `[list]`
(mailing lists) or `[EXTERNAL]` (company mail gateways), in any order,
and without case. So a subject change starts a new thread, as in Gmail,
even when the reply's `References` names the old conversation. A message
in several mailboxes (on Gmail, INBOX and All Mail; on Zoho, two copies in
Sent) is shown once, from INBOX, else Sent, Drafts, Archive, All Mail, then
the message's own mailbox. So when iris can search by the subject (below),
every message of a thread in those mailboxes gives the same thread and the
same iris IDs; naming a message in another folder adds that folder.

iris finds the replies by searching each mailbox for the subject, because
servers such as Zoho cannot search the `In-Reply-To` and `References`
headers. When a server refuses a subject (some refuse text that is not
ASCII, such as "Adam’s plan" with a curly apostrophe), iris searches for
its ASCII words instead ("adam", "plan"). When there is nothing it can
search for (an empty subject, or one with no ASCII word of three or more
letters, such as "Café"), it says so on stderr and follows only the
`Message-ID`s that the messages name: then it finds only the messages that
the named message leads back to, not the replies to them. The newest
message of a thread that never branched gives the whole thread; on a
thread that branched (A has replies B and C), naming C gives A and C, not
B.

When one message cannot be shown (in every format but `id`), iris leaves
it out, shows the others, and writes a line to stderr with its iris ID,
why, and what to do next:

- It did not download in time (SwiftMail stops every download after 10
  seconds): it may be large, or the connection slow, so try again on a
  faster connection. `iris show` has the same limit.
- It cannot be read as an email, or its HTML cannot be converted:
  `iris show '<iris-id>' --format raw` shows its source. With
  `--body html`, a message that also has a text part says to use
  `iris show '<iris-id>' --body text`.
- It is gone (deleted or moved after iris found it, before the download):
  run the command again.

When no message of the thread can be shown (in practice, a thread of one
large message), the command fails with the error `iris show` would give
for the message you named. Notes about which part of a message is shown
(such as "The message has no text part") start with that message's iris
ID.

Limits:

- A reply filed only in another folder (not INBOX, Sent, Drafts, Archive,
  or All Mail, and not the folder of the message you named) is not found.
  Zoho has no All Mail.
- Each message is shown in full, with the quoted history of the messages
  before it.

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

### Drafts

`iris draft <iris-id>` saves a reply to that message as a draft. It never
sends anything: open the draft in your mail app, check it, and send it from
there. The reply is Markdown, from exactly one source:

- the argument after the iris ID: `iris draft 'work/INBOX/4821' 'Thanks!'`.
  A reply that starts with `-` (a Markdown list) would read as an option, so
  put `--` before it: `iris draft 'work/INBOX/4821' -- '- yes'`. Or use a
  file or stdin.
- a file: `-F reply.md` (or `--file`); `-F -` reads stdin
- stdin, when there is no argument and no `-F` and stdin is not a terminal:
  `pbpaste | iris draft 'work/INBOX/4821'`

With no reply on a terminal, iris stops with an error instead of waiting for
you to type. An empty reply, or one that is not UTF-8, is an error too.

The draft is built from the original message:

- **To:** the original's `Reply-To`, else its `From`. With `--all`, **Cc:**
  the original's To and Cc recipients, without the To addresses and without
  you (your From address, and the username when it is an address).
- **Subject:** `Re: ` and the original subject (no second `Re:`).
- **In-Reply-To** and **References**, so mail apps show the draft in the
  same thread.
- **Body:** your reply, then `On <date>, <sender> wrote:` and the original's
  body. `--no-quote` leaves the quote out. The plain-text part is your
  Markdown, with `> ` before each line of the original. The HTML part is
  your Markdown rendered, with the original in a quote block as Apple Mail
  quotes: an HTML original as HTML again, and a plain-text original as its
  text, line by line, never read as Markdown. HTML in the reply or the quote
  is shown as text, never run as HTML. Quoted images that pointed at a part
  of the original (`cid:`, such as a signature logo) are left out. A line of
  only `-` or `=` under a text line, such as the `-- ` before a signature,
  stays text: it never turns the line above it into a heading (use `#` for
  a heading).

iris saves the draft with the flags `\Seen \Draft` (as Apple Mail saves its
own drafts, so it does not show as unread) in the mailbox that the server
marks `\Drafts` (`iris mailboxes` shows it; Gmail's is `[Gmail]/Drafts`), and
prints the draft's iris ID, for example `work/Drafts/77`. A server without
UIDPLUS does not report the new message's UID; then iris prints nothing on
stdout and says on stderr where it saved the draft.

### Read-only access for agents

`iris ro <command>` runs the same command as `iris <command>`, but only the
read-only commands exist under `ro`: `accounts`, `check`, `mailboxes`,
`list`, `show`, `thread`, and `auth status`. Commands that change mail
(`read`, `unread`, and `draft`) are not there, so `iris ro read ...` and
`iris ro draft ...` fail. Neither is `iris auth login`, which opens a browser
and writes `.env`.

To let an agent read your mail but never change it, allow only that prefix.
For Claude Code, in `.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(iris ro:*)"] } }
```

## Development

See [AGENTS.md](AGENTS.md) for the architecture and how to add a command.
Future work is in [plans/roadmap.md](plans/roadmap.md).
