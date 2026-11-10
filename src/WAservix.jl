"""
    WAservix

Julia client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and
gives you a REST API to send text, images, documents, locations, polls and more.

```julia
using WAservix
wa = WAservix.Client(ENV["WASERVIX_KEY"])
res = send_text(wa, "+15551234567", "Hello Aline, your order is ready")
res["msgId"]   # 58213
```

You need a Tekservix account with WAservix and your number's API key (Devices in the
dashboard). Keep it on your server. API reference: https://tekservix.com/waservix/docs/
"""
module WAservix

using HTTP
using JSON3

export send_message, send_text, send_image, send_document, send_location, get_message_info,
    edit_message, delete_message, resend_message, on_whatsapp, get_status, get_user,
    list_contacts, get_contact, save_contact, list_groups, get_group_metadata, list_sessions,
    get_session, create_session, connect_session, get_session_qr_code, verify_webhook, WAservixError

const PKG_VERSION = "1.0.0"
const DEFAULT_BASE_URL = "https://tekservix.com/waservix/api"

"""
    WAservixError

Thrown when the API answers with an error. Fields: `status` (0 if the request never reached
the API), `message`, `errors`, `body`, `retry_after`. A 503 means the number is reconnecting.
"""
struct WAservixError <: Exception
    status::Int
    message::String
    errors::Any
    body::Any
    retry_after::Union{Nothing,Float64}
end

Base.showerror(io::IO, e::WAservixError) = print(io, "WAservix: ", e.message, " (HTTP ", e.status, ")")

function default_transport(method, url, headers, body)
    res = HTTP.request(method, url, headers, body === nothing ? UInt8[] : body;
        status_exception = false, retry = false, readtimeout = 30)
    return res.status, String(res.body), Dict(lowercase(String(k)) => String(v) for (k, v) in res.headers)
end

"""
    WAservix.Client(api_key; base_url = DEFAULT_BASE_URL, transport = default_transport)

`transport(method, url, headers, body) -> (status, body, headers)` can be replaced for tests or proxies.
"""
struct Client
    api_key::String
    base_url::String
    transport::Function
end

function Client(api_key::AbstractString; base_url::AbstractString = DEFAULT_BASE_URL, transport::Function = default_transport)
    isempty(api_key) && throw(ArgumentError("WAservix: api_key is required (Devices → API key in the WAservix dashboard)"))
    return Client(String(api_key), rstrip(String(base_url), '/'), transport)
end

esc(x) = HTTP.URIs.escapeuri(string(x))

"""
    request(client, method, path, body = nothing)

Call any documented endpoint, e.g. `WAservix.request(wa, "GET", "/groups")`. Returns the `data` field.
"""
function request(c::Client, method::AbstractString, path::AbstractString, body = nothing)
    headers = [
        "Authorization" => "Bearer " * c.api_key,
        "Accept" => "application/json",
        "User-Agent" => "waservix-julia/$PKG_VERSION",
    ]
    payload = nothing
    if body !== nothing
        push!(headers, "Content-Type" => "application/json")
        payload = JSON3.write(body)
    end
    status, text, resp_headers = try
        c.transport(uppercase(method), c.base_url * path, headers, payload)
    catch err
        throw(WAservixError(0, "request failed: " * sprint(showerror, err), nothing, nothing, nothing))
    end
    data = isempty(text) ? nothing : (try JSON3.read(text) catch; nothing end)
    isobj = data isa JSON3.Object
    if status >= 400 || (isobj && get(data, :success, true) === false)
        msg = isobj && get(data, :message, nothing) isa AbstractString ? String(data[:message]) : "HTTP $status"
        retry = get(resp_headers, "retry-after", nothing)
        throw(WAservixError(status, msg, isobj ? get(data, :errors, nothing) : nothing,
            data === nothing ? text : data, retry === nothing ? nothing : tryparse(Float64, retry)))
    end
    return isobj && haskey(data, :data) ? data[:data] : data
end

