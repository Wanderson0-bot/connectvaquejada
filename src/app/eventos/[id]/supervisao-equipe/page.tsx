import Link from "next/link";
import { Activity, ClipboardCheck, FileText, Users } from "lucide-react";
import { ConfirmForm } from "@/components/ConfirmForm";
import { Voltar } from "@/components/Voltar";
import { AtualizacaoAoVivo } from "@/components/supervisao/AtualizacaoAoVivo";
import { Classificacao } from "@/components/supervisao/Classificacao";
import { carregarSupervisao } from "@/lib/supervisao/servidor";
import { funcoes, horarioEvento, rotulo, statusEvento, uuid } from "@/lib/supervisao/modelo";
import { alterarStatus } from "./actions";

const acoes = {
  iniciar: "Iniciar", pausar: "Pausar", retomar: "Retomar", concluir: "Concluir", anular: "Anular",
};
const etapas = [
  ["nova", "Nova"], ["recebida", "Recebida"], ["em_analise", "Em análise"],
  ["analise_concluida", "Análise concluída"],
  ["aguardando_decisao", "Aguardando decisão"], ["finalizada", "Finalizada"],
] as const;
const painel = "rounded-2xl border border-stone-200 bg-white p-4 sm:p-6";

export default async function SupervisaoPage({ params, searchParams }: PageProps<"/eventos/[id]/supervisao-equipe">) {
  const { id } = await params;
  const query = await searchParams;
  const filtro = typeof query.categoria === "string" ? query.categoria : "";
  const dados = await carregarSupervisao(id, uuid.test(filtro) ? filtro : null);
  const { evento, categorias, equipe, dispositivos, rodizio, boi_tv } = dados;
  const categoria = categorias.find((item) => item.id === filtro);
  const emEliminatoria = filtro === "x1" || categoria?.modelo === "eliminatoria";
  const chaves = dados.chaves.filter((chave) => filtro === "x1"
    ? chave.modelo === "X1" : chave.categoria_id === categoria?.id);
  const caminho = `/eventos/${id}/supervisao-equipe`;
  const hoje = new Intl.DateTimeFormat("sv-SE", { timeZone: "America/Sao_Paulo" }).format(new Date());
  const disponiveis: (keyof typeof acoes)[] = [];
  if (evento.status === "agendado" && evento.data <= hoje) disponiveis.push("iniciar");
  if (evento.status === "em_andamento") disponiveis.push("pausar", "concluir");
  if (evento.status === "pausado") disponiveis.push("retomar", "concluir");
  if (evento.status !== "concluido" && evento.status !== "cancelado") disponiveis.push("anular");

  return <main className="min-h-screen bg-stone-50 px-4 py-6 text-stone-900 sm:px-8">
    <div className="mx-auto max-w-7xl space-y-5">
      <Voltar />
      <header className="flex flex-wrap items-start justify-between gap-5 rounded-2xl bg-stone-900 p-6 text-white sm:p-8">
        <div>
          <p className="text-sm font-semibold text-orange-300">Central da Equipe Connect Vaquejada</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{evento.nome}</h1>
          <p className="mt-2 text-sm text-stone-200">{evento.parque ?? "Operação temporária"} · {evento.data.split("-").reverse().join("/")}</p>
          <p className="mt-3 inline-block rounded-full bg-stone-700 px-3 py-1 text-sm font-semibold">{statusEvento[evento.status]}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link className="operation-primary" href={`/eventos/${id}/relatorio-operacional`}>
            <FileText aria-hidden="true" className="size-4" /> Relatório operacional
          </Link>
          <Link className="operation-secondary" prefetch={false} href={`/eventos/${id}/relatorio-operacional/csv`} download>Exportar CSV</Link>
        </div>
      </header>

      {query.erro && <p role="alert" className="rounded-lg bg-red-100 p-3 text-red-900">A ação não foi concluída. Confira o estado atual do evento.</p>}
      {query.atualizado && <p role="status" className="rounded-lg bg-emerald-100 p-3 text-emerald-900">Estado da vaquejada atualizado.</p>}
      {disponiveis.length > 0 && <section className={painel} aria-labelledby="ciclo-evento">
        <h2 id="ciclo-evento" className="text-lg font-bold">Ciclo da vaquejada</h2>
        <div className="mt-3 flex flex-wrap gap-2">{disponiveis.map((acao) => (
          <ConfirmForm key={acao} action={alterarStatus.bind(null, id, filtro, acao)}
            message={acao === "anular" ? "Anular a vaquejada e cancelar as inscrições?" : `${acoes[acao]} a vaquejada?`}>
            <button className={acao === "anular" ? "operation-secondary text-red-800" : "operation-secondary"}>
              {acoes[acao]}
            </button>
          </ConfirmForm>
        ))}</div>
      </section>}

      <section className={painel} aria-labelledby="pista">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="pista" className="flex items-center gap-2 text-lg font-bold"><Activity aria-hidden="true" size={20} /> Acompanhamento da pista</h2>
          <AtualizacaoAoVivo key={id} eventoId={id} />
        </div>
        <nav aria-label="Selecionar categoria" className="mt-4 flex flex-wrap gap-2">
          {[...categorias.map(({ id, nome }) => ({ id, nome })), { id: "x1", nome: "X1" }].map((opcao) => (
            <Link key={opcao.id} href={`${caminho}?categoria=${opcao.id}`} aria-current={filtro === opcao.id ? "page" : undefined}
              className={filtro === opcao.id ? "operation-primary" : "operation-secondary"}>{opcao.nome}</Link>
          ))}
        </nav>
        {!categoria && filtro !== "x1" && <p className="mt-4 text-sm text-stone-600">Selecione uma categoria para acompanhar a pista.</p>}
        {categoria && !emEliminatoria && <div className="mt-5 space-y-4">
          <dl className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            {[
              ["Rodízio ativo", rodizio ? `#${rodizio.numero}` : "—"],
              ["Senha atual", rodizio?.senha_atual ?? "—"],
              ["Senhas corridas", rodizio?.corridas ?? "—"],
              ["Senhas restantes", rodizio?.restantes ?? "—"],
            ].map(([titulo, valor]) => <div key={titulo} className="rounded-lg bg-stone-100 p-3">
              <dt className="text-sm text-stone-600">{titulo}</dt><dd className="text-xl font-bold">{valor}</dd>
            </div>)}
          </dl>
          <div className="grid gap-5 xl:grid-cols-2">
            <section><h3 className="mb-2 font-bold">Classificação parcial</h3><Classificacao itens={categoria.parcial} /></section>
            <section><h3 className="mb-2 font-bold">Classificação geral</h3><Classificacao itens={categoria.geral} /></section>
          </div>
        </div>}
        {emEliminatoria && <div className="mt-5 grid gap-4">
          {!chaves.length && <p className="text-sm text-stone-600">Nenhuma chave criada.</p>}
          {chaves.map((chave) => <section key={chave.id} className="rounded-xl border border-stone-200 p-4">
            <h3 className="font-bold">{chave.categoria} · {rotulo(chave.estado)}</h3>
            <p className="mt-1 text-sm text-stone-600">{chave.confrontos.filter((confronto) => confronto.estado === "finalizada").length} de {chave.confrontos.length} confrontos concluídos</p>
            {chave.campeao && <p className="mt-2 font-semibold text-emerald-900">Campeão · {chave.campeao}</p>}
            <ul className="mt-3 divide-y divide-stone-200 text-sm">{chave.confrontos.map((confronto) => (
              <li key={confronto.id} className="flex flex-wrap justify-between gap-2 py-2">
                <span>Fase {confronto.fase} · Confronto {confronto.posicao} · {confronto.lado_a ?? "A definir"} × {confronto.lado_b ?? "A definir"}</span>
                <span className="font-semibold">{confronto.vencedor ? `Avançou: ${confronto.vencedor}` : rotulo(confronto.estado)}</span>
              </li>
            ))}</ul>
          </section>)}
        </div>}
      </section>

      <div className="grid gap-5 xl:grid-cols-2">
        <section className={painel} aria-labelledby="equipe">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 id="equipe" className="flex items-center gap-2 text-lg font-bold"><Users aria-hidden="true" size={20} /> Equipe e dispositivos</h2>
            <Link className="operation-secondary" href={`/painel/dispositivos?evento=${id}`}>Convites e revogação</Link>
          </div>
          <p className="mt-3 text-sm text-stone-600">{equipe?.length ?? 0} vínculos de equipe · {dispositivos?.filter(({ estado }) => estado === "ativo").length ?? 0} dispositivos ativos</p>
          <ul className="mt-2 divide-y divide-stone-200 text-sm">{equipe?.map((membro) => (
            <li key={membro.id} className="flex justify-between gap-3 py-2"><span>{membro.nome}</span><span>{funcoes[membro.funcao]}</span></li>
          ))}</ul>
          <ul className="mt-2 divide-y divide-stone-200 text-sm">{dispositivos?.map((dispositivo) => (
            <li key={dispositivo.id} className="py-2">
              <p className="font-semibold">{dispositivo.nome} · {funcoes[dispositivo.funcao]}</p>
              <p className="text-stone-600">{rotulo(dispositivo.estado)} · {dispositivo.operador ?? "Vínculo por código"} · Último acesso {horarioEvento(dispositivo.ultimo_acesso)}</p>
            </li>
          ))}</ul>
        </section>
        <section className={painel} aria-labelledby="boi-tv">
          <h2 id="boi-tv" className="flex items-center gap-2 text-lg font-bold"><ClipboardCheck aria-hidden="true" size={20} /> Revisões BOI TV</h2>
          <dl className="mt-4 grid grid-cols-2 gap-3">{etapas.map(([chave, titulo]) => (
            <div key={chave} className="rounded-lg bg-stone-100 p-3">
              <dt className="text-sm text-stone-600">{titulo}</dt>
              <dd className="text-2xl font-bold tabular-nums">{boi_tv[chave]}</dd>
            </div>
          ))}</dl>
        </section>
      </div>
    </div>
  </main>;
}
