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

-module(emq_coap_app).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(application).

-export([start/2, stop/1]).

-define(APP, emq_coap).

start(_Type, _Args) ->

    Ret = emq_coap_sup:start_link(application:get_env(?APP, listener, 5683)),
    case application:get_env(?APP, gateway, []) of
        [] -> emq_coap_server:register_handler("", emq_coap_server_handle);
        List ->
            lists:foreach(
                fun({Prefix, Handler, _}) ->
                    emq_coap_server:register_handler(Prefix, Handler)
                end, List)
    end,
    Ret.

stop(_State) ->
    ok.

