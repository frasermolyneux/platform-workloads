"""Rotate the status reader certificate without reading private keys or using Terraform state."""

import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid


APPLICATION_NAME = "app-platform-status-monitoring-reader"
SECRET_NAME = "monitoring-reader-certificate"
PREFIX = "platform-workloads-status-reader-"
OWNER = "platform-workloads"
ARM = "https://management.azure.com"


class RotationError(Exception):
    """Safe, actionable failure without CLI output, response bodies or credentials."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


def command(*arguments, binary=False):
    result = subprocess.run(arguments, capture_output=True, text=not binary, check=False)
    if result.returncode:
        raise RotationError(f"{arguments[0]} command failed; output is withheld to protect credentials.")
    return result.stdout


def az_json(*arguments):
    return json.loads(command("az", *arguments, "--only-show-errors", "--output", "json"))


def request(method, url, token=None, document=None, *, missing_ok=False, form=False):
    headers = {"Content-Type": "application/x-www-form-urlencoded" if form else "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = (urlencode(document).encode() if form else json.dumps(document).encode()) if document is not None else None
    try:
        with build_opener(NoRedirect).open(Request(url, data=body, headers=headers, method=method), timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        raise RotationError(f"Credential API failed (HTTP {error.code}); its response body is withheld.") from None
    except URLError:
        raise RotationError("Credential API is unavailable; the existing secret has not been intentionally removed.") from None


def timestamp(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise RotationError("Credential timestamps must include a timezone.")
    return result


def discover():
    apps = az_json("ad", "app", "list", "--display-name", APPLICATION_NAME)
    apps = [app for app in apps if app["displayName"] == APPLICATION_NAME]
    if len(apps) != 1:
        raise RotationError("Deploy exactly one dedicated status monitoring reader application first.")
    app = apps[0]
    if app.get("passwordCredentials") or app.get("requiredResourceAccess"):
        raise RotationError("The monitoring reader must have no client secrets or directory API permissions.")
    vaults = [vault for vault in az_json("keyvault", "list") if all(
        (vault.get("tags") or {}).get(key) == value for key, value in
        {"Workload": "platform-status-web", "Environment": "prd", "Purpose": "workload-secrets"}.items())]
    if len(vaults) != 1:
        raise RotationError("Expected exactly one tagged production status runtime vault in the selected subscription.")
    return app, vaults[0]["id"], az_json("account", "show")["tenantId"]


def credentials(app):
    return az_json("ad", "app", "credential", "list", "--id", app["id"], "--cert")


def b64(value):
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def verify_authentication(app, tenant, certificate, key, now):
    endpoint = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
    der = command("openssl", "x509", "-in", str(certificate), "-outform", "DER", binary=True)
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT", "x5t": b64(hashlib.sha1(der).digest())}).encode())
    claims = b64(json.dumps({
        "aud": endpoint, "iss": app["appId"], "sub": app["appId"], "jti": str(uuid.uuid4()),
        "nbf": int(now.timestamp()) - 30, "exp": int(now.timestamp()) + 600
    }).encode())
    unsigned = f"{header}.{claims}"
    assertion_path = key.parent / "assertion"
    assertion_path.write_text(unsigned, encoding="ascii")
    signature = command("openssl", "dgst", "-sha256", "-sign", str(key), str(assertion_path), binary=True)
    assertion = f"{unsigned}.{b64(signature)}"
    for attempt in range(12):
        try:
            result = request("POST", endpoint, document={
                "client_id": app["appId"], "scope": "https://api.loganalytics.io/.default",
                "grant_type": "client_credentials",
                "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
                "client_assertion": assertion
            }, form=True)
            if not result.get("access_token"):
                raise RotationError("Reader authentication returned no access token.")
            return
        except RotationError:
            if attempt == 11:
                raise
            time.sleep(5)


def publish_certificate(app, tenant, url, token, now):
    with tempfile.TemporaryDirectory(prefix="status-monitoring-reader-") as directory:
        root = Path(directory)
        root.chmod(0o700)
        key, certificate = root / "key.pem", root / "certificate.pem"
        command("openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes",
                "-keyout", str(key), "-out", str(certificate), "-days", "180",
                "-subj", f"/CN={APPLICATION_NAME}", "-addext", "basicConstraints=critical,CA:FALSE",
                "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=clientAuth")
        key.chmod(0o600)
        expiry = datetime.strptime(command("openssl", "x509", "-in", str(certificate), "-enddate", "-noout")
                                  .strip().removeprefix("notAfter="), "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
        name = PREFIX + str(uuid.uuid4())
        az_json("ad", "app", "credential", "reset", "--id", app["id"], "--append",
                "--cert", f"@{certificate}", "--display-name", name, "--end-date", expiry.strftime("%Y-%m-%dT%H:%M:%SZ"))
        registered = [entry for entry in credentials(app) if entry.get("displayName") == name]
        if len(registered) != 1 or timestamp(registered[0]["endDateTime"]) < expiry:
            raise RotationError("The new public certificate registration could not be verified; no secret was published.")
        verify_authentication(app, tenant, certificate, key, now)
        request("PUT", url, token, {
            "tags": {"managed-by": OWNER, "purpose": "status-monitoring-reader",
                     "application-id": app["appId"], "application-object-id": app["id"],
                     "credential-key-id": registered[0]["keyId"]},
            "properties": {
                "contentType": "application/x-pem-file",
                "value": certificate.read_text(encoding="ascii") + "\n" + key.read_text(encoding="ascii"),
                "attributes": {"enabled": True, "exp": int(expiry.timestamp())}
            }
        })


def rotate(app, tenant, vault, token, now):
    url = f"{ARM}{vault}/secrets/{SECRET_NAME}?api-version=2023-07-01"
    existing = request("GET", url, token, missing_ok=True)
    registered = credentials(app)
    renew = True
    if existing is not None:
        tags = existing.get("tags") or {}
        attributes = existing.get("properties", {}).get("attributes", {})
        if (tags.get("managed-by") != OWNER or tags.get("purpose") != "status-monitoring-reader"
                or tags.get("application-id") != app["appId"] or tags.get("application-object-id") != app["id"]
                or not tags.get("credential-key-id") or attributes.get("enabled") is not True
                or not isinstance(attributes.get("exp"), int)):
            raise RotationError("Existing reader secret has unexpected ownership/lifecycle metadata; explicit recovery is required.")
        expiry = datetime.fromtimestamp(attributes["exp"], timezone.utc)
        renew = not any(entry.get("keyId") == tags["credential-key-id"]
                        and (entry.get("displayName") or "").startswith(PREFIX)
                        and timestamp(entry["endDateTime"]) >= expiry for entry in registered
                        ) or expiry <= now + timedelta(days=30)
    if renew:
        publish_certificate(app, tenant, url, token, now)
        print("Published a verified reader certificate after registering its public key; previous public keys remain valid.")
    else:
        print("Retained the existing reader certificate; renewal is not due.")
    for entry in registered:
        if ((entry.get("displayName") or "").startswith(PREFIX)
                and timestamp(entry["endDateTime"]) < now - timedelta(days=7)):
            az_json("ad", "app", "credential", "delete", "--id", app["id"], "--key-id", entry["keyId"], "--cert")


def main():
    app, vault, tenant = discover()
    token = az_json("account", "get-access-token", "--resource", ARM)["accessToken"]
    rotate(app, tenant, vault, token, datetime.now(timezone.utc))


if __name__ == "__main__":
    try:
        main()
    except RotationError as error:
        raise SystemExit(str(error)) from None
