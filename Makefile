PROJECT = emqtt_coap
PROJECT_DESCRIPTION = CoAP Gateway
PROJECT_VERSION = 0.1

DEPS = lager esockd cbor emqttd

dep_esockd = git https://github.com/emqtt/esockd.git udp
dep_emqttd = git https://github.com/emqtt/emqttd.git mqtt-sn
dep_cbor   = git https://github.com/emqtt/erlang-cbor.git master

ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk
