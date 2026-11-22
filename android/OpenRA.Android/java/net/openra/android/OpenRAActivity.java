package net.openra.android;

import org.libsdl.app.SDLActivity;

/**
 * Launches SDL. SDL loads libmain.so and calls SDL_main, which hands control
 * to the .NET code registered by OpenRAApplication (see android/native/main.c).
 */
public class OpenRAActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "main" };
    }
}
