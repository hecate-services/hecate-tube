-module(tube_content_put_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    Dir = filename:join("/tmp", "tube_content_put_tests_" ++
                         integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("HECATE_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("HECATE_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

put_persists_locally_and_mints_a_single_block_mcid_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            {ok, Mcid} = tube_content_put:put(<<"jpeg bytes">>),
            ?assertMatch(<<1, 16#55, _/binary>>, Mcid),
            ?assertEqual({ok, <<"jpeg bytes">>},
                          tube_content_store:read(binary:encode_hex(Mcid, lowercase)))
        end
     end}.

%% Content-addressed: the same bytes always mint the same MCID.
put_is_deterministic_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            {ok, Mcid1} = tube_content_put:put(<<"same bytes">>),
            {ok, Mcid2} = tube_content_put:put(<<"same bytes">>),
            ?assertEqual(Mcid1, Mcid2)
        end
     end}.
