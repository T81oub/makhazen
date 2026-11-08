require "rails_helper"

# Integration test: talks to the real Pagila database.
# Needs the stack started with `./start --pagila`.
RSpec.describe Connectors::Postgres, :integration do
  let(:config) do
    {
      "host" => "source_db",
      "port" => 5432,
      "database" => "pagila",
      "username" => "makhazen_reader",
      "password" => "reader"
    }
  end

  def connector(**params)
    described_class.new(config.merge(params.transform_keys(&:to_s)))
  end

  describe "#check" do
    it "returns true when it can connect" do
      expect(connector.check).to be(true)
    end

    it "explains a wrong password" do
      expect { connector(password: "wrong").check }
        .to raise_error(Connectors::ConnectionError, /password authentication failed/)
    end

    it "explains an unknown host" do
      expect { connector(host: "no-such-host").check }
        .to raise_error(Connectors::ConnectionError, /could not translate host name/)
    end

    it "explains an unknown database" do
      expect { connector(database: "nope").check }
        .to raise_error(Connectors::ConnectionError, /database "nope" does not exist/)
    end

    it "explains a closed port" do
      expect { connector(port: 5999).check }
        .to raise_error(Connectors::ConnectionError, /Connection refused/)
    end

    it "never puts the password in the error message" do
      expect { connector(password: "wrong-s3cret").check }
        .to raise_error(Connectors::ConnectionError) { |error|
          expect(error.message).not_to include("wrong-s3cret")
        }
    end
  end

  describe "#discover" do
    context "with the default config" do
      let(:streams) { connector.discover }
      let(:names) { streams.map { |s| s[:name] } }

      it "lists every table you can sync, in order" do
        expect(names).to eq([ 'actor', 'address', 'category', 'city', 'country', 'customer', 'film', 'film_actor', 'film_category', 'inventory', 'language', 'payment', 'rental', 'staff', 'store' ])
      end

      it "skips views" do
        expect(names).not_to include("actor_info", "customer_list")
      end

      it "keeps payment as a partitioned parent table" do
        expect(streams).to include(include(name: "payment", relkind: "p"))
      end
    end

    context "with types that only exist in the source" do
      let(:film) { connector.discover.find { |s| s[:name] == "film" } }
      let(:types) { film[:columns].to_h { |c| [ c[:name], c[:type] ] } }

      it "stores a domain as the type it is built on" do
        expect(types["release_year"]).to eq("integer")
      end

      it "stores an enum as text" do
        expect(types["rating"]).to eq("text")
      end

      it "keeps the types Postgres knows everywhere" do
        expect(types).to include("title" => "text", "rental_rate" => "numeric(4,2)", "special_features" => "text[]")
      end

      it "only gives types the warehouse can create" do
        film[:columns].each do |column|
          expect { Warehouse::Base.db.get(Sequel.lit("NULL::#{column[:type]}")) }.not_to raise_error, column[:name]
        end
      end
    end

    context "when the connection fails" do
      it "raises a ConnectionError" do
        expect { connector(password: "wrong").discover }
          .to raise_error(Connectors::ConnectionError)
      end
    end

    it "closes its connection" do
      expect { connector.discover }.not_to change { Sequel::DATABASES.size }
    end

    it "describes film_actor with its columns and composite primary key" do
      stream_schema = {
        schema: "public",
        name: "film_actor",
        relkind: "r",
        columns: [
          { name: "actor_id", nullable: false, type: "integer" },
          { name: "film_id", nullable: false, type: "integer" },
          { name: "last_update", nullable: false, type: "timestamp with time zone" }
        ],
        primary_key: [ "actor_id", "film_id" ]
      }
      expect(connector.discover).to include(stream_schema)
    end

    it "turns enum columns into text, which the warehouse understands" do
      film = connector.discover.find { |s| s[:name] == "film" }
      rating = film[:columns].find { |c| c[:name] == "rating" }
      expect(rating[:type]).to eq("text")
    end
  end
    describe "#read" do
    def read_all(table, **attributes)
      columns = connector.discover.find { |t| t[:schema] == "public" && t[:name] == table }[:columns]
      loaded_rows(columns, schema_name: "public", name: table) do |stream, sync|
        stream.assign_attributes(attributes)
        @count = connector.read(stream, sync)
      end
    end

    it "copies every row of the table" do
      expect(read_all("actor").size).to eq(200)
    end

    it "returns how many rows it copied" do
      read_all("actor")
      expect(@count).to eq(200)
    end

    it "copies the values of each row" do
      penelope = read_all("actor").find { |row| row["actor_id"] == 1 }
      expect(penelope).to include("first_name" => "PENELOPE", "last_name" => "GUINESS")
    end

    it "copies only the rows newer than last_sync" do
      rows = read_all("payment", updated_at_attr: "payment_date", last_sync: "2022-07-01T00:00:00Z")

      expect(rows.size).to eq(2334)
      expect(rows.map { |row| row["payment_date"] }).to all(be > Time.utc(2022, 7, 1))
    end

    it "copies every row when there is no last_sync yet" do
      expect(read_all("payment", updated_at_attr: "payment_date").size).to eq(16049)
    end
  end
end
