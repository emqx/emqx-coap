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

-module(emqttd_coap_server).

-author("Feng Lee <feng@emqtt.io>").

-include("emqttd_coap.hrl").

-behaviour(gen_server).

%% API.
-export([start_link/0, register_handler/2, match_handler/1, unregister_handler/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).

-define(HANDLER_TAB, coap_handler).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec(register_handler(list(binary()), module()) -> ok | {error, duplicated}).
register_handler(Prefix, Handler) ->
    gen_server:call(?MODULE, {register, Prefix, Handler}).

-spec(match_handler(list(binary())) -> {ok, module()} | undefined).
match_handler(Uri) -> match_handler(Uri, ets:tab2list(?HANDLER_TAB)).

match_handler(_Uri, []) ->
    undefined;
match_handler(Uri, [{Prefix, Handler} | T]) ->
    case match_prefix(Prefix, Uri) of
        true  -> {ok, Handler};
        false -> match_handler(Uri, T)
    end.

match_prefix([], []) ->
    true;
match_prefix([], _) ->
    true;
match_prefix([H|T1], [H|T2]) ->
    match_prefix(T1, T2);
match_prefix(_Prefix, _Uri) ->
    false.

-spec(unregister_handler(list(binary())) -> ok).
unregister_handler(Prefix) ->
    gen_server:call(?MODULE, {unregister, Prefix}).

init([]) ->
    ets:new(?HANDLER_TAB, [set, named_table, protected]),
    {ok, #state{}}.

handle_call({register, Prefix, Handler}, _From, State) ->
    case ets:member(?HANDLER_TAB, Prefix) of
        true  -> {reply, {error, duplicated}, State};
        false -> ets:insert(?HANDLER_TAB, {Prefix, Handler}),
                 {reply, ok, State}
    end;

handle_call({unregister, Prefix}, _From, State) ->
    ets:delete(?HANDLER_TAB, Prefix),
	{reply, ok, State};

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

