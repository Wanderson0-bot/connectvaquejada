import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Item = { id: string; senha: number; descricao: string; ocorrido_em: string };

export default async function Historico({ params, searchParams }: PageProps<"/eventos/[id]/historico">) {
  const { id } = await params;
  const { area: areaSolicitada } = await searchParams;
  const area = areaSolicitada === "escritorio" ? "escritorio" : "locutor";
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: evento } = await supabase.from("eventos").select("nome").eq("id", id).maybeSingle();
  if (!evento) notFound();
  const { data, error } = await supabase.rpc("pista_ops_historico_operacional", { p_evento_id: id, p_area: area });
  const items = (data ?? []) as Item[];
  const destination = area === "escritorio" ? "duplas" : "pista-ops";
  const format = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" });

  return <main className="mx-auto w-full max-w-3xl px-4 py-6 sm:px-8">
    <Link href={`/eventos/${id}/${destination}`} className="inline-flex min-h-11 items-center font-semibold underline">Voltar à operação</Link>
    <h1 className="mt-3 text-2xl font-bold">Histórico {area === "escritorio" ? "de inscrições" : "de resultados"}</h1>
    <p className="mb-5 text-stone-600">{evento.nome}</p>
    {error && <p role="alert" className="rounded-lg bg-red-50 p-4 text-red-900">Não foi possível abrir o histórico. Confira sua conexão e seu acesso ao evento.</p>}
    {!error && (items.length === 0 ? <p>Nenhum registro nesta área.</p> : <ul className="divide-y rounded-xl border">
      {items.map((item) => <li key={item.id} className="p-4">
        <p><strong>Senha {item.senha}</strong> · {item.descricao}</p>
        <time dateTime={item.ocorrido_em} className="text-sm text-stone-600">{format.format(new Date(item.ocorrido_em))}</time>
      </li>)}
    </ul>)}
  </main>;
}
