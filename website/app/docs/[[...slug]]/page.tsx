import { source } from "@/lib/source";
import { DocsPage, DocsBody } from "fumadocs-ui/layouts/docs/page";
import { notFound } from "next/navigation";
import { findNeighbour } from "fumadocs-core/page-tree";
import { getMDXComponents } from "@/mdx-components";
import { DocsBanner, DocsPager } from "@/components/docs/docs-page-parts";
import { DocsPageHeader } from "@/components/docs/docs-header";
import type { Metadata } from "next";

export default async function Page(props: {
  params: Promise<{ slug?: string[] }>;
}) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const { body: Mdx, toc, title, description } = page.data;
  const tree = source.getPageTree();
  const { previous, next } = findNeighbour(tree, page.url);
  const slug = (params.slug ?? []).join("/");

  // The home page keeps the same grid as every other page (TOC column
  // included), so moving between them doesn't shift the frame.
  if (slug === "") {
    return (
      <DocsPage
        toc={toc}
        className="docs-home"
        breadcrumb={{ enabled: false }}
        footer={{ component: <DocsPager previous={previous} next={next} /> }}
      >
        <DocsBanner title={title} description={description} start={next} />
        <DocsBody className="docs-prose">
          <Mdx components={getMDXComponents()} />
        </DocsBody>
      </DocsPage>
    );
  }

  return (
    <DocsPage toc={toc} breadcrumb={{ enabled: false }} footer={{ component: <DocsPager previous={previous} next={next} /> }}>
      <DocsPageHeader slug={slug} title={title} description={description} />
      <DocsBody className="docs-prose">
        <Mdx components={getMDXComponents()} />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(props: {
  params: Promise<{ slug?: string[] }>;
}): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) return {};

  const description = page.data.description ?? "The hun.sh documentation.";

  const slug = (params.slug ?? []).join("/");
  const ogUrl = `/og/docs/${slug ? `${slug}/` : ""}image.png`;

  return {
    title: page.data.title,
    description: description,
    openGraph: {
      title: page.data.title,
      description: description,
      url: `/docs/${(params.slug ?? []).join("/")}`,
      images: [
        {
          url: ogUrl,
          width: 1200,
          height: 630,
          alt: page.data.title,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: page.data.title,
      description: description,
      images: [ogUrl],
    },
  };
}
