class Source < ApplicationRecord
  serialize :config, coder: JSON
  encrypts  :config

  validates  :name, presence: true, uniqueness: true, length: { maximum: 30 }
  normalizes :name, with: ->(name) { name.strip.downcase }
  validates  :name, format: { with: /\A[a-z][a-z0-9_]*\z/ }

  validates :connector, presence: true
  enum :connector, { postgres: "postgres" }, validate: true

  validates :config, presence: true
  validate  :source_config_validate?

  has_many :streams, dependent: :destroy

  CONNECTOR_CLASSES = { "postgres" => Connectors::Postgres }.freeze

  def source_config_validate?
    [ "host", "port", "database", "username", "password" ].each do |attr|
      return if config.blank?

      if config[attr].blank?
        errors.add(:config, "is missing #{attr}")
      end
    end
  end

  def connector_instance
    CONNECTOR_CLASSES.fetch(connector).new(config)
  end
end
