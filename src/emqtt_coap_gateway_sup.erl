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

-module(emqtt_coap_gateway_sup).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(supervisor).

-export([start_link/0, start_gateway/2, init/1]).

%% @doc Start CoAP-Gateway Supervisor.
-spec(start_link() -> {ok, pid()}).
start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Start a CoAP Gateway
-spec(start_gateway(inet:socket(), {inet:ip_address(), inet:port()}) -> {ok, pid()}).
start_gateway(Sock, Peer) ->
    supervisor:start_child(?MODULE, [Sock, Peer]).

init([]) ->
    {ok, {{simple_one_for_one, 0, 1},
          [{caop_gateway, {emqtt_caop_gateway, start_link, []},
              temporary, 5000, worker, [emqtt_caop_gateway]}]}}.

