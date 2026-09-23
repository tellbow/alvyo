#!/bin/sh
# Nightly backup: the database (custom format, kept for 14 days) and the
# photos (tar, the last 3 kept).
# Cron: 15 2 * * *  /srv/odysgeh/infra/ops/backup.sh
# Copy ./backups off the machine as well (e.g. rclone to object storage).
set -eu
cd "$(dirname "$0")/.."
mkdir -p backups
stamp=$(date +%Y-%m-%dT%H%M)
file="backups/odysgeh-$stamp.dump"
docker compose -f compose.prod.yaml exec -T db pg_dump -U odysgeh -Fc odysgeh > "$file.tmp"
mv "$file.tmp" "$file"
find backups -name 'odysgeh-*.dump' -mtime +14 -delete
echo "backup: $file ($(du -h "$file" | cut -f1))"

# docker cp streams a tar, so the (shell-less) api image needs no tar.
photos="backups/photos-$stamp.tar"
docker compose -f compose.prod.yaml cp api:/data/photos - > "$photos.tmp"
mv "$photos.tmp" "$photos"
ls -t backups/photos-*.tar | tail -n +4 | xargs -r rm --
echo "backup: $photos ($(du -h "$photos" | cut -f1))"
