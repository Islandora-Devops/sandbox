#!/usr/bin/env python3
"""Exercise the sandbox file-provider routers with a captcha-protect checkout."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True, stderr=subprocess.STDOUT)


repo = pathlib.Path(__file__).resolve().parent.parent
plugin = pathlib.Path(sys.argv[1]).resolve()
container = docker(
    "create", "traefik:v3.7.16",
    "--entrypoints.https.address=:8443",
    "--providers.file.directory=/dynamic",
    "--experimental.localPlugins.captcha-protect.moduleName=github.com/libops/captcha-protect",
    "--api.insecure=true",
).strip()
try:
    with tempfile.TemporaryDirectory() as tmp:
        for source in (repo / "rootfs/opt/sandbox/traefik").glob("*.yml"):
            config = source.read_text().replace('{{ env "DOMAIN" }}', "sandbox.example.org")
            config = config.replace('{{ env "CAPTCHA_SECRET" }}', "routing-test-secret")
            # Use Traefik's default test certificate without contacting ACME.
            config = config.replace("tls:\n        certResolver: letsencrypt", "tls: {}")
            pathlib.Path(tmp, source.name).write_text(config)
        docker("cp", tmp + "/.", container + ":/dynamic")
    with tempfile.TemporaryDirectory() as tmp:
        target = pathlib.Path(tmp, "plugins-local/src/github.com/libops/captcha-protect")
        shutil.copytree(plugin, target, ignore=shutil.ignore_patterns(".git"))
        docker("cp", str(pathlib.Path(tmp, "plugins-local")), container + ":/")
    docker("start", container)
    for attempt in range(30):
        try:
            raw = docker("exec", container, "wget", "-qO-", "http://localhost:8080/api/rawdata")
            if 'captcha-protected@file' in raw:
                break
        except subprocess.CalledProcessError:
            pass
        time.sleep(1)
    else:
        raise AssertionError("File-provider routers did not load")
    routers = json.loads(raw)["routers"]
    for name in ("captcha-protected", "drupal", "cantaloupe", "fcrepo"):
        router = routers[name + "@file"]
        assert router["status"] == "enabled", router
        if name != "captcha-protected":
            assert router["parentRefs"] == ["captcha-protected@file"], router
    for host, path in (
        ("sandbox.example.org", "/node/20"),
        ("sandbox.example.org", "/cantaloupe/iiif/2/test/info.json"),
        ("sandbox.example.org", "/cantaloupe/iiif/2/test/full/max/0/default.jpg"),
        ("sandbox.example.org", "/node/20?_format=jsonld"),
        ("fcrepo.sandbox.example.org", "/fcrepo/rest/test/fcr:metadata"),
    ):
        body = docker("exec", container, "wget", "-qO-", "--no-check-certificate",
                      "--header", "Host: " + host, "https://localhost:8443" + path)
        assert "/captcha-protect-poj.js" in body, (host, path, body)
    print("Drupal, IIIF, and Fedora all receive the parent captcha challenge")
except BaseException as error:
    if isinstance(error, subprocess.CalledProcessError):
        print(error.output, file=sys.stderr)
    print(docker("logs", container), file=sys.stderr)
    raise
finally:
    docker("rm", "-f", container)
