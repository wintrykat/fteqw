/*
 * ffmpeg6-compat.h — build-time shim for the avplug/ffmpeg plugin on FFmpeg < 7.1.
 *
 * WHY: upstream FTE's plugins/avplug/avencode.c calls
 *          avcodec_get_supported_config(..., AV_CODEC_CONFIG_SAMPLE_FORMAT, ...)
 *      unconditionally (see line ~339). That API landed in libavcodec 61.13.100
 *      (FFmpeg 7.1). Ubuntu 24.04 — our reference arm64 host — ships libavcodec 60
 *      (FFmpeg 6.1), which lacks both the function and the enum, so the plugin
 *      fails to compile. macOS builds fine only because Homebrew's ffmpeg is 7.x.
 *
 * HOW: rather than edit engine-tree source (the fork stays thin — the Linux port's
 *      promise is *zero* engine/plugin source edits, see docs/PORTING-LINUX.md §5),
 *      build-plugins.sh force-includes this header into the ffmpeg plugin compile
 *      via `CFLAGS += -include …`. Pre-7.1 it supplies the enum + a faithful
 *      pre-7.1 implementation (the codec's static sample-format list, which is
 *      exactly what the new call returns for AV_CODEC_CONFIG_SAMPLE_FORMAT). On
 *      libavcodec >= 61.13 the whole file is inert, so it is safe to inject
 *      unconditionally and to leave in place once distros ship FFmpeg 7.1.
 *
 * TEST: linux/tests/40-plugins.sh builds and loads the ffmpeg plugin; a red line
 *      there on an FFmpeg bump points back here.
 */
#ifndef FTEQW_LINUX_FFMPEG6_COMPAT_H
#define FTEQW_LINUX_FFMPEG6_COMPAT_H

/*
 * GATE ON FTEPLUGIN — do not remove.
 * This header is force-included through CFLAGS, and the engine Makefile feeds the
 * SAME $(CFLAGS) to a config-extraction step that preprocesses a config header
 * (FTE_CONFIG_EXTRA := $(shell $(CC) -E -P … $(CFLAGS) common/config_*.h),
 * engine/Makefile ~line 131). If <libavcodec/*> were pulled into that step its
 * entire expansion would be captured into FTE_CONFIG_EXTRA (~160 KB) and then
 * exported into a recipe environment, overflowing the arg list ("Argument list
 * too long"). Plugin translation units define FTEPLUGIN; the config-extraction
 * step does not — so gating the whole body on it keeps this file inert everywhere
 * except an actual plugin compile.
 */
#ifdef FTEPLUGIN

#include <libavcodec/version.h>

#if LIBAVCODEC_VERSION_INT < AV_VERSION_INT(61, 13, 100)
#include <libavcodec/avcodec.h>

/* The config selector added with the new API (FFmpeg 7.1). avencode.c only ever
 * asks for AV_CODEC_CONFIG_SAMPLE_FORMAT; the rest are declared for completeness
 * so the enum type is valid. */
enum AVCodecConfig {
	AV_CODEC_CONFIG_PIX_FORMAT,      /* AVPixelFormat */
	AV_CODEC_CONFIG_FRAME_RATE,      /* AVRational    */
	AV_CODEC_CONFIG_SAMPLE_RATE,     /* int           */
	AV_CODEC_CONFIG_SAMPLE_FORMAT,   /* AVSampleFormat */
	AV_CODEC_CONFIG_CHANNEL_LAYOUT,  /* AVChannelLayout */
	AV_CODEC_CONFIG_COLOR_RANGE,     /* AVColorRange  */
	AV_CODEC_CONFIG_COLOR_SPACE,     /* AVColorSpace  */
};

/* Pre-7.1 equivalent of avcodec_get_supported_config() for the one selector the
 * plugin uses. FFmpeg 6.x exposes the supported sample formats as the codec's
 * NULL/AV_SAMPLE_FMT_NONE-terminated static AVCodec.sample_fmts array. */
static inline int avcodec_get_supported_config(const AVCodecContext *avctx,
		const AVCodec *codec, enum AVCodecConfig config, unsigned int flags,
		const void **out_configs, int *out_num_configs)
{
	const AVCodec *c = codec ? codec : (avctx ? avctx->codec : NULL);
	const void *list = NULL;
	int n = 0;
	(void)flags;
	if (config == AV_CODEC_CONFIG_SAMPLE_FORMAT && c && c->sample_fmts) {
		const enum AVSampleFormat *f = c->sample_fmts;
		while (f[n] != AV_SAMPLE_FMT_NONE)
			n++;
		list = f;
	}
	if (out_configs)
		*out_configs = list;
	if (out_num_configs)
		*out_num_configs = n;
	return 0;
}
#endif /* libavcodec < 61.13.100 */

#endif /* FTEPLUGIN */

#endif /* FTEQW_LINUX_FFMPEG6_COMPAT_H */
