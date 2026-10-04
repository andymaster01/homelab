#!/usr/bin/env node

import https from "node:https";
import { execFileSync } from "node:child_process";
import { access, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { isIP } from "node:net";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultsPath = path.join(repoRoot, "vm-definitions", "defaults.json");
const imagesPath = path.join(repoRoot, "vm-definitions", "images.json");
const tokenName = "TF_VAR_proxmox_api_token";
const taskTimeoutMs = 900_000;

class ProxmoxError extends Error {}

async function readJson(filePath) {
  try {
    const parsed = JSON.parse(await readFile(filePath, "utf8"));
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
      throw new Error("expected a JSON object");
    }
    return parsed;
  } catch (error) {
    throw new ProxmoxError(`Could not read ${filePath}: ${error.message}`);
  }
}

function getApiToken() {
  let token = process.env[tokenName]?.trim();
  if (!token) {
    try {
      token = execFileSync("fnox", ["get", "--config", path.join(repoRoot, "fnox.toml"), tokenName], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
    } catch {
      throw new ProxmoxError(`${tokenName} is not set and could not be read from fnox.toml`);
    }
  }
  if (!token) throw new ProxmoxError(`${tokenName} is empty`);
  return token.replace(/^PVEAPIToken=/, "");
}

class ProxmoxAPI {
  constructor(apiUrl, token, verifyTls) {
    this.apiUrl = apiUrl.replace(/\/$/, "");
    this.authorization = `PVEAPIToken=${token}`;
    this.verifyTls = verifyTls;
  }

  request(method, apiPath, data) {
    const url = new URL(`${this.apiUrl}${apiPath}`);
    const body = data === undefined ? undefined : new URLSearchParams(data).toString();
    const headers = {
      Authorization: this.authorization,
      Accept: "application/json",
    };
    if (body !== undefined) headers["Content-Type"] = "application/x-www-form-urlencoded";

    return new Promise((resolve, reject) => {
      const request = https.request(url, {
        method,
        headers,
        rejectUnauthorized: this.verifyTls,
        timeout: 30_000,
      }, (response) => {
        let responseBody = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => { responseBody += chunk; });
        response.on("end", () => {
          let payload;
          try {
            payload = JSON.parse(responseBody);
          } catch {
            reject(new ProxmoxError(`Proxmox returned invalid JSON for ${apiPath}`));
            return;
          }
          if ((response.statusCode ?? 500) < 200 || (response.statusCode ?? 500) >= 300) {
            reject(new ProxmoxError(`Proxmox API ${method} ${apiPath} returned ${response.statusCode}: ${JSON.stringify(payload.errors ?? payload)}`));
            return;
          }
          if (!("data" in payload)) {
            reject(new ProxmoxError(`Proxmox returned an unexpected response for ${apiPath}`));
            return;
          }
          resolve(payload.data);
        });
      });
      request.on("timeout", () => request.destroy(new Error("request timed out")));
      request.on("error", (error) => reject(new ProxmoxError(`Proxmox API request failed for ${apiPath}: ${error.message}`)));
      if (body !== undefined) request.write(body);
      request.end();
    });
  }

  async waitForTask(node, upid) {
    const taskPath = `/nodes/${encodeURIComponent(node)}/tasks/${encodeURIComponent(upid)}/status`;
    const deadline = Date.now() + taskTimeoutMs;
    while (Date.now() < deadline) {
      const status = await this.request("GET", taskPath);
      if (status.status === "stopped") {
        if (status.exitstatus !== "OK") {
          throw new ProxmoxError(`Proxmox task failed: ${status.exitstatus ?? "unknown status"}`);
        }
        return;
      }
      await delay(2_000);
    }
    throw new ProxmoxError(`Timed out waiting for Proxmox task ${upid}`);
  }
}

function assertInteger(value, name, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ProxmoxError(`${name} must be an integer from ${min} to ${max}`);
  }
}

function validateAddress(address, gateway) {
  if (address === "dhcp") return;
  const match = /^(.+)\/(\d{1,3})$/.exec(address);
  if (!match || isIP(match[1]) === 0 || Number(match[2]) > (isIP(match[1]) === 4 ? 32 : 128)) {
    throw new ProxmoxError("network.address must be 'dhcp' or a valid IP address with CIDR prefix");
  }
  if (isIP(gateway) === 0) throw new ProxmoxError("network.gateway must be a valid IP address for static networking");
  if (isIP(match[1]) !== isIP(gateway)) throw new ProxmoxError("network.gateway address family must match network.address");
}

