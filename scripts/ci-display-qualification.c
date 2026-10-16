// Session-only display setup for an ephemeral graphical qualification runner.
#include <CoreGraphics/CoreGraphics.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void describe(CGDisplayModeRef mode) {
    printf("{\"id\":%" PRIu32 ",\"width\":%zu,\"height\":%zu,"
           "\"pixelWidth\":%zu,\"pixelHeight\":%zu}",
           (uint32_t)CGDisplayModeGetIODisplayModeID(mode), CGDisplayModeGetWidth(mode),
           CGDisplayModeGetHeight(mode), CGDisplayModeGetPixelWidth(mode),
           CGDisplayModeGetPixelHeight(mode));
}

int main(int argc, char **argv) {
    const char *ci = getenv("GITHUB_ACTIONS");
    if (!ci || strcmp(ci, "true") != 0) {
        fprintf(stderr, "Display setup is restricted to an ephemeral GitHub Mac\n");
        return 1;
    }
    uint32_t restore = 0;
    int restoring = 0;
    if (argc == 3 && strcmp(argv[1], "--restore") == 0) {
        restoring = 1;
        char *end = NULL;
        unsigned long value = strtoul(argv[2], &end, 10);
        if (!end || *end || value > UINT32_MAX) return 1;
        restore = (uint32_t)value;
    } else if (argc != 1) {
        return 1;
    }
    CGDirectDisplayID display = CGMainDisplayID();
    CGDisplayModeRef before = CGDisplayCopyDisplayMode(display);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, NULL);
    if (!before || !modes) {
        fprintf(stderr, "Display modes are unavailable\n");
        return 1;
    }
    CGDisplayModeRef chosen = NULL;
    size_t chosenArea = SIZE_MAX;
    printf("{\"displayId\":%" PRIu32 ",\"before\":", display);
    describe(before);
    printf(",\"available\":[");
    for (CFIndex i = 0; i < CFArrayGetCount(modes); ++i) {
        CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
        if (i) printf(",");
        describe(mode);
        size_t width = CGDisplayModeGetWidth(mode), height = CGDisplayModeGetHeight(mode);
        if (restoring && (uint32_t)CGDisplayModeGetIODisplayModeID(mode) == restore) chosen = mode;
        if (!restoring && width >= 1920 && height >= 1000 && width <= 2560 && height <= 1600 &&
            width * height < chosenArea) {
            chosen = mode;
            chosenArea = width * height;
        }
    }
    printf("]");
    CGError error = kCGErrorFailure;
    if (chosen) {
        CGDisplayConfigRef config = NULL;
        error = CGBeginDisplayConfiguration(&config);
        if (error == kCGErrorSuccess) {
            error = CGConfigureDisplayWithDisplayMode(config, display, chosen, NULL);
            if (error == kCGErrorSuccess) error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
            else CGCancelDisplayConfiguration(config);
        }
    }
    CGDisplayModeRef after = CGDisplayCopyDisplayMode(display);
    printf(",\"after\":");
    if (after) describe(after);
    else printf("null");
    printf(",\"errorCode\":%d,\"changed\":%s}\n", error,
           after && CGDisplayModeGetIODisplayModeID(after) != CGDisplayModeGetIODisplayModeID(before) ? "true" : "false");
    if (after) CGDisplayModeRelease(after);
    CFRelease(modes);
    CGDisplayModeRelease(before);
    return error == kCGErrorSuccess ? 0 : 2;
}
