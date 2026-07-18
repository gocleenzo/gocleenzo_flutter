// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const NOTIFICATION_CONFIG = {
  pending: {
    title: "🧹 Booking Confirmed!",
    body: () => "Your booking is confirmed! We're finding the best professional for you.",
  },
  accepted: {
    title: "✅ Pro Assigned!",
    body: (d) => `${d.worker_name || "A professional"} has been assigned and is on the way!`,
  },
  in_progress: {
    title: "🧹 Cleaning Started!",
    body: (d) => `Your ${d.service_name || "cleaning"} service has started. OTP verified!`,
  },
  completed: {
    title: "🎉 Service Complete!",
    body: (d) => `Done! Please pay ₹${d.final_amount || ""} to your professional. Thank you!`,
  },
  cancelled: {
    title: "❌ Booking Cancelled",
    body: () => "Your booking has been cancelled. Contact us if you need help.",
  },
};

// ── Get FCM access token using separate secret fields ─────────
async function getFcmAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKey  = Deno.env.get("FCM_PRIVATE_KEY");
  const projectId   = Deno.env.get("FCM_PROJECT_ID");

  if (!clientEmail || !privateKey || !projectId) {
    throw new Error("Missing FCM secrets: FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY, or FCM_PROJECT_ID");
  }

  console.log("Using client email:", clientEmail);
  console.log("Project ID:", projectId);

  // Normalize the private key — handle both \n and real newlines
  const pemKey = privateKey
    .replace(/\\n/g, "\n")
    .trim();

  // Extract raw base64 content
  const keyBase64 = pemKey
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  console.log("Key base64 length:", keyBase64.length);

  // Decode to bytes
  const binaryStr = atob(keyBase64);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }

  // Import RSA private key
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // Build JWT manually
  const now = Math.floor(Date.now() / 1000);
  const header  = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const payload = btoa(JSON.stringify({
    iss:   clientEmail,
    sub:   clientEmail,
    aud:   "https://oauth2.googleapis.com/token",
    iat:   now,
    exp:   now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const signingInput = `${header}.${payload}`;
  const sigBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  // Convert signature to base64url
  const sigArr = new Uint8Array(sigBuffer);
  let sigBin = "";
  for (let i = 0; i < sigArr.length; i++) sigBin += String.fromCharCode(sigArr[i]);
  const signature = btoa(sigBin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const jwt = `${signingInput}.${signature}`;
  console.log("JWT created, length:", jwt.length);

  // Exchange for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion:  jwt,
    }),
  });

  const tokenData = await tokenRes.json();
  console.log("Token response status:", tokenRes.status);
  if (!tokenData.access_token) {
    throw new Error(`FCM token error: ${JSON.stringify(tokenData)}`);
  }
  console.log("Access token obtained successfully");
  return tokenData.access_token;
}

// ── Send FCM push notification ────────────────────────────────
async function sendFcmNotification(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
  accessToken: string
): Promise<void> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: {
            channel_id: "high_importance_channel",
            default_sound: true,
            default_vibrate_timings: true,
          },
        },
      },
    }),
  });

  const resText = await res.text();
  console.log("FCM response:", res.status, resText);
  if (!res.ok) throw new Error(`FCM send error ${res.status}: ${resText}`);
}

// ── Main handler ──────────────────────────────────────────────
serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    const payload    = await req.json();
    const record     = payload.record;
    const old_record = payload.old_record;

    console.log("Status change:", old_record?.status, "→", record?.status);

    if (!record) return new Response("No record", { status: 400 });

    const newStatus = record.status;
    const oldStatus = old_record?.status;
    if (newStatus === oldStatus) return new Response("No status change", { status: 200 });

    const config = NOTIFICATION_CONFIG[newStatus];
    if (!config) return new Response(`No config for: ${newStatus}`, { status: 200 });

    const bookingId  = record.id;
    const customerId = record.customer_id;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL"),
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    );

    // Get customer FCM token
    const { data: customer } = await supabase
      .from("users")
      .select("fcm_token, full_name")
      .eq("id", customerId)
      .maybeSingle();

    if (!customer?.fcm_token) {
      console.log("No FCM token for customer:", customerId);
      return new Response("No FCM token", { status: 200 });
    }
    console.log("Found FCM token for customer:", customerId);

    // Get booking details
    const { data: booking } = await supabase
      .from("bookings")
      .select("final_amount, services(name)")
      .eq("id", bookingId)
      .maybeSingle();

    const templateData = {
      booking_id:   bookingId,
      status:       newStatus,
      service_name: booking?.services?.name ?? "",
      final_amount: String(booking?.final_amount ?? ""),
      worker_name:  "",
    };

    // Get worker name if accepted
    if (newStatus === "accepted" && record.worker_id) {
      const { data: worker } = await supabase
        .from("users")
        .select("full_name")
        .eq("id", record.worker_id)
        .maybeSingle();
      templateData.worker_name = worker?.full_name ?? "";
    }

    // Get FCM access token
    const accessToken = await getFcmAccessToken();

    // Send notification
    await sendFcmNotification(
      customer.fcm_token,
      config.title,
      config.body(templateData),
      templateData,
      accessToken
    );

    console.log("✅ Notification sent! customer:", customerId, "status:", newStatus);

    // Save to in-app notifications table
    await supabase.from("notifications").insert({
      user_id:    customerId,
      title:      config.title,
      body:       config.body(templateData),
      type:       "booking",
      booking_id: bookingId,
      is_read:    false,
    }).then(({ error: e }) => {
      if (e) console.log("notifications insert skipped:", e.message);
    });

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });
  } catch (err) {
    console.error("Edge function error:", String(err));
    return new Response(JSON.stringify({ error: String(err) }), {
      headers: { "Content-Type": "application/json" }, status: 500,
    });
  }
});