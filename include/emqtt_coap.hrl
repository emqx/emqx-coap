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

% +------+--------+-----------+
% | Code | Name   | Reference |
% +------+--------+-----------+
% | 0.01 | GET    | [RFC7252] |
% | 0.02 | POST   | [RFC7252] |
% | 0.03 | PUT    | [RFC7252] |
% | 0.04 | DELETE | [RFC7252] |
% +------+--------+-----------+

-type(coap_method() :: 'GET' | 'POST' | 'PUT' | 'DELETE').

% +--------+------------------+-----------+
% | Number | Name             | Reference |
% +--------+------------------+-----------+
% |      0 | (Reserved)       | [RFC7252] |
% |      1 | If-Match         | [RFC7252] |
% |      3 | Uri-Host         | [RFC7252] |
% |      4 | ETag             | [RFC7252] |
% |      5 | If-None-Match    | [RFC7252] |
% |      7 | Uri-Port         | [RFC7252] |
% |      8 | Location-Path    | [RFC7252] |
% |     11 | Uri-Path         | [RFC7252] |
% |     12 | Content-Format   | [RFC7252] |
% |     14 | Max-Age          | [RFC7252] |
% |     15 | Uri-Query        | [RFC7252] |
% |     17 | Accept           | [RFC7252] |
% |     20 | Location-Query   | [RFC7252] |
% |     35 | Proxy-Uri        | [RFC7252] |
% |     39 | Proxy-Scheme     | [RFC7252] |
% |     60 | Size1            | [RFC7252] |
% |    128 | (Reserved)       | [RFC7252] |
% |    132 | (Reserved)       | [RFC7252] |
% |    136 | (Reserved)       | [RFC7252] |
% |    140 | (Reserved)       | [RFC7252] |
% +--------+------------------+-----------+

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

-record(coap_message, {type, method, code, id, token = <<>>,
                       options = [], payload = <<>>}).

-type(coap_message() :: #coap_message{}).

% CoAP Response Codes:
%           
% +------+------------------------------+-----------+
% | Code | Description                  | Reference |
% +------+------------------------------+-----------+
% | 2.01 | Created                      | [RFC7252] |
% | 2.02 | Deleted                      | [RFC7252] |
% | 2.03 | Valid                        | [RFC7252] |
% | 2.04 | Changed                      | [RFC7252] |
% | 2.05 | Content                      | [RFC7252] |
% | 4.00 | Bad Request                  | [RFC7252] |
% | 4.01 | Unauthorized                 | [RFC7252] |
% | 4.02 | Bad Option                   | [RFC7252] |
% | 4.03 | Forbidden                    | [RFC7252] |
% | 4.04 | Not Found                    | [RFC7252] |
% | 4.05 | Method Not Allowed           | [RFC7252] |
% | 4.06 | Not Acceptable               | [RFC7252] |
% | 4.12 | Precondition Failed          | [RFC7252] |
% | 4.13 | Request Entity Too Large     | [RFC7252] |
% | 4.15 | Unsupported Content-Format   | [RFC7252] |
% | 5.00 | Internal Server Error        | [RFC7252] |
% | 5.01 | Not Implemented              | [RFC7252] |
% | 5.02 | Bad Gateway                  | [RFC7252] |
% | 5.03 | Service Unavailable          | [RFC7252] |
% | 5.04 | Gateway Timeout              | [RFC7252] |
% | 5.05 | Proxying Not Supported       | [RFC7252] |
% +------+------------------------------+-----------+


%% CoAP Content-Formats Registry
%%
%% +--------------------------+----------+----+------------------------+
%% | Media type               | Encoding | ID | Reference              |
%% +--------------------------+----------+----+------------------------+
%% | text/plain;              | -        |  0 | [RFC2046] [RFC3676]    |
%% | charset=utf-8            |          |    | [RFC5147]              |
%% | application/link-format  | -        | 40 | [RFC6690]              |
%% | application/xml          | -        | 41 | [RFC3023]              |
%% | application/octet-stream | -        | 42 | [RFC2045] [RFC2046]    |
%% | application/exi          | -        | 47 | [REC-exi-20140211]     |
%% | application/json         | -        | 50 | [RFC7159]              |
%% +--------------------------+----------+----+------------------------+


