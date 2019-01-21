%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_coap_ps_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("gen_coap/include/coap.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PORT, 5683).
-define(LOGT(Format, Args), ct:print("TEST_SUITE: " ++ Format, Args)).

suite() -> [{timetrap, {seconds, 60}}].

all() -> [case01_create, case02_create, case03_create, case04_create,
          case01_publish_post, case02_publish_post, case03_publish_post, case04_publish_post,
          case01_publish_put, case02_publish_put, case03_publish_put, case04_publish_put,
          case01_subscribe, case02_subscribe, case03_subscribe, case04_subscribe,
          case01_read, case02_read, case03_read, case04_read, case05_read,
          case01_delete, case02_delete].

init_per_suite(Config) ->
    application:set_env(emqx_coap, enable_stats, true),
    Config.

end_per_suite(Config) ->
    Config.

case01_create(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"topic1">>,
    Payload = <<"<topic1>;ct=42">>,
    Payload1 = <<"<topic1>;ct=50">>,
    URI = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    TopicInfo = [{TopicInPayload, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    timer:sleep(50),

    %% post to create the same topic but with different max age and ct value in payload
    Reply1 = er_coap_client:request(post, URI, #coap_content{max_age = 70, format = <<"application/link-format">>, payload = Payload1}),
    {ok,created, #coap_content{location_path = LocPath}} = Reply1,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{TopicInPayload, MaxAge2, CT2, _ResPayload, _TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?assertEqual(70, MaxAge2),
    ?assertEqual(<<"50">>, CT2),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_create(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"topic1">>,
    TopicInPayloadStr = binary_to_list(TopicInPayload),
    Payload = <<"<topic1>;ct=42">>,
    URI = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    TopicInfo = [{TopicInPayload, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    timer:sleep(50),

    %% post to create the a sub topic
    Payload1 = <<"<subtopic>;ct=42">>,
    TopicInPayload1 = <<"subtopic">>,
    TopicInPayloadStr1 = binary_to_list(TopicInPayload1),
    URI1 = "coap://127.0.0.1/ps/"++TopicInPayloadStr++"?c=client1&u=tom&p=secret",
    FullTopic = list_to_binary(TopicInPayloadStr++"/"++TopicInPayloadStr1),
    Reply1 = er_coap_client:request(post, URI1, #coap_content{format = <<"application/link-format">>, payload = Payload1}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,created, #coap_content{location_path = LocPath1}} = Reply1,
    ?assertEqual([<<"/ps/topic1/subtopic">>] ,LocPath1),
    [{FullTopic, MaxAge2, CT2, _ResPayload, _}] = emqx_coap_ps_topics:lookup_topic_info(FullTopic),
    ?assertEqual(60, MaxAge2),
    ?assertEqual(<<"42">>, CT2),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03_create(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"topic1">>,
    Payload = <<"<topic1>;ct=42">>,
    URI = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    TopicInfo = [{TopicInPayload, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(5, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    timer:sleep(6000),
    ?assertEqual(true, emqx_coap_ps_topics:is_topic_timeout(TopicInPayload)),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04_create(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"topic1">>,
    Payload = <<"<topic1>;ct=42">>,
    Payload1 = <<"<topic1>;ct=50">>,
    URI = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    TopicInfo = [{TopicInPayload, MaxAge1, CT1, _ResPayload, TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?LOGT("TimeStamp=~p", [TimeStamp]),
    ?assertEqual(5, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    timer:sleep(3000),

    %% post to create the same topic, the max age timer will be restarted with the new max age value
    Reply1 = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/link-format">>, payload = Payload1}),
    {ok,created, #coap_content{location_path = LocPath}} = Reply1,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{TopicInPayload, MaxAge2, CT2, _ResPayload, TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(TopicInPayload),
    ?LOGT("TimeStamp1=~p", [TimeStamp1]),
    ?assertEqual(5, MaxAge2),
    ?assertEqual(<<"50">>, CT2),

    timer:sleep(3000),
    ?assertEqual(false, emqx_coap_ps_topics:is_topic_timeout(TopicInPayload)),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case01_publish_post(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    MainTopic = <<"maintopic">>,
    TopicInPayload = <<"topic1">>,
    Payload = <<"<topic1>;ct=42">>,
    MainTopicStr = binary_to_list(MainTopic),

    %% post to create topic maintopic/topic1
    URI1 = "coap://127.0.0.1/ps/"++MainTopicStr++"?c=client1&u=tom&p=secret",
    FullTopic = list_to_binary(MainTopicStr++"/"++binary_to_list(TopicInPayload)),
    Reply1 = er_coap_client:request(post, URI1, #coap_content{format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,created, #coap_content{location_path = LocPath1}} = Reply1,
    ?assertEqual([<<"/ps/maintopic/topic1">>] ,LocPath1),
    [{FullTopic, MaxAge, CT2, <<>>, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(FullTopic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT2),

    %% post to publish message to topic maintopic/topic1
    FullTopicStr = http_uri:encode(binary_to_list(FullTopic)),
    URI2 = "coap://127.0.0.1/ps/"++FullTopicStr++"?c=client1&u=tom&p=secret",
    PubPayload = <<"PUBLISH">>,
    Reply2 = er_coap_client:request(post, URI2, #coap_content{format = <<"application/octet-stream">>, payload = PubPayload}),
    ?LOGT("Reply =~p", [Reply2]),
    {ok,changed, _} = Reply2,
    TopicInfo = [{FullTopic, MaxAge, CT2, PubPayload, _TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(FullTopic),
    ?LOGT("the topic info =~p", [TopicInfo]),

    timer:sleep(50),
    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({FullTopic, PubPayload}, PubMsg),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_publish_post(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% post to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT),

    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({Topic, Payload}, PubMsg),

    %% post to publish a new message to the same topic "topic1" with different payload
    NewPayload = <<"newpayload">>,
    Reply1 = er_coap_client:request(post, URI, #coap_content{format = <<"application/octet-stream">>, payload = NewPayload}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,changed, _} = Reply1,
    [{Topic, MaxAge, CT, NewPayload, _TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(Topic),

    timer:sleep(50),
    PubMsg1 = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg1]),
    ?assertEqual({Topic, NewPayload}, PubMsg1),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03_publish_post(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% post to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT),

    timer:sleep(50),
    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({Topic, Payload}, PubMsg),

    %% post to publish a new message to the same topic "topic1", but the ct is not same as created
    NewPayload = <<"newpayload">>,
    Reply1 = er_coap_client:request(post, URI, #coap_content{format = <<"application/exi">>, payload = NewPayload}),
    ?LOGT("Reply =~p", [Reply1]),
    ?assertEqual({error,bad_request}, Reply1),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04_publish_post(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% post to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(5, MaxAge),
    ?assertEqual(<<"42">>, CT),

    %% after max age timeout, the topic still exists but the status is timeout
    timer:sleep(6000),
    ?assertEqual(true, emqx_coap_ps_topics:is_topic_timeout(Topic)),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case01_publish_put(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    MainTopic = <<"maintopic">>,
    TopicInPayload = <<"topic1">>,
    Payload = <<"<topic1>;ct=42">>,
    MainTopicStr = binary_to_list(MainTopic),

    %% post to create topic maintopic/topic1
    URI1 = "coap://127.0.0.1/ps/"++MainTopicStr++"?c=client1&u=tom&p=secret",
    FullTopic = list_to_binary(MainTopicStr++"/"++binary_to_list(TopicInPayload)),
    Reply1 = er_coap_client:request(post, URI1, #coap_content{format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,created, #coap_content{location_path = LocPath1}} = Reply1,
    ?assertEqual([<<"/ps/maintopic/topic1">>] ,LocPath1),
    [{FullTopic, MaxAge, CT2, <<>>, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(FullTopic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT2),

    %% put to publish message to topic maintopic/topic1
    FullTopicStr = http_uri:encode(binary_to_list(FullTopic)),
    URI2 = "coap://127.0.0.1/ps/"++FullTopicStr++"?c=client1&u=tom&p=secret",
    PubPayload = <<"PUBLISH">>,
    Reply2 = er_coap_client:request(put, URI2, #coap_content{format = <<"application/octet-stream">>, payload = PubPayload}),
    ?LOGT("Reply =~p", [Reply2]),
    {ok,changed, _} = Reply2,
    [{FullTopic, MaxAge, CT2, PubPayload, _TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(FullTopic),

    timer:sleep(50),
    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({FullTopic, PubPayload}, PubMsg),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_publish_put(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% put to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT),

    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({Topic, Payload}, PubMsg),

    %% put to publish a new message to the same topic "topic1" with different payload
    NewPayload = <<"newpayload">>,
    Reply1 = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = NewPayload}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,changed, _} = Reply1,
    [{Topic, MaxAge, CT, NewPayload, _TimeStamp1}] = emqx_coap_ps_topics:lookup_topic_info(Topic),

    timer:sleep(50),
    PubMsg1 = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg1]),
    ?assertEqual({Topic, NewPayload}, PubMsg1),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03_publish_put(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% put to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(60, MaxAge),
    ?assertEqual(<<"42">>, CT),

    timer:sleep(50),
    PubMsg = test_mqtt_broker:get_published_msg(),
    ?LOGT("PubMsg=~p~n", [PubMsg]),
    ?assertEqual({Topic, Payload}, PubMsg),

    %% put to publish a new message to the same topic "topic1", but the ct is not same as created
    NewPayload = <<"newpayload">>,
    Reply1 = er_coap_client:request(put, URI, #coap_content{format = <<"application/exi">>, payload = NewPayload}),
    ?LOGT("Reply =~p", [Reply1]),
    ?assertEqual({error,bad_request}, Reply1),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04_publish_put(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"payload">>,

    %% put to publish a new topic "topic1", and the topic is created
    URI = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(put, URI, #coap_content{max_age = 5, format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/topic1">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(5, MaxAge),
    ?assertEqual(<<"42">>, CT),

    %% after max age timeout, no publish message to the same topic, the topic info will be deleted
    %%%%%%%%%%%%%%%%%%%%%%%%%%
    % but there is one thing to do is we don't count in the publish message received from emqx(from other node).TBD!!!!!!!!!!!!!
    %%%%%%%%%%%%%%%%%%%%%%%%%%
    timer:sleep(6000),
    ?assertEqual(true, emqx_coap_ps_topics:is_topic_timeout(Topic)),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case01_subscribe(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    Topic = <<"topic1">>,
    Payload1 = <<"<topic1>;ct=42">>,
    timer:sleep(100),

    %% First post to create a topic "topic1"
    Uri = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, Uri, #coap_content{format = <<"application/link-format">>, payload = Payload1}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = [LocPath]}} = Reply,
    ?assertEqual(<<"/ps/topic1">> ,LocPath),
    TopicInfo = [{Topic, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    %% Subscribe the topic
    Uri1 = "coap://127.0.0.1"++binary_to_list(LocPath)++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri1),
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    timer:sleep(100),
    SubTopics = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopics),

    %% Broker publish to the topic
    Payload = <<"123">>,
    test_mqtt_broker:dispatch(Topic, Payload, Topic),
    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,

    ?_assertEqual(Payload, PayloadRecv),

    %% GET to read the publish message of the topic
    Reply1 = er_coap_client:request(get, Uri1),
    ?LOGT("Reply=~p", [Reply1]),
    {ok,content, #coap_content{max_age = MaxAgeLeft,payload = <<"123">>}} = Reply1,
    ?_assertEqual(true, MaxAgeLeft<60),

    er_coap_observer:stop(Pid),
    timer:sleep(100),
    SubTopics2 = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopics2),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_subscribe(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"a/b">>,
    TopicStr = binary_to_list(Topic),
    PercentEncodedTopic = http_uri:encode(TopicStr),
    Payload = <<"payload">>,

    %% post to publish a new topic "a/b", and the topic is created
    URI = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/a/b">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(5, MaxAge),
    ?assertEqual(<<"42">>, CT),

    %% Wait for the max age of the timer expires
    timer:sleep(6000),
    ?assertEqual(true, emqx_coap_ps_topics:is_topic_timeout(Topic)),

    %% Subscribe to the timeout topic "a/b", still successfully，got {ok, nocontent} Method
    Uri = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    Reply1 = {ok, _Pid, _N, nocontent, _} = er_coap_observer:observe(Uri),
    ?LOGT("Subscribe Reply=~p", [Reply1]), 

    SubTopics = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([Topic], SubTopics),

    %% put to publish to topic "a/b"
    Reply2 = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    {ok,changed, #coap_content{}} = Reply2,
    [{Topic, MaxAge1, CT, Payload, TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT),
    ?assertEqual(false, TimeStamp =:= timeout),

    %% Broker dispatch the publish
    test_mqtt_broker:dispatch(Topic, Payload, Topic),
    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = Payload}} = Notif,

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03_subscribe(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %% Subscribe to the unexisted topic "a/b", got not_found
    Topic = <<"a/b">>,
    TopicStr = binary_to_list(Topic),
    PercentEncodedTopic = http_uri:encode(TopicStr),
    Uri = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    {error, not_found} = er_coap_observer:observe(Uri),

    SubTopic = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopic),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04_subscribe(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),

    %% Subscribe to the wildcad topic "+/b", got bad_request
    Topic = <<"+/b">>,
    TopicStr = binary_to_list(Topic),
    PercentEncodedTopic = http_uri:encode(TopicStr),
    Uri = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    {error, bad_request} = er_coap_observer:observe(Uri),

    SubTopic = test_mqtt_broker:get_subscrbied_topics(),
    ?_assertEqual([], SubTopic),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case01_read(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"PubPayload">>,
    timer:sleep(100),

    %% First post to create a topic "topic1"
    Uri = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, Uri, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = [LocPath]}} = Reply,
    ?assertEqual(<<"/ps/topic1">> ,LocPath),
    TopicInfo = [{Topic, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    %% GET to read the publish message of the topic
    Reply1 = er_coap_client:request(get, Uri),
    ?LOGT("Reply=~p", [Reply1]),
    {ok,content, #coap_content{max_age = MaxAgeLeft,payload = Payload}} = Reply1,
    ?_assertEqual(true, MaxAgeLeft<60),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_read(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"PubPayload">>,
    timer:sleep(100),

    %% First post to publish a topic "topic1"
    Uri = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, Uri, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = [LocPath]}} = Reply,
    ?assertEqual(<<"/ps/topic1">> ,LocPath),
    TopicInfo = [{Topic, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    %% GET to read the publish message of unmatched format, got bad_request
    Reply1 = er_coap_client:request(get, Uri, #coap_content{format = <<"application/json">>}),
    ?LOGT("Reply=~p", [Reply1]),
    {error, bad_request} = Reply1,

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case03_read(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Uri = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    timer:sleep(100),

    %% GET to read the nexisted topic "topic1", got not_found
    Reply = er_coap_client:request(get, Uri),
    ?LOGT("Reply=~p", [Reply]),
    {error, not_found} = Reply,

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case04_read(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    Topic = <<"topic1">>,
    TopicStr = binary_to_list(Topic),
    Payload = <<"PubPayload">>,
    timer:sleep(100),

    %% First post to publish a topic "topic1"
    Uri = "coap://127.0.0.1/ps/"++TopicStr++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, Uri, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = [LocPath]}} = Reply,
    ?assertEqual(<<"/ps/topic1">> ,LocPath),
    TopicInfo = [{Topic, MaxAge1, CT1, _ResPayload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?LOGT("lookup topic info=~p", [TopicInfo]),
    ?assertEqual(60, MaxAge1),
    ?assertEqual(<<"42">>, CT1),

    %% GET to read the publish message of wildcard topic, got bad_request
    WildTopic = binary_to_list(<<"+/topic1">>),
    Uri1 = "coap://127.0.0.1/ps/"++WildTopic++"?c=client1&u=tom&p=secret",
    Reply1 = er_coap_client:request(get, Uri1, #coap_content{format = <<"application/json">>}),
    ?LOGT("Reply=~p", [Reply1]),
    {error, bad_request} = Reply1,

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case05_read(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    Topic = <<"a/b">>,
    TopicStr = binary_to_list(Topic),
    PercentEncodedTopic = http_uri:encode(TopicStr),
    Payload = <<"payload">>,

    %% post to publish a new topic "a/b", and the topic is created
    URI = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    Reply = er_coap_client:request(post, URI, #coap_content{max_age = 5, format = <<"application/octet-stream">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/a/b">>] ,LocPath),
    [{Topic, MaxAge, CT, Payload, _TimeStamp}] = emqx_coap_ps_topics:lookup_topic_info(Topic),
    ?assertEqual(5, MaxAge),
    ?assertEqual(<<"42">>, CT),

    %% Wait for the max age of the timer expires
    timer:sleep(6000),
    ?assertEqual(true, emqx_coap_ps_topics:is_topic_timeout(Topic)),

    %% GET to read the expired publish message, supposed to get {ok, nocontent}, but now got {ok, content}
    Reply1 = er_coap_client:request(get, URI),
    ?LOGT("Reply=~p", [Reply1]),
    {ok, content, #coap_content{payload = <<>>}}= Reply1,

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case01_delete(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"a/b">>,
    TopicStr = binary_to_list(TopicInPayload),
    PercentEncodedTopic = http_uri:encode(TopicStr),
    Payload = list_to_binary("<"++PercentEncodedTopic++">;ct=42"),
    URI = "coap://127.0.0.1/ps/"++"?c=client1&u=tom&p=secret",

    %% Client post to CREATE topic "a/b"
    Reply = er_coap_client:request(post, URI, #coap_content{format = <<"application/link-format">>, payload = Payload}),
    ?LOGT("Reply =~p", [Reply]),
    {ok,created, #coap_content{location_path = LocPath}} = Reply,
    ?assertEqual([<<"/ps/a/b">>] ,LocPath),

    %% Client post to CREATE topic "a/b/c"
    TopicInPayload1 = <<"a/b/c">>,
    PercentEncodedTopic1 = http_uri:encode(binary_to_list(TopicInPayload1)),
    Payload1 = list_to_binary("<"++PercentEncodedTopic1++">;ct=42"),
    Reply1 = er_coap_client:request(post, URI, #coap_content{format = <<"application/link-format">>, payload = Payload1}),
    ?LOGT("Reply =~p", [Reply1]),
    {ok,created, #coap_content{location_path = LocPath1}} = Reply1,
    ?assertEqual([<<"/ps/a/b/c">>] ,LocPath1),

    timer:sleep(50),

    %% DELETE the topic "a/b"
    UriD = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    ReplyD = er_coap_client:request(delete, UriD),
    ?LOGT("Reply=~p", [Reply1]),
    {ok, deleted, #coap_content{}}= ReplyD,

    ?assertEqual(false, emqx_coap_ps_topics:is_topic_existed(TopicInPayload)),
    ?assertEqual(false, emqx_coap_ps_topics:is_topic_existed(TopicInPayload1)),

    ok = application:stop(emqx_coap),
    test_mqtt_broker:stop().

case02_delete(_Config) ->
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_coap),
    timer:sleep(100),
    TopicInPayload = <<"a/b">>,
    TopicStr = binary_to_list(TopicInPayload),
    PercentEncodedTopic = http_uri:encode(TopicStr),

    %% DELETE the unexisted topic "a/b"
    Uri1 = "coap://127.0.0.1/ps/"++PercentEncodedTopic++"?c=client1&u=tom&p=secret",
    Reply1 = er_coap_client:request(delete, Uri1),
    ?LOGT("Reply=~p", [Reply1]),
    {error, not_found} = Reply1,

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

