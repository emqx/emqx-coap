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

-module(emq_coap_timer).

-author("Feng Lee <feng@emqtt.io>").

-include("emq_coap.hrl").

-export([cancel_timer/1, start_timer/2, restart_timer/3]).


cancel_timer(TRef) when is_reference(TRef) ->
    catch erlang:cancel_timer(TRef),
    ok;
cancel_timer(_) ->
    ok.

start_timer(Sec, Msg) ->
    erlang:send_after(timer:seconds(Sec), self(), Msg).

restart_timer(TRef, Interval, Msg) ->
    cancel_timer(TRef),
    start_timer(Interval, Msg).

