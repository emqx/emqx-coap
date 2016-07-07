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

-module(emqtt_coap).

-author("Feng Lee <feng@emqtt.io>").

-include("emqtt_coap.hrl").

-export([type_name/1, type_enum/1, method_name/1, method_code/1]).

-spec(type_name(integer()) -> coap_type()).
type_name(0) -> 'CON';
type_name(1) -> 'NON';
type_name(2) -> 'ACK';
type_name(3) -> 'RST'.

-spec(type_enum(coap_type()) -> integer()).
type_enum('CON') -> 0;
type_enum('NON') -> 1;
type_enum('ACK') -> 2;
type_enum('RST') -> 3.

-spec(method_name({pos_integer(), pos_integer()}) -> coap_method()).
method_name({0, 01}) -> 'GET';
method_name({0, 02}) -> 'POST';
method_name({0, 03}) -> 'PUT';
method_name({0, 04}) -> 'DELETE';
method_name({_, _})  -> undefined.

-spec(method_code(coap_method()) -> {pos_integer(), pos_integer()}).
method_code('GET')    -> {0, 01}; 
method_code('POST')   -> {0, 02};
method_code('PUT')    -> {0, 03};
method_code('DELETE') -> {0, 04}.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

type_test() ->
    ?assertEqual(1, type_value(type_name(1))),
    ?assertEqual(2, type_value(type_name(2))),
    ?assertEqual(3, type_value(type_name(3))),
    ?assertEqual(4, type_value(type_name(4))).

method_test() ->
    ?assertEqual('GET', method_name(method_code('GET'))),
    ?assertEqual('POST', method_name(method_code('POST'))),
    ?assertEqual('PUT', method_name(method_code('PUT'))),
    ?assertEqual('DELETE', method_name(method_code('DELETE'))).

-endif.

