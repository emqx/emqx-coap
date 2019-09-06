%%--------------------------------------------------------------------
%% Copyright (c) 2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_coap_mqtt_adapter).

-behaviour(gen_server).

-include("emqx_coap.hrl").

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx/include/logger.hrl").

-logger_header("[CoAP-Adpter]").

%% API.
-export([ subscribe/2
        , unsubscribe/2
        , publish/3
        , keepalive/1
        ]).

-export([ client_pid/4
        , stop/1
        ]).

%% gen_server.
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state, {chann, peer, keepalive, sub_topics = [], enable_stats}).

-define(DEFAULT_KEEPALIVE_DURATION,  60 * 2).

-define(CHANN_INIT(A, B, C, D, E),     chann_init(A, B, C, D, E)).
-define(CHANN_SUBSCRIBE(X, Y),         chann_subscribe(X, Y)).
-define(CHANN_UNSUBSCRIBE(X, Y),       chann_unsubscribe(X, Y)).
-define(CHANN_PUBLISH(A1, A2, P),      chann_publish(A1, A2, P)).
-define(CHANN_HANDLEOUT(A1, P),        emqx_channel:handle_out(A1, P)).
-define(CHANN_DELIVER_ACK(A1, A2, P),  chann_deliver_ack(A1, A2, P)).
-define(CHANN_TIMEOUT(A1, A2, P),      chann_timeout(A1, A2, P)).
-define(CHANN_ENSURE_TIMER(A1, P),     emqx_channel:ensure_timer(A1, P)).
-define(CHANN_SHUTDOWN(A, B),          emqx_channel:terminate(A, B)).

-define(CHAN_STATS, [recv_pkt, recv_msg, send_pkt, send_msg]).
-define(SOCK_STATS, [recv_oct, recv_cnt, send_oct, send_cnt, send_pend]).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

client_pid(undefined, _Username, _Password, _Channel) ->
    {error, bad_request};
client_pid(ClientId, Username, Password, Channel) ->
    % check authority
    case start(ClientId, Username, Password, Channel) of
        {ok, Pid1}                       -> {ok, Pid1};
        {error, {already_started, Pid2}} -> {ok, Pid2};
        {error, auth_failure}            -> {error, auth_failure};
        Other                            -> {error, Other}
    end.

start(ClientId, Username, Password, Channel) ->
    % DO NOT use start_link, since multiple coap_reponsder may have relation with one mqtt adapter,
    % one coap_responder crashes should not make mqtt adapter crash too
    % And coap_responder is not a system process, it is dangerous to link mqtt adapter to coap_responder
    gen_server:start({via, emqx_coap_registry, {ClientId, Username, Password}}, ?MODULE, {ClientId, Username, Password, Channel}, []).

stop(Pid) ->
    gen_server:stop(Pid).

subscribe(Pid, Topic) ->
    gen_server:call(Pid, {subscribe, Topic, self()}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic, self()}).

publish(Pid, Topic, Payload) ->
    gen_server:call(Pid, {publish, Topic, Payload}).

