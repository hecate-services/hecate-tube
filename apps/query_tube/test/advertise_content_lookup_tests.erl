-module(advertise_content_lookup_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    Dir = filename:join("/tmp", "advertise_content_lookup_tests_" ++
                         integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("HECATE_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("HECATE_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

content_found_returns_bytes_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ok = tube_content_store:persist(<<"deadbeef">>, <<"jpeg bytes">>),
            Result = advertise_content_lookup:handle_request(
                       #{mcid => <<"deadbeef">>}, undefined),
            ?assertEqual({reply, #{bytes => <<"jpeg bytes">>}, undefined}, Result)
        end
     end}.

%% The actual case this exists for: `macula:put_content/2' is a
%% one-time transfer, not storage -- a caller asking for content that
%% was never persisted locally (or predates this fix entirely) must
%% get a clean not_found, not a crash.
content_missing_returns_not_found_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            Result = advertise_content_lookup:handle_request(
                       #{mcid => <<"nonexistent">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

%% Same regression class as advertise_video_clip_lookup_tests: `mcid'
%% arrives as an atom key, never `#{<<"mcid">> => ...}'.
binary_keyed_args_are_rejected_test() ->
    Result = advertise_content_lookup:handle_request(
               #{<<"mcid">> => <<"deadbeef">>}, undefined),
    ?assertEqual({error, bad_request, undefined}, Result).
