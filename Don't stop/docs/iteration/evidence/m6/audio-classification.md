# Exit reference classification

Classification: **B — fixed audio teardown remainder**, not a growing gameplay node leak.

The isolated `M6AudioExit` scene has one AudioStreamPlayer and no game Main scene,
enemy, Boss, projectile, UI, or gameplay Tween. Twelve play/stop cycles report
2195 objects and 484 resources at every identical stopped sampling point. The
stream instance ID stays constant and its sampled reference count is 2.

Starting playback and immediately quitting the SceneTree reproduces exactly:

- `AudioStreamPlaybackMP3`, reference count 1;
- `AudioStreamMP3`, reference count 1;
- resource `res://audio/bgm/Cephalopod.mp3`.

The same twelve cycles followed by `Demo.quit_game()` stop audio and allow the
existing 0.1 second shutdown drain; that process exits without a leaked-object
or resource error. Logs: `audio-force.txt`, `audio-normal.txt`.

The engine version is 4.7.2 / `ed1daf0bf001b61586d9930840f2f1394092c079`.
Read-only inspection of that exact official source establishes the reference
chain and asynchronous release:

1. [AudioServer's playback list node](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/audio/audio_server.h#L277)
   holds a Ref to AudioStreamPlayback (line 300).
2. [MP3 playback creation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/modules/mp3/audio_stream_mp3.cpp#L201)
   stores a Ref to the AudioStreamMP3 resource in the playback object.
3. [Stopping playback](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/audio/audio_server.cpp#L1289)
   requests fade-out deletion; it does not synchronously unreference the stream.
4. [Playback deletion](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/audio/audio_server.cpp#L734)
   registers the main-thread destructor that unreferences playback. List cleanup
   is at line 1626, while `finish()` at line 1653 shuts down the audio drivers.

Thus the remaining owning chain is the AudioServer playback/deferred-cleanup
list to playback to MP3 resource; the exact two identities in the isolated
forced-exit log match it. No exit diagnostic was suppressed and no engine or
audio implementation was changed. The final long-run and regression indexes
separately report clean exit versus this specifically identified remainder;
other identities/errors remain failures.

GPU: `M6GPUCleanup` ran on Windows / AMD Radeon RX 7900 XT for 12 actual
shoot/return cycles, 24 assertions, zero failures. Enemies, transients and orphan
nodes were zero at each camp point. Texture memory stayed 55,281,952 bytes;
reported video memory ranged 82,090,656–82,090,880 bytes. No GPU RID leak was
reported at exit. Historical residuals: **NOT REPRODUCED**, not claimed fixed.
Unsupported source texture formats were converted by the renderer and logged
as warnings; they were not hidden. This short GPU experiment is not a 30-minute
GPU soak or human visual/audio acceptance. Subsequent work is headless only,
per the user's background-only steering.
