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

%% @doc CoAP Message Format
%%
%%  0                   1                   2                   3
%%  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |Ver| T |  TKL  |      Code     |          Message ID           |
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |   Token (if any, TKL bytes) ...
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |   Options (if any) ...
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |1 1 1 1 1 1 1 1|    Payload (if any) ...
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%%
%% @end

-module(emqtt_coap_message).

-author("Feng Lee <feng@emqtt.io>").

-include("emqtt_coap.hrl").

-export([parse/1, serialize/1]).

-define(VERSION, 2#01).

-record(state, {number = 0, delta = 0, options = []}).

-spec(parse(binary()) -> coap_message()).
parse(<<?VERSION:2, Type:2, TKL:4, Code:8, MsgId:16/big-integer, Token:TKL/bytes, Bin/binary>>) ->
    {Options, Payload} = parse_option(Bin, #state{}),
    #coap_message{type = Type, code = Code, id = MsgId, token = Token,
                  options = Options, payload = Payload}.

parse_option(<<>>, #state{options = Options}) ->
    {lists:reverse(Options), <<>>};
parse_option(<<16#FF, Payload/binary>>, #state{options = Options}) ->
    {lists:reverse(Options), Payload};
parse_option(<<Delta:4, OptLen:4, Bin/binary>>, State) when Delta =< 12 ->
    parse_value({OptLen, Bin}, State#state{delta = Delta});
parse_option(<<13:4, OptLen:4, Delta:8, Bin/binary>>, State) ->
    parse_value({OptLen, Bin}, State#state{delta = Delta - 13});
parse_option(<<14:4, OptLen:4, Delta:16/big-integer, Bin/binary>>, State) ->
    parse_value({OptLen, Bin}, State#state{delta = Delta - 269}).

parse_value({OptLen, Bin}, State) when OptLen =< 12 ->
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option(Left, add_option(OptVal, State));

parse_value({13, <<Len:8, Bin/binary>>}, State) ->
    OptLen = Len - 13,
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option(Left, add_option(OptVal, State));

parse_value({14, <<Len:16/big-integer, Bin/binary>>}, State) ->
    OptLen = Len - 269,
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option(Left, add_option(OptVal, State)).

add_option(OptVal, #state{number = Number, delta = Delta, options = Options}) ->
    OptNum = Number + Delta, Option = {OptNum, OptVal},
    #state{number = OptNum, delta = 0, options = [Option | Options]}.

serialize(#coap_message{type = Type, method = _Method, code = Code, id = MsgId,
                        token = Token, options = Options, payload = Payload}) ->
    Header = <<?VERSION:2, Type:2, (size(Token)):4, Code:8, MsgId:16, Token/binary>>,
    [Header, serialize_option(Options, []), 16#FF, Payload].

serialize_option([], Acc) ->
    lists:reverse(Acc).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-endif.

