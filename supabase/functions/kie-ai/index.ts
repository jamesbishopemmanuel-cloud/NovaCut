import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function publishableKey(): string | undefined {
  const direct = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (direct) return direct;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    return keys.default as string | undefined;
  } catch {
    return undefined;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const authorization = req.headers.get("Authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json({ error: "Sign in to NovaCut before using AI." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = publishableKey();
  const kieKey = Deno.env.get("KIE_API_KEY");
  if (!supabaseUrl || !anonKey) {
    return json({ error: "Supabase function configuration is incomplete." }, 500);
  }
  if (!kieKey) {
    return json({ error: "KIE_API_KEY has not been configured in Supabase Edge Function secrets." }, 503);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    return json({ error: "Your session is invalid or expired. Sign in again." }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Request body must be valid JSON." }, 400);
  }

  const action = body.action;
  const base = "https://api.kie.ai/api/v1/jobs/";
  let upstreamUrl: string;
  let method: string;
  let upstreamBody: string | undefined;

  if (action === "create") {
    const model = typeof body.model === "string" ? body.model.trim() : "";
    const input = body.input;
    if (!model || model.length > 100 || !input || typeof input !== "object" || Array.isArray(input)) {
      return json({ error: "Provide a model name and an input object." }, 400);
    }
    const inputJson = JSON.stringify(input);
    if (inputJson.length > 100_000) {
      return json({ error: "AI input is too large. Keep the request under 100 KB." }, 413);
    }
    upstreamUrl = base + "createTask";
    method = "POST";
    upstreamBody = JSON.stringify({
      model,
      input,
      ...(typeof body.callBackUrl === "string" ? { callBackUrl: body.callBackUrl } : {}),
    });
  } else if (action === "status") {
    const taskId = typeof body.taskId === "string" ? body.taskId.trim() : "";
    if (!taskId || taskId.length > 200 || !/^[\w-]+$/.test(taskId)) {
      return json({ error: "Provide a valid taskId." }, 400);
    }
    upstreamUrl = base + "recordInfo?taskId=" + encodeURIComponent(taskId);
    method = "GET";
  } else {
    return json({ error: "Unsupported action. Use create or status." }, 400);
  }

  try {
    const upstream = await fetch(upstreamUrl, {
      method,
      headers: {
        Authorization: `Bearer ${kieKey}`,
        "Content-Type": "application/json",
      },
      ...(upstreamBody ? { body: upstreamBody } : {}),
    });
    const raw = await upstream.text();
    let result: unknown;
    try {
      result = JSON.parse(raw);
    } catch {
      return json({ error: "KIE returned an unreadable response.", upstreamStatus: upstream.status }, 502);
    }

    // KIE may report application errors in JSON even when the HTTP status is 200.
    const record = result as { code?: number; msg?: string };
    if (!upstream.ok || (typeof record.code === "number" && record.code !== 200)) {
      return json({
        error: record.msg ?? "KIE request failed.",
        kieCode: record.code ?? upstream.status,
      }, upstream.status >= 400 ? upstream.status : 502);
    }
    return json(result, 200);
  } catch {
    return json({ error: "Could not reach KIE. Check the provider status and try again." }, 502);
  }
});
