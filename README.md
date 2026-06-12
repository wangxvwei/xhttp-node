# xhttp-node

Menu-driven helper script for preparing a VPS to run a 3x-ui xhttp node behind Nginx and Cloudflare.

This script is intentionally conservative:

- It does not write to the 3x-ui database.
- It prepares system packages, Cloudflare Origin certificates, Nginx routing, static site directories, backups, checks, and a shortcut command.
- It prints the parameters that should be filled in manually inside the 3x-ui panel.
- Nginx changes are backed up and tested before reload; failed tests roll back automatically.

Main flow:

```text
57330.xyz/              -> static site
57330.xyz/api/v1/sync   -> 127.0.0.1:10000 xhttp
panel.57330.xyz/xui/    -> 127.0.0.1:2070 3x-ui panel
```

Usage on a fresh Debian/Ubuntu VPS:

```bash
chmod +x outputs/xhttp-node.sh
sudo ./outputs/xhttp-node.sh
```

After installing the shortcut from the menu, run:

```bash
xhttp-node
```

Do not paste private keys, Cloudflare tokens, or VPS passwords into this repository.
