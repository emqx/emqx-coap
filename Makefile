PROJECT = emqx_coap
PROJECT_DESCRIPTION = EMQ X CoAP Gateway
PROJECT_VERSION = 3.0

DEPS = gen_coap clique

dep_gen_coap = git-emqx https://github.com/emqx/gen_coap v0.2.2
dep_clique   = git-emqx https://github.com/emqx/clique v0.3.11

BUILD_DEPS = emqx cuttlefish
dep_emqx = git-emqx https://github.com/emqx/emqx emqx30
dep_cuttlefish = git-emqx https://github.com/emqx/cuttlefish v2.2.1

TEST_DEPS = er_coap_client
dep_er_coap_client = git-emqx https://github.com/grutabow/er_coap_client master

ERLC_OPTS += +debug_info

$(shell [ -f erlang.mk ] || curl -s -o erlang.mk https://raw.githubusercontent.com/emqx/erlmk/master/erlang.mk)
include erlang.mk

NO_AUTOPATCH = cuttlefish 

CUTTLEFISH_SCRIPT = _build/default/lib/cuttlefish/cuttlefish

app.config: $(CUTTLEFISH_SCRIPT) etc/emqx_coap.conf
	$(verbose) $(CUTTLEFISH_SCRIPT) -l info -e etc/ -c etc/emqx_coap.conf -i priv/emqx_coap.schema -d data

$(CUTTLEFISH_SCRIPT): rebar-deps
	@if [ ! -f cuttlefish ]; then make -C _build/default/lib/cuttlefish; fi

distclean::
	@rm -rf _build cover deps logs log data
	@rm -f rebar.lock compile_commands.json cuttlefish

rebar-deps:
	rebar3 get-deps

rebar-clean:
	@rebar3 clean

rebar-compile: rebar-deps
	rebar3 compile

rebar-xref:
	@rebar3 xref

## Below are for version consistency check during erlang.mk and rebar3 dual mode support
none=
space = $(none) $(none)
comma = ,
quote = \"
curly_l = "{"
curly_r = "}"
dep-versions = [$(foreach dep,$(DEPS) $(BUILD_DEPS) $(TEST_DEPS),$(curly_l)$(dep),$(quote)$(word 3,$(dep_$(dep)))$(quote)$(curly_r)$(comma))[]]

.PHONY: dep-vsn-check
dep-vsn-check:
	$(verbose) erl -noshell -eval \
		"MkVsns = lists:sort(lists:flatten($(dep-versions))), \
		{ok, Conf} = file:consult('rebar.config'), \
		{_, Deps} = lists:keyfind(deps, 1, Conf), \
		F = fun({N, V}) when is_list(V) -> {N, V}; ({N, {git, _, {branch, V}}}) -> {N, V} end, \
		RebarVsns = lists:sort(lists:map(F, Deps)), \
		case {RebarVsns -- MkVsns, MkVsns -- RebarVsns} of \
		  {[], []} -> halt(0); \
		  {Rebar, Mk} -> erlang:error({deps_version_discrepancy, [{rebar, Rebar}, {mk, Mk}]}) \
		end."
