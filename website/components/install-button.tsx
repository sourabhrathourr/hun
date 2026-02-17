"use client";

import { useState } from "react";
import { Clipboard, Check } from "@phosphor-icons/react";

export function InstallButton({ copyText }: { copyText: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(copyText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={copy}
      className="cursor-pointer p-0.5 transition-colors hover:text-foreground/60"
    >
      {copied ? (
        <Check size={14} weight="bold" className="text-green-500" />
      ) : (
        <Clipboard size={14} className="text-muted-foreground/40" />
      )}
    </button>
  );
}
