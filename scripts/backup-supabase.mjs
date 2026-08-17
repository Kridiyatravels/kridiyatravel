#!/usr/bin/env node

import { createCipheriv, createHash, randomBytes, scrypt as scryptCallback } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, rm, stat, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { promisify } from "node:util";
import { createGzip } from "node:zlib";
import { finished, pipeline } from "node:stream/promises";
import path from "node:path";

const scrypt = promisify(scryptCallback);
const MAGIC = Buffer.from("KRIDIYA-BACKUP-V1\n", "utf8");

function required(name) {
  const value = String(process.env[name] || "");
  if (!value.trim()) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit", shell: false, ...options });
    child.once("error", reject);
    child.once("exit", (code, signal) => code === 0 ? resolve() : reject(new Error(`${command} failed (${signal ? `signal ${signal}` : `exit ${code}`})`)));
  });
}

async function sha256(file) {
  const hash = createHash("sha256");
  await pipeline(createReadStream(file), hash);
  return hash.digest("hex");
}

async function encrypt(input, output, passphrase) {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const key = await scrypt(passphrase, salt, 32);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const destination = createWriteStream(output, { flags: "wx", mode: 0o600 });
  destination.write(MAGIC); destination.write(salt); destination.write(iv);
  await pipeline(createReadStream(input), cipher, destination, { end: false });
  destination.write(cipher.getAuthTag()); destination.end();
  await finished(destination);
}

const databaseUrl = required("DATABASE_URL");
const passphrase = required("BACKUP_ENCRYPTION_PASSPHRASE");
if (Buffer.byteLength(passphrase, "utf8") < 20) throw new Error("BACKUP_ENCRYPTION_PASSPHRASE must be at least 20 characters");

const outputDirectory = path.resolve(process.env.BACKUP_DIR || "backups");
await mkdir(outputDirectory, { recursive: true });
const stamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z").replaceAll(":", "-");
const plain = path.join(outputDirectory, `kridiya-production-${stamp}.sql`);
const compressed = `${plain}.gz`;
const encrypted = `${compressed}.enc`;
const manifestFile = `${encrypted}.manifest.json`;

try {
  console.log("Creating production logical backup, including Auth and operational records...");
  await run(process.env.PG_DUMP_BIN || "pg_dump", [
    "--format=plain", "--encoding=UTF8", "--clean", "--if-exists", "--no-owner", "--no-privileges",
    "--verbose", `--file=${plain}`, `--dbname=${databaseUrl}`,
    "--exclude-table=storage.buckets_vectors", "--exclude-table=storage.vector_indexes",
  ], { env: process.env });
  if ((await stat(plain)).size === 0) throw new Error("Database dump is empty");
  await pipeline(createReadStream(plain), createGzip({ level: 9 }), createWriteStream(compressed, { mode: 0o600 }));
  await encrypt(compressed, encrypted, passphrase);
  const manifest = {
    format: "kridiya-backup-manifest-v1", kind: "supabase-postgres-logical",
    created_at: new Date().toISOString(), encryption: "AES-256-GCM; scrypt KDF; header KRIDIYA-BACKUP-V1",
    file: path.basename(encrypted), bytes: (await stat(encrypted)).size, sha256: await sha256(encrypted),
    contains: ["database structure", "customers", "bookings", "payments", "auth users", "audit and operational records"],
  };
  await writeFile(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  const uploader = path.resolve(required("BACKUP_UPLOADER"));
  for (const file of [encrypted, manifestFile]) await run(process.execPath, [uploader, file], { env: process.env });
  console.log(`Encrypted database backup uploaded and verified by SHA-256: ${manifest.sha256}`);
} finally {
  await Promise.all([plain, compressed, encrypted, manifestFile].map((file) => rm(file, { force: true })));
}
