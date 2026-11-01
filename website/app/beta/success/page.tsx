import { redirect } from "next/navigation";

// The beta's checkout returned here. The beta is over; any old return link
// lands on the license page with its key and status intact.
export default async function BetaSuccess({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(await searchParams)) {
    for (const v of Array.isArray(value) ? value : value ? [value] : []) params.append(key, v);
  }
  const query = params.toString();
  redirect(`/license/success${query ? `?${query}` : ""}`);
}
