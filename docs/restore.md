# Restoring Alvyo

What a restore of the cluster deployment looks like, by what was lost. For
the single server (`infra/compose.prod.yaml`) see
[operations.md](operations.md#scheduled-jobs-cron-as-the-deploy-user).

Only two things cannot be rebuilt: the **database** (accounts, routes,
journeys, hikes, comments …) and the **photos** (files, Alvyo keeps no
other copy). Everything else comes back by itself or from a job: the
manifests from the deployment repository (secrets encrypted with sops), the
images from GHCR, and the public data from the imports.

| What | Backup | Kept |
|---|---|---|
| Database | CronJob `db-backup`: `pg_dump -Fc` nightly at 02:15 to the volume `db-backups` | 14 days |
| Photos | Longhorn snapshots of the volume `photos`, daily at 02:30 | 7 days |
| OSM extract, graph | graph-refresh, graphhopper's `osm-fetch` init container | rebuilt |
| Trails, stops, huts | `tlm-import`, `places-import` | rebuilt |
| Official routes | `wanderland-import` | rebuilt |
| Heights (swissALTI3D) | `alti-import`, about 11 hours from scratch; geo.admin meanwhile | rebuilt |
| Rain, snow | `weather-precip`, `snow-cover` (minutes, hours) | rebuilt |
| Map tiles | the tile cache fills itself again | rebuilt |

Database and photos belong together: restore both from the same night, the
photos not older than the dump (the snapshot at 02:30 follows the dump at
02:15). Photos uploaded after the dump stay on disk unused; a photo deleted
in those 15 minutes shows as missing and can be deleted again. Photos the
dump marks as deleted are removed by the API within a minute.

Snapshots and dumps on the cluster's own storage do not survive the loss of
that storage: case 3 needs copies elsewhere (a Longhorn backup target or
another off-site copy), whose state is kept in the deployment repository.

## 1. A mistake: data deleted or broken, cluster fine

A bad migration, a bug that deleted rows, a wrong hand edit. Stop the API so
nothing writes meanwhile (the website shows errors until it is back). Flux
first: it reconciles every 10 minutes and would set the API back to one
replica in the middle of the restore.

```sh
flux suspend kustomization flux-system
kubectl -n alvyo scale deploy/api --replicas=0
```

**Database** from a dump of `db-backups`, in a helper pod with the database's
own image (`alvyo-postgis:<tag>`, the tag of `db-deployment.yaml`):

```sh
kubectl -n alvyo run pg-restore --rm -it --restart=Never \
  --image=ghcr.io/tellbow/alvyo-postgis:<tag> \
  --overrides='{"spec":{"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"db-backups"}}],"containers":[{"name":"pg-restore","image":"ghcr.io/tellbow/alvyo-postgis:<tag>","stdin":true,"tty":true,"command":["sh"],"env":[{"name":"PGPASSWORD","valueFrom":{"secretKeyRef":{"name":"alvyo-secret","key":"POSTGRES_PASSWORD"}}}],"volumeMounts":[{"name":"b","mountPath":"/backups"}]}]}}'
# inside:
ls -t /backups/*.dump | head
pg_restore -h db -U alvyo -d alvyo --clean --if-exists --no-owner /backups/alvyo-<stamp>.dump
```

A dump from before a migration is restored as it was; the API's `migrate`
init container applies the newer migrations when it starts. To go back to
an older release as well, suspend Flux's image update automation
(`flux suspend image update flux-system`), or it sets the newest tags
again, and set the older tags in the deployment repository.

**Photos** only if files were lost: in the Longhorn UI, the `photos`
volume, revert to the snapshot of the same night. The volume must not be in
use: with the API at 0 replicas, attach it in maintenance mode, revert,
detach. For a few files instead, create a volume from the snapshot and copy
them over with a helper pod as in case 3.

```sh
kubectl -n alvyo scale deploy/api --replicas=1
flux resume kustomization flux-system
```

Then check as in [Afterwards](#afterwards).

## 1b. Part of the data: a user's tours, or one of them

Someone deleted their journey, a route or a collection by mistake, or all
their tours are gone: copy them back from a dump without touching the rest
(feedback issue 74). The API keeps running.

1. **A dump of the state now**, in case the copy goes wrong:
   `kubectl -n alvyo create job --from=cronjob/db-backup db-backup-before-restore`.
2. **The dump into a scratch database** `alvyo_restore` on the same server,
   in the helper pod of case 1 (with `-it` and `sh`):

   ```sh
   ls -t /backups/*.dump | head
   createdb -h db -U alvyo alvyo_restore
   pg_restore -h db -U alvyo -d alvyo_restore --no-owner /backups/alvyo-<stamp>.dump
   ```

   Dumps from before migration 0048 (release after 1.17.0) do not restore
   `routes`: replace `pg_restore … -d alvyo_restore` with
   `pg_restore -f - /backups/alvyo-<stamp>.dump | sed 's/^CREATE FUNCTION public.shown_line(g public.geometry) RETURNS public.geometry/&\n    SET search_path = public/' | psql -h db -U alvyo -d alvyo_restore`.
3. **What would come back**, without writing anything; then the same with
   `--apply`:

   ```sh
   kubectl -n alvyo exec deploy/api -- /alvyo restore user <username>
   kubectl -n alvyo exec deploy/api -- /alvyo restore route|journey|collection <id>
   kubectl -n alvyo exec deploy/api -- /alvyo restore --apply user <username>
   ```

   A user's tours are their routes, journeys (with stages and stage routes)
   and collections, with what hangs on them: who they are shared with,
   collection items, likes, comments, photos, revisions, «Gewandert»,
   travel and reminders. Only missing rows are added, in one transaction;
   what is in the database now stays as it is. «left out» counts rows
   whose other end is gone (a like from a deleted account), whose place is
   taken (an item at a position of its collection used again since) and
   photos whose file is gone: those come back only after their files
   (case 1, «Photos», a few files from a snapshot), then run it again.
   The account itself is not restored: it must still exist.
4. **The scratch database away:** `dropdb -h db -U alvyo alvyo_restore`.

## 2. A node or disk fails

Nothing to restore: every Longhorn volume keeps three replicas on different
nodes and rebuilds the missing one. Pods on the failed node start elsewhere
(the `alti` volume and the API move together; `alti-import` follows the API).

## 3. The cluster or its storage is gone

Database, dumps, photos and snapshots are lost with the storage; this needs
the off-site copies and the sops key of the deployment repository.

1. **The cluster:** a new k3s with Longhorn, then Flux bootstrapped on the
   deployment repository, with the sops age key as the decryption secret
   its Kustomization names. Flux creates the namespace, the volumes (empty),
   the secrets and every workload.
2. **Stop the API** before it serves an empty database:
   `flux suspend kustomization flux-system`, then
   `kubectl -n alvyo scale deploy/api --replicas=0`.
3. **The database:** put the newest dump from the off-site copy on the new
   `db-backups` volume (restore it from the backup target, or `kubectl cp`
   into a helper pod mounting it) and restore it as in case 1. The empty
   database is fine for `pg_restore --clean --if-exists`.
4. **The photos:** restore the `photos` volume from the backup target
   (Longhorn UI, Backup, restore to a new volume, then bind the claim
   `photos` to it with `volumeName`, as `pvc.yaml` does for kept volumes).
   From a tar of `/data/photos` instead (the image of the API has no tar):

   ```sh
   kubectl -n alvyo run photos-restore --restart=Never --image=busybox:1.37 \
     --overrides='{"spec":{"securityContext":{"runAsUser":65532,"runAsGroup":65532,"fsGroup":65532},"volumes":[{"name":"p","persistentVolumeClaim":{"claimName":"photos"}}],"containers":[{"name":"photos-restore","image":"busybox:1.37","command":["sleep","3600"],"volumeMounts":[{"name":"p","mountPath":"/data/photos"}]}]}}'
   kubectl -n alvyo exec -i photos-restore -- tar -x -C /data < photos-<stamp>.tar
   kubectl -n alvyo delete pod photos-restore
   ```

5. **The API:** `kubectl -n alvyo scale deploy/api --replicas=1` and
   `flux resume kustomization flux-system`; it applies pending migrations
   first.
6. **The public data**, while the site already runs:
   - graphhopper's `osm-fetch` init container downloads the OSM extracts and
     imports the graph (up to 30 minutes; routing is down until then);
   - then `kubectl -n alvyo create job --from=cronjob/places-import places-import-restore`
     (needs the extract) and `--from=cronjob/tlm-import tlm-import-restore`;
   - `--from=cronjob/wanderland-import wanderland-import-restore`;
   - `--from=cronjob/alti-import alti-import-restore`: about 11 hours, longer
     than the job's 8 hour limit, so start it a second time (another name)
     when it stops; it goes on where it stopped. Until then heights come
     from geo.admin.
   - rain and snow come with their next scheduled runs.

## Afterwards

- `curl -s https://alvyo.tellbow.ch/api/v1/openapi.json | jq -r .info.version`
  is the release that should run;
- `kubectl -n alvyo logs deploy/api --since=10m` has no errors;
- log in, open one's routes and a route with photos; plan a leg (heights,
  hiking time);
- the counts look right: `psql -h db -U alvyo -d alvyo -c "SELECT count(*) FROM users"`
  (and `routes`, `photos`) in the helper pod of case 1.

## Testing a restore

A backup counts only once it has been restored. Monthly, or after changing
the backup setup: load the newest dump into a scratch database next to the
live one and count, as `infra/ops/restore-check.sh` does for the single
server. In the helper pod of case 1:

```sh
psql -h db -U alvyo -d postgres -c "DROP DATABASE IF EXISTS restore_check" -c "CREATE DATABASE restore_check"
pg_restore -h db -U alvyo -d restore_check --no-owner "$(ls -t /backups/*.dump | head -1)"
psql -h db -U alvyo -d restore_check -Atc "SELECT 'users: ' || count(*) FROM users UNION ALL SELECT 'routes: ' || count(*) FROM routes"
psql -h db -U alvyo -d postgres -c "DROP DATABASE restore_check"
```

For the photos, create a volume from the newest snapshot (or backup) and
look at a few files.
