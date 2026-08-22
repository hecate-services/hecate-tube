%% @doc Query: list a channel's clips (owner's own view -- every clip
%% regardless of publish status, so the owner can manage drafts; the
%% mesh-facing view is advertise_channel_lookup / advertise_video_clip_lookup,
%% which filter to published only).
%% Route: GET /api/tube/channels/:channel_id/clips
-module(get_video_clips_page_api).

-export([init/2, routes/0]).

routes() -> [{"/api/tube/channels/:channel_id/clips", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    ChannelId = cowboy_req:binding(channel_id, Req0),
    Clips = project_tube_store:list_clips_by_channel(ChannelId),
    Body = json:encode(#{ok => true, clips => Clips}),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
