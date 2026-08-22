%% VideoClip status bit flags. Powers of two -- see evoq_bit_flags /
%% hecate-corpus's aggregate-status-fields convention.
-define(VIDEO_CLIP_UPLOADED,  1).
-define(VIDEO_CLIP_PUBLISHED, 2).
-define(VIDEO_CLIP_ARCHIVED,  4).
%% `uploaded' fires regardless of scan verdict (bytes genuinely landed
%% on disk either way) -- REJECTED is the terminal bit that keeps a
%% failed-scan clip from ever satisfying the "may publish" guard. No
%% separate ACCEPTED bit: `UPLOADED band not REJECTED' already means
%% exactly that, and the two are mutually exclusive/exhaustive given
%% the current event set.
-define(VIDEO_CLIP_REJECTED,  8).
