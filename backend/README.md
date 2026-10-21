# README


  SOURCES                      MAKHAZEN                                  WAREHOUSE
  (Extern)                  (Rails app)                               (Postgres)

  Postgres  ─┐            ┌─ Source   "where + how to connect"
  MySQL     ─┤ connector ─┤  Stream   "which table/file, selected?"   ┌─► raw      exact copies
  data.gouv ─┤  check     │  Sync     "what happened each run"        │   staging  cleaned (SQL)
  REST API  ─┘  discover  └─ Job ──── read ──── COPY ─────────────────┘   marts    business tables
                read                                                             │
                                                                      API + API keys ──► users


## try it for real

```bash
./start --pagila
./backend/exec bin/rails c
```

```ruby

pagila = Source.find_or_create_by!(name: "pagila") do |source|
  source.connector = "postgres"
  source.config = { "host" => "source_db", "port" => 5432, "database" => "pagila",
                    "username" => "makhazen_reader", "password" => "reader" }
end

p pagila.connector_instance.check          # => true
 pagila.discover!
p pagila.streams.count                     # => 15

rental = pagila.streams.find_by(name: "rental")
sync = rental.sync!
p sync.status                              # => "succeeded"
p sync.rows_loaded                         # => 16044

```
