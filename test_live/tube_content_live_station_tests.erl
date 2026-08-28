%% Live end-to-end proof for the thumbnail/logo durability fix
%% (2026-08-28): a real macula_feeder put through tube_content_put,
%% followed by a real tube.lookup_content RPC call from a SEPARATE
%% identity/pool against a real demo-fleet station, round-trips the
%% exact bytes.
%%
%% This is the test that would have caught the actual bug shipped in
%% the first version of this fix: `tube_content_put' called
%% `binary:encode_hex(Mcid, lower)', but OTP 28's real second argument
%% is the atom `lowercase', not `lower' -- a `badarg' on every real
%% call, invisible to `rebar3 eunit' because no unit test exercised a
%% real Mcid through the real function (the mesh-unreachable branch is
%% the only one any existing test could reach). A manually-typed hex
%% string handed straight to `tube_content_store:persist/2' (which is
%% how this was first "verified" live) never calls `encode_hex/2' at
%% all and would have looked identical whether the bug was fixed or not.
%%
%% Also regression-proofs the underlying lesson this fix exists for,
%% the same way hecate_om_content_live_station_tests.erl does: the
%% minted MCID must carry the non-chunked codec byte (0x55) -- if it
%% didn't, this content would get a content_announcement DHT record
%% and the durability gap this fix closes wouldn't apply to it.
%%
%% Lives in test_live/, NOT test/ -- excluded from the default
%% `rebar3 eunit' and CI's main gate on purpose; the demo fleet is
%% documented, disposable dev infra with no uptime guarantee, so a
%% station blip must never block an unrelated PR. Run explicitly:
%%   rebar3 as live_test eunit --dir test_live
-module(tube_content_live_station_tests).
-include_lib("eunit/include/eunit.hrl").

-define(SEED, <<"https://station-de-frankfurt.macula.io:4433">>).

thumbnail_round_trips_from_a_separate_caller_test_() ->
    {timeout, 30, fun run/0}.

run() ->
    DataDir = fresh_data_dir(),
    os:putenv("HECATE_DATA_DIR", DataDir),
    {ok, _} = application:ensure_all_started(macula),

    %% Pool A plays hecate-tube: puts the content, advertises the RPC.
    KeyPairA = macula_identity:generate(#{puzzle => true}),
    Realm = crypto:strong_rand_bytes(32),
    {ok, PoolA} = macula_client:connect([?SEED], #{identity => KeyPairA}),
    ok = wait_healthy(PoolA, 100),

    ok = meck:new(hecate_om, [passthrough]),
    ok = meck:expect(hecate_om, mesh_handles, fun() -> {ok, PoolA, Realm} end),

    Bytes = <<"tube thumbnail live round-trip, ", (crypto:strong_rand_bytes(8))/binary>>,
    {ok, Mcid} = tube_content_put:put(Bytes),

    %% The regression-proof: a thumbnail-sized blob must never carry the
    %% chunked codec byte -- if it did, it would get a content_announcement
    %% DHT record and this whole fix would be solving a problem that
    %% content_transfer's own discovery path already handled.
    ?assertMatch(<<1, 16#55, _/binary>>, Mcid),

    {ok, ChannelSup} = macula_response:advertise_direct(
        PoolA, Realm, <<"tube.lookup_content">>, advertise_content_lookup, [],
        KeyPairA, #{}),
    ?assert(is_pid(ChannelSup)),

    %% Pool B plays macula-realm: a SEPARATE identity, SEPARATE pool,
    %% asking for the SAME bytes later -- the exact shape of the
    %% original bug (a caller with no relationship to the original put).
    KeyPairB = macula_identity:generate(#{puzzle => true}),
    {ok, PoolB} = macula_client:connect([?SEED], #{identity => KeyPairB}),
    ok = wait_healthy(PoolB, 100),

    McidHex = binary:encode_hex(Mcid, lowercase),
    {ok, #{bytes := RoundTripped}} =
        macula_direct_dial:call(PoolB, Realm, <<"tube.lookup_content">>,
                                 #{mcid => McidHex}, 5_000),
    ?assertEqual(Bytes, RoundTripped),

    %% The not_found branch (unknown mcid) is covered without the network
    %% by advertise_content_lookup_tests.erl -- a second live call here,
    %% back-to-back with the first against a shared demo relay, hit real
    %% connection churn unrelated to this fix's correctness and bought
    %% nothing the unit test doesn't already cover.

    meck:unload(hecate_om),
    catch macula_client:close(PoolA),
    catch macula_client:close(PoolB),
    os:unsetenv("HECATE_DATA_DIR"),
    remove_dir(DataDir),
    ok.

fresh_data_dir() ->
    Dir = filename:join(["/tmp", "tube_content_live_" ++
                          integer_to_list(erlang:unique_integer([positive]))]),
    ok = filelib:ensure_dir(filename:join(Dir, "placeholder")),
    Dir.

remove_dir(Dir) ->
    [file:delete(F) || F <- filelib:wildcard(filename:join([Dir, "**"]))],
    _ = file:del_dir(filename:join(Dir, "thumbnails")),
    _ = file:del_dir(Dir),
    ok.

wait_healthy(_Pool, 0) ->
    erlang:error(seed_never_healthy);
wait_healthy(Pool, N) ->
    healthy_or_wait(macula_client:status(Pool), Pool, N).

healthy_or_wait({ok, #{healthy_links := H}}, _Pool, _N) when H > 0 ->
    ok;
healthy_or_wait(_Status, Pool, N) ->
    timer:sleep(100),
    wait_healthy(Pool, N - 1).
