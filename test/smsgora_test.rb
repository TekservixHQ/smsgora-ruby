# frozen_string_literal: true

require 'minitest/autorun'
require 'socket'
require 'json'
require 'openssl'
require 'smsgora'

# Tiny HTTP server so tests need no extra gems.
class FakeServer
  attr_reader :port, :last

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @last = nil
    @thread = Thread.new { loop { handle(@server.accept) } }
  end

  def handle(sock)
    line = sock.gets or return
    method, path, = line.split(' ')
    headers = {}
    while (h = sock.gets) && h != "\r\n"
      k, v = h.split(':', 2)
      headers[k.downcase] = v.strip
    end
    body = headers['content-length'] ? sock.read(headers['content-length'].to_i) : ''
    @last = { method: method, path: path, headers: headers, body: body.empty? ? nil : JSON.parse(body) }
    status, extra, reply = if path.start_with?('/limit')
                             [429, "Retry-After: 7\r\n", '{"success":false,"message":"Too many requests"}']
                           else
                             [200, '', '{"success":true,"data":{"message_ids":[1873]}}']
                           end
    sock.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\n#{extra}Content-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
  ensure
    sock&.close
  end
end

class SmsGoraTest < Minitest::Test
  SERVER = FakeServer.new

  def client(prefix = '')
    SmsGora::Client.new(api_key: 'sgk_test', base_url: "http://127.0.0.1:#{SERVER.port}#{prefix}/")
  end

  def test_send_sms
    assert_equal({ 'message_ids' => [1873] }, client.send_sms(to: '+1555', message: 'hi'))
    last = SERVER.last
    assert_equal ['POST', '/send-sms'], [last[:method], last[:path]]
    assert_equal 'sgk_test', last[:headers]['x-api-key']
    assert_equal({ 'recipients' => ['+1555'], 'message' => 'hi' }, last[:body])
  end

  def test_send_from_device
    client.send_sms(to: ['+1', '+2'], message: 'x', device_id: 42, sim_slot: 1, schedule_at: Time.utc(2026, 12, 1, 8))
    last = SERVER.last
    assert_equal '/devices/42/send-sms', last[:path]
    assert_equal 1, last[:body]['sim_slot']
    assert_equal '2026-12-01T08:00:00Z', last[:body]['schedule_at']
  end

  def test_paths_and_queries
    c = client
    c.list_received_sms(device_id: 3, limit: 5, since: nil)
    assert_equal '/devices/3/get-received-sms?limit=5', SERVER.last[:path]
    c.list_messages(status: 'sent')
    assert_equal '/messages?status=sent', SERVER.last[:path]
    c.delete_webhook(9)
    assert_equal ['DELETE', '/webhooks/9'], [SERVER.last[:method], SERVER.last[:path]]
    c.send_bulk_sms(42, messages: [{ recipients: ['+1'] }], message_template: 't')
    assert_equal({ 'messages' => [{ 'recipients' => ['+1'] }], 'messageTemplate' => 't' }, SERVER.last[:body])
  end

  def test_errors
    err = assert_raises(SmsGora::Error) { client('/limit').get_account }
    assert_equal 429, err.status
    assert_equal 7.0, err.retry_after
    assert_equal 'Too many requests', err.message
  end

  def test_requires_key
    assert_raises(ArgumentError) { SmsGora::Client.new(api_key: '') }
  end

  def test_webhook
    raw = '{"event":"sms.received"}'
    sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 's3cret', raw)}"
    assert SmsGora.verify_webhook(raw, sig, 's3cret')
    refute SmsGora.verify_webhook(raw, sig, 'nope')
    refute SmsGora.verify_webhook(raw, nil, 's3cret')
  end
end
