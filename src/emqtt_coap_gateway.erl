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

-module(emqtt_coap_gateway).

-author("Feng Lee <feng@emqtt.io>").

%% API.
-export([start_link/2]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {sock, peer}).

%% API.

-spec(start_link(inet:socket(), {inet:ip_address(), inet:port()}) -> {ok, pid()}).
start_link(Sock, Peer) ->
	gen_server:start_link(?MODULE, [Sock, Peer], []).

%% gen_server.
init([Sock, Peer]) ->
	{ok, #state{sock = Sock, peer = Peer}}.

handle_call(_Request, _From, State) ->
	{reply, ignored, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({datagram, _From, Packet}, State) ->
    io:format("RECV: ~p~n", [Packet]),
    Message = emqtt_coap_message:parse(Packet),
    io:format("MSG: ~p~n", [Message]),
	{noreply, State};

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

