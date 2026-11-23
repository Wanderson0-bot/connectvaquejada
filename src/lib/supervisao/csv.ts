import { indicadores, percentual, resumo, statusEvento, totalOcorrencias, type DadosEvento, type Resultados } from "./modelo";

type Celula = string | number | null;
type Linha = Record<string, Celula>;

function codificarCelula(valor: Celula) {
  const texto = typeof valor === "number" ? String(valor).replace(".", ",") : (valor ?? "");
  // Treat names and notes as literal text in spreadsheet applications.
  const literal = typeof valor === "string" && /^[\s\uFEFF]*[=+\-@\t\r\n]/u.test(texto) ? `'${texto}` : texto;
  return `"${literal.replaceAll('"', '""')}"`;
}

function resultados(dados: Resultados) {
  const total = totalOcorrencias(dados);
  return Object.fromEntries(indicadores.flatMap(({ id, nome }) => [
    [nome, dados[id]], [`${nome} (%)`, percentual(dados[id], total).toFixed(2).replace(".", ",")],
  ]));
}

export function gerarCsvOperacional(dados: DadosEvento) {
  const { evento, categorias, chaves, rodizios, revisoes } = dados;
  const total = resumo(categorias);
  const linhas: Linha[] = [{
    Seção: "Resumo geral", Evento: evento.nome, Parque: evento.parque, Data: evento.data,
    Estado: statusEvento[evento.status], "Emitido em": dados.gerado_em,
    "Inscrições ativas": total.ativas, "Inscrições canceladas": total.canceladas,
    "Corridas concluídas": total.concluidas, ...resultados(total),
  }];
  for (const categoria of categorias) {
    const resumoCategoria = resumo([categoria]);
    linhas.push({
      Seção: "Resumo por categoria", Categoria: categoria.nome,
      "Inscrições ativas": resumoCategoria.ativas, "Inscrições canceladas": resumoCategoria.canceladas,
      "Corridas concluídas": resumoCategoria.concluidas,
      ...resultados(resumoCategoria),
    });
    for (const item of categoria.geral) linhas.push({
      Seção: "Classificação", Categoria: categoria.nome, Posição: item.posicao,
      Senha: item.inscricoes.map(({ senha }) => senha).join(", "),
      Vaqueiro: item.vaqueiro,
      Cavalo: item.inscricoes.map(({ cavalo }) => cavalo ?? "—").join(" / "),
      Equipe: item.inscricoes.map(({ equipe }) => equipe ?? "—").join(" / "), Pontos: item.pontos,
    });
  }
  for (const chave of chaves) linhas.push({
    Seção: "Chaveamento", Categoria: chave.categoria, Modelo: chave.modelo, Estado: chave.estado, Campeão: chave.campeao,
  });
  for (const rodizio of rodizios ?? []) linhas.push({
    Seção: "Rodízio", Categoria: rodizio.categoria, Rodízio: rodizio.numero, Estado: rodizio.estado,
    Início: rodizio.inicio, Encerramento: rodizio.fim,
  });
  for (const revisao of revisoes ?? []) linhas.push({
    Seção: "BOI TV", Categoria: revisao.categoria, Senha: revisao.senha, "Senha reclamante": revisao.reclamante,
    Fluxo: revisao.fluxo, Origem: revisao.origem, "Tipo de solicitação": revisao.tipo, Estado: revisao.estado,
    "Resultado inicial": revisao.resultado_inicial, "Pontos iniciais": revisao.pontuacao_inicial,
    Decisão: revisao.decisao, "Pontos finais": revisao.pontuacao_final,
    "Solicitada em": revisao.solicitada, Solicitante: revisao.solicitante,
    "Recebida em": revisao.recebida, "Recebida por": revisao.recebida_por,
    "Analisada em": revisao.analisada, Analista: revisao.analista, "Atualizada em": revisao.atualizada,
    "Julgada em": revisao.julgada, "Responsável pela decisão": revisao.juiz,
    Justificativa: revisao.justificativa, Observação: revisao.observacao,
  });

  const colunas = Array.from(new Set(linhas.flatMap((linha) => Object.keys(linha))));
  return "\uFEFF" + [
    colunas.map(codificarCelula).join(";"),
    ...linhas.map((linha) => colunas.map((coluna) => codificarCelula(linha[coluna] ?? null)).join(";")),
  ].join("\r\n");
}
