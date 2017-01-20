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

-module(emq_coap_broker_api).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqttd/include/emqttd.hrl").

%% modbus API Exports
-export([subscribe/1, unsubscribe/1, publish/3]).

-ifdef(TEST).

subscribe(Topic) ->
    test_broker_api:subscribe(Topic).

unsubscribe(Topic) ->
    test_broker_api:unsubscribe(Topic).

publish(ClientId, Topic, Payload) ->
    test_broker_api:publish(ClientId, Topic, Payload).

-else.

subscribe(Topic) ->
    emqttd:subscribe(Topic).

unsubscribe(Topic) ->
    emqttd:unsubscribe(Topic).

publish(ClientId, Topic, Payload) ->
    Msg = emqttd_message:make(ClientId, 0, Topic, Payload),
    emqttd:publish(Msg#mqtt_message{retain  = 0}).

-endif.









