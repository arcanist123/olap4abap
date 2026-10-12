#!/usr/bin/env python3
"""A logging proxy between an XMLA client (Excel) and the XMLA servers: the eMondrian containers and the SAP
implementation.

Each backend gets its own local port; whatever arrives there (any method, any path) is forwarded to that backend's
URL and the answer goes back unchanged. Every exchange is printed as one line (method, SOAP action, request type or
MDX statement, status, time, size, rows/cells or the fault) and saved in full under logs/xmla-proxy/<start time>/ as
<n>-<backend>.request.txt and <n>-<backend>.response.txt (headers, a blank line, the body).

    python scripts/xmla-proxy.py                  # all four backends below
    python scripts/xmla-proxy.py --mondrian-port 9081 --sap-url http://vhcala4hci:50000/zzxxmla1?sap-client=001
    python scripts/xmla-proxy.py --backend other=8085=http://localhost:8095/emondrian/xmla   # one more server

By default:
    http://localhost:8081/  mondrian  container emondrian (8080): the reference, catalog ZFOODMART (our BW FoodMart)
    http://localhost:8082/  sap       the SAP implementation
    http://localhost:8083/  git       container emondrian-git (8091): the same build, catalog FoodMart (the sample)
    http://localhost:8084/  release   container emondrian-release (8090): the released eMondrian
A backend that is not running answers 502 Bad Gateway.

--auth-probe PORT adds a port that forwards nothing: it answers every request with 401 and the --challenge headers
and prints how the client authenticated (no header, Basic and the user, Negotiate/NTLM, or a Bearer token and its
claims). It shows whether Excel can be sent to Entra ID by a custom XMLA endpoint:
    python scripts/xmla-proxy.py --https --auth-probe 8085                       # a Bearer challenge only
    python scripts/xmla-proxy.py --https --auth-probe 8085 --challenge "Bearer authorization_uri=..." --challenge Basic
    python scripts/xmla-proxy.py --sap-url "https://localhost:50001/zzxxmla1?sap-client=001" --insecure

In Excel: Data > Get Data > From Database > From Analysis Services, server http://localhost:8081/ (or 8082, ...).

With --https the same ports speak https instead of http (https://localhost:8081/, ...). The certificate is --cert and
--key, or else a self-signed one for localhost (and this machine's name and the --bind address) that the proxy makes
with openssl under logs/xmla-proxy/tls/ on first use and reuses afterwards. Excel (MSOLAP) only connects when Windows
trusts it; import it once into the current user's trusted root certificates:
    python scripts/xmla-proxy.py --https
    certutil -user -addstore Root logs/xmla-proxy/tls/cert.pem
"""
import argparse
import base64
import datetime
import functools
import http.client
import http.server
import itertools
import json
import pathlib
import re
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer",
              "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}
# the challenge Entra-protected APIs answer with: the authority to get a token from and the resource it is for
DEFAULT_CHALLENGE = ('Bearer authorization_uri="https://login.microsoftonline.com/common/oauth2/authorize", '
                     'resource_id="api://olap4abap"')
counter = itertools.count(1)
print_lock = threading.Lock()


def text_of(body):
    return body.decode("utf-8", errors="replace")


def first(pattern, text):
    match = re.search(pattern, text, re.S)
    return match.group(1).strip() if match else None


def one_line(text, width):
    text = re.sub(r"\s+", " ", text)
    return text if len(text) <= width else text[:width - 3] + "..."


