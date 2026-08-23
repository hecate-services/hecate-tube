-module(advertise_video_clip_lookup_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% Same regression as stream_video_clip_by_id_tests: `args' arrives
%% as `#{clip_id => ...}' (atom key), never `#{<<"clip_id">> => ...}'.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_video_clip_lookup:handle_request(
                       #{clip_id => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_rejected_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_video_clip_lookup:handle_request(
                       #{<<"clip_id">> => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({error, bad_request, undefined}, Result)
        end
     end}.
