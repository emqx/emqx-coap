## shallow clone for speed

REBAR_GIT_CLONE_OPTIONS += --depth 1
export REBAR_GIT_CLONE_OPTIONS

REBAR = rebar3
all: compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean

ct: compile
	$(REBAR) as test ct -v

eunit: compile
	$(REBAR) as test eunit

xref:
	$(REBAR) xref

distclean:
	rm -rf _build
	rm -f data/app.*.config
	rm -f data/vm.*.args
