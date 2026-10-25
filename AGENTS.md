# AGENTS.md

Instructions for agents (Claude, Codex, and others) that work in this repo.

## What this is

`iris` is a command-line email reader over IMAP. It also downloads one
attachment, marks a message read or unread, and saves replies as drafts,
but it never sends mail. It follows
the structure of Adam's other CLIs, `graham` (Google Workspace) and `hunch`
(Notion): a library with all the logic (`IrisKit`) and a thin executable
(`iris`) built on swift-argument-parser.

iris does not write its own IMAP or MIME code. It uses SwiftMail for both,
SwiftText to turn HTML into Markdown, and swift-markdown to turn a draft's
Markdown into HTML. The reasons, the alternatives, and the risks are in
`plans/research/imap-libraries.md`.

## Architecture

**The one rule:** if it can be unit-tested, it belongs in `IrisKit`. The
executable only parses arguments, calls the library, and prints. IrisKit never
prints: it logs through `IrisLog`, and the executable decides where the lines
go (stderr).

```
Sources/IrisKit/
  Config/      DotEnv (.env loader, and setValue for the refresh token),
               AccountResolver (named accounts, the From address of drafts),
               Account (+ GoogleClient),
               RefreshTokenSave (where `iris auth login` put the token, and
               its stdout line and stderr message)
  Auth/        Google OAuth: HTTPTransport (the HTTP seam, URLSessionTransport,
               FormEncoder), GoogleTokenEndpoint (refresh and code exchange),
               GoogleSignIn (`iris auth login`: consent URL, PKCE, redirect
               checks), LoopbackServer (the 127.0.0.1 redirect listener),
               GoogleURL (query escaping), GoogleSignInStatus (`iris auth
               status`: the keys set and one refresh per account)
  Mail/        MailClient (the IMAP seam), SwiftMailClient (the real one),
               MailReader (sessions, paging, the thread walk, one attachment, errors),
               MailModels (rows, pages, ThreadMessage, DownloadedAttachment),
               MailWriter (the calls that change mail: read, unread, and
               saving a draft; SavedDraft),
               MessageFilter (the `list` filter options, sent as UID SEARCH),
               IrisID (the iris ID, the one message name, <account>/<mailbox>/<UID>),
               AttachmentID (a part's MIME section, such as 1.2, inside one message),
               ThreadSubject (the subject rule of `thread`)
  Message/     MessageDecoder (raw RFC 822 -> MessageDocument), FlowedText,
               BodyCleanup, HeaderDate, MessageFormatter (Markdown/JSON/raw,
               and a thread), AppleMailURL (the message: URL from the Message-ID header),
               TransferEncoding (base64 and quoted-printable of one downloaded part)
  Draft/       DraftBody (the reply's one source: argument, -F, stdin),
               DraftAttachment (a file of --attach: name, MIME type, bytes),
               ReplyComposer (MessageDocument -> DraftMessage), DraftMessage
               (headers, parts, attachments, References folding),
               MarkdownHTML (the HTML part)
  Helpers/     OutputFormatter (table/json/jsonl/id for list commands),
               MailAddress (the one address type), DateText, ModifiedUTF7,
               CalendarDay (a YYYY-MM-DD day for --since and --before),
               Redaction (removes secrets from text that iris shows),
               AttachmentOutput (`download`: stdout or a new file, safe filenames)
  IrisError.swift   the one error type; each message says what to do next
  IrisLog.swift     the logging seam
Sources/iris/
  Iris.swift        @main root command; ExpressibleByArgument conformances
  CLISupport.swift  log handler, swift-log bootstrap, AccountOptions (--account),
                    ArgumentHelp.irisID (the help for every iris ID argument)
  Commands/         one file per command
Tests/IrisKitTests/ offline library tests (LoopbackServerTests binds 127.0.0.1);
                    Support/ has FakeMailClient, LogRecorder, StubTransport
                    (HTTP), and FakeRedirectReceiver (sign-in)
Tests/CLITests/     argument parsing only, never run()
```

### The IMAP seam

`MailClient` is the protocol for the few IMAP calls iris makes to read mail.
One client is one session: `login()`, the calls, then `logout()`.
`MailClient.session` keeps that order (it logs out on success, on error, and
after a failed login); `MailReader` and `MailWriter` run every call in one.
`MailReader` holds the read logic: paging math, ordering, date fallback, and modified
UTF-7 in both directions (it decodes LIST names in `mailboxes()`, encodes
`--mailbox` before EXAMINE, and puts the typed name back into an
`unknownMailbox` error). Without a filter, `list` pages by sequence number
and sends no SEARCH. With one, it sends UID SEARCH, pages the sorted
matching UIDs with the same math (UIDs grow in arrival order, as sequence
numbers do), and fetches the page by UID. `MailClient` speaks wire names only. `SwiftMailClient` only
converts SwiftMail types and errors; for a Google account, `login()` first
gets an access token from `GoogleTokenEndpoint` (before it connects), then
sends AUTHENTICATE XOAUTH2 (`Command.authenticate`) instead of LOGIN. Its
parts that need no server are static and tested in `SwiftMailClientTests`:
the error mapping (`irisError(for:command:account:accessToken:)`), the TLS choice
(`transportSecurity(forPort:)`), the SEARCH keys
(`searchCriteria(for:)`, `subjectSearchCriteria(_:)`, `messageIDSearchCriteria(_:)`),
the STORE operation (`storeOperation(seen:)`), `MailboxInfo(swiftMail:)`,
`MessageEnvelope(swiftMail:)`, `ThreadHeaders(swiftMail:)`,
`PartStructure(swiftMail:)`, and `Email(draft:)`.

