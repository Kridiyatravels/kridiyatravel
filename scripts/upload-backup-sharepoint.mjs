#!/usr/bin/env node

import { open } from "node:fs/promises";
import path from "node:path";

function required(name) {
  const value = String(process.env[name] || "").trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function encodedPath(value) {
  return value.split("/").filter(Boolean).map(encodeURIComponent).join("/");
}

async function graph(token, resource, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  return fetch(`https://graph.microsoft.com/v1.0${resource}`, { ...init, headers });
}

async function responseError(label, response) {
  const detail = (await response.text()).slice(0, 500);
  throw new Error(`${label} failed (${response.status}): ${detail}`);
}

async function getToken() {
  const tenantId = required("MICROSOFT_TENANT_ID");
  const response = await fetch(
    `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: required("MICROSOFT_CLIENT_ID"),
        client_secret: required("MICROSOFT_CLIENT_SECRET"),
        scope: "https://graph.microsoft.com/.default",
        grant_type: "client_credentials",
      }),
    },
  );
  if (!response.ok) await responseError("Microsoft token request", response);
  const body = await response.json();
  if (!body.access_token) throw new Error("Microsoft token response contained no access token");
  return body.access_token;
}

async function getItem(token, driveId, itemPath) {
  const response = await graph(token, `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(itemPath)}`);
  if (response.status === 404) return null;
  if (!response.ok) await responseError("SharePoint path lookup", response);
  return response.json();
}

async function ensureFolder(token, driveId, folderPath) {
  const parts = folderPath.split("/").filter(Boolean);
  let currentPath = "";
  for (const part of parts) {
    const nextPath = currentPath ? `${currentPath}/${part}` : part;
    let item = await getItem(token, driveId, nextPath);
    if (!item) {
      const endpoint = currentPath
        ? `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(currentPath)}:/children`
        : `/drives/${encodeURIComponent(driveId)}/root/children`;
      const response = await graph(token, endpoint, {
        method: "POST",
        body: JSON.stringify({ name: part, folder: {}, "@microsoft.graph.conflictBehavior": "fail" }),
      });
      if (response.status === 409) item = await getItem(token, driveId, nextPath);
      else if (response.ok) item = await response.json();
      else await responseError("SharePoint folder creation", response);
    }
    if (!item?.folder) throw new Error(`SharePoint path is not a folder: ${nextPath}`);
    currentPath = nextPath;
  }
}

async function upload(token, driveId, folderPath, localFile) {
  const fileName = path.basename(localFile);
  const remotePath = `${folderPath}/${fileName}`;
  const sessionResponse = await graph(
    token,
    `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(remotePath)}:/createUploadSession`,
    {
      method: "POST",
      body: JSON.stringify({ item: { "@microsoft.graph.conflictBehavior": "replace", name: fileName } }),
    },
  );
  if (!sessionResponse.ok) await responseError("SharePoint upload-session creation", sessionResponse);
  const { uploadUrl } = await sessionResponse.json();
  if (!uploadUrl) throw new Error("Microsoft Graph returned no upload URL");

  const file = await open(localFile, "r");
  try {
    const { size } = await file.stat();
    if (!size) throw new Error("Refusing to upload an empty database dump");
    const chunkSize = 10 * 1024 * 1024; // Multiple of Graph's required 320 KiB unit.
    let offset = 0;
    let uploadedItem;
    while (offset < size) {
      const length = Math.min(chunkSize, size - offset);
      const buffer = Buffer.allocUnsafe(length);
      const { bytesRead } = await file.read(buffer, 0, length, offset);
      if (bytesRead !== length) throw new Error(`Short read at byte ${offset}`);
      const response = await fetch(uploadUrl, {
        method: "PUT",
        headers: {
          "Content-Length": String(length),
          "Content-Range": `bytes ${offset}-${offset + length - 1}/${size}`,
        },
        body: buffer,
      });
      if (response.status === 200 || response.status === 201) uploadedItem = await response.json();
      else if (response.status === 202) await response.json();
      else await responseError("SharePoint chunk upload", response);
      offset += length;
    }
    if (!uploadedItem?.id) throw new Error("Upload completed without final SharePoint item metadata");
    return { ...uploadedItem, remotePath };
  } finally {
    await file.close();
  }
}

const localFile = process.argv[2];
if (!localFile) throw new Error("Usage: upload-backup-sharepoint.mjs <dump.sql>");

const token = await getToken();
const driveId = required("MICROSOFT_DRIVE_ID");
const root = String(process.env.MICROSOFT_ROOT_FOLDER || "Kridiya Business")
  .trim()
  .replace(/^\/+|\/+$/g, "");
const folderPath = `${root}/database-backups`;
await ensureFolder(token, driveId, folderPath);
const result = await upload(token, driveId, folderPath, path.resolve(localFile));
console.log(JSON.stringify({
  id: result.id,
  name: result.name,
  size: result.size,
  path: result.remotePath,
  webUrl: result.webUrl,
}));
