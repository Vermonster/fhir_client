module FHIR
  class Reference
    def contained?
      reference.to_s.start_with?('#')
    end

    def id
      if contained?
        reference.to_s[1..-1]
      else
        reference.to_s.split("/").last
      end
    end

    def klass
      raise ArgumentError if contained?
      "FHIR::#{reference.to_s.split("/").first}".constantize
    end
  end
end
