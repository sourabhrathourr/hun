import { createFromSource } from "fumadocs-core/search/server";
import { source } from "@/lib/source";

// Backs the docs search dialog (RootProvider points it here).
export const { GET } = createFromSource(source, { language: "english" });