`download` (`MailReader.attachment(_:of:)`) is one read-only session:
EXAMINE, `fetchEnvelopes(uids:)` to check that the message exists (the
BODYSTRUCTURE of a missing UID gets no answer, which SwiftMail reports as a
failed FETCH), `fetchStructure(uid:)` (BODYSTRUCTURE, as `[PartStructure]`:
the section, the filename, and the transfer encoding of each part), then
`fetchPart(_:uid:)` (`BODY.PEEK[<section>]`) for that one part, never
`fetchRawMessage` (see "Gotchas"). A section that is not in the structure
is `unknownAttachment`, which names `iris show`. The bytes come back
transfer-encoded; `TransferEncoding.decoded(_:encoding:)` decodes base64 and
quoted-printable with SwiftMail's public `Data.decoded(for:)`. Any section
in the structure downloads, also one inside a forwarded message (`2.1`).

`MailWriteClient` refines `MailClient` with the calls that change mail:
`select(mailbox:)` (SELECT, read-write), `setSeen(_:uid:)` (UID STORE
+FLAGS or -FLAGS `\Seen`), and `appendDraft(_:to:)` (APPEND with the
flags `\Seen \Draft`). Only `MailWriter` holds one; `MailReader` holds a
plain `MailClient`, so it cannot reach them. `SwiftMailClient` and
`FakeMailClient` conform to both. `MailWriter` SELECTs the mailbox (encoded
like EXAMINE), fetches the envelope by UID to check that the message exists
(STORE answers OK for a missing UID), then STOREs. `read` always adds
`\Seen` and `unread` always removes it, never a toggle, so both are idempotent.

`MailWriter.saveReply` takes two sessions: a `MailReader` reads the original
(`rawMessage(_:)`, decoded with `MessageFormatter.document`, as `show` and
`thread` decode a message), and `saveDraft(_:)` saves the reply that `ReplyComposer`
built (pure; it needs no fake). `saveDraft` finds the `\Drafts` mailbox in
the merged LIST, APPENDs to its wire name, and makes the iris ID from the
decoded name (it also puts that name back into a `draftMayBeSaved` or
`draftRefused` error).
`appendDraft` calls SwiftMail's `createDraft(from:in:additionalFlags:)`,
which adds the `\Draft` flag and `X-Uniform-Type-Identifier:
com.apple.mail-draft`; iris adds `\Seen`
(`SwiftMailClient.additionalDraftFlags`), as Apple Mail saves its own
drafts, so other mail apps do not show the new draft as unread. Both
sessions log in through `SwiftMailClient.login()`, so a Google account
sends AUTHENTICATE XOAUTH2 to save a draft as it does to read.

The files of `draft --attach` are read before either session: the CLI
calls `DraftAttachment.read(path:)` for each path before it reads the
reply, so a bad path (`draftAttachmentNotRead`, `draftAttachmentIsAFolder`)
fails before login. Each `--attach` takes one value (`.singleValue`), so in
`--attach a.pdf b.pdf` (or a glob that matched two files) `b.pdf` is the
reply argument: `DraftBody.read(..., attaching:)` turns an argument that
names a file or folder that exists into `draftBodyNamesAFile` when there are
attachments. `DraftAttachment.read` reads through SwiftMail's `Attachment(fileURL:)`,
so the MIME type comes from SwiftMail's table by extension (internal to
SwiftMail; `application/octet-stream` when unknown), and iris keeps no
copy of it. `saveReply(..., attachments:)` passes them to `ReplyComposer`,
which puts them in `DraftMessage.attachments` unchanged, and `Email(draft:)`
makes each one a regular SwiftMail `Attachment` (`isInline: false`).
SwiftMail then writes multipart/mixed: the multipart/alternative first, then
one base64 part per file with `Content-Disposition: attachment`. With no
attachments, `Email.attachments` is nil, so the draft is the
multipart/alternative it was before `--attach`.

