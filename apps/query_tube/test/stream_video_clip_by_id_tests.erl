-module(stream_video_clip_by_id_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% macula's frame decoder makes `clip_id' an atom key only when the atom
%% already exists in the receiving VM; otherwise the key stays as it was
%% sent. A handler that matched only the atom form rejected every other
%% form with `bad_request'. Each case below reaches the store lookup and
%% gets `not_found' for an unknown clip instead.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{clip_id => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{<<"clip_id">> => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

text_valued_clip_id_is_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{clip_id => {text, <<"nonexistent-clip">>}}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

missing_clip_id_is_a_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ?assertEqual({stop, bad_request, undefined},
                         stream_video_clip_by_id:handle_open(#{}, undefined))
        end
     end}.
