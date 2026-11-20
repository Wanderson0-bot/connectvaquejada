"use client";

import { useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { FileSpreadsheet, Upload } from "lucide-react";
import { importarInscricoesCsv, type ResultadoImportacaoCsv } from "./importar-csv-action";
import { validarCsvInscricoes, type CategoriaCsv, type LinhaCsv } from "./csv";
import styles from "./escritorio.module.css";

const estadoInicial: ResultadoImportacaoCsv = { tipo: "inicial", mensagem: "" };

function BotaoImportacao({ desabilitado }: { desabilitado: boolean }) {
  const { pending } = useFormStatus();

  return (
    <button type="submit" className={`${styles.button} ${styles.buttonReserve}`} disabled={desabilitado || pending}>
      <Upload aria-hidden="true" /> {pending ? "Importando..." : "Importar inscrições"}
    </button>
  );
}

export function ImportarInscricoesCsv({ eventoId, categorias }: { eventoId: string; categorias: CategoriaCsv[] }) {
  const [resultado, setResultado] = useState(estadoInicial);
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [linhas, setLinhas] = useState<LinhaCsv[]>([]);
  const [errosArquivo, setErrosArquivo] = useState<string[]>([]);
  const formRef = useRef<HTMLFormElement>(null);

  async function importar(formData: FormData) {
    const novoResultado = await importarInscricoesCsv(resultado, formData);
    setResultado(novoResultado);
    if (novoResultado.tipo === "sucesso") {
      formRef.current?.reset();
      setArquivo(null);
      setLinhas([]);
      setErrosArquivo([]);
    }
  }

  async function selecionarArquivo(file: File | undefined) {
    setArquivo(file ?? null);
    setLinhas([]);
    setErrosArquivo([]);
    if (!file) return;
    if (file.size === 0 || file.size > 500_000) {
      setErrosArquivo(["O arquivo deve ter conteúdo e não pode ultrapassar 500 KB."]);
      return;
    }

    const resultadoCsv = validarCsvInscricoes(await file.text(), categorias);
    setLinhas(resultadoCsv.linhas);
    setErrosArquivo([
      ...resultadoCsv.erros,
      ...resultadoCsv.linhas.flatMap((linha) => linha.erros.map((erro) => `Linha ${linha.linha}: ${erro}`)),
    ]);
  }

  const errosVisiveis = errosArquivo.slice(0, 10);

  return (
    <section className={`${styles.card} ${styles.csvCard}`} aria-labelledby="csv-title">
      <div className={styles.sectionHeading}>
        <FileSpreadsheet className={styles.headingIcon} aria-hidden="true" />
        <h2 id="csv-title">Importar inscrições por CSV</h2>
        <span className={styles.headingRule} />
      </div>
      <p className={styles.csvHelp}>
        Use as colunas <code>senha,nome,categoria,equipe,cavalo</code>. Também são aceitos “Nome da Equipe” e “Nome do Cavalo”. Equipe e cavalo são opcionais;
        a categoria deve corresponder a uma categoria ativa. Aceita separador vírgula ou ponto e vírgula,
        até 1.000 inscrições e 500 KB. Todas serão reservadas como pendentes.
      </p>

      <form ref={formRef} action={importar} className={styles.csvForm}>
        <input type="hidden" name="evento_id" value={eventoId} />
        <label className={styles.csvField}>
          <span className={styles.label}>Arquivo CSV</span>
          <input
            className={styles.csvInput}
            type="file"
            name="arquivo_csv"
            accept=".csv,text/csv"
            required
            onChange={(event) => void selecionarArquivo(event.currentTarget.files?.[0])}
          />
        </label>

        {linhas.length > 0 && (
          <div className={styles.csvPreview}>
            <p className={styles.csvPreviewTitle}>Prévia: {linhas.length} linha(s) · {linhas.filter((linha) => !linha.erros.length).length} válida(s)</p>
            <div className="overflow-x-auto">
              <table className={styles.csvTable}>
                <thead><tr><th>Linha</th><th>Senha</th><th>Vaqueiro</th><th>Categoria</th><th>Equipe</th><th>Cavalo</th></tr></thead>
                <tbody>
                  {linhas.slice(0, 5).map((linha) => (
                    <tr key={linha.linha} aria-invalid={linha.erros.length > 0}>
                      <td>{linha.linha}</td><td>{linha.senha}</td><td>{linha.nome}</td><td>{linha.categoria}</td><td>{linha.equipe || "—"}</td><td>{linha.cavalo || "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {linhas.length > 5 && <p className={styles.csvHelp}>Exibindo as primeiras 5 linhas.</p>}
          </div>
        )}

        {errosVisiveis.length > 0 && (
          <div role="alert" className={styles.csvErrors}>
            <p>Corrija o arquivo antes de importar:</p>
            <ul>{errosVisiveis.map((erro, indice) => <li key={`${indice}-${erro}`}>{erro}</li>)}</ul>
            {errosArquivo.length > errosVisiveis.length && <p>Mais {errosArquivo.length - errosVisiveis.length} problema(s).</p>}
          </div>
        )}

        {resultado.tipo !== "inicial" && (
          <p role={resultado.tipo === "erro" ? "alert" : "status"} className={resultado.tipo === "erro" ? styles.csvErrors : styles.csvSuccess}>
            {resultado.mensagem}
            {resultado.erros && <ul>{resultado.erros.map((erro, indice) => <li key={`${indice}-${erro}`}>{erro}</li>)}</ul>}
          </p>
        )}

        <BotaoImportacao desabilitado={!arquivo || errosArquivo.length > 0} />
      </form>
    </section>
  );
}
