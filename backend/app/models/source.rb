class Source < ApplicationRecord
  serialize :config, coder: JSON
  encrypts  :config

  validates  :name, presence: true, uniqueness: true, length: { maximum: 30 }
  normalizes :name, with: ->(name) { name.strip.downcase }
  validates  :name, format: { with: /\A[a-z][a-z0-9_]*\z/ }

  validates :connector, presence: true
  enum :connector, { postgres: "postgres", data_gouv: "data_gouv", http: "http" }, validate: true

  validates :config, presence: true
  validate  :source_config_validate?

  has_many :streams, dependent: :destroy

  CONNECTOR_CLASSES = {
    "postgres"  => Connectors::Postgres,
    "data_gouv" => Connectors::DataGouv,
    "http"      => Connectors::Http
  }.freeze

  def source_config_validate?
    return unless CONNECTOR_CLASSES.key?(connector)
    return if config.blank?

    CONNECTOR_CLASSES.fetch(connector)::REQUIRED_CONFIG.each do |attr|
      if config[attr].blank?
        errors.add(:config, "is missing #{attr}")
      end
    end
  end

  def discover!
    found_ids = connector_instance.discover.map do |table|
      stream = streams.find_or_initialize_by(schema_name: table[:schema], name: table[:name])

      if table[:destination]
        stream.destination_table ||= "#{name}__#{table[:destination]}"
      else
        stream.destination_table ||= Stream.destination_table_for(name, table[:schema], table[:name])
      end

      stream.update!(source_columns: table[:columns], source_primary_key: table[:primary_key], removed_at: nil)
      stream.id
    end

    streams.active.where.not(id: found_ids).update_all(removed_at: Time.current)
  end

  def sync!
    streams.to_sync.map do |stream|
      stream.sync!
    rescue StandardError
      stream.syncs.last
    end
  end


  def connector_instance
    CONNECTOR_CLASSES.fetch(connector).new(config)
  end
end
