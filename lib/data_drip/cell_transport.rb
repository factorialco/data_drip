# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module DataDrip
  # Transports carry Cell API requests to other cells. A transport must respond
  # to call(cell_id:, method:, path:, body: nil) and return a Response; network
  # failures raise CellTransport::Error so callers can tell "the cell said no"
  # (an HTTP status) from "the cell is unreachable".
  module CellTransport
    class Error < DataDrip::Error
    end

    class Response
      attr_reader :status, :body

      def initialize(status:, body:)
        @status = status
        @body = body
      end

      def success?
        (200..299).cover?(status)
      end
    end

    # Plain HTTPS transport: JSON requests authenticated however the host's
    # `headers` say (typically a shared-secret bearer token).
    #
    #   DataDrip.cell_transport = DataDrip::CellTransport::Http.new(
    #     url: ->(cell_id) { "https://api.example.com/data_drip/cell_api" },
    #     query: ->(cell_id) { { cell_id: cell_id } },
    #     headers: -> { { "Authorization" => "Bearer #{ENV["DATA_DRIP_CELL_SECRET"]}" } }
    #   )
    #
    # `url` must point at the *Cell API* mount (not the human UI); paths passed
    # to #call are relative to it. `url`, `query` and `headers` each accept a
    # plain value or a callable (called with the cell id when it takes one).
    class Http
      NETWORK_ERRORS = [
        Timeout::Error,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::EPIPE,
        SocketError,
        EOFError,
        IOError,
        OpenSSL::SSL::SSLError
      ].freeze

      def initialize(url:, headers: nil, query: nil, open_timeout: 5, read_timeout: 20)
        @url = url
        @headers = headers
        @query = query
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def call(cell_id:, method:, path:, body: nil)
        uri = build_uri(cell_id, path)
        request = build_request(method, uri, body, cell_id)

        response =
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: @open_timeout,
            read_timeout: @read_timeout
          ) { |http| http.request(request) }

        Response.new(status: response.code.to_i, body: parse_body(response.body))
      rescue *NETWORK_ERRORS => e
        raise Error, "#{e.class}: #{e.message}"
      end

      private

      def build_uri(cell_id, path)
        base = resolve(@url, cell_id).to_s.chomp("/")
        uri = URI.parse("#{base}#{path}")

        extra_query = resolve(@query, cell_id)
        if extra_query.present?
          existing = URI.decode_www_form(uri.query.to_s)
          uri.query = URI.encode_www_form(existing + extra_query.to_a)
        end

        uri
      end

      def build_request(method, uri, body, cell_id)
        request_class =
          case method.to_s.downcase
          when "get" then Net::HTTP::Get
          when "post" then Net::HTTP::Post
          when "delete" then Net::HTTP::Delete
          else
            raise ArgumentError, "Unsupported HTTP method: #{method}"
          end

        request = request_class.new(uri)
        request["Accept"] = "application/json"
        resolve(@headers, cell_id).to_h.each { |key, value| request[key] = value }

        if body.present?
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end

        request
      end

      def parse_body(raw)
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def resolve(value, cell_id)
        return value unless value.respond_to?(:call)

        value.arity.zero? ? value.call : value.call(cell_id)
      end
    end
  end
end
