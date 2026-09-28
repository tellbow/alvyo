# Tools for preparing reference data: OSM extracts (osmium) and swisstopo
# vector data (GDAL/ogr2ogr).
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends osmium-tool gdal-bin postgresql-client curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
# Compose mounts ./data-import over /scripts in development; in production
# (e.g. Kubernetes jobs) the image carries them.
COPY *.sh border.geojson /scripts/
