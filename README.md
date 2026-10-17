# makhazen

makhazen is a small ELT platform. You connect a
database or a file, makhazen copies it into a Postgres warehouse, and you
read the data back through a REST API.


## How it works

```
  Sources                makhazen                     Warehouse (Postgres)
  -------                --------                     --------------------
  Postgres    --+
  MySQL       --+-->  connector  -->  sync  -->  raw      copied as-is
  CSV/Parquet --+                                staging  cleaned and typed
                                                 marts    ready for analysis
                                                    |
                                          REST API (API keys)
```

1. You register a **source** and pick the **streams** (tables or files) you want.
2. A **sync** extracts each stream with the right **connector** and loads it
   into the `raw` layer, untouched.
3. SQL transformations build `staging` and `marts` on top of it.
4. Clients read the result through a paginated, read-only API.

## Glossary

| Term | Meaning |
|---|---|
| Source | A system you extract data from: a database, a file, an API. |
| Connector | The code that knows how to talk to one technology (Postgres, MySQL, CSV...). |
| Stream | One table, file or endpoint inside a source. |
| Sync | One run of extract + load, with its status, row counts and errors. |
| raw / staging / marts | The three warehouse layers, also known as bronze / silver / gold. |

## Getting started

The only requirement is Docker (with Docker Compose). Ruby, Node and Postgres
all run in containers.

```bash
git clone https://github.com/T81oub/makhazen.git
cd makhazen
./start
```

The first start takes a few minutes (gems and npm packages are installed).
Then:

- API: http://localhost:3000/up
- Frontend: http://localhost:5173

`./start` follows the logs. Ctrl+C stops the logs, not the containers.
Use `./stop` to stop everything.

### Sample source: Pagila

[Pagila](https://github.com/devrimgunduz/pagila) is a DVD rental database.
It is small, but it has what a sync engine has to deal with: foreign keys,
enums, arrays, a partitioned table and `last_update` timestamps.

```bash
mkdir -p storage/seeds/pagila
curl -fL -o storage/seeds/pagila/01-schema.sql https://raw.githubusercontent.com/devrimgunduz/pagila/pagila-v3.1.0/pagila-schema.sql
curl -fL -o storage/seeds/pagila/02-data.sql   https://raw.githubusercontent.com/devrimgunduz/pagila/pagila-v3.1.0/pagila-data.sql
```

Add `storage/seeds/pagila/03-reader.sql` to create a read-only user:

```sql
CREATE ROLE makhazen_reader LOGIN PASSWORD 'reader';
GRANT CONNECT ON DATABASE pagila TO makhazen_reader;
GRANT USAGE ON SCHEMA public TO makhazen_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO makhazen_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO makhazen_reader;
```

Then start the stack with it:

```bash
./start --pagila
```

| | From your machine | From the backend container |
|---|---|---|
| Host | `localhost` | `source_db` |
| Port | `5433` | `5432` |
| Database | `pagila` | `pagila` |
| User / password | `makhazen_reader` / `reader` | same |

## Everyday commands

| Command | What it does |
|---|---|
| `./start` | Start the stack and follow the logs |
| `./start --pagila` | Same, plus the Pagila source database |
| `./stop` | Stop everything (data is kept in `storage/`) |
| `./backend/exec` | Open a shell in the backend container |
| `./backend/exec bin/rails console` | Run any command in the backend |
| `./backend/rspec` | Run the backend tests |
| `./frontend/exec` | Open a shell in the frontend container |
| `./frontend/test` | Run the frontend tests |

## Tech stack

- **Backend:** Ruby 3.4, Rails 8 (API mode), PostgreSQL 16
- **Background jobs:** Solid Queue (runs on Postgres, no Redis needed)
- **Frontend:** React, TypeScript, Vite
- **Tests:** RSpec, Vitest
- **Planned:** Sequel for source databases, DuckDB for reading CSV and Parquet files

## Project layout

```
makhazen/
├── backend/                    Rails API
├── frontend/                   React app
├── storage/                    Local data, not in git (Postgres files, seeds)
├── docker-compose.yml          Main stack: db, backend, frontend
├── docker-compose.pagila.yml   Optional sample source
├── start, stop                 Helper scripts
```
