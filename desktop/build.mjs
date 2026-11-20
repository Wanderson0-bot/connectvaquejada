import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL("../", import.meta.url));
const desktop = fileURLToPath(new URL("./", import.meta.url));

function run(args, cwd, env = process.env) {
  const result = spawnSync(process.execPath, args, { cwd, env, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

const builder = require.resolve("electron-builder/out/cli/cli.js");
run([require.resolve("next/dist/bin/next"), "build"], root, { ...process.env, CONNECT_DESKTOP_BUILD: "1" });
run(["desktop/stage.mjs"], root);
run([builder, "--win", "nsis", "--x64", "--publish", "never"], desktop);
