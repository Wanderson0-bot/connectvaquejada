import Link from "next/link";
import { Classificacao } from "@/components/supervisao/Classificacao";
import { ImprimirRelatorio } from "@/components/supervisao/ImprimirRelatorio";
import { Voltar } from "@/components/Voltar";
import { carregarSupervisao } from "@/lib/supervisao/servidor";
import { horarioEvento, indicadores, percentual, resumo, rotulo, statusEvento, totalOcorrencias } from "@/lib/supervisao/modelo";

const bloco = "rounded-xl border border-stone-200 bg-white p-4 sm:p-6 print:rounded-none print:border-0 print:p-0";
const porcentagem = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 });

export default async function RelatorioPage({ params }: PageProps<"/eventos/[id]/relatorio-operacional">) {
  const { id } = await params;
  const { evento, gerado_em, categorias, chaves, rodizios, revisoes } = await carregarSupervisao(id, null, true);
  const totais = resumo(categorias);
  const classificatorias = categorias.filter((categoria) => categoria.modelo === "classificatoria");
  const observacoes = totalOcorrencias(totais);
  const final = evento.status === "concluido";

  return <main className="min-h-screen bg-stone-50 px-4 py-8 text-stone-900 sm:px-8 print:min-h-0 print:bg-white print:p-0 print:text-black">
    <div className="mx-auto max-w-6xl space-y-6 print:max-w-none">
      <nav aria-label="Ações do relatório" className="flex flex-wrap items-start justify-between gap-2 print:hidden">
        <Voltar href={`/eventos/${id}/supervisao-equipe`} />
        <div className="flex flex-wrap gap-2">
          <Link className="operation-primary" prefetch={false} href={`/eventos/${id}/relatorio-operacional/csv`} download>Exportar CSV</Link>
          <ImprimirRelatorio />
        </div>
      </nav>
      <header className="border-b border-stone-300 pb-4">
        <p className="text-sm font-semibold text-orange-900">Connect Vaquejada</p>
        <h1 className="mt-1 text-3xl font-bold">Relatório operacional e esportivo</h1>
        <p className="mt-2 text-lg font-semibold">{evento.nome}</p>
        <p className="text-sm">{evento.parque ?? "Operação temporária"} · {evento.data.split("-").reverse().join("/")} · {statusEvento[evento.status]}</p>
        <p className="mt-1 text-sm">Emitido em {horarioEvento(gerado_em)}{!final ? " · Consulta do estado atual" : ""}</p>
      </header>

      <section className={bloco} aria-labelledby="resumo-operacional">
        <h2 id="resumo-operacional" className="text-xl font-bold">Resumo geral da prova</h2>
        <p className="mt-2 text-sm">{totais.ativas} inscrições ativas · {totais.canceladas} canceladas · {totais.concluidas} corridas concluídas</p>
        <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4 print:grid-cols-4">{indicadores.map(({ id, nome }) => (
          <div key={id} className="rounded-lg border border-stone-200 p-3">
            <dt className="text-sm">{nome}</dt>
            <dd className="font-bold">{totais[id]} <span className="text-sm font-normal">({porcentagem.format(percentual(totais[id], observacoes))}%)</span></dd>
          </div>
        ))}</dl>
        <p className="mt-2 text-sm text-stone-600">Os percentuais usam as ocorrências de rodízio como base. O total de corridas concluídas considera resultados definitivos e conclusões de Rabo da Gata registradas.</p>
        <div className="mt-4 overflow-x-auto print:overflow-visible">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="border-b border-stone-300"><tr>
              {["Categoria", "Inscrições ativas", "Inscrições canceladas", "Corridas concluídas", "Valeu o Boi", "Zero", "Retorno", "Rabo da Gata"].map((titulo) => <th key={titulo} scope="col" className="p-2">{titulo}</th>)}
            </tr></thead>
            <tbody>{categorias.map((categoria) => {
              const { inscricoes, resultados } = categoria;
              return <tr key={categoria.id} className="border-b border-stone-200 align-top">
                <th scope="row" className="p-2 font-semibold">{categoria.nome}</th>
                {[inscricoes?.ativas ?? 0, inscricoes?.canceladas ?? 0, resultados?.concluidas ?? 0, ...indicadores.map(({ id }) => resultados?.[id] ?? 0)].map((valor, index) => <td key={index} className="p-2">{valor}</td>)}
              </tr>;
            })}</tbody>
          </table>
        </div>
      </section>

      <section className={bloco} aria-labelledby="classificacao-oficial">
        <h2 id="classificacao-oficial" className="text-xl font-bold">{final ? "Classificação final" : "Classificação registrada"} por categoria</h2>
        <p className="mt-2 text-sm text-stone-600">A pontuação é somada por vaqueiro. Quando há mais de uma inscrição no total, senhas, cavalos e equipes aparecem na mesma ordem.</p>
        {classificatorias.map((categoria) => <section key={categoria.id} className="mt-4">
          <h3 className="mb-2 font-semibold print:break-after-avoid">{categoria.nome}</h3>
          <Classificacao itens={categoria.geral} />
        </section>)}
        <h3 className="mt-6 font-bold">Campeões de Tropa de Elite e X1</h3>
        {!chaves.length && <p className="mt-2 text-sm text-stone-600">Nenhum chaveamento registrado.</p>}
        <ul className="mt-2 divide-y divide-stone-200 text-sm">{chaves.map((chave) => (
          <li key={chave.id} className="py-2"><strong>{chave.modelo} · {chave.categoria}</strong> · {chave.campeao ?? "Campeão a definir"} · {rotulo(chave.estado)}</li>
        ))}</ul>
      </section>

      <section className={bloco} aria-labelledby="historico-rodizios">
        <h2 id="historico-rodizios" className="text-xl font-bold">Histórico de rodízios</h2>
        {!rodizios?.length && <p className="mt-2 text-sm text-stone-600">Nenhum rodízio iniciado.</p>}
        <ol className="mt-2 divide-y divide-stone-200 text-sm">{rodizios?.map((rodizio) => (
          <li key={rodizio.id} className="py-2 print:break-inside-avoid">
            <strong>{rodizio.categoria} · Rodízio {rodizio.numero}</strong> · {rotulo(rodizio.estado)}
            <p>Início {horarioEvento(rodizio.inicio)} · Encerramento {horarioEvento(rodizio.fim)}</p>
          </li>
        ))}</ol>
      </section>

      <section className={bloco} aria-labelledby="auditoria-boi-tv">
        <h2 id="auditoria-boi-tv" className="text-xl font-bold">Histórico de solicitações e decisões BOI TV</h2>
        {!revisoes?.length && <p className="mt-2 text-sm text-stone-600">Nenhuma solicitação registrada.</p>}
        <ol className="mt-2 divide-y divide-stone-200 text-sm">{revisoes?.map((revisao) => (
          <li key={revisao.id} className="space-y-1 py-3 print:break-inside-avoid">
            <h3 className="font-semibold">{revisao.categoria} · Senha {revisao.senha} · {rotulo(revisao.estado)}</h3>
            <p>{rotulo(revisao.tipo ?? "Revisão")} · Origem {rotulo(revisao.origem)}{revisao.reclamante !== null && ` · Senha reclamante ${revisao.reclamante}`}</p>
            <p>Solicitada por {revisao.solicitante} em {horarioEvento(revisao.solicitada)}</p>
            <p>Recebida por {revisao.recebida_por ?? "—"} em {horarioEvento(revisao.recebida)} · Analisada por {revisao.analista ?? "—"} em {horarioEvento(revisao.analisada)}</p>
            <p>Resultado inicial {rotulo(revisao.resultado_inicial)}{revisao.pontuacao_inicial !== null && ` · ${revisao.pontuacao_inicial} pontos`}</p>
            <p>Decisão {revisao.decisao ? rotulo(revisao.decisao) : "pendente"}{revisao.pontuacao_final !== null && ` · ${revisao.pontuacao_final} pontos`} · {revisao.juiz ?? "—"} · {horarioEvento(revisao.julgada)}</p>
            {revisao.justificativa && <p>Justificativa · {revisao.justificativa}</p>}
            {revisao.observacao && <p>Observação da equipe · {revisao.observacao}</p>}
            {revisao.atualizada && <p>Última atualização do atendimento · {horarioEvento(revisao.atualizada)}</p>}
          </li>
        ))}</ol>
      </section>
    </div>
  </main>;
}
