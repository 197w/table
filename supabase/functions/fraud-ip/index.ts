// Analiza oszustw: adres IP gościa z ipinfo.io (kraj, miasto, położenie, organizacja; przy planie z wykrywaniem
// prywatności także VPN, proxy, Tor i serwery). Wywołuje ją panel z tokenem zalogowanego konta, gdy w Dostawach,
// Odbiorze albo w „Analiza oszustw” pojawi się zamówienie z niesprawdzonym IP.
//
// Uprawnienia i zapis robią funkcje bazy (panel_fraud_ip_input, panel_fraud_apply_ip) z tokenem użytkownika,
// więc funkcja nie potrzebuje klucza serwisowego. Token ipinfo w sekrecie IPINFO_TOKEN (wpisuje użytkownik).

import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const TOKEN = Deno.env.get("IPINFO_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Tylko POST." }, 405);
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

  let orderId: string;
  try {
    orderId = String((await req.json()).order_id ?? "");
  } catch {
    return json({ error: "Zły format zapytania." }, 400);
  }
  if (!orderId) return json({ error: "Brak zamówienia." }, 400);

  const { data: input, error } = await db.rpc("panel_fraud_ip_input", { p_order_id: orderId });
  if (error) return json({ error: error.message }, 403);
  if (!input?.ip || input.checked) return json({ status: "skip" });
  if (!TOKEN) return json({ status: "no_token" });

  try {
    const res = await fetch(`https://ipinfo.io/${encodeURIComponent(input.ip)}?token=${TOKEN}`);
    if (!res.ok) {
      console.error("ipinfo", res.status, await res.text());
      return json({ status: "ipinfo_error" }, 502);
    }
    const info = await res.json();
    const { error: saveError } = await db.rpc("panel_fraud_apply_ip", { p_order_id: orderId, p_info: info });
    if (saveError) return json({ error: saveError.message }, 500);
    return json({ status: "ok" });
  } catch (e) {
    console.error(e);
    return json({ status: "ipinfo_error" }, 502);
  }
});
