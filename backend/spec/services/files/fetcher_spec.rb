require "rails_helper"

RSpec.describe Files::Fetcher do
  let(:into) { Dir.mktmpdir }
  let(:url) { "https://example.com/data/waste.csv" }

  after { FileUtils.rm_rf(into) }

  def fetch(auth: nil)
    described_class.new(url, into: into, auth: auth).fetch
  end

  it "downloads the file into the given folder" do
    stub_request(:get, url).to_return(body: "a;b\n1;2\n")

    download = fetch
    expect(download.path).to eq(File.join(into, "waste.csv"))
    expect(File.read(download.path)).to eq("a;b\n1;2\n")
  end

  it "computes the SHA-256 of the file" do
    stub_request(:get, url).to_return(body: "hello")
    expect(fetch.sha256).to eq(Digest::SHA256.hexdigest("hello"))
  end

  it "names the file 'download' when the URL has no file name" do
    stub_request(:get, "https://example.com/").to_return(body: "x")
    download = described_class.new("https://example.com/", into: into).fetch
    expect(File.basename(download.path)).to eq("download")
  end

  it "follows redirects" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "https://cdn.example.com/waste.csv" })
    stub_request(:get, "https://cdn.example.com/waste.csv").to_return(body: "ok")
    expect(File.read(fetch.path)).to eq("ok")
  end

  it "names the file after the URL it was redirected to" do
    latest = "https://www.data.gouv.fr/fr/datasets/r/res-123"
    stub_request(:get, latest).to_return(status: 302, headers: { "Location" => "https://static.data.gouv.fr/waste.xlsx" })
    stub_request(:get, "https://static.data.gouv.fr/waste.xlsx").to_return(body: "ok")

    download = described_class.new(latest, into: into).fetch
    expect(File.basename(download.path)).to eq("waste.xlsx")
  end

  it "retries when the server is briefly down" do
    stub_request(:get, url).to_return({ status: 503 }, { body: "ok" })
    expect(File.read(fetch.path)).to eq("ok")
  end

  it "raises a FetchError with the status when the file is missing" do
    stub_request(:get, url).to_return(status: 404)
    expect { fetch }.to raise_error(Files::FetchError, /404/)
  end

  describe "authentication" do
    it "sends an API key in a header" do
      stub = stub_request(:get, url).with(headers: { "X-API-KEY" => "s3cret" })
      fetch(auth: { "type" => "header", "name" => "X-API-KEY", "value" => "s3cret" })
      expect(stub).to have_been_requested
    end

    it "sends a bearer token" do
      stub = stub_request(:get, url).with(headers: { "Authorization" => "Bearer t0ken" })
      fetch(auth: { "type" => "bearer", "token" => "t0ken" })
      expect(stub).to have_been_requested
    end

    it "sends basic auth" do
      stub = stub_request(:get, url).with(basic_auth: [ "user", "pass" ])
      fetch(auth: { "type" => "basic", "username" => "user", "password" => "pass" })
      expect(stub).to have_been_requested
    end
  end
end
