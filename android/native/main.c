/*
 * libmain.so: the bridge between SDL's Android activity and the .NET game code.
 *
 * SDLActivity loads this library and calls SDL_main() on its game thread.
 * OpenRAApplication (C#) registers the managed entry point beforehand with
 * openra_set_main(), so SDL_main simply forwards to it.
 */
#include <stddef.h>
#include <android/log.h>

typedef int (*openra_main_fn)(int argc, char **argv);

static openra_main_fn managed_main = NULL;

__attribute__((visibility("default")))
void openra_set_main(openra_main_fn fn)
{
    managed_main = fn;
}

__attribute__((visibility("default")))
int SDL_main(int argc, char **argv)
{
    if (managed_main == NULL)
    {
        __android_log_print(ANDROID_LOG_ERROR, "OpenRA", "SDL_main called before the managed entry point was registered");
        return 1;
    }

    return managed_main(argc, argv);
}
