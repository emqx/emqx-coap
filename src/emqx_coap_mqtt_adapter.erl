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

%% gen_server.
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state, {client_info, peer, sub_topics = []}).

-define(CHANN_HANDLEOUT(A1, P),        emqx_channel:handle_out(A1, P)).
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

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init({ClientId, Username, Password,  {PeerHost, _Port}= Channel}) ->
    ?LOG(debug, "try to start adapter ClientId=~p, Username=~p, Password=~p, Channel=~p",
         [ClientId, Username, Password, Channel]),
    case authenticate(ClientId, Username, Password, PeerHost) of
        ok ->
            ClientInfo = #{clientid => ClientId, username => Username, peerhost => PeerHost},
            {ok, #state{client_info = ClientInfo, peer = Channel}};
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

handle_call(info, _From, State = #state{peer = PeerHost}) ->
    ClientInfo = [{peerhost, PeerHost}],
    {reply, ClientInfo, State};

handle_call(stats, _From, State) ->
    {reply, [], State, hibernate};

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

terminate(Reason, #state{client_info = ClientInfo, sub_topics = SubTopics}) ->
    ?LOG(debug, "unsubscribe ~p while exiting for ~p", [SubTopics, Reason]),
    [chann_unsubscribe(Topic, ClientInfo) || {Topic, _} <- SubTopics],
    emqx_hooks:run('client.disconnected', [ClientInfo, Reason, #{}]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Channel adapter functions

authenticate(ClientId, Username, Password, PeerHost) ->
    Credentials = credentials(PeerHost, ClientId, Username, Password),
    case emqx_access_control:authenticate(Credentials) of
        {ok, AuthResult} ->
            Credentials1 = maps:merge(Credentials, AuthResult),
            emqx_hooks:run('client.connected',
                          [Credentials1, ?RC_SUCCESS,
                          #{clean_start => true,
                            expiry_interval => 0,
                            proto_name => coap,
                            peerhost => PeerHost,
                            connected_at => os:timestamp(),
                            keepalive => 0,
                            peercert => nossl,
                            proto_ver => <<"1.0">>}]),
            ok;
        {error, Error} ->
            emqx_hooks:run('client.connected', [Credentials, ?RC_NOT_AUTHORIZED, #{}]),
            {error, Error}
    end.

chann_subscribe(Topic, ClientInfo) ->
    ?LOG(debug, "subscribe Topic=~p", [Topic]),
    Opts = #{rh => 0, rap => 0, nl => 0, qos => ?QOS_0},
    emqx_broker:subscribe(Topic, Opts),
    emqx_hooks:run('session.subscribed', [ClientInfo, Topic, Opts]).

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

credentials(PeerHost, ClientId, Username, Password) ->
    #{peerhost => PeerHost,
      clientid => ClientId,
      username => Username,
      password => Password}.
