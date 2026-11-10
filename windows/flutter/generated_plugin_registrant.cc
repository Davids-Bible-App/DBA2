//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <filegate/filegate_plugin_c_api.h>
#include <just_audio_windows_plus/just_audio_windows_plus_plugin.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <window_manager/window_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FilegatePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FilegatePluginCApi"));
  JustAudioWindowsPlusPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("JustAudioWindowsPlusPlugin"));
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
}
