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
- It prints the selected 3x-ui inbound and client-facing parameters after reading the VPS configuration.
- It reads the current 3x-ui panel port and web base path from the VPS when possible, instead of assuming a fixed panel backend port.
- If the 3x-ui panel backend path is `/`, the panel subdomain proxies `/` so absolute assets such as `/assets/...` keep working.
- The panel backend port, protocol, and public path are read from 3x-ui and are not normal editable prompts. Change them in 3x-ui first, then rerun this script.
- The script does not create or edit xhttp inbounds in 3x-ui. Create the xhttp inbound manually in the panel first.
- When configuring Nginx, the script reads existing 3x-ui xhttp inbounds from the VPS and uses the selected inbound's Path and local port.
- Nginx changes are backed up and tested before reload; failed tests roll back automatically.

Main flow:

```text
<domain>/                 -> static site directory from VPS config/input
<domain>/<xhttp-path>     -> 127.0.0.1:<xhttp-port>  (read from a 3x-ui xhttp inbound)
<panel-domain>/<path>     -> detected 3x-ui panel backend
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
