# Throwaway F3/F4 validation fixture adjustments

This branch is for validation only and must not be merged. The fix PR does not
contain these adjustments or PR #47's files.

PR #47's test files and every assertion remain unchanged. No test assertion is
weakened, deleted or edited.

The generated F4 fixture is 18 seconds instead of six. The original six-second
file could end while the UI test was still checking for retired placeholders,
before its first `/Sessions` request. Eighteen seconds still finishes within the
existing 25-second end-of-playback allowance after the session is observed.

After checksummed ffmpeg installation and fixture generation, a validation-only
wrapper inserts `-readrate 1` before the media input. Jellyfin's generated job
therefore progresses over time instead of completing these tiny files in under
two seconds. Jellyfin 10.11.11 clears `TranscodingInfo` on DirectStream Playing and
Progress reports, and ffmpeg progress updates repopulate it. Pacing lets the
unchanged assertions observe the actual server metadata while playback runs.

The wrapper still executes the same verified ffmpeg binary. It changes only
input pacing, not codecs, output formats, playback reports, authentication or
assertion expectations. The existing artifact cleanup removes both executables.
