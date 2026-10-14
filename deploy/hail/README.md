# Hail PLC read-replica deployment

This runs the official read-only `plc-replica` behind Caddy with durable SQLite storage. All PLC writes continue to use `https://plc.directory`.

## Host requirements

- A Linux VPS with Docker Compose
- At least 500 GB of NVMe storage for the replica and operational headroom
- 4–8 CPU cores and 8–16 GB RAM
- TCP ports 80 and 443 and UDP port 443 open
- A DNS A/AAAA record for the replica hostname

SQLite is the initial deployment profile because upstream reports faster backfill than PostgreSQL. Run one replica process against the database directory.

## Start and backfill

```bash
cd deploy/hail
cp .env.example .env
# Set REPLICA_HOST to the public DNS name.
install -d -m 700 data
docker compose up -d --build
docker compose logs -f replica
```

The first start validates the complete PLC history from sequence zero, then automatically switches from paginated export to the live WebSocket stream. Do not configure the origin as a Hail reader until `lastCommittedOpTime` remains within five minutes of current time:

```bash
./check-health.sh "https://$(sed -n 's/^REPLICA_HOST=//p' .env)"
```

The script requires `curl` and `jq`. Prometheus metrics are available only on the VPS loopback interface at `http://127.0.0.1:9464/metrics` by default. Alert on process exit, disk exhaustion, TLS failure, and `plc_replica_last_ingested_op_ts` lag greater than five minutes.

## Hail compatibility smoke test

After a public Hail-profile DID exists, run the cross-replica validator from the sibling Hail server checkout:

```bash
PUBLIC_PLC_SMOKE_DID=did:plc:... bun --cwd ../../../hail-server-ts run test:plc-live
```

The Hail provider must use two reviewed reader operators that are independent from each other and from the provider. Running this deployment on provider-controlled infrastructure does not make it an independent witness.

## Backups and recovery

The database can be reconstructed from the canonical export, but losing it also loses locally retained evidence of an operation the primary might later remove. Take encrypted filesystem or volume snapshots of `deploy/hail/data` and replicate them to storage outside the VPS operator.

For a consistent application-level SQLite backup when filesystem snapshots are unavailable:

```bash
docker compose stop replica
install -d -m 700 backups
sqlite3 data/replica.db ".backup 'backups/replica-$(date -u +%Y%m%dT%H%M%SZ).db'"
docker compose start replica
```

Restore only while the replica is stopped, preserve the replaced database for investigation, then start the service and verify that it resumes from its retained cursor. If no trustworthy backup exists, move the old data directory aside and perform a new sequence-zero backfill; never manufacture a late cursor.

## Updating from upstream

The deployed Git commit is the software pin. Review upstream changes before merging and deploying them:

```bash
git fetch upstream
git log --oneline HEAD..upstream/main
git merge --ff-only upstream/main  # only when the fork has no deployment commits
# Otherwise merge or rebase the reviewed upstream range normally.
docker compose -f deploy/hail/compose.yaml up -d --build
```

Record the deployed commit, operator identity, origin, snapshot policy, and successful health check. Do not automatically deploy upstream `main`.
