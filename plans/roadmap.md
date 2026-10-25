# iris roadmap

Reviewed against the code on 2026-10-25. This file tracks remaining work
and known limits. Implemented features and recorded live checks are in
[README.md](../README.md); the architecture and thread-search rationale
are in [AGENTS.md](../AGENTS.md).

## Next: live checks against real accounts

Gmail, Zoho Mail, and iCloud Mail remain the target providers. The commands
below are implemented; these are validation tasks, not missing features.
Keep the recorded results in README.md up to date as checks are completed,
including the date, provider, and behavior checked.

- Run `iris check`, `iris mailboxes`, `iris list`, and `iris show` on
  Gmail and iCloud, including a wrong password and a wrong host. Repeat
  `show` on Zoho to check the outline FETCH added after its first live
  check, for a small message as well as a large one.
- Check `iris thread` on Gmail and iCloud. Confirm that SUBJECT finds
  replies, how each server matches words, and that `--format id` gives
  the same iris IDs as the rendered thread when all messages download.
- Run `iris download` on each provider, on a PDF, an inline image, and
  a forwarded message (`message/rfc822`, saved as an `.eml`), and compare
  the downloaded bytes with the attachment.
- Show a 20 MB message (a large PDF attached) on Zoho and Gmail with
  `iris show`, `iris thread`, and `iris draft`: they must take the parts
  path, show or quote the body, and leave the PDF for `iris download`.
  Compare the body, filenames, and estimated sizes with
  `iris show --format raw` on a fast link, and with a message under 1 MiB
  that takes the whole path. Record what BODYSTRUCTURE sends for a
  non-ASCII filename (`filename*=`), and whether the outline's size,
  structure, and header fields arrive in one FETCH response or several.
- Run `iris read`, `iris unread`, and `iris draft` on each provider.
  Confirm the read/unread state in another mail app. Check that a draft
  opens in Apple Mail as its own draft, in the thread, and that the server
  reports its UID (UIDPLUS). With `--attach`, check the filenames in
  Apple Mail and Gmail's web view, including a non-ASCII name. On Zoho and
  Gmail, also attach a file larger than the server accepts: record
  APPENDLIMIT (`draftTooLarge`) or a tagged NO (`draftRefused` and its
  reason), and the upload time against the 30 second limit.
- Run `iris list --search` and `iris list --to` on each provider.
  Check that `--search` finds a word only in the body, and record how TEXT
  and TO match words. The Zoho TEXT probe with a Message-ID does not
  establish ordinary body-word matching.
- Check Gmail OAuth with Adam's Google Cloud app (External, Testing):
  `iris auth login`, `iris auth status`, `iris check`, and saving a
  draft. Verify the README console steps, consent warning, and redirect
  page. After token expiry or revoking access,
  `iris auth status` and `iris check` should report the expired sign-in
  (`invalid_grant`).
- Record post-login CAPABILITY and Drafts/Sent names for Gmail and iCloud.
  The original research captured only their pre-login capabilities.

## Quoted-history validation

- Check trimming on a real Thunderbird reply, a new Outlook reply, and a
  Gmail reply with answers between quoted lines. The existing real-message
  checks and heuristic limits are in README.md, "Quoted history and
  signatures". Use `--full` to compare the original body with the trimmed
  output.

## Later, maybe

- More `list` filters (Cc), archive/move.
- A live smoke test (`iris test`) against a real account, like graham's.
- A file log (FellerBuncher) like graham's.
- `skill/iris/SKILL.md` for agents.

## Known limits

- Raw message download has a 10 second total deadline: SwiftMail's
  `FetchRawMessageCommand.timeoutSeconds` is hard-coded at the pinned
  revision (`88c45cbd`), and `fetchRawMessage` takes no timeout. `iris show`,
  `iris thread`, and `iris draft` download a message over 1 MiB in parts
  (its headers and BODYSTRUCTURE, then only its text and HTML parts, 60
  seconds each), so they show its body and attachment IDs. Only
  `iris show --format raw` still needs the whole message, so a large one can
  time out there, and so can a message up to 1 MiB on a link slower than
  about 0.84 Mbit/s. A chunked whole download is not possible with
  SwiftMail's API: the ranged `fetchPart(section:of:offset:count:)` cannot
  ask for `BODY[]`, because `Section([])` becomes `[1]`. Fix: an upstream
  SwiftMail change that adds a timeout parameter (or a ranged `BODY[]`),
  then a pin bump (ask Adam before opening an upstream PR).
- A large message, shown in parts, takes its filenames from SwiftMail's
  BODYSTRUCTURE conversion (`MessagePart+BodyStructure.swift`), which reads
  only the `filename` and `name` parameters, not RFC 2231 `filename*=`.
  So on a server that sends only `filename*` in BODYSTRUCTURE, a non-ASCII
  name (`Résumé.pdf`) shows as "(no filename)"; its attachment ID still
  works. The conversion also keeps only the `charset` parameter of a
  Content-Type, so a `format=flowed` text body keeps its soft line breaks.
  Fix upstream (decode `filename*`, keep the parameters).
- A large message, shown in parts, takes its date from SwiftMail's ENVELOPE
  date parser (`FetchMessageInfoHandler.parseEnvelopeDate`), which reads no
  date without seconds (`Sat, 24 Oct 2026 13:42 -0500`), and SwiftMail
  keeps no raw `Date` value (it leaves Date out of `additionalFields`), so
  `HeaderDate` cannot read it either. Such a date shows as `(unknown)`, and
  the attribution line of a draft that quotes it loses its date
  ("Jane Doe wrote:" instead of "On ..., Jane Doe wrote:"). Fix upstream:
  accept a time without seconds in the ENVELOPE date parser, or keep the
  raw `Date` value in `additionalFields`.
- `iris download` fetches one part with SwiftMail's `fetchPart`, whose
  `FetchMessagePartCommand.timeoutSeconds` is hard-coded at 60 at the
  pinned revision, so an attachment that takes more than 60 seconds to
  download fails (`attachmentDownloadTimedOut`). A ranged fetch
  (`BODY.PEEK[<section>]<offset.count>`, which SwiftMail has) would remove
  the limit; it is not built.
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
  `iris download` has the same risk for its one part (`fetchPart` without a
  range), and a server that answers `BODY[<section>] NIL` gives no bytes
  too. There BODYSTRUCTURE gives the part's size, so for a part that is not
  empty iris says that the server sent no bytes (`attachmentNotReceived`)
  instead of saving an empty file. The body parts of a large message have
  the same risk, and the same check (`bodyNotReceived`).
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
- The quoted-history trimming is a heuristic (README.md, "Quoted history
  and signatures", lists its limits). It loses answers written inside an
  Outlook quote and the forwarded message of a forward from an Outlook in
  another language (`WG:`, `TR:`), finds only English attribution lines in
  text, and keeps a signature without a `-- ` line. A fix that would cover more: compare
  each quote with the earlier messages of the thread, and cut only what
  they already show.
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
