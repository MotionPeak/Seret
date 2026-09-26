#import <Foundation/Foundation.h>
#import <VLCKit/VLCKit.h>

/// The little of libvlc's C API that VLCKit does not surface, for the subtitle auto-sync probe.
///
/// VLCKit has no way to hand back decoded audio. libvlc does — `libvlc_audio_set_callbacks` — and
/// the symbols are exported from the framework binary (verified with `nm`: 310 `libvlc_*` symbols,
/// these among them). What is missing is a declaration: the framework ships `vlc/*.h` but its
/// module map EXCLUDES every one of them, so they cannot be imported.
///
/// So they are declared here instead, deliberately and minimally. The player handle is typed
/// `void *` because that is exactly what VLCKit's own bridging category calls it, and it keeps this
/// file free of any libvlc struct definition that could drift from the binary. Only the function
/// signatures have to match, and they are copied from the header the framework ships.
///
/// The whole file is one audited nullability region: every otherwise-unmarked pointer below
/// (`mp`, `format`) is therefore implicitly `_Nonnull`. `data` is explicitly `_Nullable` on every
/// callback (it is `opaque` handed back, and libvlc itself may pass it as null); `samples` is
/// `_Nullable` too — the Swift play callback (`AudioActivityProbe.swift`) unwraps both with a single
/// `guard let data, let samples`.
NS_ASSUME_NONNULL_BEGIN

/// The raw `libvlc_media_player_t *` behind a `VLCMediaPlayer`.
///
/// VLCKit declares this in its own private `VLCLibVLCBridging.h`, which is not in the module either.
/// Re-declaring the category compiles against the public class and binds at runtime to the
/// implementation already in the framework — no private header import, nothing to keep in step but
/// the name.
@interface VLCMediaPlayer (SeretLibVLCBridge)
@property (readonly) void *libVLCMediaPlayer;
@end

typedef void (*seret_audio_play_cb)(void *_Nullable data, const void *_Nullable samples,
                                    unsigned count, int64_t pts);
typedef void (*seret_audio_pause_cb)(void *_Nullable data, int64_t pts);
typedef void (*seret_audio_resume_cb)(void *_Nullable data, int64_t pts);
typedef void (*seret_audio_flush_cb)(void *_Nullable data, int64_t pts);
typedef void (*seret_audio_drain_cb)(void *_Nullable data);

/// Route decoded audio to `play` instead of to a sound device.
void libvlc_audio_set_callbacks(void *mp,
                                seret_audio_play_cb _Nullable play,
                                seret_audio_pause_cb _Nullable pause,
                                seret_audio_resume_cb _Nullable resume,
                                seret_audio_flush_cb _Nullable flush,
                                seret_audio_drain_cb _Nullable drain,
                                void *_Nullable opaque);

/// Fix the sample format the callback receives — "S16N" is native-endian signed 16-bit.
int libvlc_audio_set_format(void *mp, const char *format, unsigned rate, unsigned channels);

NS_ASSUME_NONNULL_END
