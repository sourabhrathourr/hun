import { NextResponse } from "next/server";

const latestAppcast =
  "https://github.com/sourabhrathourr/hun/releases/latest/download/appcast.xml";

export function GET() {
  return NextResponse.redirect(latestAppcast, {
    status: 307,
    headers: {
      "Cache-Control": "public, max-age=300, stale-while-revalidate=3600",
    },
  });
}
