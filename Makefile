# Compile FFmpeg and all its dependencies to JavaScript.
# You need emsdk environment installed and activated, see:
# <https://kripken.github.io/emscripten-site/docs/getting_started/downloads.html>.

PRE_JS = build/pre.js
POST_JS_SYNC = build/post-sync.js
POST_JS_WORKER = build/post-worker.js


# Filters can be used as -f...
FILTERS = scale aresample afade

# Required for concat h264 video segments.
BSF = h264_mp4toannexb


# The file formats can be recognized.
# `avi mov flv` must be included to join h264 segments.
DEMUXERS = matroska ogg avi mov flv mp3 image2 concat

# For decode file contents.
# Note that `vp9` is not equals to `libvpx_vp9`, only `libvpx_vp9` supports alpha channel.
# Note that `libvpx-vp9` is not working, but after compiled, `libvpx-vp9` and `vp9` both works when specifies codec.
DECODERS = libvpx_vp9 h264 opus mp3 aac mjpeg png


# The file format can be generated.
MUXERS = mp4 mp3 null image2

# The codecs can be used when generate files.
ENCODERS = libx264 libmp3lame aac mjpeg png


FFMPEG_BC = build/ffmpeg/ffmpeg.bc
FFMPEG_PC_PATH = ../x264/dist/lib/pkgconfig

SHARED_DEPS = \
	build/lame/dist/lib/libmp3lame.so \
	build/x264/dist/lib/libx264.so \
	build/libvpx/dist/lib/libvpx.so

all: ffmpeg.js ffmpeg-worker.js

clean: clean-js \
	clean-opus clean-libvpx \
	clean-lame clean-x264 clean-ffmpeg
clean-js:
	rm -f ffmpeg*.js
clean-opus:
	cd build/opus && git clean -xdf
clean-libvpx:
	cd build/libvpx && git clean -xdf
clean-lame:
	cd build/lame && git clean -xdf
clean-x264:
	cd build/x264 && git clean -xdf
clean-ffmpeg:
	cd build/ffmpeg && git clean -xdf

build/opus/configure:
	cd build/opus && ./autogen.sh

build/opus/dist/lib/libopus.so: build/opus/configure
	cd build/opus && \
	emconfigure ./configure \
		CFLAGS=-O3 \
		--prefix="$$(pwd)/dist" \
		--disable-static \
		--disable-doc \
		--disable-extra-programs \
		--disable-asm \
		--disable-rtcd \
		--disable-intrinsics \
		--disable-hardening \
		--disable-stack-protector \
		&& \
	emmake make -j && \
	emmake make install

# `disable-vp9-encoder` can reduce about 12KB wasm size.
build/libvpx/dist/lib/libvpx.so:
	cd build/libvpx && \
	git reset --hard && \
	patch -p1 < ../libvpx-fix-ld.patch && \
	emconfigure ./configure \
		--prefix="$$(pwd)/dist" \
		--target=generic-gnu \
		--disable-dependency-tracking \
		--disable-multithread \
		--disable-runtime-cpu-detect \
		--enable-shared \
		--disable-static \
		\
		--disable-examples \
		--disable-docs \
		--disable-unit-tests \
		--disable-webm-io \
		--disable-libyuv \
		--disable-vp8 \
		--disable-vp9-encoder \
		&& \
	emmake make -j && \
	emmake make install

build/lame/dist/lib/libmp3lame.so:
	cd build/lame/lame && \
	git reset --hard && \
	patch -p2 < ../../lame-fix-ld.patch && \
	emconfigure ./configure \
		CFLAGS="-DNDEBUG -O3" \
		--prefix="$$(pwd)/../dist" \
		--host=x86-none-linux \
		--disable-static \
		\
		--disable-gtktest \
		--disable-analyzer-hooks \
		--disable-decoder \
		--disable-frontend \
		&& \
	emmake make -j && \
	emmake make install

