%% @doc The `video_clip_published_v1' and `video_clip_retracted_v1' fact's
%% wire shape: text as `{text, Bin}' (CBOR text) so non-BEAM subscribers
%% get strings, not bytes, while ids and the thumbnail mcid stay bytes.
-module(video_clip_publication_tests).

-include_lib("eunit/include/eunit.hrl").

fact_sends_text_as_text_and_ids_as_bytes_test() ->
    Row = #{clip_id => <<"clip-1">>, channel_id => <<"ch-1">>, name => <<"Nap">>,
            description => <<"A long nap">>, tags => [<<"cats">>, <<"sleep">>],
            thumbnail_mcid => <<4, 5, 6>>, local_ref => <<"/data/clip-1.mp4">>,
            status => <<"published">>},
    Fact = video_clip_publication:fact(Row, <<"clip-1">>),
    ?assert(is_integer(maps:get(sent_at, Fact))),
    ?assertEqual(#{clip_id => <<"clip-1">>,
                   channel_id => <<"ch-1">>,
                   name => {text, <<"Nap">>},
                   description => {text, <<"A long nap">>},
                   tags => [{text, <<"cats">>}, {text, <<"sleep">>}],
                   thumbnail_mcid => <<4, 5, 6>>},
                 maps:remove(sent_at, Fact)).

fact_keeps_an_absent_description_absent_test() ->
    Fact = video_clip_publication:fact(#{channel_id => <<"ch-1">>, name => <<"Nap">>},
                                       <<"clip-1">>),
    ?assertEqual(undefined, maps:get(description, Fact)),
    ?assertEqual([], maps:get(tags, Fact)).
