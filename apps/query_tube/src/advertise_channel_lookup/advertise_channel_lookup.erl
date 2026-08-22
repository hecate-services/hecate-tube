%% @doc RPC provider: tube.lookup_channel. Returns the current channel
%% snapshot plus a summary of its published clips -- the on-demand
%% refresh path for when a consumer's cached channel_announced_v1 fact
%% is suspected stale. Never confirms the existence of a channel id that
%% doesn't exist any more than the heartbeat already does.
-module(advertise_channel_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(#{<<"channel_id">> := ChannelId}, State) ->
    reply_from(project_tube_store:get_channel(ChannelId), ChannelId, State);
handle_request(_Payload, State) ->
    {error, bad_request, State}.

reply_from({ok, Row}, ChannelId, State) ->
    {reply, #{
        channel_id  => ChannelId,
        name        => maps:get(name, Row, undefined),
        description => maps:get(description, Row, undefined),
        owner       => maps:get(owner, Row, undefined),
        tags        => maps:get(tags, Row, []),
        logo_mcid   => maps:get(logo_mcid, Row, undefined),
        clips       => published_clip_summaries(ChannelId)
    }, State};
reply_from({error, not_found}, _ChannelId, State) ->
    {error, not_found, State}.

published_clip_summaries(ChannelId) ->
    [summary(C) || C <- project_tube_store:list_clips_by_channel(ChannelId),
                  maps:get(status, C, undefined) =:= <<"published">>].

summary(C) ->
    #{
        clip_id        => maps:get(clip_id, C, undefined),
        name           => maps:get(name, C, undefined),
        thumbnail_mcid => maps:get(thumbnail_mcid, C, undefined),
        view_count     => maps:get(view_count, C, 0)
    }.
