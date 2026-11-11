# SMS Gora Ruby client

[![Gem Version](https://badge.fury.io/rb/smsgora.svg)](https://rubygems.org/gems/smsgora)

**SMS Gora SMS Gateway** - official Ruby client: send and receive SMS through your own Android phones. By Tekservix.

Ruby client for the [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) API.

SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway. Your server calls the API, a linked phone sends the text, and replies and delivery reports come back to you. There's no sender ID registration and no per-message fee from us: your mobile operator bills the texts like any SMS.

- Ruby 2.7+, no dependencies (standard library only)
- Works in Rails, Sinatra, Hanami, Sidekiq jobs and scripts
- Webhook signature check built in

## Install

```bash
gem install smsgora
```

or in your Gemfile:

```ruby
gem 'smsgora'
```

## Quick start

Create an API key in the SMS Gora dashboard (SMS Gora -> API keys) and keep it on your server.

```ruby
require 'smsgora'

sms = SmsGora::Client.new(api_key: ENV['SMSGORA_KEY'])

result = sms.send_sms(to: '+15551234567', message: 'Your verification code is 482913')
result['message_ids'] # => [1873]
```

## Sending

```ruby
# Several recipients (up to 1,000 per call)
sms.send_sms(to: ['+15551234567', '+447700900123'], message: 'Your order has shipped')

# From a chosen phone and SIM, scheduled for later
sms.send_sms(
  to: '+15551234567',
  message: 'Reminder: your appointment is tomorrow at 10:00',
  device_id: 42,
  sim_slot: 1, # 0 = SIM 1, 1 = SIM 2
  schedule_at: Time.utc(2026, 12, 1, 8, 0)
)

# Different texts for different people in one call (up to 5,000 recipients)
sms.send_bulk_sms(42,
  message_template: 'Hello, your parcel is ready for pickup.',
  messages: [
    { recipients: ['+15551234567'], message: 'Hi Aline, parcel #1042 is ready.' },
    { recipients: ['+15557654321'] }
  ])
```

## Delivery status and incoming SMS

```ruby
msg = sms.get_message(1873)
msg['status'] # queued -> dispatched -> sent -> delivered (or failed)

sms.cancel_message(1874) # works while queued or scheduled

inbox   = sms.list_received_sms(since: '2026-11-01', limit: 50)
phones  = sms.list_devices
account = sms.get_account
```

Anything else in the [API reference](https://tekservix.com/smsgora/docs/) is one call away:

```ruby
batch = sms.request(:get, '/batches/311')
```

## Webhooks

Add your HTTPS URL in SMS Gora -> Webhooks (or with `create_webhook`) and keep the secret. Each request carries `X-SmsGora-Signature: sha256=...`, an HMAC-SHA256 of the raw body. Rails example:

```ruby
class SmsWebhooksController < ActionController::API
  def create
    unless SmsGora.verify_webhook(request.raw_post, request.headers['X-SmsGora-Signature'], ENV['SMSGORA_WEBHOOK_SECRET'])
      return head :unauthorized
    end

    event = JSON.parse(request.raw_post)
    if event['event'] == 'sms.received'
      IncomingSmsJob.perform_later(event['data']['from'], event['data']['message'])
    end
    head :ok # answer within 10 seconds; do slow work in a job
  end
end
```

## Errors

Failed calls raise `SmsGora::Error` with `status`, `message`, field `errors` and, on 429, `retry_after` in seconds.

```ruby
begin
  sms.send_sms(to: '+15551234567', message: 'Hi')
rescue SmsGora::Error => e
  sleep(e.retry_after || 5) if e.status == 429 # 300 requests/minute per key, or plan limit
end
```

Never put the key in JavaScript or a mobile app: anyone could read it. Call the API from your server.

## Migrating from TextBee

SMS Gora accepts TextBee-style requests, so most integrations switch by changing the base URL and key. See the [compatibility notes](https://tekservix.com/smsgora/docs/).

## More from Tekservix

- [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/): send WhatsApp messages from your own number (`gem install waservix`)
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- SMS Gora is also available for Node.js, Python, PHP, Go, Java/Kotlin and .NET: see [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
