import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { updateBoiTvAttendance } from "../actions";
import { CentralRealtime } from "../CentralRealtime";

type EventAssignment = { evento_id: string; nome: string; atendimentos_pendentes: number; eh_operador: boolean };
type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ erro?: string }>;
};
type Attendance = {
  id: string; evento_id: string; categoria_id: string; origem: string;
  estado_atendimento: string; dados_apresentacao: Record<string, unknown>;
  observacao_operacional: string | null; criada_em: string; atualizada_em: string;
};
const labels: Record<string,string> = {
  nova: "Nova solicitação", recebida: "Recebida", em_analise: "Em análise",
  analise_concluida: "Análise concluída", aguardando_decisao: "Aguardando decisão", finalizada: "Finalizada",
};
const nextState: Record<string,string> = {
  nova: "recebida", recebida: "em_analise", em_analise: "analise_concluida", analise_concluida: "aguardando_decisao",
};
function value(item: Attendance, key: string) {
  const result = item.dados_apresentacao[key];
  return result === null || result === undefined || result === "" ? "—" : String(result);
}

export default async function BoiTvEventQueue({ params, searchParams }: Props) {
  const { id } = await params;
  const { erro } = await searchParams;
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) redirect("/");
  const { data: allowedEvents, error: eventError } = await supabase.rpc("pista_ops_boi_tv_meus_eventos");
  const event = ((allowedEvents ?? []) as EventAssignment[]).find((entry) => entry.evento_id === id);
  if (eventError || !event) notFound();
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_atendimento_estado", { p_evento_id: id });
  const attendances = (data ?? []) as Attendance[];

  return <main className="mx-auto min-h-screen max-w-6xl bg-stone-50 px-4 py-8 text-stone-900 sm:px-8">
    <Link href="/boi-tv" className="text-sm text-stone-600 underline">Todos os eventos</Link>
    <header className="mt-5"><p className="text-sm font-semibold uppercase tracking-wider text-amber-800">Central BOI TV</p><h1 className="mt-1 text-3xl font-black">{event.nome}</h1><p className="mt-2 text-stone-600">A tela recupera todos os pedidos pendentes deste evento ao abrir.</p></header>
    <CentralRealtime eventId={id}/>
    {erro === "atendimento" && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-4 text-red-900">Não foi possível atualizar o atendimento. Confira o estado atual da solicitação e tente novamente.</p>}
    {error && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-4 text-red-900">Não foi possível carregar as solicitações.</p>}
    {!error && attendances.length === 0 && <p className="mt-6 rounded-xl border bg-white p-5 text-stone-600">Nenhuma solicitação recebida para este evento.</p>}
    <ul className="mt-6 space-y-4">{attendances.map((item) => <li key={item.id} className="rounded-xl border bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-lg font-bold">{value(item,"competidor")} · Senha {value(item,"senha")}</p><p className="mt-1 text-sm text-stone-600">{value(item,"evento")} · {value(item,"categoria")} · {value(item,"origem")}</p></div><span className="rounded-full bg-amber-100 px-3 py-1 text-sm font-semibold text-amber-950">{labels[item.estado_atendimento] ?? item.estado_atendimento}</span></div>
      <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
        <div><dt className="text-stone-500">Boi</dt><dd className="font-semibold">{value(item,"numero_boi")}</dd></div>
        <div><dt className="text-stone-500">Rodízio</dt><dd className="font-semibold">{value(item,"rodizio")}</dd></div>
        <div><dt className="text-stone-500">Equipe</dt><dd className="font-semibold">{value(item,"equipe")}</dd></div>
        <div><dt className="text-stone-500">Cavalo</dt><dd className="font-semibold">{value(item,"cavalo")}</dd></div>
        <div><dt className="text-stone-500">Tipo de pedido</dt><dd className="font-semibold">{value(item,"tipo_solicitacao")}</dd></div>
        <div><dt className="text-stone-500">Solicitado pelo perfil</dt><dd className="font-mono text-xs font-semibold">{value(item,"solicitante_id")}</dd></div>
        <div><dt className="text-stone-500">Resultado original</dt><dd className="font-semibold">{value(item,"resultado_original")}{item.dados_apresentacao.pontuacao_original !== null ? ` · ${value(item,"pontuacao_original")} pontos` : ""}</dd></div>
        <div><dt className="text-stone-500">Solicitado em</dt><dd className="font-semibold">{new Date(value(item,"solicitado_em")).toLocaleString("pt-BR")}</dd></div>
        <div><dt className="text-stone-500">Origem</dt><dd className="font-semibold">{value(item,"origem")}</dd></div>
      </dl>
      {item.observacao_operacional && <p className="mt-4 rounded-lg bg-stone-50 p-3 text-sm"><b>Observação operacional:</b> {item.observacao_operacional}</p>}
      {event.eh_operador && nextState[item.estado_atendimento] && <form action={updateBoiTvAttendance} className="mt-4">
        <input type="hidden" name="evento_id" value={id}/><input type="hidden" name="atendimento_id" value={item.id}/><input type="hidden" name="estado" value={nextState[item.estado_atendimento]}/>
        {(item.estado_atendimento === "recebida" || item.estado_atendimento === "em_analise") && <label className="mb-3 grid gap-1 text-sm font-medium">Observações da análise<textarea name="observacao" maxLength={2000} defaultValue={item.observacao_operacional ?? ""} className="min-h-20 rounded-lg border p-3" placeholder="Registrar observações operacionais para o organizador"/></label>}
        <button className="rounded-lg bg-amber-800 px-4 py-2 font-bold text-white">{item.estado_atendimento === "nova" ? "Confirmar recebimento" : item.estado_atendimento === "recebida" ? "Iniciar análise" : item.estado_atendimento === "em_analise" ? "Concluir análise" : "Enviar para decisão oficial"}</button>
      </form>}
    </li>)}</ul>
  </main>;
}
