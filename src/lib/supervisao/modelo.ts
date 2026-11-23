export type Evento = {
  id: string;
  nome: string;
  parque: string | null;
  data: string;
  status: "agendado" | "em_andamento" | "pausado" | "concluido" | "cancelado";
};

export type Classificado = {
  id: string;
  posicao: number;
  vaqueiro: string;
  pontos: number;
  inscricoes: { senha: number; cavalo: string | null; equipe: string | null }[];
};

export type Resultados = { concluidas: number; valeu_boi: number; zero: number; retorno: number; rabo_da_gata: number };
export type Categoria = {
  id: string;
  nome: string;
  modelo: "classificatoria" | "eliminatoria";
  geral: Classificado[];
  parcial: Classificado[];
  inscricoes: { ativas: number; canceladas: number } | null;
  resultados: Resultados | null;
};

export type Chave = {
  id: string;
  categoria_id: string;
  categoria: string;
  modelo: "Tropa de Elite" | "X1";
  estado: string;
  campeao: string | null;
  confrontos: {
    id: string;
    fase: number;
    posicao: number;
    estado: string;
    lado_a: string | null;
    lado_b: string | null;
    vencedor: string | null;
  }[];
};

export type Revisao = {
  id: string;
  categoria: string;
  fluxo: string;
  origem: string;
  tipo: string | null;
  senha: number;
  reclamante: number | null;
  estado: string;
  resultado_inicial: string;
  pontuacao_inicial: number | null;
  decisao: string | null;
  pontuacao_final: number | null;
  justificativa: string | null;
  solicitada: string;
  solicitante: string;
  recebida: string | null;
  recebida_por: string | null;
  analisada: string | null;
  analista: string | null;
  atualizada: string | null;
  observacao: string | null;
  julgada: string | null;
  juiz: string | null;
};

type Funcao = "organizador" | "escritorio" | "locutor" | "boi_tv";
export type DadosEvento = {
  evento: Evento;
  gerado_em: string;
  categorias: Categoria[];
  chaves: Chave[];
  equipe: { id: string; nome: string; funcao: Funcao }[] | null;
  dispositivos: {
    id: string;
    nome: string;
    funcao: Funcao;
    estado: "ativo" | "bloqueado";
    operador: string | null;
    ultimo_acesso: string | null;
  }[] | null;
  rodizio: { id: string; numero: number; senha_atual: number | null; corridas: number; restantes: number } | null;
  rodizios: { id: string; categoria: string; numero: number; estado: string; inicio: string; fim: string | null }[] | null;
  boi_tv: {
    nova: number;
    recebida: number;
    em_analise: number;
    analise_concluida: number;
    aguardando_decisao: number;
    finalizada: number;
  };
  revisoes: Revisao[] | null;
};

export const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const statusEvento: Record<Evento["status"], string> = {
  agendado: "Agendado", em_andamento: "Em andamento", pausado: "Pausado",
  concluido: "Concluído", cancelado: "Anulado",
};

export const funcoes: Record<Funcao, string> = {
  organizador: "Organização", escritorio: "Escritório", locutor: "Locução", boi_tv: "BOI TV",
};

export const horario = new Intl.DateTimeFormat("pt-BR", {
  dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo",
});
export const horarioEvento = (valor: string | null) => valor ? horario.format(new Date(valor)) : "—";
export const rotulo = (valor: string) => valor.replaceAll("_", " ");

export function resumo(categorias: Categoria[]) {
  return categorias.reduce((total, { inscricoes, resultados }) => ({
    ativas: total.ativas + (inscricoes?.ativas ?? 0),
    canceladas: total.canceladas + (inscricoes?.canceladas ?? 0),
    concluidas: total.concluidas + (resultados?.concluidas ?? 0),
    valeu_boi: total.valeu_boi + (resultados?.valeu_boi ?? 0),
    zero: total.zero + (resultados?.zero ?? 0),
    retorno: total.retorno + (resultados?.retorno ?? 0),
    rabo_da_gata: total.rabo_da_gata + (resultados?.rabo_da_gata ?? 0),
  }), { ativas: 0, canceladas: 0, concluidas: 0, valeu_boi: 0, zero: 0, retorno: 0, rabo_da_gata: 0 });
}

export const indicadores = [
  { id: "valeu_boi", nome: "Valeu o Boi" },
  { id: "zero", nome: "Zero" },
  { id: "retorno", nome: "Retorno" },
  { id: "rabo_da_gata", nome: "Rabo da Gata" },
] as const;

export const totalOcorrencias = (dados: Resultados) => indicadores.reduce((total, { id }) => total + dados[id], 0);
export const percentual = (numero: number, total: number) => total ? numero * 100 / total : 0;
