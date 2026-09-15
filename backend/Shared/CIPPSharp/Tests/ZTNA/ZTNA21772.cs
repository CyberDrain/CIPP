using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Applications do not have client secrets configured.
    /// Port of Invoke-CippTestZTNA21772. Apps + ServicePrincipals with a non-empty passwordCredentials
    /// collection. Passed when none have secrets.
    /// </summary>
    public sealed class ZTNA21772 : ICippTest
    {
        public string Id => "ZTNA21772";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var apps = data.Get("Apps");
            var sps = data.Get("ServicePrincipals");

            if (!Any(apps) && !Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var appsWithSecrets = new List<JsonElement>();
            foreach (var a in Items(apps)) if (HasCredentials(a, "passwordCredentials")) appsWithSecrets.Add(a);

            var spsWithSecrets = new List<JsonElement>();
            foreach (var s in Items(sps)) if (HasCredentials(s, "passwordCredentials")) spsWithSecrets.Add(s);

            if (appsWithSecrets.Count + spsWithSecrets.Count == 0)
                return new CippTestResult(TestStatus.Passed, "Applications in your tenant do not use client secrets");

            var sb = new StringBuilder();
            sb.Append($"Found {appsWithSecrets.Count} applications and {spsWithSecrets.Count} service principals with client secrets configured\n");
            sb.Append("## Apps with client secrets:\n");
            sb.Append(JoinAppLines(appsWithSecrets));
            sb.Append("\n## Service principals with client secrets:\n");
            sb.Append(JoinAppLines(spsWithSecrets));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static string JoinAppLines(List<JsonElement> items)
        {
            var lines = new List<string>(items.Count);
            foreach (var e in items) lines.Add($"- {Text(e, "displayName")} (AppId: {Text(e, "appId")})");
            return string.Join("\n", lines);
        }
    }
}
