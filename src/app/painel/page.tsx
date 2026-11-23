import { Voltar } from "@/components/Voltar";
import Link from "next/link";
import { Flag, Plus } from "lucide-react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PainelShell } from "@/components/PainelShell";
import { iniciarOperacao } from "./operacoes/actions";
import { OperationCard } from "./OperationCard";
import { statusEvento, type Evento } from "@/lib/supervisao/modelo";

type Operacao = { id: string; nome: string; data: string; status_operacional: string; quantidade_inscricoes: number; quantidade_dispositivos: number };
type Membro = { id: string; usuario_id: string; funcao: string };
type CardOperacao = Operacao & { membros: Membro[]; membrosError: boolean; categorias: string[]; iniciadoEm: string | null };
type Props = { searchParams: Promise<{ erro?: string; iniciada?: string; encerrada?: string; membro?: string }> };

export default async function PainelPage({ searchParams }: Props) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const [{ data, error }, { data: dadosSupervisao }] = await Promise.all([
    supabase.rpc("painel_listar_operacoes"),
    supabase.rpc("connect_eventos_supervisionados"),
  ]);
  const operacoes = (data ?? []) as Operacao[];
  const eventosSupervisionados = (dadosSupervisao ?? []) as Pick<Evento, "id" | "nome" | "data" | "status">[];
  const eventosComCentral = new Set(eventosSupervisionados.map((evento) => evento.id));
  const operacoesAtivas = new Set(operacoes.map((operacao) => operacao.id));
  const outrasCentrais = eventosSupervisionados.filter((evento) => !operacoesAtivas.has(evento.id));
  const { data: horarios, error: horariosError } = operacoes.length
    ? await supabase.from("eventos").select("id,created_at").in("id", operacoes.map((op) => op.id))
    : { data: [] as { id: string; created_at: string }[], error: null };
  const horarioPorEvento = new Map((horarios ?? []).map((item) => [item.id, item.created_at]));
  const operacoesComMembros: CardOperacao[] = await Promise.all(operacoes.map(async (operacao) => {
    const { data: stateData, error: stateError } = await supabase.rpc("pista_ops_state", {
      p_evento_id: operacao.id,
      p_categoria_id: null,
    });
    const state = stateData as unknown as { membros?: Membro[]; categorias?: { nome: string }[] } | null;
    return { ...operacao,
      membros: state?.membros ?? [], membrosError: Boolean(stateError),
      categorias: (state?.categorias ?? []).map((category) => category.nome),
      iniciadoEm: horarioPorEvento.get(operacao.id) ?? null };
  }));
  const errorMessage = query.erro === "nome-operacao"
    ? "Informe um nome de até 120 caracteres."
    : query.erro === "membro-parque"
      ? "O perfil convidado deve pertencer ao mesmo parque do seu perfil. Confira também se seu perfil está associado a um parque."
      : query.erro === "membro-inexistente"
        ? "Não há acesso ativo com esse perfil e função para revogar."
        : query.erro === "membro"
          ? "Não foi possível aplicar a função. Confira os dados e sua permissão de organizador."
          : query.erro === "iniciar-operacao"
            ? "Não foi possível iniciar a operação."
            : "Não foi possível concluir a operação. Confira sua permissão e tente novamente.";

  return <PainelShell active="painel">
    <Voltar href="/" />
    <header className="dashboard-header">
      <div><h1 className="dashboard-title">Operações</h1><p className="dashboard-description">Gerencie as vaquejadas, do escritório à locução.</p></div>
      <a href="#nova-operacao" className="operation-primary"><Plus className="size-4" aria-hidden="true" /> Nova operação</a>
    </header>
    {query.erro && <p role="alert" className="dashboard-error">{errorMessage}</p>}
    {horariosError && <p role="alert" className="dashboard-error">Não foi possível carregar os horários das operações.</p>}
    {query.iniciada && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">Operação iniciada. Ela já está disponível para inscrições e chamadas.</p>}
    {query.encerrada && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">Operação encerrada. Novos cadastros, chamadas e acessos dos dispositivos foram bloqueados.</p>}
    {query.membro === "adicionado" && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">Função de evento adicionada.</p>}
    {query.membro === "revogado" && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">Função de evento revogada.</p>}

    <section id="nova-operacao" className="operation-create" aria-labelledby="nova-operacao-titulo">
      <div className="operation-create-heading">
        <span className="operation-icon"><Flag className="size-5" aria-hidden="true" /></span>
        <h2 id="nova-operacao-titulo">Iniciar nova operação</h2>
      </div>
      <form action={iniciarOperacao} className="operation-create-form">
        <label>Nome da operação
          <input name="nome" required maxLength={120} placeholder="Ex.: Vaquejada de sábado" />
        </label>
        <button className="operation-primary">Iniciar operação</button>
      </form>
    </section>

    {error && <p role="alert" className="dashboard-error">Não foi possível carregar as operações.</p>}
    <section aria-labelledby="operacoes-titulo" className="grid gap-4">
      <h2 id="operacoes-titulo" className="text-xl font-bold tracking-tight text-stone-900">Minhas operações</h2>
      {operacoesComMembros.map((operacao) => <OperationCard key={operacao.id} operation={operacao} podeSupervisionar={eventosComCentral.has(operacao.id)} />)}
      {!error && operacoes.length === 0 && <p className="dashboard-empty-state text-stone-600">Nenhuma operação disponível. Inicie uma acima para abrir o escritório e a locução.</p>}
    </section>
    {outrasCentrais.length > 0 && <section aria-labelledby="centrais-equipe" className="mt-8">
      <h2 id="centrais-equipe" className="text-xl font-bold tracking-tight text-stone-900">Centrais da equipe</h2>
      <ul className="mt-3 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-white">
        {outrasCentrais.map((evento) => <li key={evento.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
          <div><p className="font-bold">{evento.nome}</p><p className="text-sm text-stone-600">{evento.data.split("-").reverse().join("/")} · {statusEvento[evento.status]}</p></div>
          <Link href={`/eventos/${evento.id}/supervisao-equipe`} className="operation-secondary">Abrir Central da Equipe</Link>
        </li>)}
      </ul>
    </section>}
  </PainelShell>;
}
