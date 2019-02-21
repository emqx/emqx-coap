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

-module(test_mqtt_broker).

-compile(export_all).

-behaviour(gen_server).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(record_to_proplist(Def, Rec),
        lists:zip(record_info(fields, Def), tl(tuple_to_list(Rec)))).

-define(record_to_proplist(Def, Rec, Fields),
    [{K, V} || {K, V} <- ?record_to_proplist(Def, Rec),
                         lists:member(K, Fields)]).

-define(LOGT(Format, Args), ct:print("TEST_BROKER: " ++ Format, Args)).

-record(state, {subscriber}).

-record(proto_stats, {enable_stats = false, recv_pkt = 0, recv_msg = 0, send_pkt = 0, send_msg = 0}).

start(_, <<"attacker">>, _, _, _) ->
    {stop, auth_failure};
start(ClientId, Username, Password, _Channel, EnableStats) ->
    true = is_binary(ClientId),
    true = ( is_binary(Username) or (Username == undefined) ),
    true = ( is_binary(Password) or (Password == undefined) ),
    self() ! {keepalive, start, 10},
    case EnableStats of
        true ->
            self() ! emit_stats,
            ?LOGT("send emit_stats", []);
        false ->
            ?LOGT("client_enable_stats is false, stats case may fail!", [])
    end,
    {ok, []}.

publish(Topic, Payload) ->
    gen_server:call(?MODULE, {publish, {Topic, Payload}}).

get_published_msg() ->
    gen_server:call(?MODULE, get_published_msg).

subscribe(Topic) ->
    gen_server:call(?MODULE, {subscribe, Topic, self()}).

get_subscrbied_topics() ->
    gen_server:call(?MODULE, get_subscribed_topics).

unsubscribe(Topic) ->
    gen_server:call(?MODULE, {unsubscribe, Topic}).


