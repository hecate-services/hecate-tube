%%% Unit tests for tube_mesh_providers:reuse_opts/1 -- the pure logic
%%% behind periodic re-advertise. A station's wire-level registration
%%% for a procedure is tied to whichever connection sent it and does
%%% not survive that connection being replaced; re-advertising on a
%%% timer is the fix, but calling advertise_direct/6,7 without
%%% reuse_sup starts a new factory supervisor every time, leaking one
%%% per tick. Confirmed live: this was the last piece of a long-running
%%% unknown_next_peer investigation -- see macula 10.1.0's own
%%% CHANGELOG entry.
-module(tube_mesh_providers_tests).
-include_lib("eunit/include/eunit.hrl").

first_advertise_starts_fresh_test() ->
    Opts = tube_mesh_providers:reuse_opts(#{advertised => false}),
    ?assertEqual(#{}, Opts(stream_sup)).

readvertise_reuses_the_stored_supervisor_test() ->
    Sup = self(),
    Opts = tube_mesh_providers:reuse_opts(#{advertised => true, stream_sup => Sup}),
    ?assertEqual(#{reuse_sup => Sup}, Opts(stream_sup)).

each_procedure_reuses_its_own_supervisor_independently_test() ->
    State = #{advertised => true, channel_sup => c, clip_sup => l, stream_sup => s},
    Opts = tube_mesh_providers:reuse_opts(State),
    ?assertEqual(#{reuse_sup => c}, Opts(channel_sup)),
    ?assertEqual(#{reuse_sup => l}, Opts(clip_sup)),
    ?assertEqual(#{reuse_sup => s}, Opts(stream_sup)).