`thread` (`MailReader.thread`) is one session too. It reads only headers
until it knows the thread: `fetchThreadHeaders` (UID FETCH of
`BODY.PEEK[HEADER.FIELDS (Message-ID In-Reply-To References Subject Date)]`
and INTERNALDATE). It searches INBOX, each `\Sent`, `\Drafts`, `\Archive`,
and `\All` mailbox, and the input mailbox (`threadMailboxes`), the input
mailbox first because it is open already. Each gets one SUBJECT search
(`searchUIDs(subjectContainingAll:)`, one SUBJECT key per text, ANDed) for
the subject that `ThreadSubject.normalized` gives (no `Re:`/`Fwd:`/`Fw:` or
`[tags]`). `subjectSearches(for:)` lists what to try: the whole subject,
then its ASCII words (`ThreadSubject.asciiWords`). A search that is refused
(`searchFailed`), or that misses the input message in its own mailbox, is
dropped for the rest of the walk; when none is left, one `IrisLog` line
says so. Only the mailboxes with no SUBJECT search get HEADER Message-ID
searches (`searchUIDs(messageIDs:)`, at most `messageIDSearchChunkSize` IDs
each), round after round. Messages with the subject that name a known ID
join until none joins. Each Message-ID is shown once, from the first
mailbox in `threadMailboxes` order (lowest UID). That walk (`threadWalk`)
gives those copies, oldest first, from headers alone. `MailReader.threadIDs`
stops there (`thread --format id`), so it downloads nothing; `thread` then
downloads only those copies with `fetchRawMessage` (`threadDownloads`), in
the same session, mailbox by mailbox in name order, each opened once (not
at all when it is the one the walk's last EXAMINE left open, which
`ThreadWalk.openMailbox` records). A download that times out or
finds the message gone is kept as a `ThreadMessage.DownloadFailure`, and
the mailbox is examined again before the next download (SwiftMail
reconnects after a timeout, with no mailbox open). `MessageFormatter.render(thread:)`
leaves out a message that failed, or that cannot be decoded, and logs one
line for it (`leftOutLine`); when none is left to show, it throws the error
of the input message (`ThreadMessage.isInput`), as `show` would. The
decoder's notes about the part shown go through its `log` parameter, which
`render(thread:)` prefixes with the message's iris ID. An empty subject also
logs one line, as a refused SUBJECT search does. Every other error fails
the command.

Tests never touch the network: no test reaches another host. They use
`FakeMailClient`, which returns scripted results and records the calls. For
`thread` it holds whole mailboxes (`mailboxMessages`) and searches them the
way Zoho did in the 2026-10-24 probes (`SearchRules.zoho`), or by RFC 3501
(`.rfc3501`); `refusesNonASCII` models a server that refuses non-ASCII
SEARCH text, and `rawMessageErrors` a message that does not download (after
a timeout no mailbox is open, as after SwiftMail's reconnect). For
`download` it holds each UID's `structures` and `parts` (the bytes still
transfer-encoded), and fails `fetchStructure` for a UID it does not have,
as SwiftMail does. The
Google code has its own seams: `HTTPTransport` (tests use `StubTransport`)
and `RedirectReceiver` (tests use `FakeRedirectReceiver`, whose `open` is the
browser opener). One test opens a socket: `LoopbackServerTests` runs the
real `LoopbackServer`, which binds 127.0.0.1 only, and sends it the
favicon request and the redirect over loopback.

### Accounts

Each account is a group of keys, `IRIS_<NAME>_IMAP_HOST`, `_PORT` (optional,
993), `_USERNAME`, `_PASSWORD`, plus `IRIS_DEFAULT_ACCOUNT`. The name may have
underscores because the suffix is fixed. The process environment wins over
`.env`; the nearest `.env` wins over a parent's. Commands resolve the account
once, at the start, through `AccountOptions.resolve()`. A command that takes
an `IrisID` (such as `show`, `thread`, `read`, and `download`) has no `--account`: it resolves the account that
the ID names, with `AccountResolver.resolve(name:settings:)`. `auth status`
has its own `--account`: leaving it out checks every Google account, not the
default one, through `GoogleSignInStatus.check`. Resolver functions take
the settings as a parameter, so tests never read the real environment.

An account with `IRIS_<NAME>_GOOGLE_CLIENT_ID` signs in with Google
(OAuth, XOAUTH2) instead of a password. It needs `_IMAP_HOST`,
`_IMAP_USERNAME` (the address chosen at sign-in; XOAUTH2's `user=` and the
`login_hint`), `_GOOGLE_CLIENT_ID`, `_GOOGLE_CLIENT_SECRET`, and
`_GOOGLE_REFRESH_TOKEN`, which `iris auth login` writes. Then
`Account.authentication` is `.google(client, refreshToken:)`, else
`.password`. A Google account with `_IMAP_PASSWORD` too is an
`invalidSetting`; a missing refresh token is `googleNotSignedIn`, which
names `iris auth login`. `iris auth login` cannot use `resolve` (it has no
refresh token yet): it uses `resolveGoogleSignIn(name:settings:)` (username,
client ID, client secret), and `saveGoogleRefreshToken` writes the token
into the `.env` that sets the client ID. It returns a `RefreshTokenSave`
(saved, client ID only in the environment, or write failed) whose
`stdoutLine` and `message` the CLI prints unchanged, as `list` prints its hint.

