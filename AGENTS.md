# AGENTS.md

Instructions for agents (Claude, Codex, and others) that work in this repo.

## What this is

`iris` is a command-line email reader over IMAP. It follows the structure of
Adam's other CLIs, `graham` (Google Workspace) and `hunch` (Notion): a library
with all the logic (`IrisKit`) and a thin executable (`iris`) built on
swift-argument-parser.

iris does not write its own IMAP or MIME code. It uses SwiftMail for both, and
SwiftText to turn HTML into Markdown. The reasons, the alternatives, and the
risks are in `plans/research/imap-libraries.md`.

## Architecture

**The one rule:** if it can be unit-tested, it belongs in `IrisKit`. The
executable only parses arguments, calls the library, and prints. IrisKit never
prints: it logs through `IrisLog`, and the executable decides where the lines
go (stderr).

```
Sources/IrisKit/
  Config/      DotEnv (.env loader, and setValue for the refresh token),
               AccountResolver (named accounts), Account (+ GoogleClient),
               RefreshTokenSave (where `iris auth login` put the token, and
               its stdout line and stderr message)
  Auth/        Google OAuth: HTTPTransport (the HTTP seam, URLSessionTransport,
               FormEncoder), GoogleTokenEndpoint (refresh and code exchange),
               GoogleSignIn (`iris auth login`: consent URL, PKCE, redirect
               checks), LoopbackServer (the 127.0.0.1 redirect listener),
               GoogleURL (query escaping), GoogleSignInStatus (`iris auth
               status`: the keys set and one refresh per account)
  Mail/        MailClient (the IMAP seam), SwiftMailClient (the real one),
               MailReader (sessions, paging, errors), MailModels (rows, pages),
               MailWriter (the calls that change mail: read and unread),
               MessageFilter (the `list` filter options, sent as UID SEARCH),
               IrisID (the iris ID, the one message name, <account>/<mailbox>/<UID>)
  Message/     MessageDecoder (raw RFC 822 -> MessageDocument), FlowedText,
               BodyCleanup, HeaderDate, MessageFormatter (Markdown/JSON/raw),
               AppleMailURL (the message: URL from the Message-ID header)
  Helpers/     OutputFormatter (table/json/jsonl/id for list commands),
               MailAddress (the one address type), DateText, ModifiedUTF7,
               CalendarDay (a YYYY-MM-DD day for --since and --before),
               Redaction (removes secrets from text that iris shows)
  IrisError.swift   the one error type; each message says what to do next
  IrisLog.swift     the logging seam
Sources/iris/
  Iris.swift        @main root command; ExpressibleByArgument conformances
  CLISupport.swift  log handler, swift-log bootstrap, AccountOptions (--account),
                    ArgumentHelp.irisID (the help for every iris ID argument)
  Commands/         one file per command
Tests/IrisKitTests/ offline library tests (LoopbackServerTests binds 127.0.0.1);
                    Support/ has FakeMailClient, StubTransport (HTTP), and
                    FakeRedirectReceiver (sign-in)
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
(`searchCriteria(for:)`), the STORE operation (`storeOperation(seen:)`),
`MailboxInfo(swiftMail:)`, and `MessageEnvelope(swiftMail:)`.

`MailWriteClient` refines `MailClient` with the calls that change mail:
`select(mailbox:)` (SELECT, read-write) and `setSeen(_:uid:)` (UID STORE
+FLAGS or -FLAGS `\Seen`). Only `MailWriter` holds one; `MailReader` holds a
plain `MailClient`, so it cannot reach them. `SwiftMailClient` and
`FakeMailClient` conform to both. `MailWriter` SELECTs the mailbox (encoded
like EXAMINE), fetches the envelope by UID to check that the message exists
(STORE answers OK for a missing UID), then STOREs. `read` always adds
`\Seen` and `unread` always removes it, never a toggle, so both are idempotent.

Tests never touch the network: no test reaches another host. They use
`FakeMailClient`, which returns scripted results and records the calls. The
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
an `IrisID` (such as `show` and `read`) has no `--account`: it resolves the account that
the ID names, with `AccountResolver.resolve(name:settings:)`. Resolver functions take
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
   has no `--account`; see "Accounts"), options (a list command uses
   `var format: OutputFormat = .listDefault`), and a `run()` of a few lines.
   Register it (see "Read-only and write commands").
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
- A **write** command (such as `read` and `unread`) is declared
  `struct X: AsyncParsableCommand` and added only to
  `Iris.configuration.subcommands`, after the read-only ones. Never
  mark it `ReadOnlyCommand`: `ReadOnly.commands` is typed
  `[any ReadOnlyCommand.Type]`, so the compiler keeps write commands out of
  `ro`. `iris auth login` is one: it opens a browser and writes `.env`.
- A **group with both kinds** cannot be a `ReadOnlyCommand`. `auth` is one:
  `iris auth login` writes `.env`, and `iris auth status` only reads. Give
  it two forms: the full group (`Auth`, with `login` and `status`) in
  `Iris.configuration.subcommands` after the shared commands, and a second
  group, also named `auth` (`ReadOnlyAuth`), in `ReadOnly.commands` (not in
  `sharedCommands`) whose children are typed `[any ReadOnlyCommand.Type]`
  (only `Auth.Status`). Both use the same leaf types, so `iris ro auth status`
  behaves like `iris auth status`, and `iris ro auth login` fails to parse.
  A future `draft` group (`show` and `new`) works the same way.
- Keep write calls out of `MailReader` and out of the IMAP calls it uses: put
  them in `MailWriter` and `MailWriteClient` (see "The IMAP seam"), so a
  read-only command cannot reach them.

`ReadOnlyCommandTests` checks that `ro` has only read-only commands, that
every read-only command is in both places (also the read-only children of a
group with both kinds), and that `iris ro <write command>` fails.

### Add an error

Add a case to `IrisError` in its section (`// IMAP`, `// Message rendering`,
`// Google sign-in`) with an `errorDescription` that says what the user can
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
  `messageDownloadTimedOut`. `fetchEnvelopes` uses the chunked
  `fetchMessageInfos(using:options:chunkSize:)` stream (100 messages per
  FETCH), so each chunk has its own deadline. Any other timeout after login is
  `serverTimedOut`; before login it is `connectionFailed`. In the same way, a
  broken connection (a closed channel, BYE, or a network error) is
  `connectionFailed` on connect and LOGIN (or AUTHENTICATE), and `connectionLost` after it,
  so only the first one tells the user to check the host and port.
