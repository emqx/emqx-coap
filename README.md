
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

emqttd_coap_gateway.erl

```erlang
implemented behaviour emqttd_coap_handler function

handle_request(#coap_message{method = 'GET', payload = Payload}) ->
    % do publish
    publish(Payload),
    {ok, #coap_response{code = 'Content', payload = <<"handle_request GET">>}};

handle_request(#coap_message{method = 'POST', payload = Payload}) ->
    % do publish
    publish(Payload),
    {ok, #coap_response{code = 'Created', payload = <<"handle_request POST">>}};

handle_request(#coap_message{method = 'PUT'}) ->
    {ok, #coap_response{code = 'Changed', payload = <<"handle_request PUT">>}};

handle_request(#coap_message{method = 'DELETE'}) ->
    {ok, #coap_response{code = 'Deleted', payload = <<"handle_request DELETE">>}}.

handle_observe(#coap_message{payload = Payload}) ->
    % do subscribe
    subscribe(Payload),
    {ok, #coap_response{code = 'Content', payload = <<"handle_observe">>}}.

handle_unobserve(#coap_message{payload = Payload}) ->
    % do unsubscribe
    unsubscribe(Payload),
    {ok, #coap_response{code = 'Content', payload = <<"handle_unobserve">>}}.

handle_info(Topic, Msg = #mqtt_message{payload = Payload}) ->
    Payload2 = lists:concat(["topic=",binary_to_list(Topic), "&message=", binary_to_list(Payload)]),
    {ok, #coap_response{payload = Payload2}}.


publish(Payload) ->
    ParamsList = parse_params(Payload),
    ClientId = proplists:get_value("client", ParamsList, coap),
    Qos      = int(proplists:get_value("qos", ParamsList, "0")),
    Retain   = bool(proplists:get_value("retain", ParamsList, "0")),
    Content  = list_to_binary(proplists:get_value("message", ParamsList, "")),
    Topic    = list_to_binary(proplists:get_value("topic", ParamsList, "")),
    Msg = emqttd_message:make(ClientId, Qos, Topic, Content),
    emqttd:publish(Msg#mqtt_message{retain  = Retain}).

subscribe(Payload) ->
    ParamsList = parse_params(Payload),
    Topic = list_to_binary(proplists:get_value("topic", ParamsList, "")),
    emqttd:subscribe(Topic).

unsubscribe(Payload) ->
    ParamsList = parse_params(Payload),
    Topic = list_to_binary(proplists:get_value("topic", ParamsList, "")),
    emqttd:unsubscribe(Topic).

handle_info(Topic, Msg = #mqtt_message{payload = Payload}) ->
    Payload2 = lists:concat(["topic=",binary_to_list(Topic), "&message=", binary_to_list(Payload)]),
    io:format("Topic:~p, Msg:~p~n", [Topic, Msg]),
    {ok, #coap_response{payload = Payload2}}.

```

```erlang
yum install libcoap 

% coap client publish message
coap-client -m post -e "qos=0&retain=0&message=payload&topic=hello" coap://localhost/mqtt
```


Load Plugin
-----------

```
./bin/emqttd_ctl plugins load emqttd_coap
```

Author
------

Feng Lee <feng@emqtt.io>

