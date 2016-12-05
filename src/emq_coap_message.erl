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

-module(emq_coap_message).

-author("Feng Lee <feng@emqtt.io>").

-include("emq_coap.hrl").

-import(emq_coap_iana, [type_name/1, type_enum/1, method_name/1, resp_method_name/1, resp_method_code/1]).

-export([parse/1, serialize/1, format/1, get_option/2, get_last_path/1]).

-define(V, 2#01).

%%--------------------------------------------------------------------
%% Parse CoAP Message
%%--------------------------------------------------------------------

-spec(parse(binary()) -> coap_message()).
parse(<<?V:2, T:2, 0:4, 0:8, Id:16/big-integer>>) -> %% empty message
    #coap_message{type = type_name(T), code = {0, 0}, id = Id};

parse(<<?V:2, _T:2, 0:4, 0:8, _/binary>>) -> %% format error
    error(format_error);

parse(<<?V:2, T:2, TKL:4, C:3, Dd:5, Id:16/big-integer, Token:TKL/bytes, Bin/binary>>) ->
    {Options, Payload} = parse_option_list(Bin, 0, []),
    #coap_message{type = type_name(T), method = method_name({C, Dd}),
                  code = {C, Dd}, id = Id, token = Token,
                  options = Options, payload = Payload}.

parse_option_list(<<>>, _, Options) ->
    {lists:reverse(Options), <<>>};
parse_option_list(<<16#FF, Payload/binary>>, _, Options) ->
    {lists:reverse(Options), Payload};
parse_option_list(<<Delta:4, OptLen:4, Bin/binary>>, OptNum, Options) when Delta =< 12 ->
    parse_option({OptLen, Bin}, OptNum + Delta, Options);
parse_option_list(<<13:4, OptLen:4, Delta:8, Bin/binary>>, OptNum, Options) ->
    parse_option({OptLen, Bin}, OptNum + Delta + 13, Options);
parse_option_list(<<14:4, OptLen:4, Delta:16/big-integer, Bin/binary>>, OptNum, Options) ->
    parse_option({OptLen, Bin}, OptNum + Delta + 269, Options).

parse_option({OptLen, Bin}, OptNum, Options) when OptLen =< 12 ->
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option_list(Left, OptNum, add_option(OptNum, OptVal, Options));
parse_option({13, <<Len:8, Bin/binary>>}, OptNum, Options) ->
    OptLen = Len + 13,
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option_list(Left, OptNum, add_option(OptNum, OptVal, Options));
parse_option({14, <<Len:16/big-integer, Bin/binary>>}, OptNum, Options) ->
    OptLen = Len + 269,
    <<OptVal:OptLen/binary, Left/binary>> = Bin,
    parse_option(Left, OptNum, add_option(OptNum, OptVal, Options)).

add_option(OptNum, OptVal, Options) ->
    [decode_option({OptNum, OptVal}) | Options].

decode_option({1, Val})   -> {'If-Match', Val};
decode_option({3, Host})   -> {'Uri-Host', Host};
decode_option({4, Etag})   -> {'ETag', Etag};
decode_option({5, <<>>})   -> {'If-None-Match', true};
decode_option({6, Val})    -> {'Observe', binary:decode_unsigned(Val)};
decode_option({7, Port})   -> {'Uri-Port', binary:decode_unsigned(Port)};
decode_option({8, Path})   -> {'Location-Path', Path};
decode_option({11, Path})  -> {'Uri-Path', Path};
decode_option({12, Val})   -> {'Content-Format', decode_content_format(binary:decode_unsigned(Val))};
decode_option({14, Age})   -> {'Max-Age', binary:decode_unsigned(Age)};
decode_option({15, Query}) -> {'Uri-Query', Query};
decode_option({17, Accept})-> {'Accept', binary:decode_unsigned(Accept)};
decode_option({20, Query}) -> {'Location-Query', Query};
decode_option({35, Uri})   -> {'Proxy-Uri', Uri};
decode_option({39, Scheme})-> {'Proxy-Scheme', Scheme};
decode_option({60, Size})  -> {'Size1', binary:decode_unsigned(Size)};
decode_option({Num, Val})  -> {Num, Val}.

decode_content_format(0)  -> <<"text/plain">>;
decode_content_format(40) -> <<"application/link-format">>;
decode_content_format(41) -> <<"application/xml">>;
decode_content_format(42) -> <<"application/octet-stream">>;
decode_content_format(47) -> <<"application/exi">>;
decode_content_format(50) -> <<"application/json">>;
decode_content_format(60) -> <<"application/cbor">>;
decode_content_format(I)  -> I.

%%--------------------------------------------------------------------
%% Serialize CoAP Message
%%--------------------------------------------------------------------

serialize(#coap_message{type = T, code = 0, id = Id}) -> %% empty messag
    <<?V:2, (type_enum(T)):2, 0:4, 0:8, Id:16>>;

serialize(#coap_message{type = Type, code = Code, id = MsgId, token = Token,
                        options = Options, payload = Payload}) ->
    {C, Dd} = resp_method_code(Code),
    Header = <<?V:2, (type_enum(Type)):2, (size(Token)):4, C:3, Dd:5, MsgId:16, Token/binary>>,
    EncodedOptions = lists:sort([encode_option(Option) || Option <- Options]),
    OptBin = serialize_option_list(EncodedOptions),
    PayloadMarker = payload_marker(Payload),
    <<Header/binary, OptBin/binary, PayloadMarker/binary>>.

payload_marker(<<>>) -> <<>>;
payload_marker(Payload) when is_list(Payload) ->
    Payload_Bin = list_to_binary(Payload),
    <<16#FF:8, Payload_Bin/binary>>;
payload_marker(Payload) -> <<16#FF:8, Payload/binary>>.

serialize_option_list(Options) ->
    {_Number, Bin_list} = lists:foldr(fun({OptNum, OptVal}, {LastNum, Acc}) ->
                                          Bin = serialize_option(OptNum, OptVal, LastNum),
                                          {OptNum, [Bin | Acc]}
                                      end, {0, []}, Options),
    list_to_binary(lists:reverse(Bin_list)).

serialize_option(OptNum, OptVal, LastNum) ->
    Delta = OptNum - LastNum, Len = byte_size(OptVal),
    <<(encode_delta(Delta)):4, (encode_optlen(Len)):4,
      (encode_extended(Delta))/bytes, (encode_extended(Len))/bytes,
      OptVal/binary>>.

encode_option({'If-Match', Val})         -> {1, Val};
encode_option({'Uri-Host', Host})        -> {3, Host};
encode_option({'ETag', Etag})            -> {4, Etag};
encode_option({'If-None-Match', true})   -> {5, <<>>};
encode_option({'Observe', Val})          -> {6, binary:encode_unsigned(Val)};
encode_option({'Uri-Port', Port})        -> {7, binary:encode_unsigned(Port)};
encode_option({'Location-Path', Path})   -> {8, Path};
encode_option({'Uri-Path', Path})        -> {11, Path};
encode_option({'Content-Format', Val})   -> {12, binary:encode_unsigned(encode_content_format(Val))};
encode_option({'Max-Age', Age})          -> {14, binary:encode_unsigned(Age)};
encode_option({'Uri-Query', Query})      -> {15, Query};
encode_option({'Accept', Val})           -> {17, binary:encode_unsigned(Val)};
encode_option({'Location-Query', Query}) -> {20, Query};
encode_option({'Proxy-Uri', Uri})        -> {35, Uri};
encode_option({'Proxy-Scheme', Scheme})  -> {39, Scheme};
encode_option({'Size1', Size})           -> {60, binary:encode_unsigned(Size)};
encode_option({Num, Val})                -> {Num, Val}.

encode_content_format(<<"text/plain">>)              -> 0;
encode_content_format(<<"application/link-format">>) -> 40;
encode_content_format(<<"application/xml">>)         -> 41;
encode_content_format(<<"application/octet-stream">>)-> 42;
encode_content_format(<<"application/exi">>)         -> 47;
encode_content_format(<<"application/json">>)        -> 50;
encode_content_format(<<"application/cbor">>)        -> 60;
encode_content_format(I) when is_integer(I)          -> I.

encode_delta(Delta) when Delta >= 269 -> 14;
encode_delta(Delta) when Delta >= 13  -> 13;
encode_delta(Delta) -> Delta.

encode_optlen(Len) when Len >= 269 -> 14;
encode_optlen(Len) when Len >= 13  -> 13;
encode_optlen(Len) -> Len.

encode_extended(Delta) when Delta >= 269 -> <<(Delta - 269):16>>;
encode_extended(Delta) when Delta >= 13  -> <<(Delta - 13):8>>;
encode_extended(_Delta)                  -> <<>>.

format(Msg = #coap_message{}) -> Msg. %% TODO:

get_option(#coap_message{options = Opts}, OptName) ->
    [V || {OptionName, V} <- Opts, OptionName =:= OptName].

get_last_path(Req) ->
    UriList = get_option(Req, 'Uri-Path'),
    case length(UriList) of
        0 -> [];
        _ -> lists:last(UriList)
    end.


-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

parse_test() ->
    Msg = parse(<<?V:2, 0:2, 0:4, 1:8, 22096:16>>),
    serialize(Msg),
    ?assertEqual(22096, Msg#coap_message.id).

-endif.

