%%--------------------------------------------------------------------
%% Copyright (c) 2016-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-module(emq_coap_ps_resource).

-behaviour(coap_resource).

-include("emq_coap.hrl").

-include_lib("gen_coap/include/coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-export([coap_discover/2, coap_get/5, coap_post/4, coap_put/4, coap_delete/3,
         coap_observe/5, coap_unobserve/1, handle_info/2, coap_ack/2]).

-ifdef(TEST).
-export([topic/1]).
-endif.

-define(PS_PREFIX, [<<"ps">>]).

-define(LOG(Level, Format, Args),
    lager:Level("CoAP-PS-RES: " ++ Format, Args)).

%%--------------------------------------------------------------------
%% Resource Callbacks
%%--------------------------------------------------------------------
coap_discover(_Prefix, _Args) ->
    [{absolute, "ps", []}].

coap_get(ChId, ?PS_PREFIX, [Topic], Query, Content=#coap_content{format = Format}) ->
    ?LOG(debug, "coap_get() Name=~p, Query=~p~n", [Topic, Query]),
    #coap_mqtt_auth{clientid = Clientid, username = Usr, password = Passwd} = get_auth(Query),
    case emq_coap_mqtt_adapter:client_pid(Clientid, Usr, Passwd, ChId) of
        {ok, Pid} ->
            put(mqtt_client_pid, Pid),
            emq_coap_mqtt_adapter:keepalive(Pid),
            case Format of
                <<"application/link-format">> ->
                    Content;
                _Other                        ->
                    %% READ the topic info
                    read_last_publish_message(emqttd_topic:wildcard(Topic), Topic, Content)
            end;
        {error, auth_failure} ->
            put(mqtt_client_pid, undefined),
            {error, uauthorized};
        {error, bad_request} ->
            put(mqtt_client_pid, undefined),
            {error, bad_request};
        {error, _Other} ->
            put(mqtt_client_pid, undefined),
            {error, internal_server_error}
    end;
coap_get(ChId, Prefix, Name, Query, _Content) ->
    ?LOG(error, "ignore bad put request ChId=~p, Prefix=~p, Name=~p, Query=~p", [ChId, Prefix, Name, Query]),
    {error, bad_request}.

coap_post(_ChId, ?PS_PREFIX, Name, #coap_content{format = Format, payload = Payload, max_age = MaxAge}) ->
    ?LOG(debug, "coap_post() Name=~p, MaxAge=~p, Format=~p~n", [Name, MaxAge, Format]),
    TopicPrefix = get_binary(Name),
    case Format of
        %% We treat ct of "application/link-format" as CREATE message
        <<"application/link-format">> ->
            handle_received_create(TopicPrefix, MaxAge, Payload);
        %% We treat ct of other values as PUBLISH message
        Other ->
            ?LOG(debug, "coap_post() receive payload format=~p, will process as PUBLISH~n", [Format]),
            handle_received_publish(TopicPrefix, MaxAge, Other, Payload)
    end;

coap_post(_ChId, _Prefix, _Name, _Content) ->
    {error, method_not_allowed}.

coap_put(_ChId, ?PS_PREFIX, Name, #coap_content{max_age = MaxAge, format = Format, payload = Payload}) ->
    Topic = get_binary(Name),
    ?LOG(debug, "put message, Topic=~p, Payload=~p~n", [Topic, Payload]),
    handle_received_publish(Topic, MaxAge, Format, Payload);

coap_put(_ChId, Prefix, Name, Content) ->
    ?LOG(error, "put has error, Prefix=~p, Name=~p, Content=~p", [Prefix, Name, Content]),
    {error, bad_request}.

coap_delete(_ChId, ?PS_PREFIX, Name) ->
    Topic = get_binary(Name),
    delete_topic_info(Topic);

coap_delete(_ChId, _Prefix, _Name) ->
    {error, method_not_allowed}.

coap_observe(ChId, ?PS_PREFIX, [Topic], Ack, Content) ->
    TrueTopic = topic(Topic),
    ?LOG(debug, "observe Topic=~p, Ack=~p，Content=~p", [TrueTopic, Ack, Content]),
    Pid = get(mqtt_client_pid),
    emq_coap_mqtt_adapter:subscribe(Pid, TrueTopic),
    Code = case emq_coap_ps_topics:is_topic_timeout(TrueTopic) of
               true  ->
                   nocontent;
               false->
                   content
           end,
    {ok, {state, ChId, ?PS_PREFIX, [TrueTopic]}, Code, Content};

coap_observe(ChId, Prefix, Name, Ack, _Content) ->
    ?LOG(error, "unknown observe request ChId=~p, Prefix=~p, Name=~p, Ack=~p", [ChId, Prefix, Name, Ack]),
    {error, bad_request}.

coap_unobserve({state, _ChId, ?PS_PREFIX, [Topic]}) ->
    ?LOG(debug, "unobserve ~p", [Topic]),
    Pid = get(mqtt_client_pid),
    emq_coap_mqtt_adapter:unsubscribe(Pid, Topic),
    ok;
coap_unobserve({state, ChId, Prefix, Name}) ->
    ?LOG(error, "ignore unknown unobserve request ChId=~p, Prefix=~p, Name=~p", [ChId, Prefix, Name]),
    ok.

handle_info({dispatch, Topic, Payload}, State) ->
    ?LOG(debug, "dispatch Topic=~p, Payload=~p", [Topic, Payload]),
    {ok, Ret} = emq_coap_ps_topics:reset_topic_info(Topic, Payload),
    ?LOG(debug, "Updated publish info of topic=~p, the Ret is ~p", [Topic, Ret]),
    {notify, [], #coap_content{format = <<"application/octet-stream">>, payload = Payload}, State};
handle_info(Message, State) ->
    ?LOG(error, "Unknown Message ~p", [Message]),
    {noreply, State}.

coap_ack(_Ref, State) -> {ok, State}.


%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
get_auth(Query) ->
    get_auth(Query, #coap_mqtt_auth{}).

get_auth([], Auth=#coap_mqtt_auth{}) ->
    Auth;
get_auth([<<$c, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{clientid = Rest});
get_auth([<<$u, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{username = Rest});
get_auth([<<$p, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{password = Rest});
get_auth([Param|T], Auth=#coap_mqtt_auth{}) ->
    ?LOG(error, "ignore unknown parameter ~p", [Param]),
    get_auth(T, Auth).

topic(TopicBinary) ->
    %% RFC 7252 section 6.4. Decomposing URIs into Options
    %%     Note that these rules completely resolve any percent-encoding.
    %% That is to say: URI may have percent-encoding. But coap options has no percent-encoding at all.
    TopicBinary.

get_binary([]) ->
    <<>>;
get_binary([<<>>]) ->
    <<>>;
get_binary([Binary]) when is_binary(Binary) ->
    Binary.

get_stored_ct_value(Topic) ->
    emq_coap_ps_topics:lookup_topic_payload_ct(Topic).

add_topic_info(publish, Topic, MaxAge, Format, Payload) when is_binary(Topic), Topic =/= <<>>  ->
    case emq_coap_ps_topics:is_topic_existed(Topic) of
        true ->
            ?LOG(debug, "publish topic=~p already exists, need reset the topic info", [Topic]),
            StoredCT = get_stored_ct_value(Topic),
            %% check whether the ct value stored matches the ct option in this POST message
            case Format =:= StoredCT of
                true  ->
                    {ok, Ret} = emq_coap_ps_topics:reset_topic_info(Topic, MaxAge, Format, Payload),
                    {changed, Ret};
                false ->
                    ?LOG(debug, "ct values of topic=~p do not match, stored ct=~p, new ct=~p, ignore the PUBLISH", [Topic, StoredCT, Format]),
                    {changed, false}
            end;
        false ->
            ?LOG(debug, "publish topic=~p will be created", [Topic]),
            {ok, Ret} = emq_coap_ps_topics:add_topic_info(Topic, MaxAge, Format, Payload),
            {created, Ret}
    end;

add_topic_info(create, Topic, MaxAge, Format, _Payload) when is_binary(Topic), Topic =/= <<>> ->
    case emq_coap_ps_topics:is_topic_existed(Topic) of
        true ->
            ?LOG(debug, "create topic=~p already exists, need reset the topic info", [Topic]),
            {ok, Ret} = emq_coap_ps_topics:reset_topic_info(Topic, MaxAge, Format, <<>>);
        false ->
            ?LOG(debug, "create topic=~p will be created", [Topic]),
            {ok, Ret} = emq_coap_ps_topics:add_topic_info(Topic, MaxAge, Format)
    end,
    {created, Ret};

add_topic_info(_, Topic, _MaxAge, _Format, _Payload) ->
    ?LOG(debug, "create topic=~p info failed", [Topic]),
    {badarg, false}.

concatenate_location_path(List = [TopicPart1, TopicPart2, TopicPart3]) when is_binary(TopicPart1), is_binary(TopicPart2), is_binary(TopicPart3)  ->
    list_to_binary(lists:foldl( fun (Element, AccIn) when Element =/= <<>> ->
                                    AccIn ++ "/" ++ binary_to_list(Element);
                                (_Element, AccIn) ->
                                    AccIn
                                end, [], List)).

format_string_to_int(<<"application/octet-stream">>) ->
    <<"42">>;
format_string_to_int(<<"application/exi">>) ->
    <<"47">>;
format_string_to_int(<<"application/json">>) ->
    <<"50">>.

handle_received_publish(Topic, MaxAge, Format, Payload) ->
    case add_topic_info(publish, Topic, MaxAge, format_string_to_int(Format), Payload) of
        {Ret ,true}  ->
            Pid = get(mqtt_client_pid),
            emq_coap_mqtt_adapter:publish(Pid, topic(Topic), Payload),
            Content = case Ret of
                          changed ->
                              #coap_content{};
                          created ->
                              LocPath = concatenate_location_path([<<"ps">>, Topic, <<>>]),
                              #coap_content{location_path = [LocPath]}
                      end,
            {ok, Ret, Content};
        {_, false} ->
            ?LOG(debug, "add_topic_info failed, will return bad_request", []),
            {error, bad_request}
    end.

handle_received_create(TopicPrefix, MaxAge, Payload) ->
    case core_link:decode(Payload) of
        [{rootless, [Topic], [{ct, CT}]}] when is_binary(Topic), Topic =/= <<>> ->
            TrueTopic = http_uri:decode(Topic),
            ?LOG(debug, "decoded link-format payload, the Topic=~p, CT=~p~n", [TrueTopic, CT]),
            LocPath = concatenate_location_path([<<"ps">>, TopicPrefix, TrueTopic]),
            FullTopic = binary:part(LocPath, 4, byte_size(LocPath)-4),
            ?LOG(debug, "the location path is ~p, the full topic is ~p~n", [LocPath, FullTopic]),
            case add_topic_info(create, FullTopic, MaxAge, CT, <<>>) of
                {_, true}  ->
                    ?LOG(debug, "create topic info successfully, will return LocPath=~p", [LocPath]),
                    {ok, created, #coap_content{location_path = [LocPath]}};
                {_, false} ->
                    ?LOG(debug, "create topic info failed, will return bad_request", []),
                    {error, bad_request}
            end;
        Other  ->
            ?LOG(debug, "post with bad payload of link-format ~p, will return bad_request", [Other]),
            {error, bad_request}
    end.

%% the stored paylaod is <<>>, the topic is never published and not timeout. It should return nocontent here,
%% but gen_coap only receive #coap_content from coap_get, so temporarily we don't give the Code 2.07 {ok, nocontent} out.TBC!!!
return_resource(_Topic, <<>>, _Content, TimeStamp) when TimeStamp =/= timeout->
    #coap_content{};

%% the stored topic timeout, should return nocontent here.TBC!!!
return_resource(_Topic, _Payload, _Content, timeout) ->
    #coap_content{};

return_resource(Topic, Payload, Content, _TimeStamp) ->
    LeftTime = emq_coap_ps_topics:get_timer_left_seconds(Topic),
    ?LOG(debug, "topic=~p has max age left time is ~p", [Topic, LeftTime]),
    Content#coap_content{max_age = LeftTime, payload = Payload}.

read_last_publish_message(false, Topic, Content=#coap_content{format = QueryFormat}) when is_binary(QueryFormat)->
    ?LOG(debug, "the QueryFormat=~p", [QueryFormat]),
    case emq_coap_ps_topics:lookup_topic_info(Topic) of
        [] ->
            {error, not_found};
        [{_, _, CT, Payload, TimeStamp}] ->
            case CT =:= format_string_to_int(QueryFormat) of
                true  ->
                    return_resource(Topic, Payload, Content, TimeStamp);
                false ->
                    ?LOG(debug, "format value does not match, the queried format=~p, the stored format=~p", [QueryFormat, CT]),
                    {error, bad_request}
            end
    end;

read_last_publish_message(false, Topic, Content) ->
    case emq_coap_ps_topics:lookup_topic_info(Topic) of
        [] ->
            {error, not_found};
        [{_, _, _, Payload, TimeStamp}] ->
            return_resource(Topic, Payload, Content, TimeStamp)
    end;

read_last_publish_message(true, Topic, _Content) ->
    ?LOG(debug, "the topic=~p is illegal wildcard topic", [Topic]),
    {error, bad_request}.

delete_topic_info(Topic) ->
    case emq_coap_ps_topics:lookup_topic_info(Topic) of
        [] ->
            {error, not_found};
        [{_, _, _, _, _}] ->
            emq_coap_ps_topics:delete_sub_topics(Topic)
    end.
