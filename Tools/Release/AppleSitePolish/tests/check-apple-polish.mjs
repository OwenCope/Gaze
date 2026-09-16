// Focused static checks for the AppleSitePolish patch.
// Run: `node tests/check-apple-polish.mjs` from Tools/Release/AppleSitePolish/
// Operates on files/<relpath> (the patched copies) unless FILES_ROOT is set
// to a gaze-site checkout with the patch applied.
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = process.env.FILES_ROOT ?? join(dirname(fileURLToPath(import.meta.url)), "..", "files");
const read = (rel) => readFileSync(join(root, rel), "utf8");

let pass = 0;
const failures = [];
function check(name, cond) {
  if (cond) { pass++; }
  else { failures.push(name); console.error(`FAIL: ${name}`); }
}

const page = read("src/app/page.tsx");
const css = read("src/app/globals.css");
const nav = read("src/components/top-nav.tsx");
const faqs = read("src/components/faqs.tsx");
const footer = read("src/components/ui/footer-section.tsx");

// --- Honesty / safety rails (must hold) ---
check("no download button added (page)", !/Download Gaze|Download for Mac|\/dl\b/i.test(page));
check("no download button added (footer)", !/Download/i.test(footer));
check("no download routes touched", !/api\/|\/dl\/|sign-in|auth/i.test(page + nav + faqs + footer));
check("in-development statements kept", page.includes("Currently in development") && page.includes("Gaze is still in development"));
check("photo-spoof honesty kept", faqs.includes("can still be fooled"));
check("no Apple/Droppy branding copied", !/Think different|Designed by Apple in California|Droppy/i.test(page + footer + nav));
check("footer non-affiliation note kept", footer.includes("not affiliated with Apple") || page.includes("not affiliated with Apple"));

// --- Keyboard / a11y ---
check("skip link present, targets hero", page.includes('className="skip-link"') && page.includes('href="#main-content"') && page.includes('id="main-content"'));
check("skip-link styles present", css.includes(".skip-link") && css.includes(".skip-link:focus-visible"));
check("mobile menu keeps Escape + focus return", nav.includes('"Escape"') && nav.includes("menuButton.current?.focus()"));
check("mobile menu keeps aria-expanded/controls", nav.includes('aria-expanded={menuOpen}') && nav.includes('aria-controls="mobile-navigation"'));
check("menu closes on browser back/forward while open", nav.includes('addEventListener("popstate"') && nav.includes("onClick={() => setMenuOpen(false)}"));
check("mobile links have visible focus", nav.includes("min-h-12") && /min-h-12[^"]*focus-visible:outline/.test(nav));
check("footer has Footer nav landmark", footer.includes('aria-label="Footer"'));
check("brand link has visible focus", /aria-label="Gaze home"[\s\S]{0,300}focus-visible:outline/.test(footer));
check("native details/summary accordion kept", faqs.includes("<details") && faqs.includes("<summary"));

// --- Contrast / type ---
check("nav links no longer use low-contrast secondary grey", !nav.includes("var(--muted-ink)"));
check("desktop inactive links use ink-based tone", nav.includes("color-mix(in_srgb,var(--foreground)_70%"));
check("palette tokens untouched", css.includes("--background: #f5f5f7") && css.includes("--muted-ink: #6e6e73") && css.includes("--foreground: #1d1d1f"));
check("FAQ answers use text-pretty", faqs.includes("text-pretty"));

// --- Motion / transparency / contrast prefs ---
check("smooth scroll added", css.includes("scroll-behavior: smooth"));
check("existing reduced-motion guard intact", css.includes("@media (prefers-reduced-motion: reduce)"));
check("reduced-transparency handled", css.includes("prefers-reduced-transparency"));
check("high-contrast handled", css.includes("prefers-contrast: more"));
check("chevron motion is transition-only (no keyframes added)", !/@keyframes/.test(faqs) && faqs.includes("transition-transform"));

// --- Rhythm / nav performance ---
check("CTA uses site-container (no lone px-6 section)", !page.includes('<section className="px-6') && page.includes("<div className=\"site-container\">\n          <h2 className=\"site-heading\">Help shape Gaze.</h2>"));
check("anchor scroll-margin safety net", css.includes("section[id]"));
check("footer internal links use Next Link", footer.includes("import Link from \"next/link\"") && footer.includes("<Link href={link.href}") && footer.includes("<nav aria-label=\"Footer\""));
check("footer external links keep blank+noreferrer", footer.includes('target="_blank"') && footer.includes('rel="noreferrer"'));

// --- Copy preservation (spot) ---
for (const q of ["Does it need a MacBook with a notch?", "What happens if it doesn’t recognize me?", "Could someone unlock it with a photo of me?", "Does it need an internet connection?", "What about glasses, or a beard, or a haircut?", "Can more than one person enroll?", "Is it going to eat my battery?"]) {
  check(`faq kept: ${q.slice(0, 32)}…`, faqs.includes(q));
}
check("hero copy kept", page.includes("Your face.") && page.includes("Your Mac. Unlocked."));
check("security copy kept", page.includes("Your face stays on your Mac."));

console.log(`\n${pass} passed, ${failures.length} failed.`);
process.exit(failures.length ? 1 : 0);
