import { Voltar } from "@/components/Voltar";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type EventAssignment = { evento_id: string; nome: string; atendimentos_pendentes: number; eh_operador: boolean };

export default async function BoiTvCentralHome() {
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) redirect("/");
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_meus_eventos");
  const events = (data ?? []) as EventAssignment[];

  return <main className="mx-auto min-h-screen max-w-5xl bg-stone-50 px-4 py-8 text-stone-900 sm:px-8">
    {!user.is_anonymous && <Voltar />}
    <header><p className="text-sm font-semibold uppercase tracking-wider text-amber-800">Connect · Central operacional</p><h1 className="mt-1 text-3xl font-black">BOI TV</h1><p className="mt-2 text-stone-600">Eventos autorizados para sua equipe.</p></header>
    {error && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-4 text-red-900">Não foi possível carregar seus eventos.</p>}
    {!error && events.length === 0 && <p className="mt-6 rounded-xl border bg-white p-5 text-stone-600">Nenhum evento foi autorizado para este perfil.</p>}
    <ul className="mt-6 grid gap-3 sm:grid-cols-2">{events.map((event) => <li key={event.evento_id}>
      <Link href={`/boi-tv/${event.evento_id}`} className="block rounded-xl border bg-white p-5 shadow-sm hover:border-amber-500">
        <span className="text-lg font-bold">{event.nome}</span><span className="mt-2 block text-sm text-stone-600">{event.atendimentos_pendentes} solicitações pendentes</span>
      </Link>
    </li>)}</ul>
  </main>;
}
