# Tools for preparing reference data: OSM extracts (osmium) and swisstopo
# vector data (GDAL/ogr2ogr); MeteoSwiss's radar (HDF5) and forecasts (GRIB2)
# for the rain on the map (weather-precip.py).
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends osmium-tool gdal-bin postgresql-client curl unzip ca-certificates \
    python3 python3-gdal python3-h5py python3-numpy python3-scipy python3-eccodes python3-psycopg \
 && rm -rf /var/lib/apt/lists/*
# The cluster has no IPv6 route out, and Python tries a name's addresses one
# after the other (data.geo.admin.ch answers IPv6 first): IPv4 first.
RUN echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
# Not root: the scripts write only below /data (owned by uid 1000, as for
# GraphHopper) and to the database.
RUN useradd --uid 1000 --user-group --create-home --home-dir /home/alvyo alvyo \
 && mkdir /work && chown alvyo:alvyo /work
WORKDIR /work
# Compose mounts ./data-import over /scripts in development; in production
# (e.g. Kubernetes jobs) the image carries them.
COPY *.sh *.py border.geojson /scripts/
USER 1000:1000
