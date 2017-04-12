%%--------------------------------------------------------------------
%% Copyright (c) 2016-2017 Feng Lee <feng@emqtt.io>. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqttd_coap_SUITE).

-compile(export_all).

-define(PORT, 5683).

-include("emq_coap.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [case34].

all333() ->
    [
        case01_parser, case02_parser, case03_parser, case04_parser, case05_parser,
        case06_parser, case07_parser, case08_parser, case09_parser, case10_parser,
        case11_parser, case12_parser,

        case20_format_error, case21_format_error, case22_format_error,

        case30, case31, case32, case33, case34
    ].


init_per_suite(Config) ->
    lager_common_test_backend:bounce(debug),
    R1 = application:start(cbor),
    R3 = application:start(gen_logger),
    R2 = application:start(esockd),
    io:format("R1=~p, R2=~p, R3=~p", [R1, R2, R3]),
    Config.

end_per_suite(Config) ->
    application:stop(cbor),
    application:stop(esockd),
    Config.


case01_parser(_Config) ->
    Raw = <<1:2, 0:2, 0:4, 0:8, 0:16>>,
    Msg = emq_coap_message:parse(Raw),
    #coap_message{type = 'CON', code = {0, 0}, id = 0} = Msg,
    Raw = emq_coap_message:serialize(Msg).

case02_parser(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16>>,
    Msg = emq_coap_message:parse(Raw),
    #coap_message{type = 'CON', code = {0, 0}, id = 5, token = <<333:16>>} = Msg,
    Raw = emq_coap_message:serialize(Msg).

case03_parser(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16, 1:4, 0:4>>,
    Msg = emq_coap_message:parse(Raw),
    #coap_message{type = 'CON', code = {0, 0}, id = 5, token = <<333:16>>, options = [{'If-Match', <<>>}]} = Msg,
    Raw = emq_coap_message:serialize(Msg).

case04_parser(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16, 3:4, 11:4, "example.com">>,
    Msg = emq_coap_message:parse(Raw),
    #coap_message{type = 'CON', code = {0, 0}, id = 5, token = <<333:16>>, options = [{'Uri-Host', <<"example.com">>}]} = Msg,
    Raw = emq_coap_message:serialize(Msg).

case05_parser(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16, 3:4, 13:4, 2:8, "www.example.com">>,
    Msg = emq_coap_message:parse(Raw),
    #coap_message{type = 'CON', code = {0, 0}, method = undefined, id = 5, token = <<333:16>>, options = [{'Uri-Host', <<"www.example.com">>}]} = Msg,
    Raw = emq_coap_message:serialize(Msg).

case06_parser(_Config) ->
    Raw = <<1:2, 1:2, 2:4, 2:3, 1:5, 5:16, 555:16, 3:4, 13:4, 2:8, "www.example.com", 4:4, 2:4, 3456:16>>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'NON', code = {2, 1}, id = 5, token = <<555:16>>, options = [{'Uri-Host', <<"www.example.com">>}, {'Uri-Port', 3456}]} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'Created'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case07_parser(_Config) ->
    LongText = <<"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz">>,
    Raw = <<1:2, 1:2, 2:4, 2:3, 1:5, 5:16, 555:16, 3:4, 14:4, 43:16, LongText/binary, 4:4, 2:4, 3456:16>>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'NON', code = {2, 1}, id = 5, token = <<555:16>>, options = [{'Uri-Host', LongText}, {'Uri-Port', 3456}]} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'Created'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case08_parser(_Config) ->
    Raw = <<1:2, 1:2, 2:4, 2:3, 1:5, 5:16, 555:16, 3:4, 13:4, 2:8, "www.example.com", 4:4, 2:4, 3456:16, 255:8, "1234567">>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'NON', code = {2, 1}, id = 5, token = <<555:16>>, options = [{'Uri-Host', <<"www.example.com">>}, {'Uri-Port', 3456}], payload = <<"1234567">>} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'Created'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case09_parser(_Config) ->
    Raw = <<1:2, 1:2, 2:4, 2:3, 1:5, 5:16, 555:16, 3:4, 13:4, 2:8, "www.example.com", 4:4, 2:4, 3456:16, 14:4, 0:4, 1000:16, 255:8, "1234567">>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'NON', code = {2, 1}, id = 5, token = <<555:16>>, options = [{'Uri-Host', <<"www.example.com">>}, {'Uri-Port', 3456}, {1276, <<>>}], payload = <<"1234567">>} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'Created'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case10_parser(_Config) ->
    Raw = <<1:2, 1:2, 0:4, 2:3, 1:5, 5:16, 255:8, "1234567">>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'NON', code = {2, 1}, id = 5, payload = <<"1234567">>} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'Created'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case11_parser(_Config) ->
    Raw = <<1:2, 2:2, 0:4, 4:3, 4:5, 5:16, 255:8, "1234567">>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'ACK', code = {4, 4}, id = 5, payload = <<"1234567">>} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'NotFound'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    Raw = Output.

