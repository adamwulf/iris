# IMAP client library for iris: research and recommendation

Date: 2026-10-24. Toolchain: Apple Swift 6.4 on macOS 27.2 (arm64)[^1].
Method: GitHub API and README data, source reading at pinned commits, live pre-login
`CAPABILITY` captures from the three providers, and throwaway `swift build` tests run on this
machine (not committed).

## Recommendation (short)

Use **SwiftMail** (Cocoanetics) for IMAP and MIME decoding, **pinned by revision**, plus
**SwiftText** (`SwiftTextHTML`, `traits: ["HTML"]`, same author) for HTML to Markdown. IrisKit
wraps SwiftMail behind its own protocol so that the CLI logic tests run without a server. Keep
**swift-nio-imap's new `IMAPCommands` client** as the fallback: SwiftMail is built on top of
swift-nio-imap, so the protocol layer does not change if we must move down one level later.

Main costs: the package floor goes from macOS 13 to **macOS 15**, the manifest goes from tools
5.9 to at least **6.1** (for SwiftText's `traits:`), SwiftMail cannot be required by version
(only by revision or branch), and one person writes most of SwiftMail and SwiftText[^69][^92].
Details and the work that stays in IrisKit are in
[section 4](#4-recommendation-trade-offs-risks-and-what-iriskit-still-writes).

## 1. Comparison of IMAP candidates

| Candidate | What it is | Activity / releases | Stars, license | macOS floor, Swift | Resolved deps | Builds on Swift 6.4? |
|---|---|---|---|---|---|---|
| **SwiftMail** main `06b341e` (1.16.0) | High-level `IMAPServer` actor + SMTP + MIME parser, on swift-nio-imap | Pushed 2026-10-24[^2]; 10 releases from 2026-07-28 to 1.16.0 on 2026-10-09[^3] | 104★, 55 forks, 3 open issues + PRs, BSD-2-Clause[^2] | macOS 15; library compiles in Swift 5 mode[^4] | 22 pins[^5] | Yes, 33–34 s; only with a revision or branch pin[^6] |
| **swift-nio-imap** 0.4.0 | Apple's IMAP4rev1 parser/encoder + SwiftNIO channel handlers; no client, no MIME | Tagged commit dated 2026-07-20[^7] | 154★, 27 open issues + PRs, Apache-2.0[^8] | No floor; Swift 6 mode[^9][^4] | 6 pins[^9] | Yes, 18 s[^9] |
| **swift-nio-imap** main `17929ed` (`IMAPCommands`) | Same, plus a new async/await client `IMAPConnection` (PR #841, merged 2026-09-25)[^10] | 21 commits after 0.4.0, untagged[^11]; README: "not yet ready for use in production systems"[^12] | same as above | macOS 15, tools 6.2[^13] | 18 pins[^13] | Yes, 33 s[^13] |
| **MailCore2** | Obj-C/C++ IMAP/POP/SMTP client | Commits in 2026-09 add ActiveSync/Gmail API/JMAP[^14]; newest release 0.6.4 from 2020-08-01[^15] | 2,699★, 233 open issues + PRs[^16] | SPM = binary xcframework from a third-party fork, dated 2020-09-24[^17] | n/a | Not tried |
| **Postal** (Snips) | "A Swift framework for working with emails" | Last push 2019-05-22[^18] | 653★, MIT[^18] | n/a | n/a | Not tried (abandoned) |
| **libetpan** | C mail library | Pushed 2026-10-23[^19] | 632★[^19] | macOS 10.13; links curl, json-c, xml2, z[^20] | n/a | Not tried (C API only) |
| **SwiftIMAP** (HokuNZ) | Own parser on SwiftNIO; MIME decode | Pushed 2026-09-24[^21] | 0★, MIT[^21]; README: "This repository is LLM-generated code"[^22] | macOS 13, Swift 5.10[^22] | n/a | Not tried |

Other Swift IMAP repos pushed since mid-2025 have 0–6 stars[^23], so only SwiftMail and
swift-nio-imap have a real user base. SwiftMail is in use in two public Swift tools: Cocoanetics' own
**Post** CLI/daemon (SwiftMail pinned by revision + SwiftText for HTML)[^24][^25], and Mike
McQuaid's **MailSearch** (vendored SwiftMail + SwiftSoup)[^26]. I found no public production
client that uses swift-nio-imap directly.

### Feature coverage for iris

| iris need | SwiftMail (main `06b341e`) | swift-nio-imap `IMAPCommands` (main) |
|---|---|---|
| TLS on 993, LOGIN / AUTHENTICATE PLAIN / XOAUTH2 | `IMAPServer(host:port:)` infers TLS from the port[^27]; `login`, `authenticatePlain`, `authenticateXOAUTH2`[^28] | `Configuration(hostname:port:useTLS:)`; `Command.login`; `sendAuthenticate` for SASL[^13][^29] |
| EXAMINE + paged list (UID, from, subject, date) | `examineMailbox` returns a `Mailbox.Selection` with message count and UIDNEXT[^30][^89]; `fetchMessageInfos(uidRange:/sequenceRange:options:)` with `[.envelope, .internalDate]`[^31][^32]; envelope subject and names are RFC 2047-decoded[^90][^33] | Build `UID FETCH` yourself; read raw `Response` stream[^29] |
| One full message, decoded | `fetchRawMessage` sends `UID FETCH BODY.PEEK[]` (does not set `\Seen`; 10 s default timeout)[^34]; `EMLParser.parse(Data) -> Message` works offline[^35]; `textBody`, `htmlBody`, `attachments`[^36] | Not provided: you write MIME parsing |
| MIME details | Build test: QP + ISO-8859-1, base64 UTF-8 HTML, RFC 2047 subject/name, RFC 2231 filename all correct[^37]; charset fallbacks[^38]. **No `format=flowed` unwrapping** (open PR #268 only keeps the parameter)[^39] | None |
| HTML → text | Only a regex tag strip in `preview()`[^40] | None |
| Gmail X-GM-MSGID / X-GM-THRID / X-GM-LABELS | `fetchGmailAttributes(for:)` (since 2026-07, PR #192)[^41][^42][^88]. The README table still says X-GM-EXT-1 is not supported[^43]: it is out of date | FETCH attributes exist[^44]; `X-GM-THRID` / `X-GM-RAW` **search** keys only on main after SwiftMail's pin (PR #853)[^11][^45] |
| THREAD=REFERENCES | No | No `THREAD` command; only the `THREAD=` capability name is parsed[^44][^46] |
| SPECIAL-USE \Drafts + APPEND | `listSpecialUseMailboxes` (SPECIAL-USE, else English name match such as "draft", "[Gmail]/Drafts")[^47]; `createDraft(from:in:)` appends with `\Draft`[^48]. `Email` has no In-Reply-To/References fields, only `additionalHeaders`[^49]; `append(rawMessage:to:flags:internalDate:)` takes our own RFC 822 text[^48] | `append` (streaming APPEND)[^29] |
| IDLE, MOVE, UIDPLUS | Yes[^43] | `sendIdle`[^29]; MOVE and UIDPLUS types in NIOIMAPCore[^44] |
| Test seam (no server) | None public: `IMAPServer` is a concrete actor that takes host/port[^27]; SwiftMail's own tests use `@testable import`[^50]. Model types have public inits[^36][^51], and `EMLParser` runs on fixture `.eml` files[^35] | `withConnection` accepts a UNIX-socket endpoint, so a fake server is possible, but no mock is provided[^13] |

## 2. HTML to Markdown helpers

All three were built on Swift 6.4 and run on the same two fixtures: a Gmail reply with a
`gmail_quote` blockquote, and a newsletter with a layout table around a small data table[^75].

| Library | How it works | Floor, tools | Resolved pins (with the library) | Result on the fixtures |
|---|---|---|---|---|
| **SwiftText** 2.4.0, `SwiftTextHTML`, `traits: ["HTML"]` | libxml2 (through Cocoanetics/XMLKit) to Markdown[^76][^87] | macOS 13; library tools 6.3; consumer tools ≥ 6.1 to pass `traits:`[^76] | 4: SwiftText, swift-markdown, swift-cmark, XMLKit[^76] | Best. `>` quote with the list inside it, layout table unwrapped, data table as a GFM pipe table, entities decoded, no `<style>`/`<script>` text; about 0.5 ms per message[^77] |
| **Demark** 1.2.1 | Turndown.js in a WKWebView (default) or html-to-md in JavaScriptCore; `@MainActor` API[^78] | macOS 14; tools 6.0[^79] | 1[^79] | Runs in a plain CLI. Turndown makes each table cell its own paragraph; html-to-md prints the nested table as raw HTML; Demark falls back between engines without telling the caller; 310 ms cold start for the WKWebView engine[^80] |
| **SwiftSoup** 2.14.3 | HTML parser only | macOS 12; tools 6.0[^81] | 1[^81] | `text()` is one line with no structure. Only a base for our own converter[^81] |
| SwiftHTMLToMarkdown | Not tested | | | README: basic HTML "Almost fully supported, tables are not"[^82] |
| xberg-io html-to-markdown | Rust core with a Swift binding; not tested | | | "SwiftPM URL consumption is not yet available"[^83] |

**Pick SwiftText.** It is small (25★, MIT, pushed 2026-10-09)[^84], it is the HTML layer that Post
uses with SwiftMail[^24], and with the `HTML` trait it does not pull its PDF/OCR/archive parts
(the README says the trait pulls only swift-markdown; it also pulls XMLKit)[^76]. One detail: the
entity `&lt;jane@example.com&gt;` comes out as a literal `<jane@example.com>`, which a CommonMark
renderer would read as an autolink. Raw terminal output is fine[^85].

## 3. Provider facts

| | Gmail | iCloud Mail | Zoho Mail |
|---|---|---|---|
| Host | `imap.gmail.com:993`[^52] | `imap.mail.me.com:993`, SSL required[^86] | `imap.zoho.com` (personal, free org) or `imappro.zoho.com` (paid org), 993 SSL[^54]. Data-center hosts reachable on 993: `imap.zoho.eu`, `imappro.zoho.eu`, `imap.zoho.in`, `imap.zoho.com.au`, `imap.zoho.jp`, `imap.zohocloud.ca`, `imap.zoho.sa`[^55]. The account's own host is shown in Settings > Mail Accounts[^54] |
| Pre-login CAPABILITY (live, 2026-10-24) | `IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1 XYZZY SASL-IR AUTH=XOAUTH2 AUTH=PLAIN AUTH=PLAIN-CLIENTTOKEN AUTH=OAUTHBEARER`[^52] | `XAPPLEPUSHSERVICE IMAP4 IMAP4rev1 SASL-IR AUTH=ATOKEN AUTH=PLAIN AUTH=ATOKEN2 AUTH=XOAUTH2`[^53] | `IMAP4rev1 UNSELECT CHILDREN XLIST NAMESPACE IDLE MOVE ID AUTH=PLAIN SASL-IR AUTH=XOAUTH2 UIDPLUS ESEARCH LIST-EXTENDED LIST-STATUS WITHIN LITERAL- ACL CONDSTORE`[^56] |
| Full CAPABILITY per SwiftMail README table (secondary; capture method not stated) | SPECIAL-USE, MOVE, UIDPLUS, CONDSTORE, ESEARCH, ENABLE, UTF8=ACCEPT, APPENDLIMIT yes; QRESYNC, SORT no[^43] | UIDPLUS, CONDSTORE, QRESYNC, ESEARCH, SORT yes; SPECIAL-USE, MOVE no[^43] | Not in the table |
| THREAD | Not advertised before login[^52]; not in README table | Not advertised before login[^53] | Not advertised before login[^56] |
| Drafts | Find it by the `\Drafts` attribute: "All LIST responses contain these Special-Use attributes"; system labels are "prefixed by "[Gmail]" or "[GoogleMail]""[^57] | Name not verified (see section 5) | Name not verified (see section 5) |
| App password | Needs 2-Step Verification; not offered with security-key-only 2SV, work/school accounts, or Advanced Protection; revoked when the account password changes[^58]. Google's Workspace admin help: since 2025-03-14, IMAP "will no longer work with legacy passwords (basic authentication)"; the page names app passwords as an exception[^59] | Needs two-factor auth; up to 25 active; all revoked when the Apple Account password changes[^60]. Username is the name part without `@icloud.com` (try the full address if that fails)[^86] | IMAP must be turned on in Settings > Mail Accounts; app-specific password if 2FA is on; new free-plan sign-ups do not get IMAP[^54] |
| Limits and quirks | IMAP is always on since Jan 2025; up to 15 clients per account[^61]; 2,500 MB/day download, 500 MB/day upload[^62]. Labels act as folders over IMAP, so one message can be in many mailboxes[^57]. UIDs hold only inside one mailbox[^93]; `X-GM-MSGID` identifies a message "across multiple folders"[^57] | Unescaped `"` inside ENVELOPE message-IDs in `UID FETCH` replies (reported 2023, no Apple answer)[^63]; `BODY.PEEK[HEADER.FIELDS.NOT (...)]` answers with the wrong section[^64] | Only folders picked in Folder Settings show over IMAP[^54] |

## 4. Recommendation: trade-offs, risks, and what IrisKit still writes

**Pick SwiftMail** because it already does the parts that Adam called "very hard": the IMAP
state machine, envelope and RFC 2047 decoding, MIME multipart / transfer-encoding / charset
handling, special-use lookup, APPEND, IDLE, and Gmail attributes. It built and decoded our test
message correctly on Swift 6.4[^37]. It is active, and outside contributors send real-world
fixes (for example gb2312/GBK/EUC-KR charsets, Bcc in Sent copies)[^65]. It is used in a CLI of
the same shape as iris (Post)[^24].

Trade-offs and risks:

- **macOS 15 floor.** SwiftMail and swift-nio-imap main both need macOS 15; `.macOS(.v13)` fails
  with "requires minimum platform version 15.0"[^66]. With tools 5.9 write `.macOS("15.0")`,
  because `.v15` needs tools 6.0[^66]. Only swift-nio-imap 0.4.0 (parser only) works on macOS 13.
- **Manifest and toolchain.** SwiftText's `traits:` needs consumer tools 6.1 or newer, and its
  own manifest needs a Swift 6.3 toolchain[^76]. graham and hunch use tools 5.9, so iris differs
  here. Swift 6.4 is installed[^1].
- **Revision pin.** `from: "1.16.0"` and `exact: "1.16.0"` fail: "'swiftmail' depends on an
  unstable-version package 'swift-nio-imap'"[^6]. The 1.16.0 notes say the same[^67]. We pin a
  revision (1.16.0 is `88c45cbd`)[^91] and bump it by hand. Adding swift-nio-imap `main` next to
  it would probably conflict with SwiftMail's pin; this was not tested[^68].
- **Bus factor.** `odrobnik` has 492 commits; the next two have 35 and 29[^69]. The layer under it
  is Apple's swift-nio-imap (Davidde94 317, danieleggert 157 commits)[^70], and odrobnik also
  reports bugs upstream there[^71]. If SwiftMail stops, `IMAPCommands` is the exit path.
  SwiftText has the same main author (342 of 343 commits) and 25 stars[^92][^84]; if it stops, SwiftSoup plus our own
  converter is the exit path[^81].
- **Fast change.** 10 releases in about 10 weeks[^3]; the README is already behind the code
  (Gmail row)[^43][^41]. Read the source, not the README, when we bump.
- **Latent Swift 6 errors in SwiftMail.** Built with `-strict-concurrency=complete`, SwiftMail
  gives 49 warnings, 46 of them "an error in the Swift 6 language mode"[^4]. It ships in Swift 5
  mode, so iris in Swift 6 mode builds clean[^72]; Swift Package Index also reports zero data-race
  errors[^73]. This is a risk for SwiftMail's own future, not a build blocker for us.
- **Dependency weight.** 22 resolved packages (swift-nio-extras pulls the HTTP/2, certificates and
  crypto group, plus SwiftMail's demo-only dotenv and argument-parser)[^5]. All are Apple /
  swift-server packages; clean build about 34 s[^6].
- **Gmail thread search.** We can read `X-GM-THRID` for a page of messages[^41], but searching
  "all messages in this thread" with `X-GM-THRID` needs swift-nio-imap after PR #853, which is
  newer than SwiftMail's pin[^11][^45].

What IrisKit still writes:

1. A `MailClient` protocol over `IMAPServer`, a fake for tests, and `.env` multi-account config.
2. Paging: `examineMailbox`, then newest-first UID or sequence windows through
   `fetchMessageInfos(..., options: [.envelope, .internalDate])`[^30][^31].
3. Message fetch as `fetchRawMessage` + `EMLParser.parse` (one round trip). `fetchMessage(from:)`
   instead runs BODYSTRUCTURE and then one FETCH per part, one after another[^74]. Set a larger
   timeout than the 10 s default for big mail[^34].
4. Body choice (text/plain vs HTML), RFC 3676 `format=flowed` unwrapping[^39], and HTML to
   Markdown with the helper from section 2.
5. Threading: Gmail by `X-GM-THRID`; other servers by our own Message-ID / In-Reply-To /
   References threading (JWZ style), because none of the three servers advertises THREAD before
   login and neither library can send it[^46][^52][^53][^56]. `MessageInfo` gives `messageId`, `inReplyTo`,
   `references`[^51].
6. Reply drafts: build In-Reply-To / References and the quoted body ourselves, then
   `createDraft(from:)` with `additionalHeaders`, or `append(rawMessage:...)` with flags `\Draft`
   to the `\Drafts` mailbox[^48][^49].
7. Quote and history trimming (no candidate has it).
8. Provider notes: Gmail label/UID duplication, iCloud username form, Zoho data-center hosts.

## 5. Limitations / not verified

- **Post-login CAPABILITY** for all three providers was not captured (no credentials here). The
  "full CAPABILITY" row comes from SwiftMail's README table, which has no capture dates for Gmail
  or iCloud and no Zoho column[^43]. Next step: log in once per provider and record `CAPABILITY`
  and `LIST "" "*"` (Drafts names, `\Drafts` attributes, Zoho SPECIAL-USE or XLIST).
- **Drafts mailbox names** for iCloud and Zoho are not verified.
- **No live IMAP session** was run with either library against Gmail, iCloud or Zoho, so the
  iCloud ENVELOPE-quote bug[^63] is not tested against swift-nio-imap's parser.
- **Workspace app passwords for IMAP**: Google's admin page names app passwords as the exception
  but does not say they work for IMAP[^59]. Workspace accounts may need XOAUTH2.
- **MailCore2, Postal, libetpan, SwiftIMAP** were not built; they were ruled out on the data in
  section 1.
- **Zoho region list** came from DNS/TLS reachability, not from a Zoho page listing all
  regions[^55]; Zoho's own help page only names the US hosts[^54].
- The build tests used SwiftMail `main` (`06b341e`); the strict-concurrency count is for `main`,
  not the 1.16.0 revision[^4].

[^1]: [Build test, environment](evidence/build-test-imap-libraries-2026-10-24.md:10-14)
[^2]: [GitHub API, Cocoanetics/SwiftMail repo metadata, 2026-10-24](https://api.github.com/repos/Cocoanetics/SwiftMail)
[^3]: [GitHub API, SwiftMail releases list](https://api.github.com/repos/Cocoanetics/SwiftMail/releases?per_page=10)
[^4]: [Build test, SwiftMail strict-concurrency build](evidence/build-test-imap-libraries-2026-10-24.md:96-105)
[^5]: [Build test, SwiftMail Package.resolved](evidence/build-test-imap-libraries-2026-10-24.md:38-47)
[^6]: [Build test, SwiftMail version vs revision pin](evidence/build-test-imap-libraries-2026-10-24.md:23-37)
[^7]: [GitHub API, swift-nio-imap commit d67f124 (tag 0.4.0)](https://api.github.com/repos/apple/swift-nio-imap/commits/d67f1243f731457cb9f2eb0beb27eff9e533bf7b)
[^8]: [GitHub API, apple/swift-nio-imap repo metadata, 2026-10-24](https://api.github.com/repos/apple/swift-nio-imap)
[^9]: [Build test, swift-nio-imap 0.4.0](evidence/build-test-imap-libraries-2026-10-24.md:49-55)
[^10]: [apple/swift-nio-imap PR #841, "Add a imperative IMAP client and an `imap-tool` CLI"](https://github.com/apple/swift-nio-imap/pull/841)
[^11]: [GitHub compare, swift-nio-imap 0.4.0...main](https://github.com/apple/swift-nio-imap/compare/0.4.0...main)
[^12]: [swift-nio-imap README on main](https://github.com/apple/swift-nio-imap/blob/main/README.md)
[^13]: [Build test, swift-nio-imap main and IMAPConnection API](evidence/build-test-imap-libraries-2026-10-24.md:56-79)
[^14]: [GitHub API, MailCore2 recent commits](https://api.github.com/repos/MailCore/mailcore2/commits?per_page=12)
[^15]: [GitHub API, MailCore2 releases](https://api.github.com/repos/MailCore/mailcore2/releases?per_page=5)
[^16]: [GitHub API, MailCore/mailcore2 repo metadata](https://api.github.com/repos/MailCore/mailcore2)
[^17]: [MailCore2 Package.swift (binaryTarget URL)](https://github.com/MailCore/mailcore2/blob/master/Package.swift)
[^18]: [GitHub API, snipsco/Postal repo metadata](https://api.github.com/repos/snipsco/Postal)
[^19]: [GitHub API, dinhvh/libetpan repo metadata](https://api.github.com/repos/dinhvh/libetpan)
[^20]: [libetpan Package.swift](https://github.com/dinhvh/libetpan/blob/master/Package.swift)
[^21]: [GitHub API, HokuNZ/SwiftIMAP repo metadata](https://api.github.com/repos/HokuNZ/SwiftIMAP)
[^22]: [HokuNZ/SwiftIMAP README](https://github.com/HokuNZ/SwiftIMAP/blob/main/README.md)
[^23]: [GitHub search, Swift repos matching "imap" pushed after 2025-06-01](https://api.github.com/search/repositories?q=imap+language:Swift+pushed:>2025-06-01&sort=stars&order=desc&per_page=20)
[^24]: [Cocoanetics/Post Package.swift](https://github.com/Cocoanetics/Post/blob/main/Package.swift)
[^25]: [Oliver Drobnik, "Future Updates", Cocoanetics blog, 2026-03](https://www.cocoanetics.com/2026/03/future-updates/)
[^26]: [MikeMcQuaid/MailSearch Package.swift](https://github.com/MikeMcQuaid/MailSearch/blob/main/Package.swift)
[^27]: [SwiftMail `IMAPServer.init(host:port:transportSecurity:...)`, main 06b341e](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer.swift)
[^28]: [SwiftMail `IMAPServer.login` / `authenticatePlain` / `authenticateXOAUTH2`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BConnection.swift)
[^29]: [swift-nio-imap `IMAPConnection.withConnection` / `send` / `sendIdle` / `sendAuthenticate` / `append`, rev 14ad388](https://github.com/apple/swift-nio-imap/blob/14ad3887dab9ca5aba38ee0ace18fddf40e9491f/Sources/IMAPCommands/IMAPConnection.swift)
[^30]: [SwiftMail `IMAPServer.examineMailbox`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BMailbox.swift)
[^31]: [SwiftMail `IMAPServer.fetchMessageInfos(uidRange:options:headerFields:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BFetch.swift)
[^32]: [SwiftMail `FetchMessageInfoOptions`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/FetchMessageInfoOptions.swift)
[^33]: [SwiftMail `AddressListEntry` envelope decoding (`decodeMIMEHeader`)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/AddressListEntry%2BEnvelope.swift)
[^34]: [SwiftMail `FetchRawMessageCommand.toTaggedCommand` (`bodySection(peek: true, ...)`, `defaultTimeoutSeconds`)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAP/Commands/FetchCommands.swift)
[^35]: [SwiftMail `EMLParser.parse`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/MIME/EMLParser.swift)
[^36]: [SwiftMail `Message.textBody` / `htmlBody` / `attachments` / `init(header:parts:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/Message.swift)
[^37]: [Build test, offline MIME parse results](evidence/build-test-imap-libraries-2026-10-24.md:107-123)
[^38]: [SwiftMail `MessagePart.textContent`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/MessagePart.swift)
[^39]: [SwiftMail PR #268 (open), "Keep the parameters a text part is read by: format, delsp and a quoted charset"](https://github.com/Cocoanetics/SwiftMail/pull/268)
[^40]: [SwiftMail `Message.preview(maxLength:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/Message.swift)
[^41]: [SwiftMail `IMAPServer.fetchGmailAttributes(for:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BGmail.swift)
[^42]: [GitHub API, commit history of IMAPServer+Gmail.swift (first commit 2026-07-20)](https://api.github.com/repos/Cocoanetics/SwiftMail/commits?path=Sources/SwiftMail/IMAP/IMAPServer%2BGmail.swift&per_page=5)
[^43]: [SwiftMail README, IMAP capability table](https://github.com/Cocoanetics/SwiftMail/blob/main/README.md)
[^44]: [swift-nio-imap `SupportedExtensions.md`, rev 14ad388](https://github.com/apple/swift-nio-imap/blob/14ad3887dab9ca5aba38ee0ace18fddf40e9491f/Sources/NIOIMAPCore/NIOIMAPCore.docc/SupportedExtensions.md)
[^45]: [swift-nio-imap PR #853, "Add Gmail X-GM-MSGID, X-GM-THRID, and X-GM-RAW search keys"](https://github.com/apple/swift-nio-imap/pull/853)
[^46]: [swift-nio-imap `Capability.ThreadKind` / `Capability.thread(_:)`, rev 14ad388 (no THREAD in `Command`)](https://github.com/apple/swift-nio-imap/blob/14ad3887dab9ca5aba38ee0ace18fddf40e9491f/Sources/NIOIMAPCore/Grammar/Capability.swift)
[^47]: [SwiftMail `IMAPServer.listSpecialUseMailboxes` / `detectSpecialFoldersByName`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BSpecialUse.swift)
[^48]: [SwiftMail `IMAPServer.append(rawMessage:...)` / `createDraft(from:in:date:additionalFlags:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BAppend.swift)
[^49]: [SwiftMail `Email.additionalHeaders`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/Core/Models/Email.swift)
[^50]: [SwiftMail `Tests/SwiftIMAPTests` (for example `FetchRawMessageTests.swift`, `@testable import SwiftMail`)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Tests/SwiftIMAPTests/FetchRawMessageTests.swift)
[^51]: [SwiftMail `MessageInfo` (`messageId`, `inReplyTo`, `references`, `internalDate`, public init)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/MessageInfo.swift)
[^52]: [Live capture, imap.gmail.com](evidence/imap-preauth-capabilities-2026-10-24.txt:11-22)
[^53]: [Live capture, imap.mail.me.com](evidence/imap-preauth-capabilities-2026-10-24.txt:24-35)
[^54]: [Zoho Mail Help, "IMAP Access"](https://www.zoho.com/mail/help/imap-access.html)
[^55]: [Live check, Zoho data-center hosts](evidence/imap-preauth-capabilities-2026-10-24.txt:51-65)
[^56]: [Live capture, imap.zoho.com and imappro.zoho.com](evidence/imap-preauth-capabilities-2026-10-24.txt:37-78)
[^57]: [Google, "IMAP Extensions" (Gmail)](https://developers.google.com/workspace/gmail/imap/imap-extensions)
[^58]: [Google Account Help, "Sign in with app passwords"](https://support.google.com/accounts/answer/185833)
[^59]: [Google Workspace Admin Help, "Transition from less secure apps to OAuth"](https://knowledge.workspace.google.com/admin/sync/transition-from-less-secure-apps-to-oauth)
[^60]: [Apple Support, "Sign in to apps with your Apple Account using app-specific passwords"](https://support.apple.com/en-us/102654)
[^61]: [Gmail Help, IMAP troubleshooting](https://support.google.com/mail/answer/7126229)
[^62]: [Google Workspace Admin Help, "Gmail bandwidth limits"](https://knowledge.workspace.google.com/admin/gmail/gmail-bandwidth-limits)
[^63]: [Apple Developer Forums, "iCloud IMAP server bug", Feb 2023](https://developer.apple.com/forums/thread/724704)
[^64]: [GNOME Balsa issue #94, "dealing with broken IMAP servers"](https://gitlab.gnome.org/GNOME/balsa/-/issues/94)
[^65]: [GitHub API, SwiftMail recent commits (charset, Outlook, Bcc fixes by several authors)](https://api.github.com/repos/Cocoanetics/SwiftMail/commits?per_page=30)
[^66]: [Build test, platform floor](evidence/build-test-imap-libraries-2026-10-24.md:81-90)
[^67]: [SwiftMail release 1.16.0 notes](https://github.com/Cocoanetics/SwiftMail/releases/tag/1.16.0)
[^68]: [Build test, note on SwiftMail's swift-nio-imap pin vs main](evidence/build-test-imap-libraries-2026-10-24.md:61)
[^69]: [GitHub API, SwiftMail contributors](https://api.github.com/repos/Cocoanetics/SwiftMail/contributors?per_page=15)
[^70]: [GitHub API, swift-nio-imap contributors](https://api.github.com/repos/apple/swift-nio-imap/contributors?per_page=15)
[^71]: [GitHub API, swift-nio-imap open issues (#824 and #859 by odrobnik)](https://api.github.com/repos/apple/swift-nio-imap/issues?state=open&per_page=30)
[^72]: [Build test, Swift 6 language-mode consumers](evidence/build-test-imap-libraries-2026-10-24.md:92-95)
[^73]: [Swift Package Index, Cocoanetics/SwiftMail](https://swiftpackageindex.com/Cocoanetics/SwiftMail)
[^74]: [SwiftMail `IMAPServer.fetchMessage(from:)` / `fetchAllMessageParts(identifier:)`](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAPServer%2BFetch.swift)
[^75]: [HTML build test, fixtures](evidence/build-test-html-to-markdown-2026-10-24.md:8-12)
[^76]: [HTML build test, SwiftText build and Package.resolved](evidence/build-test-html-to-markdown-2026-10-24.md:28-38)
[^77]: [HTML build test, SwiftText timing and output](evidence/build-test-html-to-markdown-2026-10-24.md:40-68)
[^78]: [steipete/Demark README](https://github.com/steipete/Demark/blob/main/README.md)
[^79]: [HTML build test, Demark build](evidence/build-test-html-to-markdown-2026-10-24.md:70-78)
[^80]: [HTML build test, Demark behavior, timing and output](evidence/build-test-html-to-markdown-2026-10-24.md:79-140)
[^81]: [HTML build test, SwiftSoup](evidence/build-test-html-to-markdown-2026-10-24.md:143-158)
[^82]: [ActuallyTaylor/SwiftHTMLToMarkdown README](https://github.com/ActuallyTaylor/SwiftHTMLToMarkdown/blob/main/README.md)
[^83]: [xberg-io/html-to-markdown, `packages/swift` README](https://github.com/xberg-io/html-to-markdown/tree/main/packages/swift)
[^84]: [GitHub API, Cocoanetics/SwiftText repo metadata](https://api.github.com/repos/Cocoanetics/SwiftText)
[^85]: [HTML build test, summary note on `&lt;...&gt;`](evidence/build-test-html-to-markdown-2026-10-24.md:26)
[^86]: [Apple Support, "iCloud Mail server settings for other email client apps"](https://support.apple.com/en-us/102525)
[^87]: [Cocoanetics/SwiftText README (HTMLParser "libxml2-backed", traits)](https://github.com/Cocoanetics/SwiftText/blob/main/README.md)
[^88]: [SwiftMail PR #192, "Add Gmail X-GM-EXT-1 attribute fetch (X-GM-MSGID, X-GM-THRID, X-GM-LABELS)"](https://github.com/Cocoanetics/SwiftMail/pull/192)
[^89]: [SwiftMail `Mailbox.Selection` (`messageCount`, `uidNext`)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/Mailbox.swift)
[^90]: [SwiftMail `FetchMessageInfoHandler` (`header.subject = subject.decodeMIMEHeader()`)](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/IMAP/Handler/FetchMessageInfoHandler.swift)
[^91]: [GitHub API, SwiftMail tags (1.16.0 = 88c45cbd31b3)](https://api.github.com/repos/Cocoanetics/SwiftMail/tags)
[^92]: [GitHub API, SwiftText contributors (odrobnik 342, tabmail-kmyi 1)](https://api.github.com/repos/Cocoanetics/SwiftText/contributors?per_page=10)
[^93]: [SwiftMail `GmailMessageAttributes` doc comment ("unlike UIDs, which are only stable within a single mailbox")](https://github.com/Cocoanetics/SwiftMail/blob/06b341e2762a5a5e3c608b3a8150007fa21807ce/Sources/SwiftMail/IMAP/Models/GmailMessageAttributes.swift)
