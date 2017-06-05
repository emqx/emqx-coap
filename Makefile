PROJECT = emq_coap
PROJECT_DESCRIPTION = CoAP Gateway
PROJECT_VERSION = 2.2

DEPS = cbor lager esockd

dep_cbor     = git https://github.com/emqtt/erlang-cbor master
dep_lager    = git https://github.com/basho/lager
dep_esockd   = git https://github.com/emqtt/esockd master
dep_mochiweb = git https://github.com/emqtt/mochiweb master

BUILD_DEPS = emqttd cuttlefish
dep_emqttd = git https://github.com/emqtt/emqttd emq22
dep_cuttlefish = git https://github.com/emqtt/cuttlefish

ERLC_OPTS += +debug_info
ERLC_OPTS += +'{parse_transform, lager_transform}'
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emq_coap.conf -i priv/emq_coap.schema -d data
