"""Package the Godot web export for hosts with a per-file size limit.

Splits index.wasm and index.pck into chunks and injects a tiny fetch shim into
index.html that reassembles them when the Godot loader requests the originals.

    python tools/web/package_web.py build/web build/web_split [--chunk-mb 9]
"""

import math
import os
import shutil
import sys

BIG = {"index.wasm": "application/wasm", "index.pck": "application/octet-stream"}

SHIM = """<script>
// Reassemble chunked engine/pack files (host limits single files to 15 MB).
(function () {
  var PARTS = %(parts)s;
  var TYPES = %(types)s;
  var status = null;
  var realFetch = window.fetch.bind(window);
  window.fetch = async function (input, init) {
    var url = typeof input === "string" ? input : input.url;
    var clean = url.split("?")[0];
    var name = Object.keys(PARTS).find(function (k) { return clean.endsWith(k); });
    if (!name) return realFetch(input, init);
    var bufs = [];
    for (var i = 0; i < PARTS[name]; i++) {
      status = status || document.getElementById("status-notice");
      if (status) { status.textContent = "Loading " + name + " (" + (i + 1) + "/" + PARTS[name] + ")"; status.style.display = "block"; }
      var r = await realFetch(name + ".part" + i + ".wasm");
      if (!r.ok) throw new Error("Missing chunk " + name + ".part" + i);
      bufs.push(await r.arrayBuffer());
    }
    if (status) status.style.display = "none";
    var blob = new Blob(bufs, { type: TYPES[name] });
    return new Response(blob, { status: 200, headers: { "Content-Type": TYPES[name], "Content-Length": String(blob.size) } });
  };
})();
</script>
"""


def main(src, dst, chunk_mb=9.0):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    chunk = int(chunk_mb * 1024 * 1024)
    parts = {}
    for f in os.listdir(src):
        p = os.path.join(src, f)
        if f in BIG:
            data = open(p, "rb").read()
            n = math.ceil(len(data) / chunk)
            for i in range(n):
                open(os.path.join(dst, f"{f}.part{i}.wasm"), "wb").write(data[i * chunk:(i + 1) * chunk])
            parts[f] = n
        elif f != "index.html":
            shutil.copy(p, dst)
    html = open(os.path.join(src, "index.html"), encoding="utf-8").read()
    import json
    shim = SHIM % {"parts": json.dumps(parts), "types": json.dumps(BIG)}
    html = html.replace('<script src="index.js"></script>', shim + '<script src="index.js"></script>', 1)
    assert shim in html, "could not find the index.js script tag"
    html = html.replace("<title>North Gate</title>", "<title>North Gate</title>", 1)
    open(os.path.join(dst, "index.html"), "w", encoding="utf-8").write(html)
    open(os.path.join(dst, "artifact.html"), "w", encoding="utf-8").write(artifact_page(html))
    print("parts:", parts)


LOADER_CSS = """
:root { --bg: #0f1722; --panel: #18222d; --ink: #ffffff; --muted: #a9b6c3; --amber: #f5c56b;
  --line: #3a4757; color-scheme: dark; }
html, body { height: 100%; }
body { background: var(--bg) !important; color: var(--ink); }
#status { background: var(--bg) !important; font-family: "Barlow", system-ui, sans-serif; gap: 18px; }
#status-progress { accent-color: var(--amber); }
#status-notice { color: var(--muted) !important; background: transparent !important; border: 0 !important;
  font: 600 15px/1.4 "Barlow", system-ui, sans-serif; text-align: center; padding: 0 16px; }
#ng-brand { font: 800 40px/1 "Barlow Condensed", "Arial Narrow", sans-serif; letter-spacing: .04em;
  text-transform: uppercase; color: var(--ink); }
#ng-brand span { color: var(--amber); }
"""


def artifact_page(html):
    """Godot's page as a fragment for a host that supplies the document skeleton."""
    import re
    style = re.search(r"<style>(.*?)</style>", html, re.S).group(1)
    body = re.search(r"<body>(.*)</body>", html, re.S).group(1)
    body = body.replace('<div id="status">', '<div id="status">\n<div id="ng-brand"><span>&#9650;</span> North Gate</div>', 1)
    return ("<title>North Gate</title>\n"
            '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow:wght@600&family=Barlow+Condensed:wght@800&display=swap">\n'
            "<style>" + style + LOADER_CSS + "</style>\n" + body)


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    mb = float(sys.argv[sys.argv.index("--chunk-mb") + 1]) if "--chunk-mb" in sys.argv else 9.0
    main(a[0], a[1], mb)
