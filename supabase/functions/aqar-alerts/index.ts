import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Alkazemi Asset Management · alert delivery
// Sends queued outbox rows by email (Resend) and WhatsApp (Twilio).
// Without keys, rows are marked waiting_keys and go out automatically once keys are added (if under 24 h old).
// Secrets (Supabase → Edge Functions → Secrets): RESEND_API_KEY, ALERT_FROM_EMAIL,
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const RESEND = Deno.env.get("RESEND_API_KEY");
const FROM = Deno.env.get("ALERT_FROM_EMAIL");
const SID = Deno.env.get("TWILIO_ACCOUNT_SID");
const TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN");
const WA_FROM = Deno.env.get("TWILIO_WHATSAPP_FROM");
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const emailOn = !!(RESEND && FROM), waOn = !!(SID && TOKEN && WA_FROM);
const waNum = (p: string) => "whatsapp:+" + p.replace(/[^0-9]/g, "");

async function sendEmail(d: any) {
  const r = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [d.to], subject: d.subject, text: d.body }) });
  if (!r.ok) throw new Error("Resend " + r.status + ": " + (await r.text()).slice(0, 200));
}
async function sendWhatsApp(d: any) {
  const body = new URLSearchParams({ From: WA_FROM!.startsWith("whatsapp:") ? WA_FROM! : "whatsapp:" + WA_FROM, To: waNum(d.to), Body: String(d.body).slice(0, 1500) });
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${SID}/Messages.json`, { method: "POST", headers: { Authorization: "Basic " + btoa(`${SID}:${TOKEN}`), "Content-Type": "application/x-www-form-urlencoded" }, body });
  if (!r.ok) throw new Error("Twilio " + r.status + ": " + (await r.text()).slice(0, 200));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let input: any = {};
  try { input = await req.json(); } catch (_) { /* empty body from cron */ }
  const since = new Date(Date.now() - 864e5).toISOString();
  if (input.health) {
    const c = async (st: string) => (await db.from("outbox").select("id", { count: "exact", head: true }).eq("status", st).gte("data->>at", since)).count ?? 0;
    return json({ email: emailOn, whatsapp: waOn, queued: await c("queued"), waiting: await c("waiting_keys"), sent: await c("sent") });
  }
  const { data: rows, error } = await db.from("outbox").select("id,data,status,attempts").in("status", ["queued", "waiting_keys"]).gte("data->>at", since).order("updated_at").limit(80);
  if (error) return json({ error: error.message }, 500);
  let sent = 0, waiting = 0, failed = 0;
  for (const row of rows ?? []) {
    const d = row.data || {}; const ch = d.channel || "email";
    const ready = ch === "whatsapp" ? waOn : emailOn;
    if (!ready) { if (row.status !== "waiting_keys") await db.from("outbox").update({ status: "waiting_keys" }).eq("id", row.id); waiting++; continue; }
    try {
      if (ch === "whatsapp") await sendWhatsApp(d); else await sendEmail(d);
      await db.from("outbox").update({ status: "sent", sent_at: new Date().toISOString(), error: null }).eq("id", row.id); sent++;
    } catch (e) {
      const attempts = (row.attempts || 0) + 1;
      await db.from("outbox").update({ status: attempts >= 3 ? "failed" : "queued", attempts, error: String((e as Error).message || e) }).eq("id", row.id); failed++;
    }
  }
  return json({ processed: (rows ?? []).length, sent, waiting, failed, email: emailOn, whatsapp: waOn });
});
