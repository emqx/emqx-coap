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

-module(emq_coap_gateway).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(emq_coap_handler).
%% API.
-export([handle_request/1, handle_observe/1, handle_unobserve/1, handle_info/2]).

-include("emq_coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

handle_request(_Req=#coap_message{method = 'GET'}) ->
    {notsupport};

handle_request(#coap_message{method = 'POST', payload = Payload}) ->
    publish(Payload),
    {ok, #coap_response{code = 'Created'}};

handle_request(_Req = #coap_message{method = 'PUT'}) ->
    {notsupport};

handle_request(_Req = #coap_message{method = 'DELETE'}) ->
    {notsupport}.

handle_observe(Req) ->
    Queries = emq_coap_message:get_option(Req, 'Uri-Query'),
    lists:foreach(fun subscribe/1, Queries),
    {ok, #coap_response{code = 'Content', payload = <<"handle_observe">>}}.

handle_unobserve(Req) ->
    Queries = emq_coap_message:get_option(Req, 'Uri-Query'),
    lists:foreach(fun unsubscribe/1, Queries),
    {ok, #coap_response{code = 'Content', payload = <<"handle_unobserve">>}}.

handle_info(Topic, Msg = #mqtt_message{payload = Payload}) ->
    Payload2 = lists:concat(["topic=",binary_to_list(Topic), "&message=", binary_to_list(Payload)]),
    ?LOG(debug, "Topic:~p, Msg:~p~n", [Topic, Msg]),
    {ok, #coap_response{payload = Payload2}}.

int(S) -> list_to_integer(S).

bool("0") -> false;
bool("1") -> true.

parse_params(Payload) ->
    Params = string:tokens(binary_to_list(Payload), "&"),
    lists:foldl(
        fun(Param, AccIn) -> 
            [Key, Value] = string:tokens(Param, "="),
            [{Key, Value}| AccIn]
        end, [], Params).

publish(<<>>) ->
    ok;
publish(Payload)->
    ParamsList = parse_params(Payload),
    Content1 = proplists:get_value("message", ParamsList, ""),
    Content  = list_to_binary(http_uri:decode(Content1)),
    Topic1 = proplists:get_value("topic", ParamsList, ""),
    case Topic1 of
        "" -> ok;
        _ ->
            Topic    = list_to_binary(http_uri:decode(Topic1)),
            ?LOG(debug, "gateway publish Topic=~p, Content=~p", [Topic, Content]),
            emq_coap_broker_api:publish(coap, Topic, Content)
    end.

subscribe(<<>>) ->
    ok;
subscribe(Payload) ->
    ParamsList = parse_params(Payload),
    Topic1 = proplists:get_value("topic", ParamsList, ""),
    case Topic1 of
        "" -> ok;
        _ ->
            Topic = list_to_binary(http_uri:decode(Topic1)),
            ?LOG(debug, "gateway subscribe Topic=~p", [Topic]),
            emq_coap_broker_api:subscribe(Topic)
    end.

unsubscribe(<<>>) ->
    ok;
unsubscribe(Payload) ->
    ParamsList = parse_params(Payload),
    Topic1 = proplists:get_value("topic", ParamsList, ""),
    case Topic1 of
        "" -> ok;
        _ ->
            Topic = list_to_binary(http_uri:decode(Topic1)),
            ?LOG(debug, "gateway unsubscribe Topic=~p", [Topic]),
            emq_coap_broker_api:unsubscribe(Topic)
    end.

