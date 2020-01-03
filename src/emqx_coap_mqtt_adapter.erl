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

-module(emqx_coap_mqtt_adapter).

-behaviour(gen_server).

-include("emqx_coap.hrl").

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").

-logger_header("[CoAP-Adpter]").

%% API.
-export([ subscribe/2
        , unsubscribe/2
        , publish/3
        ]).

-export([ client_pid/4
        , stop/1
        ]).

-export([call/2]).

%% gen_server.
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state, {client_info, peername, sub_topics = [], connected_at}).

-define(ALIVE_INTERVAL, 20000).

-define(CONN_STATS, [recv_pkt, recv_msg, send_pkt, send_msg]).

-define(SUBOPTS, #{rh => 0, rap => 0, nl => 0, qos => ?QOS_0, is_new => false}).

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

%% For emqx_management plugin
call(Pid, Msg) ->
    Pid ! Msg, ok.

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init({ClientId, Username, Password,  {PeerHost, _Port}= Channel}) ->
    ?LOG(debug, "try to start adapter ClientId=~p, Username=~p, Password=~p, Channel=~p",
         [ClientId, Username, Password, Channel]),
    case authenticate(ClientId, Username, Password, PeerHost) of
        ok ->
            ClientInfo = #{clientid => ClientId, username => Username, peerhost => PeerHost},
            State = #state{client_info = ClientInfo,
                           peername = Channel,
                           connected_at = os:system_time(second)},

            %% TODO: Evict same clientid on other node??

            erlang:send_after(?ALIVE_INTERVAL, self(), check_alive),

            emqx_cm:register_channel(ClientId, info(State), stats(State)),

            {ok, State};
        {error, Reason} ->
            ?LOG(debug, "authentication faild: ~p", [Reason]),
            {stop, {shutdown, Reason}}
    end.

