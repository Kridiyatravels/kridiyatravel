import { createClient } from "jsr:@supabase/supabase-js@2";
import { supabaseRuntimeKeys } from "../_shared/runtime.ts";

type DigestMode = "daily" | "overdue";
type Task = {
  id: string;
  title: string;
  priority: string;
  due_at: string | null;
  assigned_to: string | null;
  entity_reference: string | null;
  entity_title: string | null;
  action_url: string | null;
};

const ALLOWED_ORIGINS = new Set([
  "https://admin.kridiyatravel.com",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
]);

function headers(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://admin.kridiyatravel.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

function reply(origin: string | null, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) });
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character] || character));
}

function taskRows(tasks: Task[]) {
  return tasks.slice(0, 20).map((task) => {
    const due = task.due_at ? new Intl.DateTimeFormat("en-AE", {
      timeZone: "Asia/Dubai", dateStyle: "medium", timeStyle: "short",
    }).format(new Date(task.due_at)) : "No deadline";
    const url = task.action_url?.startsWith("/")
      ? `https://admin.kridiyatravel.com${task.action_url}`
      : "https://admin.kridiyatravel.com/tasks.html";
    return `<tr><td style="padding:10px;border-bottom:1px solid #eee"><a href="${escapeHtml(url)}" style="color:#a84708;font-weight:700;text-decoration:none">${escapeHtml(task.title)}</a><br><span style="color:#68707a;font-size:12px">${escapeHtml(task.entity_reference || task.entity_title || "Operations")}</span></td><td style="padding:10px;border-bottom:1px solid #eee">${escapeHtml(task.priority)}</td><td style="padding:10px;border-bottom:1px solid #eee">${escapeHtml(due)}</td></tr>`;
  }).join("");
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: headers(origin) });
  if (request.method !== "POST") return reply(origin, 405, { error: "Method not allowed" });
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(origin, 403, { error: "Origin not allowed" });

  const authHeader = request.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const { url, publishableKey, secretKey } = supabaseRuntimeKeys();
  const resendKey = Deno.env.get("RESEND_API_KEY") || "";
  const fromEmail = Deno.env.get("UNSUBSCRIBE_FROM_EMAIL") || "Kridiya Travel <deals@kridiyatravel.com>";
  if (!url || !publishableKey || !secretKey || !resendKey) return reply(origin, 503, { error: "Digest delivery is not configured" });
  if (!token) return reply(origin, 401, { error: "Authentication required" });

  const admin = createClient(url, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const isServiceCall = token === secretKey;
  if (!isServiceCall) {
    const caller = createClient(url, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const [{ data: userData }, { data: isAdmin }] = await Promise.all([
      caller.auth.getUser(token), caller.rpc("is_admin"),
    ]);
    if (!userData.user || isAdmin !== true) return reply(origin, 403, { error: "Admin access required" });
  }

  let body: Record<string, unknown> = {};
  try { body = await request.json(); } catch { /* scheduled calls may send no body */ }
  const mode: DigestMode = body.mode === "overdue" ? "overdue" : "daily";
  const force = body.force === true && !isServiceCall;
  const now = new Date();
  const digestDate = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Dubai", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);

  try {
    const [{ data: profiles, error: profileError }, { data: preferences }, usersResult, { data: roles }, { data: allTasks, error: taskError }] = await Promise.all([
      admin.from("staff_profiles").select("user_id,full_name").eq("active", true).is("deleted_at", null),
      admin.from("staff_notification_preferences").select("user_id,email_daily_digest,email_overdue_digest"),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      admin.from("staff_roles").select("user_id,role"),
      admin.from("tasks_reminders")
        .select("id,title,priority,due_at,assigned_to,entity_type,entity_id")
        .in("status", ["open", "snoozed"])
        .or(`snoozed_until.is.null,snoozed_until.lte.${now.toISOString()}`)
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(1000),
    ]);
    if (profileError || taskError) throw profileError || taskError;

    const preferenceMap = new Map((preferences || []).map((row) => [row.user_id, row]));
    const roleMap = new Map((roles || []).map((row) => [row.user_id, String(row.role)]));
    const emailMap = new Map((usersResult.data?.users || []).filter((user) => user.email).map((user) => [user.id, user.email as string]));
    const tasks = (allTasks || []).map((task) => ({
      ...task,
      entity_reference: task.entity_type ? String(task.entity_type).replaceAll("_", " ") : "Operations",
      entity_title: null,
      action_url: task.entity_type === "enquiry" && task.entity_id
        ? `/admin.html?focus=${encodeURIComponent(task.entity_id)}`
        : task.entity_type === "booking" && task.entity_id
          ? `/booking-detail.html?id=${encodeURIComponent(task.entity_id)}`
          : "/tasks.html",
    })) as Task[];
    const results: Array<Record<string, unknown>> = [];

    for (const profile of profiles || []) {
      const email = emailMap.get(profile.user_id);
      const preference = preferenceMap.get(profile.user_id);
      const enabled = mode === "daily" ? preference?.email_daily_digest !== false : preference?.email_overdue_digest !== false;
      if (!email || !enabled) continue;
      const isAdmin = roleMap.get(profile.user_id) === "admin";
      const relevant = tasks.filter((task) => {
        if (!isAdmin && task.assigned_to !== profile.user_id) return false;
        if (mode === "overdue") return Boolean(task.due_at && new Date(task.due_at).getTime() < now.getTime());
        return true;
      });
      if (!relevant.length && mode === "overdue") continue;

      if (force) await admin.from("staff_digest_email_deliveries").delete()
        .eq("user_id", profile.user_id).eq("digest_type", mode).eq("digest_date", digestDate);
      const claim = await admin.from("staff_digest_email_deliveries").insert({
        user_id: profile.user_id, digest_type: mode, digest_date: digestDate, task_count: relevant.length,
      }).select("id").single();
      if (claim.error) {
        if (claim.error.code === "23505") results.push({ user_id: profile.user_id, status: "already_delivered" });
        else results.push({ user_id: profile.user_id, status: "claim_failed" });
        continue;
      }

      try {
        const overdue = relevant.filter((task) => task.due_at && new Date(task.due_at).getTime() < now.getTime()).length;
        const subject = mode === "overdue"
          ? `[Action required] ${relevant.length} overdue operation${relevant.length === 1 ? "" : "s"}`
          : `[Daily operations] ${relevant.length} active · ${overdue} overdue`;
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: fromEmail, to: [email], subject,
            html: `<div style="font-family:Arial,sans-serif;max-width:720px;margin:auto;color:#1d2430"><h2>${mode === "overdue" ? "Overdue work digest" : "Daily operations summary"}</h2><p>Hello ${escapeHtml(profile.full_name)},</p><p><b>${relevant.length}</b> active items are in your operational view; <b>${overdue}</b> are overdue.</p>${relevant.length ? `<table style="width:100%;border-collapse:collapse"><thead><tr><th align="left">Work item</th><th align="left">Priority</th><th align="left">Due</th></tr></thead><tbody>${taskRows(relevant)}</tbody></table>` : "<p>Your queue is clear.</p>"}<p><a href="https://admin.kridiyatravel.com/tasks.html" style="display:inline-block;background:#bd5108;color:white;text-decoration:none;padding:12px 18px;border-radius:8px">Open operations workspace</a></p><p style="color:#68707a;font-size:12px">Kridiya Staff Tools · controlled by your notification preferences.</p></div>`,
          }),
        });
        const provider = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(typeof provider.message === "string" ? provider.message : `Resend returned ${response.status}`);
        await admin.from("staff_digest_email_deliveries").update({ status: "sent", provider_message_id: provider.id || null, sent_at: new Date().toISOString(), last_error: null }).eq("id", claim.data.id);
        results.push({ user_id: profile.user_id, status: "sent", task_count: relevant.length });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown delivery error";
        await admin.from("staff_digest_email_deliveries").update({ status: "failed", last_error: message.slice(0, 1000) }).eq("id", claim.data.id);
        results.push({ user_id: profile.user_id, status: "failed" });
      }
    }

    await admin.from("audit_events").insert({
      actor_user_id: null, event_type: `operations.digest_${mode}`, entity_type: "operations_digest",
      metadata: { digest_date: digestDate, results },
    });
    return reply(origin, 200, { ok: true, mode, digest_date: digestDate, results });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown digest error";
    console.error("staff-operations-digest:", message);
    return reply(origin, 503, { error: "Operations digest could not be delivered" });
  }
});
