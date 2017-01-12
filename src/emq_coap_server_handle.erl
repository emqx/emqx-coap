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

-module(emq_coap_server_handle).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(emq_coap_handler).
%% API.
-export([handle_request/1, handle_observe/1, handle_unobserve/1, handle_info/2]).

-include("emq_coap.hrl").

handle_request(_Req = #coap_message{method = 'GET'}) ->
    {error, 'MethodNotAllowed'};

handle_request(_Req = #coap_message{method = 'POST'}) ->
    {error, 'MethodNotAllowed'};
    
handle_request(_Req = #coap_message{method = 'PUT'}) ->
    {error, 'MethodNotAllowed'};
    
handle_request(_Req = #coap_message{method = 'DELETE'}) ->
    {error, 'MethodNotAllowed'}.

handle_observe(_Req) ->
    {error, 'MethodNotAllowed'}.

handle_unobserve(_Req) ->
    {error, 'MethodNotAllowed'}.

handle_info(_, _) ->
	ok.