`IRIS_<NAME>_FROM` (optional) is the From line of drafts, read only by
`AccountResolver.fromAddress(for:in:)`; without it, the username (for a
Google account, the address chosen at sign-in) is used when it is an
address, else `draftFromAddressMissing` names the key. It is not an
`AccountResolver.Field`: reading needs no From address, so the key alone
does not make an account, and `iris accounts` does not check it.

Never put a secret in an error message, a log line, or JSON output: the
password, the client secret, the refresh token, the access token, the code,
or the PKCE verifier. `Account.secrets` lists an account's secrets, and
`Redaction.redacting(_:in:)` removes them from server text and from the
token endpoint's answers (`SwiftMailClient` adds the access token during
AUTHENTICATE). The one exception: when `iris auth login` does not write
`.env` (no `.env` sets the client ID, or the write fails), it prints the
refresh token's `KEY=value` line (`RefreshTokenSave.stdoutLine`) on stdout
for the user to save.

### Output

- A message is always named by its iris ID (`IrisID`), `<account>/<mailbox>/<UID>`
  (for example `work/INBOX/4821`), in every output and every argument. Never
  show or take a UID alone: UIDs repeat in every mailbox. Parse it with
  `IrisID(parsing:)` (account before the first `/`, UID after the last, the
  mailbox between), and take it as an `@Argument` with
  `transform: IrisID.init(parsing:)`, so a bad ID explains the form. The
  mailbox is the decoded name. JSON encodes it as one string, with the key
  `irisID`.
- Make an `IrisID` only with `IrisID(account:mailbox:uid:)` or
  `IrisID(parsing:)`, never by joining strings: both lowercase the account
  and write INBOX in any case as `INBOX`, so one message has one ID. Compare
  mailboxes through `IrisID`, not with the typed `--mailbox`.
- Words: user-facing text says "iris ID" for the `IrisID`. "Message ID"
  means only the `Message-ID` header (`messageID` in `show --format json`).
