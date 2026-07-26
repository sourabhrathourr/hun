import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://hun.sh"),
  title: {
    default: "Hun — a native macOS workspace for local development",
    template: "%s",
  },
  description:
    "Switch projects, run services, inspect Git changes, use project terminals, and follow logs from one native macOS workspace.",
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "https://hun.sh",
    siteName: "hun.sh",
    title: "Hun — a native macOS workspace for local development",
    description:
      "Projects, services, Git, terminals, and logs in one native macOS workspace.",
    images: [{ url: "/api/og/macos", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Hun — a native macOS workspace for local development",
    description:
      "Projects, services, Git, terminals, and logs in one native macOS workspace.",
    images: ["/api/og/macos"],
  },
  robots: {
    index: true,
    follow: true,
  },
  other: {
    "theme-color": "#0a0a0a",
    "color-scheme": "dark",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className="dark"
      style={{ colorScheme: "dark" }}
      suppressHydrationWarning
    >
      <head>
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
