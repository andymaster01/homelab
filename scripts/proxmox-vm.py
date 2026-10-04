#!/usr/bin/env python3

"""Create Proxmox VMs directly from an importable cloud image."""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import ssl
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULTS_PATH = REPO_ROOT / "vm-definitions" / "defaults.json"
TOKEN_NAME = "TF_VAR_proxmox_api_token"
TASK_TIMEOUT_SECONDS = 900


class ProxmoxError(Exception):
    pass


def read_json(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as source:
            value = json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        raise ProxmoxError(f"Could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise ProxmoxError(f"Expected a JSON object in {path}")
    return value


def get_api_token() -> str:
    token = os.environ.get(TOKEN_NAME, "").strip()
    if not token:
        fnox = shutil_which("fnox")
        if not fnox:
            raise ProxmoxError(
                f"{TOKEN_NAME} is not set and fnox is not installed. "
                f"Load the token from fnox.toml or export {TOKEN_NAME}."
            )
        result = subprocess.run(
            [fnox, "get", "--config", str(REPO_ROOT / "fnox.toml"), TOKEN_NAME],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise ProxmoxError(f"Could not read {TOKEN_NAME} from fnox.toml")
        token = result.stdout.strip()
    if not token:
        raise ProxmoxError(f"{TOKEN_NAME} is empty")
    return token.removeprefix("PVEAPIToken=")


def shutil_which(command: str) -> str | None:
    # Keep this tool dependency-free while still honoring PATH.
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


class ProxmoxAPI:
    def __init__(self, api_url: str, token: str, verify_tls: bool):
        self.api_url = api_url.rstrip("/")
        self.authorization = f"PVEAPIToken={token}"
        self.ssl_context = ssl.create_default_context() if verify_tls else ssl._create_unverified_context()

    def request(self, method: str, path: str, data: dict | None = None):
        body = urlencode(data).encode() if data is not None else None
        request = Request(
            f"{self.api_url}{path}",
            data=body,
            method=method,
            headers={
                "Authorization": self.authorization,
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        try:
            with urlopen(request, context=self.ssl_context, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            try:
                detail = json.loads(detail).get("errors", detail)
            except json.JSONDecodeError:
                pass
            raise ProxmoxError(f"Proxmox API {method} {path} returned {error.code}: {detail}") from error
        except (URLError, TimeoutError, http.client.HTTPException, json.JSONDecodeError) as error:
            raise ProxmoxError(f"Proxmox API request failed for {path}: {error}") from error
        if "data" not in payload:
            raise ProxmoxError(f"Proxmox API returned an unexpected response for {path}")
        return payload["data"]

    def wait_for_task(self, node: str, upid: str) -> None:
        task_path = f"/nodes/{quote(node, safe='')}/tasks/{quote(upid, safe='')}/status"
        deadline = time.monotonic() + TASK_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            status = self.request("GET", task_path)
            if status.get("status") == "stopped":
                if status.get("exitstatus") != "OK":
                    raise ProxmoxError(
                        f"Proxmox task failed: {status.get('exitstatus', 'unknown status')}"
                    )
                return
            time.sleep(2)
        raise ProxmoxError(f"Timed out waiting for Proxmox task {upid}")


def load_definition(path: Path) -> tuple[dict, dict]:
    defaults = read_json(DEFAULTS_PATH)
    definition = read_json(path)
    return defaults, definition


def validate_definition(defaults: dict, vm: dict) -> dict:
    required = ("name", "vm_id", "node", "cpu_cores", "memory_mb", "disk_gb", "network", "cloud_init")
    missing = [key for key in required if key not in vm]
    if missing:
        raise ProxmoxError(f"VM definition is missing: {', '.join(missing)}")

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,62}", str(vm["name"])):
        raise ProxmoxError("name must be 1-63 letters, numbers, dots, underscores, or dashes")
    for field, minimum, maximum in (("vm_id", 100, 999999999), ("cpu_cores", 1, 128), ("memory_mb", 512, 1048576), ("disk_gb", 4, 65536)):
        value = vm[field]
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            raise ProxmoxError(f"{field} must be an integer from {minimum} to {maximum}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", str(vm["node"])):
        raise ProxmoxError("node contains unsupported characters")

    network = vm["network"]
    cloud_init = vm["cloud_init"]
    if not isinstance(network, dict) or not isinstance(cloud_init, dict):
        raise ProxmoxError("network and cloud_init must be JSON objects")
    address = network.get("address")
    if not isinstance(address, str) or not address:
        raise ProxmoxError("network.address must be an IP/CIDR address or 'dhcp'")
    if address != "dhcp":
        try:
            import ipaddress

            ipaddress.ip_interface(address)
            ipaddress.ip_address(network.get("gateway", ""))
        except ValueError as error:
            raise ProxmoxError(f"Invalid static IP or gateway: {error}") from error
        if "/" not in address:
            raise ProxmoxError("Static network.address must include a CIDR prefix")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", str(cloud_init.get("username", ""))):
        raise ProxmoxError("cloud_init.username must be a valid Linux username")
    key_file = cloud_init.get("ssh_public_key_file")
    if not isinstance(key_file, str) or not key_file:
        raise ProxmoxError("cloud_init.ssh_public_key_file is required")
    public_key_path = Path(key_file).expanduser()
    if not public_key_path.is_file():
        raise ProxmoxError(f"SSH public key file not found: {public_key_path}")
    public_key = public_key_path.read_text(encoding="utf-8").strip()
    if not public_key.startswith(("ssh-ed25519 ", "ssh-rsa ", "ecdsa-sha2-")):
        raise ProxmoxError(f"{public_key_path} does not look like an OpenSSH public key")

    api_url = defaults.get("api_url")
    source = defaults.get("image_volume")
    storage = defaults.get("target_storage")
    bridge = defaults.get("bridge")
    if not isinstance(api_url, str) or not api_url.startswith("https://"):
        raise ProxmoxError("defaults.api_url must be an HTTPS URL")
    if not isinstance(source, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+:import/[A-Za-z0-9_.+-]+", source):
        raise ProxmoxError("defaults.image_volume must identify an import volume, such as local:import/image.raw")
    for label, value in (("target_storage", storage), ("bridge", bridge)):
        if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
            raise ProxmoxError(f"defaults.{label} is invalid")
    dns = defaults.get("dns", [])
    if not isinstance(dns, list) or any(not isinstance(item, str) for item in dns):
        raise ProxmoxError("defaults.dns must be an array of IP addresses")

    return {
        "api_url": api_url,
        "verify_tls": defaults.get("verify_tls", True),
        "image_volume": source,
        "target_storage": storage,
        "bridge": bridge,
        "dns": ",".join(dns),
        "public_key": public_key,
        "public_key_path": public_key_path,
    }


def validate_on_proxmox(api: ProxmoxAPI, defaults: dict, vm: dict, resolved: dict) -> None:
    nodes = api.request("GET", "/nodes")
    node = next((item for item in nodes if item.get("node") == vm["node"]), None)
    if not node:
        raise ProxmoxError(f"Proxmox node {vm['node']} was not found")
    if node.get("status") != "online":
        raise ProxmoxError(f"Proxmox node {vm['node']} is not online")

    storages = api.request("GET", f"/nodes/{quote(vm['node'], safe='')}/storage")
    storage = next((item for item in storages if item.get("storage") == resolved["target_storage"]), None)
    if not storage or not storage.get("active") or "images" not in storage.get("content", ""):
        raise ProxmoxError(
            f"Target storage {resolved['target_storage']} is not active or does not support VM images on {vm['node']}"
        )

    source_storage, _ = resolved["image_volume"].split(":", 1)
    import_content = api.request(
        "GET",
        f"/nodes/{quote(vm['node'], safe='')}/storage/{quote(source_storage, safe='')}/content?content=import",
    )
    if not any(item.get("volid") == resolved["image_volume"] for item in import_content):
        raise ProxmoxError(
            f"Image {resolved['image_volume']} is not available as import content on {vm['node']}"
        )

    resources = api.request("GET", "/cluster/resources?type=vm")
    existing = next((item for item in resources if item.get("vmid") == vm["vm_id"]), None)
    if existing:
        raise ProxmoxError(f"VM ID {vm['vm_id']} is already used by {existing.get('name', 'a guest')}")


def create_vm(api: ProxmoxAPI, vm: dict, resolved: dict) -> None:
    network = vm["network"]
    ipconfig = f"ip={network['address']}"
    if network["address"] != "dhcp":
        ipconfig += f",gw={network['gateway']}"
    disk = (
        f"{resolved['target_storage']}:0,import-from={resolved['image_volume']},"
        f"discard=on,iothread=1,size={vm['disk_gb']}G"
    )
    config = {
        "vmid": vm["vm_id"],
        "name": vm["name"],
        "cores": vm["cpu_cores"],
        "sockets": 1,
        "cpu": "host",
        "memory": vm["memory_mb"],
        "ostype": "l26",
        "scsihw": "virtio-scsi-pci",
        "scsi0": disk,
        "ide2": f"{resolved['target_storage']}:cloudinit",
        "boot": "order=scsi0;net0",
        "net0": f"virtio,bridge={resolved['bridge']}",
        "agent": "enabled=1",
        "ciuser": vm["cloud_init"]["username"],
        "sshkeys": resolved["public_key"],
        "ipconfig0": ipconfig,
        "start": 0,
        "onboot": 1,
    }
    if resolved["dns"]:
        config["nameserver"] = resolved["dns"]

    print(f"Creating VM {vm['name']} (ID {vm['vm_id']}) on {vm['node']} from {resolved['image_volume']}...")
    upid = api.request("POST", f"/nodes/{quote(vm['node'], safe='')}/qemu", config)
    api.wait_for_task(vm["node"], upid)

    print(f"Starting VM {vm['name']}...")
    upid = api.request(
        "POST",
        f"/nodes/{quote(vm['node'], safe='')}/qemu/{vm['vm_id']}/status/start",
        {},
    )
    api.wait_for_task(vm["node"], upid)
    print(f"VM {vm['name']} (ID {vm['vm_id']}) started; cloud-init will configure it on first boot.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create Proxmox VMs from an importable Ubuntu cloud image.")
    parser.add_argument("action", choices=("validate", "create"), help="validate settings or create and start the VM")
    parser.add_argument("definition", type=Path, help="path to a VM JSON file (usually in vm-definitions/)")
    args = parser.parse_args()

    try:
        defaults, vm = load_definition(args.definition)
        resolved = validate_definition(defaults, vm)
        api = ProxmoxAPI(resolved["api_url"], get_api_token(), bool(resolved["verify_tls"]))
        validate_on_proxmox(api, defaults, vm, resolved)
        print(
            f"Validated {vm['name']} (ID {vm['vm_id']}) on {vm['node']}: "
            f"{vm['cpu_cores']} CPU, {vm['memory_mb']} MiB RAM, {vm['disk_gb']} GiB disk, "
            f"network {vm['network']['address']}, SSH key {resolved['public_key_path']}"
        )
        if args.action == "create":
            create_vm(api, vm, resolved)
    except ProxmoxError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
