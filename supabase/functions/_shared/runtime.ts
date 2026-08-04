export function defaultKey(environmentName: string): string {
  try {
    const keys = JSON.parse(Deno.env.get(environmentName) || "{}");
    if (typeof keys.default === "string" && keys.default) return keys.default;
    const fallback = Object.values(keys).find((value) => typeof value === "string" && value);
    return typeof fallback === "string" ? fallback : "";
  } catch {
    return "";
  }
}

export function allKeys(environmentName: string): string[] {
  try {
    const keys = JSON.parse(Deno.env.get(environmentName) || "{}");
    return Object.values(keys).filter((value): value is string => typeof value === "string" && Boolean(value));
  } catch {
    return [];
  }
}

export function supabaseRuntimeKeys() {
  return {
    url: Deno.env.get("SUPABASE_URL") || "",
    publishableKey: defaultKey("SUPABASE_PUBLISHABLE_KEYS"),
    secretKey: defaultKey("SUPABASE_SECRET_KEYS"),
  };
}

export function supabaseSecretKeys(): string[] {
  return allKeys("SUPABASE_SECRET_KEYS");
}

export function generateSixDigitPin(): string {
  const range = 900_000;
  const limit = Math.floor(0x1_0000_0000 / range) * range;
  const values = new Uint32Array(1);
  do crypto.getRandomValues(values); while (values[0] >= limit);
  return String(100_000 + (values[0] % range));
}

export function clientAddress(request: Request): string {
  const chain = (request.headers.get("x-forwarded-for") || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  // Supabase's hosted gateway is the trusted final proxy. Client-supplied XFF
  // values can occupy the left side of the chain, so only the rightmost value
  // is suitable for a rate-limit bucket. Re-check this when changing gateways.
  return chain.at(-1) || "unknown";
}
