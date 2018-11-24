PROJECT = emqx_coap
PROJECT_DESCRIPTION = EMQ X CoAP Gateway
PROJECT_VERSION = 3.0

DEPS = gen_coap clique
dep_gen_coap = git-emqx https://github.com/emqx/gen_coap v0.2.2
dep_clique   = git-emqx https://github.com/emqx/clique

BUILD_DEPS = emqx cuttlefish
dep_emqx = git-emqx https://github.com/emqx/emqx emqx30
dep_cuttlefish = git-emqx https://github.com/emqx/cuttlefish emqx30

TEST_DEPS = er_coap_client
dep_er_coap_client = git-emqx https://github.com/grutabow/er_coap_client

ERLC_OPTS += +debug_info

define dep_fetch_git-emqx
	git clone -q --depth 1 -b $(call dep_commit,$(1)) -- $(call dep_repo,$(1)) $(DEPS_DIR)/$(call dep_name,$(1)) > /dev/null 2>&1; \
	cd $(DEPS_DIR)/$(call dep_name,$(1));
endef

include erlang.mk

NO_AUTOPATCH = cuttlefish

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_coap.conf -i priv/emqx_coap.schema -d data
