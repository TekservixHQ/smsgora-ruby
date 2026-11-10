# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

# Ruby client for the SMS Gora SMS Gateway API.
#
#   sms = SmsGora::Client.new(api_key: ENV['SMSGORA_KEY'])
#   sms.send_sms(to: '+15551234567', message: 'Your verification code is 482913')
#
# Docs: https://tekservix.com/smsgora/docs/
module SmsGora
  VERSION = '1.0.0'
  DEFAULT_BASE_URL = 'https://tekservix.com/smsgora/api/v1'

  # Raised when the API answers with an error.
  class Error < StandardError
    attr_reader :status, :errors, :body, :retry_after

    def initialize(message, status: nil, errors: nil, body: nil, retry_after: nil)
      super(message)
      @status = status
      @errors = errors
      @body = body
      @retry_after = retry_after
    end
  end

  class Client
    attr_reader :base_url

    # api_key: your SMS Gora API key (starts with sgk_). Keep it on your server.
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: 30)
      raise ArgumentError, 'SmsGora: api_key is required (create one in SMS Gora -> API keys)' if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = base_url.sub(%r{/+\z}, '')
      @timeout = timeout
    end

    # Call any documented endpoint, e.g. request(:get, '/devices'). Returns the `data` field.
    def request(method, path, body = nil)
      uri = URI(@base_url + path)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method.to_s.downcase.to_sym)
      req = klass.new(uri)
      req['x-api-key'] = @api_key
      req['Accept'] = 'application/json'
      req['User-Agent'] = "smsgora-ruby/#{VERSION}"
      unless body.nil?
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                open_timeout: @timeout, read_timeout: @timeout) { |http| http.request(req) }
      status = res.code.to_i
      text = res.body.to_s
      json = begin
        text.empty? ? nil : JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      if status >= 400 || (json.is_a?(Hash) && json['success'] == false)
        retry_after = res['Retry-After']
        raise Error.new((json.is_a?(Hash) && json['message']) || "HTTP #{status}",
                        status: status,
                        errors: json.is_a?(Hash) ? json['errors'] : nil,
                        body: json || text,
                        retry_after: retry_after && Float(retry_after, exception: false))
      end
      json.is_a?(Hash) && json.key?('data') ? json['data'] : json
    end

    # Send an SMS to one number or up to 1,000. Picks your best online phone unless device_id is given.
    # sim_slot: 0 = SIM 1, 1 = SIM 2. schedule_at: Time or ISO 8601 string.
    def send_sms(to:, message:, device_id: nil, sim_slot: nil, schedule_at: nil)
      body = { recipients: Array(to), message: message }
      body[:sim_slot] = sim_slot unless sim_slot.nil?
      body[:schedule_at] = schedule_at.respond_to?(:utc) ? schedule_at.utc.iso8601 : schedule_at if schedule_at
      path = device_id ? "/devices/#{esc(device_id)}/send-sms" : '/send-sms'
      request(:post, path, body)
    end

    # Different texts for different people in one call (up to 5,000 recipients).
    # messages: [{ recipients: ['+1555...'], message: 'optional own text' }, ...]
    def send_bulk_sms(device_id, messages:, message_template: nil)
      body = { messages: messages }
      body[:messageTemplate] = message_template if message_template
      request(:post, "/devices/#{esc(device_id)}/send-bulk-sms", body)
    end

    # Status is queued, dispatched, sent, delivered, failed or cancelled.
    def get_message(id)
      request(:get, "/messages/#{esc(id)}")
    end

    # Cancel a queued or scheduled message.
    def cancel_message(id)
      request(:post, "/messages/#{esc(id)}/cancel")
    end

    # Filters: direction (in/out), status, device_id, phone, since, after_id, page, limit.
    def list_messages(**filters)
      request(:get, "/messages#{query(filters)}")
    end

    # Incoming SMS for all phones, or one phone with device_id.
    def list_received_sms(device_id: nil, **filters)
      path = device_id ? "/devices/#{esc(device_id)}/get-received-sms" : '/received-sms'
      request(:get, path + query(filters))
    end

    def get_batch(id)
      request(:get, "/batches/#{esc(id)}")
    end

    # Your linked Android phones.
    def list_devices
      request(:get, '/devices')
    end

    def get_device(id)
      request(:get, "/devices/#{esc(id)}")
    end

    # Account, plan and usage.
    def get_account
      request(:get, '/account')
    end

    def list_webhooks
      request(:get, '/webhooks')
    end

    # Register a webhook. The answer includes the secret (only returned once).
    def create_webhook(url:, events: ['sms.received'], device_id: nil)
      request(:post, '/webhooks', { url: url, events: events, device_id: device_id })
    end

    def delete_webhook(id)
      request(:delete, "/webhooks/#{esc(id)}")
    end

    private

    def esc(value)
      URI.encode_www_form_component(value.to_s).gsub('+', '%20')
    end

    def query(params)
      clean = params.reject { |_, v| v.nil? || v.to_s.empty? }
      clean.empty? ? '' : "?#{URI.encode_www_form(clean)}"
    end
  end

  # Check the X-SmsGora-Signature header (sha256=<hex HMAC-SHA256 of the raw body>).
  # Pass the raw request body (e.g. request.raw_post in Rails), before JSON parsing.
  def self.verify_webhook(raw_body, signature, secret)
    return false if raw_body.nil? || raw_body.empty? || signature.nil? || signature.empty? || secret.nil? || secret.empty?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)}"
    secure_compare(expected, signature.to_s)
  end

  # Constant-time string comparison (works on every Ruby version).
  def self.secure_compare(a, b)
    return false unless a.bytesize == b.bytesize

    diff = 0
    a.bytes.zip(b.bytes) { |x, y| diff |= x ^ y }
    diff.zero?
  end
  private_class_method :secure_compare
end