- List commands (`accounts`, `mailboxes`, `list`, `auth status`) take `--format
  table|json|jsonl|id`, default `table` (`OutputFormat.listDefault`: use it
  for `--format`, never the literal), through `OutputFormatter` and the
  `IrisRow` protocol. `OutputFormatter.render` returns the exact stdout text
  (every line ends with `\n`; for zero rows, `json` is `[]`, `table` is the
  header line, and `jsonl`/`id` are empty), and the CLI writes it unchanged
  with `CLI.printRows`. Output is deterministic: sorted JSON keys, no trailing
  whitespace in tables, and cells padded by `Character` (emoji are safe).
  Table columns line up on the left, except those a row names in
  `rightAlignedColumns` (such as `list`'s `UNREAD`).
- The next-page hint keeps `--account`, `--mailbox`, the filter options
  (`MessageFilter.options`), `--limit`, and `--format`, and is written to
  stderr for every format.
- `show` takes `--format markdown|json|raw`, default `markdown`. Markdown and
  JSON show the iris ID (`MessageFormatter.render` sets
  `MessageDocument.irisID`); `raw` is the exact message source, never changed.
  Markdown and JSON also show `appleMailURL`, the `message:` URL that opens
  the message in Apple Mail. `MessageDocument` makes it from `messageID` with
  `AppleMailURL`, so it is nil when there is no `Message-ID` header.
- Every attachment that `show` and `thread` list (`MessageAttachment`) has
  an attachment ID (`AttachmentID`), the part's MIME section from
  `MessageDecoder.attachments(of:)`: first on its Markdown line, in code
  (`` - `2` report.pdf (application/pdf, 120 KB) ``), and `attachmentID`, a
  string such as `"1.2"`, in JSON. Parse it with `AttachmentID(parsing:)`
  and take it as an `@Argument` with `transform: AttachmentID.init(parsing:)`.
  Words: user-facing text says "attachment ID". `show` and `thread` never
  include attachment bytes.
- `download` writes the attachment's decoded bytes to stdout, exactly, with
  nothing else (as `show --format raw` writes a message), or, with `-o`,
  saves a new file and writes its path and a newline.
  `AttachmentOutput(path:stdoutIsTerminal:)` picks one before the download:
  without `-o`, a terminal on stdout is `attachmentStdoutIsTerminal`, so
  binary never lands in a terminal. The CLI checks `isatty` and passes it
  in, as `draft` passes `stdinIsTerminal`. `-o` naming a folder saves under
  `AttachmentOutput.safeFilename(_:attachmentID:)`: the filename comes from
  the sender, so only its last path component, without control characters,
  leading dots, or outer white space, else `attachment-<id>`. A file is
  never overwritten (`.withoutOverwriting`): `attachmentFileExists` says to
  pass another `-o`.
- `thread` takes `--format markdown|json|jsonl|id` (`ThreadOutputFormat`),
  default `markdown`. Its `messagesFormat` is the `ThreadMessagesFormat`
  of `MessageFormatter.render(thread:format:body:timeZone:)`, which prints
  the downloaded messages: each message as `show` prints it, oldest first,
  with a `* * *` line between messages, a JSON array of the
  `show --format json` objects, or those objects one per line (compact,
  sorted keys, as the list commands' `jsonl`). For `id` it is nil: one iris
  ID per line, as `list --format id` writes them, which the CLI gets from
  `MailReader.threadIDs` and prints with `MessageFormatter.render(threadIDs:)`,
  so it downloads and leaves out nothing, and only the walk's own lines go
  to stderr.
- `draft` writes the new draft's iris ID and a newline to stdout, made with
  `IrisID(account:mailbox:uid:)` from the decoded Drafts name and the
  APPENDUID UID. Without a UID (no UIDPLUS), stdout is empty, and
  `SavedDraft.missingIDNote` goes to stderr.
- Hints (such as the next-page command) and errors go to stderr. stdout holds
  only data.

## Recipes

### Add a command

1. Put the logic in IrisKit (a `MailReader` method, or a `MailWriter` method
   for a write command) with tests over `FakeMailClient`.
2. If it needs a new IMAP call, add it to `MailClient` (or to
   `MailWriteClient` if it changes mail), implement it in `SwiftMailClient`
   (types and errors only), and script it in `FakeMailClient`.
3. Add `Sources/iris/Commands/<Name>Command.swift`: `@OptionGroup var
   accountOptions: AccountOptions` (but a command that takes an `IrisID`
   has no `--account`, and `auth status` has its own, where leaving it out
   means every Google account; see "Accounts"), options (a list command uses
   `var format: OutputFormat = .listDefault`), and a `run()` of a few lines.
   Register it (see "Read-only and write commands"). When the command's name
   is also a Foundation type (`Thread`), name the struct `<Name>Command` and
   set `commandName`, or the tests cannot tell the two apart.
4. Add parse tests in `Tests/CLITests/ArgumentParsingTests.swift`.
5. Update README.md ("What works today", "Usage") and remove the item from
   `plans/roadmap.md`.

### Read-only and write commands

`iris ro <command>` holds only the read-only commands, so Adam can allow an
agent `Bash(iris ro:*)` and nothing else. `Sources/iris/Commands/ReadOnlyCommand.swift`
enforces it:

- A **read-only** command (it cannot send, draft, move, flag, or delete) is
  declared `struct X: ReadOnlyCommand` and added to `ReadOnly.sharedCommands`.
  It then appears both as `iris x` and `iris ro x`.
- A **write** command (such as `read`, `unread`, `draft`, and `download`)
  is declared `struct X: AsyncParsableCommand` and added only to
  `Iris.configuration.subcommands`, after the read-only ones. Never
  mark it `ReadOnlyCommand`: `ReadOnly.commands` is typed
  `[any ReadOnlyCommand.Type]`, so the compiler keeps write commands out of
  `ro`.
- A **group with both kinds** cannot be a `ReadOnlyCommand`. `auth` is one:
  `iris auth login` writes `.env`, and `iris auth status` only reads. Give
  it two forms: the full group (`Auth`, with `login` and `status`) in
  `Iris.configuration.subcommands` after the shared commands, and a second
  group, also named `auth` (`ReadOnlyAuth`), in `ReadOnly.commands` (not in
  `sharedCommands`) whose children are typed `[any ReadOnlyCommand.Type]`
  (only `Auth.Status`). Both use the same leaf types, so `iris ro auth status`
  behaves like `iris auth status`, and `iris ro auth login` fails to parse.
  `draft` is a write command, not a group; a future `drafts` group (`list`
  and `new`) would work the same way as `auth`.
- A **write command whose ro form drops the options that write** cannot
  be a `ReadOnlyCommand` either. `download` is one: `-o` writes a file
  whose content and name come from the sender, and without `-o` it only
  writes the bytes to stdout. Give it two types: the full command
  (`Download`, with `-o`) in `Iris.configuration.subcommands` after the
  shared commands, and a second type with the same `commandName`
  (`ReadOnlyDownload`, without `-o`) in `ReadOnly.commands` (not in
  `sharedCommands`). Both take one `@OptionGroup` (`DownloadArguments`, the
  iris ID and the attachment ID) and call its one `run(outputPath:)`, so
  they cannot drift; `iris ro download ... -o x` fails to parse. The reason:
  under `ro`, iris writes nothing to disk itself. The bytes go to stdout, so
  any file write is done by the caller's shell, inside the agent's sandbox
  and permission rules, never by iris at a path the sandbox does not cover.
  Its IMAP calls stay read calls in `MailReader` (EXAMINE and PEEK):
  downloading never changes mail.
- Keep write calls out of `MailReader` and out of the IMAP calls it uses: put
  them in `MailWriter` and `MailWriteClient` (see "The IMAP seam"), so a
  read-only command cannot reach them.

`ReadOnlyCommandTests` checks that `ro` has only read-only commands, that
every read-only command is in both places (also the read-only children of a
group with both kinds), that the rest of `ro` is the read-only form of a
top-level write command (`auth`, `download`), and that
`iris ro <write command>` and `iris ro download -o` fail.

### Add an error

Add a case to `IrisError` in its section (`// IMAP`, `// Message rendering`,
`// Drafts`, `// Attachments`, `// Google sign-in`) with an `errorDescription` that says what the user can
do next. Map library errors to it in one place (for IMAP,
`SwiftMailClient.irisError(for:command:account:accessToken:)`, with a test in
`SwiftMailClientTests`; for Google's token endpoint,
`GoogleTokenEndpoint.error(for:grant:secrets:account:)`, with a test in
`GoogleTokenEndpointTests`). A next-step command in the message names the
account (`--account <name>`).

## Gotchas

- **SwiftMail is pinned by revision** (`88c45cbd` = 1.16.0). SwiftPM cannot
  resolve it by version, because it pins swift-nio-imap by revision. To bump
  it, change the revision in `Package.swift`, then run `swift package resolve`
  (never edit `Package.resolved` by hand). Read SwiftMail's source in
  `.build/checkouts/SwiftMail`; its README is behind the code.
- **10 second deadlines:** every SwiftMail FETCH gives up after 10 seconds
  (fixed in SwiftMail). `fetchRawMessage` turns that into
  `messageDownloadTimedOut`. `fetchEnvelopes` and `fetchThreadHeaders` use
  the chunked `fetchMessageInfos(using:options:headerFields:chunkSize:)`
  stream (`envelopeChunkSize`, 100 messages per FETCH), so each chunk has
  its own deadline. Any other timeout after login is
  `serverTimedOut`; before login it is `connectionFailed`. In the same way, a
  broken connection (a closed channel, BYE, or a network error) is
  `connectionFailed` on connect and LOGIN (or AUTHENTICATE), and `connectionLost` after it,
  so only the first one tells the user to check the host and port. APPEND
  has 30 seconds (`AppendCommand.timeoutSeconds`). A timeout or a broken
  connection during APPEND is `draftMayBeSaved` instead, because the server
  may have saved the draft: it names the Drafts mailbox to look in before
  trying again.
- **A large draft fails in three ways:** base64 makes each attached file
  about 4/3 of its size, and every limit counts the whole message.
  - `draftTooLarge`, only when the server announces APPENDLIMIT: SwiftMail
    checks the size before it sends (`IMAPError.appendLimitExceeded`).
  - `draftRefused`, when it announces none (Zoho) and answers APPEND with
    a tagged NO or BAD (`commandFailed`). Every IMAPError on `.append`
    that is not one of the other two cases (or `connectionFailed`) maps
    here, so a full mailbox lands here too; `serverError`'s advice (`iris
    check`) never fits a refused draft.
  - `draftMayBeSaved`, on a timeout: APPEND has 30 seconds
    (`AppendCommand.timeoutSeconds`, fixed in SwiftMail), and the clock
    starts when the APPEND line is flushed, before the message bytes go
    out, so a large attachment on a slow uplink can run out of time.
- **Attachment filenames:** SwiftMail writes a filename of printable ASCII
  as `filename="..."`, and any other (non-ASCII, `"`, `\`, a control
  character) as one RFC 2231 parameter, `filename*=UTF-8''R%C3%A9sum%C3%A9.pdf`
  (`MIMEHeaderEncoding`). A regular attachment gets no `name=` on its
  Content-Type. SwiftMail sends a `text/calendar` part with a `method`
  parameter as an invite, not base64; a type from an extension (`.ics` is
  `text/calendar`) never has one.
- **60 seconds for one part:** `download` fetches only the attachment, with
  SwiftMail's `fetchPart(section:of:)` (`FetchMessagePartCommand.timeoutSeconds`,
  fixed at 60, `SwiftMailClient.partTimeoutSeconds`). It never uses
  `fetchRawMessage`: its 10 seconds fail large messages, and attachments are
  what make a message large. A part-fetch timeout is
  `attachmentDownloadTimedOut`; a BODYSTRUCTURE timeout (10 seconds, but a
  few hundred bytes) is `serverTimedOut`. No chunked or ranged fetch is
  built, so an attachment that takes more than 60 seconds fails
  (`plans/roadmap.md`, "Known limits").
