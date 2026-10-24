"""Register a catalogued runtime GitHub App; keep its private key only in Key Vault."""

import argparse
import base64
import html
import importlib.util
import json
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener
import webbrowser


ROOT = Path(__file__).resolve().parents[1]
API = "https://api.github.com"


class BootstrapError(Exception):
    """An actionable error that never contains an API response or credential."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


def request_json(method, url, *, data=None, token=None):
    headers = {"Accept": "application/json", "User-Agent": "platform-workloads-app-bootstrap"}
    if url.startswith(f"{API}/"):
        headers["Accept"] = "application/vnd.github+json"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    payload = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        payload = json.dumps(data).encode()
    request = Request(url, data=payload, headers=headers, method=method)
    try:
        with build_opener(NoRedirect).open(request, timeout=30) as response:
            body = response.read(1024 * 1024 + 1)
            if len(body) > 1024 * 1024:
                raise BootstrapError("API response exceeds the bootstrap size limit.")
            try:
                return json.loads(body) if body else None
            except (ValueError, UnicodeError):
                raise BootstrapError("API returned an invalid JSON response; its body is withheld.") from None
    except HTTPError as error:
        raise BootstrapError(f"API request failed (HTTP {error.code}); credentials and response bodies are withheld.") from None
    except URLError:
        raise BootstrapError("API request failed; check network access and retry.") from None


def az_json(*arguments):
    executable = shutil.which("az")
    if executable is None:
        raise BootstrapError("Azure CLI is required. Install it and run az login before bootstrapping.")
    result = subprocess.run([executable, *arguments, "--only-show-errors", "--output", "json"],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise BootstrapError("Azure CLI failed; check az login, subscription and Key Vault permissions.")
    return json.loads(result.stdout)


def load_app(workload, name):
    files = list((ROOT / "terraform" / "workloads").glob("**/*.json"))
    matches = [(path, json.loads(path.read_text(encoding="utf-8")))
               for path in files if "examples" not in path.relative_to(ROOT / "terraform" / "workloads").parts]
    matches = [(path, value) for path, value in matches if value.get("name") == workload]
    if len(matches) != 1:
        raise BootstrapError("Expected exactly one workload catalog entry.")
    path, catalog = matches[0]
    app = catalog.get("github", {}).get("runtime_apps", {}).get(name)
    if app is None:
        raise BootstrapError("The requested runtime App is not declared in this workload.")
    validate_app(app)
    return path, catalog, app


def validate_app(app):
    allowed = {"display_name", "description", "owner", "owner_type", "homepage_url", "environment",
               "repositories", "repository_permissions", "key_vault_secret_name", "registration"}
    if (set(app) != allowed or app.get("owner_type") not in ("User", "Organization")
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}", app.get("owner", ""))
            or not re.fullmatch(r"[A-Za-z0-9-]{1,127}", app.get("key_vault_secret_name", ""))
            or app.get("environment") not in ("dev", "tst", "prd")
            or not app.get("display_name") or not app.get("description")
            or not app.get("repository_permissions")
            or any(value not in ("read", "write") for value in app["repository_permissions"].values())
            or not app.get("repositories")
            or len({repo.lower() for repo in app["repositories"]}) != len(app["repositories"])
            or any(not re.fullmatch(r"[A-Za-z0-9_.-]+", repo) for repo in app["repositories"])):
        raise BootstrapError("Invalid runtime GitHub App declaration.")
    url = urlparse(app.get("homepage_url", ""))
    if url.scheme != "https" or not url.hostname or url.username or url.password:
        raise BootstrapError("The App homepage must be a public HTTPS URL without credentials.")
    registration = app["registration"]
    if registration is not None and (
            set(registration) != {"app_id", "installation_id", "slug"}
            or not re.fullmatch(r"[1-9][0-9]*", str(registration.get("app_id", "")))
            or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", registration.get("slug", ""))
            or registration["installation_id"] is not None and
            not re.fullmatch(r"[1-9][0-9]*", str(registration["installation_id"]))):
        raise BootstrapError("Invalid runtime GitHub App registration metadata.")


def discover_vault(workload, app):
    vaults = az_json("keyvault", "list")
    matches = [vault["name"] for vault in vaults if all(
        (vault.get("tags") or {}).get(key) == value for key, value in
        {"Workload": workload, "Environment": app["environment"], "Purpose": "workload-secrets"}.items())]
    if len(matches) != 1:
        raise BootstrapError(f"Expected exactly one tagged workload-secrets vault; found {len(matches)}. Check the selected subscription.")
    return matches[0]


def vault_request(method, vault, name, token, data=None):
    return request_json(method, f"https://{vault}.vault.azure.net/secrets/{name}?api-version=7.4", data=data, token=token)


def read_existing(vault, app, workload, name, token):
    metadata = az_json("keyvault", "secret", "list", "--vault-name", vault)
    if not any(secret["name"].lower() == app["key_vault_secret_name"].lower() for secret in metadata):
        deleted = az_json("keyvault", "secret", "list-deleted", "--vault-name", vault)
        if any(secret["name"].lower() == app["key_vault_secret_name"].lower() for secret in deleted):
            raise BootstrapError("The App key is soft-deleted. Recover it explicitly before resuming bootstrap.")
        return None
    stored = vault_request("GET", vault, app["key_vault_secret_name"], token)
    tags = stored.get("tags") or {}
    attributes = stored.get("attributes") or {}
    if (tags.get("managed-by") != "platform-workloads" or tags.get("workload") != workload
            or tags.get("runtime-app") != name or attributes.get("enabled") is not True
            or attributes.get("exp") is not None or not tags.get("app-id") or not tags.get("app-slug")):
        raise BootstrapError("An existing key has unexpected ownership or lifecycle metadata. Explicit recovery is required; it will not be overwritten.")
    return {"id": tags["app-id"], "slug": tags["app-slug"], "pem": stored["value"]}


def manifest(app, callback):
    return {"name": app["display_name"], "description": app["description"], "url": app["homepage_url"],
            "redirect_url": callback, "public": False, "default_events": [],
            "default_permissions": app["repository_permissions"],
            "hook_attributes": {"url": app["homepage_url"], "active": False}}


def callback_code(path, state):
    uri = urlparse(path)
    values = parse_qs(uri.query)
    if (uri.path != "/callback" or values.get("state") != [state]
            or len(values.get("code", [])) != 1 or not re.fullmatch(r"[A-Za-z0-9_-]{1,200}", values["code"][0])):
        return None
    return values["code"][0]


def create_app(app, *, browser=True, timeout=900):
    state = secrets.token_urlsafe(32)
    owner_path = "" if app["owner_type"] == "User" else f"/organizations/{app['owner']}"
    action = f"https://github.com{owner_path}/settings/apps/new?state={state}"
    result = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_arguments):
            pass

        def do_GET(self):
            if self.path == f"/?state={state}":
                value = html.escape(json.dumps(manifest(app, result["callback"])), quote=True)
                self.reply(200, f'<html><body><form method="post" action="{html.escape(action, quote=True)}">'
                           f'<input type="hidden" name="manifest" value="{value}">'
                           '<button type="submit">Register the reviewed GitHub App</button></form></body></html>')
                return
            code = callback_code(self.path, state)
            if code is None:
                self.reply(400, "Invalid bootstrap callback.")
                return
            result["code"] = code
            self.reply(200, "Registration received. Return to the terminal to finish installation.")

        def reply(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", "default-src 'none'; form-action https://github.com; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(body.encode())

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        server.timeout = 1
        result["callback"] = f"http://127.0.0.1:{server.server_port}/callback"
        link = f"http://127.0.0.1:{server.server_port}/?state={state}"
        print(f"Approve the App registration in your browser: {link}", flush=True)
        if browser:
            webbrowser.open(link)
        until = time.monotonic() + timeout
        while "code" not in result:
            if time.monotonic() >= until:
                raise BootstrapError("Registration timed out. No key was retrieved; restart bootstrap to try again.")
            server.handle_request()
    return request_json("POST", f"{API}/app-manifests/{result['code']}/conversions")


def app_jwt(identity):
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError:
        raise BootstrapError("Install scripts/requirements-github-apps.txt before bootstrapping.") from None
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + 540, "iss": str(identity["id"])}
    unsigned = encode(b'{"alg":"RS256","typ":"JWT"}') + b"." + encode(json.dumps(payload).encode())
    key = serialization.load_pem_private_key(identity["pem"].encode(), password=None)
    signature = key.sign(unsigned, padding.PKCS1v15(), hashes.SHA256())
    return (unsigned + b"." + encode(signature)).decode()


def validate_identity(identity, app):
    actual = request_json("GET", f"{API}/app", token=app_jwt(identity))
    permissions = {key: value for key, value in actual["permissions"].items() if key != "metadata"}
    if (str(actual["id"]) != str(identity["id"]) or actual["slug"] != identity["slug"]
            or actual["owner"]["login"].lower() != app["owner"].lower()
            or permissions != app["repository_permissions"] or actual.get("events") != []):
        raise BootstrapError("The App identity, owner, permissions or webhook events differ from the reviewed declaration.")


def verify_installation(identity, app, installation):
    permissions = {key: value for key, value in installation["permissions"].items() if key != "metadata"}
    if (installation["account"]["login"].lower() != app["owner"].lower()
            or installation["repository_selection"] != "selected"
            or installation.get("suspended_at") is not None or permissions != app["repository_permissions"]):
        raise BootstrapError("Install the App on the declared account, with only the selected repositories and reviewed permissions.")
    token = request_json("POST", f"{API}/app/installations/{installation['id']}/access_tokens",
                         token=app_jwt(identity))["token"]
    try:
        expected = {f"{app['owner']}/{repo}".lower() for repo in app["repositories"]}
        actual = set()
        for page in range(1, (len(expected) + 99) // 100 + 1):
            response = request_json("GET", f"{API}/installation/repositories?per_page=100&page={page}", token=token)
            if response["total_count"] != len(expected):
                raise BootstrapError("The installation repository selection differs from the declaration. Correct it in GitHub and rerun bootstrap.")
            actual.update(repo["full_name"].lower() for repo in response["repositories"])
            if len(response["repositories"]) < 100:
                break
        if actual != expected:
            raise BootstrapError("The installation repository selection differs from the declaration. Correct it in GitHub and rerun bootstrap.")
    finally:
        request_json("DELETE", f"{API}/installation/token", token=token)


def wait_installation(identity, app, *, browser=True, timeout=900):
    link = f"https://github.com/apps/{identity['slug']}/installations/new"
    print(f"Install the App on only {', '.join(app['repositories'])}: {link}", flush=True)
    if browser:
        webbrowser.open(link)
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        installations = request_json("GET", f"{API}/app/installations?per_page=100", token=app_jwt(identity))
        matches = [item for item in installations if item["account"]["login"].lower() == app["owner"].lower()]
        if len(matches) > 1 or len(installations) > 1:
            raise BootstrapError("Unexpected multiple installations; explicit review is required.")
        if matches:
            verify_installation(identity, app, matches[0])
            return matches[0]["id"]
        time.sleep(5)
    raise BootstrapError("Installation timed out. The key is safe in Key Vault; rerun bootstrap to resume without registering another App.")


def save_registration(path, catalog, name, identity, installation):
    current = json.loads(path.read_text(encoding="utf-8"))
    expected = catalog["github"]["runtime_apps"][name]
    actual = current["github"]["runtime_apps"][name]
    if {key: value for key, value in expected.items() if key != "registration"} != {
            key: value for key, value in actual.items() if key != "registration"}:
        raise BootstrapError("The App declaration changed during bootstrap. The stored key is safe; review the catalog and resume.")
    actual["registration"] = {
        "app_id": str(identity["id"]), "installation_id": str(installation) if installation is not None else None,
        "slug": identity["slug"]}
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(json.dumps(current, indent=4) + "\n")
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def bootstrap(workload, name, *, browser=True):
    path, catalog, app = load_app(workload, name)
    if importlib.util.find_spec("cryptography") is None:
        raise BootstrapError("Install scripts/requirements-github-apps.txt before bootstrapping.")
    vault = discover_vault(workload, app)
    token = az_json("account", "get-access-token", "--resource", "https://vault.azure.net")["accessToken"]
    identity = read_existing(vault, app, workload, name, token)
    if identity is None:
        if app.get("registration") is not None:
            raise BootstrapError("A registered App has no active key. Restore or rotate it explicitly; bootstrap will not create a replacement App.")
        identity = create_app(app, browser=browser)
        validate_identity(identity, app)
        if read_existing(vault, app, workload, name, token) is not None:
            raise BootstrapError("A key appeared during registration. Refusing to overwrite it; review the newly created App manually.")
        vault_request("PUT", vault, app["key_vault_secret_name"], token, {
            "value": identity["pem"], "contentType": "application/x-pem-file", "attributes": {"enabled": True},
            "tags": {"managed-by": "platform-workloads", "workload": workload, "runtime-app": name,
                     "app-id": str(identity["id"]), "app-slug": identity["slug"]}})
        save_registration(path, catalog, name, identity, None)
        print(f"Stored the App key in {vault}/{app['key_vault_secret_name']}; no key was written locally.", flush=True)
    else:
        validate_identity(identity, app)
        registered = app.get("registration")
        if registered and (registered["app_id"] != str(identity["id"]) or registered["slug"] != identity["slug"]):
            raise BootstrapError("The existing key and catalog registration disagree. Explicit recovery is required.")
    installation = wait_installation(identity, app, browser=browser)
    save_registration(path, catalog, name, identity, installation)
    print(f"Verified App {identity['slug']} ({identity['id']}), installation {installation}. Review the catalog diff before Terraform apply.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workload", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--no-browser", action="store_true")
    arguments = parser.parse_args()
    try:
        bootstrap(arguments.workload, arguments.app, browser=not arguments.no_browser)
    except (BootstrapError, KeyboardInterrupt) as error:
        print(str(error) or "Bootstrap cancelled. Rerun to resume any key already stored in Key Vault.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
