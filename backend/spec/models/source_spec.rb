require 'rails_helper'

RSpec.describe Source, type: :model do
  let(:postgres_config) do
    {
      "host"     => "source_db",
      "port"     => 5432,
      "database" => "pagila",
      "username" => "makhazen_reader",
      "password" => "s3cret-password"
    }
  end

  def build_source(**params)
    Source.new({ name: "pagila", connector: "postgres", config: postgres_config }.merge(params))
  end

  it "is valid with a name, a connector and a complete config" do
    expect(build_source).to be_valid
  end

  describe "name" do
    it "is required" do
      source = build_source(name: nil)
      expect(source).not_to be_valid
      expect(source.errors[:name]).to include("can't be blank")
    end

    it "is unique" do
      build_source.save!
      duplicate = build_source
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "is stripped and lowercased" do
      expect(build_source(name: "  Pagila ").name).to eq("pagila")
    end

    it "is at most 30 characters" do
      expect(build_source(name: "a" * 30)).to be_valid
      expect(build_source(name: "a" * 31)).not_to be_valid
    end
  end

  describe "connector" do
    it "is required" do
      expect(build_source(connector: nil)).not_to be_valid
    end

    it "must be a supported connector" do
      source = build_source(connector: "my_connector")
      expect(source).not_to be_valid
      expect(source.errors[:connector]).to include("is not included in the list")
    end
  end

  describe "config" do
    it "is required" do
      expect(build_source(config: nil)).not_to be_valid
    end

    it "treats a blank value as missing" do
      source = build_source(config: postgres_config.merge("host" => ""))

      expect(source).not_to be_valid
      expect(source.errors[:config]).to include("is missing host")
    end
  end

  describe "config storage" do
    it "reads back the same config after saving" do
      source = build_source
      source.save!
      expect(source.reload.config).to eq(postgres_config)
    end

    it "is encrypted in the database" do
      source = build_source
      source.save!

      raw = Source.connection.select_value("SELECT config FROM sources WHERE id = #{source.id.to_i}")
      expect(raw).not_to include("s3cret-password")
      expect(raw).not_to include("source_db")
    end

    it "never shows the password when the record is inspected" do
      expect(build_source.inspect).not_to include("s3cret-password")
    end
  end

  describe "#connector_instance" do
    it "had a valid connector" do
      source = build_source
      expect(source.connector_instance).to be_a(Connectors::Postgres)
    end

    it "not a valid connector" do
      source = build_source(connector: "my_connector")
      expect { source.connector_instance }.to raise_error(KeyError, /my_connector/)
    end
  end

  describe "#discover!" do
    let(:source) { build_source.tap(&:save!) }
    let(:discovered) do
      [
        {
          schema: "public",
          name: "rental",
          relkind: "r",
          columns: [
            {
              name: "rental_id",
              type: "integer",
              nullable: false
            }
          ],
          primary_key: [ "rental_id" ]
        }
      ]
    end

    before do
      fake_connector = double("connector", discover: discovered)
      allow(source).to receive(:connector_instance).and_return(fake_connector)
    end

    it "creates a stream for each discovered table" do
      source.discover!
      expect(source.streams.pluck(:name)).to eq([ "rental" ])
    end

    it "does not create duplicates when run twice" do
      source.discover!
      source.discover!
      expect(source.streams.count).to eq(1)
    end
  end
end
