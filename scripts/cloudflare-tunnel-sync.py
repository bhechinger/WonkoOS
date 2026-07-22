#!/usr/bin/env python3

import json
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API = "https://api.cloudflare.com/client/v4"
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


def main(token_file, account_id, zone_id, tunnel_id, config_file, dns_file):
    with open(token_file, encoding="utf-8") as file:
        token = file.read().strip()
    if not token:
        raise RuntimeError("Cloudflare API token is empty")
    with open(config_file, encoding="utf-8") as file:
        tunnel = json.load(file)
    with open(dns_file, encoding="utf-8") as file:
        records = json.load(file)

    api = Cloudflare(token)
    sync_tunnel(api, account_id, tunnel_id, tunnel)
    for record in records:
        sync_dns(api, zone_id, record)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 7:
        main(*sys.argv[1:])
    else:
        raise SystemExit(
            "usage: cloudflare-tunnel-sync TOKEN ACCOUNT ZONE TUNNEL CONFIG DNS"
        )