def describe_request(body):
    """The request type of a Discover or the statement of an Execute, plus the session handling."""
    text = text_of(body)
    session = ("BeginSession" if "BeginSession" in text else "EndSession" if "EndSession" in text
               else "Session" if re.search(r"<\w*:?Session\b", text) else "")
    if "<Execute" in text:
        statement = first(r"<Statement>(.*?)</Statement>", text) or ""
        what = "Execute " + one_line(statement.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&"), 160)
    elif "<Discover" in text:
        what = "Discover " + (first(r"<RequestType>(.*?)</RequestType>", text) or "?")
        restrictions = first(r"<RestrictionList>(.*?)</RestrictionList>", text)
        if restrictions:
            what += " " + one_line(re.sub(r"<(\w+)>([^<]*)</\1>", r"\1=\2", restrictions), 80)
    elif text.strip():
        what = one_line(text, 80)
    else:
        what = "(no body)"
    return what + (f" [{session}]" if session else "")


def describe_response(body):
    text = text_of(body)
    fault = first(r"<faultstring>(.*?)</faultstring>", text)
    error = first(r'<Error\b[^>]*Description="([^"]*)"', text)
    if fault or error:
        return "FAULT " + one_line(" / ".join(x for x in (fault, error) if x), 200)
    parts = []
    for tag in ("row", "Tuple", "Cell"):
        n = len(re.findall(rf"<{tag}[\s>/]", text))
        if n:
            parts.append(f"{n} {tag.lower()}s")
    cell_error = first(r'<Error[^>]*ErrorCode="[^"]*"[^>]*Description="([^"]*)"', text)
    if cell_error:
        parts.append("cell error: " + one_line(cell_error, 100))
    return ", ".join(parts) or "ok"


def save(directory, name, start_line, headers, body):
    with open(directory / name, "wb") as f:
        f.write((start_line + "\n" + "".join(f"{k}: {v}\n" for k, v in headers) + "\n").encode("utf-8"))
        f.write(body)


def find_openssl():
    found = shutil.which("openssl")
    if found:
        return found
    # Git for Windows brings one that is not on the PATH of cmd or PowerShell
    for candidate in (r"C:\Program Files\Git\mingw64\bin\openssl.exe", r"C:\Program Files\Git\usr\bin\openssl.exe"):
        if pathlib.Path(candidate).exists():
            return candidate
    sys.exit("xmla-proxy: --https needs openssl (on the PATH or from Git for Windows), or --cert and --key")


def self_signed_certificate(bind):
    """A self-signed certificate for localhost, made once under logs/xmla-proxy/tls/ and reused."""
    directory = ROOT / "logs" / "xmla-proxy" / "tls"
    cert, key = directory / "cert.pem", directory / "key.pem"
    if cert.exists() and key.exists():
        return cert, key
    directory.mkdir(parents=True, exist_ok=True)
    names = ["DNS:localhost", "IP:127.0.0.1", "IP:::1", f"DNS:{socket.gethostname()}"]
    if bind not in ("127.0.0.1", "0.0.0.0", "localhost"):
        names.append(f"IP:{bind}" if re.fullmatch(r"[\d.]+|[\da-fA-F:]+", bind) else f"DNS:{bind}")
    subprocess.run([find_openssl(), "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "825",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=" + ",".join(names),
                    "-addext", "extendedKeyUsage=serverAuth", "-keyout", str(key), "-out", str(cert)],
                   check=True, capture_output=True)
    print(f"made a self-signed certificate {cert} for {', '.join(names)}")
    return cert, key


def make_handler(backend, target, log_dir, insecure=False):
    url = urllib.parse.urlsplit(target)
    path = url.path + ("?" + url.query if url.query else "")
    if url.scheme == "https":
        # a development system's certificate is self-signed: --insecure skips its check
        context = ssl._create_unverified_context() if insecure else None
        connection_class = functools.partial(http.client.HTTPSConnection, context=context)
    else:
        connection_class = http.client.HTTPConnection

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):
            pass

        def handle(self):
            try:
                super().handle()
            except ssl.SSLError as e:
                # with --https: a client that speaks plain http or does not trust the certificate
                with print_lock:
                    print(f"{datetime.datetime.now():%H:%M:%S}       {backend:8} TLS failed: {e.reason or e}", flush=True)

        def read_body(self):
            if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
                body = b""
                while True:
                    size = int(self.rfile.readline().split(b";")[0].strip(), 16)
                    if size == 0:
                        while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                            pass
                        return body
                    body += self.rfile.read(size)
                    self.rfile.readline()
            return self.rfile.read(int(self.headers.get("Content-Length") or 0))

        def forward(self):
            n = next(counter)
            body = self.read_body()
            headers = [(k, v) for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP]
            save(log_dir, f"{n:04d}-{backend}.request.txt", f"{self.command} {self.path} -> {target}", headers, body)
            started = time.monotonic()
            try:
                upstream = connection_class(url.hostname, url.port, timeout=900)
                upstream.putrequest(self.command, path, skip_host=True, skip_accept_encoding=True)
                upstream.putheader("Host", url.netloc)
                for k, v in headers:
                    upstream.putheader(k, v)
                upstream.putheader("Content-Length", str(len(body)))
                upstream.endheaders(body)
                response = upstream.getresponse()
                status, reason = response.status, response.reason
                response_headers = [(k, v) for k, v in response.getheaders() if k.lower() not in HOP_BY_HOP]
                response_body = response.read()
                upstream.close()
            except OSError as e:
                status, reason, response_headers = 502, "Bad Gateway", [("Content-Type", "text/plain")]
                response_body = f"xmla-proxy: {target} not reachable: {e}".encode("utf-8")
            elapsed = time.monotonic() - started
            save(log_dir, f"{n:04d}-{backend}.response.txt", f"{status} {reason}", response_headers, response_body)
            self.send_response(status, reason)
            for k, v in response_headers:
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(response_body)
            action = (self.headers.get("SOAPAction") or "").strip('"').rsplit(":", 1)[-1]
            line = (f"{datetime.datetime.now():%H:%M:%S} #{n:04d} {backend:8} {self.command} {action:8} "
                    f"{describe_request(body)}\n{'':23}-> {status} {elapsed * 1000:7.0f} ms {len(response_body):9} B  "
                    f"{describe_response(response_body)}")
            with print_lock:
                print(line, flush=True)

        do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = forward

    return Handler


def jwt_claims(token):
    """The claims of a JWT that tell who issued it for whom (no signature check: only to see what a client sends)."""
    try:
        payload = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (IndexError, ValueError):
        return "not a JWT"
    keys = ("aud", "iss", "appid", "azp", "app_displayname", "scp", "roles", "upn", "unique_name", "tid")
    return ", ".join(f"{k}={claims[k]}" for k in keys if k in claims)


