module FHIR
  class Model
    class << self
      cattr_accessor :client
    end

    attr_writer :client

    def client
      @client || self.class.client
    end

    def self.read(id, client = self.client)
      client.read(self, id).resource
    end

    def self.search(params = {}, client = self.client)
      client.search(self, search: { parameters: params }).resource
    end

    def self.create(model, client = self.client)
      model = new(model) unless model.is_a?(self)
      client.create(model).resource
    end

    def update
      client.update(self, id).resource
    end

    def destroy
      client.destroy(self, id) unless id.nil?
      nil
    end

    def save
      if id.nil?
        self.class.create(self, client)
      else
        update
      end
    end

    def resolve(reference)
      if reference.contained?
        contained.detect { |resource| resource.id == reference.id }
      else
        reference.klass.read(reference.id)
      end
    end
  end
end
