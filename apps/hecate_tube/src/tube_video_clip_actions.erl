%% @doc Owner UI: publish/retract/archive a clip. Pure POST actions
%% triggered from buttons on the dashboard -- no page of their own, always
%% redirects back to `/'. One handler module for all three, distinguished
%% by the action atom carried in the route's own Opts (the third element
%% of each route tuple), matching the routes/0 aggregation pattern
%% query_tube_sup already uses.
%% Routes: POST /owner/clips/:clip_id/publish|retract|archive
-module(tube_video_clip_actions).

-export([init/2, routes/0]).

routes() ->
    [{"/owner/clips/:clip_id/publish", ?MODULE, publish},
     {"/owner/clips/:clip_id/retract", ?MODULE, retract},
     {"/owner/clips/:clip_id/archive", ?MODULE, archive}].

init(Req0, Action) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, Action);
        _          -> tube_owner_http:method_not_allowed(Req0, Action)
    end.

handle_post(Req0, Action) ->
    ClipId = cowboy_req:binding(clip_id, Req0),
    with_clip(project_tube_store:get_clip(ClipId), ClipId, Action, Req0).

with_clip({ok, Clip}, ClipId, Action, Req0) ->
    Params = #{clip_id => ClipId, channel_id => maps:get(channel_id, Clip, undefined)},
    reply_with_result(dispatch(Action, Params), Req0, Action);
with_clip({error, not_found}, _ClipId, Action, Req0) ->
    tube_owner_http:redirect(<<"/">>, <<"That clip no longer exists.">>, Req0, Action).

dispatch(publish, Params) -> maybe_publish_video_clip:dispatch(Params);
dispatch(retract, Params) -> maybe_retract_video_clip:dispatch(Params);
dispatch(archive, Params) -> maybe_archive_video_clip:dispatch(Params).

reply_with_result({ok, _Version, _Events}, Req0, Action) ->
    tube_owner_http:redirect(<<"/">>, <<"Done.">>, Req0, Action);
reply_with_result({error, Reason}, Req0, Action) ->
    tube_owner_http:redirect(<<"/">>,
        tube_owner_http:error_message(<<"Could not update the clip: ">>, Reason), Req0, Action).
