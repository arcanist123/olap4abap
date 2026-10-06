#!/usr/bin/env python3
"""A logging proxy between an XMLA client (Excel) and the two XMLA servers: eMondrian and the SAP implementation.

Each backend gets its own local port; whatever arrives there (any method, any path) is forwarded to that backend's
URL and the answer goes back unchanged. Every exchange is printed as one line (method, SOAP action, request type or
MDX statement, status, time, size, rows/cells or the fault) and saved in full under logs/xmla-proxy/<start time>/ as
<n>-<backend>.request.txt and <n>-<backend>.response.txt (headers, a blank line, the body).

    python scripts/xmla-proxy.py                  # Mondrian on http://localhost:8081/, SAP on http://localhost:8082/
    python scripts/xmla-proxy.py --mondrian-port 9081 --sap-url http://vhcala4hci:50000/zzxxmla1?sap-client=001
    python scripts/xmla-proxy.py --backend release=8083=http://localhost:8090/emondrian/xmla   # a third server
    python scripts/xmla-proxy.py --sap-url "https://localhost:50001/zzxxmla1?sap-client=001" --insecure

In Excel: Data > Get Data > From Database > From Analysis Services, server http://localhost:8081/ (or 8082).
"""
import argparse
import datetime
import functools
import http.client
import http.server
import itertools
import pathlib
import re
import ssl
import sys
import threading
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer",
              "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}
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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mondrian-port", type=int, default=8081)
    parser.add_argument("--mondrian-url", default="http://localhost:8080/emondrian/xmla")
    parser.add_argument("--sap-port", type=int, default=8082)
    parser.add_argument("--sap-url", default="http://localhost:50000/zzxxmla1?sap-client=001")
    parser.add_argument("--bind", default="127.0.0.1", help="address to listen on (0.0.0.0 for other machines)")
    parser.add_argument("--backend", action="append", default=[], metavar="NAME=PORT=URL",
                        help="one more backend, e.g. release=8083=http://localhost:8090/emondrian/xmla")
    parser.add_argument("--insecure", action="store_true",
                        help="do not check the certificates of https backends (self-signed development systems)")
    args = parser.parse_args()

    log_dir = ROOT / "logs" / "xmla-proxy" / f"{datetime.datetime.now():%Y%m%d-%H%M%S}"
    log_dir.mkdir(parents=True, exist_ok=True)
    servers = []
    backends = [("mondrian", args.mondrian_port, args.mondrian_url), ("sap", args.sap_port, args.sap_url)]
    for extra in args.backend:
        name, port, target = extra.split("=", 2)
        backends.append((name, int(port), target))
    for backend, port, target in backends:
        server = http.server.ThreadingHTTPServer((args.bind, port), make_handler(backend, target, log_dir, args.insecure))
        servers.append(server)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"{backend:8} http://{'localhost' if args.bind == '127.0.0.1' else args.bind}:{port}/ -> {target}")
    print(f"logging to {log_dir}", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