build/x264/dist/lib/libx264.so:
	cd build/x264 && \
	emconfigure ./configure \
		--prefix="$$(pwd)/dist" \
		--extra-cflags="-Wno-unknown-warning-option" \
		--host=x86-none-linux \
		--disable-cli \
		--enable-shared \
		--disable-opencl \
		--disable-thread \
		--disable-interlaced \
		--bit-depth=8 \
		--chroma-format=420 \
		--disable-asm \
		\
		--disable-avs \
		--disable-swscale \
		--disable-lavf \
		--disable-ffms \
		--disable-gpac \
		--disable-lsmash \
		&& \
	emmake make -j && \
	emmake make install

# TODO(Kagami): Emscripten documentation recommends to always use shared
# libraries but it's not possible in case of ffmpeg because it has
# multiple declarations of `ff_log2_tab` symbol. GCC builds FFmpeg fine
# though because it uses version scripts and so `ff_log2_tag` symbols
# are not exported to the shared libraries. Seems like `emcc` ignores
# them. We need to file bugreport to upstream. See also:
# - <https://kripken.github.io/emscripten-site/docs/compiling/Building-Projects.html>
# - <https://github.com/kripken/emscripten/issues/831>
# - <https://ffmpeg.org/pipermail/libav-user/2013-February/003698.html>
COMMON_FFMPEG_ARGS = \
	--cc=emcc \
	--ranlib=emranlib \
	--enable-cross-compile \
	--target-os=none \
	--arch=x86 \
	--disable-runtime-cpudetect \
	--disable-asm \
	--disable-fast-unaligned \
	--disable-pthreads \
	--disable-w32threads \
	--disable-os2threads \
	--disable-debug \
	--disable-stripping \
	--disable-safe-bitstream-reader \
	\
	--disable-all \
	--enable-ffmpeg \
	--enable-avcodec \
	--enable-avformat \
	--enable-avfilter \
	--enable-avutil \
	--enable-swresample \
	--enable-swscale \
	--disable-network \
	--disable-d3d11va \
	--disable-dxva2 \
	--disable-vaapi \
	--disable-vdpau \
	$(addprefix --enable-decoder=,$(DECODERS)) \
	$(addprefix --enable-demuxer=,$(DEMUXERS)) \
	--enable-protocol=file \
	$(addprefix --enable-filter=,$(FILTERS)) \
	$(addprefix --enable-bsf=,$(BSF)) \
	--disable-bzlib \
	--disable-iconv \
	--disable-libxcb \
	--disable-lzma \
	--disable-sdl2 \
	--disable-securetransport \
	--disable-xlib \
	--enable-zlib

build/ffmpeg/ffmpeg.bc: $(SHARED_DEPS)
	cd build/ffmpeg && \
	EM_PKG_CONFIG_PATH=$(FFMPEG_PC_PATH) emconfigure ./configure \
		$(COMMON_FFMPEG_ARGS) \
		$(addprefix --enable-encoder=,$(ENCODERS)) \
		$(addprefix --enable-muxer=,$(MUXERS)) \
		--enable-gpl \
		--enable-libmp3lame \
		--enable-libx264 \
		--enable-libvpx \
		--extra-cflags="-s USE_ZLIB=1 -I../lame/dist/include -I../libvpx/dist/include" \
		--extra-ldflags="-L../lame/dist/lib -L../libvpx/dist/lib" \
		&& \
	emmake make -j && \
	cp ffmpeg ffmpeg.bc

EMCC_ARGS = \
	-O3 \
	--closure 1 \
	-s WASM=1 \
	-s WASM_ASYNC_COMPILATION=0 \
	-s ASSERTIONS=0 \
	-s EXIT_RUNTIME=1 \
	-s NODEJS_CATCH_EXIT=0 \
	-s NODEJS_CATCH_REJECTION=0 \
	-s TOTAL_MEMORY=67108864 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-lnodefs.js -lworkerfs.js \
	--pre-js $(PRE_JS) \
	-o $@

ffmpeg.js: $(FFMPEG_BC) $(PRE_JS) $(POST_JS_SYNC)
	emcc $(FFMPEG_BC) $(SHARED_DEPS) \
		--post-js $(POST_JS_SYNC) \
		$(EMCC_ARGS)

ffmpeg-worker.js: $(FFMPEG_BC) $(PRE_JS) $(POST_JS_WORKER)
	emcc $(FFMPEG_BC) $(SHARED_DEPS) \
		--post-js $(POST_JS_WORKER) \
		$(EMCC_ARGS)
