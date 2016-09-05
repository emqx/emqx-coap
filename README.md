
emqttd_coap
===========

CoAP Gateway for The EMQTT Broker

License
-------

Apache License Version 2.

Configure Plugin
----------------

File: etc/emqttd_coap.conf

```erlang
{listener, coap1, 5683, []}.

{listener, coap2, 5684, []}.

{gateway, "mqtt", emqttd_coap_gateway}.

```

## Usage

### simple 

```erlang
implemented behaviour emqttd_coap_handler function

handle_request(#coap_message{method = 'GET'}) ->
    {ok, #coap_response{code = 'Content', payload = <<"handle_request GET">>}};

handle_request(#coap_message{method = 'POST'}) ->
    {ok, #coap_response{code = 'Created', payload = <<"handle_request POST">>}};

handle_request(#coap_message{method = 'PUT'}) ->
    {ok, #coap_response{code = 'Changed', payload = <<"handle_request PUT">>}};

handle_request(#coap_message{method = 'DELETE'}) ->
    {ok, #coap_response{code = 'Deleted', payload = <<"handle_request DELETE">>}}.

handle_observe(#coap_message{}) ->
    {ok, #coap_response{code = 'Content', payload = <<"handle_observe">>}}.

handle_unobserve(#coap_message{}) ->
    {ok, #coap_response{code = 'Content', payload = <<"handle_unobserve">>}}.

```

Load Plugin
-----------

```
./bin/emqttd_ctl plugins load emqttd_coap
```

Author
------

Feng Lee <feng@emqtt.io>

