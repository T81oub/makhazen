require "rails_helper"

RSpec.describe Stream, type: :model do
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

  it "is valid with a source, a schema, a name and a destination table" do
    expect(build_stream).to be_valid
  end

  describe "source" do
    it "is required" do
      stream = build_stream
      stream.source = nil
      expect(stream).not_to be_valid
      expect(stream.errors[:source]).to include("must exist")
    end

    it "lists its streams" do
      stream = build_stream
      stream.save!
      expect(source.streams).to contain_exactly(stream)
    end

    it "deletes its streams when the source is deleted" do
      build_stream.save!
      expect { source.destroy }.to change(Stream, :count).by(-1)
    end
  end

  describe "schema_name and name" do
    it "requires a schema_name" do
      expect(build_stream(schema_name: nil)).not_to be_valid
    end

    it "requires a name" do
      expect(build_stream(name: nil)).not_to be_valid
    end

    it "does not allow the same table twice in the same source" do
      build_stream.save!
      duplicate = build_stream
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "allows the same table name in another schema" do
      build_stream.save!
      expect(build_stream(schema_name: "sales", destination_table: "pagila__sales__film_actor")).to be_valid
    end

    it "allows the same table in another source" do
      build_stream.save!
      other_source = Source.create!(name: "pagila_copy", connector: "postgres", config: source.config)
      other = other_source.streams.build(
        schema_name: "public", name: "film_actor", destination_table: "pagila_copy__film_actor"
      )
      expect(other).to be_valid
    end
  end

  describe ".available_destination_table" do
    it "returns the name when it is free" do
      expect(Stream.available_destination_table("pagila__film_actor")).to eq("pagila__film_actor")
    end

    it "adds the next free suffix when the name is taken" do
      build_stream.save!
      build_stream(name: "film_actor_2", destination_table: "pagila__film_actor_2").save!

      expect(Stream.available_destination_table("pagila__film_actor")).to eq("pagila__film_actor_3")
    end
  end

  describe "destination_table" do
    it "is required" do
      expect(build_stream(destination_table: nil)).not_to be_valid
    end

    it "is unique across all sources" do
      build_stream.save!
      other_source = Source.create!(name: "pagila_copy", connector: "postgres", config: source.config)
      other = other_source.streams.build(schema_name: "public", name: "film_actor", destination_table: "pagila__film_actor")

      expect(other).not_to be_valid
      expect(other.errors[:destination_table]).to include("has already been taken")
    end

    it "is at most 63 characters, the Postgres limit for names" do
      expect(build_stream(destination_table: "a" * 63)).to be_valid
      expect(build_stream(destination_table: "a" * 64)).not_to be_valid
    end

    it "only allows a safe SQL identifier" do
      expect(build_stream(destination_table: "pagila__film_actor")).to be_valid
      expect(build_stream(destination_table: "pagila film")).not_to be_valid
      expect(build_stream(destination_table: "pagila;drop")).not_to be_valid
      expect(build_stream(destination_table: "Pagila")).not_to be_valid
    end
  end

  describe "defaults" do
    it "is not selected" do
      expect(Stream.new.selected).to be(false)
    end

    it "has no columns and no primary key" do
      expect(Stream.new.source_columns).to eq([])
      expect(Stream.new.source_primary_key).to eq([])
    end
  end

  describe "source_columns" do
    it "reads back the same columns after saving" do
      stream = build_stream
      stream.save!
      expect(stream.reload.source_columns).to eq([
        { "name" => "actor_id", "type" => "integer", "nullable" => false },
        { "name" => "film_id", "type" => "integer", "nullable" => false }
      ])
    end
  end

  describe "removal" do
    it "is not removed by default" do
      expect(build_stream).not_to be_removed
    end

    it "is removed once removed_at is set" do
      expect(build_stream(removed_at: Time.current)).to be_removed
    end
  end

  describe "scopes" do
    let!(:selected_stream) { build_stream(name: "rental", destination_table: "pagila__rental", selected: true).tap(&:save!) }
    let!(:unselected_stream) { build_stream(name: "actor", destination_table: "pagila__actor").tap(&:save!) }
    let!(:removed_stream) do
      build_stream(name: "old_table", destination_table: "pagila__old_table", selected: true, removed_at: 1.day.ago).tap(&:save!)
    end

    it ".active returns the streams that still exist in the source" do
      expect(Stream.active).to contain_exactly(selected_stream, unselected_stream)
    end

    it ".to_sync returns selected streams that still exist in the source" do
      expect(Stream.to_sync).to contain_exactly(selected_stream)
    end
  end

  describe ".destination_table_for" do
    it "leaves out the public schema" do
      expect(Stream.destination_table_for("pagila", "public", "film_actor")).to eq("pagila__film_actor")
    end

    it "keeps any other schema" do
      expect(Stream.destination_table_for("pagila", "sales", "orders")).to eq("pagila__sales__orders")
    end
  end
end
