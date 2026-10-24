require "rails_helper"

RSpec.describe Files::Reader do
  let(:reader) { described_class.new(file_fixture("waste_sample.csv").to_s) }

  describe "#columns" do
    it "detects every column of the CSV with its Postgres type" do
      expect(reader.columns.size).to eq(13)
      expect(reader.columns.first).to eq({ name: "QUALI_WASTE", type: "text", nullable: true })
      expect(reader.columns.last).to eq({ name: "OBS_VALUE", type: "bigint", nullable: true })
    end
  end

  describe "#each_batch" do
    it "gives every row as a Hash" do
      rows = []
      reader.each_batch(size: 1000) { |batch| rows.concat(batch) }

      expect(rows.size).to eq(3)
      expect(rows.first).to include("QUALI_WASTE" => "_Z", "TIME_PERIOD" => 2022)
    end
  end

  describe "with a Parquet file" do
    let(:reader) { described_class.new(file_fixture("waste_sample.parquet").to_s) }

    it "detects the same columns as the CSV" do
      csv = described_class.new(file_fixture("waste_sample.csv").to_s)
      expect(reader.columns).to eq(csv.columns)
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
