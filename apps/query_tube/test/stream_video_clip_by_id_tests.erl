-module(stream_video_clip_by_id_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% Regression: macula's frame decoder round-trips a known map key
%% through binary_to_existing_atom/1, so `args' arrives as
%% `#{clip_id => ...}' (atom key), never `#{<<"clip_id">> => ...}'
%% (binary key). Confirmed live via a macula_frame:stream_open/1 +
%% encode/1 + decode/1 round-trip. A wrongly-binary-keyed match clause
%% falls through to the catch-all and rejects every real call with
%% `bad_request' — this pins the atom-keyed clause as the one that
%% actually fires.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{clip_id => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_rejected_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{<<"clip_id">> => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, bad_request, undefined}, Result)
        end
     end}.
