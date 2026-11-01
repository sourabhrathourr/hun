export const HUN_PRODUCT_ID = "pdt_0NqT6hcDftBBLBUTgJc6P";
export const HUN_PRICE = "$9";
export const HUN_MAC_LIMIT = 3;

/** Checkout returns to /license/success with ?license_key= and ?status=. */
export const hunCheckoutURL =
  process.env.NEXT_PUBLIC_DODO_CHECKOUT_URL ??
  `https://checkout.dodopayments.com/buy/${HUN_PRODUCT_ID}?quantity=1&redirect_url=https://hun.sh%2Flicense%2Fsuccess`;

// The public beta (ended 31 October 2026). The webhook still gives any beta
// key it sees this expiry; it leaves paid keys alone.
export const HUN_BETA_PRODUCT_ID = "pdt_0Nk9a6sOPWWJ4iOwu4bwl";
export const HUN_BETA_ENDS_AT = "2026-10-31T18:29:59Z";

export const hunBetaEndsAt = process.env.DODO_BETA_EXPIRES_AT ?? HUN_BETA_ENDS_AT;
if (Number.isNaN(new Date(hunBetaEndsAt).getTime())) {
  throw new Error("DODO_BETA_EXPIRES_AT must be a valid timestamp");
}
