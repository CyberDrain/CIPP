using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;

namespace CIPP.Tests
{
    /// <summary>
    /// Entry point PowerShell drives. Dispatch/fan-out/scheduling stay in PS; this runs the
    /// evaluation and writes results. One <see cref="TenantData"/> is built per call so every test
    /// in the suite shares a single parse of each reporting type — the whole reason for the C#
    /// engine (the PS path re-materialised the fat Users set per test and OOM-crash-looped).
    /// </summary>
    public static class TestEngine
    {
        private const string ResultsTable = "CippTestResults";

        // The registry (types never change in a process; the module watcher restarts the worker on
        // a registry edit, and a fail-closed validation error is cached deliberately — the process
        // should not run a broken registry).
        private static readonly Lazy<TestRegistry> Registry = new(() => TestRegistry.Load());

        /// <summary>
        /// Run every test in <paramref name="suiteName"/> against <paramref name="tenantFilter"/>.
        /// <paramref name="capabilities"/> is the tenant's service-plan map (servicePlanName→enabled),
        /// resolved once by the PS dispatcher (Get-CIPPTenantCapabilities) and passed in: a test whose
        /// RequiredCapabilities aren't met gets an <see cref="TestStatus.Unlicensed"/> result and its
        /// body is not run. Pass null to disable gating entirely (tests always run).
        /// </summary>
        public static SuiteRunSummary RunSuite(string tenantFilter, string suiteName, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var metas = Registry.Value.GetSuite(suiteName);
            return RunCore(tenantFilter, suiteName, metas, tables, log, capabilities);
        }

        /// <summary>Run a specific set of tests (by id). See <see cref="RunSuite"/> for <paramref name="capabilities"/>.</summary>
        public static SuiteRunSummary RunTests(string tenantFilter, string[] testIds, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var metas = Registry.Value.GetTests(testIds);
            return RunCore(tenantFilter, "(selected tests)", metas, tables, log, capabilities);
        }

        /// <summary>
        /// Run every test across <b>all</b> of <paramref name="suiteNames"/> against
        /// <paramref name="tenantFilter"/> under a <b>single</b> <see cref="TenantData"/>: each
        /// reporting type is read from the table and parsed exactly once for the whole group, then
        /// shared by every test in every suite. This is the cross-suite counterpart to RunSuite's
        /// within-suite sharing — the PS dispatcher groups a tenant's suites into one call so the fat
        /// Users set (read by CIS, CISA, E8, EIDSCA, ZTNA, …) is not re-read and re-parsed per suite.
        /// A suite name the registry does not know (a PS-only suite) is skipped, not fatal; a test that
        /// appears in more than one suite runs once (deduped by id). See <see cref="RunSuite"/> for
        /// <paramref name="capabilities"/>.
        /// </summary>
        public static SuiteRunSummary RunSuites(string tenantFilter, string[] suiteNames, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var registry = Registry.Value;
            var metas = new List<TestMeta>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var included = new List<string>();

            foreach (var suite in suiteNames ?? Array.Empty<string>())
            {
                if (string.IsNullOrWhiteSpace(suite)) continue;
                IReadOnlyList<TestMeta> suiteMetas;
                try
                {
                    suiteMetas = registry.GetSuite(suite);
                }
                catch (KeyNotFoundException)
                {
                    // A suite with no registered C# tests (still PS-only on disk). Not an error: the
                    // dispatcher runs its leftover .ps1 separately. Skip it in the engine group.
                    log.Info($"No registered C# tests for suite '{suite}' — skipping in engine group", tenantFilter, null);
                    continue;
                }
                included.Add(suite);
                foreach (var m in suiteMetas)
                    if (seen.Add(m.Id)) metas.Add(m);
            }

            var label = included.Count > 0 ? string.Join("+", included) : "(no engine suites)";
            return RunCore(tenantFilter, label, metas, tables, log, capabilities);
        }

        // True when the tenant has at least one of the test's required service plans enabled. A test
        // with no RequiredCapabilities is never gated; a null capability map disables gating.
        private static bool IsLicensed(TestMeta meta, IReadOnlyDictionary<string, bool>? capabilities)
        {
            if (meta.RequiredCapabilities == null || meta.RequiredCapabilities.Count == 0) return true;
            if (capabilities == null) return true;
            foreach (var cap in meta.RequiredCapabilities)
                if (capabilities.TryGetValue(cap, out var enabled) && enabled) return true;
            return false;
        }

