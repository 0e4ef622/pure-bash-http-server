pure-bash-http-server
=====================

why do i do these things to myself

Requires `socat` so that it can listen on a port. `mime.types` was copied from `/etc/mime.types` with the type
for markdown added.

Do not use to serve large files, as it will read the entire file into memory before serving it.
