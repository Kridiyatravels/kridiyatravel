#!/usr/bin/env node

import { mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

function requiredConnection() {
  if (process.env.DATABASE_URL) return { url: process.env.DATABASE_URL, env: process.env };

  const required = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"];
  const missing = required.filter((name) => !process.env[name]);
  if (missing.length) {
    throw new Error(`Set DATABASE_URL or all PostgreSQL variables. Missing: ${missing.join(", ")}`);
  }
  return { url: undefined, env: process.env };
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit", shell: false, ...options });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} failed (${signal ? `signal ${signal}` : `exit ${code}`})`));
    });
  });
}

function timestamp() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z").replaceAll(":", "-");
}

const { url, env } = requiredConnection();
const outputDirectory = path.resolve(process.env.BACKUP_DIR || "backups");
await mkdir(outputDirectory, { recursive: true });

const outputFile = path.join(outputDirectory, `supabase-${timestamp()}.sql`);
const args = [
  "--format=plain",
  "--encoding=UTF8",
  "--clean",
  "--if-exists",
  "--no-owner",
  "--no-privileges",
  "--verbose",
  `--file=${outputFile}`,
];
if (url) args.push(`--dbname=${url}`);

console.log(`Creating logical backup: ${outputFile}`);
await run(process.env.PG_DUMP_BIN || "pg_dump", args, { env });
console.log(`Backup completed: ${outputFile}`);

// The destination-specific uploader is intentionally a separate executable.
// This keeps credentials out of process arguments and lets the same dump logic
// work with SharePoint/Graph or an independent cloud bucket.
if (process.env.BACKUP_UPLOADER) {
  console.log("Uploading backup to the configured off-site destination...");
  const uploader = path.resolve(process.env.BACKUP_UPLOADER);
  const uploaderCommand = /\.(?:mjs|js|cjs)$/i.test(uploader) ? process.execPath : uploader;
  const uploaderArgs = uploaderCommand === process.execPath ? [uploader, outputFile] : [outputFile];
  await run(uploaderCommand, uploaderArgs, { env });
  console.log("Off-site upload completed.");
} else {
  console.log("BACKUP_UPLOADER is not set; the dump remains local and has not been uploaded.");
}
