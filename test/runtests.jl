using WAservix
using Test
using JSON3

mutable struct Recorder
    calls::Vector{Any}
    status::Int
    reply::String
end
Recorder() = Recorder([], 200, """{"success":true,"data":{"msgId":58213,"status":"in_progress"}}""")

function client(r::Recorder)
    transport = (method, url, headers, body) -> begin
        push!(r.calls, (method = method, url = url, headers = Dict(headers), body = body === nothing ? nothing : JSON3.read(body)))
        (r.status, r.reply, Dict{String,String}())
    end
    return WAservix.Client("wpk_test"; base_url = "https://example.test/api", transport = transport)
end

@testset "WAservix" begin
    @testset "sending" begin
        r = Recorder(); wa = client(r)
        res = send_text(wa, "+1555", "hi")
        @test res["msgId"] == 58213
        @test r.calls[1].url == "https://example.test/api/send-message"
        @test r.calls[1].headers["Authorization"] == "Bearer wpk_test"
        @test Dict(string(k) => v for (k, v) in r.calls[1].body) == Dict("to" => "+1555", "text" => "hi")

        send_image(wa, "+1", "https://x/y.jpg")
        @test !haskey(r.calls[2].body, "text")
        @test r.calls[2].body["imageUrl"] == "https://x/y.jpg"
        send_document(wa, "+1", "https://x/a.pdf"; file_name = "a.pdf", caption = "c")
        @test r.calls[3].body["fileName"] == "a.pdf"
        send_location(wa, "+1", -1.9441, 30.0619; name = "Shop")
        @test r.calls[4].body["location"]["name"] == "Shop"
        send_message(wa, "1203@g.us"; poll = Dict("name" => "Lunch?", "options" => ["Yes", "No"]))
        @test r.calls[5].body["to"] == "1203@g.us"
        @test_throws ArgumentError send_text(wa, "", "x")
        @test_throws ArgumentError WAservix.Client("")
    end

    @testset "paths" begin
        r = Recorder(); wa = client(r)
        get_message_info(wa, 5)
        @test r.calls[1].url == "https://example.test/api/messages/5/info"
        edit_message(wa, 5, "t")
        @test r.calls[2].method == "PUT"
        on_whatsapp(wa, "+1555")
        @test r.calls[3].url == "https://example.test/api/on-whatsapp/%2B1555"
        get_group_metadata(wa, "1203@g.us")
        @test r.calls[4].url == "https://example.test/api/groups/1203%40g.us/metadata"
        connect_session(wa, 3)
        @test r.calls[5].body["method"] == "qr"
        connect_session(wa, 3; phone = "+1555")
        @test r.calls[6].body["phone"] == "+1555"
    end

    @testset "errors" begin
        r = Recorder(); r.status = 503; r.reply = """{"success":false,"message":"Device reconnecting"}"""
        err = try get_status(client(r)); nothing catch e; e end
        @test err isa WAservixError
        @test err.status == 503
        @test err.message == "Device reconnecting"

        r2 = Recorder(); r2.reply = """{"success":false,"message":"Invalid number"}"""
        err2 = try send_text(client(r2), "+1", "x"); nothing catch e; e end
        @test err2.message == "Invalid number"
    end

    @testset "webhook" begin
        @test verify_webhook("abc", "abc")
        @test !verify_webhook("abd", "abc")
        @test !verify_webhook("abcd", "abc")
        @test !verify_webhook(nothing, "abc")
    end
end
