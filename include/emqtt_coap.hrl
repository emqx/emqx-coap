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

%% CON: Confirmable
%% NON: Non-confirmable
%% ACK: Acknowledgement
%% RST: Rest
-type(coap_type() :: 'CON' | 'NON' | 'ACK' | 'RST').

-type(coap_method() :: 'GET' | 'POST' | 'PUT' | 'DELETE').

-type(coap_option() :: 'Etag' | ).

-record(coap_message, {type, method, code, id, token = <<>>, options = [], payload = <<>>}).

-type(coap_message() :: #coap_message{}).

%% Get response: 2.05(Content), 2.03(Valid),
%% Post response: 2.01(Created), 2.04(Changed), 2.02(Deleted)
%% Put: 2.04(Changed), 2.01(Created)
%% Delete: 2.02(Deleted)
%%

%%--------------------------------------------------------------------
%% Response Code
%%--------------------------------------------------------------------

%% Success 2.xx (5.9.1)
-define(RC_CREATED, {2, 01}).
-define(RC_DELETED, {2, 02}).
-define(RC_VALID,   {2, 03}).
-define(RC_CHANGED, {2, 04}).
-define(RC_CONTENT, {2, 05}).

%% Client Error 4.xx (5.9.2)
-define(RC_BAD_REQUEST,  {4, 00}).
-define(RC_UNAUTHORIZED, {4, 01}).

%%   4.02 Bad Option
%%   4.03 Fobidden
%%   4.04 Not Found
%%   4.05 Method Not Allowed
%%   4.06 Not Acceptable
%%   4.12 Precondition Failed
%%   4.13 Request Entity Too Large
%%   4.15 Unsupported Content-format

%% Server Error 5.xx
%%   5.00 Internal Server Erro34 BVD
%%   5.01 Not Implemented
%%   5.02 Bad Gateway
%%   5.03 Service Unavailable
%%   5.04 Gateway Timeout
%%   5.05 Proxying Not Supported


