# SpacetimeDB standalone, prepared for Railway.
#
# The upstream image is used verbatim; this layer only adds the boot-time work
# Railway needs and that no environment variable can express:
#   * take ownership of the root-owned volume, then drop back to `spacetime`
#   * bind [::] so a peer on Railway's IPv6-only private network can reach it
#   * size the page pool from the cgroup instead of the 48-core host
FROM clockworklabs/spacetime:latest

USER root

# `setpriv` (util-linux) is what drops back to the unprivileged user after the
# volume chown. Assert it here so a missing binary fails the build in seconds
# instead of crash-looping a container.
RUN command -v setpriv >/dev/null \
    && test -x /opt/spacetime/spacetimedb-standalone \
    && id spacetime >/dev/null

COPY spacetimedb/entrypoint.sh /usr/local/bin/stdb-entrypoint.sh
RUN chmod 0755 /usr/local/bin/stdb-entrypoint.sh && bash -n /usr/local/bin/stdb-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/stdb-entrypoint.sh"]
