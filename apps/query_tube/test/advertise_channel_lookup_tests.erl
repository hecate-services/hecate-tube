-module(advertise_channel_lookup_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% macula's frame decoder makes `channel_id' an atom key only when the
%% atom already exists in the receiving VM; otherwise the key stays as it
%% was sent. The handler must reach the lookup for every form it can read.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_channel_lookup:handle_request(
                       #{channel_id => <<"nonexistent-channel">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = advertise_channel_lookup:handle_request(
                       #{<<"channel_id">> => <<"nonexistent-channel">>}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

text_valued_channel_id_is_looked_up_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ok = project_tube_store:put_channel(<<"ch-text">>, #{channel_id => <<"ch-text">>}),
            {reply, Reply, undefined} = advertise_channel_lookup:handle_request(
                                          #{channel_id => {text, <<"ch-text">>}}, undefined),
            ?assertEqual(<<"ch-text">>, maps:get(channel_id, Reply))
        end
     end}.

missing_channel_id_is_a_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ?assertEqual({error, bad_request, undefined},
                         advertise_channel_lookup:handle_request(#{}, undefined))
        end
     end}.

%% Text goes out as `{text, Bin}' (CBOR text) so non-BEAM callers get
%% strings, not bytes. Ids and mcids stay bytes.
reply_sends_text_as_text_and_ids_as_bytes_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ok = project_tube_store:put_channel(<<"ch-1">>, #{
                channel_id => <<"ch-1">>, name => <<"Cats">>,
                description => <<"All the cats">>, owner => <<"Raf">>,
                tags => [<<"cats">>, <<"pets">>], logo_mcid => <<1, 2, 3>>}),
            ok = project_tube_store:put_clip(<<"clip-1">>, #{
                clip_id => <<"clip-1">>, channel_id => <<"ch-1">>, name => <<"Nap">>,
                thumbnail_mcid => <<4, 5, 6>>, status => <<"published">>}),
            {reply, Reply, undefined} = advertise_channel_lookup:handle_request(
                                          #{channel_id => <<"ch-1">>}, undefined),
            ?assertEqual(#{channel_id => <<"ch-1">>,
                           name => {text, <<"Cats">>},
                           description => {text, <<"All the cats">>},
                           owner => {text, <<"Raf">>},
                           tags => [{text, <<"cats">>}, {text, <<"pets">>}],
                           logo_mcid => <<1, 2, 3>>,
                           clips => [#{clip_id => <<"clip-1">>,
                                       name => {text, <<"Nap">>},
                                       thumbnail_mcid => <<4, 5, 6>>,
                                       view_count => 0}]},
                         Reply)
        end
     end}.
