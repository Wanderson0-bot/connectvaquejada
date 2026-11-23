import type { Classificado } from "@/lib/supervisao/modelo";

export function Classificacao({ itens }: { itens: Classificado[] }) {
  if (!itens.length) return <p className="py-3 text-sm text-stone-600">Nenhum resultado registrado.</p>;

  return <div className="overflow-x-auto print:overflow-visible">
    <table className="w-full border-collapse text-left text-sm">
      <thead className="bg-stone-100"><tr>
        {["Posição", "Senha", "Vaqueiro", "Cavalo", "Equipe", "Pontos"].map((titulo) => (
          <th key={titulo} scope="col" className="p-2">{titulo}</th>
        ))}
      </tr></thead>
      <tbody>{itens.map((item) => <tr key={item.id} className="border-b border-stone-200 align-top">
        <td className="p-2 font-semibold">{item.posicao}º</td>
        <td className="p-2">{item.inscricoes.map((inscricao) => inscricao.senha).join(", ")}</td>
        <td className="p-2">{item.vaqueiro}</td>
        <td className="p-2">{item.inscricoes.map(({ cavalo }) => cavalo ?? "—").join(" / ")}</td>
        <td className="p-2">{item.inscricoes.map(({ equipe }) => equipe ?? "—").join(" / ")}</td>
        <td className="p-2 font-semibold tabular-nums">{item.pontos.toLocaleString("pt-BR")}</td>
      </tr>)}</tbody>
    </table>
  </div>;
}
