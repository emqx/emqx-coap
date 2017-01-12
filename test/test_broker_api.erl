%%--------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
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

-module(test_broker_api).

-compile(export_all).

-behaviour(gen_server).

-record(state, {subscriber}).

-include_lib("emqttd/include/emqttd.hrl").


publish(ClientId, Topic, Payload) ->
    gen_server:call(?MODULE, {publish, {ClientId, Topic, Payload}}).

get_published_msg() ->
    gen_server:call(?MODULE, get_published_msg).

subscribe(Topic) ->
    gen_server:call(?MODULE, {subscribe, Topic, self()}).

get_subscrbied_topic() ->
    gen_server:call(?MODULE, get_subscribed_topic).

unsubscribe(Topic) ->
    gen_server:call(?MODULE, {unsubscribe, Topic}).

get_unsubscrbied_topic() ->
    gen_server:call(?MODULE, get_unsubscribed_topic).

dispatch(Topic, Msg) ->
    gen_server:call(?MODULE, {dispatch, {Topic, Msg}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

init(_Param) ->
    {ok, #state{subscriber = undefined}}.


handle_call({publish, Msg}, _From, State) ->
    io:format("test api publish ~p~n", [Msg]),
    put(unittest_message, Msg),
    {reply, ok, State};

handle_call(get_published_msg, _From, State) ->
    Response = get(unittest_message),
    io:format("test api get published msg=~p~n", [Response]),
    {reply, Response, State};

handle_call({subscribe, Topic, Proc}, _From, State) ->
    io:format("test api subscribe Topic=~p~n", [Topic]),
    put(unittest_subscribe, Topic),
    {reply, ok, State#state{subscriber = Proc}};

handle_call(get_subscribed_topic, _From, State) ->
    Response = get(unittest_subscribe),
    io:format("test api get subscribed topic=~p~n", [Response]),
    {reply, Response, State};

handle_call({unsubscribe, Topic}, _From, State) ->
    io:format("test api subscribe Topic=~p~n", [Topic]),
    put(unittest_unsubscribe, Topic),
    {reply, ok, State#state{subscriber = undefined}};

handle_call(get_unsubscribed_topic, _From, State) ->
    Response = get(unittest_unsubscribe),
    io:format("test api get unsubscribed topic=~p~n", [Response]),
    {reply, Response, State};

handle_call({dispatch, {Topic, Msg}}, _From, State=#state{subscriber = undefined}) ->
    io:format("test api NOT dispatch topic=~p, Msg=~p~n", [Topic, Msg]),
    {reply, ok, State};

handle_call({dispatch, {Topic, Msg}}, _From, State=#state{subscriber = SubProc}) ->
    SubProc ! {dispatch, Topic, #mqtt_message{payload=Msg}},
    io:format("test api dispatch topic=~p, Msg=~p~n", [Topic, Msg]),
    {reply, ok, State};

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(Req, _From, State) ->
    io:format("test_modbus_server: ignore call Req=~p~n", [Req]),
    {reply, {error, badreq}, State}.


handle_cast(Msg, State) ->
    io:format("test_modbus_server: ignore cast msg=~p~n", [Msg]),
    {noreply, State}.

handle_info(Info, State) ->
    io:format("test_modbus_server: ignore info=~p~n", [Info]),
    {noreply, State}.

terminate(Reason, _State) ->
    io:format("test_modbus_server: terminate Reason=~p~n", [Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
