module Connectors
  class Base
    def initialize(config)
      @config = config
    end

    def check
      raise NotImplementedError, "#{self.class.name} must implement #check"
    end

    def discover
      raise NotImplementedError, "#{self.class.name} must implement #discover"
    end

    def read(stream, sync)
      raise NotImplementedError, "#{self.class.name} must implement #read"
    end

    private

    attr_reader :config
  end
end
