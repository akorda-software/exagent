"""Read back HexDocs bytes and ensure the existing package was not replaced."""
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request

# HexDocs inserts this exact analytics block in HTML before </head>.
# Preserve every other byte; unknown transformations must fail comparison.
HEXDOCS_ANALYTICS = (b'<script async defer src="https://s.hexdocs.pm/js/script.js"></script>'
                    b'<script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},'
                    b'plausible.init=plausible.init||function(i){plausible.o=i||{}};'
                    b'plausible.init({endpoint:"https://s.hexdocs.pm/api/event"})</script>')
EXDOC_FOOTER = (b'<a href="https://github.com/elixir-lang/ex_doc" title="ExDoc" '
                b'target="_blank" rel="help noopener" translate="no">ExDoc</a>')
HEXDOCS_FOOTER = EXDOC_FOOTER.replace(b'rel="help noopener"', b'rel="help noopener nofollow"')


def documentation_bytes(name, value):
    if name.endswith(".html") and value.count(HEXDOCS_ANALYTICS) == 1:
        value = value.replace(HEXDOCS_ANALYTICS, b"", 1)
    if name.endswith(".html") and value.count(HEXDOCS_FOOTER) == 1:
        value = value.replace(HEXDOCS_FOOTER, EXDOC_FOOTER, 1)
    return value


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "ExAgent-documentation-readback"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def verify(metadata, root):
    version = metadata["version"]
    package = fetch(f"https://repo.hex.pm/tarballs/exagent-{version}.tar")
    if hashlib.sha256(package).hexdigest() != metadata["hex_checksum"]:
        raise ValueError("published package bytes changed")

    names = ["index.html", "welcome.html", "documentation.html", "agents.md", "llms.txt", "readme.html"]
    names += [str(path.relative_to(root)) for path in root.glob("dist/sidebar_items-*.js")]
    if len(names) == 6:
        raise ValueError("missing generated sidebar navigation")
    pending = {name: (root / name).read_bytes() for name in names}
    errors = {}
    for attempt in range(12):
        for name in list(pending):
            try:
                actual = fetch(f"https://hexdocs.pm/exagent/{version}/{name}?docs={metadata['docs_commit']}")
                if documentation_bytes(name, actual) == pending[name]:
                    del pending[name]
                    errors.pop(name, None)
                else:
                    errors[name] = "bytes differ from generated documentation"
            except (OSError, urllib.error.URLError) as error:
                errors[name] = str(error)
        if not pending:
            print(json.dumps({"version": version, "docs_commit": metadata["docs_commit"],
                              "verified_pages": names, "hex_checksum": metadata["hex_checksum"],
                              "html_normalization": "exact HexDocs analytics block and ExDoc footer nofollow only"}))
            return
        if attempt < 11:
            time.sleep(5)
    raise ValueError("HexDocs readback failed: " + json.dumps(errors))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: documentation_publication.py METADATA.json GENERATED_DOCS")
    verify(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]))