- **message/rfc822 sections:** EMLParser (`show`) keeps a forwarded message
  as one part and does not open it, so the part after it is `3`, not a
  section inside it. SwiftMail's BODYSTRUCTURE conversion
  (`[MessagePart](BodyStructure)`) keeps the message/rfc822 part at its own
  section and then adds its inner parts (`2`, `2.1`, `2.2`; SwiftMail's
  `rfc822InsideMultipartMixed` test pins this). So every ID that `show`
  lists is in the structure, and `BODY[2]` gives the whole forwarded
  message, an `.eml`. BODYSTRUCTURE also names a message/rfc822 part from
  its subject (`Plans.eml`) when it has no filename, and falls back to the
  Content-ID, so `download` may save a name that `show` does not list.
- **Mailbox names are modified UTF-7** on the wire (RFC 3501 5.1.3):
  `[Gmail]/Entw&APw-rfe`, `R&-D`. SwiftMail keeps the wire form, and
  `MailClient` (and `FakeMailClient`) use wire names only. `MailReader`
  decodes in `mailboxes()` and encodes before EXAMINE, and `MailWriter`
  encodes before SELECT, APPENDs to the Drafts mailbox by the wire name
  from LIST, and decodes that name for the iris ID. Users only see and type
  the decoded names.
- **Transport security:** iris passes `.startTLS` for port 143 and
  `.implicitTLS` for every other port. SwiftMail's `.automatic` would continue
  in plain text on 143 when the server has no STARTTLS.
