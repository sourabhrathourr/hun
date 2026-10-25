export const HUN_PRODUCT_ID = "pdt_0NqT6hcDftBBLBUTgJc6P";
export const HUN_PRICE = "$9";
export const HUN_MAC_LIMIT = 3;

export const HUN_BETA_PRODUCT_ID = "pdt_0Nk9a6sOPWWJ4iOwu4bwl";

export const HUN_BETA_ENDS_AT = "2026-10-31T18:29:59Z";

function parseBetaEndDate(value: string): Date {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error("DODO_BETA_EXPIRES_AT must be a valid timestamp");
  }
  return date;
}

export const hunBetaEndsAt =
  process.env.DODO_BETA_EXPIRES_AT ?? HUN_BETA_ENDS_AT;
const betaEndDate = parseBetaEndDate(hunBetaEndsAt);

export const hunBetaEndDateLong = new Intl.DateTimeFormat("en-GB", {
  dateStyle: "long",
  timeZone: "Asia/Kolkata",
}).format(betaEndDate);

export const hunBetaEndDateShort = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  year: "numeric",
  timeZone: "Asia/Kolkata",
}).format(betaEndDate);

const liveCheckoutURL =
  "https://checkout.dodopayments.com/buy/pdt_0Nk9a6sOPWWJ4iOwu4bwl?quantity=1&redirect_url=https://hun.sh%2Fbeta%2Fsuccess";

export const hunBetaCheckoutURL =
  process.env.NEXT_PUBLIC_DODO_BETA_CHECKOUT_URL ?? liveCheckoutURL;

export const hunCheckoutURL =
  process.env.NEXT_PUBLIC_DODO_CHECKOUT_URL ??
  `https://checkout.dodopayments.com/buy/${HUN_PRODUCT_ID}?quantity=1&redirect_url=https://hun.sh%2Flicense%2Fsuccess`;
