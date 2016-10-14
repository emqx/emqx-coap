PROJECT = emq_coap
PROJECT_DESCRIPTION = EMQ CoAP Gateway
PROJECT_VERSION = 0.3

DEPS = cbor lager esockd mochiweb

dep_cbor     = git https://github.com/emqtt/erlang-cbor master
dep_lager    = git https://github.com/basho/lager
dep_esockd   = git https://github.com/emqtt/esockd emq20
dep_mochiweb = git https://github.com/emqtt/mochiweb master

BUILD_DEPS = emqttd
dep_emqttd = git https://github.com/emqtt/emqttd emq30

TEST_DEPS = cuttlefish
dep_cuttlefish = git https://github.com/basho/cuttlefish master

ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk

app.config::
	cuttlefish -l info -e etc/ -c etc/emq_coap.conf -i priv/emq_coap.schema -d data
