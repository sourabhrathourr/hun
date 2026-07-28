import { HUN_BETA_ENDS_AT, HUN_BETA_PRODUCT_ID } from "@/lib/dodo";
import { Webhook } from "standardwebhooks";

export const runtime = "nodejs";

type LicenseKeyCreatedPayload = {
  type?: string;
  data?: {
    id?: string;
    product_id?: string;
  };
  id?: string;
  product_id?: string;
};

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}
export async function POST(request: Request) {
  try {
    const secret = requiredEnvironment("DODO_WEBHOOK_SECRET");
    const rawBody = await request.text();
    const webhook = new Webhook(secret);

    await webhook.verify(rawBody, {
      "webhook-id": request.headers.get("webhook-id") ?? "",
      "webhook-signature": request.headers.get("webhook-signature") ?? "",
      "webhook-timestamp": request.headers.get("webhook-timestamp") ?? "",
    });

    const payload = JSON.parse(rawBody) as LicenseKeyCreatedPayload;
    if (payload.type !== "license_key.created") {
      return Response.json({ received: true });
    }

    const license = payload.data ?? payload;
    const productID =
      process.env.DODO_BETA_PRODUCT_ID ?? HUN_BETA_PRODUCT_ID;

    if (license.product_id !== productID || !license.id) {
      return Response.json({ received: true });
    }

    const apiBaseURL =
      process.env.DODO_API_BASE_URL ?? "https://live.dodopayments.com";
    const betaEndsAt =
      process.env.DODO_BETA_EXPIRES_AT ?? HUN_BETA_ENDS_AT;
    const response = await fetch(
      `${apiBaseURL}/license_keys/${encodeURIComponent(license.id)}`,
      {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${requiredEnvironment("DODO_PAYMENTS_API_KEY")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          expires_at: betaEndsAt,
        }),
      },
    );

    if (!response.ok) {
      const detail = await response.text();
      throw new Error(
        `Dodo license expiry update failed (${response.status}): ${detail}`,
      );
    }

    return Response.json({ received: true });
  } catch (error) {
    console.error("Dodo webhook failed", error);
    return Response.json(
      { error: "Webhook processing failed" },
      { status: 500 },
    );
  }
}
