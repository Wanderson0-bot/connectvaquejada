import { redirect } from "next/navigation";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ erro?: string; sucesso?: string }>;
};

export default async function NovaDuplaPage({ params, searchParams }: Props) {
  const { id } = await params;
  const { erro, sucesso } = await searchParams;
  const query = new URLSearchParams();
  if (erro) query.set("erro", erro);
  if (sucesso) query.set("sucesso", sucesso);
  const queryString = query.toString();
  const suffix = queryString ? `?${queryString}` : "";
  redirect(`/eventos/${encodeURIComponent(id)}/duplas${suffix}`);
}
