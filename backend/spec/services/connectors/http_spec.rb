require "rails_helper"

RSpec.describe Connectors::Http do
  let(:csv_url) { "https://example.com/data/waste.csv" }
  let(:zip_url) { "https://example.com/export" }
  let(:csv) { file_fixture("waste_sample.csv").read }
  let(:auth) { { "type" => "header", "name" => "X-API-KEY", "value" => "s3cret" } }

  def connector(urls: [ csv_url, zip_url ], auth: nil)
    described_class.new({ "urls" => urls, "auth" => auth }.compact)
  end

  def zip_of(entries)
    Zip::OutputStream.write_buffer { |zip|
      entries.each { |name, content| zip.put_next_entry(name); zip.write(content) }
    }.string
  end

  before do
    stub_request(:get, csv_url).to_return(body: csv)
    stub_request(:get, zip_url).to_return(body: zip_of("codes.csv" => "code;label\nA;Alpha\n"))
  end

  describe "#check" do
    it "returns true when every URL answers" do
      expect(connector.check).to be(true)
    end

    it "explains a URL that doesn't answer" do
      stub_request(:get, zip_url).to_return(status: 404)
      expect { connector.check }.to raise_error(Connectors::ConnectionError, /404/)
    end
  end

  describe "#discover" do
    let(:streams) { connector.discover }

    it "gives one stream per data file, named after the file" do
      expect(streams.map { |s| s[:name] }).to contain_exactly("waste", "codes")
    end

    it "uses the URL as the schema" do
      expect(streams.map { |s| s[:schema] }).to contain_exactly(csv_url, zip_url)
    end

    it "describes the columns of each file" do
      waste = streams.find { |s| s[:name] == "waste" }
      expect(waste[:columns].size).to eq(13)
    end

    it "skips a URL it can't download" do
      stub_request(:get, zip_url).to_return(status: 404)
      expect(streams.map { |s| s[:name] }).to eq([ "waste" ])
    end
  end

  describe "#read" do
    def read_all(connector, schema_name, name)
      rows = []
      connector.read(Stream.new(schema_name: schema_name, name: name)) { |batch| rows.concat(batch) }
      rows
    end

    it "gives every row of the file as a Hash" do
      rows = read_all(connector, csv_url, "waste")
      expect(rows.size).to eq(3)
      expect(rows.first).to include("QUALI_WASTE" => "_Z", "TIME_PERIOD" => "2022")
    end

    it "reads a file inside a zip" do
      expect(read_all(connector, zip_url, "codes")).to eq([ { "code" => "A", "label" => "Alpha" } ])
    end

    it "explains a URL that was removed from the config" do
      expect { read_all(connector, "https://example.com/old.csv", "old") }
        .to raise_error(Connectors::ConnectionError, /old.csv is gone/)
    end

    it "skips a file that has not changed" do
      stream = Stream.new(schema_name: csv_url, name: "waste", last_sha256: Digest::SHA256.hexdigest(csv))
      rows = []

      result = connector.read(stream) { |batch| rows.concat(batch) }

      expect(result).to eq(:unchanged)
      expect(rows).to be_empty
    end
  end

  describe "authentication" do
    it "sends the credentials with every download" do
      stub = stub_request(:get, csv_url).with(headers: { "X-API-KEY" => "s3cret" }).to_return(body: csv)

      connector(urls: [ csv_url ], auth: auth).read(Stream.new(schema_name: csv_url, name: "waste")) { }
      expect(stub).to have_been_requested
    end
  end
end
