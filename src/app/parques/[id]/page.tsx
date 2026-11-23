import { Voltar } from "@/components/Voltar";
import Link from "next/link";
import { CalendarDays, Layers3, MapPin, Plus, RefreshCw, Ticket, Tag, ArrowRight } from "lucide-react";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PainelShell } from "@/components/PainelShell";
import { Paisagem } from "@/components/Paisagem";
import { atualizarStatusEvento } from "@/app/eventos/[id]/actions";

type Evento = { id: string; nome: string; data: string; status_operacional: string; quantidade_senhas: number; quantidade_rodizios: number; categorias: string[] };
function dataPt(data: string) { return new Date(`${data}T12:00:00`).toLocaleDateString("pt-BR", { day: "2-digit", month: "short", year: "numeric" }); }

export default async function ParquePage({ params, searchParams }: PageProps<"/parques/[id]">) {
  const { id } = await params;
  const { erro } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const [{ data: parques }, { data: lista, error }] = await Promise.all([
    supabase.rpc("painel_listar_parques"),
    supabase.rpc("painel_eventos_do_parque", { p_parque_id: id }),
  ]);
  const parque = (parques ?? []).find((item: { id: string }) => item.id === id);
  if (!parque) notFound();
  if (error) return <PainelShell active="painel"><Voltar /><p role="alert">Não foi possível carregar os eventos deste parque.</p></PainelShell>;
  const eventos = (lista ?? []) as Evento[];
  const hoje = new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });
  return <PainelShell active="painel">
    <Voltar />
    <header className="mb-7 flex flex-wrap items-start justify-between gap-4">
      <div><h1 className="mt-2 text-3xl font-bold sm:text-4xl">{parque.nome}</h1>
        <p className="mt-2 flex flex-wrap items-center gap-2 text-gray-600"><MapPin className="size-4" />{parque.localizacao}<span className="mx-2 text-gray-300">|</span><Layers3 className="size-5" />{String(parque.quantidade_eventos).padStart(2,"0")} eventos</p></div>
      <Link href={`/parques/${id}/eventos/novo`} aria-label="Criar evento" className="flex size-11 items-center justify-center rounded-full bg-[#87320a] text-white hover:bg-[#a34614]"><Plus className="size-7" /></Link>
    </header>
    {erro === "evento" && <p role="alert" className="mb-5 rounded-lg bg-red-50 p-3 text-sm text-red-800">Não foi possível criar o evento. Confira o nome e a data.</p>}
    {!eventos.length ? <section className="rounded-2xl bg-white p-8 text-center shadow-md"><h2 className="text-xl font-semibold">Nenhum evento cadastrado</h2><p className="mt-2 text-gray-600">Crie o primeiro evento deste parque pelo botão +.</p></section> :
      <section aria-label="Eventos do parque" className="grid gap-6 xl:grid-cols-2">
        {eventos.map((evento) => {
          const pendente = evento.status_operacional === "agendado" && evento.data <= hoje;
          const rotulos: Record<string,string> = { em_andamento: "Em andamento", pausado: "Pausado", concluido: "Concluído", cancelado: "Cancelado" };
          const cor = evento.status_operacional === "em_andamento" ? "bg-[#ff7a00]" : evento.status_operacional === "concluido" ? "bg-emerald-500" : evento.status_operacional === "cancelado" ? "bg-gray-500" : "bg-amber-500";
          return <article key={evento.id} className="overflow-hidden rounded-xl bg-white shadow-md">
            <Paisagem className="h-44 w-full" />
            <div className="p-5">
              <h2 className="text-lg font-bold">{evento.nome}</h2>
              <div className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-sm text-gray-600">
                <p className="flex items-center gap-2"><CalendarDays className="size-4" />{dataPt(evento.data)}</p>
                <p className="flex items-center gap-2"><RefreshCw className="size-4" />{String(evento.quantidade_rodizios).padStart(2,"0")} Rodízios</p>
                <p className="flex items-center gap-2"><Ticket className="size-4" />{evento.quantidade_senhas} Senhas</p>
                <p className="col-span-2 flex items-start gap-2"><Tag className="mt-0.5 size-4 shrink-0" />{evento.categorias.length ? evento.categorias.join(" · ") : "Sem categorias cadastradas"}</p>
              </div>
              <div className="mt-5 flex min-h-10 justify-end">
                {(pendente || rotulos[evento.status_operacional]) && <span className={`inline-flex items-center rounded-full px-5 py-2 text-sm font-bold text-white ${pendente ? "bg-amber-500" : cor}`}>{pendente ? "Pendente" : rotulos[evento.status_operacional]}</span>}
                {pendente && <form action={atualizarStatusEvento} className="ml-2"><input type="hidden" name="evento_id" value={evento.id}/><input type="hidden" name="acao" value="iniciar"/><button className="rounded-lg bg-emerald-600 px-5 py-2 text-sm font-bold text-white">Iniciar</button></form>}
                <Link href={`/eventos/${evento.id}`} className="ml-3 inline-flex items-center gap-2 self-end font-medium text-[#87320a] underline">Ver detalhes <ArrowRight className="size-4" /></Link>
              </div>
            </div>
          </article>;
        })}
      </section>}
  </PainelShell>;
}
