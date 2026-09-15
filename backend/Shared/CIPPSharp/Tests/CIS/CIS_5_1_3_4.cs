using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.3.4) — Users SHALL NOT be able to create Microsoft 365 groups. Port of
    /// Invoke-CippTestCIS_5_1_3_4. Single source: Settings (Group.Unified directory setting).
    /// </summary>
    public sealed class CIS_5_1_3_4 : ICippTest
    {
        public string Id => "CIS_5_1_3_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Settings cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? groupSetting = null;
            foreach (var s in settings.EnumerateArray())
            {
                if (StrEq(s, "templateId", "62375ab9-6b52-47ed-826b-58e47e0e304b")
                    || StrEq(s, "displayName", "Group.Unified"))
                {
                    groupSetting = s;
                    break;
                }
            }

            if (groupSetting == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No Group.Unified directory settings object exists, so the default applies (users can create Microsoft 365 groups). Set Users can create Microsoft 365 groups to No.");
            }

            // ($GroupSetting.values | Where name -eq 'EnableGroupCreation').value  — $null when absent.
            string? enableGroupCreation = null;
            foreach (var v in Arr(groupSetting.Value, "values"))
            {
                if (StrEq(v, "name", "EnableGroupCreation")) { enableGroupCreation = Str(v, "value"); break; }
            }

            // PS: "$EnableGroupCreation" -eq 'false' (case-insensitive; $null → "").
            if (string.Equals(enableGroupCreation ?? "", "false", System.StringComparison.OrdinalIgnoreCase))
            {
                return new CippTestResult(TestStatus.Passed,
                    "Users cannot create Microsoft 365 groups (EnableGroupCreation: false).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Users can create Microsoft 365 groups (EnableGroupCreation: {enableGroupCreation}).");
        }
    }
}
