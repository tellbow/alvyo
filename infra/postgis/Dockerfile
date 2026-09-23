# Multi-arch PostGIS: the official postgis/postgis image is amd64-only.
# postgres:18 already has the PGDG apt repository configured.
FROM postgres:18
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-18-postgis-3 \
 && rm -rf /var/lib/apt/lists/*
