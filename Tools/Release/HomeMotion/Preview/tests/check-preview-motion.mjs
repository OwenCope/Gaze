// Static contract checks for the NotchVideo preview-motion patch.
// Usage: node tests/check-preview-motion.mjs [path/to/notch-video.tsx]
// Exit 0 when every check passes, 1 otherwise.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const target = resolve(process.argv[2] ?? new URL("../files/src/components/notch-video.tsx", import.meta.url).pathname);
const src = readFileSync(target, "utf8");

let pass = 0;
let fail = 0;
const check = (name, ok) => {
  if (ok) { pass += 1; console.log(`ok - ${name}`); }
  else { fail += 1; console.log(`NOT OK - ${name}`); }
};

// Preserved surface.
check("keeps 'use client'", src.includes('"use client"'));
check("keeps NotchStyle export", /export type NotchStyle/.test(src));
check("keeps style prop signature", /export function NotchVideo\(\{ style \}: \{ style: NotchStyle \}\)/.test(src));
check("keeps all three recorded assets", ["/clips/normal.mp4", "/clips/semiLiquidGlass.mp4", "/clips/liquidGlass.mp4"].every((s) => src.includes(s)));
check("keeps static poster", src.includes('poster="/desktop.jpg"') && src.includes('src="/desktop.jpg"'));
check("keeps muted + playsInline", /muted/.test(src) && /playsInline/.test(src));
check("enforces defaultMuted imperatively", src.includes("defaultMuted = true"));
check("keeps loop", /\bloop\b/.test(src));
check("keeps near-viewport arming (600px rootMargin)", src.includes('rootMargin: "600px"'));

// Playback control.
check("no autoPlay attribute", !/autoPlay/.test(src));
check("Play preview / Pause preview accessible names", src.includes('"Play preview"') && src.includes('"Pause preview"'));
check("button has 44px minimum hit target", src.includes("min-h-[44px]") && src.includes("min-w-[44px]"));
check("button has visible focus style", src.includes("focus-visible:outline"));
check("button always rendered (no hover-only gating)", /<button[\s\S]*?aria-label=\{isPlaying \? "Pause preview" : "Play preview"\}/.test(src) && !/group-hover/.test(src));
check("button sits top-right, clear of center-bottom switcher", src.includes("right-3 top-3"));
check("only selected style plays; hidden clips pause", /key !== style/.test(src) && /\.pause\(\)/.test(src));
check("pauses off actual viewport (second observer)", /threshold: 0\.1/.test(src));
check("pauses on document hidden", src.includes("visibilitychange") && src.includes("document.hidden"));
check("honors explicit pause via intent", /intent/.test(src) && src.includes('"pause"'));
check("reduced motion starts static + pauses on enable", src.includes("prefers-reduced-motion") && src.includes("!reducedMotion"));
check("explicit Play can override reduced motion", /intent === "play" \? true/.test(src));
check("reduced motion enable demotes a stale explicit Play", /prev === "play" \? "auto" : prev/.test(src));
check("cross-fade disabled under reduced motion", /canAnimate = pointerDriven && !reducedMotion/.test(src) || /pointerDriven && !reducedMotion/.test(src));
check("lazy preload: hidden none, selected metadata", src.includes('"none"') && src.includes('"metadata"'));
check("play() rejection handled (no unhandled promise)", /\.then\(/.test(src) && src.includes("setIsPlaying(false)"));
check("stale play() continuation cannot restart (generation guard)", src.includes("opRef.current === op"));
check("cleanup disconnects observers + removes listeners", (src.match(/io\.disconnect\(\)/g) ?? []).length >= 2 && src.includes("removeEventListener"));

// Motion restraint.
check("cross-fade at most 220ms", (() => { const m = src.match(/FADE_SECONDS = (0\.\d+)/); return m !== null && Number(m[1]) <= 0.22; })());
check("no animation on initial mount", src.includes("initial={false}"));
check("keyboard-driven changes skip the fade (input modality)", src.includes("pointerdown") && src.includes("keydown") && src.includes("pointerDriven"));
check("animates opacity only", src.includes("animate={{ opacity:"));

// Honesty: a recorded preview, never a live unlock test.
check("no camera APIs", !/getUserMedia|mediaDevices|ImageCapture/.test(src));
check("never labeled a live unlock test", !/live unlock|unlock test|test .*unlock|try it|live demo|face id|faceid/i.test(src));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
