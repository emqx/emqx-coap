
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
```

Load Plugin
-----------

```
./bin/emqttd_ctl plugins load emqttd_coap
```

Author
------

Feng Lee <feng@emqtt.io>