- **Mailbox names are modified UTF-7** on the wire (RFC 3501 5.1.3):
  `[Gmail]/Entw&APw-rfe`, `R&-D`. SwiftMail keeps the wire form, and
  `MailClient` (and `FakeMailClient`) use wire names only. `MailReader`
  decodes in `mailboxes()` and encodes before EXAMINE, and `MailWriter`
  encodes before SELECT. Users only see and type the decoded names.
- **Transport security:** iris passes `.startTLS` for port 143 and
  `.implicitTLS` for every other port. SwiftMail's `.automatic` would continue
  in plain text on 143 when the server has no STARTTLS.
- **Read-only:** `MailReader` uses EXAMINE, never SELECT, and `BODY.PEEK[]`,
  so reading never sets `\Seen`. Only `MailWriter` SELECTs, for the STORE.
- **UIDs** belong to one mailbox. A missing UID gets an empty answer, not an
  error (FETCH returns nothing, and STORE answers OK); `MailReader` and
  `MailWriter` turn that into `unknownMessage`.
- **SEARCH days:** SwiftMail takes a `Date` for SINCE and BEFORE and turns
  it into a day with the `Calendar` it is given. Its `IMAPCalendarDay`
  holds only the years 1900 to 2500, and SwiftMail stops the program
  (a force unwrap) for other years. So `CalendarDay(parsing:)` rejects those
  years, and `searchUIDs` passes `CalendarDay.calendar` (UTC), the calendar
  that made `CalendarDay.start`, so no time zone moves the day.
- **Quoted ENVELOPE names:** Zoho keeps the header's quotes in the ENVELOPE
  name (`"\"Doe, Jane\""`), and SwiftMail passes them on. `MailAddress.init`
  removes the quotes of a name that is one quoted-string, for every address.
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
