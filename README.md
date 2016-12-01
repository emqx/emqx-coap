
emq_coap
========

CoAP Gateway for the EMQ Broker

Configure Plugin
----------------

File: etc/emq_coap.conf

```
coap.server = 5683

coap.prefix.set1 = mqtt
coap.handler.set1 = emq_coap_gateway
```

The prefix "mqtt" means a coap request to coap://example.org/mqtt will be processed by a handler called "emq_coap_gateway". 

## Implement your own coap handler

emq_coap_gateway.erl is an template, please write your own handler by this example.

```erlang
implemented behaviour emq_coap_handler function

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

Load Plugin
-----------

```
./bin/emqttd_ctl plugins load emq_coap
```

## Client
Here is a coap client code snippet talking with emq_coap gateway. It depends on coapthon package, please install it through 'pip install coapthon'.  
```python
#!/usr/bin/env python
from Queue import Queue
import getopt
import random
import sys
import threading
from coapthon import defines
from coapthon.client.coap import CoAP
from coapthon.client.helperclient import HelperClient
from coapthon.messages.message import Message
from coapthon.messages.request import Request
from coapthon.utils import parse_uri
import socket, time



def client_callback_observe(response):
    print("get a response\n")
    print response.pretty_print()


def main():
    
    coap_uri = coap://localhost/mqtt?topic=abc
    host, port, path = parse_uri(coap_uri)
    host = socket.gethostbyname(host)
    client = HelperClient(server=(host, port))
    
    # subscribe topic "abc"
    client.observe(coap_uri, client_callback_observe)
        
    time.sleep(1)
    
    # publish a message with topic="abc" payload="hello"
    payload = "qos=1&retain=0&topic=abc&message=hello"
    response = client.post("coap://localhost/mqtt", payload)
    
    client.stop()
    


if __name__ == '__main__':
    main()
```

emq_coap gateway does not accept GET and DELETE request.

License
-------

Apache License Version 2.0

Author
------

Feng Lee <feng@emqtt.io>