case12_parser(_Config) ->
    Raw = <<1:2, 3:2, 0:4, 0:3, 0:5, 5:16, 255:8, "1234567">>,
    Msg = emq_coap_message:parse(Raw),
    io:format("Msg=~p~n", [Msg]),
    #coap_message{type = 'RST', code = {0, 0}, id = 5, payload = <<"1234567">>} = Msg,
    Output = emq_coap_message:serialize(Msg#coap_message{code = 'NotFound'}),
    io:format("   Raw=~p~n", [Raw]),
    io:format("Output=~p~n", [Output]),
    <<1:2, 3:2, 0:4, 0:3, 0:5, 5:16>> = Output.

case20_format_error(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16, 3:4, 15:4, "www.example.com">>,
    case catch(emq_coap_message:parse(Raw)) of
        Msg = #coap_message{} ->
            error({not_expected, Msg});
        {'EXIT', {format_error, _}} ->
            "this is expected"
    end.

case21_format_error(_Config) ->
    Raw = <<1:2, 0:2, 2:4, 0:8, 5:16, 333:16, 3:4, 13:4, 15:8, "www.example.com">>,
    case catch(emq_coap_message:parse(Raw)) of
        Msg = #coap_message{} ->
            error({not_expected, Msg});
        {'EXIT', {format_error, _}} ->
            "this is expected"
    end.

case22_format_error(_Config) ->
    test_random_binary(),
    test_random_binary(),
    test_random_binary(),
    test_random_binary(),
    test_random_binary(),
    test_random_binary().

test_random_binary() ->
    Raw = generate_random_binary(),
    io:format("Raw=~p~n", [Raw]),
    case catch(emq_coap_message:parse(Raw)) of
        Msg = #coap_message{} ->
            Msg;
        {'EXIT', {format_error, _}} ->
            ok
    end.


case30(_Config) ->
    What = application:start(emq_coap),
    io:format("What=~p", [What]),
    ok = What,
    test_broker_api:start_link(),

    {ok, USock} = gen_udp:open(0, [binary, {active, false}]),
    Topic = <<"abc">>,
    Content = <<"12345">>,
    Topic1 = encode(Topic),
    Content1 = encode(Content),
    Msg = emq_coap_message:serialize_request(#coap_message{type = 'CON',code = 'POST', id = 35, options = [{'Uri-Host', "localhost"}, { 'Uri-Path', "mqtt"}], payload = <<"topic=", Topic1/binary, "&message=", Content1/binary>>}),
    gen_udp:send(USock, "localhost", ?PORT, Msg),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet}} = gen_udp:recv(USock, 256),
    #coap_message{type = 'ACK', code = {2, 1}, id = 35} = emq_coap_message:parse(Packet),
    PubMsg = test_broker_api:get_published_msg(),
    io:format("published message is ~p~n", [PubMsg]),

    {coap, Topic, Content} = PubMsg,
    gen_udp:close(USock),
    test_broker_api:stop(),
    application:stop(emq_coap).

case31(_Config) ->
    What = application:start(emq_coap),
    io:format("What=~p", [What]),
    ok = What,
    test_broker_api:start_link(),

    {ok, USock} = gen_udp:open(0, [binary, {active, false}]),
    Topic = <<"/abc/X7yz">>,
    Content = <<"12345", 5>>,
    Topic1 = encode(Topic),
    Content1 = encode(Content),
    Msg = emq_coap_message:serialize_request(#coap_message{type = 'CON',code = 'POST', id = 35, options = [{'Uri-Host', "localhost"}, { 'Uri-Path', "mqtt"}], payload = <<"topic=", Topic1/binary, "&message=", Content1/binary>>}),
    gen_udp:send(USock, "localhost", ?PORT, Msg),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet}} = gen_udp:recv(USock, 256),
    #coap_message{type = 'ACK', code = {2, 1}, id = 35} = emq_coap_message:parse(Packet),
    PubMsg = test_broker_api:get_published_msg(),
    io:format("published message is ~p~n", [PubMsg]),

    {coap, Topic, Content} = PubMsg,
    gen_udp:close(USock),
    test_broker_api:stop(),
    application:stop(emq_coap).


