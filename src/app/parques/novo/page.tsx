import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { criarParque } from "../actions";

export default async function NovoParquePage({ searchParams }: PageProps<"/parques/novo">) {
  const { erro } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  return <main className="mx-auto min-h-screen max-w-xl px-5 py-10">
    <Link href="/painel" className="text-sm text-gray-600 underline">Voltar ao painel</Link>
    <h1 className="mt-6 text-3xl font-bold">Cadastrar parque</h1>
    <p className="mt-2 text-gray-600">Informe o nome e a localização do parque.</p>
    {erro && <p role="alert" className="mt-5 rounded-lg bg-red-50 p-3 text-sm text-red-800">{erro === "campos" ? "Preencha o nome e a localização." : "Não foi possível cadastrar o parque. Confira os dados e tente novamente."}</p>}
    <form action={criarParque} className="mt-7 grid gap-5 rounded-2xl bg-white p-6 shadow-lg">
      <label className="grid gap-2 text-sm font-semibold">Nome do parque<input name="nome" required maxLength={120} className="rounded-lg border px-3 py-2.5 font-normal" placeholder="Ex.: Rancho do Vaqueiro" /></label>
      <label className="grid gap-2 text-sm font-semibold">Localização<input name="localizacao" required maxLength={180} className="rounded-lg border px-3 py-2.5 font-normal" placeholder="Cidade, Estado" /></label>
      <button className="rounded-lg bg-[#ff7a00] px-5 py-3 font-bold text-white">Criar parque</button>
    </form>
  </main>;
}
