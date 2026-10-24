require "rails_helper"

require "rails_helper"

RSpec.describe Files::Unpacker do
  let(:csv) { file_fixture("waste_sample.csv") }
  let(:tmp) { Pathname(Dir.mktmpdir) }
  let(:out) { Pathname(Dir.mktmpdir) }

  after { FileUtils.rm_rf([ tmp, out ]) }

  def unpack(path)
    described_class.new(path.to_s, into: out.to_s).files
  end

  def make_zip(name, entries)
    path = tmp.join(name)
    Zip::File.open(path.to_s, create: true) do |zip|
      entries.each { |entry, content| zip.get_output_stream(entry) { |f| f.write(content) } }
    end
    path
  end

  def names(files)
    files.map { |file| File.basename(file) }
  end

  describe "a plain data file" do
    it "returns the file itself" do
      expect(unpack(csv)).to eq([ csv.to_s ])
    end
  end

  describe "a zip" do
    it "returns every data file inside it" do
      zip = make_zip("data.zip", "waste.csv" => csv.read, "metadata.csv" => "a;b\n1;2\n")
      expect(names(unpack(zip))).to contain_exactly("waste.csv", "metadata.csv")
    end

    it "skips files that are not data" do
      zip = make_zip("data.zip", "waste.csv" => csv.read, "README.pdf" => "%PDF-1.4")
      expect(names(unpack(zip))).to eq([ "waste.csv" ])
    end

    it "finds data files in sub-folders" do
      zip = make_zip("data.zip", "2022/waste.csv" => csv.read)
      expect(names(unpack(zip))).to eq([ "waste.csv" ])
    end

    it "recognises a zip even without the .zip extension" do
      zip = make_zip("download", "waste.csv" => csv.read)
      expect(names(unpack(zip))).to eq([ "waste.csv" ])
    end

    it "extracts into the given folder" do
      zip = make_zip("data.zip", "waste.csv" => csv.read)
      expect(unpack(zip)).to all(start_with(out.to_s))
    end

    it "gives files the Reader can read" do
      zip = make_zip("data.zip", "waste.csv" => csv.read)
      expect(Files::Reader.new(unpack(zip).first).columns.size).to eq(13)
    end
  end

  describe "a gzip file" do
    it "returns the decompressed file" do
      gz = tmp.join("waste.csv.gz")
      Zlib::GzipWriter.open(gz.to_s) { |file| file.write(csv.read) }

      files = unpack(gz)
      expect(names(files)).to eq([ "waste.csv" ])
      expect(File.read(files.first)).to eq(csv.read)
    end
  end
end
