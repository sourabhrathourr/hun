import type { Metadata, Viewport } from "next";
import "./globals.css";

const title = "Hun · Always know what's running, and on which port";
const description =
  "A menu bar app for the dev servers on your Mac. Your agents start them through Hun, and you see every one, with its port and its logs.";

export const metadata: Metadata = {
  metadataBase: new URL("https://hun.sh"),
  title: { default: title, template: "%s" },
  description,
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "https://hun.sh",
    siteName: "Hun",
    title,
    description,
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
  },
  robots: { index: true, follow: true },
};

// The whole site is warm paper: Safari tints its bars from this.
export const viewport: Viewport = {
  themeColor: "#F5F0E6",
  colorScheme: "light",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" style={{ colorScheme: "light", background: "#F5F0E6" }} suppressHydrationWarning>
      <head>
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link rel="apple-touch-icon" href="/hun-app-icon.png" />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
