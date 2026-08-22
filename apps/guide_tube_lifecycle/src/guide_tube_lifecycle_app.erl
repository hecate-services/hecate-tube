%% @doc OTP application entry for the CMD department.
-module(guide_tube_lifecycle_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> guide_tube_lifecycle_sup:start_link().

stop(_State) -> ok.
