# iris roadmap (rough plan)

This file is only future work. When a milestone is done, remove it from here
and describe it in README.md.

Providers that must work: Gmail, Zoho Mail, iCloud Mail. Auth is an
app-specific password over TLS on port 993.

Milestone 1 (the inbox reader: accounts, check, mailboxes, list, show) is
done; README.md describes it.

## Next: live check against real accounts

- Run `iris check`, `iris mailboxes`, `iris list`, `iris show`, `iris read`,
  and `iris unread` once per provider (Gmail, iCloud, Zoho), and once each
  with a wrong password and a wrong host. Nothing has run against a real
  server yet.
- Record the post-login CAPABILITY and the Drafts/Sent names per provider
  (open in `plans/research/imap-libraries.md`, section 5).

## Milestone 2: threads

- `iris thread <iris-id>`: every message in the thread, oldest first, as
  Markdown. Each message shows its own iris ID, so a reply in Sent shows a
  Sent iris ID.
- How to find the thread depends on the server:
  - Gmail: `X-GM-THRID` (search `[Gmail]/All Mail`, so sent replies appear).
    Blocked at the current pin: SwiftMail can FETCH `X-GM-THRID`, but the
    swift-nio-imap revision it pins has no Gmail SEARCH keys (they came in
    swift-nio-imap PR #853). Bump SwiftMail first, or use the References
    walk below on Gmail too.
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

- `iris draft reply <iris-id> [--all] [--body-file <path> | stdin]`. The body is
  Markdown.
- Build the message: `To` from `Reply-To` or `From` (`--all` adds the other
  recipients as `Cc`), `Subject: Re: ...`, `In-Reply-To`, `References`, and
  `multipart/alternative` with the Markdown as text/plain and rendered HTML.
- Save it with APPEND to the special-use `\Drafts` mailbox (found with LIST;
  Gmail's is `[Gmail]/Drafts`) with the `\Draft` flag.
- iris never sends mail. The user reviews and sends the draft from a mail app.
- `draft` is a write command: it is never under `iris ro` (see AGENTS.md,
  "Read-only and write commands"), and its APPEND call lives outside
  `MailReader` (in `MailWriter` and `MailWriteClient`, as for `iris read`).
  `iris thread` (milestone 2) is read-only and goes in both.
- Probably needs a new optional key for the From address and display name
  (for example `IRIS_<NAME>_FROM`), because the username is not always the
  address.

## Later, maybe

- XOAUTH2 login for Gmail.
- More `list` filters (body text, To, Cc), archive/move.
- A live smoke test (`iris test`) against a real account, like graham's.
- A file log (FellerBuncher) like graham's.
- `skill/iris/SKILL.md` for agents.

## Known limits

- Raw message download has a 10 second total deadline: SwiftMail's
  `FetchRawMessageCommand.timeoutSeconds` is hard-coded at the pinned
  revision (`88c45cbd`), and `fetchRawMessage` takes no timeout. Large
  messages may fail. Fix: an upstream SwiftMail change that adds a timeout
  parameter, then a pin bump (ask Adam before opening an upstream PR).
- A quoted non-Latin charset (`charset="koi8-r"`) is not recognized by
  SwiftMail's `declaredCharset`, so such a body may decode wrong. UTF-8 and
  Latin-1 are correct. Upstream: SwiftMail PR #268.
- On a server without SPECIAL-USE (iCloud, by SwiftMail's table), SwiftMail
  guesses the special-use attributes from mailbox names by substring, so a
  mailbox named "Consent forms" shows `\Sent`.
- `inReplyTo` keeps only the first message ID (the same as SwiftMail's model).
- SwiftMail's full-message fetch keeps only the first FETCH answer. If the
  server sends an unsolicited `* n FETCH (FLAGS ...)` first, iris reports
  that the message does not exist. Rare in a short session; fix upstream.
- A filtered `iris list` gets every matching UID in one SEARCH reply, and
  SwiftMail reads at most 1 MiB per reply
  (`IMAPServer.defaultResponseBufferLimit`). A plain SEARCH reply takes
  about 11 bytes per UID, so a filter that matches more than about 90,000
  messages fails. ESEARCH (Gmail and iCloud have it) sends ranges such as
  `101:250`, which are much shorter. Fix if it happens: send the search in
  UID ranges, newest first, until a page is full.
- An iris ID (`<account>/<mailbox>/<UID>`) is valid only while the
  mailbox's UIDVALIDITY stays the same. If the server rebuilds the mailbox,
  the old IDs name other messages or none; run `iris list` again. iris does
  not check UIDVALIDITY.
- Table columns are padded by `Character`, so emoji and CJK text are never
  cut, but a value with 2-column-wide characters (for example an emoji in a
  subject or a CJK sender name) pushes the columns after it out of line.
- A server that sends a mailbox name that is not valid modified UTF-7 (raw
  `R&D` instead of `R&-D`) shows it unchanged, but typing it sends `R&-D`,
  so that mailbox cannot be opened. RFC 3501 servers do not do this.
- A text/plain part outside the multipart/alternative (for example a
  mailing-list footer) is part of the text body. When the HTML body is shown,
  that part is not shown and not listed (`--body text` shows it). SwiftMail
  keeps only leaf parts, not the multipart subtypes, so iris cannot tell a
  footer from the text rendition of the same body.

## Open questions

- Paging: page numbers (`--page 2`) are simple but shift when new mail
  arrives; a cursor (for example `--older-than <iris-id>`) is stable.
  Possibly both. (`--before` is taken: it is the date filter.)
