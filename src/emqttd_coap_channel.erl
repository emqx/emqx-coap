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

-module(emqttd_coap_channel).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(gen_server).

-include("emqttd_coap.hrl").

%% API.
-export([start_link/2, send_response/2]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {sock, endpoint, resp, next_msg_id, auto_reply_ack, awaiting_ack}).

-define(LOG(Level, Format, Args, State),
        lager:Level("CoAP(~s): " ++ Format,
                    [esockd_net:format(State#state.endpoint) | Args])).

-define(ACK_TIMEOUT, 2000).
-define(ACK_RANDOM_FACTOR, 1000). % ACK_TIMEOUT*0.5`
-define(MAX_RETRANSMIT, 4).

-define(PROCESSING_DELAY, 1000).
-define(EXCHANGE_LIFETIME, 247000).
-define(NON_LIFETIME, 145000).

-spec(send_response(pid(), coap_message()) -> ok).
send_response(Channel, Resp) ->
    gen_server:cast(Channel, {send_response, Resp}).

-spec(start_link(inet:socket(), coap_endpoint()) -> {ok, pid()}).
start_link(Sock, Endpoint) ->
	gen_server:start_link(?MODULE, [Sock, Endpoint], []).

%% gen_server.
init([Sock, Endpoint]) ->
    {ok, #state{sock           = Sock, 
                endpoint       = Endpoint, 
                next_msg_id    = 0,
                auto_reply_ack = #{},
                awaiting_ack   = #{}}}.

handle_call(_Request, _From, State) ->
	{reply, ignored, State}.

handle_cast({send_response, Resp}, State = #state{
             endpoint = Endpoint, sock = Sock, auto_reply_ack = AutoReplyAck, 
             awaiting_ack = AwaitingAck, next_msg_id = NextMsgId}) ->
    {IpAddr, Port} = Endpoint,
    MsgId = Resp#coap_message.id,
    NextMsgId2 = next_msg_id(NextMsgId),
    {State2, Resp2} = case maps:find(MsgId, AutoReplyAck) of
        {ok, {_, undefined}} ->
            Resp3 = Resp#coap_message{id = NextMsgId2},
            random:seed(os:timestamp()),
            Timeout = ?ACK_TIMEOUT+random:uniform(?ACK_RANDOM_FACTOR),
            AckTimer = erlang:send_after(Timeout, self(), {awaiting_ack, Resp3}),
            AwaitingAck2 = maps:put(NextMsgId2, {AckTimer, Timeout, 0}, AwaitingAck),
            
            {State#state{auto_reply_ack = maps:remove(MsgId, AutoReplyAck), 
                         awaiting_ack = AwaitingAck2,
                         next_msg_id = NextMsgId2}, Resp3};
        {ok, {_, Timer}} ->
            erlang:cancel_timer(Timer),
            {State#state{auto_reply_ack = maps:remove(MsgId, AutoReplyAck)}, Resp#coap_message{type = 'ACK'}};
        _ ->
            {State#state{next_msg_id = NextMsgId2}, Resp#coap_message{id = NextMsgId2}}    
    end,
    ?LOG(info, "SEND ~p", [emqttd_coap_message:format(Resp2)], State),
    gen_udp:send(Sock, IpAddr, Port, emqttd_coap_message:serialize(Resp2)),
    {noreply, State2};

handle_cast(_Req, State) ->
	{noreply, State}.

handle_info({datagram, _From, Packet}, State) ->
    ?LOG(debug, "RECV ~p", [Packet], State),
    Msg = emqttd_coap_message:parse(Packet),
    ?LOG(info, "RECV ~p", [emqttd_coap_message:format(Msg)], State),
    handle_message(Msg, State);

handle_info({awaiting_ack, RespMsg = #coap_message{id = MsgId}}, 
             State = #state{endpoint = Endpoint, sock = Sock, awaiting_ack = AwaitingAck})->
    {IpAddr, Port} = Endpoint,
    case maps:find(MsgId, AwaitingAck) of
        {ok, {_, Timeout, RetryCount}} when RetryCount < 4 ->
            Timeout2 = Timeout * 2,
            AckTimer = erlang:send_after(Timeout2, self(), {awaiting_ack, RespMsg}),
            AwaitingAck2 = maps:put(MsgId, {AckTimer, Timeout2, RetryCount+1}, AwaitingAck),
            ?LOG(info, "SEND ~p", [emqttd_coap_message:format(RespMsg)], State),
            gen_udp:send(Sock, IpAddr, Port, emqttd_coap_message:serialize(RespMsg)),
            {noreply, State#state{awaiting_ack = AwaitingAck2}};
        {ok, {_, _, _}} ->
            {stop, normal, State};
        _ ->
            {noreply, State}
    end;

handle_info({auto_reply_ack, AckMsg = #coap_message{id = MsgId}, Token}, State = #state{
             endpoint = Endpoint, sock = Sock, auto_reply_ack = AutoReplyAck}) ->
    {IpAddr, Port} = Endpoint,
    ?LOG(info, "SEND ~p", [emqttd_coap_message:format(AckMsg)], State),
    gen_udp:send(Sock, IpAddr, Port, emqttd_coap_message:serialize(AckMsg)),
    AutoReplyAck2 = maps:put(MsgId, {Token, undefined}, AutoReplyAck),
    {noreply, State#state{auto_reply_ack = AutoReplyAck2}};

% handle_info({_, timeout}, State) ->
%     {noreply, State};

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

handle_message(Msg = #coap_message{type = Type}, State) ->
    {noreply, idle(Type, Msg, State)}.

idle('CON', Msg, State) ->
    % erlang:send_after(?EXCHANGE_LIFETIME, self(), {con_req, timeout}),
    handle_con_req(Msg, State);

idle('NON', Msg, State) ->
    % erlang:send_after(?NON_LIFETIME, self(), {non_req, timeout}),
    handle_non_req(Msg, State);

idle('ACK', #coap_message{id = MsgId}, State = #state{awaiting_ack = AwaitingAck}) ->
    case maps:find(MsgId, AwaitingAck) of
        {ok, {Timer, _, _}} ->
            erlang:cancel_timer(Timer),
            State#state{awaiting_ack = maps:remove(MsgId, AwaitingAck)};
        _ ->
            State
    end;

idle('RST', #coap_message{}, State) ->
    State.
    
handle_con_req(Req = #coap_message{method = Mothod, token = Token, id = MsgId}, 
               State = #state{auto_reply_ack = AutoReplyAck}) ->
    case Mothod of
        undefined ->
            send_res_msg(Req, State);
        _ ->
            AckMsg = #coap_message{type = 'ACK', id = Req#coap_message.id},
            Timer = erlang:send_after(?PROCESSING_DELAY, self(), {auto_reply_ack, AckMsg, Token}),
            AutoReplyAck2 = maps:put(MsgId, {Token, Timer}, AutoReplyAck),
            handle_response(Req, State#state{auto_reply_ack = AutoReplyAck2})
    end.

handle_non_req(Req, State) ->
    handle_response(Req, State).
    
send_res_msg(Req, State = #state{sock = Sock, endpoint = Endpoint}) ->
    {IpAddr, Port} = Endpoint,
    Resp = #coap_message{type = 'RST', id = Req#coap_message.id},
    ?LOG(info, "SEND ~p", [emqttd_coap_message:format(Resp)], State),
    gen_udp:send(Sock, IpAddr, Port, emqttd_coap_message:serialize(Resp)),
    State.

handle_response(Req = #coap_message{options = Options}, 
                State = #state{sock = Sock, endpoint = Endpoint, auto_reply_ack = AutoReplyAck}) ->
    Uri = proplists:get_value('Uri-Path', Options, <<>>),
    MsgId = Req#coap_message.id,
    case emqttd_coap_response:get_responder(self(), binary_to_list(Uri), Endpoint) of
        {ok, Pid} ->
            Pid ! {coap_req, Req},
            State;
        {error, Code} ->
            Resp = #coap_message{type = 'ACK', code = Code, id = MsgId},
            {IpAddr, Port} = Endpoint,
            ?LOG(info, "SEND ~p", [emqttd_coap_message:format(Resp)], State),
            gen_udp:send(Sock, IpAddr, Port, emqttd_coap_message:serialize(Resp)),
            case maps:find(MsgId, AutoReplyAck) of
                {ok, { _, undefined}} -> ok;
                {ok, { _, Timer}}     -> erlang:cancel_timer(Timer);
                _                     -> ok
            end,
            State#state{auto_reply_ack = maps:remove(MsgId, AutoReplyAck)}
    end.

next_msg_id(Msgid) when Msgid =:= 65535 ->
    1;
next_msg_id(Msgid) ->
    Msgid + 1.