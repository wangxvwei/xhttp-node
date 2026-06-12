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
- When configuring Nginx, the script reads existing 3x-ui xhttp inbounds from the VPS and can proxy all, multiple selected, or one selected inbound by Path and local port.
- It can also read the enabled 3x-ui subscription service and add a panel-domain reverse proxy such as `https://panel.example.com/dingyue/ -> http://127.0.0.1:2096/dingyue/`.
- For subscription reverse proxy, the script prints the public URI that should be filled into 3x-ui's reverse proxy URI field. It still does not write to the 3x-ui database.
- The default static site includes a custom `404.html` with a home button so meaningless non-xhttp paths do not expose the default Nginx error page.
- Nginx changes are backed up and tested before reload; failed tests roll back automatically.

Main flow:

```text
<domain>/                 -> static site directory from VPS config/input
<domain>/<xhttp-path>     -> 127.0.0.1:<xhttp-port>  (read from a 3x-ui xhttp inbound)
<panel-domain>/<path>     -> detected 3x-ui panel backend
<panel-domain>/<sub-path> -> detected 3x-ui subscription backend
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
