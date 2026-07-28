export const HUN_BETA_PRODUCT_ID = "pdt_0Nk9a6sOPWWJ4iOwu4bwl";

export const HUN_BETA_ENDS_AT = "2026-08-31T18:29:59Z";

const liveCheckoutURL =
  "https://checkout.dodopayments.com/buy/pdt_0Nk9a6sOPWWJ4iOwu4bwl?quantity=1&redirect_url=https://hun.sh%2Fbeta%2Fsuccess";

export const hunBetaCheckoutURL =
  process.env.NEXT_PUBLIC_DODO_BETA_CHECKOUT_URL ?? liveCheckoutURL;
