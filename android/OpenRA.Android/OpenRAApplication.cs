using System;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Android.App;
using Android.Runtime;
using OpenRA;

namespace OpenRADroid
{
	/// <summary>
	/// Starts before any activity. Registers the game's entry point with libmain.so so that
	/// SDL's game thread can run OpenRA once SDLActivity has created the window.
	/// </summary>
	[Application(Name = "net.openra.android.OpenRAApplication")]
	public class OpenRAApplication : Application
	{
		const string Tag = "OpenRA";

		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		delegate int MainDelegate(int argc, IntPtr argv);

		[DllImport("main")]
		static extern void openra_set_main(MainDelegate fn);

		// Kept in a static field so the delegate is never garbage collected.
		static MainDelegate mainDelegate;

		static string filesDir;
		static global::Android.Content.Res.AssetManager assets;
		static float density = 1f;

		public OpenRAApplication(IntPtr handle, JniHandleOwnership transfer)
			: base(handle, transfer) { }

		public override void OnCreate()
		{
			base.OnCreate();

			filesDir = FilesDir.AbsolutePath;
			assets = Assets;
			density = Resources.DisplayMetrics.Density;

			mainDelegate = RunGame;
			openra_set_main(mainDelegate);
			global::Android.Util.Log.Info(Tag, "Managed entry point registered");
		}

		static int RunGame(int argc, IntPtr argv)
		{
			try
			{
				var engineDir = Path.Combine(filesDir, "engine");
				var supportDir = Path.Combine(filesDir, "support");

				ExtractEngine(engineDir);
				Directory.CreateDirectory(supportDir);

				Environment.SetEnvironmentVariable("OPENRA_ANDROID", "1");

				// Scale the UI so it is readable on high density tablet/phone screens.
				var scale = Math.Max(1f, density * 0.75f);
				Environment.SetEnvironmentVariable("OPENRA_DISPLAY_SCALE", scale.ToString(CultureInfo.InvariantCulture));

				OpenRA.Platform.OverrideEngineDir(engineDir);
				OpenRA.Platform.OverrideSupportDir(supportDir);

				global::Android.Util.Log.Info(Tag, $"Starting OpenRA (engine: {engineDir}, support: {supportDir}, scale: {scale})");
				return (int)OpenRA.Game.InitializeAndRun(new[] { "Game.Mod=ra" });
			}
			catch (Exception e)
			{
				global::Android.Util.Log.Error(Tag, "OpenRA crashed: " + e);
				return 1;
			}
			finally
			{
				OpenRA.Log.Dispose();
			}
		}

		/// <summary>
		/// The engine data (mods, shaders) ships as one zip inside the APK.
		/// Unpack it on first launch, and again whenever the APK carries a new build.
		/// </summary>
		static void ExtractEngine(string engineDir)
		{
			string bundledVersion;
			using (var reader = new StreamReader(assets.Open("engine.version")))
				bundledVersion = reader.ReadToEnd().Trim();

			var versionFile = Path.Combine(engineDir, ".android-version");
			if (File.Exists(versionFile) && File.ReadAllText(versionFile).Trim() == bundledVersion)
				return;

			global::Android.Util.Log.Info(Tag, $"Extracting engine data ({bundledVersion})");

			if (Directory.Exists(engineDir))
				Directory.Delete(engineDir, true);

			Directory.CreateDirectory(engineDir);

			// ZipArchive needs a seekable stream; APK assets are not, so copy to a temp file first.
			var tempZip = Path.Combine(filesDir, "engine.zip.tmp");
			using (var input = assets.Open("engine.zip"))
			using (var output = File.Create(tempZip))
				input.CopyTo(output);

			ZipFile.ExtractToDirectory(tempZip, engineDir);
			File.Delete(tempZip);

			File.WriteAllText(versionFile, bundledVersion);
		}
	}
}
