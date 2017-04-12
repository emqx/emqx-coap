%%--------------------------------------------------------------------
%% Copyright (c) 2016-2017 Feng Lee <feng@emqtt.io>. All Rights Reserved.
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

-module(emq_coap_response).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(gen_server).

-include("emq_coap.hrl").

-record(state, {uri, handler, ob_state, ob_seq, ob_token, channel, timer}).

%% API.
-export([get_responder/3]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------


get_responder(Channel, Uri, Endpoint) ->
    ?LOG(debug, "get_responder() Channel=~p, Uri=~p, Endpoint=~p", [Channel, Uri, Endpoint]),
    case emq_coap_server:match_handler(Uri) of
        {ok, Handler} ->
            case start_link(Channel, Uri, Endpoint, Handler) of
                {ok, Pid} -> {ok, Pid};
                {error, {already_started, Pid}} -> {ok, Pid};
                {error, Other} -> {error, Other}
            end;
        undefined  -> {error, 'NotFound'}
    end.

start_link(Channel, Uri, Endpoint, Handler) ->
    ?LOG(debug, "start response Channel=~p, Uri=~p, Endpoint=~p, Handler=~p", [Channel, Uri, Endpoint, Handler]),
    gen_server:start_link({via, emq_coap_registry, {Uri, Endpoint}}, ?MODULE, [Channel, Uri, Handler], []).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------


init([Channel, Uri, Handler]) ->
    erlang:monitor(process, Channel),
    Interval = application:get_env(?COAP_APP, keepalive, 3600),
    Timer = emq_coap_timer:start_timer(Interval, keepalive_timer),
    {ok, #state{uri = Uri, handler = Handler, ob_state = 0, ob_seq = 0,
        channel = Channel, timer = Timer}}.