case32(_Config) ->
    What = application:start(emq_coap),
    io:format("What=~p", [What]),
    ok = What,
    test_broker_api:start_link(),

    {ok, USock} = gen_udp:open(0, [binary, {active, false}]),
    Topic = <<"/abc/X7yz">>,
    Topic1 = encode(Topic),
    Msg = emq_coap_message:serialize_request(#coap_message{type = 'CON',code = 'GET', id = 35,
                                                 options = [{'Uri-Host', "localhost"},
                                                            { 'Uri-Path', "mqtt"},
                                                            {'Uri-Query', binary_to_list(<<"topic=", Topic1/binary>>)},
                                                            {'Observe', 0}]}),
    gen_udp:send(USock, "localhost", ?PORT, Msg),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet}} = gen_udp:recv(USock, 256),
    CoapMsg = emq_coap_message:parse(Packet),
    io:format("CoapMsg=~p", [CoapMsg]),
    #coap_message{type = 'ACK', code = {2, 5}, id = 35, options = [{'Observe', 1}]} = CoapMsg,
    SubTopic = test_broker_api:get_subscrbied_topic(),
    io:format("subscribed topic is ~p~n", [SubTopic]),

    Topic = SubTopic,
    gen_udp:close(USock),
    test_broker_api:stop(),
    application:stop(emq_coap).


case33(_Config) ->
    What = application:start(emq_coap),
    io:format("What=~p", [What]),
    ok = What,
    test_broker_api:start_link(),

    %% subscribe a wild match topic
    {ok, USock} = gen_udp:open(0, [binary, {active, false}]),
    Token = <<3, 5>>,
    Topic = <<"/abc/#">>,
    Topic1 = encode(Topic),
    Msg = emq_coap_message:serialize_request(#coap_message{type = 'CON',code = 'GET', id = 35,
                                        token = Token,
                                        options = [{'Uri-Host', "localhost"},
                                            { 'Uri-Path', "mqtt"},
                                            {'Uri-Query', binary_to_list(<<"topic=", Topic1/binary>>)},
                                            {'Observe', 0}]}),
    gen_udp:send(USock, "localhost", ?PORT, Msg),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet}} = gen_udp:recv(USock, 256),
    CoapMsg = emq_coap_message:parse(Packet),
    io:format("CoapMsg=~p", [CoapMsg]),
    #coap_message{type = 'ACK', code = {2, 5}, id = 35, options = [{'Observe', 1}]} = CoapMsg,
    SubTopic = test_broker_api:get_subscrbied_topic(),
    io:format("subscribed topic is ~p~n", [SubTopic]),
    Topic = SubTopic,

    %% receive dispatched message from others
    test_broker_api:dispatch(<<"/abc/X">>, <<"900">>),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet3}} = gen_udp:recv(USock, 256),
    CoapMsg3 = emq_coap_message:parse(Packet3),
    io:format("CoapMsg=~p", [CoapMsg3]),
    #coap_message{type = 'CON', code = {2, 5}, token = Token, options = [{'Observe', 2}], payload = <<"topic=/abc/X&message=900">>} = CoapMsg3,

    %% unsubscribe topic
    Msg2 = emq_coap_message:serialize_request(#coap_message{type = 'CON',code = 'GET', id = 36,
                                        token = Token,
                                        options = [{'Uri-Host', "localhost"},
                                            { 'Uri-Path', "mqtt"},
                                            {'Uri-Query', binary_to_list(<<"topic=", Topic1/binary>>)},
                                            {'Observe', 1}]}),
    gen_udp:send(USock, "localhost", ?PORT, Msg2),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet2}} = gen_udp:recv(USock, 256),
    CoapMsg2 = emq_coap_message:parse(Packet2),
    io:format("CoapMsg=~p", [CoapMsg2]),
    #coap_message{type = 'ACK', code = {2, 5}, id = 36, token = Token, options = [{'Observe', 3}]} = CoapMsg2,
    UnSubTopic = test_broker_api:get_unsubscrbied_topic(),
    io:format("unsubscribed topic is ~p~n", [UnSubTopic]),
    Topic = UnSubTopic,


    gen_udp:close(USock),
    test_broker_api:stop(),
    application:stop(emq_coap).


