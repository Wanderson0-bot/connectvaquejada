import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { CalendarDays, Layers3, MapPin, RefreshCw, Tag, Ticket } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import type { ReactNode } from "react";
import { ConfirmForm } from "@/components/ConfirmForm";
import { RefreshOnInterval } from "@/components/RefreshOnInterval";
import { atualizarStatusEvento, criarIniciarRodizio, terminarRodizioAtual } from "./actions";

type Category = { id: string; nome: string; ordem: number; valor_inscricao: number; ativa: boolean };
type Round = { id: string; numero: number; estado: string; categoria_nome: string; fila_total: number; fila_pendente: number };
type Event = { id: string; nome: string; data: string; status_operacional: string; parque_id: string; parque_nome: string; localizacao: string; quantidade_senhas: number; quantidade_rodizios: number; categorias: Category[]; rodizio_ativo: null | { id: string; numero: number; categoria_id: string; categoria_nome: string; fila_total: number; fila_pendente: number }; rodizios: Round[]; formato_competicao: string };

function fmtDate(date: string) { return new Date(`${date}T12:00:00`).toLocaleDateString("pt-BR", { day: "2-digit", month: "long", year: "numeric" }); }

export default async function EventoPage({ params, searchParams }: PageProps<"/eventos/[id]">) {
  const { id } = await params;
  const { acao, erro, sucesso } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data, error } = await supabase.rpc("painel_detalhes_evento", { p_evento_id: id });
  if (error || !data) notFound();
  const { data: formatoData, error: formatoError } = await supabase
    .from("eventos")
    .select("formato_competicao")
    .eq("id", id)
    .maybeSingle();
  if (formatoError || !formatoData) {
    return <main className="mx-auto min-h-screen max-w-4xl px-4 py-10">
      <p role="alert" className="rounded-lg bg-red-50 p-4 text-red-900">Não foi possível carregar o formato da competição. Verifique se a migration de Tropa de Elite foi aplicada.</p>
    </main>;
  }
  const evento = { ...(data as Omit<Event, "formato_competicao">), formato_competicao: formatoData.formato_competicao } as Event;
  const tropaDeElite = evento.formato_competicao === "tropa_de_elite";
  const hoje = new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });
  const pendente = evento.status_operacional === "agendado" && evento.data <= hoje;
  const ativo = evento.status_operacional === "em_andamento";
  const pausado = evento.status_operacional === "pausado";
  const encerrado = ["concluido", "cancelado"].includes(evento.status_operacional);
  const rotuloStatus: Record<string,string> = { em_andamento: "Em andamento", pausado: "Pausado", concluido: "Concluído", cancelado: "Cancelado" };

  return <main className="min-h-screen border-t-4 border-violet-500 bg-[#f7f7fc] px-4 py-6 sm:px-8">
    <RefreshOnInterval enabled={!acao} />
    <div className="mx-auto max-w-6xl">
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div><Link href={`/parques/${evento.parque_id}`} className="text-sm text-gray-600 underline">{evento.parque_nome}</Link><h1 className="mt-2 text-2xl font-bold sm:text-3xl">{evento.nome}</h1></div>
        {(ativo || pausado || encerrado) && <span className={`rounded-full px-5 py-2 font-bold text-white ${ativo ? "bg-[#ff7a00]" : pausado ? "bg-amber-500" : evento.status_operacional === "concluido" ? "bg-emerald-600" : "bg-gray-500"}`}>{rotuloStatus[evento.status_operacional]}</span>}
        {pendente && <span className="rounded-full bg-amber-500 px-5 py-2 font-bold text-white">Pendente</span>}
      </div>
      <div className="flex flex-wrap gap-x-8 gap-y-2 text-sm text-gray-600"><span className="flex items-center gap-2"><MapPin className="size-4" />{evento.localizacao}</span><span className="flex items-center gap-2"><CalendarDays className="size-4" />{fmtDate(evento.data)}</span></div>
      {erro && <p role="alert" className="mt-5 rounded-lg bg-red-50 p-3 text-sm text-red-800">{erro === "rodizio" ? "Não foi possível iniciar. Verifique a categoria, a quantidade de bois e se já há um rodízio ativo." : erro === "terminar-rodizio" ? "Não foi possível terminar o rodízio ativo." : "Essa ação não está disponível para o estado atual do evento."}</p>}
      {sucesso && <p role="status" className="mt-5 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-900">{sucesso === "rodizio" || sucesso === "terminar-rodizio" ? "Rodízio atualizado." : "Estado do evento atualizado."}</p>}
      {pendente && <div className="mt-6 flex flex-wrap items-center gap-4 rounded-xl bg-amber-50 p-4 text-amber-950"><p>O evento pode ser iniciado hoje.</p><form action={atualizarStatusEvento}><input type="hidden" name="evento_id" value={id} /><input type="hidden" name="acao" value="iniciar" /><button className="rounded-lg bg-emerald-600 px-5 py-2 font-bold text-white">Iniciar evento</button></form></div>}
      {evento.status_operacional === "agendado" && !pendente && <p className="mt-6 rounded-lg bg-white p-4 text-gray-600">O início ficará disponível no dia do evento.</p>}
      {pausado && <p role="status" className="mt-6 rounded-lg bg-amber-50 p-4 text-amber-950">Vaquejada pausada. Locução e inscrições estão temporariamente bloqueadas.</p>}
      {encerrado && <p role="status" className="mt-6 rounded-lg bg-gray-100 p-4 text-gray-700">{evento.status_operacional === "cancelado" ? "Evento anulado; as inscrições foram canceladas e removidas do Escritório." : "Evento concluído; inscrições e locução estão encerradas."}</p>}

      <section className="mt-8 rounded-2xl bg-white p-5 shadow-md sm:p-8">
        <div className="mb-8 flex flex-wrap justify-center gap-4">
          <Stat icon={<RefreshCw />} value={tropaDeElite ? "Eliminatória direta" : `${String(evento.quantidade_rodizios).padStart(2,"0")} Rodízios`} />
          <Stat icon={<Ticket />} value={`${evento.quantidade_senhas} Senhas`} />
          <Stat icon={<Tag />} value={evento.categorias.filter((cat) => cat.ativa).map((cat) => cat.nome).join(" · ") || "Sem categorias"} />
        </div>

        {!tropaDeElite && evento.rodizio_ativo && <div className="mb-6 rounded-xl border border-orange-200 bg-orange-50 p-4">
          <h2 className="font-bold text-orange-950">Rodízio #{evento.rodizio_ativo.numero} {evento.rodizios.find((round) => round.id === evento.rodizio_ativo?.id)?.estado === "aguardando_proximo_rodizio" ? "aguardando encerramento" : "em andamento"} · {evento.rodizio_ativo.categoria_nome}</h2>
          <p className="mt-1 text-sm text-gray-700">Corridas na fila: {evento.rodizio_ativo.fila_pendente} pendentes de {evento.rodizio_ativo.fila_total} registradas neste rodízio.</p>
          {ativo && <div className="mt-4 flex flex-wrap gap-3"><form action={terminarRodizioAtual}><input type="hidden" name="evento_id" value={id} /><button className="rounded-lg bg-[#87320a] px-5 py-3 font-bold text-white">Terminar rodízio</button></form></div>}
        </div>}

        {!tropaDeElite && ativo && !evento.rodizio_ativo && <div className="mb-6"><Link href={`/eventos/${id}?acao=novo-rodizio`} className="rounded-lg bg-emerald-600 px-5 py-3 font-bold text-white">Novo rodízio</Link></div>}

        {tropaDeElite ? <section className="rounded-xl border border-emerald-200 bg-emerald-50 p-5">
          <p className="text-sm font-bold uppercase tracking-wide text-emerald-900">Tropa de Elite · fase eliminatória</p>
          <h2 className="mt-2 text-xl font-bold text-emerald-950">A disputa começa sem classificatória</h2>
          <p className="mt-2 text-sm leading-relaxed text-emerald-950">Monte o chaveamento por categoria. Cada confronto começa com um boi por competidor; empate após esses bois segue para morte súbita.</p>
          <Link href={`/eventos/${id}/x1`} className="mt-4 inline-flex rounded-lg bg-emerald-800 px-5 py-3 font-bold text-white hover:bg-emerald-900">Abrir chave eliminatória</Link>
        </section> : <div className="grid gap-6 lg:grid-cols-2">
          <section className="rounded-xl bg-white p-5 shadow-[0_2px_14px_#0002] sm:p-7">
            <h2 className="text-center text-2xl font-bold">Ações do rodízio</h2>
            <p className="mt-2 text-center text-sm text-gray-600">O rodízio ativo é único para todo o evento.</p>
            {evento.rodizios.length > 0 && <ul className="mt-5 divide-y rounded-lg border text-sm">{evento.rodizios.map((round) => <li key={round.id} className="flex flex-wrap items-center justify-between gap-2 p-3"><span>#{round.numero} · {round.categoria_nome} · {round.estado.replaceAll("_"," ")}</span><span>Fila {round.fila_pendente}/{round.fila_total}</span></li>)}</ul>}
          </section>
          <section className="rounded-xl bg-white p-5 shadow-[0_2px_14px_#0002] sm:p-7">
            <h2 className="text-center text-2xl font-bold">Ações da vaquejada</h2>
            <div className="mt-6 flex flex-wrap justify-center gap-3">
              {(ativo || pausado) && <ConfirmForm action={atualizarStatusEvento} message="Terminar a vaquejada? Locução e inscrições serão encerradas."><input type="hidden" name="evento_id" value={id}/><input type="hidden" name="acao" value="concluir"/><button className="rounded-lg bg-[#87320a] px-5 py-3 font-bold text-white">Termina Vaquejada</button></ConfirmForm>}
              {ativo && <form action={atualizarStatusEvento}><input type="hidden" name="evento_id" value={id}/><input type="hidden" name="acao" value="pausar"/><button className="rounded-lg bg-black px-5 py-3 font-bold text-white">Parar Vaquejada</button></form>}
              {pausado && <form action={atualizarStatusEvento}><input type="hidden" name="evento_id" value={id}/><input type="hidden" name="acao" value="retomar"/><button className="rounded-lg bg-emerald-600 px-5 py-3 font-bold text-white">Continuar Vaquejada</button></form>}
              {!encerrado && <ConfirmForm action={atualizarStatusEvento} message="Anular a vaquejada? As inscrições serão canceladas e removidas da lista do Escritório."><input type="hidden" name="evento_id" value={id}/><input type="hidden" name="acao" value="anular"/><button className="rounded-lg bg-red-500 px-5 py-3 font-bold text-white">Anular Vaquejada</button></ConfirmForm>}
            </div>
          </section>
        </div>}

        <nav aria-label="Áreas do evento" className="mt-7 flex flex-wrap gap-3 border-t pt-5">
          <Link className="rounded-lg border px-4 py-2 text-sm font-semibold hover:border-orange-500" href={`/eventos/${id}/duplas`}>Escritório · Inscrições</Link>
          <Link className="rounded-lg border border-emerald-300 bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-900 hover:border-emerald-600" href={`/eventos/${id}/x1`}>{tropaDeElite ? "Tropa de Elite · Eliminatória" : "X1 · Chaveamento e pista"}</Link>
          <Link className="rounded-lg border px-4 py-2 text-sm font-semibold hover:border-orange-500" href={`/eventos/${id}/categorias`}>Categorias</Link>
          {ativo && !tropaDeElite && <Link className="rounded-lg border px-4 py-2 text-sm font-semibold hover:border-orange-500" href={`/eventos/${id}/pista-ops`}>Painel de locução</Link>}
        </nav>
      </section>
    </div>

    {!tropaDeElite && acao === "novo-rodizio" && <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4">
      <section role="dialog" aria-modal="true" aria-labelledby="new-round-title" className="w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl">
        <div className="flex items-start justify-between gap-3"><div><h2 id="new-round-title" className="text-xl font-bold">Novo rodízio</h2><p className="mt-1 text-sm text-gray-600">Escolha a categoria e a quantidade de bois; o sistema planeja e inicia o rodízio.</p></div><Link href={`/eventos/${id}`} aria-label="Fechar" className="rounded p-1 text-xl">×</Link></div>
        {erro === "rodizio" && <p role="alert" className="mt-4 rounded bg-red-50 p-3 text-sm text-red-800">Não foi possível iniciar. Confira os campos e se já há outro rodízio ativo.</p>}
        <form action={criarIniciarRodizio} className="mt-5 grid gap-4"><input type="hidden" name="evento_id" value={id}/>
          <label className="grid gap-2 text-sm font-semibold">Categoria<select name="categoria_id" required className="rounded-lg border px-3 py-2.5 font-normal"><option value="">Selecione</option>{evento.categorias.filter((cat) => cat.ativa).map((cat) => <option key={cat.id} value={cat.id}>{cat.nome}</option>)}</select></label>
          <label className="grid gap-2 text-sm font-semibold">Quantidade de bois<input name="quantidade_bois" type="number" min="1" step="1" required aria-describedby="capacidade-rodizio" className="rounded-lg border px-3 py-2.5 font-normal"/></label>
          <p id="capacidade-rodizio" className="text-sm text-gray-600">Esse número define as posições de boi do rodízio. No formato tradicional, cada inscrição gera duas corridas previstas, e a segunda depende do resultado da primeira.</p>
          <button className="rounded-lg bg-emerald-600 px-5 py-3 font-bold text-white">Planejar e iniciar</button>
        </form>
      </section>
    </div>}
  </main>;
}

function Stat({ icon, value }: { icon: ReactNode; value: string }) {
  return <div className="flex min-h-14 items-center gap-3 rounded-xl bg-[#ff7a00] px-4 py-3 text-sm font-semibold text-white sm:px-5"><span className="size-5 [&>svg]:size-5">{icon}</span><span>{value}</span></div>;
}