handle_call(_Msg, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    noreply(State).

handle_info({coap_req, Request}, State=#state{timer = Timer}) ->
    NewTimer = emq_coap_timer:kick_timer(Timer),
    handle_method(Request, State#state{timer = NewTimer});

handle_info({dispatch, Topic, Msg}, State = #state{ob_state = 1}) ->
    ?LOG(debug, "dispatch Topic:~p , Msg:~p~n", [Topic, Msg]),
    call_handle_info(Topic, Msg, State);
handle_info({dispatch, Topic, Msg}, State = #state{ob_state = 0}) ->
    ?LOG(debug, "discard message from broker topic:~p, payload:~p~n", [Topic, Msg]),
    noreply(State);

handle_info({'DOWN', _, _, _, _}, State) ->
    {stop, normal, State};


handle_info(keepalive_timer, State=#state{timer = Timer}) ->
    case emq_coap_timer:is_timeout(Timer) of
        true ->
            ?LOG(debug, "emq_coap_channel keepalive_timer timeout", []),
            {stop, normal, State};
        false ->
            ?LOG(debug, "emq_coap_response restart keepalive_timer", []),
            NewTimer = emq_coap_timer:restart_timer(Timer),
            {noreply, State#state{timer = NewTimer}}
    end;

handle_info(Info, State) ->
    ?LOG(error, "Unknown Msg:~p~n", [Info]),
    noreply(State).

terminate(_Reason, #state{timer = Timer}) ->
    emq_coap_timer:cancel_timer(Timer),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------


if_match(#coap_message{options = Options}, #coap_response{etag = ETag}) ->
    case proplists:get_value('If-Match', Options, undefined) of
        undefined -> true;
        ETag1 -> ETag1 =:= ETag
    end;
if_match(#coap_message{options = Options}, _) ->
    not proplists:is_defined('If-Match', Options).

if_none_match(#coap_message{options = Options}, #coap_response{}) ->
    not proplists:is_defined('If-None-Match', Options);
if_none_match(#coap_message{}, _) ->
    true.

handle_method(Req = #coap_message{method = Method, options=Options}, State) when is_atom(Method) ->
    case proplists:get_value('Observe', Options) of
        0 ->            call_observe(Req, State);
        1 ->            call_unobserve(Req, State);
        undefined ->   call_handler(Req, State);
        _ ->             noreply( return_response(Req, 'BadOption', State) )
    end;

handle_method(Req, State) ->
    noreply( return_response(Req, 'MethodNotAllowed', State) ).

call_handler(Req, State = #state{handler = Handler}) ->
    ?LOG(debug, "call_handler() Req=~p, Handler=~p", [Req, Handler]),
    case Handler:handle_request(Req) of
        {ok, Resp}    -> 
            case if_match(Req, Resp) and if_none_match(Req, Resp) of
                true  -> noreply( return_response(Req, Resp, State) );
                false -> noreply( return_response(Req, 'PreconditionFailed', State) )
            end;
        {notsupport} -> return_reset(Req, State);
        {error, Code} -> noreply( return_response(Req, Code, State) )
    end.

call_observe(Req = #coap_message{options = _Options},
             State = #state{handler = Handler, ob_seq = ObSeq, ob_state = 0})->
    case Handler:handle_observe(Req) of
        {error, Code} -> noreply( return_response(Req, Code, State) );
        {ok, _Resp}    -> 
            NextObSeq = next_ob_seq(ObSeq),
            Resp = #coap_response{code = 'Content', payload = Req#coap_message.payload},
            NewState = return_response(Req, Resp, State, [{'Observe', NextObSeq}]),
            noreply( NewState#state{ob_state = 1, ob_token = Req#coap_message.token, ob_seq = NextObSeq} )
    end;

call_observe(Req, State = #state{ob_state = 1})->
    % already in observation state, no 2nd observe is allowed
    ?LOG(warning, "discard second observe request", []),
    noreply( return_response(Req, 'BadRequest', State) ).


call_unobserve(Req, State = #state{handler = Handler, ob_state = 1, ob_seq = ObSeq}) ->
    ?LOG(debug, "call_unobserve() Req=~p, Handler=~p", [Req, Handler]),
    case Handler:handle_unobserve(Req) of
        {error, Code} -> noreply( return_response(Req, Code, State) );
        {ok, _Resp}   ->
            NextObSeq = next_ob_seq(ObSeq),
            Resp = #coap_response{code = 'Content'},
            NewState = return_response(Req, Resp, State, [{'Observe', NextObSeq}]),
            noreply( NewState#state{ob_state = 0, ob_token = undefined} )
    end;

call_unobserve(Req, State = #state{ob_state = 0}) ->
    ?LOG(warning, "discard unobserve request since observe is not set", []),
    noreply( return_response(Req, 'BadRequest', State) ).

call_handle_info(Topic, Msg, State = #state{handler = Handler}) ->
    case Handler:handle_info(Topic, Msg) of
        ok         -> noreply(State);
        {ok, Resp} -> observe_notify(Resp, State)
    end.

observe_notify(Msg, State = #state{ob_state = 0}) ->
    ?LOG(info, "discard notification since observation is not set, ~p", [Msg]),
    noreply(State);

observe_notify(Resp =  #coap_response{}, State = #state{ob_token = Token, ob_seq = ObSeq}) ->
    NextObSeq = next_ob_seq(ObSeq),
    Req = #coap_message{type = 'CON', token = Token},
    Resp2 = Resp#coap_response{code = 'Content'},
    NewState = return_response(Req, Resp2, State, [{'Observe', NextObSeq}]),
    noreply(NewState#state{ob_seq = NextObSeq});

observe_notify(Msg, State = #state{ob_token = Token, ob_seq = ObSeq}) ->
    NextObSeq = next_ob_seq(ObSeq),
    Req = #coap_message{type = 'CON', token = Token},
    Resp = #coap_response{code = 'Content', payload = Msg},
    NewState = return_response(Req, Resp, State, [{'Observe', NextObSeq}]),
    noreply(NewState#state{ob_seq = NextObSeq}).

return_reset(Req, State = #state{channel = Channel}) ->
    Resp = #coap_message{type = 'RST', code = 0, id = Req#coap_message.id},
    emq_coap_channel:send_response(Channel, Resp),
    noreply(State).

return_response(Req, Code, State = #state{channel = Channel}) when is_atom(Code) ->
    Resp = #coap_message{type = Req#coap_message.type, code = Code, id = Req#coap_message.id},
    emq_coap_channel:send_response(Channel, Resp),
    State;
return_response(Req, Resp, State) ->
    return_response(Req, Resp, State, []).

return_response(Req = #coap_message{options = Options}, 
                Resp = #coap_response{etag = ETag}, 
                State = #state{channel = Channel}, OptionsList) ->
    Resp2 = case lists:member(ETag, proplists:get_value(etag, Options, [])) of
        true ->
            #coap_message{code = 'Valid', options = [{'ETag', ETag} | OptionsList]};
        false ->
            #coap_message{code = Resp#coap_response.code, options = OptionsList}
    end,
    Resp3 = Resp2#coap_message{
                type    = Req#coap_message.type,
                id      = Req#coap_message.id, 
                token   = Req#coap_message.token,
                payload = Resp#coap_response.payload},
    ?LOG(debug, "return_response Resp=~p", [Resp3]),
    emq_coap_channel:send_response(Channel, Resp3),
    State.

next_ob_seq(16#FFFFFF) ->
    0;
next_ob_seq(ObSeq) ->
    ObSeq + 1.

noreply(State) ->
    {noreply, State}.


