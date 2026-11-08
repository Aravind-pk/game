# North Gate — playable web build

Godot 4.5.1 web export, single-threaded, Compatibility renderer. The engine (`index.wasm`) and data
pack (`index.pck`) are split into 9 MB chunks (`*.partN.wasm`). A small loader in the page puts
them back together while they download.

- `index.html`: standalone page. Serve this folder with any static server, for example
  `python3 -m http.server`, then open `index.html`.
- `artifact.html`: the same game as a page fragment for hosts that supply their own document
  skeleton. The canvas fits inside the phone's safe area.

Rebuild: see "Web build" in the repository README.
