import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401 });

  const { data, error } = await supabase.rpc("pista_ops_boi_tv_meus_eventos");
  if (error || !(data ?? []).some((event: { evento_id: string }) => event.evento_id === id)) {
    return new Response("Forbidden", { status: 403 });
  }

  const encoder = new TextEncoder();
  let channel: ReturnType<typeof supabase.channel> | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const enqueue = (value: string) => {
        try { controller.enqueue(encoder.encode(value)); } catch { /* Closed by the client. */ }
      };
      enqueue(": connected\n\n");
      channel = supabase.channel(`boi-tv-${id}-${crypto.randomUUID()}`)
        .on("postgres_changes", {
          event: "*", schema: "public", table: "pista_ops_boi_tv_atendimentos",
          filter: `evento_id=eq.${id}`,
        }, (payload) => enqueue(`data: ${JSON.stringify(payload)}\n\n`))
        .subscribe();
      heartbeat = setInterval(() => enqueue(": keepalive\n\n"), 20000);
      request.signal.addEventListener("abort", () => {
        if (heartbeat) clearInterval(heartbeat);
        if (channel) void supabase.removeChannel(channel);
        try { controller.close(); } catch { /* Stream already closed. */ }
      }, { once: true });
    },
    cancel() {
      if (heartbeat) clearInterval(heartbeat);
      if (channel) void supabase.removeChannel(channel);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
