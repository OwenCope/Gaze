import * as React from "react";
import { createRoot } from "react-dom/client";
// The actual staged component under test — imported verbatim, not copied.
import { ReadmeEditor } from "../readme-editor.tsx";

// ---- Controllable POST transport stub (secret-free, synthetic only) ----
const realFetch = window.fetch.bind(window);
window.__refreshCount = 0;
window.__calls = []; // parsed { readme, expectedVersion } bodies in order
window.__pending = []; // deferred { resolve, reject } per in-flight POST
window.__inits = []; // raw { method, headers } per POST, to verify shape
window.__confirmCalls = [];
window.__confirmNext = undefined; // when set, window.confirm returns it once

const nativeConfirm = window.confirm.bind(window);
window.confirm = (message) => {
  window.__confirmCalls.push(String(message));
  if (window.__confirmNext !== undefined) {
    const next = window.__confirmNext;
    window.__confirmNext = undefined;
    return next;
  }
  return nativeConfirm(message);
};

window.fetch = (input, init) => {
  const url = typeof input === "string" ? input : input.url;
  if (url === "/api/readme") {
    let body = {};
    try {
      body = JSON.parse(init?.body ?? "{}");
    } catch {
      body = {};
    }
    window.__calls.push(body);
    window.__inits.push({ method: init?.method, headers: init?.headers });
    return new Promise((resolve, reject) => {
      window.__pending.push({ resolve, reject });
    });
  }
  return realFetch(input, init);
};

function okResponse(payload) {
  return {
    ok: true,
    status: 200,
    json: async () => payload,
  };
}

function statusResponse(status, isOk, payload, rawText) {
  return {
    ok: isOk,
    status,
    json: async () => {
      if (rawText !== undefined) throw new SyntaxError("Unexpected token <");
      return payload;
    },
  };
}

// Test driver API — all synthetic, no production data.
window.__t = {
  calls: () => window.__calls.map((c) => c.readme),
  versions: () => window.__calls.map((c) => c.expectedVersion),
  pendingCount: () => window.__pending.length,
  refreshCount: () => window.__refreshCount,
  resolveNextOk: (version) => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(okResponse({ ok: true, version: version ?? "b".repeat(64) }));
  },
  resolveNextOkMissingVersion: () => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(okResponse({ ok: true }));
  },
  resolveNextConflict: (msg) => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(statusResponse(409, false, { error: msg ?? "conflict synthetic" }));
  },
  resolveNextErr: (msg) => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(statusResponse(500, false, { error: msg }));
  },
  resolveNextNonJsonErr: () => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(statusResponse(500, false, null, "<html>boom"));
  },
  rejectNext: (msg) => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.reject(new TypeError(msg ?? "Failed to fetch"));
  },
  reset: () => {
    window.__calls = [];
    window.__pending = [];
    window.__inits = [];
    window.__refreshCount = 0;
    window.__confirmCalls = [];
    window.__confirmNext = undefined;
  },
  inits: () => window.__inits,
  savedVisible: () => {
    const el = document.querySelector('[role="status"]');
    return el !== null && el.textContent === "Saved";
  },
  errorText: () => document.querySelector('[role="alert"]')?.textContent ?? null,
  draft: () => document.querySelector("#tester-notes")?.value ?? null,
  busy: () =>
    document.querySelector("#tester-notes")?.getAttribute("aria-busy") ??
    document.querySelector("button")?.disabled ??
    null,
  reloadVisible: () =>
    [...document.querySelectorAll("button")].some(
      (b) => b.textContent === "Reload saved notes",
    ),
  confirmCalls: () => window.__confirmCalls,
};

const V0 = "a".repeat(64);

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ReadmeEditor initial={"seed-A"} initialVersion={V0} />
  </React.StrictMode>,
);
