const pending = new Map();
const actionStates = new Map();
const host = "com.gazeunlock.passwords";
const defaultActionTitle = "Fill with Gaze Passwords";

function forgetCredentials(reply) {
  if (reply && typeof reply === "object") {
    delete reply.username;
    delete reply.password;
  }
}

function recordState(tabID, requestID, operation, state, error) {
  const entry = { requestID, operation, state, at: Date.now() };
  if (error) entry.error = error;
  actionStates.set(tabID, entry);
  if (actionStates.size > 256) actionStates.delete(actionStates.keys().next().value);
}

function validatedNativeError(reply, requestID, origin) {
  if (reply?.version === 1 && reply.operation === "error" && typeof reply.requestID === "string" &&
    reply.requestID.toLowerCase() === requestID && reply.origin === origin &&
    reply.approved == null && reply.username == null && reply.password == null &&
    typeof reply.error === "string" && reply.error.length > 0 &&
    new TextEncoder().encode(reply.error).length <= 4096) return reply.error;
  return null;
}

function readTabURL(tab) {
  try {
    return new URL(tab?.url);
  } catch {
    throw new Error("Open an HTTPS login page first.");
  }
}

async function clearBadge(tabID) {
  await chrome.action.setBadgeText({ tabId: tabID, text: "" }).catch(() => {});
  await chrome.action.setTitle({ tabId: tabID, title: defaultActionTitle }).catch(() => {});
}

async function currentActionState() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const status = actionStates.get(tab?.id);
  if (!status || Date.now() - status.at >= 90000) {
    if (tab?.id) actionStates.delete(tab.id);
    return { ok: true, state: "idle" };
  }
  const result = { ok: true, state: status.state, operation: status.operation };
  if (status.error) result.error = status.error;
  return result;
}

function cancelTab(tabID) {
  pending.get(tabID)?.disconnect();
  pending.delete(tabID);
  actionStates.delete(tabID);
  clearBadge(tabID);
}
async function cancelActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id || !pending.has(tab.id)) return { ok: false, error: "No pending request found. Check the page or Passwords before retrying." };
  const status = actionStates.get(tab.id);
  cancelTab(tab.id);
  if (status) recordState(tab.id, status.requestID, status.operation, "cancelled");
  return { ok: true };
}
chrome.tabs.onRemoved.addListener(cancelTab);
chrome.tabs.onUpdated.addListener((tabID, change) => {
  if (change.status === "loading" || change.url) cancelTab(tabID);
});

let checkingConnection = false;
async function checkConnection() {
  if (checkingConnection) throw new Error("A connection check is already running.");
  checkingConnection = true;
  let port;
  let reply;
  try {
    const requestID = crypto.randomUUID();
    const origin = "https://gaze.invalid";
    try {
      port = chrome.runtime.connectNative(host);
    } catch {
      throw new Error("Open Passwords → Settings → Connect browser to set up the native helper.");
    }
    reply = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error("Connection timed out. Open Gaze Passwords and try again.")); port.disconnect(); }, 15000);
      port.onMessage.addListener(message => { clearTimeout(timer); resolve(message); });
      port.onDisconnect.addListener(() => {
        clearTimeout(timer);
        const failure = chrome.runtime.lastError;
        reject(new Error(failure ? "Open Passwords → Settings → Connect browser to set up the native helper." : "Connection closed. Open Gaze Passwords and try again."));
      });
      port.postMessage({ version: 1, operation: "status", requestID, origin });
    });
    if (reply?.version !== 1 || reply.operation !== "status" || typeof reply.requestID !== "string" || reply.requestID.toLowerCase() !== requestID ||
        reply.origin !== origin || reply.approved != null || reply.username != null || reply.password != null || reply.error != null) {
      throw new Error("Connection was not confirmed. Open Gaze Passwords and try again.");
    }
    return { ok: true };
  } finally { forgetCredentials(reply); port?.disconnect(); checkingConnection = false; }
}

