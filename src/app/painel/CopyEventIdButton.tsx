"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";

export function CopyEventIdButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  async function copyId() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      setCopied(false);
    }
  }

  return <button type="button" onClick={copyId} aria-label="Copiar identificador da vaquejada"
    className="inline-flex size-9 shrink-0 items-center justify-center rounded-lg border border-red-200 bg-white text-red-950 transition hover:bg-red-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-800">
    {copied ? <Check className="size-4" aria-hidden="true" /> : <Copy className="size-4" aria-hidden="true" />}
    <span className="sr-only">{copied ? "Identificador copiado" : "Copiar identificador"}</span>
  </button>;
}
