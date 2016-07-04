PROJECT = emqtt_coap
PROJECT_DESCRIPTION = Erlang CoAP Server
PROJECT_VERSION = 0.1

DEPS = lager esockd cbor

dep_esockd = git https://github.com/emqtt/esockd.git udp
dep_cbor   = git https://github.com/emqtt/erlang-cbor.git master

ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk
