import { notFound } from "next/navigation";
import { PAGE_SECTIONS, SECTION_IMAGES } from "@/components/docs/docs-header";
import { sceneCard } from "@/lib/og/og";
import { source } from "@/lib/source";

// Each docs page's social card: /og/docs/<slug>/image.png (and
// /og/docs/image.png for the docs home). Built once at build time.

const SECTION_LABELS = { start: "Get started", using: "Using Hun", reference: "Reference" } as const;

export const dynamic = "force-static";

export async function GET(_req: Request, { params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const slugs = slug.slice(0, -1);
  const page = source.getPage(slugs);
  if (!page || slug[slug.length - 1] !== "image.png") notFound();

  const key = slugs.join("/");
  const section = PAGE_SECTIONS[key];
  return sceneCard({
    image: section ? SECTION_IMAGES[section] : "/site/bg/docs-a.jpg",
    focus: section ? "right" : "center",
    eyebrow: section ? SECTION_LABELS[section] : "Docs",
    title: page.data.title,
    description: page.data.description,
    address: key ? `hun.sh/docs/${key}` : "hun.sh/docs",
  });
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({ slug: [...page.slugs, "image.png"] }));
}
