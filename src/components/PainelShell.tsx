import Link from "next/link";
import Image from "next/image";
import { LayoutDashboard, LogOut, Smartphone, Swords, Tv } from "lucide-react";
import type { ReactNode } from "react";
import { sair } from "@/app/auth/actions";

export function PainelShell({ children, active }: { children: ReactNode; active: "painel" | "dispositivos" | "x1" }) {
  return (
    <div className="dashboard-shell">
      <aside className="dashboard-sidebar">
        <Link href="/painel" className="dashboard-brand" aria-label="Connect Vaquejada, Painel">
          <Image src="/logo-connect-vaquejada-branco.png" alt="Connect Vaquejada" width={150} height={100} priority className="dashboard-logo" />
        </Link>
        <nav className="dashboard-navigation" aria-label="Navegação principal">
          <Link href="/painel" className="dashboard-navigation-link" aria-current={active === "painel" ? "page" : undefined}>
            <LayoutDashboard className="size-4" aria-hidden="true" /> Operações
          </Link>
          <Link href="/painel/x1" className="dashboard-navigation-link" aria-current={active === "x1" ? "page" : undefined}>
            <Swords className="size-4" aria-hidden="true" /> X1
          </Link>
          <Link href="/painel/dispositivos" className="dashboard-navigation-link" aria-current={active === "dispositivos" ? "page" : undefined}>
            <Smartphone className="size-4" aria-hidden="true" /> Dispositivos
          </Link>
          <Link href="/boi-tv" className="dashboard-navigation-link">
            <Tv className="size-4" aria-hidden="true" /> BOI TV
          </Link>
        </nav>
        <form action={sair} className="dashboard-logout-form">
          <button className="dashboard-logout"><LogOut className="size-4" aria-hidden="true" /> Sair</button>
        </form>
      </aside>
      <main className="dashboard-content">{children}</main>
    </div>
  );
}
