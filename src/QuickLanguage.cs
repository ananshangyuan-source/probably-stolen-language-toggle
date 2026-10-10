using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Text.Json;
using BepInEx;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using Il2CppInterop.Runtime.Injection;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using TMPro;
using UnityEngine;
using UnityEngine.Localization;
using UnityEngine.Localization.Settings;
using UnityEngine.Localization.Tables;
using UnityEngine.ResourceManagement.AsyncOperations;
using UnityEngine.AddressableAssets;
using UnityEngine.UI;
using Object = UnityEngine.Object;
using TargetLocale = UnityEngine.Localization.Locale;

namespace ProbablyStolenQuickLanguage
{
    [BepInPlugin("local.quicklanguage.probablystolen", "Quick Language EN-ZH Recovery", "1.0.3")]
    public class Plugin : BasePlugin
    {
        public static Plugin Instance;
        public override void Load()
        {
            Instance = this;
            LanguageController.Instance = new LanguageController();
            Log.LogInfo("Managed controller created; patching UI frame callback...");
            var harmony = new Harmony("local.quicklanguage.probablystolen");
            harmony.CreateClassProcessor(typeof(UIFrameCallback)).Patch();
            Log.LogInfo("Global text replacement and localization interception are disabled. Item text stays native.");
            Log.LogInfo("Q language toggle loaded. Uses bundled translations; no network or save editing.");
        }
    }

