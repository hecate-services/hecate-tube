%% @doc Aggregates every owner-UI route into one list, mirroring
%% query_tube_sup's own routes/0 -- mounted by hecate_tube_sup alongside
%% query_tube's JSON API routes on the one HTTP listener this service owns.
-module(tube_owner_ui_routes).

-export([routes/0]).

-spec routes() -> [{string(), module(), term()}].
routes() ->
    tube_dashboard_page:routes() ++
    tube_channel_configure_page:routes() ++
    tube_video_clip_upload_page:routes() ++
    tube_video_clip_actions:routes() ++
    tube_owner_content_page:routes().
