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

-module(emqx_coap_app).

-behaviour(application).

-emqx_plugin(?MODULE).

-include("emqx_coap.hrl").

-export([ start/2
        , stop/1
        ]).

start(_Type, _Args) ->
    {ok, Sup} = emqx_coap_sup:start_link(),
    ok = coap_server_registry:add_handler([<<"mqtt">>], emqx_coap_resource, undefined),
    ok = coap_server_registry:add_handler([<<"ps">>], emqx_coap_ps_resource, undefined),
    _ = coap_server:start_udp(coap, application:get_env(?APP, port, 5683)),
    emqx_coap_config:register(),
    {ok,Sup}.

stop(_State) ->
    ok = coap_server:del_handler([<<"mqtt">>], emqx_coap_resource),
    ok = coap_server:del_handler([<<"ps">>], emqx_coap_ps_resource),
    _ = coap_server:stop_udp(coap, application:get_env(?APP, port, 5683)),
    emqx_coap_config:unregister().

%%TODO: DTLS
%%start(Port) ->
%%    CertFile = application:get_env(?APP, certfile, ""),
%%   KeyFile = application:get_env(?APP, keyfile, ""),
%%   case (filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile)) of
%%       true ->
%%           coap_server:start_dtls(coap_dtls_socket, [{certfile, CertFile}, {keyfile, KeyFile}]);
%%      false ->
%%            emqx_logger:error("Certfile ~p or keyfile ~p are not valid, turn off coap DTLS", [CertFile, KeyFile])
%%   end,
%%   emqx_coap_ps_topics:start().
%%

