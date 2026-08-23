%% @doc `video_clip_scan:probe/3' already computes duration/size
%% synchronously as part of every upload (see video_clip_scan.erl) --
%% these were computed and then discarded before ever reaching the
%% owner. This pins the formatting that now surfaces them in the
%% post-upload flash message.
-module(tube_video_clip_upload_page_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PAGE, tube_video_clip_upload_page).

format_duration_under_a_minute_test() ->
    ?assertEqual(<<"00:07">>, ?PAGE:format_duration(7_000)).

format_duration_over_a_minute_test() ->
    ?assertEqual(<<"01:23">>, ?PAGE:format_duration(83_000)).

format_duration_rounds_down_to_the_second_test() ->
    ?assertEqual(<<"00:01">>, ?PAGE:format_duration(1_999)).

format_size_under_a_megabyte_reads_as_kb_test() ->
    ?assertEqual(<<"512.0KB">>, ?PAGE:format_size(512_000)).

format_size_over_a_megabyte_reads_as_mb_test() ->
    ?assertEqual(<<"5.6MB">>, ?PAGE:format_size(5_618_695)).

accepted_message_with_no_scan_data_falls_back_to_the_bare_message_test() ->
    ?assertEqual(<<"Clip uploaded, private until you publish it.">>,
                 ?PAGE:accepted_message(undefined)).

accepted_message_with_scan_data_includes_duration_and_size_test() ->
    ?assertEqual(
       <<"Clip uploaded (01:23, 5.6MB), private until you publish it.">>,
       ?PAGE:accepted_message({83_000, 5_618_695})).
