const { renderMarkdown, parseDocument } = globalThis.gazeMarkdownFixture;

// Parse sanitized output using the installed HTML parser, including malformed input.
function scan(html) {
  const tags = [];
  function visit(node) {
    if (node.name) tags.push({ name: node.name, closing: false, attrs: node.attribs ?? {} });
    for (const child of node.children ?? []) visit(child);
  }
  visit(parseDocument(html));
  return tags;
}

const opens = (html, name) => scan(html).filter((t) => t.name === name && !t.closing);
const hasAttrPrefix = (html, prefix) =>
  scan(html).some((t) => Object.keys(t.attrs).some((k) => k.startsWith(prefix)));

let pass = 0;
let fail = 0;
function ok(cond, label, detail = "") {
  if (cond) {
    pass++;
    console.log(`PASS ${label}`);
  } else {
    fail++;
    console.log(`FAIL ${label}${detail ? " — " + detail : ""}`);
  }
}

// ---------- UNSAFE: must be stripped ----------

// 1. Event handlers
{
  const out = renderMarkdown('<img src="https://example.com/a.png" onerror="alert(1)">');
  ok(opens(out, "img").length === 1, "event-handler: img element survives");
  ok(!hasAttrPrefix(out, "on"), "event-handler: no on* attribute", out);
  ok(!out.includes("alert(1)"), "event-handler: payload text gone", out);
}

// 2. Script
{
  const out = renderMarkdown("<script>alert(1)</script>");
  ok(opens(out, "script").length === 0, "script: no script element", out);
  ok(!out.includes("<script"), "script: no script literal", out);
}

// 3. SVG
{
  const out = renderMarkdown('<svg onload="alert(1)"><circle r="10"/></svg>');
  ok(opens(out, "svg").length === 0, "svg: no svg element", out);
  ok(opens(out, "circle").length === 0, "svg: no circle element", out);
  ok(!hasAttrPrefix(out, "on"), "svg: no on* attribute", out);
}

// 4. iframe
{
  const out = renderMarkdown('<iframe src="https://evil.example"></iframe>');
  ok(opens(out, "iframe").length === 0, "iframe: no iframe element", out);
  ok(!out.includes("evil.example"), "iframe: evil src gone", out);
}

// 5. form
{
  const out = renderMarkdown('<form action="https://evil.example"><input type="text" name="x"></form>');
  ok(opens(out, "form").length === 0, "form: no form element", out);
  ok(opens(out, "input").length === 0, "form: no input element", out);
}

// 6. Malformed nested HTML
{
  const out = renderMarkdown('<div><p>hi<script>alert(1)</script></p><img src=x onerror=alert(1)>');
  ok(opens(out, "script").length === 0, "malformed: no script element", out);
  ok(!hasAttrPrefix(out, "on"), "malformed: no on* attribute", out);
  ok(opens(out, "div").length === 0, "malformed: div not allowlisted", out);
  ok(opens(out, "p").length >= 1, "malformed: paragraph structure survives", out);
}

// 7. Encoded + mixed-case unsafe schemes in links
for (const [label, md] of [
  ["entity-colon", "[x](javascript&#58;alert(1))"],
  ["hex-entity", "[x](&#x6A;avascript:alert(1))"],
  ["mixed-case", "[x](JaVaScRiPt:alert(1))"],
  ["vbscript", "[x](vbscript:msgbox(1))"],
  ["data-link", "[x](data:text/html;base64,PHNjcmlwdA==)"],
]) {
  const out = renderMarkdown(md);
  const anchors = opens(out, "a");
  ok(anchors.length === 1, `${label}: link text stays a link`, out);
  ok(!("href" in (anchors[0]?.attrs ?? {})), `${label}: unsafe href stripped`, out);
  ok(!/javascript|vbscript|data:/i.test(Object.values(anchors[0]?.attrs ?? {}).join(" ")), `${label}: no unsafe scheme in attrs`, out);
}

