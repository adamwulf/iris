# Build test: HTML to Markdown libraries with Swift 6.4 (2026-10-24)

Raw report from worker agent `agent-1103a9a4`, which made throwaway SwiftPM packages (not
committed), built them, and converted two HTML fixtures on this machine. Copied verbatim from
the agent's message. Only this heading is added. Inside the fenced output blocks, trailing
spaces that the worker described may not survive copying; the worker's notes say where they are.

Fixtures (from the task brief):

1. Gmail-style reply:
   `<div dir="ltr">Sounds good, see you then.<br><br>-- Adam</div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Oct 20, 2026 at 9:14 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex"><div>Can we meet <b>Tuesday</b> at <a href="https://example.com/cal">the usual place</a>?</div><ul><li>Agenda item one</li><li>Agenda item two</li></ul></blockquote></div>`
2. Newsletter-style layout table:
   `<html><head><style>.x{color:red}</style></head><body><table width="600"><tr><td><h1>Weekly News</h1></td></tr><tr><td><p>Hello &amp; welcome. Read <a href="https://example.com/a">the article</a>.</p><img src="https://example.com/logo.png" alt="Logo"></td></tr><tr><td><table><tr><th>Item</th><th>Price</th></tr><tr><td>Caf&eacute;</td><td>$3</td></tr></table></td></tr></table><script>alert(1)</script></body></html>`

---

TOOLCHAIN (`swift --version`):
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.2.0

=== SUMMARY ===
- A) SwiftText 2.4.0 (traits ["HTML"]): builds at macOS 13 and 15. It gives the best Markdown: a clean blockquote, a GFM pipe table for the data table, the layout table unwrapped, entities decoded. No style/script leak. About 0.5 ms per conversion.
- B) Demark 1.2.1: does NOT build at macOS 13 (it needs 14). Builds at 15. BOTH engines work from a plain CLI (top-level async main.swift, no NSApplication). The WKWebView/Turndown engine did NOT hang (60 s watchdog never fired). Its cold start is about 310 ms, then 1-6 ms per conversion. Turndown flattens tables into separate paragraphs (no GFM plugin). html-to-md handles the newsletter badly: the layout table becomes a 1-column pipe table, and the nested table comes out as RAW HTML with `&eacute;` not decoded.
- C) SwiftSoup 2.14.3: builds at macOS 13 and 15. `try SwiftSoup.parse(html).text()` gives plain text on one line (all whitespace collapsed, no line breaks between blocks). No style/script leak. Image alt text is dropped.
- No library leaked <style>/<script> content.
- The `&lt;jane@example.com&gt;` entity comes out as a literal `<jane@example.com>` in all three (A, both B engines, C). A CommonMark renderer will read that as an email autolink and show it without the angle brackets. Raw terminal display is fine.

=== A) SwiftText  https://github.com/Cocoanetics/SwiftText  ===
Dependency: .package(url: "https://github.com/Cocoanetics/SwiftText", from: "2.4.0", traits: ["HTML"]); product SwiftTextHTML. The consumer must use tools-version >= 6.1 to pass `traits:` (I used 6.1).
Library declares: swift-tools-version:6.3 (toolchains older than 6.3 cannot parse the manifest). platforms macOS 13 / iOS 15 / tvOS 15 / watchOS 10 (package-wide floor, caused by swift-archive).
Build with consumer .macOS(.v13): "Build complete! (13.05 sec)"  (the first build, after fetch)
Build with consumer .macOS(.v15): "Build complete! (5.10 sec)"
Package.resolved (4 pins):
  swifttext       2.4.0  15e176a1910ece26c87468e151714f6253a6b385
  swift-markdown  0.9.0  25cb61d3482054b09ae76ca4f281b1bfe7fe5a43
  swift-cmark     0.9.0  08ddb528923cc1a6527e02b7a1aee9e516ca749a
  xmlkit          1.0.1  92f0051ab9f2d570647b8b76f688b53bdfc1bf06
NOTE: the README says that traits ["HTML"] resolves only swift-markdown. That is not fully correct. The HTML trait also pulls Cocoanetics/XMLKit (HTMLParser, libxml2-backed; on macOS it links -lxml2 from the SDK; XMLKit is tools 6.1, macOS 12). The trait pruning does work for the rest: swift-argument-parser and swift-archive (libarchive) are NOT resolved.
API used exactly as in the README: `let document = try await HTMLDocument(data: data, baseURL: url); let md = document.markdown()`.
Timing (release; cold = first call, warm = average of 20): gmail cold 6.6 ms, warm 0.55 ms. newsletter cold 0.72 ms, warm 0.53 ms. (Debug is about the same: 0.60 / 0.56 ms warm.)

Fixture 1 (gmail) output. Line 1 ends with 2 spaces; line 2 is exactly 2 spaces; the "> " line has 1 trailing space:
```
Sounds good, see you then.  
  
-- Adam

On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote:

> Can we meet **Tuesday** at [the usual place](https://example.com/cal)?
> 
> - Agenda item one
> - Agenda item two
```
Fixture 2 (newsletter) output:
```
# Weekly News

Hello & welcome. Read [the article](https://example.com/a).

![Logo](https://example.com/logo.png)

|Item|Price|
|----|-----|
|Café|$3   |
```
Quote: the blockquote becomes "> " with the nested list kept inside the quote. The gmail_attr line stays outside the quote (correct, same as the HTML). <br> becomes a hard break (two trailing spaces).
Table: the outer layout table is unwrapped into normal blocks; the inner data table becomes a GFM pipe table; &eacute; is decoded. No style/script leak.

