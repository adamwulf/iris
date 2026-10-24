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
  Config/      DotEnv (.env loader), AccountResolver (named accounts), Account
  Mail/        MailClient (the IMAP seam), SwiftMailClient (the real one),
               MailReader (sessions, paging, errors), MailModels (rows, pages)
  Message/     MessageDecoder (raw RFC 822 -> MessageDocument), FlowedText,
               BodyCleanup, HeaderDate, MessageFormatter (Markdown/JSON/raw)
  Helpers/     OutputFormatter (table/json/jsonl/id for list commands)
  IrisError.swift   the one error type; each message says what to do next
  IrisLog.swift     the logging seam
Sources/iris/
  Iris.swift        @main root command; ExpressibleByArgument conformances
  CLISupport.swift  log handler, swift-log bootstrap, AccountOptions (--account)
  Commands/         one file per command
Tests/IrisKitTests/ offline library tests; Support/FakeMailClient.swift
Tests/CLITests/     argument parsing only, never run()
```

### The IMAP seam

`MailClient` is the protocol for the few IMAP calls iris makes. One client is
one session: `login()`, the calls, then `logout()`. `MailReader` owns that
order (`withClient` logs out on success, on error, and after a failed login)
and holds all the logic: paging math, ordering, date fallback, and error
mapping. `SwiftMailClient` only converts SwiftMail types and errors; it has no
logic that a test would need, because it needs a server.

Tests never touch the network. They use `FakeMailClient`, which returns
scripted results and records the calls.

### Accounts

Each account is a group of keys, `IRIS_<NAME>_IMAP_HOST`, `_PORT` (optional,
993), `_USERNAME`, `_PASSWORD`, plus `IRIS_DEFAULT_ACCOUNT`. The name may have
underscores because the suffix is fixed. The process environment wins over
`.env`; the nearest `.env` wins over a parent's. Commands resolve the account
once, at the start, through `AccountOptions.resolve()`. Resolver functions take
the settings as a parameter, so tests never read the real environment.

Never put a password in an error message, a log line, or JSON output.
`SwiftMailClient.redacting` removes it from server text.

### Output

- List commands (`accounts`, `mailboxes`, `list`) take `--format
  table|json|jsonl|id`, default `table`, through `OutputFormatter` and the
  `IrisRow` protocol. Output is deterministic: sorted JSON keys, no trailing
  whitespace in tables.
- `show` takes `--format markdown|json|raw`, default `markdown`.
- Hints (such as the next-page command) and errors go to stderr. stdout holds
  only data.

## Recipes

### Add a command

1. Put the logic in IrisKit (usually a `MailReader` method) with tests over
   `FakeMailClient`.
2. If it needs a new IMAP call, add it to `MailClient`, implement it in
   `SwiftMailClient` (types and errors only), and script it in
   `FakeMailClient`.
3. Add `Sources/iris/Commands/<Name>Command.swift`: `@OptionGroup var
   accountOptions: AccountOptions`, options, and a `run()` of a few lines.
   Register it in `Iris.swift`.
4. Add parse tests in `Tests/CLITests/ArgumentParsingTests.swift`.
5. Update README.md ("What works today", "Usage") and remove the item from
   `plans/roadmap.md`.

### Add an error

Add a case to `IrisError` in its section (`// IMAP`, `// Message rendering`)
with an `errorDescription` that says what the user can do next. Map library
errors to it in one place (for IMAP, `SwiftMailClient.irisError(for:command:)`).

## Gotchas

- **SwiftMail is pinned by revision** (`88c45cbd` = 1.16.0). SwiftPM cannot
  resolve it by version, because it pins swift-nio-imap by revision. To bump
  it, change the revision in `Package.swift`, then run `swift package resolve`
  (never edit `Package.resolved` by hand). Read SwiftMail's source in
  `.build/checkouts/SwiftMail`; its README is behind the code.
- **Raw fetch deadline:** `fetchRawMessage` gives up after 10 seconds (fixed
  in SwiftMail). iris turns that into `messageDownloadTimedOut`.
- **Transport security:** iris passes `.startTLS` for port 143 and
  `.implicitTLS` for every other port. SwiftMail's `.automatic` would continue
  in plain text on 143 when the server has no STARTTLS.
- **Read-only:** use EXAMINE, never SELECT, and `BODY.PEEK[]`, so iris never
  sets `\Seen`.
- **UIDs** belong to one mailbox. A missing UID gets an empty answer, not an
  error; `MailReader` turns that into `unknownUID`.
- **Special-use:** a plain LIST may leave out the attributes, so
  `SwiftMailClient.listMailboxes` merges LIST with LIST RETURN (SPECIAL-USE).
  Servers without SPECIAL-USE get SwiftMail's guess from mailbox names.
- **EMLParser:** a `Date:` header with a trailing comment such as `(CDT)`
  gives nil, so `HeaderDate` reads it from the raw bytes. In-Reply-To and
  References are only in `additionalFields`. A quoted non-Latin charset
  (`charset="koi8-r"`) is not recognized (SwiftMail PR #268).
- **libxml2** obeys a `<meta charset>` over the encoding it is given, so
  `MessageDecoder.declaringUTF8` points every `<meta>` charset at UTF-8 (the
  text is already decoded).
- **swift-log:** SwiftMail logs at `.info` to stderr by default.
  `CLI.bootstrapSwiftLog()` keeps only warnings. Only the executable depends on
  swift-log.
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
