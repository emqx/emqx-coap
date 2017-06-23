
emq_coap
=========

CoAP Gateway for the EMQ Broker

Configure Plugin
----------------

File: etc/emq_coap.conf

```
coap.port = 5683
coap.keepalive = 120
coap.certfile = etc/certs/cert.pem
coap.keyfile = etc/certs/key.pem
```
- coap.port
  + UDP port for coap.
- coap.keepalive
  + Interval for keepalive, in seconds.
- coap.certfile
  + server certificate for DTLS
- coap.keyfile
  + private key for DTLS

Load Plugin
-----------

```
./bin/emqttd_ctl plugins load emq_coap
```



Observe (subscribe topic)
-----------------
To subscribe any topic, issue following command:

```
  GET  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}    with OBSERVE=0
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} should be percent-encoded to prevent special characters.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.


Unobserve (unsubscribe topic)
---------
To cancel observation, issue following command:

```
  GET  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}    with OBSERVE=1
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} should be percent-encoded to prevent special characters.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.


Notification (subscribed Message)
-----------
Server will issue an observe-notification as a subscribed message.

- Its payload is exactly the mqtt payload.
- payload data type is "application/octet-stream".

Publish
-----------
Issue a coap put command to do publishment. For example

```
  PUT  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} should be percent-encoded to prevent special characters.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.
- payload could be any binary data.
- payload data type is "application/octet-stream".
- publish message will be sent with qos0.


Keep Alive
-----------
Device should issue a get command periodically, serve as a ping to keep mqtt session online.

```
  GET  coap://localhost/mqtt/{any_topicname}?c={clientid}&u={username}&p={password}
```

- "mqtt" in the path is mandatory.
- replace {any_topicname}, {clientid}, {username} and {password} with your true values.
- {any_topicname} is optional, and should be percent-encoded to prevent special characters.
- {clientid} is mandatory. If clientid is absent, a "bad_request" will be returned.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.
- coap client should do keepalive work periodically to keep mqtt session online, especially those devices in a NAT network.

DTLS
-----------
emq-coap support DTLS to secure UDP data.

Please config coap.certfile and coap.keyfile in emq_coap.conf. If certfile or keyfile are invalid, DTLS will be turned off and you could read a error message in system log.

## Client
libcoap is an excellent coap library which has a simple client tool.

To compile libcoap, do following steps:

```
git clone http://github.com/obgm/libcoap
cd libcoap
./autogen.sh
./configure --enable-documentation=no --enable-tests=no
make
```

### Publish example:
```
libcoap/examples/coap-client -m put -e 1234  "coap://127.0.0.1/mqtt/topic1?c=client1&u=tom&p=secret"
```
- topic name is topic1
- client id is client1
- username is tom
- password is secret
- payload is a text string "1234"

### Subscribe example:

```
libcoap/examples/coap-client -m get -s 10 "coap://127.0.0.1/mqtt/topic1?c=client1&u=tom&p=secret"
```
- topic name is topic1
- client id is client1
- username is tom
- password is secret
- subscribe time is 10 seconds

And you will get following result if anybody sent message with text "1234567" on topic1:

```
v:1 t:CON c:GET i:31ae {} [ ]
1234567v:1 t:CON c:GET i:31af {} [ Observe:1, Uri-Path:mqtt, Uri-Path:topic1, Uri-Query:c=client1, Uri-Query:u=tom, Uri-Query:p=secret ]
```

The output message is not well formatted which hide "1234567" at the head of the 2nd line.


### NOTES
emq_coap gateway does not accept POST and DELETE request.


## Known Issues
- Upon unloading emq-coap plugin, udp dtls port (5884 by default) could not be closed properly.


License
-------

Apache License Version 2.0

Author
------

Feng Lee <feng@emqtt.io>

