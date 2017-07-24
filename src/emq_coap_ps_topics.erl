%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-module(emq_coap_ps_topics).

-behaviour(gen_server).

-include("emq_coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

%% API.
-export([add_topic_info/3, add_topic_info/4, delete_topic_info/1, delete_sub_topics/1,
    is_topic_existed/1, is_topic_timeout/1, reset_topic_info/2, reset_topic_info/4,
    lookup_topic_info/1, lookup_topic_payload_ct/1, lookup_topic_payload/1, get_timer_left_seconds/1]).

-export([start/0, stop/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).

-define(LOG(Level, Format, Args),
    lager:Level("CoAP-PS-TOPICS: " ++ Format, Args)).

-define(COAP_TOPIC_TABLE, coap_topic).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
start() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop(Pid) ->
    gen_server:stop(Pid).

add_topic_info(Topic, MaxAge, CT) when is_binary(Topic), is_integer(MaxAge), is_binary(CT) ->
    add_topic_info(Topic, MaxAge, CT, <<>>).

add_topic_info(Topic, MaxAge, CT, Payload) when is_binary(Topic), is_integer(MaxAge), is_binary(CT), is_binary(Payload) ->
    gen_server:call(?MODULE, {add_topic, {Topic, MaxAge, CT, Payload}}).

delete_topic_info(Topic) when is_binary(Topic) ->
    gen_server:call(?MODULE, {remove_topic, Topic}).

delete_sub_topics(Topic) when is_binary(Topic) ->
    gen_server:cast(?MODULE, {remove_sub_topics, Topic}).

reset_topic_info(Topic, Payload) ->
    gen_server:call(?MODULE, {reset_topic, {Topic, Payload}}).

reset_topic_info(Topic, MaxAge, CT, Payload) ->
    gen_server:call(?MODULE, {reset_topic, {Topic, MaxAge, CT, Payload}}).

is_topic_existed(Topic) ->
    ets:member(?COAP_TOPIC_TABLE, Topic).

is_topic_timeout(Topic) when is_binary(Topic) ->
    timeout =:= ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 5).

lookup_topic_info(Topic) ->
    ets:lookup(?COAP_TOPIC_TABLE, Topic).

lookup_topic_payload_ct(Topic) ->
    ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 3).

lookup_topic_payload(Topic) ->
    case ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 4) of
        Payload ->
            Payload;
        badarg ->
            undefined
    end.

