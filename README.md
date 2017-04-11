
# emq_coap

CoAP Gateway for the EMQ Broker

## Configure Plugin

File: etc/emq_coap.conf

```
coap.server = 5683
coap.keepalive = 3600
```

## Load Plugin

```
./bin/emqttd_ctl plugins load emq_coap
```

## PUBLISH MESSAGE
Send a POST command to "coap://host/mqtt", with payload="topic=XX&message=YY", where XX is topic and YY is payload. XX and YY should be percent-encoded.

## SUBSCRIBE TOPIC
Send a GET command to "coap://host/mqtt/?topic=XX", with observe=0 option, where XX is topic. XX should be percent-encoded.

## UNSUBSCRIBE TOPIC
Send a GET command to "coap://host/mqtt/?topic=XX", with observe=1 option, where XX is topic. XX should be percent-encoded.

## DISPATCHED MESSAGE
MQTT message sent from broker is carried in a caop notification, with payload="topic=XX&message=YY", where XX is topic and YY is payload. XX and YY are percent-encoded.

## KEEPALIVE
Send a GET command to "coap://host/mqtt/", without any options. The default timeout is 3600 seconds. Once keepalive timeout, coap client context will be dropped and coap client will never receive messages from broker.

## NOTE
Only one topic could be subscribed.


## Client Example
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
    if response:
        print(response.pretty_print())

def keepalive(client, uri):
    client.get(uri)
        

def main():
    # please encode topic and message payload with percent-encoding
    # if topic and payload contains special characters other than alphabet and digits 
    
    coap_uri = "coap://192.168.222.130/mqtt?topic=abc"
    host, port, path = parse_uri(coap_uri)
    host = socket.gethostbyname(host)
    client = HelperClient(server=(host, port))
    
    # subscribe topic "abc"
    client.observe(coap_uri, client_callback_observe)
        
    time.sleep(1)
    
    # publish a message with topic="abc" payload="hello"
    payload = "topic=abc&message=hello"
    response = client.post("coap://192.168.222.130/mqtt", payload)

    count = 0
    while count < 20:  # wait 20 seconds to get subscribed message
        count = count + 1
        time.sleep(1)
        keepalive(client, coap_uri)
    
    client.stop()
    


if __name__ == '__main__':
    main()
    
```

emq_coap gateway does not accept PUT and DELETE request.

In case topic and message contains special characters, such as '&' or '/', please percent-encoding them before assembling a coap payload.
For example, topic="/abc" and message="x=9", coap payload should be "topic=%2Fabc&message=x%3D9".


# License

Apache License Version 2.0

# Author

Feng Lee <feng@emqtt.io>

