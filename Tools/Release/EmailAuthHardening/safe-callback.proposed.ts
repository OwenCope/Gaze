/** Return only local paths; callback parameters also reach client-side navigation. */
export function safeCallbackPath(value: unknown): string {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//") ||
      /[\\\u0000-\u0020\u007f]/.test(value)) return "/";
  try {
    const url = new URL(value, "https://callback.invalid");
    if (url.origin !== "https://callback.invalid") return "/";
    return url.pathname + url.search + url.hash;
  } catch { return "/"; }
}
