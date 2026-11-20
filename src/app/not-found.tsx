import Link from "next/link";

export default function PaginaNaoEncontrada() {
  return (
    <main className="mx-auto grid min-h-svh max-w-lg content-center gap-4 px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Página não encontrada</h1>
      <p className="text-stone-600">Verifique o endereço ou volte para a página inicial.</p>
      <Link href="/" className="operation-primary justify-self-start">Voltar ao início</Link>
    </main>
  );
}
