# iris roadmap (rough plan)

This file is only future work. When a milestone is done, remove it from here
and describe it in README.md.

Providers that must work: Gmail, Zoho Mail, iCloud Mail. Auth is an
app-specific password over TLS on port 993.

## Milestone 1: inbox reader (in progress)

- [x] Package skeleton: `IrisKit` (all logic) + thin `iris` CLI.
- [x] Many named accounts in `.env` (`IRIS_<NAME>_IMAP_*`), `--account`,
      `IRIS_DEFAULT_ACCOUNT`, and `iris accounts`.
- [x] IMAP library choice: SwiftMail (pinned by revision) + SwiftText for
      HTML to Markdown (research: `plans/research/imap-libraries.md`).
- [ ] Connect: a command that logs in and reports the server's capabilities
      and the INBOX message count, to check an account's settings.
- [ ] List: newest first, with paging. Columns: UID, sender, subject, date.
      Formats: table (default), json, jsonl, id.
- [ ] Show: one full message, decoded (MIME parts, base64, quoted-printable,
      charsets, encoded headers) and printed as Markdown. HTML-only mail is
      converted to Markdown. Also `--format json`.
- [ ] README.md (setup per provider), AGENTS.md (architecture, recipes).

## Milestone 2: threads

- `iris thread <uid>`: every message in the thread, oldest first, as Markdown.
- How to find the thread depends on the server:
  - Gmail: `X-GM-THRID` (search `[Gmail]/All Mail`, so sent replies appear).
  - Servers that advertise `THREAD=REFERENCES`: use it.
  - Otherwise: walk `Message-ID` / `In-Reply-To` / `References` with header
    searches in INBOX and the special-use `\Sent` mailbox.
- Trim repeated history. Each reply usually quotes the whole chain under it,
  so the thread view shows only the new text of each message, with a
  `--full` flag to turn trimming off. This is a heuristic, but the common
  clients leave markers we can find:
  - HTML: Gmail `div.gmail_quote`, Apple Mail `blockquote type="cite"`,
    Outlook `div#divRplyFwdMsg` / `"From: ... Sent: ..."` header blocks.
  - Plain text: an `On <date>, <name> wrote:` line followed by `>` lines.
  - Signatures after a `-- ` line.
  When no marker is found, show the whole message (never drop text we are
  not sure about).

## Milestone 3: draft a reply

- `iris draft reply <uid> [--all] [--body-file <path> | stdin]`. The body is
  Markdown.
- Build the message: `To` from `Reply-To` or `From` (`--all` adds the other
  recipients as `Cc`), `Subject: Re: ...`, `In-Reply-To`, `References`, and
  `multipart/alternative` with the Markdown as text/plain and rendered HTML.
- Save it with APPEND to the special-use `\Drafts` mailbox (found with LIST;
  Gmail's is `[Gmail]/Drafts`) with the `\Draft` flag.
- iris never sends mail. The user reviews and sends the draft from a mail app.
- Probably needs a new optional key for the From address and display name
  (for example `IRIS_<NAME>_FROM`), because the username is not always the
  address.

## Later, maybe

- XOAUTH2 login for Gmail.
- Search, mark as read, archive/move.
- A live smoke test (`iris test`) against a real account, like graham's.
- A file log (FellerBuncher) like graham's.
- `skill/iris/SKILL.md` for agents, and install with
  `mint install adamwulf/iris@main`.

## Open questions

- Paging: page numbers (`--page 2`) are simple but shift when new mail
  arrives; a cursor (`--before <uid>`) is stable. Possibly both.
- How the message ID is shown to users: the IMAP UID (only valid in one
  mailbox) or a provider ID such as Gmail's `X-GM-MSGID`.
