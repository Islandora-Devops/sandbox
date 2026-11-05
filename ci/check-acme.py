#!/usr/bin/env python3
"""Check that a Traefik ACME store contains usable certificates and keys."""
import base64
import json
import os
import ssl
import sys
import tempfile
import time


def matches(pattern, hostname):
    pattern = pattern.lower()
    hostname = hostname.lower()
    if pattern.startswith("*."):
        return hostname.count(".") == pattern.count(".") and hostname.endswith(pattern[1:])
    return pattern == hostname

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        store = json.load(source)
    hosts = set(sys.argv[2:])
    if not hosts:
        raise ValueError("no hostnames supplied")
    with tempfile.TemporaryDirectory() as directory:
        cert_path = os.path.join(directory, "certificate.pem")
        key_path = os.path.join(directory, "key.pem")
        for entry in store.get("letsencrypt", {}).get("Certificates", []) or []:
            try:
                for path, field in ((cert_path, "certificate"), (key_path, "key")):
                    data = base64.b64decode(entry[field], validate=True)
                    with open(path, "wb") as output:
                        os.chmod(path, 0o600)
                        output.write(data)
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(cert_path, key_path)
                certificate = ssl._ssl._test_decode_cert(cert_path)
                if (ssl.cert_time_to_seconds(certificate["notBefore"]) > time.time()
                        or ssl.cert_time_to_seconds(certificate["notAfter"]) <= time.time() + 300):
                    continue
                for host in list(hosts):
                    if any(kind == "DNS" and matches(value, host)
                           for kind, value in certificate.get("subjectAltName", ())):
                        hosts.remove(host)
            except (ValueError, KeyError, ssl.SSLError, OSError):
                continue
    if hosts:
        raise ValueError("no valid certificate and matching key for " + ", ".join(sorted(hosts)))
except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
    sys.exit(f"ACME store check failed: {error}")
