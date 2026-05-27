// =====================================================================
// SUPABASE EDGE FUNCTION: notify-new-matches
// =====================================================================
// Sends an email to every user who is a member of any quiniela
// when a new match is added (with real team names, not TBD placeholders).
//
// To deploy: see DEPLOY-EMAIL.md
// =====================================================================

// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Read environment variables (set in Supabase dashboard or `supabase secrets`)
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") || "onboarding@resend.dev";
const APP_URL = Deno.env.get("APP_URL") || "https://your-quiniela.vercel.app";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    // The DB trigger calls us with the new match record
    const match = body.record || body;

    if (!match?.home_team || !match?.away_team) {
      return new Response("Skipped — no real teams yet", { status: 200 });
    }
    if (match.home_team.toLowerCase().includes("winner")
        || match.away_team.toLowerCase().includes("winner")
        || match.home_team.toLowerCase().includes("tbd")
        || match.away_team.toLowerCase().includes("tbd")) {
      return new Response("Skipped — placeholder teams", { status: 200 });
    }

    // Find all users who are members of any quiniela (they all need to predict)
    const { data: memberships } = await supabase
      .from("memberships")
      .select("user_id");
    const userIds = [...new Set((memberships || []).map(m => m.user_id))];
    if (userIds.length === 0) {
      return new Response("No members to notify", { status: 200 });
    }

    // Get their emails from auth.users (only the service role can read this)
    const { data: { users } } = await supabase.auth.admin.listUsers();
    const memberEmails = users
      .filter(u => userIds.includes(u.id) && u.email)
      .map(u => ({ email: u.email!, username: u.user_metadata?.username || u.email!.split("@")[0] }));

    if (memberEmails.length === 0) {
      return new Response("No emails to notify", { status: 200 });
    }

    // Format kickoff
    const kickoff = match.kickoff
      ? new Date(match.kickoff).toLocaleString("en-US", { weekday: "long", month: "long", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" })
      : "TBD";

    // Send email via Resend (batch to all recipients)
    const subject = `New match: ${match.home_team} vs ${match.away_team}`;
    const html = `
      <div style="font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:24px;background:#0a0a0a;color:#f5f5f5;border-radius:12px">
        <h1 style="font-family:'Bebas Neue',sans-serif;color:#d4ff3a;font-size:28px;margin:0 0 16px;letter-spacing:1px">NEW MATCH</h1>
        <p style="font-size:15px;color:#a3a3a3;margin:0 0 20px">A new World Cup match was just added. Log in to submit your prediction before kickoff.</p>
        <div style="background:#161616;border:1px solid #262626;border-radius:10px;padding:18px;margin:0 0 18px">
          <div style="font-size:11px;color:#a3a3a3;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">${match.round || ""}${match.group_name ? " · " + match.group_name : ""}</div>
          <div style="font-size:20px;font-weight:700">${match.home_team} <span style="color:#a3a3a3">vs</span> ${match.away_team}</div>
          <div style="font-size:13px;color:#a3a3a3;margin-top:8px">⏱️ ${kickoff}</div>
        </div>
        <a href="${APP_URL}" style="display:inline-block;background:#d4ff3a;color:#0a0a0a;padding:12px 22px;border-radius:8px;text-decoration:none;font-weight:700;font-size:14px">Open Quiniela →</a>
        <p style="font-size:11px;color:#737373;margin-top:24px">You're receiving this because you're a member of a quiniela.</p>
      </div>
    `;

    const results = await Promise.allSettled(memberEmails.map(({ email }) =>
      fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: FROM_EMAIL,
          to: email,
          subject,
          html,
        }),
      })
    ));

    const sent = results.filter(r => r.status === "fulfilled").length;
    const failed = results.length - sent;
    return new Response(JSON.stringify({ sent, failed }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("Edge function error:", e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
