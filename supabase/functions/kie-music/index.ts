// Supabase Edge Function: supabase/functions/kie-music/index.ts
// Configure KIE_API_KEY as a Supabase Function secret. Never put this key in Flutter code.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);
  const apiKey = Deno.env.get("KIE_API_KEY");
  if (!apiKey) return json({ error: "KIE_API_KEY is not configured as a Supabase Function secret." }, 500);

  try {
    const body = await req.json();
    const action = String(body.action ?? "");
    let url: string;
    let payload: Record<string, unknown> | undefined;
    if (action === "generate") {
      const prompt = String(body.prompt ?? "").trim();
      if (!prompt) return json({ error: "Song description or lyrics are required." }, 400);
      const instrumental = body.instrumental === true;
      payload = {
        model: "ai-music-api/generate",
        input: {
          custom_mode: false,
          instrumental,
          model: "V6",
          prompt: prompt.slice(0, 3000),
          ...(instrumental ? {} : {}),
        },
      };
      // Non-custom mode uses prompt for the song request. Title/style are intentionally
      // not sent in this mode because KIE says other parameters should be left empty.
      url = "https://api.kie.ai/api/v1/jobs/createTask";
    } else if (action === "status") {
      const taskId = String(body.taskId ?? "").trim();
      if (!taskId) return json({ error: "taskId is required." }, 400);
      url = "https://api.kie.ai/api/v1/jobs/recordInfo?taskId=" + encodeURIComponent(taskId);
    } else if (action === "separate") {
      const taskId = String(body.taskId ?? "").trim();
      const audioId = String(body.audioId ?? "").trim();
      if (!taskId || !audioId) return json({ error: "taskId and audioId are required for generated-track stem extraction." }, 400);
      payload = { model: "ai-music-api/separate-vocals", input: { task_id: taskId, audio_id: audioId, type: String(body.type ?? "split_stem") } };
      url = "https://api.kie.ai/api/v1/jobs/createTask";
    } else {
      return json({ error: "Unsupported action. Use generate, status, or separate." }, 400);
    }

    const response = await fetch(url, {
      method: action === "status" ? "GET" : "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      ...(payload ? { body: JSON.stringify(payload) } : {}),
    });
    const result = await response.json().catch(() => ({}));
    // KIE can return HTTP 200 for API-level errors, so inspect its code too.
    if (!response.ok || (typeof result.code === "number" && result.code !== 200 && result.code !== 201)) {
      return json({ error: result.msg ?? result.message ?? `KIE API failed (HTTP ${response.status})`, details: result }, 502);
    }
    return json(result, 200);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected KIE integration error." }, 500);
  }
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
