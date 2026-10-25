# iris roadmap

Reviewed against the code on 2026-10-25. This file tracks remaining work
and known limits. Implemented features and recorded live checks are in
[README.md](../README.md). The architecture is in [AGENTS.md](../AGENTS.md);
thread-search constraints are described there and in the original
[library research](research/imap-libraries.md).

## Next: iCloud validation

Adam confirmed on 2026-10-25 that all functionality works well with agents
on his Zoho and Gmail accounts. Routine validation of those providers is
complete. iCloud remains the provider to check end to end.

- Run `iris check`, `iris mailboxes`, `iris list`, `iris show`, and
  `iris thread` on iCloud. Check the list filters, subject matching, and
  that `thread --format id` gives the same iris IDs as a rendered thread
  when all messages download.
- Run `iris download` on a PDF, an inline image, and a forwarded message
  (`message/rfc822`, saved as an `.eml`), and compare the bytes. Check
  `show`, `thread`, and `draft` with a large original as well as a small
  one.
- Run `iris read`, `iris unread`, and `iris draft`. Confirm the flags in
  another mail app, and that the draft opens in Apple Mail as its own
  draft in the thread. Check the returned iris ID and `--attach`, including
  a non-ASCII filename.
- Record post-login CAPABILITY and Drafts/Sent names. The original
  research captured only iCloud's pre-login capabilities.

## Targeted validation and provider details

These checks cover specific limits and failure handling beyond regular
use. Keep results in README.md with the date, provider, and case checked.

- Check wrong-password and wrong-host errors. For Gmail OAuth, check the
  expired/revoked-token behavior in `iris auth status` and `iris check`.
  Verify the README console setup steps when setting up another client.
- Compare a 20 MB message's body, filenames, and estimated attachment
  sizes in `show` and `thread` with `show --format raw` on a fast link;
  check that `draft` quotes its body correctly. Download the PDF, compare
  its bytes, and record the time against the 60 second part limit. On
  Zoho and Gmail, record what BODYSTRUCTURE sends for a non-ASCII filename
  (`filename*=`), and whether the outline's size, structure, and headers
  arrive in one FETCH response or several.
- On Zoho and Gmail, attach a file larger than the server accepts: record
  APPENDLIMIT (`draftTooLarge`) or a tagged NO (`draftRefused` and its
  reason), and the upload time against the 30 second limit.
- Record how Gmail and iCloud match SUBJECT, TEXT (`list --search`), and
  TO (`list --to`) words, and how Zoho matches ordinary TEXT/TO words.
  Zoho's earlier TEXT probe with a Message-ID does not establish those
  matching rules.
- Record Gmail's post-login CAPABILITY and Drafts/Sent names alongside
  the existing Zoho record.

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
  seconds each), so they show or quote its body; `show` and `thread` also
  list its attachment IDs. `iris show --format raw` always needs the whole
  message. Other formats also download whole when the size is unknown or
  at most 1 MiB, or when a large message has no readable BODYSTRUCTURE.
  Each whole download can time out, including a message up to 1 MiB on a
  link slower than about 0.84 Mbit/s. A chunked whole download is not possible with
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
