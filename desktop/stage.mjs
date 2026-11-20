import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import nextEnv from "@next/env";
import sharp from "sharp";

nextEnv.loadEnvConfig(process.cwd());

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const activationOrigin = process.env.DESKTOP_ACTIVATION_ORIGIN;
if (!supabaseUrl || !supabaseKey) throw new Error("Configure as variáveis públicas do Supabase.");
if (new URL(supabaseUrl).protocol !== "https:") throw new Error("Use HTTPS no endereço do Supabase.");
const publicKey = supabaseKey.startsWith("sb_publishable_") ||
  (supabaseKey.split(".").length === 3 &&
    JSON.parse(Buffer.from(supabaseKey.split(".")[1], "base64url").toString("utf8")).role === "anon");
if (!publicKey) throw new Error("Use somente a chave pública do Supabase no instalador.");
if (activationOrigin && new URL(activationOrigin).protocol !== "https:") {
  throw new Error("Use HTTPS em DESKTOP_ACTIVATION_ORIGIN.");
}

const target = ".next/desktop-server";
rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
cpSync(".next/standalone", target, {
  recursive: true,
  dereference: true,
  filter: (source) => !basename(source).startsWith(".env"),
});
cpSync(".next/static", resolve(target, ".next/static"), { recursive: true });
cpSync("public", resolve(target, "public"), { recursive: true });
await sharp("public/logo-connect-vaquejada.png")
  .resize(224, 224, { fit: "contain", background: "#fff" })
  .extend({ top: 16, bottom: 16, left: 16, right: 16, background: "#fff" })
  .png()
  .toFile(".next/desktop-icon.png");
writeFileSync(resolve(target, "desktop-settings.json"), JSON.stringify({
  NEXT_PUBLIC_SUPABASE_URL: supabaseUrl,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: supabaseKey,
  DEVICE_ACTIVATION_ORIGIN: activationOrigin ?? "",
  DEVICE_ACTIVATION_TTL_MINUTES: process.env.DEVICE_ACTIVATION_TTL_MINUTES ?? "10",
}), "utf8");