=== B) Demark  https://github.com/steipete/Demark  from: "1.2.1" ===
Library declares: swift-tools-version: 6.0. platforms macOS 14 / iOS 16 / watchOS 10 / tvOS 17 / visionOS 1. No external dependencies. It bundles turndown.min.js and html-to-md.min.js as resources.
Build with consumer .macOS(.v13): FAILS:
  error: The package product 'Demark-product' requires minimum platform version 14.0 for the macOS platform, but this target supports 13.0
  error: Build failed
Build with consumer .macOS(.v15): "Build complete! (1.01 sec)". (The first v15 attempt failed only because of an error in MY test code: `Thread.isMainThread` is unavailable from async contexts in Swift 6. I changed it to pthread_main_np(). This was not a library problem.)
Package.resolved (1 pin):
  demark  1.2.1  f13b1926c7bf00d59f54bdc379415b67f6167e30
Test harness: top-level async main.swift (so it runs on the main actor). `Demark()` + `convertToMarkdown(html, options: DemarkOptions(engine: .turndown | .htmlToMd))`. A DispatchQueue.global watchdog calls exit(2) after 60 s.
IMPORTANT library behavior (from Demark.swift): if the Turndown engine throws, Demark SILENTLY retries with html-to-md and only writes an os_log warning. The caller cannot tell which engine ran. I confirmed that Turndown really ran: its output style is different from html-to-md ("-   " list markers, tables flattened instead of a pipe table, a trailing "  " after "wrote:"), and an OSLogStore scan found no "falling back" warnings.
WKWebView engine in a CLI: WORKS. No hang, the watchdog did not fire, the process exited cleanly. It is the same in debug and release.
Timing (release; cold = first call, warm = average of 20):
  turndown:  gmail cold 310 ms (WKWebView + WebContent process spin-up), warm 6.3 ms; newsletter cold 1.7 ms, warm 1.0 ms
  htmlToMd:  gmail cold 10.7 ms (JSContext init), warm 0.64 ms; newsletter cold 1.7 ms, warm 0.62 ms
Caveat (inference, NOT tested): the whole public API is @MainActor. The internal ConversionRuntime is @MainActor too, so even html-to-md starts and resumes on the main actor. If a TUI blocks the main thread (for example, a synchronous stdin read loop), both engines would stall. Turndown also needs the main run loop to be serviced.

B-turndown, fixture 1 (gmail). Line 1 ends with 2 spaces; line 2 is 2 spaces; the line after the blank line under "\-- Adam" is 2 spaces; the "wrote:" line ends with 2 spaces; the "> " line has 1 trailing space:
```
Sounds good, see you then.  
  
\-- Adam

  

On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote:  

> Can we meet **Tuesday** at [the usual place](https://example.com/cal)?
> 
> -   Agenda item one
> -   Agenda item two
```
B-turndown, fixture 2 (newsletter):
```
# Weekly News

Hello & welcome. Read [the article](https://example.com/a).

![Logo](https://example.com/logo.png)

Item

Price

Café

$3
```
B-htmlToMd, fixture 1 (gmail). Line 1 ends with 2 spaces; line 2 is 2 spaces; the line after "\-- Adam" is 2 spaces; the ">" line has NO trailing space:
```
Sounds good, see you then.  
  
\-- Adam
  

On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote:

> Can we meet **Tuesday** at [the usual place](https://example.com/cal)?
>
> * Agenda item one
> * Agenda item two
```
B-htmlToMd, fixture 2 (newsletter):
```
||
|---|
|# Weekly News|
|Hello & welcome. Read [the article](https://example.com/a).![Logo](https://example.com/logo.png)|
|<table><tr><th>Item</th><th>Price</th></tr><tr><td>Caf&eacute;</td><td>$3</td></tr></table>|
```
Quote: both engines give a correct "> " quote with the list inside it. Turndown uses "-   " (3-space) markers. html-to-md uses "*" inside the quote, because Demark's normalizer from "*" to "-" does not touch lines that start with ">". Both escape "-- Adam" as "\-- Adam". Both add extra whitespace-only lines from the <br> between the divs.
Table: Turndown has no GFM table plugin, so each cell becomes its own paragraph. html-to-md turns the layout table into a pipe table with an empty header and the h1 inside a cell, and it outputs the nested table as raw HTML with &eacute; not decoded. It also glues the image onto the paragraph text.
No style/script leak in either engine (Turndown removes them explicitly with turndownService.remove(['script','style'])).

=== C) SwiftSoup  https://github.com/scinfu/SwiftSoup  ===
Dependency: from: "2.14.3" (latest tag, Oct 16 2026). Library declares: swift-tools-version:6.0, platforms macOS 12 / iOS 13 / tvOS 13 / watchOS 6.
Build with consumer .macOS(.v13): "Build complete! (9.37 sec)"
Build with consumer .macOS(.v15): "Build complete! (0.99 sec)"
Package.resolved (1 pin):
  swiftsoup  2.14.3  e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f
`try SwiftSoup.parse(html).text()` output (debug build, one run each: gmail 19.7 ms including first-call warm-up, newsletter 4.6 ms):
fixture 1:
```
Sounds good, see you then. -- Adam On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote: Can we meet Tuesday at the usual place? Agenda item one Agenda item two
```
fixture 2:
```
Weekly News Hello & welcome. Read the article. Item Price Café $3
```
It gives plain text as expected. All structure is lost (one line, no quote marker). The script and style text do not leak. The img alt "Logo" is dropped. Entities are decoded.