async function fillActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No tab is selected. Open an HTTPS login page first.");
  if (pending.has(tab.id)) throw new Error("A request is already open. Complete or cancel it in Gaze Passwords, then try again.");
  const url = readTabURL(tab);
  if (url.protocol !== "https:" || url.username || url.password) throw new Error("Open an HTTPS login page first.");
  const requestID = crypto.randomUUID();
  const reservation = { disconnect() {} };
  pending.set(tab.id, reservation);
  recordState(tab.id, requestID, "fill", "pending");
  await clearBadge(tab.id);
  let port;
  let documentID;
  let reply;
  try {
    const installed = await chrome.scripting.executeScript({ target: { tabId: tab.id, frameIds: [0] }, files: ["login-form.js"] });
    documentID = installed[0]?.documentId;
    if (!documentID) throw new Error("The page changed. Try again.");
    const [prepared] = await chrome.scripting.executeScript({ target: { tabId: tab.id, documentIds: [documentID] },
      func: nonce => { const helper = globalThis.GazeLoginForm; if (!helper) throw new Error("The page changed. Try again."); return helper.prepare(nonce); }, args: [requestID] });
    if (prepared?.result?.origin !== url.origin || pending.get(tab.id) !== reservation) throw new Error("The page changed. Try again.");
    try {
      port = chrome.runtime.connectNative(host);
    } catch {
      throw new Error("Gaze Passwords is not connected. Install its browser helper first.");
    }
    pending.set(tab.id, port);
    reply = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error("The approval expired.")); port.disconnect(); }, 90000);
      port.onMessage.addListener(message => { clearTimeout(timer); resolve(message); });
      port.onDisconnect.addListener(() => {
        clearTimeout(timer);
        const failed = chrome.runtime.lastError;
        reject(new Error(failed ? "Gaze Passwords is not connected. Install its browser helper first." : "Approval cancelled. Nothing was filled."));
      });
      port.postMessage({ version: 1, operation: "fill", requestID, origin: url.origin });
    });
    const nativeError = validatedNativeError(reply, requestID, url.origin);
    if (nativeError) throw new Error(nativeError);
    if (pending.get(tab.id) !== port || reply?.version !== 1 || typeof reply.requestID !== "string" || reply.requestID.toLowerCase() !== requestID ||
        reply.origin !== url.origin || reply.operation !== "filled" || reply.approved !== true || reply.error != null ||
        typeof reply.username !== "string" || typeof reply.password !== "string" || !reply.password ||
        new TextEncoder().encode(reply.username).length > 4096 || new TextEncoder().encode(reply.password).length > 16384) {
      throw new Error("Approval did not complete. Nothing was filled.");
    }
    const [filled] = await chrome.scripting.executeScript({ target: { tabId: tab.id, documentIds: [documentID] },
      func: (nonce, origin, username, password) => { const helper = globalThis.GazeLoginForm; if (!helper) throw new Error("The page changed before filling completed."); return helper.fill(nonce, origin, username, password); },
      args: [requestID, url.origin, reply.username, reply.password] });
    forgetCredentials(reply);
    if (filled?.result?.filled !== true || pending.get(tab.id) !== port) throw new Error("The page changed before filling completed.");
    recordState(tab.id, requestID, "fill", "complete");
    await chrome.action.setBadgeText({ tabId: tab.id, text: "✓" }).catch(() => {});
    await chrome.action.setTitle({ tabId: tab.id, title: "Filled with Gaze. Sign in when you’re ready." }).catch(() => {});
    return { ok: true };
  } catch (error) {
    const state = actionStates.get(tab.id);
    if (state?.requestID === requestID && state.state === "pending") {
      recordState(tab.id, requestID, "fill", "failed", error instanceof Error ? error.message : "Approval did not complete. Nothing was filled.");
    }
    throw error;
  } finally {
    forgetCredentials(reply);
    if (pending.get(tab.id) === port || pending.get(tab.id) === reservation) pending.delete(tab.id);
    port?.disconnect();
    if (documentID) {
      await chrome.scripting.executeScript({ target: { tabId: tab.id, documentIds: [documentID] },
        func: nonce => globalThis.GazeLoginForm?.cancel(nonce), args: [requestID] }).catch(() => {});
    }
  }
}

