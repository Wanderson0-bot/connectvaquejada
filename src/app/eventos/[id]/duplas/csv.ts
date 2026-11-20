export type CategoriaCsv = { id: string; nome: string };
export type LinhaCsv = {
  linha: number;
  senha: string;
  nome: string;
  categoria: string;
  equipe: string;
  cavalo: string;
  erros: string[];
};
export type InscricaoCsv = {
  numero_senha: number;
  nome: string;
  categoria_id: string;
  nome_equipe: string;
  nome_cavalo: string;
};

function contarDelimitadores(linha: string) {
  let emAspas = false;
  let virgulas = 0;
  let pontoEVirgulas = 0;

  for (let indice = 0; indice < linha.length; indice += 1) {
    if (linha[indice] === '"') {
      if (emAspas && linha[indice + 1] === '"') {
        indice += 1;
      } else {
        emAspas = !emAspas;
      }
    } else if (!emAspas && linha[indice] === ",") {
      virgulas += 1;
    } else if (!emAspas && linha[indice] === ";") {
      pontoEVirgulas += 1;
    }
  }

  return pontoEVirgulas > virgulas ? ";" : ",";
}

function lerRegistros(conteudo: string, delimitador: string) {
  const registros: { valores: string[]; linha: number }[] = [];
  let valores: string[] = [];
  let valor = "";
  let emAspas = false;
  let depoisDasAspas = false;
  let linha = 1;
  let inicioRegistro = 1;
  let erroAspas = false;

  function terminarValor() {
    valores.push(valor);
    valor = "";
    depoisDasAspas = false;
  }

  function terminarRegistro() {
    terminarValor();
    if (valores.some((item) => item.trim())) {
      registros.push({ valores, linha: inicioRegistro });
    }
    valores = [];
    inicioRegistro = linha + 1;
  }

  for (let indice = 0; indice < conteudo.length; indice += 1) {
    const caractere = conteudo[indice];

    if (emAspas) {
      if (caractere === '"' && conteudo[indice + 1] === '"') {
        valor += '"';
        indice += 1;
      } else if (caractere === '"') {
        emAspas = false;
        depoisDasAspas = true;
      } else {
        valor += caractere;
        if (caractere === "\n") linha += 1;
      }
      continue;
    }

    if (depoisDasAspas && caractere !== delimitador && caractere !== "\r" && caractere !== "\n" && !/\s/.test(caractere)) {
      erroAspas = true;
    }

    if (caractere === '"' && !valor.length && !depoisDasAspas) {
      emAspas = true;
    } else if (caractere === delimitador) {
      terminarValor();
    } else if (caractere === "\n" || caractere === "\r") {
      if (caractere === "\r" && conteudo[indice + 1] === "\n") indice += 1;
      terminarRegistro();
      linha += 1;
      inicioRegistro = linha;
    } else if (!depoisDasAspas) {
      if (caractere === '"') erroAspas = true;
      valor += caractere;
    }
  }

  if (emAspas) erroAspas = true;
  if (valor.length || valores.length) terminarRegistro();

  return { registros, erroAspas };
}

function normalizarCabecalho(valor: string) {
  return valor.trim().toLocaleLowerCase("pt-BR").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[\s-]+/g, "_");
}

function normalizarNome(valor: string) {
  return valor.trim().toLocaleLowerCase("pt-BR").normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

export function validarCsvInscricoes(conteudo: string, categorias: CategoriaCsv[]) {
  const primeiraLinha = conteudo.replace(/^\uFEFF/, "").split(/\r?\n/, 1)[0] ?? "";
  const delimitador = contarDelimitadores(primeiraLinha);
  const { registros, erroAspas } = lerRegistros(conteudo.replace(/^\uFEFF/, ""), delimitador);
  const erros: string[] = [];

  if (erroAspas) erros.push("O CSV contém aspas inválidas ou não fechadas.");
  if (!registros.length) return { linhas: [] as LinhaCsv[], inscricoes: [] as InscricaoCsv[], erros: [...erros, "O arquivo não contém cabeçalho nem inscrições."] };

  const cabecalhos = registros[0].valores.map(normalizarCabecalho);
  const indiceCabecalho = {
    senha: cabecalhos.findIndex((valor) => ["senha", "numero_senha"].includes(valor)),
    nome: cabecalhos.findIndex((valor) => ["nome", "vaqueiro", "nome_do_vaqueiro"].includes(valor)),
    categoria: cabecalhos.findIndex((valor) => valor === "categoria"),
    equipe: cabecalhos.findIndex((valor) => ["equipe", "nome_equipe", "nome_da_equipe"].includes(valor)),
    cavalo: cabecalhos.findIndex((valor) => ["cavalo", "nome_cavalo", "nome_do_cavalo"].includes(valor)),
  };

  for (const campo of ["senha", "nome", "categoria"] as const) {
    if (indiceCabecalho[campo] < 0) erros.push(`Cabeçalho obrigatório ausente: ${campo}.`);
  }
  if (new Set(cabecalhos).size !== cabecalhos.length) erros.push("O arquivo contém cabeçalhos duplicados.");
  if (registros.length - 1 > 1000) erros.push("O limite por arquivo é de 1.000 inscrições.");

  const categoriasPorNome = new Map(categorias.map((categoria) => [normalizarNome(categoria.nome), categoria]));
  const linhas: LinhaCsv[] = registros.slice(1).map(({ valores, linha }) => {
    const ler = (campo: keyof typeof indiceCabecalho) => indiceCabecalho[campo] < 0 ? "" : (valores[indiceCabecalho[campo]] ?? "").trim();
    const item: LinhaCsv = {
      linha,
      senha: ler("senha"),
      nome: ler("nome"),
      categoria: ler("categoria"),
      equipe: ler("equipe"),
      cavalo: ler("cavalo"),
      erros: [],
    };

    if (!item.senha || !/^\d+$/.test(item.senha) || !Number.isSafeInteger(Number(item.senha)) || Number(item.senha) < 1 || Number(item.senha) > 2147483647) {
      item.erros.push("senha deve ser um número inteiro positivo.");
    }
    if (!item.nome || item.nome.length > 120) item.erros.push("nome é obrigatório e deve ter até 120 caracteres.");
    if (!item.categoria || !categoriasPorNome.has(normalizarNome(item.categoria))) item.erros.push("categoria não corresponde a uma categoria ativa.");
    if (item.equipe.length > 120) item.erros.push("equipe deve ter até 120 caracteres.");
    if (item.cavalo.length > 120) item.erros.push("cavalo deve ter até 120 caracteres.");
    return item;
  });

  const senhas = new Set<string>();
  const inscricoes: InscricaoCsv[] = [];
  for (const item of linhas) {
    const categoria = categoriasPorNome.get(normalizarNome(item.categoria));
    if (!item.erros.length && categoria) {
      const chave = `${categoria.id}:${item.senha}`;
      if (senhas.has(chave)) {
        item.erros.push("senha duplicada nesta categoria no próprio arquivo.");
      } else {
        senhas.add(chave);
        inscricoes.push({
          numero_senha: Number(item.senha),
          nome: item.nome,
          categoria_id: categoria.id,
          nome_equipe: item.equipe,
          nome_cavalo: item.cavalo,
        });
      }
    }
  }

  return { linhas, inscricoes, erros };
}
