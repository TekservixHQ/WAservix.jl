# WAservix.jl

[![CI](https://github.com/TekservixHQ/WAservix.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/TekservixHQ/WAservix.jl/actions/workflows/CI.yml)

Julia client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and gives you a REST API to send text, images, documents, locations and polls. Handy for sending plots, reports and alerts from Julia scripts straight to WhatsApp.

## Install

```julia
using Pkg
Pkg.add("WAservix")
```

Julia 1.6+.

## Quick start

You need a Tekservix account with WAservix and your number's API key (Devices in the dashboard). Keep it out of shared notebooks.

```julia
using WAservix

wa = WAservix.Client(ENV["WASERVIX_KEY"])

res = send_text(wa, "+15551234567", "Training finished: accuracy 97.4%")
res["msgId"], res["status"]   # (58213, "in_progress")
```

## Sending

```julia
send_image(wa, "+15551234567", "https://example.com/plot.png"; caption = "Today's results")
send_document(wa, "+15551234567", "https://example.com/report.pdf"; file_name = "Report.pdf", caption = "Weekly report")
send_location(wa, "+15551234567", -1.9441, 30.0619; name = "Our office")

# Anything the API supports, including groups (JID ending in @g.us)
send_message(wa, "120363040000000000@g.us"; text = "Team meeting at 3pm")
send_message(wa, "+15551234567"; poll = Dict("name" => "Lunch?", "options" => ["Pizza", "Sushi"]))
```

## Status, contacts and groups

```julia
get_message_info(wa, 58213)        # queued, sent, delivered, read, played or failed
on_whatsapp(wa, "+15551234567")    # {"exists": true, "jid": "..."}
get_status(wa)                     # {"status": "connected"}
edit_message(wa, 58213, "Corrected text")
list_groups(wa)
WAservix.request(wa, "POST", "/messages/read", Dict("msgId" => "3EB0X123456789"))   # any other endpoint
```

## Webhooks

Each webhook request carries `X-Webhook-Signature`, which equals your number's webhook secret:

```julia
verify_webhook(HTTP.header(req, "X-Webhook-Signature"), ENV["WASERVIX_WEBHOOK_SECRET"]) || return HTTP.Response(401)
```

## Errors

Failed calls throw `WAservixError` with `status`, `message`, `errors`, `body` and `retry_after`. A 503 means the number is reconnecting.

## Use it responsibly

WAservix is not Meta's official WhatsApp Business Platform. There's no business verification and no per-conversation fee, but WhatsApp's spam rules apply to your number directly. Message people who expect to hear from you, warm up new numbers slowly and keep the built-in account protection on.

## More from Tekservix

- [SMS Gora SMS Gateway](https://tekservix.com/smsgora/): SMS through your own Android phones (`Pkg.add("SmsGora")`)
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- WAservix libraries for many more languages: [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
