import * as React from "react";
import { createRoot } from "react-dom/client";
// The actual patched component under test — imported verbatim, not copied.
import { ReadmeEditor } from "../readme-editor.patched.tsx";

// ---- Controllable POST transport stub (secret-free, synthetic only) ----
const realFetch = window.fetch.bind(window);
window.__refreshCount = 0;
window.__calls = []; // parsed { readme } bodies in order
window.__pending = []; // deferred { resolve, reject } per in-flight POST
window.__inits = []; // raw { method, headers } per POST, to verify shape

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

function errResponse(status, payload, rawText) {
  // rawText !== undefined simulates a non-JSON body: json() rejects.
  return {
    ok: false,
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
  pendingCount: () => window.__pending.length,
  refreshCount: () => window.__refreshCount,
  resolveNextOk: () => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(okResponse({ ok: true }));
  },
  resolveNextHtmlSuccess: () => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve({ ...errResponse(200, null, "<html>unconfirmed"), ok: true });
  },
  resolveNextErr: (msg) => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(errResponse(500, { error: msg }));
  },
  resolveNextNonJsonErr: () => {
    const d = window.__pending.shift();
    if (!d) throw new Error("no pending request");
    d.resolve(errResponse(500, null, "<html>boom"));
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
};

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ReadmeEditor initial={"seed-A"} />
  </React.StrictMode>,
);
