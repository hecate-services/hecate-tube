%% @doc The `channel_announced_v1' fact's wire shape: text as `{text, Bin}'
%% (CBOR text) so non-BEAM subscribers get strings, not bytes, while the
%% channel id and logo mcid stay bytes.
-module(channel_announcement_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CHANNEL, <<"channel-announcement-tests-channel">>).
-define(PUBLISHED_CLIP, <<"channel-announcement-tests-published-clip">>).
-define(UPLOADED_CLIP, <<"channel-announcement-tests-uploaded-clip">>).

%% project_tube_store is registered, channel_aggregate_tests leaves it up in
%% the same VM, and eunit runs this suite twice (under its owning module and
%% by its own name), so the store may already be running. Same tolerance as
%% channel_aggregate_tests; ids unique to this suite keep the count exact.
fact_sends_text_as_text_and_ids_as_bytes_test() ->
    ensure_started(project_tube_store:start_link()),
    ok = project_tube_store:put_clip(?PUBLISHED_CLIP, #{
        clip_id => ?PUBLISHED_CLIP, channel_id => ?CHANNEL, status => <<"published">>}),
    ok = project_tube_store:put_clip(?UPLOADED_CLIP, #{
        clip_id => ?UPLOADED_CLIP, channel_id => ?CHANNEL, status => <<"uploaded">>}),
    Row = #{channel_id => ?CHANNEL, name => <<"Cats">>, description => undefined,
            owner => <<"Raf">>, tags => [<<"cats">>], logo_mcid => <<1, 2, 3>>},
    Fact = channel_announcement:fact(Row, ?CHANNEL, <<"heartbeat">>),
    ?assert(is_integer(maps:get(announced_at, Fact))),
    ?assertEqual(#{channel_id => ?CHANNEL,
                   action => {text, <<"heartbeat">>},
                   name => {text, <<"Cats">>},
                   description => undefined,
                   owner => {text, <<"Raf">>},
                   tags => [{text, <<"cats">>}],
                   logo_mcid => <<1, 2, 3>>,
                   published_clip_count => 1},
                 maps:remove(announced_at, Fact)).

ensure_started({ok, _Pid}) -> ok;
ensure_started({error, {already_started, _Pid}}) -> ok.
