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

-module(emqx_coap_mqtt_adapter).

-behaviour(gen_server).

-include("emqx_coap.hrl").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

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

-record(state, {proto, peer, keepalive, sub_topics = [], enable_stats}).

-define(DEFAULT_KEEPALIVE_DURATION,  60 * 2).

-define(LOG(Level, Format, Args),
        emqx_logger:Level("CoAP-MQTT: " ++ Format, Args)).

-ifdef(TEST).
-define(PROTO_INIT(A, B, C, D, E),     test_mqtt_broker:start(A, B, C, D, E)).
-define(PROTO_SUBSCRIBE(X, Y),         test_mqtt_broker:subscribe(X)).
-define(PROTO_UNSUBSCRIBE(X, Y),       test_mqtt_broker:unsubscribe(X)).
-define(PROTO_PUBLISH(A1, A2, P),      test_mqtt_broker:publish(A1, A2)).
-define(PROTO_DELIVER_ACK(A1, A2, P),  P).
-define(PROTO_TIMEOUT(A1, A2, P),      P).
-define(PROTO_ENSURE_TIMER(A1, P),     ok).
-define(PROTO_SHUTDOWN(A, B),          ok).
-else.
-define(PROTO_INIT(A, B, C, D, E),     proto_init(A, B, C, D, E)).
-define(PROTO_SUBSCRIBE(X, Y),         proto_subscribe(X, Y)).
-define(PROTO_UNSUBSCRIBE(X, Y),       proto_unsubscribe(X, Y)).
-define(PROTO_PUBLISH(A1, A2, P),      proto_publish(A1, A2, P)).
-define(PROTO_DELIVER_ACK(A1, A2, P),  proto_deliver_ack(A1, A2, P)).
-define(PROTO_TIMEOUT(A1, A2, P),      proto_timeout(A1, A2, P)).
-define(PROTO_ENSURE_TIMER(A1, P),     emqx_channel:ensure_timer(A1, P)).
-define(PROTO_SHUTDOWN(A, B),          emqx_channel:terminate(A, B)).
-endif.

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
    case ?PROTO_INIT(ClientId, Username, Password, Channel, EnableStats) of
        {ok, Proto}           -> {ok, #state{proto = Proto, peer = Channel, enable_stats = EnableStats}};
        {stop, auth_failure}  -> {stop, auth_failure};
        Other                 -> {stop, Other}
    end.

handle_call({subscribe, Topic, CoapPid}, _From, State=#state{proto = Proto, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    IsWild = emqx_topic:wildcard(Topic),
    NewProto = ?PROTO_SUBSCRIBE(Topic, Proto),
    {reply, ok, State#state{proto = NewProto, sub_topics = [{Topic, {IsWild, CoapPid}}|NewTopics]}, hibernate};

handle_call({unsubscribe, Topic, _CoapPid}, _From, State=#state{proto = Proto, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    NewProto = ?PROTO_UNSUBSCRIBE(Topic, Proto),
    {reply, ok, State#state{proto = NewProto, sub_topics = NewTopics}, hibernate};

handle_call({publish, Topic, Payload}, _From, State=#state{proto = Proto}) ->
    NewProto = ?PROTO_PUBLISH(Topic, Payload, Proto),
    {reply, ok, State#state{proto = NewProto}};


handle_call(info, _From, State = #state{proto = ProtoState, peer = Channel}) ->
    ProtoInfo  = emqx_protocol:info(ProtoState),
    ClientInfo = [{peername, Channel}],
    Stats = stats(State),
    {reply, lists:append([ClientInfo, ProtoInfo, Stats]), State};

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

handle_call(session, _From, State = #state{proto = ProtoState}) ->
    {reply, emqx_protocol:session(ProtoState), State};

handle_call(Request, _From, State) ->
    ?LOG(error, "adapter unexpected call ~p", [Request]),
    {reply, ignored, State, hibernate}.

handle_cast(keepalive, State=#state{keepalive = undefined}) ->
    {noreply, State, hibernate};
handle_cast(keepalive, State=#state{keepalive = Keepalive, proto = Proto}) ->
    NProto = ?PROTO_ENSURE_TIMER(emit_stats, Proto),
    NewKeepalive = emqx_coap_timer:kick_timer(Keepalive),
    {noreply, State#state{keepalive = NewKeepalive, proto = NProto}, hibernate};

handle_cast(Msg, State) ->
    ?LOG(error, "broker_api unexpected cast ~p", [Msg]),
    {noreply, State, hibernate}.

handle_info(Deliver = {deliver, _Topic, _Msg}, State = #state{proto = Proto, sub_topics = Subscribers}) ->
    case emqx_channel:handle_out(Deliver, Proto) of
        {ok, Proto1} -> {noreply, State#state{proto = Proto1}};
        {ok, PubPkts, Proto1} ->
            Proto2 = deliver(PubPkts, Proto1, Subscribers),
            {noreply, State#state{proto = Proto2}};
        {stop, Reason, Proto1} ->
            {stop, Reason, State#state{proto = Proto1}}
    end;

%% TODO:
handle_info({keepalive, start, Interval}, StateData) ->
    ?LOG(debug, "Keepalive at the interval of ~p", [Interval]),
    KeepAlive = emqx_coap_timer:start_timer(Interval, {keepalive, check}),
    {noreply, StateData#state{keepalive = KeepAlive}, hibernate};

handle_info({keepalive, check}, StateData = #state{keepalive = KeepAlive}) ->
    case emqx_coap_timer:is_timeout(KeepAlive) of
        false ->
            ?LOG(debug, "Keepalive checked ok", []),
            NewKeepAlive = emqx_coap_timer:restart_timer(KeepAlive),
            {noreply, StateData#state{keepalive = NewKeepAlive}};
        true ->
            ?LOG(debug, "Keepalive timeout", []),
            {stop, normal, StateData}
    end;

handle_info({timeout, TRef, emit_stats}, State) ->
    {noreply, handle_timeout(TRef, {emit_stats, stats(State)}, State)};

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

terminate(Reason, #state{proto = Proto, keepalive = KeepAlive}) ->
    emqx_coap_timer:cancel_timer(KeepAlive),
    case {Proto, Reason} of
        {undefined, _} ->
            ok;
        {_, {shutdown, Error}} ->
            ?PROTO_SHUTDOWN(Error, Proto);
        {_, Reason} ->
            ?PROTO_SHUTDOWN(Reason, Proto)
    end.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

proto_init(ClientId, Username, Password, Channel, EnableStats) ->
    Options = [{zone, external}],
    ConnInfo = #{peername => Channel,
                 sockname => {{0,0,0,0}, 5683},
                 peercert => nossl},
    Proto = set_enable_stats(EnableStats, emqx_channel:init(ConnInfo, Options)),
    ConnPkt = #mqtt_packet_connect{client_id  = ClientId,
                                   username = Username,
                                   password = Password,
                                   clean_start = true,
                                   keepalive = application:get_env(?APP, keepalive, ?DEFAULT_KEEPALIVE_DURATION)},
    case emqx_channel:received(?CONNECT_PACKET(ConnPkt), Proto) of
        {ok, _Connack, Proto1} -> {ok, Proto1};
        {stop, {shutdown, auth_failure}, _Connack, _Proto1} -> {stop, auth_failure};
        Other -> error(Other)
    end.

proto_subscribe(Topic, Proto) ->
    ?LOG(debug, "subscribe Topic=~p", [Topic]),
    case emqx_channel:handle_in(?SUBSCRIBE_PACKET(1, [{Topic, #{rh => 0, rap => 0, nl => 0, qos => ?QOS_1}}]), Proto) of
        {ok, _Suback, Proto1} -> Proto1;
        {stop, {shutdown, Reason}, _Discon, _Proto1} -> error({shutdown, Reason});
        Other -> error(Other)
    end.

proto_unsubscribe(Topic, Proto) ->
    ?LOG(debug, "unsubscribe Topic=~p", [Topic]),
    case emqx_channel:handle_in(?UNSUBSCRIBE_PACKET(1, [Topic]), Proto) of
        {ok, _Unsuback, Proto1} -> Proto1;
        {stop, {shutdown, Reason}, _Discon, _Proto1} -> error({shutdown, Reason});
        Other -> error(Other)
    end.

proto_publish(Topic, Payload, Proto) ->
    ?LOG(debug, "publish Topic=~p, Payload=~p", [Topic, Payload]),
    Publish = #mqtt_packet{
                 header = #mqtt_packet_header{type = ?PUBLISH, qos = ?QOS_0},
                 variable = #mqtt_packet_publish{topic_name = Topic, packet_id = 1},
                 payload  = Payload
                },
    case emqx_channel:handle_in(Publish, Proto) of
        {ok, Proto1}  -> Proto1;
        {stop, {shutdown, Reason}, _Discon, _Proto1} -> error({shutdown, Reason});
        Other         -> error(Other)
    end.

proto_deliver_ack(?QOS_0, _, Proto) ->
    Proto;
proto_deliver_ack(?QOS_1, PktId, Proto) ->
    case emqx_channel:handle_in(?PUBACK_PACKET(PktId), Proto) of
        {ok, NProto} -> NProto;
        Other -> error(Other)
    end;

proto_deliver_ack(?QOS_2, PktId, Proto) ->
    case emqx_channel:handle_in(?PUBREC_PACKET(PktId), Proto) of
        {ok, Proto1} ->
            case emqx_channel:handle_in(?PUBCOMP_PACKET(PktId), Proto1) of
                {ok, Proto2} -> Proto2;
                Another -> error(Another)
            end;
        Other -> error(Other)
    end.

proto_timeout(TRef, Msg, Proto) ->
    case emqx_channel:timeout(TRef, Msg, Proto) of
        {ok, NProto} -> NProto;
        {ok, _Pkts, NProto} ->
            %% TODO: pkts???
            NProto;
        Other -> error(Other)
    end.

deliver([], Proto, _) -> Proto;
deliver([Pub | More], Proto, Subscribers) ->
    {ok, Proto1} = deliver(Pub, Proto, Subscribers),
    deliver(More, Proto1, Subscribers);

deliver(?PUBLISH_PACKET(Qos, Topic, PktId, Payload), Proto, Subscribers) ->
    %% handle PUBLISH packet from broker
    ?LOG(debug, "deliver message from broker Topic=~p, Payload=~p", [Topic, Payload]),

    NProto = ?PROTO_DELIVER_ACK(Qos, PktId, Proto),
    deliver_to_coap(Topic, Payload, Subscribers),
    {ok, NProto};

deliver(Pkt, Proto, _Subscribers) ->
    ?LOG(warning, "unknown packet type to deliver, pkt=~p,", [Pkt]),
    {ok, Proto}.

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
%%--------------------------------------------------------------------

set_enable_stats(EnableStats, PState) ->
    PState#{enable_stats => EnableStats}.

handle_timeout(TRef, Msg = {emit_stats, _}, #state{proto = Proto}) ->
    ?PROTO_TIMEOUT(TRef, Msg, Proto),
    ok.

stats(#state{proto = ChanState}) ->
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