- **Read-only:** `MailReader` uses EXAMINE, never SELECT, and `BODY.PEEK[]`
  (`BODY.PEEK[<section>]` for one part), so reading never sets `\Seen`.
  Only `MailWriter` SELECTs, for the STORE.
- **UIDs** belong to one mailbox. A missing UID gets an empty answer, not an
  error (FETCH returns nothing, and STORE answers OK); `MailReader` and
  `MailWriter` turn that into `unknownMessage`. SwiftMail's `fetchStructure`
  throws instead (`fetchFailed`, "No body structure received"), so
  `MailReader.attachment` fetches the envelope first, as `MailWriter` does
  before STORE.
- **SEARCH days:** SwiftMail takes a `Date` for SINCE and BEFORE and turns
  it into a day with the `Calendar` it is given. Its `IMAPCalendarDay`
  holds only the years 1900 to 2500, and SwiftMail stops the program
  (a force unwrap) for other years. So `CalendarDay(parsing:)` rejects those
  years, and `searchUIDs` passes `CalendarDay.calendar` (UTC), the calendar
  that made `CalendarDay.start`, so no time zone moves the day.
- **Quoted ENVELOPE names:** Zoho keeps the header's quotes in the ENVELOPE
  name (`"\"Doe, Jane\""`), and SwiftMail passes them on. `MailAddress.init`
  removes the quotes of a name that is one quoted-string, for every address.
- **Servers search a word index, not the text** (Zoho probes, 2026-10-24).
  HEADER Message-ID matches the whole ID, with or without `< >`. HEADER
  In-Reply-To and HEADER References never match, in any form, even when the
  header holds the ID, so a header walk finds only the ancestors that a
  known message names, never the replies; `thread` finds replies through
  SUBJECT. SUBJECT matches whole words ("Champ" does not find "Champion");
  several SUBJECT keys AND correctly. A word ends at punctuation, `-`, `.`,
  `@`, `_`, and the curly apostrophe ("bill" finds "bill’s"), but not at an
  ASCII apostrophe ("don" does not find "don't"; "vanguard" does find
  "Vanguard's"). A key of only a word shorter than 3 ("ai") finds nothing.
  Zoho accepted non-ASCII SUBJECT text (curly apostrophe, emoji, em dash,
  "café"), which SwiftMail sends with CHARSET UTF-8; other servers may
  refuse it (`searchFailed`), hence the ASCII-words retry. An OR tree of
  HEADER keys that mixed in In-Reply-To/References keys gave wrong answers
  (the same matching key found the message with 3, 6, and 12 keys but not
  with 9 or 15 to 18), so `thread` sends only Message-ID keys, at most 10
  per SEARCH. TEXT (`list --search`) with a Message-ID matches nothing;
  TEXT and TO (`list --to`) were not probed with words. Gmail's SEARCH is
  also index-based; check it before relying on RFC 3501 substring matching
  anywhere.
- **Special-use:** a plain LIST may leave out the attributes, so
  `SwiftMailClient.listMailboxes` merges LIST with LIST RETURN (SPECIAL-USE).
  Servers without SPECIAL-USE get SwiftMail's guess from mailbox names.
