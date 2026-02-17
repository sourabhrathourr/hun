import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://hun.sh"),
  title: "hun.sh - seamless project context switching for developers",
  description:
    "hun is a command-line tool that makes context switching between dev projects smooth and seamless. one command to switch services, ports, and logs.",
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "https://hun.sh",
    siteName: "hun.sh",
    title: "hun.sh - seamless project context switching for developers",
    description:
      "hun is a command-line tool that makes context switching between dev projects smooth and seamless. one command to switch services, ports, and logs.",
    images: [{ url: "/api/og", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "hun.sh - seamless project context switching for developers",
    description:
      "hun is a command-line tool that makes context switching between dev projects smooth and seamless. one command to switch services, ports, and logs.",
    images: ["/api/og"],
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
    <html lang="en">
      <head>
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
