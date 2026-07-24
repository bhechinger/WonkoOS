#!/usr/bin/env python3

import ipaddress
import json
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API = "https://api.cloudflare.com/client/v4"
TRACE = "https://1.1.1.1/cdn-cgi/trace"
ADDRESS_TYPES = {"A", "AAAA", "CNAME"}


class Cloudflare:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        request = Request(
            API + path,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                result = json.load(response)
        except HTTPError as error:
            try:
                errors = json.loads(error.read()).get("errors", [])
                message = "; ".join(item.get("message", str(item)) for item in errors)
            except (json.JSONDecodeError, UnicodeDecodeError):
                message = error.reason
            raise RuntimeError(
                f"Cloudflare {method} {path} failed ({error.code}): {message}"
            ) from error
        except URLError as error:
            raise RuntimeError(f"Cloudflare {method} {path} failed: {error.reason}") from error

        if not result.get("success"):
            message = "; ".join(
                item.get("message", str(item)) for item in result.get("errors", [])
            )
            raise RuntimeError(f"Cloudflare {method} {path} failed: {message}")
        return result["result"]


def record_matches(current, desired):
    return all(current.get(key) == value for key, value in desired.items())


def dns_plan(current, desired):
    record_type = desired["type"]
    if desired.get("absent"):
        return [
            ("delete", record) for record in current if record["type"] == record_type
        ]
    conflicts = [
        record
        for record in current
        if (
            record["type"] in ADDRESS_TYPES
            if record_type in ADDRESS_TYPES
            else record["type"] == record_type
        )
    ]
    keeper = next(
        (
            record
            for record in conflicts
            if record["type"] == record_type
            and record.get("content") == desired["content"]
        ),
        next((record for record in conflicts if record["type"] == record_type), None),
    )
    actions = [("delete", record) for record in conflicts if record is not keeper]
    if keeper is None:
        actions.append(("create", desired))
    elif not record_matches(keeper, desired):
        actions.append(("update", keeper, desired))
    return actions


def spectrum_plan(current, desired):
    matching = [
        app
        for app in current
        if app.get("dns", {}).get("name") == desired["dns"]["name"]
    ]
    if len(matching) > 1:
        raise RuntimeError(f"multiple Spectrum apps use {desired['dns']['name']}")
    if matching:
        app = matching[0]
        if record_matches(app, desired):
            return []
        return [("update", app, desired)]
    if current:
        raise RuntimeError(
            "the Pro plan Spectrum app is already assigned to another hostname"
        )
    return [("create", desired)]


def parse_public_ipv4(trace):
    values = dict(
        line.split("=", 1) for line in trace.splitlines() if "=" in line
    )
    try:
        address = ipaddress.ip_address(values["ip"])
    except (KeyError, ValueError) as error:
        raise RuntimeError("Cloudflare trace did not return a valid public IP") from error
    if address.version != 4 or not address.is_global:
        raise RuntimeError("Cloudflare trace did not return a public IPv4 address")
    return str(address)


def public_ipv4():
    try:
        with urlopen(TRACE, timeout=30) as response:
            return parse_public_ipv4(response.read().decode())
    except (HTTPError, URLError, UnicodeDecodeError) as error:
        raise RuntimeError(f"public IPv4 discovery failed: {error}") from error


def sync_tunnel(api, account_id, tunnel_id, desired):
    path = f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations"
    current = api.request("GET", path)["config"]
    if current == desired:
        print("Cloudflare Tunnel configuration unchanged")
        return
    api.request("PUT", path, {"config": desired})
    print("Cloudflare Tunnel configuration updated")


def sync_dns(api, zone_id, desired):
    name = desired["name"]
    query = urlencode({"name": name, "per_page": 100})
    path = f"/zones/{zone_id}/dns_records"
    current = api.request("GET", f"{path}?{query}")
    actions = dns_plan(current, desired)
    for action in actions:
        if action[0] == "delete":
            api.request("DELETE", f"{path}/{action[1]['id']}")
        elif action[0] == "create":
            api.request("POST", path, action[1])
        else:
            api.request("PUT", f"{path}/{action[1]['id']}", action[2])
    print(f"{name} {desired['type']}: {'updated' if actions else 'unchanged'}")


def sync_spectrum(api, zone_id, hostname, origin_ipv4):
    path = f"/zones/{zone_id}/spectrum/apps"
    desired = {
        "protocol": "minecraft",
        "dns": {"type": "CNAME", "name": hostname},
        "origin_direct": [f"tcp://{origin_ipv4}:25565"],
    }
    actions = spectrum_plan(api.request("GET", path), desired)
    for action in actions:
        if action[0] == "create":
            api.request("POST", path, action[1])
        else:
            api.request("PUT", f"{path}/{action[1]['id']}", action[2])
    print(f"Spectrum {hostname}: {'updated' if actions else 'unchanged'}")


def self_test():
    desired = {
        "type": "CNAME",
        "name": "pwppp.example.net",
        "content": "tunnel.cfargotunnel.com",
        "ttl": 1,
        "proxied": True,
    }
    stale = [
        {"id": "a", "type": "A", "content": "192.0.2.1"},
        {"id": "txt", "type": "TXT", "content": "cloudflared-use-tunnel"},
    ]
    assert dns_plan(stale, desired) == [
        ("delete", stale[0]),
        ("create", desired),
    ]
    current = {"id": "cname", **desired}
    assert dns_plan([current, stale[1]], desired) == []
    changed = {**current, "proxied": False}
    assert dns_plan([changed], desired) == [("update", changed, desired)]
    absent = {"type": "TXT", "name": desired["name"], "absent": True}
    assert dns_plan([current, stale[1]], absent) == [("delete", stale[1])]

    spectrum = {
        "protocol": "minecraft",
        "dns": {"type": "CNAME", "name": "minecraft-tcp.example.net"},
        "origin_direct": ["tcp://192.0.2.1:25565"],
    }
    assert spectrum_plan([], spectrum) == [("create", spectrum)]
    existing = {"id": "spectrum", **spectrum}
    assert spectrum_plan([existing], spectrum) == []
    changed = {**existing, "origin_direct": ["tcp://192.0.2.2:25565"]}
    assert spectrum_plan([changed], spectrum) == [("update", changed, spectrum)]
    assert parse_public_ipv4("fl=1\nip=1.1.1.1\nts=1") == "1.1.1.1"


def main(
    token_file,
    spectrum_token_file,
    account_id,
    zone_id,
    tunnel_id,
    config_file,
    dns_file,
    spectrum_hostname,
):
    with open(token_file, encoding="utf-8") as file:
        token = file.read().strip()
    if not token:
        raise RuntimeError("Cloudflare API token is empty")
    with open(spectrum_token_file, encoding="utf-8") as file:
        spectrum_token = file.read().strip()
    if not spectrum_token:
        raise RuntimeError("Cloudflare Spectrum API token is empty")
    if spectrum_token.startswith("REPLACE_WITH_"):
        raise RuntimeError("replace the Cloudflare Spectrum API token placeholder")
    with open(config_file, encoding="utf-8") as file:
        tunnel = json.load(file)
    with open(dns_file, encoding="utf-8") as file:
        records = json.load(file)

    sync_spectrum(Cloudflare(spectrum_token), zone_id, spectrum_hostname, public_ipv4())
    api = Cloudflare(token)
    for record in records:
        sync_dns(api, zone_id, record)
    sync_tunnel(api, account_id, tunnel_id, tunnel)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 9:
        main(*sys.argv[1:])
    else:
        raise SystemExit(
            "usage: cloudflare-tunnel-sync TOKEN SPECTRUM_TOKEN ACCOUNT ZONE "
            "TUNNEL CONFIG DNS SPECTRUM_HOSTNAME"
        )