// 8. Protocol-relative URLs rejected
{
  const outA = renderMarkdown("[x](//evil.example/y)");
  const a = opens(outA, "a");
  ok(a.length === 1 && !("href" in a[0].attrs), "proto-rel link: href stripped", outA);

  const outImg = renderMarkdown("![a](//evil.example/a.png)");
  const imgs = opens(outImg, "img");
  ok(imgs.length === 1 && !("src" in imgs[0].attrs), "proto-rel img: src stripped", outImg);
}

// 9. style attribute stripped, element kept
{
  const out = renderMarkdown('<p style="color:red">hi</p>');
  const ps = opens(out, "p");
  ok(ps.length >= 1, "style: p survives", out);
  ok(!("style" in (ps[0]?.attrs ?? {})), "style: style attr stripped", out);
}

// 10. data: image rejected, element kept without src
{
  const out = renderMarkdown("![a](data:image/png;base64,AAA)");
  const imgs = opens(out, "img");
  ok(imgs.length === 1, "data-img: img element survives", out);
  ok(!("src" in imgs[0].attrs), "data-img: src stripped", out);
  ok(imgs[0].attrs.alt === "a", "data-img: alt preserved", out);
}

// ---------- SAFE: must be preserved ----------

// 11. Headings / lists / tables
{
  const out = renderMarkdown("# T\n\n- a\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n");
  ok(opens(out, "h1").length === 1, "structure: h1 present", out);
  ok(opens(out, "ul").length === 1 && opens(out, "li").length === 2, "structure: ul+2 li", out);
  ok(
    opens(out, "table").length === 1 &&
      opens(out, "thead").length === 1 &&
      opens(out, "th").length === 2 &&
      opens(out, "td").length === 2,
    "structure: table/thead/th/td",
    out,
  );
}

// 12. Safe links incl. relative + mailto
{
  const out = renderMarkdown("[ok](https://example.com) [rel](/releases/v1) [mail](mailto:a@b.com)");
  const hrefs = opens(out, "a").map((t) => t.attrs.href);
  ok(hrefs.includes("https://example.com"), "safe links: https kept", out);
  ok(hrefs.includes("/releases/v1"), "safe links: relative kept", out);
  ok(hrefs.includes("mailto:a@b.com"), "safe links: mailto kept", out);
}

// 13. Safe images incl. relative + title/dimensions
{
  const out = renderMarkdown('![a](https://example.com/a.png) ![b](/img.png "T")');
  const imgs = opens(out, "img");
  const srcs = imgs.map((t) => t.attrs.src);
  ok(srcs.includes("https://example.com/a.png"), "safe imgs: https kept", out);
  ok(srcs.includes("/img.png"), "safe imgs: relative kept", out);
  ok(imgs.some((t) => t.attrs.title === "T"), "safe imgs: title kept", out);
}

// 14. Escaped code samples stay inert text inside pre>code
{
  const out = renderMarkdown("```html\n<script>alert(1)</script>\n```");
  ok(opens(out, "script").length === 0, "codeblock: no real script element", out);
  ok(opens(out, "pre").length === 1 && opens(out, "code").length === 1, "codeblock: pre>code kept", out);
  ok(out.includes("&lt;script&gt;"), "codeblock: sample stays escaped", out);
}

// 15. Inline formatting
{
  const out = renderMarkdown("**bold** *it* ~~strike~~ `code`");
  ok(opens(out, "strong").length === 1, "inline: strong", out);
  ok(opens(out, "em").length === 1, "inline: em", out);
  ok(opens(out, "del").length === 1 || opens(out, "s").length >= 1, "inline: del/s", out);
  ok(opens(out, "code").length === 1, "inline: code", out);
}

// 16. http image dropped per policy (https + relative only), link http kept
{
  const out = renderMarkdown("![h](http://example.com/a.png) [l](http://example.com)");
  const imgs = opens(out, "img");
  ok(imgs.length === 1 && !("src" in imgs[0].attrs), "http img: src dropped", out);
  ok(opens(out, "a").some((t) => t.attrs.href === "http://example.com"), "http link: href kept", out);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
