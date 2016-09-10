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

%% CON: Confirmable, NON: Non-confirmable, ACK: Acknowledgement, RST: Rest
-type(coap_type() :: 'CON' | 'NON' | 'ACK' | 'RST').

-type(coap_method() :: 'GET' | 'POST' | 'PUT' | 'DELETE').

-type(coap_endpoint() :: {inet:ip_address(), inet:port()}).

-type(coap_code() :: {0..5, non_neg_integer()}).

-record(coap_message, {type, method, code, id, token = <<>>,
                       options = [], payload = <<>>}).

-type(coap_message() :: #coap_message{}).

-record(coap_request, {method, path :: binary(), query = [], payload = <<>>}).

-type(coap_request() :: #coap_request{}).

-record(coap_response, {code, payload = <<>>, etag = <<>>}).

-type(coap_response() :: #coap_response{}).

-type(coap_option() :: 'If-Match'
                     | 'Uri-Host'
                     | 'ETag'
                     | 'If-None-Match'
                     | 'Uri-Port'
                     | 'Location-Path'
                     | 'Uri-Path'
                     | 'Content-Format'
                     | 'Max-Age'
                     | 'Uri-Query'
                     | 'Accept'
                     | 'Location-Query'
                     | 'Proxy-Uri'
                     | 'Proxy-Scheme'
                     | 'Size1').
