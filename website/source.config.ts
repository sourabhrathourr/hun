import { defineDocs, defineConfig } from "fumadocs-mdx/config";
import { hunPaperTheme } from "./components/docs/code-theme";

export const docs = defineDocs({
  dir: "content/docs",
});

// The docs are light only, but the root <html> carries `.dark`, so both shiki
// slots get the same warm theme.
export default defineConfig({
  mdxOptions: {
    rehypeCodeOptions: {
      themes: { light: hunPaperTheme, dark: hunPaperTheme },
    },
  },
});
