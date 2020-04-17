%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_coap_server).

-include("emqx_coap.hrl").

-export([ start/0
        , stop/0
        ]).

start() ->
    {ok, _} = application:ensure_all_started(gen_coap),
    start_udp(),
    start_dtls(),
    coap_server_registry:add_handler([<<"mqtt">>], emqx_coap_resource, undefined),
    coap_server_registry:add_handler([<<"ps">>], emqx_coap_ps_resource, undefined),
    emqx_coap_ps_topics:start_link().

stop() ->
    stop_udp(),
    stop_dtls().

start_udp() ->
    BindUdps = application:get_env(?APP, bind_udp, [{5683, []}]),
    lists:foreach(fun({Port, InetOpt}) ->
        Name = process_name(coap_udp_socket, Port),
        coap_server:start_udp(Name, Port, InetOpt)
    end, BindUdps).

start_dtls() ->
    case application:get_env(?APP, dtls_opts, []) of
        [] -> ok;
        DtlsOpts ->
            BindDtls = application:get_env(?APP, bind_dtls, [{5684, []}]),
            lists:foreach(fun({DtlsPort, InetOpt}) ->
                Name = process_name(coap_dtls_socket, DtlsPort),
                coap_server:start_dtls(Name, DtlsPort, InetOpt ++ DtlsOpts)
            end, BindDtls)
    end.

stop_udp() ->
    BindUdps = application:get_env(?APP, bind_udp, [{5683, []}]),
    lists:foreach(fun({Port, _}) ->
        Name = process_name(coap_udp_socket, Port),
        coap_server:stop_udp(Name)
    end, BindUdps).

stop_dtls() ->
    BindDtls = application:get_env(?APP, bind_dtls, [{5684, []}]),
    lists:foreach(fun({Port, _}) ->
        Name = process_name(coap_dtls_socket, Port),
        coap_server:stop_dtls(Name)
    end, BindDtls).

process_name(Mod, Port) ->
    list_to_atom(atom_to_list(Mod) ++ "_" ++ integer_to_list(Port)).