def make_auth_probe(challenges, log_dir):
    """Forwards nothing: answers every request with 401 and the challenges, and shows how the client authenticates."""

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):
            pass

        def probe(self):
            n = next(counter)
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            authorization = self.headers.get("Authorization") or ""
            scheme, _, credentials = authorization.partition(" ")
            if not authorization:
                seen = "no Authorization header"
            elif scheme.lower() == "bearer":
                seen = f"Bearer token: {jwt_claims(credentials)}"
            elif scheme.lower() == "basic":
                user = text_of(base64.b64decode(credentials + "==")).partition(":")[0]
                seen = f"Basic, user {user}"
            else:
                seen = f"{scheme} ({len(credentials)} characters)"
            # the credentials themselves are not saved
            headers = [(k, scheme + " <redacted>" if k.lower() == "authorization" else v) for k, v in self.headers.items()]
            save(log_dir, f"{n:04d}-auth-probe.request.txt", f"{self.command} {self.path}", headers, body)
            response_body = f"xmla-proxy auth probe: {seen}\n".encode("utf-8")
            self.send_response(401, "Unauthorized")
            for challenge in challenges:
                self.send_header("WWW-Authenticate", challenge)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(response_body)
            action = (self.headers.get("SOAPAction") or "").strip('"').rsplit(":", 1)[-1]
            with print_lock:
                print(f"{datetime.datetime.now():%H:%M:%S} #{n:04d} probe    {self.command} {action:8} "
                      f"{describe_request(body)}\n{'':23}-> 401  {seen}  "
                      f"(User-Agent: {self.headers.get('User-Agent', '-')})", flush=True)

        do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = probe

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mondrian-port", type=int, default=8081)
    parser.add_argument("--mondrian-url", default="http://localhost:8080/emondrian/xmla")
    parser.add_argument("--sap-port", type=int, default=8082)
    parser.add_argument("--sap-url", default="http://localhost:50000/zzxxmla1?sap-client=001")
    parser.add_argument("--git-port", type=int, default=8083)
    parser.add_argument("--git-url", default="http://localhost:8091/emondrian/xmla")
    parser.add_argument("--release-port", type=int, default=8084)
    parser.add_argument("--release-url", default="http://localhost:8090/emondrian/xmla")
    parser.add_argument("--bind", default="127.0.0.1", help="address to listen on (0.0.0.0 for other machines)")
    parser.add_argument("--backend", action="append", default=[], metavar="NAME=PORT=URL",
                        help="one more backend, e.g. other=8085=http://localhost:8095/emondrian/xmla")
    parser.add_argument("--insecure", action="store_true",
                        help="do not check the certificates of https backends (self-signed development systems)")
    parser.add_argument("--https", action="store_true",
                        help="listen with https instead of http (a self-signed certificate unless --cert and --key)")
    parser.add_argument("--cert", help="certificate (PEM) for --https")
    parser.add_argument("--key", help="private key (PEM) of --cert")
    parser.add_argument("--auth-probe", type=int, metavar="PORT",
                        help="also listen on PORT, answer everything with 401 and the --challenge headers, and show "
                             "how the client authenticates (forwards nothing)")
    parser.add_argument("--challenge", action="append", metavar="HEADER",
                        help="a WWW-Authenticate header of --auth-probe (repeatable); default: " + DEFAULT_CHALLENGE)
    args = parser.parse_args()
    tls = None
    if args.https:
        if bool(args.cert) != bool(args.key):
            parser.error("--cert and --key go together")
        cert, key = (args.cert, args.key) if args.cert else self_signed_certificate(args.bind)
        tls = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        tls.load_cert_chain(cert, key)
        print(f"https with certificate {cert}")

    log_dir = ROOT / "logs" / "xmla-proxy" / f"{datetime.datetime.now():%Y%m%d-%H%M%S}"
    log_dir.mkdir(parents=True, exist_ok=True)
    servers = []
    backends = [("mondrian", args.mondrian_port, args.mondrian_url), ("sap", args.sap_port, args.sap_url),
                ("git", args.git_port, args.git_url), ("release", args.release_port, args.release_url)]
    for extra in args.backend:
        name, port, target = extra.split("=", 2)
        backends.append((name, int(port), target))
    handlers = [(backend, port, target, make_handler(backend, target, log_dir, args.insecure))
                for backend, port, target in backends]
    if args.auth_probe:
        challenges = args.challenge or [DEFAULT_CHALLENGE]
        handlers.append(("probe", args.auth_probe, "401 " + " | ".join(challenges), make_auth_probe(challenges, log_dir)))
    for backend, port, target, handler in handlers:
        server = http.server.ThreadingHTTPServer((args.bind, port), handler)
        if tls:
            # the handshake runs in the request's thread, so a client that stalls in it blocks no other client
            server.socket = tls.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        servers.append(server)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"{backend:8} {'https' if tls else 'http'}://{'localhost' if args.bind == '127.0.0.1' else args.bind}:{port}/ -> {target}")
    print(f"logging to {log_dir}", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
