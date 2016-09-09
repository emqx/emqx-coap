PROJECT = emqttd_coap
PROJECT_DESCRIPTION = CoAP Gateway for The EMQTT Broker
PROJECT_VERSION = 0.2.0

DEPS = cbor lager gen_conf esockd mochiweb emqttd

dep_cbor     = git https://github.com/emqtt/erlang-cbor.git master
dep_lager    = git https://github.com/basho/lager.git
dep_gen_conf = git https://github.com/emqtt/gen_conf.git master
dep_esockd   = git https://github.com/emqtt/esockd.git udp
dep_emqttd   = git https://github.com/emqtt/emqttd.git
dep_mochiweb = git https://github.com/emqtt/mochiweb.git master

ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk
