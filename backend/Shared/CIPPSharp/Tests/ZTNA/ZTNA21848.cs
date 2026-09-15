using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Add organizational terms to the banned password list.
    /// Port of Invoke-CippTestZTNA21848. The password-protection directory setting must enable the
    /// banned-password check and carry a non-empty custom banned password list.
    /// </summary>
    public sealed class ZTNA21848 : ICippTest
    {
        private const string TemplateId = "5cf42378-d67d-4f36-ba46-e8b86229381d";
        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/";
        private const int MaxDisplay = 10;

        public string Id => "ZTNA21848";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            JsonElement settings = default;
            bool found = false;
            foreach (var s in Items(data.Get("Settings")))
                if (StrEq(s, "templateId", TemplateId)) { settings = s; found = true; break; }

            if (!found)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            string? enableRaw = null;
            string? bannedList = null;
            foreach (var v in Arr(settings, "values"))
            {
                var name = Str(v, "name");
                if (string.Equals(name, "EnableBannedPasswordCheck", StringComparison.OrdinalIgnoreCase)) enableRaw = Str(v, "value");
                else if (string.Equals(name, "BannedPasswordList", StringComparison.OrdinalIgnoreCase)) bannedList = Str(v, "value");
            }

            if (string.IsNullOrEmpty(bannedList)) bannedList = null;
            bool enableBanned = string.Equals(enableRaw, "true", StringComparison.OrdinalIgnoreCase);

            bool passed = enableBanned && bannedList != null;

            string enforced = enableBanned ? "Yes" : "No";
            var bannedArray = bannedList != null ? bannedList.Split('\t') : Array.Empty<string>();

            var display = new List<string>();
            if (bannedArray.Length > MaxDisplay)
            {
                for (int i = 0; i < MaxDisplay; i++) display.Add(bannedArray[i]);
                display.Add($"...and {bannedArray.Length - MaxDisplay} more");
            }
            else display.AddRange(bannedArray);

            var sb = new StringBuilder(passed
                ? "✅ Custom banned passwords are properly configured with organization-specific terms.\n\n"
                : "❌ Custom banned passwords are not enabled or lack organization-specific terms.\n\n");
            sb.Append($"## [Password protection settings]({PortalLink})\n\n");
            sb.Append("| Enforce custom list | Custom banned password list | Number of terms |\n");
            sb.Append("| :------------------ | :-------------------------- | :-------------- |\n");
            sb.Append($"| {enforced} | {string.Join(", ", display)} | {bannedArray.Length} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
