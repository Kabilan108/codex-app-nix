# codex-app-nix

Run [OpenAI Codex Desktop](https://openai.com/index/introducing-codex/) on Linux by converting the official macOS app.

Extracts the macOS DMG, rebuilds native modules (`better-sqlite3`, `node-pty`) for Linux, patches the Electron binary for NixOS, and bundles everything with a `.desktop` entry.

## Install

Requires the [Codex CLI](https://github.com/openai/codex) (`codex`) to be in your `PATH`.

### Nix (recommended)

```bash
nix run github:kabilan108/codex-app-nix
```

Or install persistently:

```bash
nix profile install github:kabilan108/codex-app-nix
```

To add as a flake input in your NixOS/home-manager config:

```nix
{
  inputs.codex-desktop.url = "github:kabilan108/codex-app-nix";

  # then in home.packages or environment.systemPackages:
  inputs.codex-desktop.packages.x86_64-linux.default
}
```

### Shell script (non-Nix)

```bash
# on NixOS, enter the dev shell first
nix develop

./install.sh
./codex-app/start.sh
```

The script downloads the DMG and Electron, builds native modules, and installs to `./codex-app/`. Works on any x86_64 Linux distro with Node 20+, Python 3, and standard build tools.

## How it works

1. Fetches the official Codex Desktop DMG and Electron v40.0.0 for Linux
2. Extracts `app.asar` from the macOS bundle
3. Removes macOS-only modules (`sparkle-darwin`)
4. Rebuilds `better-sqlite3` and `node-pty` against Electron's Node headers
5. Repacks the asar with Linux-native binaries
6. Patches the Electron binary with the correct dynamic linker and rpath (NixOS)
7. Serves the webview over a local HTTP server and launches Electron

## License

Apache-2.0
