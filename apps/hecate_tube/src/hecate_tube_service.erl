%% @doc The hecate_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. hecate_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% IT ANNOUNCES NOTHING AND ASKS FOR NOTHING, on purpose. A service that does
%% nothing yet has no capability to offer and needs no authority from the realm.
%% Advertising a capability before it exists puts a lie on the mesh that another
%% service can find and call. Both lists grow when the thing they name exists,
%% and a generated test fails when they change, so growing them is a deliberate
%% act rather than a comment someone forgot.
-module(hecate_tube_service).

-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
-export([store_id/0, data_dir/0]).

info() ->
    #{name => <<"hecate-tube">>,
      version => <<"0.1.0">>,
      description => <<"YouTube over mesh -- a channel/video service exercising every macula primitive pair">>}.

start(_Opts) -> hecate_tube_sup:start_link().

stop(_State) -> ok.

%% Green once the supervision tree is up. Replace this with a real probe of
%% whatever this service needs in order to do its job. A dark mesh is usually NOT
%% a health failure: decide that deliberately rather than by default.
health() -> ok.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. Other services find this one by these
%% names, so each entry is a promise that something answers.
capabilities() -> [].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"hecate-tube">>,
      actions => [],
      resources => [],
      ttl_days => 30}.

%% CMD/PRJ wiring: exporting both callbacks makes hecate_om:boot/1 start
%% reckon-db + the evoq subscription before start/1 runs -- see
%% hecate_om_store. Requires the {evoq, [...]} adapter block in sys.config
%% (config/sys.config.src's <<store>> section), or evoq dispatch crashes on
%% {not_configured, event_store_adapter}.
store_id() -> tube_store.

data_dir() ->
    os:getenv("HECATE_DATA_DIR", "/var/lib/hecate-tube").
