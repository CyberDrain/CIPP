using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Runtime;

namespace CIPP.Tests
{
    /// <summary>
    /// Entry point PowerShell drives. Dispatch/fan-out/scheduling of suites stays in PS; this runs the
    /// evaluation for a tenant and writes results. All of a tenant's suites run under ONE
    /// <see cref="TenantData"/>, ordered by data locality: each reporting type is read and parsed once,
    /// shared by every test that needs it, and released the moment its last declared consumer has run —
    /// so peak live data stays near the largest co-resident set instead of the whole union.
    /// </summary>
    public static class TestEngine
    {
        private const string ResultsTable = "CippTestResults";

        // Compact the LOH back to the OS once this much released data has accumulated mid-run, so RSS
        // (not just the managed heap) drops as types are released. Small releases don't warrant a GC.
        private const long GcCompactThresholdBytes = 64L * 1024 * 1024;

        private static readonly Lazy<TestRegistry> Registry = new(() => TestRegistry.Load());

        /// <summary>
        /// Run every test across <paramref name="suiteNames"/> against <paramref name="tenantFilter"/>
        /// under one TenantData. <paramref name="capabilities"/> is the tenant's service-plan map
        /// (servicePlanName→enabled), resolved once by the PS dispatcher: a test whose
        /// RequiredCapabilities aren't met gets an <see cref="TestStatus.Unlicensed"/> result without
        /// running. Pass null to disable license gating.
        /// </summary>
        public static SuiteRunSummary RunSuites(string tenantFilter, string[] suiteNames, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var registry = Registry.Value;
            var metas = new List<TestMeta>();
            foreach (var suite in suiteNames)
                metas.AddRange(registry.GetSuite(suite));
            var label = string.Join("+", suiteNames);

            var stopwatch = Stopwatch.StartNew();
            var entities = new List<IDictionary<string, object>>(metas.Count);
            var timings = new List<TestTiming>(metas.Count);
            int ran = 0, failed = 0;

            var ordered = ScheduleByDataLocality(metas);
            var remaining = CountConsumers(metas);
            long freedSinceGc = 0;

            using (var data = new TenantData(tenantFilter, tables, log))
            {
                foreach (var meta in ordered)
                {
                    var sw = Stopwatch.StartNew();
                    var (result, errored) = Evaluate(registry, meta, data, log, tenantFilter, label, capabilities);
                    sw.Stop();

                    log.Info($"{label}: {meta.Id} for {tenantFilter} → {result.Status} in {FormatSeconds(sw.Elapsed.TotalSeconds)}s",
                        tenantFilter, meta.Id);
                    entities.Add(MapEntity(tenantFilter, meta, result));
                    timings.Add(new TestTiming(meta.Id, sw.Elapsed.TotalSeconds, errored));
                    if (errored) failed++; else ran++;

                    // Release each type whose last consumer has now run; compact the LOH periodically.
                    if (meta.DataTypes != null)
                        foreach (var t in meta.DataTypes)
                            if (--remaining[t] == 0) freedSinceGc += data.Release(t);
                    if (freedSinceGc >= GcCompactThresholdBytes) { CompactLoh(); freedSinceGc = 0; }
                }
            }

            if (entities.Count > 0)
                tables.WriteEntities(ResultsTable, entities);

            stopwatch.Stop();
            log.Info($"{label} for {tenantFilter}: {ran} ran, {failed} failed, {FormatSeconds(stopwatch.Elapsed.TotalSeconds)}s",
                tenantFilter, null);
            return new SuiteRunSummary(label, tenantFilter, ran, failed, stopwatch.Elapsed.TotalSeconds, timings);
        }

        // Evaluate one test: license gate, then run its body. A throwing test becomes a Failed result
        // (one bad test must not abort the tenant's run).
        private static (CippTestResult result, bool errored) Evaluate(
            TestRegistry registry, TestMeta meta, TenantData data, ILogSink log,
            string tenant, string label, IReadOnlyDictionary<string, bool>? capabilities)
        {
            if (!IsLicensed(meta, capabilities))
            {
                var caps = string.Join(", ", meta.RequiredCapabilities!);
                return (new CippTestResult(TestStatus.Unlicensed,
                    $"This tenant is not licensed for the required capabilities: {caps}."), false);
            }
            try
            {
                var result = registry.CreateTest(meta).Evaluate(data, log)
                             ?? new CippTestResult(TestStatus.Failed, "Test returned no result.");
                return (result, false);
            }
            catch (Exception ex)
            {
                log.Error($"{label}: {meta.Id} threw: {ex.Message}", tenant, meta.Id, ex);
                return (new CippTestResult(TestStatus.Failed, $"Test failed: {ex.Message}"), true);
            }
        }