async function validateDefinition(defaults, imageRegistry, vm) {
  const required = ["name", "vm_id", "node", "image", "cpu_cores", "memory_mb", "disk_gb", "network", "cloud_init"];
  const missing = required.filter((key) => !(key in vm));
  if (missing.length) throw new ProxmoxError(`VM definition is missing: ${missing.join(", ")}`);
  if (typeof vm.name !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$/.test(vm.name)) {
    throw new ProxmoxError("name must be 1-63 letters, numbers, dots, underscores, or dashes");
  }
  assertInteger(vm.vm_id, "vm_id", 100, 999_999_999);
  assertInteger(vm.cpu_cores, "cpu_cores", 1, 128);
  assertInteger(vm.memory_mb, "memory_mb", 512, 1_048_576);
  assertInteger(vm.disk_gb, "disk_gb", 4, 65_536);
  if (typeof vm.node !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(vm.node)) {
    throw new ProxmoxError("node contains unsupported characters");
  }
  if (!vm.network || typeof vm.network !== "object" || Array.isArray(vm.network)
      || !vm.cloud_init || typeof vm.cloud_init !== "object" || Array.isArray(vm.cloud_init)) {
    throw new ProxmoxError("network and cloud_init must be JSON objects");
  }
  if (typeof vm.network.address !== "string") throw new ProxmoxError("network.address is required");
  validateAddress(vm.network.address, vm.network.gateway ?? "");
  if (typeof vm.cloud_init.username !== "string" || !/^[a-z_][a-z0-9_-]{0,31}$/.test(vm.cloud_init.username)) {
    throw new ProxmoxError("cloud_init.username must be a valid Linux username");
  }
  if (typeof vm.cloud_init.ssh_public_key_file !== "string" || !vm.cloud_init.ssh_public_key_file) {
    throw new ProxmoxError("cloud_init.ssh_public_key_file is required");
  }
  const keyFile = path.resolve(vm.cloud_init.ssh_public_key_file.replace(/^~(?=$|\/)/, os.homedir()));
  try {
    await access(keyFile, constants.R_OK);
  } catch {
    throw new ProxmoxError(`SSH public key file not found or unreadable: ${keyFile}`);
  }
  const publicKey = (await readFile(keyFile, "utf8")).trim();
  if (!/^(ssh-ed25519 |ssh-rsa |ecdsa-sha2-)/.test(publicKey)) {
    throw new ProxmoxError(`${keyFile} does not look like an OpenSSH public key`);
  }

  if (typeof defaults.api_url !== "string" || !defaults.api_url.startsWith("https://")) {
    throw new ProxmoxError("defaults.api_url must be an HTTPS URL");
  }
  if (typeof vm.image !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(vm.image)) {
    throw new ProxmoxError("image must be a valid image identifier from vm-definitions/images.json");
  }
  if (!imageRegistry.images || typeof imageRegistry.images !== "object" || Array.isArray(imageRegistry.images)) {
    throw new ProxmoxError("vm-definitions/images.json must contain an images object");
  }
  const image = imageRegistry.images[vm.image];
  if (!image || typeof image !== "object" || Array.isArray(image)) {
    throw new ProxmoxError(`Image identifier '${vm.image}' is not defined in vm-definitions/images.json`);
  }
  if (typeof image.volume !== "string" || !/^[A-Za-z0-9_.-]+:import\/[A-Za-z0-9_.+-]+$/.test(image.volume)) {
    throw new ProxmoxError(`Image '${vm.image}' must have a volume in import content, such as local:import/image.raw`);
  }
  for (const name of ["target_storage", "bridge"]) {
    if (typeof defaults[name] !== "string" || !/^[A-Za-z0-9_.-]+$/.test(defaults[name])) {
      throw new ProxmoxError(`defaults.${name} is invalid`);
    }
  }
  if (!Array.isArray(defaults.dns) || defaults.dns.some((ip) => typeof ip !== "string" || isIP(ip) === 0)) {
    throw new ProxmoxError("defaults.dns must contain valid IP addresses");
  }
  if (typeof (defaults.verify_tls ?? true) !== "boolean") {
    throw new ProxmoxError("defaults.verify_tls must be true or false");
  }

  return {
    apiUrl: defaults.api_url,
    verifyTls: defaults.verify_tls ?? true,
    imageId: vm.image,
    imageVolume: image.volume,
    targetStorage: defaults.target_storage,
    bridge: defaults.bridge,
    dns: defaults.dns.join(","),
    publicKey,
    publicKeyPath: keyFile,
  };
}

