// Stub for next/navigation — records refresh() calls, never navigates.
export function useRouter() {
  return {
    refresh: () => {
      window.__refreshCount = (window.__refreshCount ?? 0) + 1;
    },
  };
}