async function saveActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error("No tab is selected. Open an HTTPS login page first.");
  if (pending.has(tab.id)) throw new Error("A request is already open. Complete or cancel it in Gaze Passwords, then try again.");
  const url = readTabURL(tab);
  if (url.protocol !== "https:" || url.username || url.password) throw new Error("Open an HTTPS login page first.");
  const reservation = { disconnect() {} };
  const requestID = crypto.randomUUID();
  pending.set(tab.id, reservation);
  recordState(tab.id, requestID, "save", "pending");
  await clearBadge(tab.id);
  let port;
  let captured;
  let reply;
  try {
    const installed = await chrome.scripting.executeScript({ target: { tabId: tab.id, frameIds: [0] }, files: ["login-form.js"] });
    const documentID = installed[0]?.documentId;
    if (!documentID || pending.get(tab.id) !== reservation) throw new Error("The page changed. Try again.");
    const [result] = await chrome.scripting.executeScript({ target: { tabId: tab.id, documentIds: [documentID] },
      func: () => { const helper = globalThis.GazeLoginForm; if (!helper) throw new Error("The page or login changed. Nothing was saved."); return helper.capture(); } });
    captured = result?.result;
    if (captured?.origin !== url.origin || typeof captured.username !== "string" || typeof captured.password !== "string" ||
        !captured.password || new TextEncoder().encode(captured.username).length > 4096 ||
        new TextEncoder().encode(captured.password).length > 16384 || pending.get(tab.id) !== reservation) {
      throw new Error("The page or login changed. Nothing was saved.");
    }
    try {
      port = chrome.runtime.connectNative(host);
    } catch {
      throw new Error("Gaze Passwords is not connected. Install its browser helper first.");
    }
    pending.set(tab.id, port);
    reply = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error("The save request expired.")); port.disconnect(); }, 90000);
      port.onMessage.addListener(message => { clearTimeout(timer); resolve(message); });
      port.onDisconnect.addListener(() => {
        clearTimeout(timer);
        const failed = chrome.runtime.lastError;
        reject(new Error(failed ? "Gaze Passwords is not connected. Install its browser helper first." : "Save request cancelled."));
      });
      port.postMessage({ version: 1, operation: "save", requestID, origin: url.origin,
        username: captured.username, password: captured.password });
      captured.username = "";
      captured.password = "";
    });
    const nativeError = validatedNativeError(reply, requestID, url.origin);
    if (nativeError) throw new Error(nativeError);
    if (pending.get(tab.id) !== port || reply?.version !== 1 || reply.operation !== "saved" ||
        typeof reply.requestID !== "string" || reply.requestID.toLowerCase() !== requestID || reply.origin !== url.origin || reply.approved !== true ||
        reply.username != null || reply.password != null || reply.error != null) throw new Error("Save was not confirmed. Check Passwords before trying again.");
    recordState(tab.id, requestID, "save", "complete");
    await chrome.action.setBadgeText({ tabId: tab.id, text: "✓" }).catch(() => {});
    await chrome.action.setTitle({ tabId: tab.id, title: "Saved in Gaze Passwords" }).catch(() => {});
    return { ok: true };
  } catch (error) {
    const state = actionStates.get(tab.id);
    if (state?.requestID === requestID && state.state === "pending") {
      recordState(tab.id, requestID, "save", "failed", error instanceof Error ? error.message : "Save was not confirmed. Check Passwords before trying again.");
    }
    throw error;
  } finally {
    forgetCredentials(reply);
    if (captured) { captured.username = ""; captured.password = ""; }
    if (pending.get(tab.id) === port || pending.get(tab.id) === reservation) pending.delete(tab.id);
    port?.disconnect();
  }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || sender.tab || sender.url !== chrome.runtime.getURL("popup.html") || !["fill", "save", "status", "state", "cancel"].includes(message?.operation)) return false;
  if (message.operation === "state") { currentActionState().then(respond, () => respond({ ok: false })); return true; }
  const run = message.operation === "cancel" ? cancelActiveTab : message.operation === "status" ? checkConnection : message.operation === "save" ? saveActiveTab : fillActiveTab;
  run().then(respond, error => {
    const text = error instanceof Error ? error.message : "Nothing was filled. Try again.";
    respond({ ok: false, error: text });
  });
  return true;
});