    public class LanguageController
    {
        public static LanguageController Instance;
        readonly Dictionary<string, string> toEnglish = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly Dictionary<string, string> toChinese = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly Dictionary<string, string> rewriteCache = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly Dictionary<string, string[]> entriesByKey = new Dictionary<string, string[]>();
        Regex englishPattern, chinesePattern;
        TargetLocale english, chinese;
        bool loading, ready, refreshing;
        float lastPoll;
        float lastError;
        string diagnosticDirectory;
        public LanguageController()
        {
            Instance = this;
            diagnosticDirectory = Path.Combine(Paths.BepInExRootPath, "quick-language");
            Directory.CreateDirectory(diagnosticDirectory);
        }
        public void Update()
        {
            try
            {
                if (!loading) BeginPreload();
                if (ready && Input.GetKeyDown(KeyCode.Q) && !IsTyping()) Toggle();
                if (Time.unscaledTime - lastPoll > 0.5f)
                {
                    lastPoll = Time.unscaledTime;
                    var commandPath = Path.Combine(diagnosticDirectory, "command.txt");
                    if (File.Exists(commandPath))
                    {
                        var command = File.ReadAllText(commandPath).Trim();
                        File.Delete(commandPath);
                        if (command == "dump") Dump("dump");
                        else if (ready && command == "toggle") Toggle();
                        else if (ready && (command == "en" || command == "zh")) Switch(command);
                    }
                }
            }
            catch (Exception ex)
            {
                if (Time.unscaledTime - lastError > 10f) { lastError = Time.unscaledTime; Plugin.Instance.Log.LogError(ex); }
            }
        }
        void BeginPreload()
        {
            if (Time.realtimeSinceStartup < 5f) return;
            var locales = LocalizationSettings.AvailableLocales.Locales;
            for (int i = 0; i < locales.Count; i++)
            {
                var locale = locales[i];
                if (locale.Identifier.Code == "en") english = locale;
                if (locale.Identifier.Code == "zh") chinese = locale;
            }
            if (english == null || chinese == null) return;
            loading = true;
            var rows = JsonSerializer.Deserialize<List<string[]>>(File.ReadAllText(Path.Combine(Paths.PluginPath, "language-pairs.json")));
            foreach (var row in rows)
            {
                entriesByKey[row[0] + "\n" + row[1]] = new[] { row[2], row[3] };
                if (!row[2].Contains("{") && !row[3].Contains("{")) Remember(row[2], row[3]);
            }
            FinishPreload();
        }
        void FinishPreload()
        {
            englishPattern = MakePattern(toEnglish.Keys);
            chinesePattern = MakePattern(toChinese.Keys);
            ready = true;
            Plugin.Instance.Log.LogInfo("Preloaded " + entriesByKey.Count + " bilingual entries; " + toEnglish.Count + " text pairs. Q is ready.");
            Dump("ready");
        }
        static Regex MakePattern(IEnumerable<string> keys)
        {
            var terms = keys.Where(x => x.Length >= 2 && x.Length < 10000)
                .OrderByDescending(x => x.Length).Select(x =>
                {
                    var escaped = Regex.Escape(x);
                    if (Regex.IsMatch(x, "^[A-Za-z0-9 ]+$")) escaped = "(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])";
                    return escaped;
                });
            var pattern = string.Join("|", terms);
            return pattern.Length == 0 ? null : new Regex(pattern, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
        }
        void Remember(string en, string zh)
        {
            if (string.IsNullOrWhiteSpace(en) || string.IsNullOrWhiteSpace(zh) || en == zh) return;
            toChinese[en] = zh; toEnglish[zh] = en;
        }
        public void Capture(string table, string key, Il2CppReferenceArray<Il2CppSystem.Object> args, string result)
        {
            if (!ready || refreshing || string.IsNullOrEmpty(result)) return;
            try
            {
                string[] pair;
                if (!entriesByKey.TryGetValue(table + "\n" + key, out pair)) return;
                var values = new object[args?.Length ?? 0];
                for (int i = 0; i < values.Length; i++) values[i] = args[i]?.ToString() ?? "";
                var en = values.Length == 0 ? pair[0] : string.Format(pair[0], values);
                var zh = values.Length == 0 ? pair[1] : string.Format(pair[1], values);
                Remember(en, zh);
                rewriteCache.Remove("en\n" + zh); rewriteCache.Remove("zh\n" + en);
            }
            catch { /* Missing entries retain the original game fallback. */ }
        }
        public string Translate(string text, string target)
        {
            if (!ready || string.IsNullOrEmpty(text)) return text;
            var dictionary = target == "zh" ? toChinese : toEnglish;
            string exact;
            if (dictionary.TryGetValue(text, out exact)) return exact;
            var cacheKey = target + "\n" + text;
            if (rewriteCache.TryGetValue(cacheKey, out exact)) return exact;
            var pattern = target == "zh" ? chinesePattern : englishPattern;
            string result = text;
            try
            {
                if (pattern != null)
                {
                    var chunks = Regex.Split(text, "(<[^>]*>)");
                    for (int i = 0; i < chunks.Length; i += 2)
                        chunks[i] = pattern.Replace(chunks[i], m => dictionary[m.Value]);
                    result = string.Concat(chunks);
                }
            }
            catch (RegexMatchTimeoutException) { return text; }
            if (rewriteCache.Count > 6000) rewriteCache.Clear();
            rewriteCache[cacheKey] = result;
            return result;
        }
        static bool IsTyping()
        {
            foreach (var input in Object.FindObjectsOfType<TMP_InputField>()) if (input.isFocused) return true;
            foreach (var input in Object.FindObjectsOfType<InputField>()) if (input.isFocused) return true;
            return false;
        }
        public string CurrentCode => LocalizationSettings.SelectedLocale?.Identifier.Code ?? "en";
        public bool Ready => ready;
        public bool Refreshing => refreshing;
        void Toggle() => Switch(CurrentCode == "zh" ? "en" : "zh");
        void Switch(string target)
        {
            var clock = Stopwatch.StartNew();
            var snapshots = Object.FindObjectsOfType<TMP_Text>().Select(t => new KeyValuePair<TMP_Text,string>(t,t.text)).ToArray();
            int changed = 0;
            refreshing = true;
            try
            {
                LocalizationSettings.SelectedLocale = target == "zh" ? chinese : english;
                foreach (var localizer in Object.FindObjectsOfType<TMPLocalizer>())
                {
                    if (localizer.textMeshPro == null) continue;
                    try
                    {
                        var fonts = FontLoader.Instance;
                        if (fonts != null) localizer.textMeshPro.font = fonts.GetFontByRole(localizer.fontRole, LocalizationSettings.SelectedLocale);
                    }
                    catch { /* Incomplete optional widgets keep their current usable font. */ }
                }
                foreach (var snapshot in snapshots)
                {
                    if (snapshot.Key == null) continue;
                    // Custom item windows contain layered rich text and layout data.
                    // Rewriting their rendered strings can hide category words or clip lines.
                    if (snapshot.Key.GetComponent<TreeNodeRender>() != null || snapshot.Key.GetComponentInParent<TreeNodeRender>() != null) continue;
                    var translated = Translate(snapshot.Value, target);
                    if (translated != snapshot.Value)
                    {
                        snapshot.Key.text = translated;
                        changed++;
                    }
                }
                var menu = MainMenuUIController.Instance;
                if (menu != null && menu.localeDropdown != null)
                {
                    for (int i = 0; i < menu.localeDropdown.options.Count; i++)
                    {
                        var label = menu.localeDropdown.options[i].text;
                        if ((target == "en" && label.Contains("English")) ||
                            (target == "zh" && Regex.IsMatch(label, "Chinese|中文|简体")))
                        { menu.localeDropdown.SetValueWithoutNotify(i); menu.localeDropdown.RefreshShownValue(); break; }
                    }
                }
                Canvas.ForceUpdateCanvases();
            }
            finally { refreshing = false; }
            clock.Stop();
            Plugin.Instance.Log.LogInfo("Language " + target + ": updated " + changed + " cached labels in " + clock.ElapsedMilliseconds + " ms.");
            Dump("switched-" + target);
        }
        void Dump(string state)
        {
            var lines = new List<string> { "State=" + state, "Locale=" + CurrentCode, "Ready=" + ready, "Entries=" + entriesByKey.Count };
            foreach (var text in Object.FindObjectsOfType<TMP_Text>())
            {
                if (!text.gameObject.activeInHierarchy || string.IsNullOrWhiteSpace(text.text)) continue;
                lines.Add(text.gameObject.name + "\t" + text.text.Replace("\n", "\\n").Replace("\r", ""));
            }
            File.WriteAllLines(Path.Combine(diagnosticDirectory, "status.txt"), lines);
        }
    }

    [HarmonyPatch(typeof(CanvasUpdateRegistry), "PerformUpdate")]
    public static class UIFrameCallback
    {
        static int lastFrame = -1;
        static void Postfix()
        {
            if (lastFrame == Time.frameCount) return;
            lastFrame = Time.frameCount;
            LanguageController.Instance?.Update();
        }
    }

    [HarmonyPatch(typeof(LocHelper), "Get")]
    public static class LocalizationCapture
    {
        static void Postfix(string table, string key, Il2CppReferenceArray<Il2CppSystem.Object> arguments, string __result)
            => LanguageController.Instance?.Capture(table, key, arguments, __result);
    }
    [HarmonyPatch(typeof(TMP_Text), "set_text")]
    public static class CachedTextRefresh
    {
        static void Prefix(ref string value)
        {
            var controller = LanguageController.Instance;
            if (controller != null && controller.Ready && !controller.Refreshing)
                value = controller.Translate(value, controller.CurrentCode);
        }
    }

}
