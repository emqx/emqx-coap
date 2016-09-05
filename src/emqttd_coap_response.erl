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

-module(emqttd_coap_response).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(gen_server).

-include("emqttd_coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-record(state, {uri, handler, ob_state, ob_seq, token, channel}).

%% API.
-export([get_responder/3]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

get_responder(Channel, Uri, Endpoint) ->
    case start_link(Channel, Uri, Endpoint) of
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, Other} -> {error, Other}
    end.

start_link(Channel, Uri, Endpoint) ->
    gen_server:start_link({local, name(Uri, Endpoint)}, ?MODULE, [Channel, Uri], []).

init([Channel, Uri]) ->
    erlang:monitor(process, Channel),
    case emqttd_coap_server:match_handler(Uri) of
       {ok, Handler} -> {ok, #state{uri = Uri, handler = Handler, ob_state = 0, ob_seq = 0, channel = Channel}};
       undefined     -> {stop, 'NotFound'}
    end.

handle_call(_Msg, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) -> 
    {noreply, State}.

handle_info({coap_req, Request}, State) ->
    call_handler(Request, State);

handle_info({dispatch, Topic, Msg}, State = #state{ob_state = 1}) ->
    io:format("Topic:~p , Msg:~p~n", [Topic, Msg]),
    observe_notify(Msg#mqtt_message.payload, State);

handle_info({notify, Msg}, State = #state{ob_state = 1}) -> 
    observe_notify(Msg, State);

handle_info({notify, Msg}, State = #state{ob_state = 0}) ->
    io:format("ob_state is closed, Msg:~p~n", [Msg]),
    {noreply, State, hibernate};

handle_info({'DOWN', _, _, _, _}, State = #state{ob_state = Observe, uri = Uri}) ->
    case Observe of
        1 -> emqttd_coap_observer:unobserve(Uri);
        _ -> ok
    end,
    {stop, normal, State};

handle_info(_Info, State) ->
    io:format("_Info Msg:~p~n", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% handle(Req = #coap_message{options=Options}, State) ->
%     Block1 = proplists:get_value('Block1', Options),
%     case gen_payload(Req, Block1, State) of
%         {error, Code} ->
%             return_response(Req, Code, State);
%         {Code, State2} ->
%             return_response(Req, Code, State2);
%         {ok, Payload, State2} ->
%             check_hanler(Req#coap_message{payload = Payload}, State2)
%     end.

% gen_payload(#coap_message{payload = Payload}, undefined, State) ->
%     {ok, Payload, State};

% gen_payload(#coap_message{payload = Payload}, {_Num, true, Size}, State) ->
%     case byte_size(Payload) of
%         Size -> {'Continue', State};
%         _Else -> {error, 'BadRequest'}
%     end;

% gen_payload(#coap_message{payload = Payload}, {_Num, false, _Size}, State) ->
%     {ok, <<Payload/binary>>, State}.

call_handler(Req, State = #state{handler = Handler}) ->
    case Handler:handle_request(Req) of
        {ok, Resp = #coap_response{}} -> check_cond(Req, Resp, State);
        {error, Code} -> return_response(Req, Code, State)
    end.

check_cond(Req, Resp, State) ->
    case if_match(Req, Resp) of
        true  -> handle_method(Req, Resp, State);
        false -> return_response(Req, 'PreconditionFailed', State)
    end. 

if_match(_Req, _Resp) ->
    true.

handle_method(Req = #coap_message{method = Method, options=Options}, Resp, State) when is_atom(Method) ->
    case proplists:get_value('Observe', Options) of
        0 -> call_observe(Req, State);
        1 -> call_unobserve(Req, State);
        undefined -> return_response(Req, Resp, State);
        _ -> return_response(Req, 'BadOption', State)
    end;

handle_method(Req, _Resp, State) ->
    return_response(Req, 'MethodNotAllowed', State).

call_observe(Req = #coap_message{options = Options}, State = #state{handler = Handler, ob_seq = ObSeq}) ->
    Uri = proplists:get_value('Uri-Path', Options, <<>>),
    case Handler:handle_observe(Req) of
        {error, Code} -> return_response(Req, Code, State);
        _Resp         -> 
            NextObSeq = next_ob_seq(ObSeq),
            ok = emqttd_coap_observer:observe(binary_to_list(Uri)),
            Resp = #coap_response{code = 'Content', payload = Req#coap_message.payload},
            return_response(Req, Resp, State, [{'Observe', NextObSeq}]),
            {noreply, State#state{ob_state = 1, token = Req#coap_message.token, ob_seq = NextObSeq}}
    end.

call_unobserve(Req = #coap_message{options = Options}, State = #state{handler = Handler}) ->
    Uri = proplists:get_value('Uri-Path', Options, <<>>),
    case Handler:handle_unobserve(Req) of
        {error, Code} -> return_response(Req, Code, State);
        _Resp         -> 
            ok = emqttd_coap_observer:unobserve(binary_to_list(Uri)),
            {noreply, State#state{ob_state = 0, token = undefined}}
    end.

observe_notify(Msg, State = #state{token = Token, ob_seq = ObSeq}) ->
    NextObSeq = next_ob_seq(ObSeq),
    Req = #coap_message{type = 'ACK', token = Token},
    Resp = #coap_response{code = 'Content', payload = Msg},
    return_response(Req, Resp, State, [{'Observe', NextObSeq}]),
    {noreply, State#state{ob_seq = NextObSeq}}.

return_response(Req, Code, State = #state{channel = Channel}) when is_atom(Code) ->
    Resp = #coap_message{type = Req#coap_message.type, code = Code, id = Req#coap_message.id},
    emqttd_coap_channel:send_response(Channel, Resp),
    {noreply, State};
return_response(Req, Resp, State) ->
    return_response(Req, Resp, State, []).

return_response(Req, Resp, State = #state{channel = Channel}, Options) ->
    Resp2 = #coap_message{
        type    = Req#coap_message.type,
        code    = Resp#coap_response.code, 
        id      = Req#coap_message.id, 
        token   = Req#coap_message.token,
        options = Options,
        payload = Resp#coap_response.payload},
    emqttd_coap_channel:send_response(Channel, Resp2),
    {noreply, State}.

next_ob_seq(ObSeq) when ObSeq =:= 65535 ->
    1;
next_ob_seq(ObSeq) ->
    ObSeq + 1.

name(Uri, Endpoint) ->
    list_to_atom(lists:concat([?MODULE, "_",emqttd_net:format(Endpoint), Uri])).