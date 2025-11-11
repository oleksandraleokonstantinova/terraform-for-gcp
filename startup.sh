#!/usr/bin/env bash
set -euo pipefail

retry() { local n=0; until "$@"; do n=$((n+1)); [ $n -ge 10 ] && exit 1; sleep 3; done; }

retry apt-get update -y
retry apt-get install -y nginx

systemctl enable nginx
systemctl restart nginx

cat >/var/www/html/index.html <<'HTML'
<html>
  <head><title>GCP MVP</title></head>
  <body style="font-family:Arial; text-align:center">
    <h1>It works!</h1>
    <p>Served by: $(hostname)</p>
  </body>
</html>
HTML

ss -lntp | grep ':80' || (echo "nginx not listening"; systemctl status nginx --no-pager; exit 1)
