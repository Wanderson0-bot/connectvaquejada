"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function AtualizacaoAoVivo({ eventoId }: { eventoId: string }) {
  const router = useRouter();
  const [conectado, setConectado] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    let ativo = true;
    let atualizar: number | undefined;
    const agendar = () => {
      if (!ativo || atualizar !== undefined) return;
      atualizar = window.setTimeout(() => {
        atualizar = undefined;
        router.refresh();
      }, 250);
    };
    const identificador = Math.random().toString(36).slice(2);
    const canal = supabase.channel(`connect-supervisao-${eventoId}-${identificador}`)
      .on("postgres_changes", {
        event: "INSERT", schema: "public", table: "connect_supervisao_realtime", filter: `evento_id=eq.${eventoId}`,
      }, agendar)
      .on("postgres_changes", {
        event: "UPDATE", schema: "public", table: "connect_supervisao_realtime", filter: `evento_id=eq.${eventoId}`,
      }, agendar)
      .subscribe((estado) => {
        if (!ativo) return;
        setConectado(estado === "SUBSCRIBED");
        if (estado === "SUBSCRIBED") agendar();
      });

    // Refresh also rechecks authorization after an organizer loses access.
    const intervalo = window.setInterval(agendar, 15000);
    return () => {
      ativo = false;
      window.clearInterval(intervalo);
      window.clearTimeout(atualizar);
      void supabase.removeChannel(canal);
    };
  }, [eventoId, router]);

  return <p role="status" className="flex items-center gap-2 text-sm text-stone-700">
    <span aria-hidden="true" className={`size-2 rounded-full ${conectado ? "bg-emerald-600" : "bg-amber-600"}`} />
    {conectado ? "Acompanhamento ao vivo" : "Atualização periódica"}
  </p>;
}