handle_call({subscribe, Topic, CoapPid}, _From, State=#state{client_info = ClientInfo, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    IsWild = emqx_topic:wildcard(Topic),
    chann_subscribe(Topic, ClientInfo),
    {reply, ok, State#state{sub_topics = [{Topic, {IsWild, CoapPid}}|NewTopics]}, hibernate};

handle_call({unsubscribe, Topic, _CoapPid}, _From, State=#state{client_info = ClientInfo, sub_topics = TopicList}) ->
    NewTopics = proplists:delete(Topic, TopicList),
    chann_unsubscribe(Topic, ClientInfo),
    {reply, ok, State#state{sub_topics = NewTopics}, hibernate};

handle_call({publish, Topic, Payload}, _From, State=#state{client_info = ClientInfo}) ->
    chann_publish(Topic, Payload, ClientInfo),
    {reply, ok, State};

handle_call(info, _From, State) ->
    {reply, info(State), State};

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

handle_call(Request, _From, State) ->
    ?LOG(error, "adapter unexpected call ~p", [Request]),
    {reply, ignored, State, hibernate}.

handle_cast(Msg, State) ->
    ?LOG(error, "broker_api unexpected cast ~p", [Msg]),
    {noreply, State, hibernate}.

handle_info({deliver, _Topic, #message{topic = Topic, payload = Payload}}, State = #state{sub_topics = Subscribers}) ->
    deliver([{Topic, Payload}], Subscribers),
    {noreply, State, hibernate};

handle_info(check_alive, State = #state{sub_topics = []}) ->
    {stop, {shutdown, check_alive}, State};
handle_info(check_alive, State) ->
    erlang:send_after(?ALIVE_INTERVAL, self(), check_alive),
    {noreply, State, hibernate};

handle_info({shutdown, Error}, State) ->
    {stop, {shutdown, Error}, State};

handle_info({shutdown, conflict, {ClientId, NewPid}}, State) ->
    ?LOG(warning, "clientid '~s' conflict with ~p", [ClientId, NewPid]),
    {stop, {shutdown, conflict}, State};

handle_info(kick, State) ->
    ?LOG(info, "Kicked", []),
    {stop, {shutdown, kick}, State};

handle_info(Info, State) ->
    ?LOG(error, "adapter unexpected info ~p", [Info]),
    {noreply, State, hibernate}.

terminate(Reason, #state{client_info = ClientInfo, sub_topics = SubTopics}) ->
    ?LOG(debug, "unsubscribe ~p while exiting for ~p", [SubTopics, Reason]),
    #{clientid := ClientId} = ClientInfo,
    [chann_unsubscribe(Topic, ClientInfo) || {Topic, _} <- SubTopics],
    emqx_cm:unregister_channel(ClientId),
    emqx_hooks:run('client.disconnected', [ClientInfo, Reason, #{}]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Channel adapter functions

authenticate(ClientId, Username, Password, PeerHost) ->
    ClientInfo = clientinfo(PeerHost, ClientId, Username, Password),
    case emqx_access_control:authenticate(ClientInfo) of
        {ok, AuthResult} ->
            ClientInfo1 = maps:merge(ClientInfo, AuthResult),
            emqx_hooks:run('client.connected',
                          [ClientInfo1, ?RC_SUCCESS,
                          #{clean_start => true,
                            expiry_interval => 0,
                            proto_name => coap,
                            peerhost => PeerHost,
                            connected_at => erlang:system_time(second),
                            keepalive => 0,
                            peercert => nossl,
                            proto_ver => <<"1.0">>}]),
            ok;
        {error, Error} ->
            emqx_hooks:run('client.connected', [ClientInfo, ?RC_NOT_AUTHORIZED, #{}]),
            {error, Error}
    end.

chann_subscribe(Topic, ClientInfo = #{clientid := ClientId}) ->
    ?LOG(debug, "subscribe Topic=~p", [Topic]),
    emqx_broker:subscribe(Topic, ClientId, ?SUBOPTS),
    emqx_hooks:run('session.subscribed', [ClientInfo, Topic, ?SUBOPTS]).

chann_unsubscribe(Topic, ClientInfo) ->
    ?LOG(debug, "unsubscribe Topic=~p", [Topic]),
    Opts = #{rh => 0, rap => 0, nl => 0, qos => 0},
    emqx_broker:unsubscribe(Topic),
    emqx_hooks:run('session.unsubscribed', [ClientInfo, Topic, Opts]).

chann_publish(Topic, Payload, #{clientid := ClientId}) ->
    ?LOG(debug, "publish Topic=~p, Payload=~p", [Topic, Payload]),
    emqx_broker:publish(
        emqx_message:set_flag(retain, false,
            emqx_message:make(ClientId, ?QOS_0, Topic, Payload))).

%%--------------------------------------------------------------------
%% Deliver

deliver([], _) -> ok;
deliver([Pub | More], Subscribers) ->
    ok = do_deliver(Pub, Subscribers),
    deliver(More, Subscribers).

do_deliver({Topic, Payload}, Subscribers) ->
    %% handle PUBLISH packet from broker
    ?LOG(debug, "deliver message from broker Topic=~p, Payload=~p", [Topic, Payload]),
    deliver_to_coap(Topic, Payload, Subscribers),
    ok;

do_deliver(Pkt, _Subscribers) ->
    ?LOG(warning, "unknown packet type to deliver, pkt=~p,", [Pkt]),
    ok.

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
%% Info & Stats

info(State) ->
    ChannInfo = chann_info(State),
    ChannInfo#{sockinfo => sockinfo(State)}.

%% copies from emqx_connection:info/1
sockinfo(#state{peername = Peername}) ->
    #{socktype => udp,
      peername => Peername,
      sockname => {{127,0,0,1}, 5683},    %% FIXME: Sock?
      sockstate =>  running,
      active_n => 1
     }.

%% copies from emqx_channel:info/1
chann_info(State = #state{client_info = ClientInfo}) ->
    #{conninfo => conninfo(State),
      conn_state => connected,
      clientinfo => ClientInfo,
      session => maps:from_list(session_info(State)),
      will_msg => undefined
     }.

conninfo(#state{peername = Peername,
                connected_at = ConnectedAt,
                client_info = #{clientid := ClientId}}) ->
    #{socktype => udp,
      sockname => {{127,0,0,1}, 5683},
      peername => Peername,
      peercert => nossl,        %% TODO: dtls
      conn_mod => ?MODULE,
      proto_name => <<"coap">>,
      proto_ver => 1,
      clean_start => true,
      clientid => ClientId,
      username => undefined,
      conn_props => undefined,
      connected => true,
      connected_at => ConnectedAt,
      keepalive => 0,
      receive_maximum => 0,
      expiry_interval => 0
     }.

%% copies from emqx_session:info/1
session_info(#state{sub_topics = SubTopics, connected_at = ConnectedAt}) ->
    Subs = lists:foldl(
             fun({Topic, _}, Acc) ->
                Acc#{Topic => ?SUBOPTS}
             end, #{}, SubTopics),
    [{subscriptions, Subs},
     {upgrade_qos, false},
     {retry_interval, 0},
     {await_rel_timeout, 0},
     {created_at, ConnectedAt}
    ].

%% The stats keys copied from emqx_connection:stats/1
stats(#state{sub_topics = SubTopics}) ->
    SockStats = [{recv_oct,0}, {recv_cnt,0}, {send_oct,0}, {send_cnt,0}, {send_pend,0}],
    ConnStats = emqx_pd:get_counters(?CONN_STATS),
    ChanStats = [{subscriptions_cnt, length(SubTopics)},
                 {subscriptions_max, length(SubTopics)},
                 {inflight_cnt, 0},
                 {inflight_max, 0},
                 {mqueue_len, 0},
                 {mqueue_max, 0},
                 {mqueue_dropped, 0},
                 {next_pkt_id, 0},
                 {awaiting_rel_cnt, 0},
                 {awaiting_rel_max, 0}
                ],
    ProcStats = emqx_misc:proc_stats(),
    lists:append([SockStats, ConnStats, ChanStats, ProcStats]).

clientinfo(PeerHost, ClientId, Username, Password) ->
    #{zone => undefined,
      protocol => coap,
      peerhost => PeerHost,
      clientid => ClientId,
      username => Username,
      password => Password
     }.

