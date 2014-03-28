# Sources and objects

export ANDROID_HOME=$(ANDROID_SDK)

ARCH = $(ANDROID_ABI)

SRC=vlc-android
JAVA_SOURCES=$(SRC)/src/org/videolan/vlc/*.java
JNI_SOURCES=$(SRC)/jni/*.c $(SRC)/jni/*.h
LIBVLCJNI=	\
	$(SRC)/obj/local/$(ARCH)/libvlcjni.so \
	$(SRC)/obj/local/$(ARCH)/libiomx-ics.so \
	$(SRC)/obj/local/$(ARCH)/libiomx-hc.so \
	$(SRC)/obj/local/$(ARCH)/libiomx-gingerbread.so \

LIBVLCJNI_H=$(SRC)/jni/libvlcjni.h

PRIVATE_LIBDIR=android-libs
PRIVATE_LIBS=$(PRIVATE_LIBDIR)/libstagefright.so $(PRIVATE_LIBDIR)/libmedia.so $(PRIVATE_LIBDIR)/libutils.so $(PRIVATE_LIBDIR)/libbinder.so

ifneq ($(V),)
ANT_OPTS += -v
VERBOSE =
GEN =
else
VERBOSE = @
GEN = @echo "Generating" $@;
endif

ifeq ($(RELEASE),1)
ANT_TARGET = release
VLC_APK=$(SRC)/bin/VLC-release-unsigned.apk
NDK_DEBUG=0
else
ANT_TARGET = debug
VLC_APK=$(SRC)/bin/VLC-debug.apk
NDK_DEBUG=1
endif

$(VLC_APK): $(LIBVLCJNI) $(JAVA_SOURCES)
	@echo
	@echo "=== Building $@ for $(ARCH) ==="
	@echo
	date +"%Y-%m-%d" > $(SRC)/assets/builddate.txt
	echo `id -u -n`@`hostname` > $(SRC)/assets/builder.txt
	git rev-parse --short HEAD > $(SRC)/assets/revision.txt
	./gen-env.sh $(SRC)
	$(VERBOSE)cd $(SRC) && ant $(ANT_OPTS) $(ANT_TARGET)

VLC_MODULES=`./find_modules.sh $(VLC_BUILD_DIR)`

$(LIBVLCJNI_H):
	$(VERBOSE)if [ -z "$(VLC_BUILD_DIR)" ]; then echo "VLC_BUILD_DIR not defined" ; exit 1; fi
	$(GEN)modules="$(VLC_MODULES)" ; \
	if [ -z "$$modules" ]; then echo "No VLC modules found in $(VLC_BUILD_DIR)/modules"; exit 1; fi; \
	DEFINITION=""; \
	BUILTINS="const void *vlc_static_modules[] = {\n"; \
	for file in $$modules; do \
		name=`echo $$file | sed 's/.*\.libs\/lib//' | sed 's/_plugin\.a//'`; \
		DEFINITION=$$DEFINITION"int vlc_entry__$$name (int (*)(void *, void *, int, ...), void *);\n"; \
		BUILTINS="$$BUILTINS vlc_entry__$$name,\n"; \
	done; \
	BUILTINS="$$BUILTINS NULL\n};\n"; \
	printf "/* Autogenerated from the list of modules */\n $$DEFINITION\n $$BUILTINS\n" > $@

$(PRIVATE_LIBDIR)/%.so: $(PRIVATE_LIBDIR)/%.c
	$(GEN)$(TARGET_TUPLE)-gcc $< -shared -o $@ --sysroot=$(ANDROID_NDK)/platforms/android-9/arch-$(PLATFORM_SHORT_ARCH)

$(PRIVATE_LIBDIR)/%.c: $(PRIVATE_LIBDIR)/%.symbols
	$(VERBOSE)rm -f $@
	$(GEN)for s in `cat $<`; do echo "void $$s() {}" >> $@; done

$(LIBVLCJNI): $(JNI_SOURCES) $(LIBVLCJNI_H) $(PRIVATE_LIBS)
	@if [ -z "$(VLC_BUILD_DIR)" ]; then echo "VLC_BUILD_DIR not defined" ; exit 1; fi
	@if [ -z "$(ANDROID_NDK)" ]; then echo "ANDROID_NDK not defined" ; exit 1; fi
	@echo
	@echo "=== Building libvlcjni ==="
	@echo
	$(VERBOSE)if [ -z "$(VLC_SRC_DIR)" ] ; then VLC_SRC_DIR=./vlc; fi ; \
	if [ -z "$(VLC_CONTRIB)" ] ; then VLC_CONTRIB="$$VLC_SRC_DIR/contrib/$(TARGET_TUPLE)"; fi ; \
	vlc_modules="$(VLC_MODULES)" ; \
	if [ `echo "$(VLC_BUILD_DIR)" | head -c 1` != "/" ] ; then \
		vlc_modules="`echo $$vlc_modules|sed \"s|$(VLC_BUILD_DIR)|../$(VLC_BUILD_DIR)|g\"`" ; \
        VLC_BUILD_DIR="../$(VLC_BUILD_DIR)"; \
	fi ; \
	[ `echo "$$VLC_CONTRIB" | head -c 1` != "/" ] && VLC_CONTRIB="../$$VLC_CONTRIB"; \
	[ `echo "$$VLC_SRC_DIR" | head -c 1` != "/" ] && VLC_SRC_DIR="../$$VLC_SRC_DIR"; \
	$(ANDROID_NDK)/ndk-build -C $(SRC) \
		VLC_SRC_DIR="$$VLC_SRC_DIR" \
		VLC_CONTRIB="$$VLC_CONTRIB" \
		VLC_BUILD_DIR="$$VLC_BUILD_DIR" \
		VLC_MODULES="$$vlc_modules" \
		NDK_DEBUG=$(NDK_DEBUG) \
		TARGET_CFLAGS="$$VLC_EXTRA_CFLAGS"

apkclean:
	rm -f $(VLC_APK)

lightclean:
	cd $(SRC) && rm -rf libs obj bin $(VLC_APK)
	rm -f $(PRIVATE_LIBDIR)/*.so $(PRIVATE_LIBDIR)/*.c

clean: lightclean
	rm -rf $(SRC)/gen java-libs/*/gen java-libs/*/bin .sdk vlc-sdk/ vlc-sdk.7z

jniclean: lightclean
	rm -f $(LIBVLCJNI) $(LIBVLCJNI_H)

distclean: clean jniclean

install: $(VLC_APK)
	@echo "=== Installing VLC on device ==="
	adb wait-for-device
	adb install -r $(VLC_APK)

uninstall:
	adb wait-for-device
	adb uninstall org.videolan.vlc

run:
	@echo "=== Running VLC on device ==="
	adb wait-for-device
ifeq ($(URL),)
	adb shell am start -n org.videolan.vlc/org.videolan.vlc.gui.MainActivity
else
	adb shell am start -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity $(URL)
endif

build-and-run: install run

apkclean-run: apkclean build-and-run
	adb logcat -c

distclean-run: distclean build-and-run
	adb logcat -c

vlc-sdk.7z: .sdk
	7z a $@ vlc-sdk/

.sdk:
	mkdir -p vlc-sdk/libs
	cd vlc-android; cp -r libs/* ../vlc-sdk/libs
	mkdir -p vlc-sdk/src/org/videolan
	cp -r vlc-android/src/org/videolan/libvlc vlc-sdk/src/org/videolan
	touch $@

.PHONY: lightclean clean jniclean distclean distclean-run apkclean apkclean-run install run build-and-run