case34(_Config) ->
    ok = application:set_env(?COAP_APP, keepalive, 2),
    What = application:start(emq_coap),
    io:format("What=~p", [What]),
    ok = What,
    test_broker_api:start_link(),

    {ok, USock} = gen_udp:open(0, [binary, {active, false}]),
    Topic = <<"/abc/X7yz">>,
    Topic1 = encode(Topic),
    Token = <<3, 5>>,
    CoapSubscribeMsg = #coap_message{type = 'CON',code = 'GET', id = 35, token = Token,
                                        options = [{'Uri-Host', "localhost"},
                                                   {'Uri-Path', "mqtt"},
                                                   {'Uri-Query', binary_to_list(<<"topic=", Topic1/binary>>)},
                                                   {'Observe', 0}]},
    Msg = emq_coap_message:serialize_request(CoapSubscribeMsg),
    gen_udp:send(USock, "localhost", ?PORT, Msg),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet}} = gen_udp:recv(USock, 256),
    CoapMsg = emq_coap_message:parse(Packet),
    ?assertEqual(#coap_message{type = 'ACK',token = Token, code = {2, 5}, id = 35, options = [{'Observe', 1}]}, CoapMsg),
    SubTopic = test_broker_api:get_subscrbied_topic(),
    ?assertEqual(Topic, SubTopic),

    %% broker try to dispatch message
    test_broker_api:dispatch(<<"/abc/X7yz">>, <<"900">>),
    timer:sleep(200),
    {ok, {_Address, _Port, Packet3}} = gen_udp:recv(USock, 256),
    CoapRcvedDispatchMsg = emq_coap_message:parse(Packet3),
    ?assertEqual(#coap_message{type = 'CON', code = {2, 5}, id = 1, token = Token, options = [{'Observe', 2}], payload = <<"topic=/abc/X7yz&message=900">>}, CoapRcvedDispatchMsg),

    % wait long enough, let emq_coap_channel and emq_coap_reponse become timeout and quit
    timer:sleep(5000),

    %% broker try to dispatch message again, client should receive nothing
    test_broker_api:dispatch(<<"/abc/X7yz">>, <<"900">>),
    timer:sleep(200),
    UdpRet = gen_udp:recv(USock, 256, 1000),
    ?assertEqual({error, timeout}, UdpRet),

    gen_udp:close(USock),
    test_broker_api:stop(),
    application:stop(emq_coap).



generate_random_binary() ->
    Len = rand:uniform(300),
    gen_next(Len, <<>>).

gen_next(0, Acc) ->
    Acc;
gen_next(N, Acc) ->
    Byte = rand:uniform(256) - 1,
    gen_next(N-1, <<Acc/binary, Byte:8>>).


encode(Payload) when is_list(Payload) ->
    list_to_binary(http_uri:encode(Payload));
encode(Payload) when is_binary(Payload) ->
    Payload1 = binary_to_list(Payload),
    list_to_binary(http_uri:encode(Payload1)).




