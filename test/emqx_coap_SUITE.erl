%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_coap_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("gen_coap/include/coap.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PORT, 5683).
-define(LOGT(Format, Args), ct:print("TEST_SUITE: " ++ Format, Args)).

suite() -> [{timetrap, {seconds, 30}}].

all() ->
    [ case01
    , case02
    , case03
    , case04
    , case05
    , case06_keepalive
    , case07_one_clientid_sub_2_topics
    , case10_auth_failure
    , case11_invalid_parameter
    , case12_invalid_topic
    , case13_emit_stats_test
    ].

init_per_suite(Config) ->
    application:set_env(emqx_coap, enable_stats, true),
    Config.

end_per_suite(Config) ->
    Config.

case01(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"abc">>, Payload = <<"123">>,
    TopicStr = binary_to_list(Topic),
    URI = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    {ok,changed, _} = Reply,
    timer:sleep(50),
    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p, Reply=~p~n", [PubMsg, Reply]),
    ?assertEqual({Topic, Payload}, PubMsg),
    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    Topic = <<"abc">>, TopicStr = binary_to_list(Topic),
    Payload = <<"123">>,
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    timer:sleep(100),
    SubTopics = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopics),

    test_mqtt_broker:dispatch(Topic, Payload, Topic),
    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,

    ?_assertEqual(Payload, PayloadRecv),

    er_coap_observer:stop(Pid),
    timer:sleep(100),
    SubTopics2 = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopics2),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% subscribe a wild char topic
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic = <<"+/b">>, TopicStr = http_uri:encode(binary_to_list(Topic)),
    Payload = <<"123">>,
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Uri=~p, Pid=~p, N=~p, Code=~p, Content=~p", [Uri, Pid, N, Code, Content]),

    timer:sleep(100),
    SubTopic = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopic),

    test_mqtt_broker:dispatch(<<"a/b">>, Payload, Topic),
    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,
    ?_assertEqual(Payload, PayloadRecv),

    er_coap_observer:stop(Pid),
    timer:sleep(100),
    SubTopic2 = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopic2),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% subscribe a wild char topic
    %% publish 2 topics
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic = <<"+/b">>, TopicStr = http_uri:encode(binary_to_list(Topic)),
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    timer:sleep(100),
    SubTopic = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopic),

    Topic2 = <<"a/b">>, Payload2 = <<"UFO">>,
    TopicStr2 = http_uri:encode(binary_to_list(Topic2)),
    URI2 = "coap://127.0.0.1/mqtt/"++TopicStr2++"?c=client1&u=tom&p=secret",
    Reply2 = er_coap_client:request(put, URI2, #coap_content{format = <<"application/octet-stream">>, payload = Payload2}),
    {ok,changed, _} = Reply2,
    timer:sleep(50),
    PubMsg2 = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p, Reply=~p~n", [PubMsg2, Reply2]),
    ?assertEqual({Topic2, Payload2}, PubMsg2),

    test_mqtt_broker:dispatch(Topic2, Payload2, Topic),
    Notif2 = receive_notification(),
    ?LOGT("observer get Notif2=~p", [Notif2]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv2}} = Notif2,
    ?_assertEqual(Payload2, PayloadRecv2),

    Topic3 = <<"j/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = http_uri:encode(binary_to_list(Topic3)),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?c=client2&u=mike&p=guess",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    {ok,changed, _} = Reply3,
    timer:sleep(50),
    PubMsg3 = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p, Reply=~p~n", [PubMsg3, Reply3]),
    ?assertEqual({Topic3, Payload3}, PubMsg3),

    test_mqtt_broker:dispatch(Topic3, Payload3, Topic),
    Notif3 = receive_notification(),
    ?LOGT("observer get Notif3=~p", [Notif3]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv3}} = Notif3,
    ?_assertEqual(Payload3, PayloadRecv3),

    er_coap_observer:stop(Pid),
    timer:sleep(100),
    SubTopicFinal = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopicFinal),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case05(_Config) ->
    {ok, _} = application:ensure_all_started(emqx_coap),
    ?LOGT("Started", []),
    timer:sleep(100),
    application:stop(emqx_coap),
    application:stop(gen_coap),
    application:stop(crypto),
    application:stop(ssl).