        private static SuiteRunSummary RunCore(
            string tenantFilter, string suiteLabel, IReadOnlyList<TestMeta> metas,
            ITableClient tables, ILogSink log, IReadOnlyDictionary<string, bool>? capabilities)
        {
            var registry = Registry.Value;
            var suiteStopwatch = Stopwatch.StartNew();
            var entities = new List<IDictionary<string, object>>(metas.Count);
            var timings = new List<TestTiming>(metas.Count);
            int ran = 0, failed = 0;

            using (var data = new TenantData(tenantFilter, tables, log))
            {
                foreach (var meta in metas)
                {
                    var sw = Stopwatch.StartNew();

                    // License gate: dispatcher-supplied capabilities + registry-declared requirements.
                    // A gated-out test gets an Unlicensed result and its body never runs — the same
                    // verdict the PS in-test Test-CIPPStandardLicense check produced, but resolved once
                    // per tenant rather than per test.
                    if (!IsLicensed(meta, capabilities))
                    {
                        sw.Stop();
                        var caps = string.Join(", ", meta.RequiredCapabilities ?? Array.Empty<string>());
                        var unlicensed = new CippTestResult(TestStatus.Unlicensed,
                            $"This tenant is not licensed for the required capabilities: {caps}.");
                        log.Info($"{suiteLabel}: {meta.Id} for {tenantFilter} → Unlicensed", tenantFilter, meta.Id);
                        entities.Add(MapEntity(tenantFilter, meta, unlicensed));
                        timings.Add(new TestTiming(meta.Id, sw.Elapsed.TotalSeconds, false));
                        ran++;
                        continue;
                    }

                    log.Info($"{suiteLabel}: starting {meta.Id} for {tenantFilter}", tenantFilter, meta.Id);

                    CippTestResult result;
                    bool errored = false;
                    try
                    {
                        var test = registry.CreateTest(meta);
                        result = test.Evaluate(data, log)
                                 ?? new CippTestResult(TestStatus.Failed, "Test returned no result.");
                    }
                    catch (Exception ex)
                    {
                        errored = true;
                        log.Error($"{suiteLabel}: {meta.Id} threw: {ex.Message}", tenantFilter, meta.Id, ex);
                        result = new CippTestResult(TestStatus.Failed, $"Test failed: {ex.Message}");
                    }

                    sw.Stop();
                    var seconds = sw.Elapsed.TotalSeconds;
                    log.Info(
                        $"{suiteLabel}: {meta.Id} for {tenantFilter} → {result.Status} in {FormatSeconds(seconds)}s",
                        tenantFilter, meta.Id);

                    entities.Add(MapEntity(tenantFilter, meta, result));
                    timings.Add(new TestTiming(meta.Id, seconds, errored));
                    if (errored) failed++; else ran++;
                }
            }

            // One batch write for the whole suite. A write failure is logged but never masks the
            // run summary — the caller still learns what ran.
            if (entities.Count > 0)
            {
                try
                {
                    tables.WriteEntities(ResultsTable, entities);
                }
                catch (Exception ex)
                {
                    log.Error($"{suiteLabel}: failed to write {entities.Count} result rows: {ex.Message}",
                        tenantFilter, null, ex);
                }
            }

            suiteStopwatch.Stop();
            var total = suiteStopwatch.Elapsed.TotalSeconds;
            log.Info($"{suiteLabel} for {tenantFilter}: {ran} ran, {failed} failed, {FormatSeconds(total)}s",
                tenantFilter, null);

            return new SuiteRunSummary(suiteLabel, tenantFilter, ran, failed, total, timings);
        }

        // Columns EXACTLY as Add-CippTestResult emits, so ListTests and the frontend read them
        // unchanged. Metadata comes from the registry (single source of truth); Pillar has no
        // registry field and defaults to "" — matching the PS tests, which do not set it.
        private static IDictionary<string, object> MapEntity(string tenant, TestMeta meta, CippTestResult result)
        {
            return new Dictionary<string, object>
            {
                ["PartitionKey"] = tenant,
                ["RowKey"] = meta.Id,
                ["Status"] = result.Status ?? "",
                ["ResultMarkdown"] = result.Markdown ?? "",
                ["ResultDataJson"] = result.ResultDataJson ?? "",
                ["Risk"] = meta.Risk ?? "",
                ["Name"] = meta.Name ?? "",
                ["Pillar"] = "",
                ["UserImpact"] = meta.UserImpact ?? "",
                ["ImplementationEffort"] = meta.ImplementationEffort ?? "",
                ["Category"] = meta.Category ?? "",
                ["TestType"] = meta.TestType ?? "Identity",
            };
        }

        private static string FormatSeconds(double seconds) =>
            seconds.ToString("N3", CultureInfo.InvariantCulture);
    }

    /// <summary>Per-test timing for the suite summary.</summary>
    public sealed record TestTiming(string Id, double Seconds, bool Errored);

    /// <summary>Summary of one engine call — counts plus per-test timings, for the PS log line.</summary>
    public sealed record SuiteRunSummary(
        string Suite, string Tenant, int Ran, int Failed, double TotalSeconds,
        IReadOnlyList<TestTiming> Timings);
}
