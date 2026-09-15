using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guests do not own apps in the tenant.
    /// Port of Invoke-CippTestZTNA21868. Skipped when any of Guests/Apps/ServicePrincipals is missing.
    /// Failed when a guest (matched by object id) owns an application or service principal.
    /// </summary>
    public sealed class ZTNA21868 : ICippTest
    {
        public string Id => "ZTNA21868";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var guests = data.Get("Guests");
            var apps = data.Get("Apps");
            var sps = data.Get("ServicePrincipals");

            if (!Any(guests) || !Any(apps) || !Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var guestIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var g in Items(guests))
            {
                var id = Str(g, "id");
                if (id != null) guestIds.Add(id);
            }

            // (display, upn, targetName)
            var appOwners = new List<(string, string, string)>();
            foreach (var app in Items(apps))
                foreach (var owner in Arr(app, "owners"))
                {
                    var oid = Str(owner, "id");
                    if (oid != null && guestIds.Contains(oid))
                        appOwners.Add((Text(owner, "displayName"), Text(owner, "userPrincipalName"), Text(app, "displayName")));
                }

            var spOwners = new List<(string, string, string)>();
            foreach (var sp in Items(sps))
                foreach (var owner in Arr(sp, "owners"))
                {
                    var oid = Str(owner, "id");
                    if (oid != null && guestIds.Contains(oid))
                        spOwners.Add((Text(owner, "displayName"), Text(owner, "userPrincipalName"), Text(sp, "displayName")));
                }

            bool hasApp = appOwners.Count > 0;
            bool hasSp = spOwners.Count > 0;

            if (!hasApp && !hasSp)
                return new CippTestResult(TestStatus.Passed,
                    "No guest users own any applications or service principals in the tenant");

            var sb = new StringBuilder("Guest users own applications or service principals\n\n");

            if (hasApp && hasSp)
            {
                sb.Append("## Guest users own both applications and service principals\n\n");
                sb.Append("### Applications owned by guest users\n\n");
                sb.Append("| User Display Name | User Principal Name | Application |\n");
                sb.Append("| :---------------- | :------------------ | :---------- |\n");
                sb.Append(Rows(appOwners));
                sb.Append("\n\n### Service principals owned by guest users\n\n");
                sb.Append("| User Display Name | User Principal Name | Service Principal |\n");
                sb.Append("| :---------------- | :------------------ | :---------------- |\n");
                sb.Append(Rows(spOwners));
            }
            else if (hasApp)
            {
                sb.Append("## Guest users own applications\n\n");
                sb.Append("| User Display Name | User Principal Name | Application |\n");
                sb.Append("| :---------------- | :------------------ | :---------- |\n");
                sb.Append(Rows(appOwners));
            }
            else
            {
                sb.Append("## Guest users own service principals\n\n");
                sb.Append("| User Display Name | User Principal Name | Service Principal |\n");
                sb.Append("| :---------------- | :------------------ | :---------------- |\n");
                sb.Append(Rows(spOwners));
            }

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static string Rows(List<(string Display, string Upn, string Target)> owners)
        {
            var lines = new List<string>(owners.Count);
            foreach (var o in owners) lines.Add($"| {o.Display} | {o.Upn} | {o.Target} |");
            return string.Join("\n", lines);
        }
    }
}
