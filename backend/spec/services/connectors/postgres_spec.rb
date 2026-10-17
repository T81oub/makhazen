require "rails_helper"

# Integration test: talks to the real Pagila database.
# Needs the stack started with `./start --pagila`.
RSpec.describe Connectors::Postgres, :integration do
  let(:config) do
    {
      "host" => "source_db",
      "port" => 5432,
      "database" => "pagila",
      "username" => "makhazen_reader",
      "password" => "reader"
    }
  end

  def connector(**params)
    described_class.new(config.merge(params.transform_keys(&:to_s)))
  end

  describe "#check" do
    it "returns true when it can connect" do
      expect(connector.check).to be(true)
    end

    it "explains a wrong password" do
      expect { connector(password: "wrong").check }
        .to raise_error(Connectors::ConnectionError, /password authentication failed/)
    end

    it "explains an unknown host" do
      expect { connector(host: "no-such-host").check }
        .to raise_error(Connectors::ConnectionError, /could not translate host name/)
    end

    it "explains an unknown database" do
      expect { connector(database: "nope").check }
        .to raise_error(Connectors::ConnectionError, /database "nope" does not exist/)
    end

    it "explains a closed port" do
      expect { connector(port: 5999).check }
        .to raise_error(Connectors::ConnectionError, /Connection refused/)
    end

    it "never puts the password in the error message" do
      expect { connector(password: "wrong-s3cret").check }
        .to raise_error(Connectors::ConnectionError) { |error|
          expect(error.message).not_to include("wrong-s3cret")
        }
    end
  end
end
