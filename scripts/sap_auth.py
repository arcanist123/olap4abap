"""Basic authentication of the test scripts at SAP's endpoint /zzxxmla1 (the ICF node takes personal logons,
docs/environment.md): the user and password are SAP_USER and SAP_PASSWORD of the git-ignored .env.sap, the logon
data of sapcli too; environment variables of the same names win over the file.

    import sap_auth
    sap_auth.install()          # every urllib request to SAP's host and port carries the logon, in one cookie session

install() puts a global urllib opener in place that adds the Authorization header only to requests to SAP's host and
port (SAP_ASHOST:SAP_PORT, also localhost and 127.0.0.1 with that port), so the reference server and SSAS get none,
keeps SAP's cookies, so a script is one security session, and logs it off at exit. http_credentials() is the same
logon for Playwright's browser context.
"""
import atexit
import base64
import os
import pathlib
import urllib.parse
import urllib.request
import http.cookiejar

ROOT = pathlib.Path(__file__).resolve().parent.parent


def env():
    """.env.sap, overridden by the environment."""
    values = {}
    path = ROOT / ".env.sap"
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    for key in ("SAP_ASHOST", "SAP_PORT", "SAP_CLIENT", "SAP_USER", "SAP_PASSWORD"):
        if os.environ.get(key):
            values[key] = os.environ[key]
    return values


def credentials():
    e = env()
    if not e.get("SAP_USER") or not e.get("SAP_PASSWORD"):
        raise SystemExit("SAP_USER and SAP_PASSWORD are needed in .env.sap (or the environment)")
    return e["SAP_USER"], e["SAP_PASSWORD"]


def http_credentials():
    """For Playwright: browser.new_page(http_credentials=sap_auth.http_credentials())."""
    user, password = credentials()
    return {"username": user, "password": password}


def is_sap(url):
    e = env()
    parts = urllib.parse.urlsplit(url)
    port = str(parts.port or (443 if parts.scheme == "https" else 80))
    hosts = {(e.get("SAP_ASHOST") or "").lower(), "localhost", "127.0.0.1"}
    return port == str(e.get("SAP_PORT") or "50000") and (parts.hostname or "").lower() in hosts


class BasicAuthHandler(urllib.request.BaseHandler):
    """Sends the logon with every request to SAP (no round trip for a 401 first) and remembers where to log off."""

    def __init__(self, user, password):
        self.authorization = "Basic " + base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
        self.used = set()

    def http_request(self, request):
        url = request.full_url
        if is_sap(url) and not request.has_header("Authorization"):
            request.add_unredirected_header("Authorization", self.authorization)
            parts = urllib.parse.urlsplit(url)
            client = urllib.parse.parse_qs(parts.query).get("sap-client", [env().get("SAP_CLIENT", "001")])[0]
            self.used.add((f"{parts.scheme}://{parts.netloc}/zzxxmla1", client))
        return request

    https_request = http_request


_opener = None


def install():
    """Once per script: SAP's requests through urllib.request.urlopen carry the logon."""
    global _opener
    if _opener:
        return _opener
    handler = BasicAuthHandler(*credentials())
    _opener = urllib.request.build_opener(handler, urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    urllib.request.install_opener(_opener)

    def logoff():
        for base, client in handler.used:
            try:
                _opener.open(f"{base}?sap-client={client}&sap-sessioncmd=logoff", timeout=30).read()
            except OSError:
                pass

    atexit.register(logoff)
    return _opener
