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

-module(emqtt_coap_sup).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(supervisor).

-export([start_link/1]).

-export([init/1]).

start_link(Listener) ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, [Listener]).

init([Port, Opts]) ->
    ChanSup = {emqtt_coap_channel_sup,
                {emqtt_coap_channel_sup, start_link, []},
                  permanent, infinity, supervisor, [emqtt_coap_channel_sup]},

    MFA = {emqtt_coap_channel_sup, start_channel, []},

    UdpSrv = {emqtt_coap_udp_server,
               {esockd_udp, server, [mqtt_sn, Port, Opts, MFA]},
                 permanent, 5000, worker, [esockd_udp]},

	{ok, {{one_for_one, 10, 3600}, [ChanSup, UdpSrv]}}.

