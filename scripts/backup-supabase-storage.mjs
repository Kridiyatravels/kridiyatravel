#!/usr/bin/env node

import { createCipheriv, createHash, randomBytes, scrypt as scryptCallback } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, rm, stat, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { promisify } from "node:util";
import { finished, pipeline } from "node:stream/promises";
import path from "node:path";

const scrypt = promisify(scryptCallback);
const MAGIC = Buffer.from("KRIDIYA-BACKUP-V1\n", "utf8");
const required = (name) => {
  const value = String(process.env[name] || "");
  if (!value.trim()) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};
const safeParts = (value) => String(value).replaceAll("\\", "/").split("/").filter(Boolean).map((part) => {
  if (part === "." || part === "..") throw new Error("Unsafe Storage object path");
  return part;
});
const run = (command, args, options = {}) => new Promise((resolve, reject) => {
  const child = spawn(command, args, { stdio: "inherit", shell: false, ...options });
  child.once("error", reject);
  child.once("exit", (code, signal) => code === 0 ? resolve() : reject(new Error(`${command} failed (${signal ? `signal ${signal}` : `exit ${code}`})`)));
});

async function api(base, key, resource, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${key}`); headers.set("apikey", key);
  if (init.body) headers.set("Content-Type", "application/json");
  const response = await fetch(`${base}/storage/v1${resource}`, { ...init, headers });
  if (!response.ok) throw new Error(`Storage API ${resource} failed (${response.status}): ${(await response.text()).slice(0, 300)}`);
  return response;
}

async function listObjects(base, key, bucket, prefix = "") {
  const found = [];
  let offset = 0;
  while (true) {
    const page = await (await api(base, key, `/object/list/${encodeURIComponent(bucket)}`, {
      method: "POST", body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }),
    })).json();
    for (const item of page) {
      const name = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) found.push(...await listObjects(base, key, bucket, name)); else found.push(name);
    }
    if (page.length < 1000) break;
    offset += page.length;
  }
  return found;
}

async function sha256(file) {
  const hash = createHash("sha256");
  await pipeline(createReadStream(file), hash);
  return hash.digest("hex");
}

async function encrypt(input, output, passphrase) {
  const salt = randomBytes(16); const iv = randomBytes(12); const key = await scrypt(passphrase, salt, 32);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const destination = createWriteStream(output, { flags: "wx", mode: 0o600 });
  destination.write(MAGIC); destination.write(salt); destination.write(iv);
  await pipeline(createReadStream(input), cipher, destination, { end: false });
  destination.write(cipher.getAuthTag()); destination.end();
  await finished(destination);
}

const base = required("SUPABASE_URL").replace(/\/+$/, "");
const serviceKey = required("SUPABASE_SERVICE_ROLE_KEY");
const passphrase = required("BACKUP_ENCRYPTION_PASSPHRASE");
if (Buffer.byteLength(passphrase, "utf8") < 20) throw new Error("BACKUP_ENCRYPTION_PASSPHRASE must be at least 20 characters");
const root = path.resolve(process.env.BACKUP_DIR || "backups");
const work = path.join(root, `storage-work-${Date.now()}`);
const objectsRoot = path.join(work, "objects");
const stamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z").replaceAll(":", "-");
const archive = path.join(root, `kridiya-storage-${stamp}.tar.gz`);
const encrypted = `${archive}.enc`;
const manifestFile = `${encrypted}.manifest.json`;

try {
  await mkdir(objectsRoot, { recursive: true });
  const buckets = await (await api(base, serviceKey, "/bucket")).json();
  const inventory = []; let totalBytes = 0;
  for (const bucket of buckets) {
    for (const name of await listObjects(base, serviceKey, bucket.id)) {
      const target = path.join(objectsRoot, ...safeParts(bucket.id), ...safeParts(name));
      await mkdir(path.dirname(target), { recursive: true });
      const resource = `/object/${encodeURIComponent(bucket.id)}/${safeParts(name).map(encodeURIComponent).join("/")}`;
      const response = await api(base, serviceKey, resource);
      await pipeline(response.body, createWriteStream(target, { mode: 0o600 }));
      const bytes = (await stat(target)).size; totalBytes += bytes;
      inventory.push({ bucket: bucket.id, name, bytes, sha256: await sha256(target) });
    }
  }
  await writeFile(path.join(work, "inventory.json"), `${JSON.stringify({ created_at: new Date().toISOString(), objects: inventory }, null, 2)}\n`, { mode: 0o600 });
  await run("tar", ["-czf", archive, "-C", work, "."]);
  await encrypt(archive, encrypted, passphrase);
  const manifest = {
    format: "kridiya-backup-manifest-v1", kind: "supabase-storage-objects", created_at: new Date().toISOString(),
    encryption: "AES-256-GCM; scrypt KDF; header KRIDIYA-BACKUP-V1", file: path.basename(encrypted),
    bytes: (await stat(encrypted)).size, sha256: await sha256(encrypted), bucket_count: buckets.length,
    object_count: inventory.length, uncompressed_object_bytes: totalBytes,
  };
  await writeFile(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  const uploader = path.resolve(required("BACKUP_UPLOADER"));
  for (const file of [encrypted, manifestFile]) await run(process.execPath, [uploader, file], { env: process.env });
  console.log(`Encrypted Storage backup uploaded: ${inventory.length} objects across ${buckets.length} buckets.`);
} finally {
  await rm(work, { recursive: true, force: true });
  await Promise.all([archive, encrypted, manifestFile].map((file) => rm(file, { force: true })));
}
