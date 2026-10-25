# iris roadmap (rough plan)

This file is only future work. When a milestone is done, remove it from here
and describe it in README.md.

Providers that must work: Gmail, Zoho Mail, iCloud Mail. Auth is an
app-specific password over TLS on port 993, or, for a Gmail account that
cannot make an app password, Google OAuth (XOAUTH2) after `iris auth login`.

Milestone 1 (the inbox reader: accounts, check, mailboxes, list, show) is
done; README.md describes it.

## Next: live check against real accounts

- Run `iris check`, `iris mailboxes`, `iris list`, and `iris show` once per
  provider (Gmail, iCloud), and once each with a wrong password and a wrong
  host.
- Run `iris read` and `iris unread` once per provider (Gmail, iCloud,
  Zoho). They have not run against a real server yet.
- Zoho (`imappro.zoho.com`) was checked on 2026-10-24: `check`,
  `mailboxes`, `list`, and `show` work. Post-login CAPABILITY: `IMAP4rev1
  UNSELECT CHILDREN XLIST NAMESPACE IDLE MOVE ID AUTH=PLAIN SASL-IR
  AUTH=XOAUTH2 UIDPLUS ESEARCH LIST-EXTENDED LIST-STATUS WITHIN LITERAL- ACL
  CONDSTORE` (no SPECIAL-USE, no THREAD, no MULTISEARCH). Special-use
  mailboxes: `Drafts`, two `\Sent` (`Sent` and `Sent Messages`), `Archive`,
  `Junk` and `Spam`, `Trash` and `Deleted Messages`; no `\All`.
- Gmail with Google OAuth, with Adam's Google Cloud app (External,
  Testing): run `iris auth login`, then `iris auth status` and
  `iris check`. Check the console steps in README.md ("Gmail with OAuth")
  as they are done, the "not verified" warning, and the page the browser
  shows after the redirect. After the 7 days (or after removing the access
  at myaccount.google.com/permissions), `iris auth status` and `iris check`
  should both show the expired sign-in (`invalid_grant`). None of it has
  run against Google yet.
- Record the post-login CAPABILITY and the Drafts/Sent names for Gmail and
  iCloud (open in `plans/research/imap-libraries.md`, section 5).

## Milestone 2: threads

- `iris thread <iris-id>`: every message in the thread, oldest first, as
  Markdown. Each message shows its own iris ID, so a reply in Sent shows a
  Sent iris ID.
- Find the thread the same way on every server: walk `Message-ID` /
  `In-Reply-To` / `References` with header searches (SwiftMail's
  `SearchCriteria.header`). The shortcuts are not available:
  - Gmail `X-GM-THRID`: SwiftMail can FETCH it but not SEARCH by it. The
    swift-nio-imap revision it pins has no Gmail SEARCH keys (they came in
    swift-nio-imap PR #853), and 1.16.0 is SwiftMail's latest release.
  - `THREAD=REFERENCES`: swift-nio-imap has no THREAD command, and Zoho
    does not advertise it.
  - One search over the whole account: MULTISEARCH (RFC 7377) is not
    advertised by Zoho or Gmail, and SwiftMail has no API for it.
- Search these mailboxes, each that the server has: INBOX, every `\Sent`,
  `\Archive`, `\Drafts`, and `\All` mailbox, and the input message's
  mailbox. Gmail's `\All` holds every message except Spam and Trash; Zoho
  has no `\All`, so a reply filed only in another folder is not found.
- Repeat the search with the new IDs until no new message appears. Apple
  Mail on iPhone puts only the parent in `References`, so one search for
  the first message's ID misses most of a thread (seen live on Zoho).
- Show each `Message-ID` once. Zoho's Sent held two copies of one sent
  message, and on Gmail one message is in many mailboxes.
- Open: should a subject change (ignoring `Re:`/`Fwd:`) end the thread?
  Outlook users reply to an old email and change the subject, so
  `References` links the new conversation to the old one (seen live on
  Zoho). Gmail starts a new thread when the subject changes.
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
