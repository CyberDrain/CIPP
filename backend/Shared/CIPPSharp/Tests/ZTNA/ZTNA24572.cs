using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Device enrollment notifications are enforced to ensure user awareness and secure onboarding.
    /// Port of Invoke-CippTestZTNA24572. Skipped on no IntuneDeviceEnrollmentConfigurations data;
    /// Passed when at least one enrollment-notification configuration is assigned.
    /// </summary>
    public sealed class ZTNA24572 : ICippTest
    {
        public string Id => "ZTNA24572";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceEnrollmentConfigurations");
            if (!Any(configs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var notifications = new List<JsonElement>();
            foreach (var c in Items(configs))
                if (StrEq(c, "@odata.type", "#microsoft.graph.windowsEnrollmentStatusScreenSettings")
                    || StrEq(c, "deviceEnrollmentConfigurationType", "EnrollmentNotificationsConfiguration"))
                    notifications.Add(c);

            int assignedCount = 0;
            foreach (var n in notifications) if (IsAssigned(n)) assignedCount++;
            bool passed = assignedCount > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one device enrollment notification is configured and assigned.\n\n"
                : "❌ No device enrollment notification is configured or assigned in Intune.\n\n");

            if (notifications.Count > 0)
            {
                sb.Append("## Device Enrollment Notifications\n\n");
                sb.Append("| Policy Name | Assigned |\n");
                sb.Append("| :---------- | :------- |\n");
                foreach (var n in notifications)
                {
                    var assigned = IsAssigned(n) ? "✅ Yes" : "❌ No";
                    sb.Append($"| {Text(n, "displayName")} | {assigned} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
