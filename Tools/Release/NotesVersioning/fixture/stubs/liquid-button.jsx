import * as React from "react";

// Minimal stand-in for LiquidButton: same contract used by the editor
// (button element, disabled, onClick, children, title). No styles needed.
export function LiquidButton({ children, ...props }) {
  return <button {...props}>{children}</button>;
}
