# iris roadmap (rough plan)

This file is only future work. When a milestone is done, remove it from here
and describe it in README.md.

Providers that must work: Gmail, Zoho Mail, iCloud Mail. Auth is an
app-specific password over TLS on port 993, or, for a Gmail account that
cannot make an app password, Google OAuth (XOAUTH2) after `iris auth login`.

Milestone 1 (the inbox reader: accounts, check, mailboxes, list, show) and
milestone 3 (`iris draft`, a reply saved as a draft) are done; README.md
describes them.

## Next: live check against real accounts

- Run `iris check`, `iris mailboxes`, `iris list`, and `iris show` once per
  provider (Gmail, iCloud), and once each with a wrong password and a wrong
  host.
- Run `iris read`, `iris unread`, and `iris draft` once per provider (Gmail,
  iCloud, Zoho). They have not run against a real server yet. For
  `iris draft`, check that the draft opens in Apple Mail as its own draft,
  in the thread, and that the server reports its UID (UIDPLUS; Zoho
  advertises it). With `--attach`, check that Apple Mail and Gmail's web
  view show the files with their names, also a non-ASCII name (RFC 2231
  `filename*=`). Also attach a file larger than the server takes, on Zoho
  and on Gmail: record whether each announces APPENDLIMIT (`draftTooLarge`)
  or answers with a tagged NO (`draftRefused`, and the reason text it
  sends), and how long the upload takes against the 30 second limit.
- Run `iris list --search` and `iris list --to` once per provider (Gmail,
  iCloud, Zoho). IMAP TEXT and TO have not been sent to a real server
  yet: check that `--search` finds a word that is only in the body, and
  how each server matches words (whole words, as SUBJECT on Zoho?).
- Zoho (`imappro.zoho.com`) was checked on 2026-10-24: `check`,
  `mailboxes`, `list`, `show`, and `thread` work. Post-login CAPABILITY: `IMAP4rev1
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
  should both show the expired sign-in (`invalid_grant`), and `iris draft`
  on the OAuth account should save a draft. None of it has run against
  Google yet.
- Record the post-login CAPABILITY and the Drafts/Sent names for Gmail and
  iCloud (open in `plans/research/imap-libraries.md`, section 5).

## Milestone 2: threads

`iris thread` (step 1) is done; README.md describes it, and AGENTS.md
describes the walk. Why it works the way it does:

- The shortcuts are not available, so every server gets the same walk:
  - Gmail `X-GM-THRID`: SwiftMail can FETCH it but not SEARCH by it. The
    swift-nio-imap revision it pins has no Gmail SEARCH keys (they came in
    swift-nio-imap PR #853), and 1.16.0 is SwiftMail's latest release.
  - `THREAD=REFERENCES`: swift-nio-imap has no THREAD command, and Zoho
    does not advertise it.
  - One search over the whole account: MULTISEARCH (RFC 7377) is not
    advertised by Zoho or Gmail, and SwiftMail has no API for it.
- The first plan, HEADER searches on `In-Reply-To` and `References`, cannot
  find replies on Zoho. Probes on 2026-10-24 (read-only): HEADER
  `Message-ID` matches the whole ID, with or without `< >`; HEADER
  `In-Reply-To` and `References` never match, in any form, even when the
  header holds the ID; TEXT with an ID matches nothing; SUBJECT matches
  whole words ("Champ" does not find "Champion"), and an AND of SUBJECT
  word keys gave exactly the right messages; and an OR tree that mixed in
  the dead keys gave wrong answers (the same matching key found the message
  with 3, 6, and 12 keys, but not with 9 or 15 to 18). So replies are found
  through the subject, which every member must share. HEADER `Message-ID`
  searches (at most 10 IDs each) run only where no SUBJECT search ran.
- A server may refuse a subject that is not ASCII (Zoho did not, for a
  curly apostrophe, emoji, em dash, arrows, or "café"), so iris then
  searches for the subject's ASCII words. More probes for those words: a
  word ends at punctuation, `-`, `.`, `@`, `_`, and the curly apostrophe,
  but not at an ASCII apostrophe ("don" does not find "don't"), and "ai"
  (two letters) finds nothing. So words with an ASCII apostrophe and words
  shorter than 3 are left out, and at most the 5 longest are sent.
- Apple Mail on iPhone puts only the parent in `References`, so the walk
  links messages round after round (seen live on Zoho).
- A subject change starts a new thread, as in Gmail: subjects are compared
  without leading `Re:`/`Fwd:`/`Fw:` and `[tags]` (Mailman 3 writes
  "[list] Re: x", gateways add "[EXTERNAL]"). Outlook users reply to an old
  email and change the subject, so `References` links the new conversation
  to the old one (seen live on Zoho).
- Each `Message-ID` is shown once, from a fixed mailbox order, so every
  message of a thread gives the same thread with the same iris IDs (when
  the SUBJECT search runs and the thread is in the searched mailboxes).
  Zoho's Sent held two copies of one sent message, and on Gmail one message
  is in many mailboxes.
- One message that does not download or cannot be read is left out with a
  line on stderr; the rest of the thread is still shown. When nothing is
  left to show, the command fails as `iris show` would for the message
  named.

Next:

- Check `iris thread` on Gmail and iCloud. Gmail's SEARCH is also
  index-based: confirm that SUBJECT finds the replies there, and how it
  matches words.
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

## Later, maybe

- More `list` filters (Cc), archive/move.
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
- `iris thread` finds replies only through the SUBJECT search. When none
  runs (an empty subject, a subject with no ASCII word of 3 or more letters
  on a server that refuses non-ASCII text, or a server that refuses both
  searches or misses the named message), only the messages that the named
  message leads back to are found, round after round, through the
  `Message-ID`s they name: never a reply to them. On a thread that never
  branched the newest message gives the whole thread; on one that branched
  (A has replies B and C), naming C gives A and C, not B, and the oldest
  message gives only itself. A generic subject ("Hi") makes many
  candidates; each costs a few hundred header bytes, but a large `\All`
  mailbox could take a while. A reply filed only in a folder that is not
  searched is not found.
- A server that sends a mailbox name that is not valid modified UTF-7 (raw
  `R&D` instead of `R&-D`) shows it unchanged, but typing it sends `R&-D`,
  so that mailbox cannot be opened. RFC 3501 servers do not do this.
- A text/plain part outside the multipart/alternative (for example a
  mailing-list footer) is part of the text body. When the HTML body is shown,
  that part is not shown and not listed (`--body text` shows it). SwiftMail
  keeps only leaf parts, not the multipart subtypes, so iris cannot tell a
  footer from the text rendition of the same body.
- `iris draft` decodes the original as `iris show` does. When its HTML body
  cannot be converted and it has no text part, the error gives `show`'s
  advice (`--format raw`), which `draft` does not have, even with
  `--no-quote`, which needs no body.
- APPEND has a 30 second total deadline: SwiftMail's
  `AppendCommand.timeoutSeconds` is hard-coded at the pinned revision, and
  the clock starts before the message bytes are sent. A draft with large
  `--attach` files (base64 makes them about 4/3 their size) on a slow uplink
  can time out, which iris reports as `draftMayBeSaved`. Fix: the same kind
  of upstream timeout parameter as for the raw download.

## Open questions

- Paging: page numbers (`--page 2`) are simple but shift when new mail
  arrives; a cursor (for example `--older-than <iris-id>`) is stable.
  Possibly both. (`--before` is taken: it is the date filter.)
