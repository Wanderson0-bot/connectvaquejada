import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowRight, Swords } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { PainelShell } from "@/components/PainelShell";

type EventOption = { id: string; nome: string; data: string };

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", year: "numeric" })
    .format(new Date(`${value}T12:00:00`));
}

export default async function DisputaX1Page() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");

  const [{ data: operations }, { data: parkEvents }] = await Promise.all([
    supabase.rpc("painel_listar_operacoes"),
    supabase.rpc("painel_eventos_em_andamento"),
  ]);
  const byId = new Map<string, EventOption>();
  for (const event of [...(operations ?? []), ...(parkEvents ?? [])] as EventOption[]) {
    byId.set(event.id, { id: event.id, nome: event.nome, data: event.data });
  }
  const events = [...byId.values()].sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  return <PainelShell active="x1">
    <header className="dashboard-header">
      <div>
        <h1 className="dashboard-title">Disputa de X1</h1>
        <p className="dashboard-description">Escolha uma vaquejada ativa para abrir ou acompanhar o chaveamento e registrar os bois.</p>
      </div>
    </header>
    {!events.length ? <section className="rounded-2xl border border-dashed border-orange-200 bg-white/70 p-8 text-stone-600">
      Nenhum evento ativo disponível para abrir uma disputa de X1.
    </section> : <section aria-label="Eventos ativos" className="grid gap-4 lg:grid-cols-2">
      {events.map((event) => <article key={event.id} className="rounded-2xl border border-orange-100 bg-white/95 p-5 shadow-lg shadow-orange-950/5">
        <h2 className="text-xl font-bold text-stone-900">{event.nome}</h2>
        <p className="mt-1 text-sm text-stone-600">Ativo · {formatDate(event.data)}</p>
        <Link href={`/eventos/${event.id}/x1`} className="mt-5 inline-flex items-center gap-2 rounded-lg bg-emerald-800 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-900">
          <Swords className="size-4" /> Abrir disputa <ArrowRight className="size-4" />
        </Link>
      </article>)}
    </section>}
  </PainelShell>;
}
