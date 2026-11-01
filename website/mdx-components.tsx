import defaultMdxComponents from "fumadocs-ui/mdx";
import { Step, Steps } from "fumadocs-ui/components/steps";
import { Tab, Tabs } from "fumadocs-ui/components/tabs";
import { Accordion, Accordions } from "fumadocs-ui/components/accordion";
import type { MDXComponents } from "mdx/types";

// Fumadocs' components, restyled warm in app/globals.css (`.docs-root`).
// Steps, Tabs and Accordions are available in every page without an import.
export function getMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...defaultMdxComponents,
    Step,
    Steps,
    Tab,
    Tabs,
    Accordion,
    Accordions,
    ...components,
  };
}