dispatch(Topic, Msg, MatchedTopicFilter) ->
    gen_server:call(?MODULE, {dispatch, {Topic, Msg, MatchedTopicFilter}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

init(_Param) ->
    ets:new(test_client_stats, [set, named_table, public]),
    {ok, #state{subscriber = []}}.


handle_call({publish, Msg = {Topic, Payload}}, _From, State) ->
    ?LOGT("test broker publish ~p~n", [Msg]),
    (is_binary(Topic) and is_binary(Payload)) orelse error("Topic and Payload should be binary"),
    put(unittest_message, Msg),
    {reply, {ok, []}, State};

handle_call(get_published_msg, _From, State) ->
    Response = get(unittest_message),
    ?LOGT("test broker get published msg=~p~n", [Response]),
    {reply, Response, State};

handle_call({subscribe, Topic, Proc}, _From, State=#state{subscriber = SubList}) ->
    ?LOGT("test broker subscribe Topic=~p, Pid=~p~n", [Topic, Proc]),
    is_binary(Topic) orelse error("Topic should be a binary"),
    {reply, {ok, []}, State#state{subscriber = [{Topic, Proc}|SubList]}};

handle_call(get_subscribed_topics, _From, State=#state{subscriber = SubList}) ->
    Response = subscribed_topics(SubList, []),
    ?LOGT("test broker get subscribed topics=~p~n", [Response]),
    {reply, Response, State};

handle_call({unsubscribe, Topic}, _From, State=#state{subscriber = SubList}) ->
    ?LOGT("test broker unsubscribe Topic=~p~n", [Topic]),
    is_binary(Topic) orelse error("Topic should be a binary"),
    NewSubList = proplists:delete(Topic, SubList),
    {reply, {ok, []}, State#state{subscriber = NewSubList}};


handle_call({dispatch, {Topic, Msg, MatchedTopicFilter}}, _From, State=#state{subscriber = SubList}) ->
    (is_binary(Topic) and is_binary(Msg)) orelse error("Topic and Msg should be binary"),
    Pid = proplists:get_value(MatchedTopicFilter, SubList),
    ?LOGT("test broker dispatch topic=~p, Msg=~p, Pid=~p, MatchedTopicFilter=~p, SubList=~p~n", [Topic, Msg, Pid, MatchedTopicFilter, SubList]),
    (Pid == undefined) andalso ?LOGT("!!!!! this topic ~p has never been subscribed, please specify a valid topic filter", [MatchedTopicFilter]),
    ?assertNotEqual(undefined, Pid),
    Pid ! {deliver, {publish, 1, #message{topic = Topic, payload = Msg}}},
    {reply, ok, State};

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(Req, _From, State) ->
    ?LOGT("test_broker_server: ignore call Req=~p~n", [Req]),
    {reply, {error, badreq}, State}.


handle_cast(Msg, State) ->
    ?LOGT("test_broker_server: ignore cast msg=~p~n", [Msg]),
    {noreply, State}.

handle_info(Info, State) ->
    ?LOGT("test_broker_server: ignore info=~p~n", [Info]),
    {noreply, State}.

terminate(Reason, _State) ->
    ?LOGT("test_broker_server: terminate Reason=~p~n", [Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.




subscribed_topics([], Acc) ->
    Acc;
subscribed_topics([{Topic,_Pid}|T], Acc) ->
    subscribed_topics(T, [Topic|Acc]).




-record(keepalive, {statfun, statval, tsec, tmsg, tref, repeat = 0}).

-type(keepalive() :: #keepalive{}).

%% @doc Start a keepalive
-spec(start(fun(), integer(), any()) -> undefined | keepalive()).
start(_, 0, _) ->
    undefined;
start(StatFun, TimeoutSec, TimeoutMsg) ->
    {ok, StatVal} = StatFun(),
    #keepalive{statfun = StatFun, statval = StatVal,
        tsec = TimeoutSec, tmsg = TimeoutMsg,
        tref = timer(TimeoutSec, TimeoutMsg)}.

%% @doc Check keepalive, called when timeout.
-spec(check(keepalive()) -> {ok, keepalive()} | {error, any()}).
check(KeepAlive = #keepalive{statfun = StatFun, statval = LastVal, repeat = Repeat}) ->
    case StatFun() of
        {ok, NewVal} ->
            if NewVal =/= LastVal ->
                {ok, resume(KeepAlive#keepalive{statval = NewVal, repeat = 0})};
                Repeat < 1 ->
                    {ok, resume(KeepAlive#keepalive{statval = NewVal, repeat = Repeat + 1})};
                true ->
                    {error, timeout}
            end;
        {error, Error} ->
            {error, Error}
    end.

resume(KeepAlive = #keepalive{tsec = TimeoutSec, tmsg = TimeoutMsg}) ->
    KeepAlive#keepalive{tref = timer(TimeoutSec, TimeoutMsg)}.

%% @doc Cancel Keepalive
-spec(cancel(keepalive()) -> ok).
cancel(#keepalive{tref = TRef}) ->
    cancel(TRef);
cancel(undefined) ->
    ok;
cancel(TRef) ->
        catch erlang:cancel_timer(TRef).

timer(Sec, Msg) ->
    erlang:send_after(timer:seconds(Sec), self(), Msg).

log(Format, Args) ->
    logger:debug(Format, Args).

clientid(_) ->
    cleintid_test.

stats(_) ->
    Stats = #proto_stats{enable_stats = true, recv_pkt = 3, recv_msg = 3,
        send_pkt = 2, send_msg = 2},
    tl(?record_to_proplist(proto_stats, Stats)).

set_client_stats(ClientId, Statlist) ->
    ets:insert(test_client_stats, {ClientId, [{'$ts', emqx_time:now_secs()}|Statlist]}).

print_table() ->
    List = ets:tab2list(test_client_stats),
    ?LOGT("The table ~p with the content is ~p~n", [ets:info(test_client_stats, name), List]).
