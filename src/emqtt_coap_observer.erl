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

-module(emqtt_coap_observer).

-author("Feng Lee <feng@emqtt.io>").

%% API.
-export([start_link/0, observe/1, notify/2, unobserve/1, stop/0]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).

%%--------------------------------------------------------------------
%% API.
%%--------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

observe(Uri) ->
    gen_server:call(?MODULE, {observe, Uri, self()}).

notify(Uri, Msg) ->
    case pg2:get_members(subject(Uri)) of
        {error, _} -> ok;
        Observers  -> [Pid ! {notify, Msg} || Pid <- Observers]
    end.

unobserve(Uri) ->
    gen_server:call(?MODULE, {unobserve, Uri, self()}).

stop() ->
    gen_server:call(?MODULE, stop).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([]) ->
    {ok, #state{}}.

handle_call({observe, Uri, Pid}, _From, State) ->
    Subject = subject(Uri),
    pg2:create(Subject ),
    {reply, pg2:join(Subject, Pid), State};

handle_call({unobserve, Uri, Pid}, _From, State) ->
    Subject = subject(Uri),
    pg2:leave(Subject, Pid),
    io:format("Unobserve ~p ~p~n", [Subject, Pid]),
    case pg2:get_members(Subject) of
        [] -> pg2:delete(Subject);
        _  -> ok
    end,
    {reply, ok, State};

handle_call(stop, _From, State) ->
	{stop, normal, ok, State};

handle_call(_Request, _From, State) ->
	{reply, ignored, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

subject(Uri) -> {coap, observer, Uri}.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

observer_test() ->
    {ok, _Pid} = start_link(),
    Uri = <<"a/b/c">>,
    observe(Uri),
    notify(Uri, hello),
    ?assertEqual(ok, receive {notify, hello} -> ok after 3 -> timeout end),
    unobserve(Uri),
    ?assertMatch({error, {no_such_group, _}}, pg2:get_members(topic(Uri))),
    stop().
    
-endif.

