# Multi-arch PostGIS: the official postgis/postgis image is amd64-only.
# postgres:18 already has the PGDG apt repository configured.
FROM postgres:18
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-18-postgis-3 \
 && rm -rf /var/lib/apt/lists/*
# pg_stat_statements: which queries take the time (migration 0037).
# No USER: the base image's entrypoint sets up the data directory as root,
# then runs the server as postgres (in the cluster the pod runs as 999 anyway).
# nosemgrep: dockerfile.security.missing-user.missing-user
CMD ["postgres", "-c", "shared_preload_libraries=pg_stat_statements"]
