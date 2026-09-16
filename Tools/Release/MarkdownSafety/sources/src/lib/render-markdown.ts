import "server-only";
import { marked } from "marked";
import sanitizeHtml from "sanitize-html";

/**
 * Render Markdown to sanitized HTML for `dangerouslySetInnerHTML`.
 *
 * Server-only: both callers (`src/lib/releases.ts` and
 * `src/app/testers/page.tsx`) run in React Server Components, so the raw
 * Markdown never needs to reach the client unfiltered.
 *
 * `marked` passes block/inline HTML straight through, so the parse result is
 * always filtered with the maintained `sanitize-html` allowlist below — never
 * a hand-rolled regex. Structure from Markdown (headings, lists, tables, code
 * samples) is preserved; escaped code stays escaped text.
 */
export function renderMarkdown(source: string): string {
  const raw = marked.parse(source, { async: false }) as string;
  return sanitizeHtml(raw, {
    allowedTags: [
      "p",
      "br",
      "strong",
      "em",
      "del",
      "s",
      "blockquote",
      "ul",
      "ol",
      "li",
      "h1",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "pre",
      "code",
      "hr",
      "table",
      "thead",
      "tbody",
      "tr",
      "th",
      "td",
      "a",
      "img",
    ],
    allowedAttributes: {
      a: ["href", "title"],
      img: ["src", "alt", "title", "width", "height"],
    },
    // Links: http/https/mailto plus ordinary relative URLs. Images: https
    // plus ordinary relative URLs (http images are dropped to <img/>).
    allowedSchemes: ["http", "https", "mailto"],
    allowedSchemesByTag: {
      img: ["https"],
    },
    // Reject protocol-relative URLs (//evil.example/…) and
    // javascript:/vbscript:/data: URLs including encoded variants —
    // sanitize-html decodes entities before checking the scheme.
    allowProtocolRelative: false,
    disallowedTagsMode: "discard",
  });
}
