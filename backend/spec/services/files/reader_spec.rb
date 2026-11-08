require "rails_helper"

RSpec.describe Files::Reader do
  let(:reader) { described_class.new(file_fixture("waste_sample.csv").to_s) }

  def rows_of(reader)
    loaded_rows(reader.columns) { |stream, sync| reader.load_into(stream, sync) }
  end

  describe "#columns" do
    it "detects every column of the CSV with its Postgres type" do
      expect(reader.columns.size).to eq(13)
      expect(reader.columns.first).to eq({ name: "quali_waste", type: "text", nullable: true })
      expect(reader.columns.last).to eq({ name: "obs_value", type: "text", nullable: true })
    end
  end

  describe "#load_into" do
    it "writes every row into the loading table" do
      rows = rows_of(reader)

      expect(rows.size).to eq(3)
      expect(rows.first).to include("quali_waste" => "_Z", "time_period" => "2022")
    end

    it "stamps every row with the sync and returns how many it wrote" do
      loaded_rows(reader.columns) do |stream, sync|
        expect(reader.load_into(stream, sync)).to eq(3)
        expect(Warehouse::Raw.db[Warehouse::Raw.loading_table(stream)].select_map(:_sync_id)).to eq([ 1, 1, 1 ])
      end
    end
  end

  describe "with French accents" do
    def first_row(fixture)
      rows_of(described_class.new(file_fixture(fixture).to_s)).first
    end

    it "reads a UTF-8 file" do
      expect(first_row("waste_sample_2.csv")).to include("conf_status" => "éûè", "time_period" => "2022")
    end

    it "reads a Latin-1 file and gives the text back in UTF-8" do
      expect(first_row("waste_sample_latin1.csv")).to include("conf_status" => "éûè", "time_period" => "2022")
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
      rows = rows_of(described_class.new(file.path))

      expect(rows.size).to eq(30_001)
      expect(rows).to include("id" => "30000", "amount" => "N/A")
    end
  end

  describe "with a Parquet file" do
    let(:reader) { described_class.new(file_fixture("waste_sample.parquet").to_s) }

    it "detects the same column names as the CSV" do
      csv = described_class.new(file_fixture("waste_sample.csv").to_s)
      expect(reader.columns.map { |c| c[:name] }).to eq(csv.columns.map { |c| c[:name] })
    end

    it "keeps the types written in the file" do
      expect(reader.columns.last).to eq({ name: "obs_value", type: "bigint", nullable: true })
    end

    it "writes every row with its type" do
      rows = rows_of(reader)
      expect(rows.size).to eq(3)
      expect(rows.first).to include("quali_waste" => "_Z", "time_period" => 2022)
    end
  end

  describe "with odd column names" do
    let(:long) { "Libellé de la commune de résidence du bénéficiaire principal du contrat" }
    let(:file) do
      Tempfile.new([ "names", ".csv" ]).tap do |f|
        f.puts("Montant (€);Montant ($);Date de mise à jour;2022;#{long} A;#{long} B")
        f.puts("1;2;2026-01-01;3;x;y")
        f.close
      end
    end
    let(:reader) { described_class.new(file.path) }

    after { file.unlink }

    it "gives clean, unique names that Postgres won't cut" do
      names = reader.columns.map { |c| c[:name] }

      expect(names.first(4)).to eq(%w[montant montant_2 date_de_mise_a_jour col_2022])
      expect(names[5]).to eq("#{names[4]}_2")
      expect(names).to all(satisfy { |name| name.length <= 63 })
    end

    it "writes the values under those names" do
      expect(rows_of(reader).first).to include("montant" => "1", "montant_2" => "2", "col_2022" => "3")
    end
  end

  describe "with an Excel file" do
    let(:path) { File.join(Dir.mktmpdir, "waste.xlsx") }
    let(:reader) { described_class.new(path) }

    before do
      duckdb = DuckDB::Database.open.connect
      %w[INSTALL LOAD].each { |verb| duckdb.query("#{verb} excel") }
      duckdb.query("COPY (SELECT 'Paris' AS \"Ville\", 42 AS \"Tonnes\") TO '#{path}' (FORMAT xlsx, HEADER true)")
    end

    after { FileUtils.rm_rf(File.dirname(path)) }

    it "reads the first sheet, with clean names, as text" do
      expect(reader.columns.map { |c| c[:type] }).to all(eq("text"))
      expect(rows_of(reader)).to eq([ { "ville" => "Paris", "tonnes" => "42" } ])
    end
  end

  describe "with a format it can't read" do
    it "raises a KeyError naming the format" do
      expect { described_class.new("data.zip") }.to raise_error(KeyError, /zip/)
    end
  end

  describe "with nested JSON" do
    let(:file) do
      Tempfile.new([ "nested", ".json" ]).tap do |f|
        f.write('[{"id": 1, "address": {"city": "Paris", "zip": "75001"}, "tags": ["a", "b"]}]')
        f.close
      end
    end
    let(:reader) { described_class.new(file.path) }

    after { file.unlink }

    it "describes objects and arrays as jsonb" do
      types = reader.columns.to_h { |c| [ c[:name], c[:type] ] }
      expect(types).to include("address" => "jsonb", "tags" => "jsonb")
    end

    it "stores objects and arrays as jsonb in Postgres" do
      row = rows_of(reader).first

      expect(JSON.parse(row["address"])).to eq("city" => "Paris", "zip" => "75001")
      expect(JSON.parse(row["tags"])).to eq([ "a", "b" ])
    end
  end
end
