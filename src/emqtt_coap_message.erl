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
%% |   Token (if any, TKL bytes) ...                               |
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |   Options (if any) ...                                        |
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%% |1 1 1 1 1 1 1 1|    Payload (if any) ...                       |
%% +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%%
%% @end

-module(emqtt_coap_message).

-author("Feng Lee <feng@emqtt.io>").

-include("emqtt_coap.hrl").

-export([parse/1, serialize/1]).

-define(VERSION, 2#01).

-record(opt_state, {last_number = 0, delta = 0, options = []}).

-spec(parse(binary()) -> coap_message()).
parse(<<?VERSION:2, T:2, TKL:4, C:8, Id:16/big-integer, Token:TKL/bytes, Bin/binary>>) ->
    if_empty(C, Token, Bin),
    {Options, Payload} = parse_option(Bin, #opt_state{}),
    #coap_message{type = type_name(T), code = parse_code(C),
                  id = Id, token = Token, options = Options,
                  payload = Payload}.

if_empty(0, Token, Bin) when size(Token) > 0; size(Bin) > 0 ->
    error(format_error);
if_empty(0, _, _) ->
    ok.

type_name(0) -> 'CON';
type_name(1) -> 'NON';
type_name(2) -> 'ACK';
type_name(3) -> 'RST'.

parse_code(<<Class:3, Detail:5>>) ->
    Class * 100 + Detail.

parse_option(<<>>, #opt_state{options = Options}) ->
    {lists:reverse(Options), <<>>};
parse_option(<<16#FF, Payload/binary>>, #opt_state{options = Options}) ->
    {lists:reverse(Options), Payload};
parse_option(<<Delta:4, OptLen:4, Bin/binary>>, State) when Delta =< 12 ->
    parse_value({OptLen, Bin}, State#opt_state{delta = Delta});
parse_option(<<13:4, OptLen:4, Delta:8, Bin/binary>>, State) ->
    parse_value({OptLen, Bin}, State#opt_state{delta = Delta - 13});
parse_option(<<14:4, OptLen:4, Delta:16/big-integer, Bin/binary>>, State) ->
    parse_value({OptLen, Bin}, State#opt_state{delta = Delta - 269}).

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

add_option(OptVal, #opt_state{last_number = Number, delta = Delta, options = Options}) ->
    OptNum = Number + Delta, Option = {OptNum, OptVal},
    #opt_state{last_number = OptNum, delta = 0, options = [Option | Options]}.

serialize(#coap_message{type = Type, method = _Method, code = Code, id = MsgId,
                        token = Token, options = Options, payload = Payload}) ->
    Header = <<?VERSION:2, (type_value(Type)):2, (size(Token)):4,
               (serialize_code(Code)):8, MsgId:16, Token/binary>>,
    [Header, serialize_option(Options, []), 16#FF, Payload].

type_value('CON') -> 0;
type_value('NON') -> 1;
type_value('ACK') -> 2;
type_value('RST') -> 3.

serialize_code(Code) ->
    (Code div 100) bsl 5 + (Code rem 100).

serialize_option([], Acc) ->
    lists:reverse(Acc).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-endif.

