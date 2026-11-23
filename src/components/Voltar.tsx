import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export function Voltar({ href = "/painel" }: { href?: string }) {
  return (
    <Link
      href={href}
      className="mb-3 inline-flex min-h-11 w-fit items-center gap-2 rounded-lg border border-stone-300 bg-white px-3 text-sm font-semibold text-stone-800 hover:border-orange-500 hover:text-orange-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700"
    >
      <ArrowLeft className="size-4" aria-hidden="true" />
      Voltar
    </Link>
  );
}
