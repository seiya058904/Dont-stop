# CPU monitor semantics

Godot 4.7.2 accumulates process/physics maxima and publishes them approximately
once per second, then resets the accumulators. B11 reads those gauges each frame.
Its derived CPU percentiles are therefore frame-weighted samples of one-second
maxima, not percentiles of independent per-frame CPU durations.

Source: https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L4723-L4762

All original proxy-threshold failures remain failures and their raw data is kept.
Frame-delta latency is measured separately and is not relabelled. True per-frame
CPU duration is N/A through these shipped release monitors; GPU duration is N/A
without GPU timer instrumentation. Neither limitation is a performance pass.
