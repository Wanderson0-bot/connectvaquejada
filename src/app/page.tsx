"use client";

import { FormEvent, useState } from "react";
import Image from "next/image";
import { ArrowRight, Eye, EyeOff, LockKeyhole, Mail } from "lucide-react";
import { autenticar } from "@/app/auth/actions";

export default function Home() {
  const [erro, setErro] = useState("");
  const [carregando, setCarregando] = useState(false);
  const [mostrarSenha, setMostrarSenha] = useState(false);

  async function entrar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const dados = new FormData(event.currentTarget);
    setErro("");
    setCarregando(true);

    try {
      const resultado = await autenticar(dados);

      if (resultado.error) {
        setErro(resultado.error);
        return;
      }

      window.location.replace("/painel");
    } catch {
      setErro("Não foi possível conectar ao serviço de autenticação. Verifique sua conexão e tente novamente.");
    } finally {
      setCarregando(false);
    }
  }

  return (
    <main className="login-page">
      <svg className="login-art" viewBox="0 0 1440 900" preserveAspectRatio="none" aria-hidden="true">
        <path d="M0 0h288C228 100 149 126 0 169V0Z" fill="#f0a36a" />
        <path d="M286 0c-46 77-117 115-196 147C47 176 18 205 0 239V0h286Z" fill="#f8eee5" />
        <path d="M1366 112 1292 190l148 168v-31l-119-137 71-78-26 10Z" fill="#f4e2d5" />
        <path d="M1263 165c-75 18-128 83-128 157 0 91 74 164 165 164 26 0 51-6 73-17-66 15-137-2-183-48-49-49-64-121-38-184 22-34 60-62 111-72Z" fill="#f4e2d5" />
        <path d="M1354 209c27 12 53 37 72 63l14 18v-40l-15-17c-21-22-45-34-71-24Z" fill="#f4e2d5" />
        <path d="M1297 226c-16 33-16 60 3 77 16 15 36 8 55 11 27 4 50 29 72 47 10 8 20 8 30-1v-21c-9 8-17 7-26-1-23-21-46-48-77-53-22-4-43 4-56-8-14-13-14-31-1-51Z" fill="#f4e2d5" />
        <ellipse cx="1347" cy="255" rx="7" ry="11" transform="rotate(-35 1347 255)" fill="#f4e2d5" />
        <path d="M1440 667c-71 35-117 73-158 111-43 40-77 78-126 122h284V667Z" fill="#a84a0d" />
      </svg>
      <section className="auth-card" aria-labelledby="login-title">
      <form onSubmit={entrar} className="auth-form">
        <div className="auth-brand">
          <Image
            src="/logo-connect-vaquejada.png"
            alt="Connect Vaquejada"
            width={220}
            height={124}
            priority
            className="auth-logo"
          />
          <h1 id="login-title" className="auth-title">Entre na sua conta</h1>
          <p className="auth-description">Use sua conta para acessar o painel da vaquejada.</p>
        </div>

        <div className="auth-fields">
          <label className="auth-field">
            <span className="auth-label">Email</span>
            <div className="input-wrap">
            <Mail className="input-icon" size={18} />
            <input
              type="email"
              name="email"
              required
              autoComplete="username"
              placeholder="exemplo@dominio.com"
              className="auth-input"
            />
            </div>
          </label>

          <label className="auth-field">
            <span className="auth-label">Senha</span>
            <div className="input-wrap">
            <LockKeyhole className="input-icon" size={18} />
            <input
              type={mostrarSenha ? "text" : "password"}
              name="senha"
              required
              autoComplete="current-password"
              placeholder="Digite sua senha"
              className="auth-input"
            />
            <button type="button" aria-label={mostrarSenha ? "Ocultar senha" : "Mostrar senha"} className="password-toggle" onClick={() => setMostrarSenha(!mostrarSenha)}>
              {mostrarSenha ? <Eye size={18} /> : <EyeOff size={18} />}
            </button>
            </div>
          </label>
        </div>

        {erro && (
          <p role="alert" className="auth-error">
            {erro}
          </p>
        )}

        <button
          type="submit"
          disabled={carregando}
          className="auth-submit"
        >
          {carregando ? "Entrando..." : <>Entrar <ArrowRight size={19} strokeWidth={2.5} /></>}
        </button>
      </form>
      </section>
    </main>
  );
}
