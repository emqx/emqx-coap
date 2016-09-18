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

-module(emqttd_coap_app).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(application).

-export([start/2, stop/1]).

-define(APP, emqttd_coap).

start(_Type, _Args) ->
    gen_conf:init(?APP),
    Ret = emqttd_coap_sup:start_link(gen_conf:list(?APP, listener)),
    case gen_conf:list(?APP, gateway) of
        [] -> emqttd_coap_server:register_handler("", emqttd_coap_server_handle);
        List ->
            lists:foreach(
                fun({_, Prefix, Handler}) -> 
                    emqttd_coap_server:register_handler(Prefix, Handler)
                end, List)
    end,
    Ret.

stop(_State) ->
    ok.

