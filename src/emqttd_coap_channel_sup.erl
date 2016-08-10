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

-module(emqttd_coap_channel_sup).

-author("Feng Lee <feng@emqtt.io>").

-include("emqttd_coap.hrl").

-behaviour(supervisor).

-export([start_link/0, start_channel/2, init/1]).

%% @doc Start CoAP Channel Supervisor.
-spec(start_link() -> {ok, pid()}).
start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Start a CoAP Channel
-spec(start_channel(inet:socket(), coap_endpoint()) -> {ok, pid()}).
start_channel(Sock, Endpoint) ->
    supervisor:start_child(?MODULE, [Sock, Endpoint]).

init([]) ->
    {ok, {{simple_one_for_one, 0, 1},
          [{coap_channel, {emqttd_coap_channel, start_link, []},
              temporary, 5000, worker, [emqttd_coap_channel]}]}}.

