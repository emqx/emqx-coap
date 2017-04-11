
# emq_coap

CoAP Gateway for the EMQ Broker

## Configure Plugin

File: etc/emq_coap.conf

```
coap.server = 5683

```

## Load Plugin

```
./bin/emqttd_ctl plugins load emq_coap
```

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

def main():
    # please encode topic and message payload with percent-encoding
    # if topic and payload contains special characters other than alphabet and digits 
    
    coap_uri = "coap://localhost/mqtt?topic=abc"
    host, port, path = parse_uri(coap_uri)
    host = socket.gethostbyname(host)
    client = HelperClient(server=(host, port))
    
    # subscribe topic "abc"
    client.observe(coap_uri, client_callback_observe)
        
    time.sleep(1)
    
    # publish a message with topic="abc" payload="hello"
    payload = "topic=abc&message=hello"
    response = client.post("coap://localhost/mqtt", payload)
    
    client.stop()
    
if __name__ == '__main__':
    main()
```

emq_coap gateway does not accept GET and DELETE request.

In case topic and message contains special characters, such as '&' or '/', please percent-encoding them before assembling a coap payload.
For example, topic="/abc" and message="x=9", coap payload should be "topic=%2Fabc&message=x%3D9".


# License

Apache License Version 2.0

# Author

Feng Lee <feng@emqtt.io>

