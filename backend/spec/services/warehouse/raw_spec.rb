require "rails_helper"

RSpec.describe Connectors::Postgres, :integration do
  let(:source) do
    Source.create!(
      name: "pagila",
      connector: "postgres",
      config: {
        "host" => "source_db",
        "port" => 5432,
        "database" => "pagila",
        "username" => "makhazen_reader",
        "password" => "s3cret-password"
      }
    )
  end

  def build_stream(**params)
    source.streams.build(
      {
        schema_name: "public",
        name: "film_actor",
        destination_table: "pagila__film_actor",
        source_columns: [
          { "name" => "actor_id", "type" => "integer", "nullable" => false },
          { "name" => "film_id", "type" => "integer", "nullable" => false }
        ],
        source_primary_key: %w[actor_id film_id]
      }.merge(params)
    )
  end

  it "#create_table" do
    Warehouse::Raw.create_table(build_stream)
    columns = Warehouse::Base.db.schema(Sequel[:raw][:pagila__film_actor]).map(&:first)
    expect(columns).to eq([ :actor_id, :film_id ])
  end

  it "#load" do
    stream = build_stream

    Warehouse::Raw.create_table(stream)
    Warehouse::Raw.load(stream, [ { actor_id: 1, film_id: 10 }, { actor_id: 2, film_id: 20 } ])

    expect(Warehouse::Base.db.schema(Sequel[:raw][:pagila__film_actor]).count).to eq(2)
  end

  after { Warehouse::Base.db.drop_table?(Sequel[:raw][:pagila__film_actor]) }
end
