%%--------------------------------------------------------------------
%% Copyright (c) 2016 Feng Lee <feng@emqtt.io>. All Rights Reserved.
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

-module(emqttd_coap_server_handle).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(emqttd_coap_handler).
%% API.
-export([handle_request/1, handle_observe/1, handle_unobserve/1]).

-include("emqttd_coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

handle_request(_Req = #coap_message{method = 'GET'}) ->
    {ok, #coap_response{code = 'Content', payload = <<"handle_request GET">>}};

handle_request(_Req = #coap_message{method = 'POST', payload = Payload}) ->
    Params = string:tokens(binary_to_list(Payload), "&"),
    ParamsList = lists:foldl(
        fun(Param, AccIn) -> 
            [Key, Value] = string:tokens(Param, "="),
            [{Key, Value}| AccIn]
        end, [], Params),
    io:format("ParamsList:~p~n", [ParamsList]),
    ClientId = proplists:get_value("client", ParamsList, coap),
    Qos      = int(proplists:get_value("qos", ParamsList, "0")),
    Retain   = bool(proplists:get_value("retain", ParamsList, "0")),
    Content  = list_to_binary(proplists:get_value("message", ParamsList)),
    Topic    = list_to_binary(proplists:get_value("topic", ParamsList)),
    Msg = emqttd_message:make(ClientId, Qos, Topic, Content),
    emqttd:publish(Msg#mqtt_message{retain  = Retain}),
    {ok, #coap_response{code = 'Created', payload = <<"handle_request POST">>}};

handle_request(_Req = #coap_message{method = 'PUT', options = Options}) ->
    Uri = proplists:get_value('Uri-Path', Options, <<>>),
    emqttd_coap_observer:notify(binary_to_list(Uri), <<"handle_request_put">>),
    {ok, #coap_response{code = 'Changed', payload = <<"handle_request PUT">>}};

handle_request(_Req = #coap_message{method = 'DELETE', options = Options}) ->
    Uri = proplists:get_value('Uri-Path', Options, <<>>),
    emqttd_coap_observer:notify(binary_to_list(Uri), <<"handle_request_delete">>),
    {ok, #coap_response{code = 'Deleted', payload = <<"handle_request DELETE">>}}.

handle_observe(_Req) ->
    emqttd:subscribe("coap_topic"),
    {ok, #coap_response{code = 'Content', payload = <<"handle_observe">>}}.

handle_unobserve(_Req) ->
    {ok, #coap_response{code = 'Content', payload = <<"handle_unobserve">>}}.

int(S) -> list_to_integer(S).

bool("0") -> false;
bool("1") -> true.