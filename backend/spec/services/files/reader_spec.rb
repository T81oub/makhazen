require "rails_helper"

RSpec.describe Files::Reader do
  let(:reader) { described_class.new(file_fixture("waste_sample.csv").to_s) }

  describe "#columns" do
    it "detects every column of the CSV with its Postgres type" do
      expect(reader.columns.size).to eq(13)
      expect(reader.columns.first).to eq({ name: "QUALI_WASTE", type: "text", nullable: true })
      expect(reader.columns.last).to eq({ name: "OBS_VALUE", type: "text", nullable: true })
    end
  end

  describe "#each_batch" do
    it "gives every row as a Hash" do
      rows = []
      reader.each_batch(size: 1000) { |batch| rows.concat(batch) }

      expect(rows.size).to eq(3)
      expect(rows.first).to include("QUALI_WASTE" => "_Z", "TIME_PERIOD" => "2022")
    end
  end

  describe "with French accents" do
    def first_row(fixture)
      rows = []
      described_class.new(file_fixture(fixture).to_s).each_batch(size: 1000) { |batch| rows.concat(batch) }
      rows.first
    end

    it "reads a UTF-8 file" do
      expect(first_row("waste_sample_2.csv")).to include("CONF_STATUS" => "éûè", "TIME_PERIOD" => "2022")
    end

    it "reads a Latin-1 file and gives the text back in UTF-8" do
      expect(first_row("waste_sample_latin1.csv")).to include("CONF_STATUS" => "éûè", "TIME_PERIOD" => "2022")
    end
  end

  describe "with a value that does not match the rest of its column" do
    let(:file) do
      Tempfile.new([ "big", ".csv" ]).tap do |f|
        f.puts("id,amount")
        30_000.times { |i| f.puts("#{i},#{i * 10}") }
        f.puts("30000,N/A")
        f.close
      end
    end

    after { file.unlink }

    it "reads every row instead of crashing past the rows DuckDB looked at" do
      rows = []
      described_class.new(file.path).each_batch(size: 10_000) { |batch| rows.concat(batch) }

      expect(rows.size).to eq(30_001)
      expect(rows.last).to eq("id" => "30000", "amount" => "N/A")
    end
  end

  describe "with a Parquet file" do
    let(:reader) { described_class.new(file_fixture("waste_sample.parquet").to_s) }

    it "detects the same column names as the CSV" do
      csv = described_class.new(file_fixture("waste_sample.csv").to_s)
      expect(reader.columns.map { |c| c[:name] }).to eq(csv.columns.map { |c| c[:name] })
    end

    it "keeps the types written in the file" do
      expect(reader.columns.last).to eq({ name: "OBS_VALUE", type: "bigint", nullable: true })
    end

    it "gives every row as a Hash" do
      rows = []
      reader.each_batch(size: 1000) { |batch| rows.concat(batch) }
      expect(rows.size).to eq(3)
      expect(rows.first).to include("QUALI_WASTE" => "_Z", "TIME_PERIOD" => 2022)
    end
  end

  describe "with a format it can't read" do
    it "raises a KeyError naming the format" do
      expect { described_class.new("data.zip") }.to raise_error(KeyError, /zip/)
    end
  end
end
