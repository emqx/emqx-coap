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

-module(emqtt_coap_channel).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(gen_server).

-include("emqtt_coap.hrl").

%% API.
-export([start_link/2]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {sock, endpoint}).

-define(LOG(Level, Format, Args, State),
        lager:Level("CoAP(~s): " ++ Format,
                    [esockd_net:format(State#state.endpoint) | Args])).

-spec(start_link(inet:socket(), coap_endpoint()) -> {ok, pid()}).
start_link(Sock, Endpoint) ->
	gen_server:start_link(?MODULE, [Sock, Endpoint], []).

%% gen_server.
init([Sock, Endpoint]) ->
    {ok, #state{sock = Sock, endpoint = Endpoint}}.

handle_call(_Request, _From, State) ->
	{reply, ignored, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({datagram, _From, Packet}, State = #state{sock = Sock, endpoint = {IpAddr, Port}}) ->
    ?LOG(debug, "RECV ~p", [Packet], State),
    Msg = emqtt_coap_message:parse(Packet),
    ?LOG(info, "RECV ~p", [emqtt_coap_message:format(Msg)], State),
    handle_message(Msg, State);

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

handle_message(Msg = #coap_message{method = 'GET', id = MsgId, token = Token, options = Options},
               State = #state{sock = Sock, endpoint = {IpAddr, Port}}) ->
    Uri = proplists:get_value('Uri-Path', Options),
    io:format("GET URI: ~p~n", [Uri]),
    AckMsg = #coap_message{type = 'ACK', id = MsgId, code = {2,05}, token = Token, payload = <<"Hello">>},
    ?LOG(info, "SEND ~p", [emqtt_coap_message:format(AckMsg)], State),
    gen_udp:send(Sock, IpAddr, Port, emqtt_coap_message:serialize(AckMsg)),
    {noreply, State};

handle_message(#coap_message{method = 'POST', id = MsgId, token = Token, options = Options},
               State = #state{sock = Sock, endpoint = {IpAddr, Port}}) ->
    %case emqtt_coap_server:match_handler(Uri) of
    %    {ok, Handler} -> Handler:kk
    %    undefined     -> respond_404(Msg)
    %end,
    {noreply, State};

handle_message(#coap_message{method = 'PUT', id = MsgId, token = Token, options = Options},
               State = #state{sock = Sock, endpoint = {IpAddr, Port}}) ->
    {noreply, State};

handle_message(#coap_message{method = 'DELETE', id = MsgId, token = Token, options = Options},
               State = #state{sock = Sock, endpoint = {IpAddr, Port}}) ->
    {noreply, State}.