"""
    send_message(client, to; fields...)

Send any message type to a number or group JID (`...@g.us`). Keyword names follow the API:
`text`, `imageUrl`, `videoUrl`, `audioUrl`, `documentUrl`, `fileName`, `stickerUrl`, `contact`,
`location`, `poll`, `replyTo`, `mentions`, `viewOnce`. Returns `{"msgId", "jid", "status"}`.
"""
function send_message(c::Client, to::AbstractString; fields...)
    isempty(to) && throw(ArgumentError("send_message: \"to\" is required (international number or group JID)"))
    body = Dict{String,Any}(string(k) => v for (k, v) in fields if v !== nothing)
    body["to"] = to
    return request(c, "POST", "/send-message", body)
end

send_text(c::Client, to, text) = send_message(c, to; text = text)
send_image(c::Client, to, image_url; caption = nothing) = send_message(c, to; imageUrl = image_url, text = caption)
send_document(c::Client, to, document_url; file_name = nothing, caption = nothing) =
    send_message(c, to; documentUrl = document_url, fileName = file_name, text = caption)

function send_location(c::Client, to, latitude::Real, longitude::Real; name = nothing)
    location = Dict{String,Any}("latitude" => latitude, "longitude" => longitude)
    name === nothing || (location["name"] = name)
    return send_message(c, to; location = location)
end

"Status: queued, sent, delivered, read, played or failed."
get_message_info(c::Client, id) = request(c, "GET", "/messages/$(esc(id))/info")
"Edit one of your own text messages (about 15 minutes after sending)."
edit_message(c::Client, id, text) = request(c, "PUT", "/messages/$(esc(id))", Dict("text" => text))
delete_message(c::Client, id) = request(c, "DELETE", "/messages/$(esc(id))")
resend_message(c::Client, id) = request(c, "POST", "/messages/$(esc(id))/resend")

"Is this number on WhatsApp? Returns `{\"exists\": true/false, \"jid\": ...}`."
on_whatsapp(c::Client, phone) = request(c, "GET", "/on-whatsapp/$(esc(phone))")
"connected, connecting, need_scan, disconnected, logged_out or expired."
get_status(c::Client) = request(c, "GET", "/status")
get_user(c::Client) = request(c, "GET", "/user")
list_contacts(c::Client) = request(c, "GET", "/contacts")
get_contact(c::Client, phone) = request(c, "GET", "/contacts/$(esc(phone))")
save_contact(c::Client, phone, name) = request(c, "PUT", "/contacts", Dict("phone" => phone, "name" => name))
list_groups(c::Client) = request(c, "GET", "/groups")
get_group_metadata(c::Client, jid) = request(c, "GET", "/groups/$(esc(jid))/metadata")

"Sessions need a personal access token, not a device key."
list_sessions(c::Client) = request(c, "GET", "/whatsapp-sessions")
get_session(c::Client, id) = request(c, "GET", "/whatsapp-sessions/$(esc(id))")
create_session(c::Client, params = Dict{String,Any}()) = request(c, "POST", "/whatsapp-sessions", params)

"Connect by QR code, or by pairing code when `phone` is given."
connect_session(c::Client, id; phone = nothing) = request(c, "POST", "/whatsapp-sessions/$(esc(id))/connect",
    phone === nothing ? Dict("method" => "qr") : Dict("method" => "code", "phone" => phone))

get_session_qr_code(c::Client, id) = request(c, "GET", "/whatsapp-sessions/$(esc(id))/qrcode")

"""
    verify_webhook(signature, secret) -> Bool

Constant-time check of the `X-Webhook-Signature` header against your number's webhook secret.
"""
function verify_webhook(signature, secret)
    (signature === nothing || secret === nothing || isempty(signature) || isempty(secret)) && return false
    a, b = codeunits(String(signature)), codeunits(String(secret))
    length(a) == length(b) || return false
    diff = 0x00
    for i in eachindex(a)
        diff |= a[i] ⊻ b[i]
    end
    return diff == 0x00
end

end # module
