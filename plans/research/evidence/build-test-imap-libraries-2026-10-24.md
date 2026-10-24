# Build test: SwiftMail and swift-nio-imap with Swift 6.4 (2026-10-24)

Raw report from worker agent `agent-3775b349`, which made throwaway SwiftPM packages (not
committed) and ran `swift package resolve`, `swift build` and `swift run` on this machine.
Copied verbatim from the agent's message. Only the heading above is added.

---

```
== 1. Environment ==
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.2.0
sw_vers: the harness hook blocks it ("Tool not in allow list"). From /System/Library/CoreServices/SystemVersion.plist: ProductName macOS, ProductVersion 27.2, ProductBuildVersion 26B118. SDK used by SPM: MacOSX27.0.sdk.

== Commands (one package per directory, all consumers are executableTargets) ==
swift package --package-path scratch-buildtest/<dir> resolve
swift build   --package-path scratch-buildtest/<dir>
swift run     --package-path scratch-buildtest/<dir> <target>
Dirs: A (SwiftMail branch main, tools 5.9), A-from (from:/exact: 1.16.0), A-rev (revision 88c45cbd), A6 (SwiftMail main, tools 6.0), B-tag (nio-imap from 0.4.0, tools 5.9), B-main (nio-imap branch main, tools 5.9), B6-tag / B6-main (same, tools 6.0).
Build times: each is a cold .build for that package. Git clones come from SPM's shared cache after the first fetch. The first SwiftMail resolve with network fetch took about 2.5 min.

== A) SwiftMail ==
SwiftMail main = 06b341e2762a5a5e3c608b3a8150007fa21807ce. Its manifest: swift-tools-version:5.9, platforms .macOS("15.0"), .iOS("18.0"), .tvOS("18.0"), .watchOS("11.0"), .visionOS("2.0"), .macCatalyst("18.0"). Products: SwiftMail (library). Also SwiftIMAPCLI and SwiftSMTPCLI executables (demos). It pins swift-nio-imap by revision: 14ad3887dab9ca5aba38ee0ace18fddf40e9491f.

A (branch main, tools 5.9, .macOS("15.0")): "Build complete! (34.44 sec)". It runs (output in section 6).

Manager addition (a), version requirement: FAILS.
from: "1.16.0" ->
error: Dependencies could not be resolved because root depends on 'swiftmail' 1.16.0..<2.0.0.
'swiftmail' >= 1.16.0 cannot be used because no versions of 'swiftmail' match the requirement 1.16.1..<2.0.0 and package 'swiftmail' is required using a stable-version but 'swiftmail' depends on an unstable-version package 'swift-nio-imap'.
exact: "1.16.0" ->
error: Dependencies could not be resolved because package 'swiftmail' is required using a stable-version but 'swiftmail' depends on an unstable-version package 'swift-nio-imap' and root depends on 'swiftmail' 1.16.0.

Manager addition (b), revision: "88c45cbd31b347b373f7c87e197be63eb95efbc2" WORKS: "Build complete! (33.47 sec)". It resolves the same swift-nio-imap revision 14ad388 and the same 22 pins. branch: "main" also works.
Conclusion: a consumer must pin SwiftMail by revision or branch. A version requirement cannot resolve.

A Package.resolved: 22 pins.
swiftmail main 06b341e2762a5a5e3c608b3a8150007fa21807ce
swift-nio-imap revision 14ad3887dab9ca5aba38ee0ace18fddf40e9491f (no version)
swift-nio 2.104.0 | swift-nio-ssl 2.37.5 | swift-nio-extras 1.35.1 | swift-nio-http2 1.46.0
swift-log 1.16.2 | swift-collections 1.7.4 | swift-atomics 1.3.1 | swift-system 1.8.1
swift-algorithms 1.2.1 | swift-numerics 1.1.1 | swift-async-algorithms 1.1.7
swift-asn1 1.7.3 | swift-certificates 1.21.0 | swift-crypto 5.0.3
swift-http-types 1.8.0 | swift-http-structured-headers 1.7.0 | swift-service-lifecycle 2.13.0
swift-argument-parser 1.8.2 | swift-dotenv 2.1.0 (these two are for SwiftMail's demo CLIs) | SwiftCross 1.2.0
SwiftMail's test-only swift-testing (exact 6.3.2) is not resolved for consumers. Not all 22 pins compile: the http2, certificates, and crypto group is pulled in through swift-nio-extras's manifest.

== B) swift-nio-imap ==
Tags: 0.4.0 (newest, Jul 21 2026), 0.3.0, 0.2.0, 0.1.0.

(1) from: "0.4.0" (resolved 0.4.0 = d67f1243f731457cb9f2eb0beb27eff9e533bf7b), product NIOIMAP, consumer tools 5.9: "Build complete! (18.10 sec)". It runs.
0.4.0 manifest: swift-tools-version:6.0, NO platforms declared, products: NIOIMAP only.
Package.resolved: 6 pins. swift-nio-imap 0.4.0 | swift-nio 2.104.0 | swift-collections 1.7.4 | swift-atomics 1.3.1 | swift-system 1.8.1 | swift-se0270-range-set 1.0.1

(2) branch: "main" = 17929ed44f58e4baac5e265e5bc4c176709e8523, products NIOIMAP + IMAPCommands, consumer tools 5.9, .macOS("15.0"): "Build complete! (32.92 sec)". It runs.
main manifest: swift-tools-version:6.2 (comment: "6.2 is the floor so that the package always builds with `nonisolated(nonsending)` available"). Platforms: .macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2).
Products on main: .library NIOIMAP and .library IMAPCommands. There is no executable product. imap-tool is a SEPARATE nested package at Examples/IMAPTool/Package.swift (name "imap-tool-example", tools 6.2, macOS 15, products IMAPToolLib + executable "imap-tool"). It depends on the root by path: "../..". IMAPCommands target uses .enableUpcomingFeature("NonisolatedNonsendingByDefault"). NIOIMAP and NIOIMAPCore use "MemberImportVisibility". IMAPCommands depends on NIO, NIOSSL, NIOExtras, Logging.
Package.resolved: 18 pins. This is the same set as SwiftMail's list minus swiftmail, SwiftCross, swift-dotenv, and swift-argument-parser. swift-nio-imap branch main 17929ed44f58e4baac5e265e5bc4c176709e8523 | swift-nio 2.104.0 | swift-nio-ssl 2.37.5 | swift-nio-extras 1.35.1 | swift-nio-http2 1.46.0 | swift-log 1.16.2 | swift-collections 1.7.4 | swift-atomics 1.3.1 | swift-system 1.8.1 | swift-algorithms 1.2.1 | swift-numerics 1.1.1 | swift-async-algorithms 1.1.7 | swift-asn1 1.7.3 | swift-certificates 1.21.0 | swift-crypto 5.0.3 | swift-http-types 1.8.0 | swift-http-structured-headers 1.7.0 | swift-service-lifecycle 2.13.0

Important: SwiftMail's pinned revision 14ad388 ALREADY contains IMAPCommands/IMAPConnection. Its Package.swift is the same as main's (tools 6.2, macOS 15, same 2 products). The GitHub compare page (via WebFetch) shows main is 7 commits ahead of 14ad388, Oct 10-16 2026: #853 Gmail X-GM-MSGID/THRID/RAW search keys, #857 housekeeping, #861 Android exit tests, #870 "Fix race in ClientBootstrap", #871 QUOTA fixes, #855 "Accept the responses a server may send during IDLE", #873 "Handle invalid mailbox IDs". NOT TESTED: one consumer that depends on both SwiftMail (nio-imap pinned to 14ad388) and nio-imap branch main. I expect SPM to reject the conflicting requirements, but I did not run it.

main.swift (both B variants): imports NIOCore + NIOIMAP. I declared swift-nio / NIOCore explicitly for ByteBuffer; I did not test without it. NIOIMAP @_exported-imports NIOIMAPCore.
Output, identical on 0.4.0 and main:
encoded select: "A1 SELECT \"INBOX\"\r\n"
encoded login: "A2 LOGIN \"user\" \"p\\\"w\"\r\n"
parsed: response(* OK [CAPABILITY IMAP4rev1 IDLE UIDPLUS] Server ready)
parsed: response(* 1 FETCH ()   / response(UID 42) / response(FLAGS (\Seen)) / response())   <- FETCH is streamed as start/attr/attr/finish
parsed: response(A1 OK [READ-WRITE] SELECT completed)
remaining bytes: 0
Encoding note: TaggedCommand.debugDescription runs the real CommandEncodeBuffer. CommandEncodeBuffer.buffer is "@_spi(NIOIMAPInternal) public", so raw bytes are not public API without SPI or the channel handler.
API used: ResponseParser(options: .init()) and mutating parseResponseStream(buffer: inout ByteBuffer) throws -> ResponseOrContinuationRequest?; TaggedCommand(tag:command:); Command.select(.inbox), .login(username:password:).

IMAPConnection on main (IMAPCommands module): `public final class IMAPConnection: Sendable` with an INTERNAL init. The only entry is `static func withConnection<Result>(configuration:_ body: nonisolated(nonsending) (Greeting, IMAPConnection) async throws -> Result)`. Then `send(_ command:_ handler: nonisolated(nonsending) (Tag, ResponseStream) async throws -> Result)`, plus sendIdle, sendAuthenticate, append, and setEncodingOptions. Configuration: init(endpoint:useTLS:logging:), init(hostname:port:useTLS:logging:), init(serverText:logging:) throws. Endpoint: .hostname(String, port: UInt16) / .unixDomainSocket(path:).
No-network output:
config a: endpoint=hostname("imap.example.com", port: 993) useTLS=true      <- serverText "imap.example.com"
config b: endpoint=hostname("mail.example.com", port: 143) useTLS=false     <- serverText "imap://mail.example.com:143"
withConnection threw (expected, no socket): Error: The connection failed: connect(descriptor:addr:size:): No such file or directory) (errno: 2)
  (the error type is IMAPConnection.Error; .unixDomainSocket(path: "/nonexistent-dir/imap.sock"))

== 4. Platform floor ==
SwiftMail (main and 1.16.0 rev): requires macOS 15.
.macOS(.v13) -> "error: The package product 'SwiftMail-product' requires minimum platform version 15.0 for the macOS platform, but this target supports 13.0" then "error: Build failed"
.macOS(.v14) -> the same error with "supports 14.0".
macOS 15 -> OK. Gotcha: `.macOS(.v15)` needs tools >= 6.0. With tools 5.9 it fails at manifest compile: "error: 'v15' is unavailable" / "note: 'v15' was introduced in PackageDescription 6.0". With tools 5.9, use .macOS("15.0").
swift-nio-imap 0.4.0: no platform floor. It builds with consumer .macOS(.v13) and also with NO platforms entry (SPM default, macOS 10.13 for tools 5.9). Its dependencies (nio 2.104, collections, atomics, system, range-set) also do not force a floor.
swift-nio-imap main (17929ed): requires macOS 15. .macOS(.v13) ->
error: The package product 'NIOIMAP-product' requires minimum platform version 15.0 for the macOS platform, but this target supports 13.0
error: The package product 'IMAPCommands-product' requires minimum platform version 15.0 for the macOS platform, but this target supports 13.0
error: Build failed

== 5. Swift 6 language mode (consumer swift-tools-version 6.0) ==
A6 (SwiftMail main, .macOS(.v15)): "Build complete! (32.62 sec)". 0 errors and 0 warnings in consumer code. It runs. It also passes a parsed Message (Sendable) and the IMAPServer actor into Task.detached with no diagnostics.
B6-tag (0.4.0): "Build complete! (17.61 sec)". 0 errors, 0 warnings. ResponseOrContinuationRequest values and TaggedCommand crossed Task.detached with no diagnostics.
B6-main (main + IMAPCommands): "Build complete! (32.97 sec)". 0 errors, 0 warnings. A NON-Sendable final class mutated inside the withConnection and send closures from top-level (MainActor) code compiled clean. The nonisolated(nonsending) closure design works for callers in Swift 6 mode.
Library-side: SPM compiles each dependency in its own language mode and hides remote-dependency warnings. So the consumer builds above cannot show library warnings. I checked separately:
- SwiftMail is tools 5.9 = Swift 5 mode. I built the SwiftMail main checkout as a ROOT package: swift build --package-path scratch-buildtest/A/.build/checkouts/SwiftMail --scratch-path scratch-buildtest/swiftmail-root-build --target SwiftMail -Xswiftc -strict-concurrency=complete
  Result: "Build complete! (37.46 sec)" with 49 warnings in Sources/SwiftMail. 46 of them say "this is an error in the Swift 6 language mode", so SwiftMail would NOT compile as-is in Swift 6 mode. Consumers do not see these today. Kinds of warning:
  "sending 'self.primaryConnection' risks causing data races; this is an error in the Swift 6 language mode" (most; IMAPServer+Connection/+Idle/+Fetch/+Mailbox/+Enable/+Helpers.swift, IMAPNamedConnection*.swift)
  "capture of 'connection' with non-Sendable type 'IMAPConnection' in a '@Sendable' closure; this is an error in the Swift 6 language mode" (IMAPServer+Idle.swift:174)
  "passing closure as a 'sending' parameter risks causing data races between 'self'-isolated code and concurrent execution of the closure; this is an error in the Swift 6 language mode" (IMAPServer+Helpers.swift:35, IMAPServer+Idle.swift:153)
  "conformance of 'CommandType' to protocol 'IMAPCommand' may be isolated and cannot be passed to @concurrent context" (IMAPNamedConnection.swift:130, IMAPServer+Helpers.swift:19)
  "reference to captured var 'messageBuffer' in concurrently-executing code" (IMAP/Commands/AppendCommand.swift:53)
  (I ran this on main 06b341e, not on the 1.16.0 revision.)
- swift-nio-imap 0.4.0 (tools 6.0) and main (tools 6.2) already compile in Swift 6 language mode. A successful build therefore means full Swift 6 checking passed.

== 6. SwiftMail server-free MIME parse: YES, and all checked values are correct ==
API: `public struct EMLParser { public static func parse(_ data: Data) throws -> Message }` in Sources/SwiftMail/MIME/EMLParser.swift. There is also `Message(emlData:)`. Other parsers in that folder: MIME/MSG/MSGParser.swift (Outlook .msg), MIME/EMLSerializer.swift, MIME/Address/AddressParser.swift.
Input: the message as specified, CRLF line endings. One change: I used filename*=UTF-8''r%C3%A9sum%C3%A9.pdf (with the two apostrophes that RFC 2231 requires; the brief's text did not have them, probably lost to shell quoting). I did not test the form without the apostrophes.
Output (Swift 5 and Swift 6 consumers are identical):
subject: Optional("Échantillon test")                       OK
from: Optional("André <andre@example.com>")                  OK
fromAddresses: [=?UTF-8?B?QW5kcsOp?= <andre@example.com>]    <- by design: AddressListEntry.description is RFC 5322 header form, so it re-encodes
  mailbox name=Optional("André") address=andre@example.com   OK (decoded name on .fromAddresses.mailboxes[0].name)
textBody: Optional("café")                                   OK (ISO-8859-1 quoted-printable)
htmlBody: Optional("<p>Hello <b>world</b></p>")              OK (UTF-8 base64)
parts (3):
  section=1.1 contentType=text/plain; charset=ISO-8859-1 disposition=nil encoding=Optional("quoted-printable") filename=nil
  section=1.2 contentType=text/html; charset=UTF-8 disposition=nil encoding=Optional("base64") filename=nil
  section=2 contentType=application/pdf disposition=Optional("attachment") encoding=Optional("base64") filename=Optional("résumé.pdf")
attachments (1):
  filename=Optional("résumé.pdf") suggestedFilename="résumé.pdf" contentType=application/pdf decodedBytesMatch=true   OK (RFC 2231 decoded; base64 bytes equal the original)
Nothing was wrong. Notes: `parts` lists only leaf parts (the multipart containers are not entries; section numbers are IMAP-style). Message.from is the decoded display string. MessagePart gives filename, suggestedFilename, decodedData(), and textContent. textContent decodes with the declared charset and then falls back to ISO-2022-JP, UTF-8, Japanese heuristics, CP1252, Latin-1, and ASCII.

== Summary: what a consumer needs ==
SwiftMail: macOS 15+ (iOS 18+). It must be pinned by revision or branch; from:/exact: versions cannot resolve. 22 pins. Tools 5.9 is OK with .macOS("15.0"). The library is in Swift 5 mode and has 46 latent Swift-6 errors, which are hidden from consumers.
swift-nio-imap 0.4.0: no floor, 6 pins, NIOIMAP only (no client).
swift-nio-imap main: macOS 15+, toolchain >= 6.2, branch/revision pin (no tag contains IMAPCommands), 18 pins, adds the IMAPCommands async client (IMAPConnection.withConnection).
```
