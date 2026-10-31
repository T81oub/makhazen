# Makhazen backend

```
  SOURCES                     MAKHAZEN (Rails)                          WAREHOUSE (Postgres)

  Postgres   ─┐             ┌─ Source  where the data is, how to connect
  data.gouv  ─┤  connector ─┤  Stream  one table or file, selected or not   ┌─► raw      exact copies
  any URL    ─┘  check      └─ Sync    what happened on each run  ── read ──┘   staging  cleaned (later)
                 discover                                                       marts    business tables (later)
                 read
```

## Connectors

| Connector   | Config                                              | One stream per |
|-------------|-----------------------------------------------------|----------------|
| `postgres`  | `host`, `port`, `database`, `username`, `password`  | table          |
| `data_gouv` | `dataset` (slug or id)                              | data file in the dataset |
| `http`      | `urls`, optional `auth`                             | data file at each URL |

Files can be CSV, Parquet or JSON, plain, zipped or gzipped. The format is found from the file itself, not from its name.

`auth` for `http` is one of:

```ruby
{ "type" => "header", "name" => "X-API-KEY", "value" => "..." }
{ "type" => "bearer", "token" => "..." }
{ "type" => "basic", "username" => "...", "password" => "..." }
```

Configs are encrypted in the database.

## Sync modes

**Full refresh** (default). Every sync reloads the whole table. The rows go into `raw_loading` first, then replace the old table in one transaction. If a sync fails halfway, the previous copy stays as it was.

**Incremental**. Set `updated_at_attr` on the stream: the column that changes when a row is added or updated, like `last_update`. The stream should also have a primary key, so changed rows are updated instead of added twice.

- The first sync loads everything and saves the newest `updated_at_attr` value in `last_sync`.
- The next ones only read rows newer than that value, and update the rows that already exist.
- If a sync fails, `last_sync` doesn't move, so the next sync picks up the same rows again.

Deleted rows in the source are not detected in incremental mode.

## Scheduled syncs

Each stream has a `sync_every`: `hourly`, `daily` (default) or `monthly`. Every hour, `SyncDueStreamsJob` starts a `SyncStreamJob` for each selected stream whose `next_sync_at` has passed, then plans its next sync. A stream that was never synced runs at the next tick.

```ruby
stream.update!(selected: true, sync_every: "hourly")
SyncDueStreamsJob.perform_now
```

The jobs run in Solid Queue, inside Puma (`SOLID_QUEUE_IN_PUMA`), so `./start` is enough.

## Try it for real

```bash
./start --pagila
./backend/exec bin/rails c
```

### A Postgres database

```ruby
pagila = Source.find_or_create_by!(name: "pagila") do |source|
  source.connector = "postgres"
  source.config = { "host" => "source_db", "port" => 5432, "database" => "pagila",
                    "username" => "makhazen_reader", "password" => "reader" }
end

pagila.connector_instance.check
pagila.discover!
pagila.streams.count

rental = pagila.streams.find_by(name: "rental")
rental.sync!.rows_loaded

rental.update!(updated_at_attr: "last_update")
rental.sync!.rows_loaded           
rental.sync!.rows_loaded
```

### A data.gouv dataset

```ruby
waste = Source.find_or_create_by!(name: "waste") do |source|
  source.connector = "data_gouv"
  source.config = { "dataset" => "enquete-sur-la-production-de-dechets-non-dangereux-dans-les-services-en-2022" }
end

waste.connector_instance.check         # => true
waste.discover!
waste.streams.update_all(selected: true)
waste.sync!

Warehouse::Raw.db.tables(schema: :raw)
Warehouse::Raw.db[Sequel[:raw][:waste__ds_dechet_services_data]].first(3)
```

### Files at any URL

```ruby
files = Source.find_or_create_by!(name: "files") do |source|
  source.connector = "http"
  source.config = { "urls" => [ "https://www.data.gouv.fr/api/1/datasets/r/63379d67-452f-4cb3-8788-1703bddabaef" ] }
end

files.connector_instance.check
files.discover!
files.streams.update_all(selected: true)
files.sync!
```

## Tests

```bash
./backend/rspec
```

Tests tagged `:integration` need the Pagila database, so start the stack with `./start --pagila`.
