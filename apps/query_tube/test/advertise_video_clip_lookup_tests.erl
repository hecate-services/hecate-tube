-module(advertise_video_clip_lookup_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% Same key forms as advertise_channel_lookup_tests: `clip_id' is an atom
%% key only when the atom already exists in the receiving VM.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_video_clip_lookup:handle_request(
                       #{clip_id => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_video_clip_lookup:handle_request(
                       #{<<"clip_id">> => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

missing_clip_id_is_a_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ?assertEqual({error, bad_request, undefined},
                         advertise_video_clip_lookup:handle_request(#{}, undefined))
        end
     end}.

%% Text goes out as `{text, Bin}' (CBOR text) so non-BEAM callers get
%% strings, not bytes. Ids and the thumbnail mcid stay bytes.
reply_sends_text_as_text_and_ids_as_bytes_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ok = project_tube_store:put_clip(<<"clip-1">>, #{
                clip_id => <<"clip-1">>, channel_id => <<"ch-1">>, name => <<"Nap">>,
                description => <<"A long nap">>, tags => [<<"cats">>],
                thumbnail_mcid => <<4, 5, 6>>, status => <<"published">>}),
            {reply, Reply, undefined} = advertise_video_clip_lookup:handle_request(
                                          #{clip_id => {text, <<"clip-1">>}}, undefined),
            ?assertEqual(#{clip_id => <<"clip-1">>,
                           channel_id => <<"ch-1">>,
                           name => {text, <<"Nap">>},
                           description => {text, <<"A long nap">>},
                           tags => [{text, <<"cats">>}],
                           thumbnail_mcid => <<4, 5, 6>>,
                           view_count => 0},
                         Reply)
        end
     end}.
