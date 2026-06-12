# xhttp-node

Menu-driven helper script for preparing a VPS to run a 3x-ui xhttp node behind Nginx and Cloudflare.

## One-Command Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wangxvwei/xhttp-node/main/install.sh)
```

If this repository is private, the command above will not work from a fresh VPS unless GitHub authentication is provided. For a 3x-ui-style public one-command installer, make the repository public first.

This script is intentionally conservative:

- It does not write to the 3x-ui database.
- It prepares system packages, Cloudflare Origin certificates, Nginx routing, static site directories, backups, checks, and a shortcut command.
- It prints the parameters that should be filled in manually inside the 3x-ui panel.
- It reads the current 3x-ui panel port and web base path from the VPS when possible, instead of assuming a fixed panel backend port.
- If the 3x-ui panel backend path is `/`, the panel subdomain proxies `/` so absolute assets such as `/assets/...` keep working.
- Nginx changes are backed up and tested before reload; failed tests roll back automatically.

Main flow:

```text
example.com/              -> static site
example.com/api/v1/sync   -> 127.0.0.1:10000 xhttp
panel.example.com/xui/    -> detected 3x-ui panel backend
```

Usage on a fresh Debian/Ubuntu VPS:

```bash
chmod +x xhttp-node.sh
sudo ./xhttp-node.sh
```

After installing the shortcut from the menu, run:

```bash
xhttp-node
```

Do not paste private keys, Cloudflare tokens, or VPS passwords into this repository.