        // True when the tenant has at least one of the test's required service plans. No requirements,
        // or a null capability map, means never gated.
        private static bool IsLicensed(TestMeta meta, IReadOnlyDictionary<string, bool>? capabilities)
        {
            if (meta.RequiredCapabilities == null || meta.RequiredCapabilities.Count == 0) return true;
            if (capabilities == null) return true;
            foreach (var cap in meta.RequiredCapabilities)
                if (capabilities.TryGetValue(cap, out var enabled) && enabled) return true;
            return false;
        }

        private static Dictionary<string, int> CountConsumers(IReadOnlyList<TestMeta> metas)
        {
            var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var m in metas)
                if (m.DataTypes != null)
                    foreach (var t in m.DataTypes)
                        counts[t] = counts.TryGetValue(t, out var c) ? c + 1 : 1;
            return counts;
        }

        // Deterministic data-locality order: greedily run the pending test that pulls in the fewest NEW
        // cached types; ties go to the one that finishes off the most currently-loaded types, then to a
        // stable order (type-set signature, then id). Keeps the working set — and thus peak memory —
        // near the largest co-resident set. Purely a function of the registry's declared dataTypes.
        // ponytail: O(n²) selection over ~500 tests (~130k cheap iterations); a priority queue only if n grows.
        private static List<TestMeta> ScheduleByDataLocality(IReadOnlyList<TestMeta> metas)
        {
            var types = new string[metas.Count][];
            var sigs = new string[metas.Count];
            var remaining = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < metas.Count; i++)
            {
                var dt = metas[i].DataTypes;
                types[i] = (dt != null && dt.Count > 0)
                    ? dt.OrderBy(x => x, StringComparer.Ordinal).ToArray()
                    : Array.Empty<string>();
                sigs[i] = string.Join("|", types[i]);
                foreach (var t in types[i]) remaining[t] = remaining.TryGetValue(t, out var c) ? c + 1 : 1;
            }

            var loaded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var used = new bool[metas.Count];
            var order = new List<TestMeta>(metas.Count);

            for (int step = 0; step < metas.Count; step++)
            {
                int best = -1, bestNew = int.MaxValue, bestFreed = -1;
                string bestSig = null!, bestId = null!;
                for (int i = 0; i < metas.Count; i++)
                {
                    if (used[i]) continue;
                    int newCount = 0, freed = 0;
                    foreach (var t in types[i])
                    {
                        if (!loaded.Contains(t)) newCount++;
                        else if (remaining[t] == 1) freed++;
                    }
                    if (best == -1
                        || newCount < bestNew
                        || (newCount == bestNew && freed > bestFreed)
                        || (newCount == bestNew && freed == bestFreed && string.CompareOrdinal(sigs[i], bestSig) < 0)
                        || (newCount == bestNew && freed == bestFreed && sigs[i] == bestSig && string.CompareOrdinal(metas[i].Id, bestId) < 0))
                    { best = i; bestNew = newCount; bestFreed = freed; bestSig = sigs[i]; bestId = metas[i].Id; }
                }

                used[best] = true;
                order.Add(metas[best]);
                foreach (var t in types[best]) { loaded.Add(t); if (--remaining[t] == 0) loaded.Remove(t); }
            }
            return order;
        }

        // Return freed managed memory (LOH included) to the OS so RSS drops, not just the heap.
        private static void CompactLoh()
        {
            GCSettings.LargeObjectHeapCompactionMode = GCLargeObjectHeapCompactionMode.CompactOnce;
            GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
        }

        // Columns EXACTLY as Add-CippTestResult emits, so ListTests and the frontend read them
        // unchanged. Metadata comes from the registry; Pillar has no registry field (matches the PS
        // tests, which do not set it).
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
