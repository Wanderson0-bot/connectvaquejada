import { redirect } from "next/navigation";

export default async function OperacaoAdminPage({ params, searchParams }: PageProps<"/painel/operacoes/[id]">) {
  const { id } = await params;
  const query = new URLSearchParams();
  for (const [chave, valor] of Object.entries(await searchParams)) {
    for (const item of Array.isArray(valor) ? valor : [valor]) {
      if (item !== undefined) query.append(chave, item);
    }
  }
  redirect(`/eventos/${encodeURIComponent(id)}/supervisao-equipe${query.size ? `?${query}` : ""}`);
}