get_timer_left_seconds(Topic) ->
    PassedTime = trunc(timer:now_diff(erlang:now(), ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 5)) / 1000),
    TimerState= ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 2),
    emq_coap_timer:get_timer_length(TimerState) - PassedTime.

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([]) ->
    ets:new(?COAP_TOPIC_TABLE, [set, named_table, protected]),
    ?LOG(debug, "Create the coap_topic table", []),
    {ok, #state{}}.


handle_call({add_topic, {Topic, MaxAge, CT, Payload}}, _From, State) ->
    TimerState = emq_coap_timer:start_timer(MaxAge, {max_age_timeout, Topic}),
    Ret = create_table_element(Topic, TimerState, CT, Payload),
    {reply, {ok, Ret}, State, hibernate};

handle_call({reset_topic, {Topic, Payload}}, _From, State) ->
    NewTimerState = restart_max_age_timer(Topic),
    Ret = update_table_element(Topic, NewTimerState, Payload),
    {reply, {ok, Ret}, State, hibernate};

handle_call({reset_topic, {Topic, MaxAge, CT, Payload}}, _From, State) ->
    NewTimerState = restart_max_age_timer(Topic, MaxAge),
    Ret = update_table_element(Topic, NewTimerState, CT, Payload),
    {reply, {ok, Ret}, State, hibernate};

handle_call({remove_topic, {Topic, _Content}}, _From, State) ->
    ets:delete(?COAP_TOPIC_TABLE, Topic),
    ?LOG(debug, "Remove topic ~p in the coap_topic table", [Topic]),
    {reply, ok, State, hibernate};

handle_call(Request, _From, State) ->
    ?LOG(error, "adapter unexpected call ~p", [Request]),
    {reply, ignored, State, hibernate}.

handle_cast({remove_sub_topics, TopicPrefix}, State) ->
    DeletedTopicNum = ets:foldl(fun ({Topic, _, _, _, _}, AccIn) ->
                                    case binary:match(Topic, TopicPrefix) =/= nomatch of
                                        true  ->
                                            ?LOG(debug, "Remove topic ~p in the coap_topic table", [Topic]),
                                            ets:delete(?COAP_TOPIC_TABLE, Topic),
                                            AccIn + 1;
                                        false ->
                                            AccIn
                                    end
                                end, 0, ?COAP_TOPIC_TABLE),
    ?LOG(debug, "Remove number of ~p topics with prefix=~p in the coap_topic table", [DeletedTopicNum, TopicPrefix]),
    {noreply, State, hibernate};

handle_cast(Msg, State) ->
    ?LOG(error, "broker_api unexpected cast ~p", [Msg]),
    {noreply, State, hibernate}.

handle_info({max_age_timeout, Topic}, State) ->
    ?LOG(debug, "Max-Age timeout with topic ~p, delete the topic from coap_topic table", [Topic]),
    set_max_age_timeout(Topic),
    {noreply, State, hibernate};

handle_info(Info, State) ->
    ?LOG(error, "adapter unexpected info ~p", [Info]),
    {noreply, State, hibernate}.

terminate(Reason, #state{}) ->
    ets:delete(?COAP_TOPIC_TABLE),
    ?LOG(error, "the ~p terminate for reason ~p", [?MODULE, Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
create_table_element(Topic, TimerState, CT, <<>>) ->
    TopicInfo = {Topic, TimerState, CT, <<>>, undefined},
    ?LOG(debug, "Insert ~p in the coap_topic table", [TopicInfo]),
    ets:insert_new(?COAP_TOPIC_TABLE, TopicInfo);

create_table_element(Topic, TimerState, CT, Payload) ->
    TopicInfo = {Topic, TimerState, CT, Payload, erlang:now()},
    ?LOG(debug, "Insert ~p in the coap_topic table", [TopicInfo]),
    ets:insert_new(?COAP_TOPIC_TABLE, TopicInfo).

update_table_element(Topic, TimerState, Payload) ->
    ?LOG(debug, "Update the topic=~p info of TimerState=~p", [Topic, TimerState]),
    ets:update_element(?COAP_TOPIC_TABLE, Topic, [{2, TimerState}, {4, Payload}, {5, erlang:now()}]).

update_table_element(Topic, TimerState, CT, <<>>) ->
    ?LOG(debug, "Update the topic=~p info of TimerState=~p, CT=~p, payload=<<>>", [Topic, TimerState, CT]),
    ets:update_element(?COAP_TOPIC_TABLE, Topic, [{2, TimerState}, {3, CT}]);

update_table_element(Topic, TimerState, CT, Payload) ->
    ?LOG(debug, "Update the topic=~p info of TimerState=~p, CT=~p, payload=~p", [Topic, TimerState, CT, Payload]),
    ets:update_element(?COAP_TOPIC_TABLE, Topic, [{2, TimerState}, {3, CT}, {4, Payload}, {5, erlang:now()}]).

restart_max_age_timer(Topic) ->
    TimerState = ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 2),
    MaxAge = emq_coap_timer:get_timer_length(TimerState),
    ?LOG(debug, "Stored MaxAge=~p, will restart the timer", [MaxAge]),
    emq_coap_timer:cancel_timer(TimerState),
    emq_coap_timer:start_timer(MaxAge, {max_age_timeout, Topic}).

restart_max_age_timer(Topic, MaxAge) ->
    TimerState = ets:lookup_element(?COAP_TOPIC_TABLE, Topic, 2),
    emq_coap_timer:cancel_timer(TimerState),
    emq_coap_timer:start_timer(MaxAge, {max_age_timeout, Topic}).

set_max_age_timeout(Topic) ->
    ets:update_element(?COAP_TOPIC_TABLE, Topic, [{5, timeout}]).

