PROJECT = emqx_coap
PROJECT_DESCRIPTION = EMQ X CoAP Gateway
PROJECT_VERSION = 3.0

DEPS = gen_coap clique
dep_gen_coap = git https://github.com/emqx/gen_coap v0.2.2
dep_clique   = git https://github.com/emqx/clique

BUILD_DEPS = emqx cuttlefish
dep_emqx = git https://github.com/emqtt/emqttd emqx30
dep_cuttlefish = git https://github.com/emqx/cuttlefish emqx30

TEST_DEPS = er_coap_client
dep_er_coap_client = git https://github.com/grutabow/er_coap_client

ERLC_OPTS += +debug_info

include erlang.mk

NO_AUTOPATCH = cuttlefish

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_coap.conf -i priv/emqx_coap.schema -d data
