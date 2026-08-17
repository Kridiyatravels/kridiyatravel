#!/usr/bin/env node

import { createDecipheriv, scrypt as scryptCallback } from "node:crypto";
import { open, rm, stat } from "node:fs/promises";
import { createReadStream, createWriteStream } from "node:fs";
import { promisify } from "node:util";
import { pipeline } from "node:stream/promises";
import path from "node:path";

const scrypt = promisify(scryptCallback);
const MAGIC = Buffer.from("KRIDIYA-BACKUP-V1\n", "utf8");
const input = process.argv[2] ? path.resolve(process.argv[2]) : "";
const output = process.argv[3] ? path.resolve(process.argv[3]) : "";
const passphrase = String(process.env.BACKUP_ENCRYPTION_PASSPHRASE || "");
if (!input || !output) throw new Error("Usage: decrypt-backup.mjs <archive.enc> <output-file>");
if (!passphrase) throw new Error("Set BACKUP_ENCRYPTION_PASSPHRASE in the environment");

const size = (await stat(input)).size;
const headerLength = MAGIC.length + 16 + 12;
if (size <= headerLength + 16) throw new Error("Encrypted backup is too short");
const file = await open(input, "r");
try {
  const header = Buffer.alloc(headerLength);
  await file.read(header, 0, header.length, 0);
  if (!header.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error("Unsupported backup format");
  const salt = header.subarray(MAGIC.length, MAGIC.length + 16);
  const iv = header.subarray(MAGIC.length + 16, headerLength);
  const tag = Buffer.alloc(16);
  await file.read(tag, 0, tag.length, size - tag.length);
  const decipher = createDecipheriv("aes-256-gcm", await scrypt(passphrase, salt, 32), iv);
  decipher.setAuthTag(tag);
  try {
    await pipeline(
      createReadStream(input, { start: headerLength, end: size - tag.length - 1 }),
      decipher,
      createWriteStream(output, { flags: "wx", mode: 0o600 }),
    );
  } catch (error) {
    await rm(output, { force: true });
    throw error;
  }
  console.log(`Decrypted backup written to ${output}`);
} finally {
  await file.close();
}
