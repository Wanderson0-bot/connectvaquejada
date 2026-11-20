import type { NextConfig } from "next";

const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (supabaseKey) {
  const [header, payload, signature] = supabaseKey.split(".");
  const role = header && payload && signature
    ? JSON.parse(Buffer.from(payload, "base64url").toString("utf8")).role
    : undefined;
  if (!supabaseKey.startsWith("sb_publishable_") && role !== "anon") {
    throw new Error("NEXT_PUBLIC_SUPABASE_ANON_KEY deve usar uma chave pública do Supabase.");
  }
}

const nextConfig: NextConfig = {
  ...(process.env.CONNECT_DESKTOP_BUILD === "1" ? { output: "standalone" } : {}),
  /* config options here */
  allowedDevOrigins: ["10.0.0.190"],
  logging: {
    serverFunctions: false,
  },
  experimental: {
    serverActions: {
      allowedOrigins: ["10.0.0.190:3000"],
    },
  },
  cacheComponents: false,
};

export default nextConfig;
