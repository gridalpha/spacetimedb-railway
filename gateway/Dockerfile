# Public gateway in front of SpacetimeDB.
FROM caddy:2-alpine

COPY gateway/Caddyfile /etc/caddy/Caddyfile
COPY gateway/entrypoint.sh /usr/local/bin/gateway-entrypoint.sh

RUN chmod 0755 /usr/local/bin/gateway-entrypoint.sh \
    && sh -n /usr/local/bin/gateway-entrypoint.sh \
    && caddy fmt --overwrite /etc/caddy/Caddyfile \
    && caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

ENTRYPOINT ["/usr/local/bin/gateway-entrypoint.sh"]
