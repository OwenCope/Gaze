let actionInProgress = false;
let localActionInProgress = false;
let connectionInProgress = false;
let supportsActions = false;
let cancelling = false;
let actionRevision = 0;
const actionButtons = [document.querySelector("#fill"), document.querySelector("#save")];
function updateButtons() {
  actionButtons.forEach(button => { button.disabled = actionInProgress || connectionInProgress || cancelling || !supportsActions; });
  document.querySelector("#connection").disabled = actionInProgress || connectionInProgress || cancelling;
  document.querySelector("#cancel").hidden = !actionInProgress && !cancelling;
  document.querySelector("#cancel").disabled = cancelling;
}
for (const operation of ["fill", "save"]) document.querySelector(`#${operation}`).addEventListener("click", async () => {
  if (actionInProgress || connectionInProgress || cancelling || !supportsActions) return;
  const revision = ++actionRevision;
  const status = document.querySelector("#status");
  actionInProgress = true;
  localActionInProgress = true;
  updateButtons();
  status.textContent = "Continue in Gaze Passwords. This popup may close while you approve.";
  document.querySelector("#cancel").focus?.();
  try {
    const result = await chrome.runtime.sendMessage({ operation });
    if (revision !== actionRevision) return;
    status.textContent = result.ok ? operation === "save" ? "Saved in Passwords." : "Filled. Sign in when you’re ready." : result.error;
  } catch { if (revision === actionRevision) status.textContent = "The request closed. Try again from this website."; }
  finally {
    if (revision === actionRevision) {
      actionInProgress = false;
      localActionInProgress = false;
      updateButtons();
      document.querySelector(`#${operation}`).focus?.();
    }
  }
});
chrome.tabs.query({ active: true, currentWindow: true }).then(([tab]) => {
  const url = new URL(tab?.url ?? "about:blank");
  document.querySelector("#site").textContent = url.protocol === "https:" ? url.host : "Open an HTTPS login page";
  supportsActions = url.protocol === "https:" && !url.username && !url.password;
  updateButtons();
}).catch(() => {});

async function restoreActionState() {
  const revision = actionRevision;
  const wasWaiting = actionInProgress && !localActionInProgress && !cancelling;
  try {
    const result = await chrome.runtime.sendMessage({ operation: "state" });
    if (!result?.ok || localActionInProgress || cancelling || revision !== actionRevision) {
      if (!result?.ok && wasWaiting && revision === actionRevision && !localActionInProgress && !cancelling) setTimeout(restoreActionState, 750);
      return;
    }
    const status = document.querySelector("#status");
    if (result.state === "pending") {
      actionInProgress = true;
      status.textContent = "Waiting for your approval in Gaze Passwords…";
      setTimeout(restoreActionState, 750);
    } else {
      actionInProgress = false;
      if (result.state === "complete") status.textContent = result.operation === "save" ? "Saved in Passwords." : "Filled. Sign in when you’re ready.";
      else if (result.state === "failed") status.textContent = result.error ?? (result.operation === "save" ? "Save was not confirmed. Check Passwords before retrying." : "Approval did not complete. Try again.");
      else if (result.state === "cancelled") status.textContent = "Request cancelled. Anything already saved or filled is unchanged.";
      else if (wasWaiting) status.textContent = "The request closed. Try again from this website.";
    }
    updateButtons();
  } catch {
    if (wasWaiting && revision === actionRevision && !localActionInProgress && !cancelling) setTimeout(restoreActionState, 750);
  }
}
updateButtons();
restoreActionState();

document.querySelector("#cancel").addEventListener("click", async () => {
  if (!actionInProgress || cancelling) return;
  ++actionRevision;
  cancelling = true;
  localActionInProgress = false;
  updateButtons();
  const status = document.querySelector("#status");
  status.textContent = "Cancelling request…";
  try {
    const result = await chrome.runtime.sendMessage({ operation: "cancel" });
    if (result?.ok) {
      actionInProgress = false;
      status.textContent = "Request cancelled. Anything already saved or filled is unchanged.";
    } else {
      status.textContent = result?.error ?? "Cancellation was not confirmed. Check Gaze Passwords.";
    }
  } catch { status.textContent = "Could not cancel. Review the request in Gaze Passwords."; }
  finally { cancelling = false; updateButtons(); document.querySelector("#fill").focus?.(); }
  if (actionInProgress) await restoreActionState();
});

document.querySelector("#connection").addEventListener("click", async () => {
  if (actionInProgress || connectionInProgress || cancelling) return;
  const status = document.querySelector("#connection-status");
  connectionInProgress = true;
  updateButtons();
  status.textContent = "Checking the app connection…";
  try {
    const result = await chrome.runtime.sendMessage({ operation: "status" });
    status.textContent = result?.ok ? "Connected to Gaze Passwords. No credentials accessed." : result?.error ?? "Connection not confirmed.";
  } catch { status.textContent = "Connection closed. Open Gaze Passwords and try again."; }
  finally { connectionInProgress = false; updateButtons(); document.querySelector("#connection").focus?.(); }
});