keepalive(Pid)->
    gen_server:cast(Pid, keepalive).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init({ClientId, Username, Password, Channel}) ->
    ?LOG(debug, "try to start adapter ClientId=~p, Username=~p, Password=~p, Channel=~p", [ClientId, Username, Password, Channel]),

    EnableStats = application:get_env(?APP, enable_stats, false),
    Interval = application:get_env(?APP, keepalive, ?DEFAULT_KEEPALIVE_DURATION),

    case ?CHANN_INIT(ClientId, Username, Password, Channel, EnableStats) of
        {ok, CState} ->
            ?LOG(debug, "Keepalive at the interval of ~p", [Interval]),
            AliveTimer = emqx_coap_timer:start_timer(Interval, {keepalive, check}),
            {ok, #state{chann = CState, peer = Channel, keepalive = AliveTimer, enable_stats = EnableStats}};
        {stop, auth_failure} ->
            {stop, auth_failure};
        Other ->
            {stop, Other}
    end.

handle_call({subscribe, Topic, CoapPid}, _From, State=#state{chann = CState, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    IsWild = emqx_topic:wildcard(Topic),
    NCState = ?CHANN_SUBSCRIBE(Topic, CState),
    {reply, ok, State#state{chann = NCState, sub_topics = [{Topic, {IsWild, CoapPid}}|NewTopics]}, hibernate};

handle_call({unsubscribe, Topic, _CoapPid}, _From, State=#state{chann = CState, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    NCState = ?CHANN_UNSUBSCRIBE(Topic, CState),
    {reply, ok, State#state{chann = NCState, sub_topics = NewTopics}, hibernate};

handle_call({publish, Topic, Payload}, _From, State=#state{chann = CState}) ->
    NCState = ?CHANN_PUBLISH(Topic, Payload, CState),
    {reply, ok, State#state{chann = NCState}};

handle_call(info, _From, State = #state{chann = CStateState, peer = Channel}) ->
    CStateInfo  = emqx_channel:info(CStateState),
    ClientInfo = [{peername, Channel}],
    Stats = stats(State),
    {reply, lists:append([ClientInfo, CStateInfo, Stats]), State};

handle_call(stats, _From, State) ->
    {reply, stats(State), State, hibernate};

handle_call(kick, _From, State) ->
    {stop, {shutdown, kick}, ok, State};

handle_call({set_rate_limit, _Rl}, _From, State) ->
    ?LOG(error, "set_rate_limit is not support", []),
    {reply, ok, State};

handle_call(get_rate_limit, _From, State) ->
    ?LOG(error, "get_rate_limit is not support", []),
    {reply, ok, State};

handle_call(session, _From, State = #state{chann = CStateState}) ->
    {reply, emqx_channel:info(session, CStateState), State};

handle_call(Request, _From, State) ->
    ?LOG(error, "adapter unexpected call ~p", [Request]),
    {reply, ignored, State, hibernate}.

handle_cast(keepalive, State=#state{keepalive = undefined}) ->
    {noreply, State, hibernate};

handle_cast(keepalive, State=#state{keepalive = Keepalive}) ->
    NewKeepalive = emqx_coap_timer:kick_timer(Keepalive),
    {noreply, State#state{keepalive = NewKeepalive}, hibernate};

handle_cast(Msg, State) ->
    ?LOG(error, "broker_api unexpected cast ~p", [Msg]),
    {noreply, State, hibernate}.

handle_info(Deliver = {deliver, _Topic, _Msg}, State = #state{chann = CState, sub_topics = Subscribers}) ->
    Delivers = emqx_misc:drain_deliver([Deliver]),
    case ?CHANN_HANDLEOUT({deliver, Delivers}, CState) of
        {ok, CState1} -> {noreply, State#state{chann = CState1}};
        {ok, PubPkts, CState1} ->
            {ok, CState2} = deliver(PubPkts, CState1, Subscribers),
            {noreply, State#state{chann = CState2}};
        {stop, Reason, CState1} ->
            {stop, Reason, State#state{chann = CState1}}
    end;

handle_info({keepalive, check}, State = #state{keepalive = Timer}) ->
    case emqx_coap_timer:is_timeout(Timer) of
        false ->
            ?LOG(debug, "Keepalive checked ok", []),
            NTimer = emqx_coap_timer:restart_timer(Timer),
            {noreply, State#state{keepalive = NTimer}};
        true ->
            ?LOG(info, "Keepalive timeout", []),
            {stop, normal, State}
    end;

handle_info({timeout, TRef, emit_stats}, State) ->
    {noreply, ok, handle_timeout(TRef, {emit_stats, stats(State)}, State)};

handle_info(timeout, State) ->
    {stop, {shutdown, idle_timeout}, State};

handle_info({shutdown, Error}, State) ->
    {stop, {shutdown, Error}, State};

handle_info({shutdown, conflict, {ClientId, NewPid}}, State) ->
    ?LOG(warning, "clientid '~s' conflict with ~p", [ClientId, NewPid]),
    {stop, {shutdown, conflict}, State};

handle_info(Info, State) ->
    ?LOG(error, "adapter unexpected info ~p", [Info]),
    {noreply, State, hibernate}.

terminate(Reason, #state{chann = CState, keepalive = Timer}) ->
    emqx_coap_timer:cancel_timer(Timer),
    case {CState, Reason} of
        {undefined, _} ->
            ok;
        {_, {shutdown, Error}} ->
            ?CHANN_SHUTDOWN(Error, CState);
        {_, Reason} ->
            ?CHANN_SHUTDOWN(Reason, CState)
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Channel adapter functions

chann_init(ClientId, Username, Password, Channel, EnableStats) ->
    Options = [{zone, external}],
    ConnInfo = #{peername => Channel,
                 sockname => {{0,0,0,0}, 5683},
                 peercert => nossl},
    CState = set_enable_stats(EnableStats, emqx_channel:init(ConnInfo, Options)),
    ConnPkt = #mqtt_packet_connect{client_id   = ClientId,
                                   username    = Username,
                                   password    = Password,
                                   clean_start = true,
                                   keepalive   = 0         %% Not set keepalive timer with channel functions
                                  },
    case emqx_channel:handle_in(?CONNECT_PACKET(ConnPkt), CState) of
        {ok, _Connack, CState1} -> {ok, CState1};
        {stop, {shutdown, auth_failure}, _Connack, _CState1} -> {stop, auth_failure};
        Other -> error(Other)
    end.

chann_subscribe(Topic, CState) ->
    ?LOG(debug, "subscribe Topic=~p", [Topic]),
    SubOpts = #{rh => 0, rap => 0, nl => 0, qos => ?QOS_1},
    throw_if(
      emqx_channel:handle_in(?SUBSCRIBE_PACKET(1, [{Topic, SubOpts}]), CState)).

chann_unsubscribe(Topic, CState) ->
    ?LOG(debug, "unsubscribe Topic=~p", [Topic]),
    throw_if(
      emqx_channel:handle_in(?UNSUBSCRIBE_PACKET(1, [Topic]), CState)).

chann_publish(Topic, Payload, CState) ->
    ?LOG(debug, "publish Topic=~p, Payload=~p", [Topic, Payload]),
    Publish = #mqtt_packet{
                 header = #mqtt_packet_header{type = ?PUBLISH, qos = ?QOS_0},
                 variable = #mqtt_packet_publish{topic_name = Topic, packet_id = 1},
                 payload  = Payload
                },
    throw_if(
      emqx_channel:handle_in(Publish, CState)).

chann_deliver_ack(?QOS_0, _, CState) ->
    CState;
chann_deliver_ack(?QOS_1, PktId, CState) ->
    throw_if(
      emqx_channel:handle_in(?PUBACK_PACKET(PktId), CState));

chann_deliver_ack(?QOS_2, PktId, CState) ->
    CState1 = throw_if(emqx_channel:handle_in(?PUBREC_PACKET(PktId), CState)),
    throw_if(
      emqx_channel:handle_in(?PUBCOMP_PACKET(PktId), CState1)).

chann_timeout(TRef, Msg, CState) ->
    case emqx_channel:timeout(TRef, Msg, CState) of
        {ok, NCState} -> NCState;
        {ok, _Pkts, NCState} ->
            %% TODO: pkts???
            NCState;
        Other -> error(Other)
    end.

%%--------------------------------------------------------------------
%% Deliver

deliver([], CState, _) -> CState;
deliver([Pub | More], CState, Subscribers) ->
    {ok, CState1} = deliver(Pub, CState, Subscribers),
    deliver(More, CState1, Subscribers);

deliver(?PUBLISH_PACKET(Qos, Topic, PktId, Payload), CState, Subscribers) ->
    %% handle PUBLISH packet from broker
    ?LOG(debug, "deliver message from broker Topic=~p, Payload=~p", [Topic, Payload]),

    NCState = ?CHANN_DELIVER_ACK(Qos, PktId, CState),
    deliver_to_coap(Topic, Payload, Subscribers),
    {ok, NCState};

deliver(Pkt, CState, _Subscribers) ->
    ?LOG(warning, "unknown packet type to deliver, pkt=~p,", [Pkt]),
    {ok, CState}.

deliver_to_coap(_TopicName, _Payload, []) ->
    ok;
deliver_to_coap(TopicName, Payload, [{TopicFilter, {IsWild, CoapPid}}|T]) ->
    Matched =   case IsWild of
                    true  -> emqx_topic:match(TopicName, TopicFilter);
                    false -> TopicName =:= TopicFilter
                end,
    %?LOG(debug, "deliver_to_coap Matched=~p, CoapPid=~p, TopicName=~p, Payload=~p, T=~p", [Matched, CoapPid, TopicName, Payload, T]),
    Matched andalso (CoapPid ! {dispatch, TopicName, Payload}),
    deliver_to_coap(TopicName, Payload, T).

%%--------------------------------------------------------------------
%% Misc funcs

set_enable_stats(EnableStats, CState) ->
    StatsTimer = if
                     EnableStats -> undefined;
                     true -> disabled
                 end,
    Timers = element(6, CState),
    setelement(6, CState, Timers#{stats_timer => StatsTimer}).

handle_timeout(TRef, Msg = {emit_stats, _}, State = #state{chann = CState}) ->
    State#state{chann = ?CHANN_TIMEOUT(TRef, Msg, CState)}.

throw_if({ok, CState}) ->
    CState;
throw_if({ok, _Pkts, CState}) ->
    CState;
throw_if({stop, Reason, _DisconnPkt, _CState}) ->
    error(Reason);
throw_if(OtherRet) ->
    error(OtherRet).


stats(#state{chann = ChanState}) ->
    SockStats = socket_stats(undefined, ?SOCK_STATS),
    ChanStats = [{Name, emqx_pd:get_counter(Name)} || Name <- ?CHAN_STATS],
    SessStats = emqx_session:stats(emqx_channel:info(session, ChanState)),
    lists:append([SockStats, ChanStats, SessStats, emqx_misc:proc_stats()]).

%% here we keep the original socket_stats implementation, which will be put into use when we can get socket fd in emqx_coap_mqtt_adapter process
%socket_stats(Sock, Stats) when is_port(Sock), is_list(Stats)->
    %inet:getstat(Sock, Stats).

%%this socket_stats is a fake funtion
socket_stats(undefined, Stats) when is_list(Stats)->
    FakeSockOpt = [0, 0, 0, 0, 0],
    List = lists:zip(Stats, FakeSockOpt),
    ?LOG(debug, "The List=~p", [List]),
    List.

