module FHIR
  class ClientReply

    @@validation_rules = JSON.parse( File.open(File.join(File.expand_path('..',File.dirname(File.absolute_path(__FILE__))),'fhir_api_validation.json'),'r:UTF-8',&:read) )
    @@path_regexes = {
      '[type]' => "(#{FHIR::RESOURCES.join('|')})",
      '[id]' => FHIR::PRIMITIVES['id']['regex'],
      '[vid]' => FHIR::PRIMITIVES['id']['regex'],
      '[name]' => "([A-Za-z\-]+)"
    }
    @@rfs1123 = /\A\s*
      (?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*,\s*)?
      (\d{1,2})\s+
      (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+
      (\d{2,})\s+
      (\d{2})\s*
      :\s*(\d{2})\s*
      (?::\s*(\d{2}))?\s+
      ([+-]\d{4}|
       UT|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|[A-IK-Z])/ix

    @@header_regexes = {
      'Content-Type' => Regexp.new("(#{FHIR::Formats::ResourceFormat::RESOURCE_XML.gsub('+','\\\+')}|#{FHIR::Formats::ResourceFormat::RESOURCE_JSON.gsub('+','\\\+')})(([ ;]+)(charset)([ =]+)(UTF-8|utf-8))?"),
      'Accept' => Regexp.new("(#{FHIR::Formats::ResourceFormat::RESOURCE_XML.gsub('+','\\\+')}|#{FHIR::Formats::ResourceFormat::RESOURCE_JSON.gsub('+','\\\+')})"),
      'Prefer' => Regexp.new("(return=minimal|return=representation)"),
      'ETag' => Regexp.new('(W\/)?"[\dA-Za-z]+"'),
      'If-Modified-Since' => @@rfs1123,
      'If-Match' => Regexp.new('(W\/)?"[\dA-Za-z]+"'),
      'If-None-Match' => Regexp.new('(W\/)?"[\dA-Za-z]+"'),
      'If-None-Exist' => Regexp.new('([\w\-]+(=[\w\-.:\/\|]*)?(&[\w\-]+(=[\w\-.:\/\|]*)?)*)?'),
      'Location' => Regexp.new("http(s)?:\/\/[A-Za-z0-9\/\\-\\.]+\/#{@@path_regexes['[type]']}\/#{@@path_regexes['[id]']}\/_history\/#{@@path_regexes['[vid]']}"),
      'Last-Modified' => @@rfs1123
    }

    # {
    #   :method => :get,
    #   :url => 'http://bonfire.mitre.org/fhir/Patient/123/$everything',
    #   :path => 'Patient/123/$everything'
    #   :headers => {},
    #   :payload => nil # body of request goes here in POST
    # }
    attr_accessor :request  
    # {
    #   :code => '200',
    #   :headers => {},
    #   :body => '{xml or json here}'
    # }
    attr_accessor :response 
    attr_accessor :resource # a FHIR resource
    attr_accessor :resource_class # class of the :resource

    def initialize(request, response)
      @request = request
      @response = response
    end

    def code
      @response[:code].to_i unless @response.nil?
    end

    def id
      return nil if @resource_class.nil?
      (self_link || @request[:url]) =~ %r{(?<=#{@resource_class.name.demodulize}\/)([^\/]+)}
      $1
    end

    def version
      self_link =~ %r{(?<=_history\/)(\w+)}
      $1
    end

    def self_link
      (@response[:headers]['content-location'] || @response[:headers]['location']) unless @response.nil? || @response[:headers].nil?
    end

    def body
      @response[:body] unless @response.nil?
    end

    def to_hash
      hash = {}
      hash['request'] = @request
      hash['response'] = @response
      hash
    end

    def is_valid?
      validate.empty?
    end

    def validate
      errors = []
      @@validation_rules.each do |rule|
        if rule['verb']==@request[:method].to_s.upcase
          rule_match = false
          rule['path'].each do |path|
            rule_regex = path.gsub('/','(\/)').gsub('?','\?')
            @@path_regexes.each do |token,regex|
              rule_regex.gsub!(token,regex)
            end
            rule_match = true if(Regexp.new(rule_regex) =~ @request[:path])
          end
          if rule_match
            # check the request headers
            errors << validate_headers("#{rule['interaction'].upcase} REQUEST",@request[:headers],rule['request']['headers'])
            # check the request body
            errors << validate_body("#{rule['interaction'].upcase} REQUEST",@request[:payload],rule['request']['body'])
            # check the response codes
            if !rule['response']['status'].include?(@response[:code].to_i)
              errors << "#{rule['interaction'].upcase} RESPONSE: Invalid response code: #{@response[:code]}" 
            end
            if @response[:code].to_i < 400
              # check the response headers
              errors << validate_headers("#{rule['interaction'].upcase} RESPONSE",@response[:headers],rule['response']['headers'])
              # check the response body
              errors << validate_body("#{rule['interaction'].upcase} RESPONSE",@response[:body],rule['response']['body'])
            end
          end
        end
      end
      errors.flatten
    end

    def validate_headers(name,headers,header_rules)
      errors = []
      header_rules.each do |header,present|
        value = headers[header]
        if present==true
          if value
            errors << "#{name}: Malformed value for header #{header}: #{value}" if !(@@header_regexes[header] =~ value)
          else
            errors << "#{name}: Missing header: #{header}"
          end
        elsif (present=='optional' && value)
          errors << "#{name}: Malformed value for optional header #{header}: #{value}" if !(@@header_regexes[header] =~ value)
          binding.pry if !(@@header_regexes[header] =~ value)
        elsif !value.nil?
          errors << "#{name}: Should not have header: #{header}"
        end
      end
      errors
    end

    def validate_body(name,body,body_rules)
      errors = []
      if body && body_rules
        if body_rules['types']
          body_type_match = false
          body_rules['types'].each do |type|
            begin
              content = FHIR.from_contents(body)
              body_type_match = true if content.resourceType==type
              body_type_match = true if type=='Resource' && FHIR::RESOURCES.include?(content.resourceType)
            rescue
            end
          end
          errors << "#{name}: Body does not match allowed types: #{body_rules['types'].join(', ')}" if !body_type_match              
        end
        if body_rules['regex']
          regex = Regexp.new(body_rules['regex'])
          errors << "#{name}: Body does not match regular expression: #{body_rules['regex']}" if !(regex =~ body)
        end
      elsif body && !body_rules
        errors "#{name}: Body not allowed"
      end
      errors
    end

    private :validate_headers, :validate_body

  end
end