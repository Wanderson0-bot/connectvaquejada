"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export function RefreshOnInterval({ everyMs = 10000, enabled = true }: { everyMs?: number; enabled?: boolean }) {
  const router = useRouter();
  useEffect(() => {
    if (!enabled) return;
    const timer = window.setInterval(() => {
      if (document.visibilityState !== "visible" || !navigator.onLine) return;
      if (document.activeElement?.matches("input, select, textarea, [contenteditable]")) return;
      router.refresh();
    }, everyMs);
    return () => window.clearInterval(timer);
  }, [router, everyMs, enabled]);
  return null;
}
