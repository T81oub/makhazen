require "rails_helper"

RSpec.describe Connectors::DataGouv do
  let(:connector) { described_class.new("dataset" => "waste-2022") }
  let(:dataset_url) { "https://www.data.gouv.fr/api/1/datasets/waste-2022/" }
  let(:zip_url) { "https://www.data.gouv.fr/api/1/datasets/r/res-zip" }
  let(:dead_url) { "https://www.data.gouv.fr/api/1/datasets/r/res-dead" }
  let(:doc_url) { "https://example.com/guide.pdf" }
  let(:csv) { file_fixture("waste_sample.csv").read }

  let(:resources) do
    [
      { "id" => "res-zip", "type" => "main", "latest" => zip_url },
      { "id" => "res-dead", "type" => "main", "latest" => dead_url },
      { "id" => "res-doc", "type" => "documentation", "latest" => doc_url }
    ]
  end

  def zip_of(entries)
    Zip::OutputStream.write_buffer { |zip|
      entries.each { |name, content| zip.put_next_entry(name); zip.write(content) }
    }.string
  end

  before do
    stub_request(:get, dataset_url).to_return(
      body: { "id" => "abc123", "resources" => resources }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    stub_request(:get, zip_url).to_return(
      body: zip_of("DS_DECHET_SERVICES_data.csv" => csv, "DS_DECHET_SERVICES_metadata.csv" => "code;label\nA;Alpha\n")
    )
    stub_request(:get, dead_url).to_return(status: 404)
  end

  describe "#check" do
    it "returns true when the dataset exists" do
      expect(connector.check).to be(true)
    end

    it "explains an unknown dataset" do
      stub_request(:get, dataset_url).to_return(status: 404)
      expect { connector.check }.to raise_error(Connectors::ConnectionError, /waste-2022 not found/)
    end
  end

  describe "#discover" do
    let(:streams) { connector.discover }

    it "gives one stream per data file, named after the file" do
      expect(streams.map { |s| s[:name] }).to contain_exactly("ds_dechet_services_data", "ds_dechet_services_metadata")
    end

    it "uses the resource id as the schema" do
      expect(streams.map { |s| s[:schema] }).to all(eq("res-zip"))
    end

    it "describes the columns of each file" do
      data = streams.find { |s| s[:name] == "ds_dechet_services_data" }
      expect(data[:columns].size).to eq(13)
      expect(data[:columns].last).to eq({ name: "obs_value", type: "text", nullable: true })
    end

    it "skips a resource it can't download" do
      expect(streams.map { |s| s[:schema] }).not_to include("res-dead")
    end

    it "ignores resources that are not data" do
      streams
      expect(a_request(:get, doc_url)).not_to have_been_made
    end
  end

  describe "#read" do
    def read_all(schema_name, name)
      rows = []
      connector.read(Stream.new(schema_name: schema_name, name: name)) { |batch| rows.concat(batch) }
      rows
    end

    it "gives every row of the file as a Hash" do
      rows = read_all("res-zip", "ds_dechet_services_data")
      expect(rows.size).to eq(3)
      expect(rows.first).to include("quali_waste" => "_Z", "time_period" => "2022")
    end

    it "reads the right file when a zip has several" do
      expect(read_all("res-zip", "ds_dechet_services_metadata")).to eq([ { "code" => "A", "label" => "Alpha" } ])
    end

    it "explains a resource that is gone" do
      expect { read_all("res-gone", "anything") }
        .to raise_error(Connectors::ConnectionError, /res-gone is gone/)
    end
  end
end