- **EMLParser:** a `Date:` header with a trailing comment such as `(CDT)`
  gives nil, so `HeaderDate` reads it from the raw bytes. In-Reply-To and
  References are only in `additionalFields`. A quoted non-Latin charset
  (`charset="koi8-r"`) is not recognized (SwiftMail PR #268).
- **Body parts:** SwiftMail keeps only the leaf parts, not the multipart
  subtypes. iris joins every text/plain (or text/html) part that is not an
  attachment into the body (Apple Mail splits the body around attachments),
  lists every other part, and leaves out only a known list of other
  renditions (`MessageDecoder.otherRenditionTypes`, such as Gmail's
  `text/x-amp-html`) that sit next to a body part.
- **libxml2** obeys a `<meta charset>` over the encoding it is given, so
  `MessageDecoder.declaringUTF8` points every `<meta>` charset at UTF-8 (the
  text is already decoded).
- **Draft headers:** SwiftMail writes `Email.additionalHeaders` values
  unchanged and unfolded, so `DraftMessage.folded` folds References between
  IDs, and `ReplyComposer` drops a message ID with white space or a control
  character (it could break the header). SwiftMail's `constructContent` adds
  Date (now) and a new Message-ID.
- **HTMLFormatter** (swift-markdown) writes text, code, and link targets
  without escaping them, and passes raw HTML through. `MarkdownHTML` escapes
  them first, and turns raw HTML into text: the quoted original is untrusted,
  so iris never emits HTML that it did not make. It writes a soft break as a
  bare newline (a space in HTML), so `MarkdownHTML` makes each one a line
  break, and it drops `cid:` images (SwiftText keeps an original's
  `<img src="cid:...">`, which the draft has no part for). It also parses
  with `.disableSmartOpts`, so the HTML part has the same quotes and dashes
  as the text part.
- **No setext headings:** a line of only `-` or `=` under a text line (the
  `-- ` signature separator, RFC 3676) would make the lines above it one
  `<h2>`. `MarkdownHTML` turns a setext heading back into a paragraph with
  its underline as text, joined to a paragraph on the next line, in the
  tree, so a code block is never touched. swift-cmark ends a setext
  heading's range on the line that closed it (the line after the underline,
  or the underline at the end of the input), not on the underline, so the
  underline is found by scanning the source lines inside the range for the
  first line of only `-` or `=`; an ATX heading (`# Title`) has a one-line
  range and stays a heading.
- **The HTML quote:** only an original whose body came from HTML
  (`bodySource == .html`) is rendered as Markdown. A text/plain original is
  escaped line by line (`MarkdownHTML.html(fromPlainText:)`), because as
  Markdown a `-- ` signature line makes the line above it a heading. The
  text part quotes both kinds with `> `.
- **swift-log:** SwiftMail logs at `.info` to stderr by default, and logs
  every failed command at `.error`. iris reports each failure itself as an
  `IrisError`, so `CLI.bootstrapSwiftLog()` keeps only `.critical`. Only the
  executable depends on swift-log.
- **Google OAuth, 7 days:** Adam's Google Cloud app is External and in
  Testing, so Google ends each refresh token after 7 days (and when the
  Google password changes). The refresh then answers HTTP 400
  `invalid_grant`, which `GoogleTokenEndpoint` turns into
  `googleSignInExpired` (sign in again). `invalid_grant` from the code
  exchange is a failed sign-in, not an expired one. `invalid_client`,
  `unauthorized_client`, and `deleted_client` (the client, or its Cloud
  project, was deleted) are `googleClientRejected`, which names the client keys.
- **Refresh token only with consent:** Google sends a refresh token only
  with `access_type=offline`, and on a later sign-in only with
  `prompt=consent`, so the sign-in URL has both. No refresh token is
  `googleNoRefreshToken` (remove the app's access at
  myaccount.google.com/permissions). A grant without
  `https://mail.google.com/` (the user can untick it) is refused in
  `GoogleSignIn.refreshToken(from:account:)`: IMAP needs that scope.
- **Loopback redirect:** Google has no copy-and-paste flow for installed
  apps, so `LoopbackServer` listens on 127.0.0.1 on a port the system picks,
  and the redirect URI is `http://127.0.0.1:<port>`; the exchange must send
  the same URI. `waitForRedirect` registers its continuation before it calls
  back to open the browser, ignores requests with neither `code` nor `error`
  (`/favicon.ico`), and gives up after 300 seconds; each wait has a number,
  so an earlier wait's timeout never ends a later wait. No semaphores: the
  listener's start waits on a continuation.
- **PKCE and state:** each sign-in makes a new random state and PKCE
  verifier (`OAuthRandom`, `SystemRandomNumberGenerator`). The page gets
  `code_challenge` (base64url SHA-256, `S256`); the exchange sends
  `code_verifier`. The redirect is checked for the state first, then
  `error`, then `code`.
- **`+` in URLs:** `URLComponents` leaves `+` in a query, and Google reads it
  as a space. `GoogleURL.build` and `FormEncoder` encode everything but
  unreserved ASCII, so `me+tag@gmail.com` stays intact.
- **Key names are per account:** never use graham's plain `GOOGLE_*` keys.
  Both tools read and write the nearest `.env`, so shared names would
  overwrite each other's refresh tokens.
- **XOAUTH2 errors:** SwiftMail reports a refused token as
  `IMAPError.authFailed` (the tagged NO, then Gmail's decoded JSON
  challenge). On `Command.authenticate` that is `googleLoginRefused`, not
  `loginFailed` with its app-password advice. A server without
  `AUTH=XOAUTH2` (`unsupportedAuthMechanism`) points at the host key.
- **Adam's global gitignore ignores folders named `Output/`.** Do not put
  sources in one. After adding files, check `git status --short --ignored`.

## Commands

```sh
swift build
swift test
swift test --filter MailReaderTests
swift run iris --help
swift run iris list --account work
```

Git: never use `git -C`. Use `grep`, not `rg`.
