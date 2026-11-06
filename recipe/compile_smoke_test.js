// Program for the `bun build --compile` test in recipe.yaml.
//
// Compiled into a standalone executable, it uses two of the libraries bun
// links from conda-forge, zlib and sqlite, and prints its arguments. It fails
// when it is not running as a compiled executable.

import { Database } from "bun:sqlite";

const greeting = "hello from a compiled executable";

if (!Bun.isStandaloneExecutable) {
  console.error("not running as a compiled executable");
  process.exit(1);
}

const roundTrip = new TextDecoder().decode(Bun.gunzipSync(Bun.gzipSync(greeting)));
const { sum } = new Database(":memory:").query("select 1 + 1 as sum").get();
if (roundTrip !== greeting || sum !== 2) {
  console.error(`unexpected results: gzip round trip "${roundTrip}", sqlite 1 + 1 = ${sum}`);
  process.exit(1);
}

console.log(`${greeting}, called with: ${process.argv.slice(2).join(" ")}`);
