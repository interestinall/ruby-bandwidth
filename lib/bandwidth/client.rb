require 'faraday'
require 'certified'
require 'json'
require 'active_support/core_ext/string/inflections'

module Bandwidth

  # Catapult client class. It is used by any api related class
  class Client
    # Initializer
    # @param user_id [String|Hash] user id to connect to Catapult API. If value is hash it will be used as options storage
    # @param api_token [String] token to connect to Catapult API.
    # @param api_secret [String] catapult API secret
    # @param api_endpoint [String] base url of Catapult API
    # @param api_version [String] version of Catapult API
    #
    # @example
    #   client = Client.new("userId", "token", "secret")
    #   client = Client.new(:user_id => "userId", :api_token => "token", :api_secret => "secret") # with has of options
    #   client = Client.new() #options from Client.global_options will be used here
    def initialize (user_id = nil, api_token = nil, api_secret = nil, api_endpoint = 'https://api.catapult.inetwork.com', api_version = 'v1')
      if api_token == nil && api_secret == nil
        if  user_id == nil
          user_id = @@global_options
        end
        if user_id.is_a?(Hash)
          opts = user_id
          api_version = opts[:api_version] if opts[:api_version]
          api_endpoint = opts[:api_endpoint] if opts[:api_endpoint]
          api_secret = opts[:api_secret]
          api_token = opts[:api_token]
          user_id = opts[:user_id]
        end
      end
      raise Errors::MissingCredentialsError.new() if (user_id || '').length == 0 || (api_token || '').length == 0 || (api_secret || '').length == 0
      @concat_user_path = lambda {|path| "/users/#{user_id}" + (if path[0] == "/" then path else "/#{path}" end) }
      @build_path = lambda {|path| "/#{api_version}" + (if path[0] == "/" then path else "/#{path}" end) }
      @set_adapter = lambda {|faraday| faraday.adapter(Faraday.default_adapter)}
      @create_connection = lambda{||
        Faraday.new(api_endpoint) { |faraday|
          faraday.basic_auth(api_token, api_secret)
          faraday.headers['Accept'] = 'application/json'
          faraday.headers['User-Agent'] = "ruby-bandwidth/v#{Bandwidth::VERSION}"
          @set_adapter.call(faraday)
        }
      }
      @api_endpoint = api_endpoint
      @api_version = api_version
    end

    attr_reader :api_endpoint, :api_version

    @@global_options = {}

    # Return global options
    # @return [Hash] Options
    def Client.global_options
      @@global_options
    end

    # Set global options
    # @param v [Hash] Options to set
    def Client.global_options=(v)
      @@global_options = v
    end

    # Extract id from location header
    # @param location [String] location header value
    # @return [String] extracted id
    def Client.get_id_from_location_header(location)
      items = (location || '').split('/')
      raise StandardError.new('Missing id in the location header') if items.size < 2
      items.last
    end

    # Make HTTP request to Catapult API
    # @param method [Symbol] http method to make
    # @param path [String] path of url (exclude api verion and endpoint) to make call
    # @param data [Hash] data  which will be sent with request (for :get and :delete request they will be sent with query in url)
    # @return [Array] array with 2 elements: parsed json data of response and response headers
    def make_request(method, path, data = {})
      d  = camelcase(data)
      connection = @create_connection.call()
      response =  if method == :get || method == :delete
                    connection.run_request(method, @build_path.call(path), nil, nil) do |req|
                      req.params = d unless d == nil || d.empty?
                    end
                  else
                    connection.run_request(method, @build_path.call(path), d.to_json(), {'Content-Type' => 'application/json'})
                  end
      check_response(response)
      r = if response.body.strip().size > 0 then symbolize(JSON.parse(response.body)) else {} end
      [r, symbolize(response.headers || {})]
    end

    # Check response object and raise error if status code >= 400
    # @param response response object
    def check_response(response)
      if response.status >= 400
        parsed_body = JSON.parse(response.body)
        raise Errors::GenericError.new(parsed_body['code'], parsed_body['message'])
      end
    end

    # Build url path like /users/<user-id>/<path>
    def concat_user_path(path)
      @concat_user_path.call(path)
    end

    # Return new configured connection object
    # @return [Faraday::Connection] connection
    def create_connection()
      @create_connection.call()
    end

    protected

    # Convert all keys of a hash to camel cased strings
    def camelcase v
      case
        when v.is_a?(Array)
          v.map {|i| camelcase(i)}
        when v.is_a?(Hash)
          result = {}
          v.each do |k, val|
            result[k.to_s().camelcase(:lower)] = camelcase(val)
          end
          result
        else
          v
      end
    end

    # Convert all keys of hash to underscored symbols
    def symbolize v
      case
        when v.is_a?(Array)
          v.map {|i| symbolize(i)}
        when v.is_a?(Hash)
          result = {}
          v.each do |k, val|
            result[k.underscore().to_sym()] = symbolize(val)
          end
          result
        else
          v
      end
    end
  end
end