case06_keepalive(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    Topic = <<"+/b">>, TopicStr = http_uri:encode(binary_to_list(Topic)),
    Payload = <<"123">>,
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    timer:sleep(100),
    SubTopic = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopic),

    timer:sleep(2000),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % keepalive action should lead to nothing
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply3 = er_coap_client:request(get, URI3),
    ?assertMatch({ok,content, _}, Reply3),
    timer:sleep(50),
    PubMsg3 = test_mqtt_broker:get_published_msg(),
    ?assertEqual(undefined, PubMsg3),

    test_mqtt_broker:dispatch(<<"a/b">>, Payload, Topic),
    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,
    ?_assertEqual(Payload, PayloadRecv),

    er_coap_observer:stop(Pid),
    timer:sleep(100),
    SubTopicFinal = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopicFinal),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case07_one_clientid_sub_2_topics(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    Topic1 = <<"abc">>, TopicStr1 = binary_to_list(Topic1),
    Payload1 = <<"123">>,
    Uri1 = "coap://127.0.0.1/mqtt/"++TopicStr1++"?c=client1&u=tom&p=secret",
    {ok, Pid1, N1, Code1, Content1} = er_coap_observer:observe(Uri1),
    ?LOGT("observer 1 Pid=~p, N=~p, Code=~p, Content=~p", [Pid1, N1, Code1, Content1]),
    timer:sleep(100),
    SubTopic1 = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic1], SubTopic1),

    Topic2 = <<"x/y">>, TopicStr2 = http_uri:encode(binary_to_list(Topic2)),
    Payload2 = <<"456">>,
    Uri2 = "coap://127.0.0.1/mqtt/"++TopicStr2++"?c=client1&u=tom&p=secret",
    {ok, Pid2, N2, Code2, Content2} = er_coap_observer:observe(Uri2),
    ?LOGT("observer 2 Pid=~p, N=~p, Code=~p, Content=~p", [Pid2, N2, Code2, Content2]),
    timer:sleep(100),
    SubTopic2 = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic1, Topic2], SubTopic2),

    test_mqtt_broker:dispatch(Topic1, Payload1, Topic1),
    Notif1 = receive_notification(),
    ?LOGT("observer 1 get Notif=~p", [Notif1]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv1}} = Notif1,
    ?_assertEqual(Payload1, PayloadRecv1),

    test_mqtt_broker:dispatch(Topic2, Payload2, Topic2),
    Notif2 = receive_notification(),
    ?LOGT("observer 2 get Notif=~p", [Notif2]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv2}} = Notif2,
    ?_assertEqual(Payload2, PayloadRecv2),

    er_coap_observer:stop(Pid1),
    er_coap_observer:stop(Pid2),
    timer:sleep(100),
    SubTopicFinal = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopicFinal),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case10_auth_failure(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% username is "attacker", auth failure required
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic3 = <<"a/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = http_uri:encode(binary_to_list(Topic3)),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?c=client2&u=attacker&p=guess",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error,uauthorized}, Reply3),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case11_invalid_parameter(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "cid=client2" is invaid
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic3 = <<"a/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = http_uri:encode(binary_to_list(Topic3)),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?cid=client2&u=tom&p=simple",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error,bad_request}, Reply3),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "what=hello" is invaid
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    URI4 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?what=hello",
    Reply4 = er_coap_client:request(put, URI4, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error, bad_request}, Reply4),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case12_invalid_topic(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "a/b" is a valid topic string
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic3 = <<"a/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = binary_to_list(Topic3),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?c=client2&u=tom&p=simple",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({ok,changed,_Content}, Reply3),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "+?#" is invaid topic string
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    URI4 = "coap://127.0.0.1/mqtt/"++"+?#"++"?what=hello",
    Reply4 = er_coap_client:request(put, URI4, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error,bad_request}, Reply4),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case13_emit_stats_test(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    Topic = <<"a/b">>, Payload = <<"ET629">>,
    TopicStr = http_uri:encode(binary_to_list(Topic)),
    URI = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client2&u=tom&p=simple",
    Reply = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?assertMatch({ok, _Code, _Content}, Reply),

    test_mqtt_broker:print_table(),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

receive_notification() ->
    receive
        {coap_notify, Pid, N2, Code2, Content2} ->
            {coap_notify, Pid, N2, Code2, Content2}
    after 2000 ->
        receive_notification_timeout
    end.

