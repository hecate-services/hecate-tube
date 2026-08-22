%% @doc RPC provider: tube.lookup_video_clip. Returns clip metadata
%% including its current view count -- only for PUBLISHED clips. Never
%% confirms the existence of an unpublished or archived clip over RPC,
%% same privacy discipline as the streaming provider.
-module(advertise_video_clip_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(#{<<"clip_id">> := ClipId}, State) ->
    reply_from(project_tube_store:get_clip(ClipId), State);
handle_request(_Payload, State) ->
    {error, bad_request, State}.

reply_from({ok, #{status := <<"published">>} = Row}, State) ->
    {reply, #{
        clip_id        => maps:get(clip_id, Row, undefined),
        channel_id     => maps:get(channel_id, Row, undefined),
        name           => maps:get(name, Row, undefined),
        description    => maps:get(description, Row, undefined),
        tags           => maps:get(tags, Row, []),
        thumbnail_mcid => maps:get(thumbnail_mcid, Row, undefined),
        view_count     => maps:get(view_count, Row, 0)
    }, State};
reply_from({ok, _NotPublished}, State) ->
    {error, not_found, State};
reply_from({error, not_found}, State) ->
    {error, not_found, State}.
