
emq_coap
=========

emq-coap is a CoAP Gateway for the EMQ Broker. It translates CoAP messages into MQTT messages and make it possible to communiate between CoAP clients and MQTT clients.


Client Usage Example
--------------------
libcoap is an excellent coap library which has a simple client tool. It is recommended to use libcoap as a coap client.

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
- topic name is "topic1", NOT "/topic1"
- client id is client1
- username is tom
- password is secret
- payload is a text string "1234"

A mqtt message with topic="topic1", payload="1234" has been published. Any mqtt client or coap client, who has subscribed this topic could receive this message immediately.

### Subscribe example:

```
libcoap/examples/coap-client -m get -s 10 "coap://127.0.0.1/mqtt/topic1?c=client1&u=tom&p=secret"
```
- topic name is "topic1", NOT "/topic1"
- client id is client1
- username is tom
- password is secret
- subscribe time is 10 seconds

And you will get following result if any mqtt client or coap client sent message with text "1234567" to "topic1":

```
v:1 t:CON c:GET i:31ae {} [ ]
1234567v:1 t:CON c:GET i:31af {} [ Observe:1, Uri-Path:mqtt, Uri-Path:topic1, Uri-Query:c=client1, Uri-Query:u=tom, Uri-Query:p=secret ]
```
The output message is not well formatted which hide "1234567" at the head of the 2nd line.


Configure emq-coap
------------------

File: etc/emq_coap.conf

```
coap.port = 5683
coap.keepalive = 120
coap.enable_stats = off
coap.certfile = etc/certs/cert.pem
coap.keyfile = etc/certs/key.pem
```
- coap.port
  + UDP port for coap.
- coap.keepalive
  + Interval for keepalive, in seconds.
- coap.enable_stats
  + To control whether write statistics data into ETS table for dashbord to read.
- coap.certfile
  + server certificate for DTLS
- coap.keyfile
  + private key for DTLS

Load emq-coap
-------------

```
./bin/emqttd_ctl plugins load emq_coap
```

CoAP Client Observe Operation (subscribe topic)
-----------------------------------------------
To subscribe any topic, issue following command:

```
  GET  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}    with OBSERVE=0
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} in URI should be percent-encoded to prevent special characters, such as + and #.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.
- topic is subscribed with qos1.

CoAP Client Unobserve Operation (unsubscribe topic)
---------------------------------------------------
To cancel observation, issue following command:

```
  GET  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}    with OBSERVE=1
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} in URI should be percent-encoded to prevent special characters, such as + and #.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.


CoAP Client Notification Operation (subscribed Message)
-------------------------------------------------------
Server will issue an observe-notification as a subscribed message.

- Its payload is exactly the mqtt payload.
- payload data type is "application/octet-stream".

CoAP Client Publish Operation
-----------------------------
Issue a coap put command to do publishment. For example:

```
  PUT  coap://localhost/mqtt/{topicname}?c={clientid}&u={username}&p={password}
```

- "mqtt" in the path is mandatory.
- replace {topicname}, {clientid}, {username} and {password} with your true values.
- {topicname} and {clientid} is mandatory.
- if clientid is absent, a "bad_request" will be returned.
- {topicname} in URI should be percent-encoded to prevent special characters, such as + and #.
- {username} and {password} are optional.
- if {username} and {password} are not correct, an uauthorized error will be returned.
- payload could be any binary data.
- payload data type is "application/octet-stream".
- publish message will be sent with qos0.

CoAP Client Keep Alive
----------------------
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

CoAP Client NOTES
-----------------
emq-coap gateway does not accept POST and DELETE requests.

Topics in URI should be percent-encoded, but corresponding uri_path option has percent-encoding converted. Please refer to RFC 7252 section 6.4, "Decomposing URIs into Options":

> Note that these rules completely resolve any percent-encoding.

That implies coap client is responsible to convert any percert-encoding into true character while assembling coap packet.


DTLS
----
emq-coap support DTLS to secure UDP data.

Please config coap.certfile and coap.keyfile in emq_coap.conf. If certfile or keyfile are invalid, DTLS will be turned off and you could read a error message in system log.


ClientId, Username, Password and Topic
--------------------------------------
ClientId/username/password/topic in the coap URI are the concepts in mqtt. That is to say, emq-coap is trying to fit coap message into mqtt system, by borrowing the client/username/password/topic from mqtt.

The Auth/ACL/Hook features in mqtt also applies on coap stuff. For example:
- If username/password is not authorized, coap client will get an uauthorized error.
- If username or clientid is not allowed to published specific topic, coap message will be dropped in fact, although coap client will get an acknoledgement from emq-coap.
- If a coap message is published, a 'message.publish' hook is able to capture this message as well.



License
-------

Apache License Version 2.0

Author
------

Feng Lee <feng@emqtt.io>
