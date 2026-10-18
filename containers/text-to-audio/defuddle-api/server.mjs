import { createHash, randomUUID } from "node:crypto";
import { lookup } from "node:dns/promises";
import { createServer } from "node:http";
import { isIP } from "node:net";
import { spawn } from "node:child_process";
import { access, mkdir, rename, rm, stat } from "node:fs/promises";
import path from "node:path";

const port = Number(process.env.PORT ?? 8080);
const outputDir = process.env.OUTPUT_DIR ?? "/output";
const outputHostPath = process.env.OUTPUT_HOST_PATH ?? outputDir;
const publicBaseUrl = (process.env.PUBLIC_BASE_URL ?? `http://localhost:${port}`).replace(/\/$/, "");
const maxRequestBytes = 32 * 1024;
const maxOutputBytes = 12 * 1024 * 1024;
const extractionTimeoutMs = 90_000;

function isPrivateAddress(address) {
  const version = isIP(address);
  if (version === 4) {
    const octets = address.split(".").map(Number);
    const [a, b, c] = octets;
    return a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && (b === 0 || b === 168) && (b !== 0 || c === 0)) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113);
  }
  if (version === 6) {
    const value = address.toLowerCase().split("%")[0];
    if (value.startsWith("::ffff:")) return isPrivateAddress(value.slice(7));
    return value === "::" || value === "::1" || /^(fc|fd|fe[89ab]|ff)/.test(value);
  }
  return true;
}

async function validateUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("url must be a valid absolute URL");
  }
  if (!new Set(["http:", "https:"]).has(url.protocol)) {
    throw new Error("only http and https URLs are supported");
  }
  if (url.username || url.password) throw new Error("URLs with credentials are not supported");
  if (url.port && !new Set(["80", "443"]).has(url.port)) {
    throw new Error("only the standard HTTP and HTTPS ports are supported");
  }
  const hostname = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (hostname === "localhost" || hostname.endsWith(".localhost") || hostname.endsWith(".local")) {
    throw new Error("local hostnames are not supported");
  }
  if (isIP(hostname)) {
    if (isPrivateAddress(hostname)) throw new Error("private network addresses are not supported");
  } else {
    let addresses;
    try {
      addresses = await lookup(hostname, { all: true, verbatim: true });
    } catch {
      throw new Error("hostname could not be resolved");
    }
    if (!addresses.length || addresses.some(({ address }) => isPrivateAddress(address))) {
      throw new Error("URLs resolving to private network addresses are not supported");
    }
  }
  return url;
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxRequestBytes) throw new Error("request body is too large");
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("request body must be valid JSON");
  }
}

function slug(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48) || "page";
}

function runDefuddle(url, tempPath) {
  return new Promise((resolve, reject) => {
    const child = spawn("./node_modules/.bin/defuddle", ["parse", url.href, "--md", "--frontmatter", "--output", tempPath], {
      cwd: "/app",
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    let settled = false;
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      if (!settled) {
        settled = true;
        reject(new Error("extraction timed out"));
      }
    }, extractionTimeoutMs);
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => { stderr = (stderr + chunk).slice(-4000); });
    child.on("error", (error) => {
      clearTimeout(timer);
      if (!settled) reject(error);
      settled = true;
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (settled) return;
      settled = true;
      if (code === 0) resolve();
      else reject(new Error(stderr.trim() || `Defuddle exited with status ${code}`));
    });
  });
}

function sendJson(response, status, value) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(value));
}

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      return sendJson(response, 200, { status: "ok" });
    }
    if (request.method === "POST" && request.url === "/extract") {
      const body = await readJson(request);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        return sendJson(response, 400, { error: "request body must be a JSON object" });
      }
      if (typeof body.url !== "string" || !body.url.trim()) {
        return sendJson(response, 400, { error: "url is required" });
      }
      const url = await validateUrl(body.url.trim());
      await mkdir(outputDir, { recursive: true });
      const date = new Date().toISOString().slice(0, 10);
      const digest = createHash("sha256").update(url.href).digest("hex").slice(0, 8);
      const filename = `${date}-${slug(url.hostname)}-${digest}-${randomUUID().slice(0, 8)}.md`;
      const target = path.join(outputDir, filename);
      const temp = path.join(outputDir, `.${filename}.${process.pid}.tmp`);
      try {
        await runDefuddle(url, temp);
        const { size } = await stat(temp);
        if (size > maxOutputBytes) throw new Error("extracted content is too large");
        await rename(temp, target);
      } catch (error) {
        await rm(temp, { force: true });
        throw error;
      }
      return sendJson(response, 201, {
        status: "completed",
        source_url: url.href,
        filename,
        file_path: path.join(outputHostPath, filename),
        download_url: `${publicBaseUrl}/files/${encodeURIComponent(filename)}`,
      });
    }
    if (request.method === "GET" && request.url?.startsWith("/files/")) {
      const filename = decodeURIComponent(request.url.slice("/files/".length));
      if (path.basename(filename) !== filename || !filename.endsWith(".md")) {
        return sendJson(response, 400, { error: "invalid file name" });
      }
      const file = path.join(outputDir, filename);
      try {
        await access(file);
      } catch {
        return sendJson(response, 404, { error: "file not found" });
      }
      response.writeHead(200, {
        "content-type": "text/markdown; charset=utf-8",
        "content-disposition": `attachment; filename="${filename}"`,
      });
      const { createReadStream } = await import("node:fs");
      return createReadStream(file).pipe(response);
    }
    return sendJson(response, 404, { error: "not found" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "request failed";
    const status = message.includes("URL") || message.includes("url ") || message.includes("hostname") || message.includes("private") || message.includes("credentials") || message.includes("ports") || message.includes("local hostnames") || message.includes("valid JSON") ? 400 : message.includes("request body is too large") ? 413 : 502;
    return sendJson(response, status, { error: message });
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Defuddle API listening on ${port}; saving Markdown to ${outputDir}`);
});