async function validateOnProxmox(api, vm, resolved) {
  const nodes = await api.request("GET", "/nodes");
  const node = nodes.find((item) => item.node === vm.node);
  if (!node) throw new ProxmoxError(`Proxmox node ${vm.node} was not found`);
  if (node.status !== "online") throw new ProxmoxError(`Proxmox node ${vm.node} is not online`);

  const nodePath = `/nodes/${encodeURIComponent(vm.node)}`;
  const storages = await api.request("GET", `${nodePath}/storage`);
  const storage = storages.find((item) => item.storage === resolved.targetStorage);
  if (!storage || !storage.active || !String(storage.content ?? "").split(",").includes("images")) {
    throw new ProxmoxError(`Target storage ${resolved.targetStorage} is not active or does not support VM images on ${vm.node}`);
  }

  const sourceStorage = resolved.imageVolume.split(":", 1)[0];
  const importItems = await api.request(
    "GET",
    `${nodePath}/storage/${encodeURIComponent(sourceStorage)}/content?content=import`,
  );
  if (!importItems.some((item) => item.volid === resolved.imageVolume)) {
    throw new ProxmoxError(`Image ${resolved.imageVolume} is not available as import content on ${vm.node}`);
  }

  const resources = await api.request("GET", "/cluster/resources?type=vm");
  const existing = resources.find((item) => item.vmid === vm.vm_id);
  if (existing) throw new ProxmoxError(`VM ID ${vm.vm_id} is already used by ${existing.name ?? "a guest"}`);
}

async function createVm(api, vm, resolved) {
  const network = vm.network;
  let ipconfig = `ip=${network.address}`;
  if (network.address !== "dhcp") ipconfig += `,gw=${network.gateway}`;
  const config = {
    vmid: String(vm.vm_id),
    name: vm.name,
    cores: String(vm.cpu_cores),
    sockets: "1",
    cpu: "host",
    memory: String(vm.memory_mb),
    ostype: "l26",
    scsihw: "virtio-scsi-pci",
    scsi0: `${resolved.targetStorage}:0,import-from=${resolved.imageVolume},discard=on,iothread=1,size=${vm.disk_gb}G`,
    ide2: `${resolved.targetStorage}:cloudinit`,
    boot: "order=scsi0;net0",
    net0: `virtio,bridge=${resolved.bridge}`,
    agent: "enabled=1",
    ciuser: vm.cloud_init.username,
    sshkeys: resolved.publicKey,
    ipconfig0: ipconfig,
    start: "0",
    onboot: "1",
  };
  if (resolved.dns) config.nameserver = resolved.dns;

  console.log(`Creating VM ${vm.name} (ID ${vm.vm_id}) on ${vm.node} from ${resolved.imageVolume}...`);
  const upid = await api.request("POST", `/nodes/${encodeURIComponent(vm.node)}/qemu`, config);
  await api.waitForTask(vm.node, upid);

  console.log(`Starting VM ${vm.name}...`);
  const startTask = await api.request(
    "POST",
    `/nodes/${encodeURIComponent(vm.node)}/qemu/${vm.vm_id}/status/start`,
    {},
  );
  await api.waitForTask(vm.node, startTask);
  console.log(`VM ${vm.name} (ID ${vm.vm_id}) started; cloud-init will configure it on first boot.`);
}

function printValidatedSpecs(vm, resolved) {
  const network = vm.network.address === "dhcp"
    ? "DHCP"
    : `${vm.network.address} (gateway ${vm.network.gateway})`;
  const dns = resolved.dns || "Proxmox node defaults";
  const ramGiB = Number((vm.memory_mb / 1024).toFixed(1));

  console.log(`\nVM definition valid: ${vm.name}`);
  console.log(`  Proxmox node : ${vm.node}`);
  console.log(`  VM ID        : ${vm.vm_id}`);
  console.log("  Machine");
  console.log(`    CPU        : ${vm.cpu_cores} cores (host)`);
  console.log(`    Memory     : ${vm.memory_mb} MiB (${ramGiB} GiB)`);
  console.log(`    Boot disk  : ${vm.disk_gb} GiB on ${resolved.targetStorage}`);
  console.log(`    Image      : ${resolved.imageId}`);
  console.log(`    Source     : ${resolved.imageVolume}`);
  console.log("  Network");
  console.log(`    Bridge     : ${resolved.bridge}`);
  console.log(`    Address    : ${network}`);
  console.log(`    DNS        : ${dns}`);
  console.log("  Cloud-init");
  console.log(`    Username   : ${vm.cloud_init.username}`);
  console.log(`    SSH key    : ${resolved.publicKeyPath}`);
}

async function main() {
  const [action, definitionPath, ...extraArgs] = process.argv.slice(2);
  if (!["validate", "create"].includes(action) || !definitionPath || extraArgs.length) {
    console.error("Usage: node scripts/proxmox-vm.mjs <validate|create> <vm-definition.json>");
    return 2;
  }
  try {
    const [defaults, imageRegistry, vm] = await Promise.all([
      readJson(defaultsPath),
      readJson(imagesPath),
      readJson(path.resolve(definitionPath)),
    ]);
    const resolved = await validateDefinition(defaults, imageRegistry, vm);
    const api = new ProxmoxAPI(resolved.apiUrl, getApiToken(), resolved.verifyTls);
    await validateOnProxmox(api, vm, resolved);
    printValidatedSpecs(vm, resolved);
    if (action === "create") await createVm(api, vm, resolved);
    return 0;
  } catch (error) {
    console.error(`Error: ${error.message}`);
    return 1;
  }
}

process.exitCode = await main();
