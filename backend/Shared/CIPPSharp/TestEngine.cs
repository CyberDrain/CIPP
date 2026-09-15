using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;

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
            long peakBytes = 0;

            // Deterministic, config-driven data-locality schedule: order tests so those sharing cached
            // types run together, then release each type once its last declared consumer has run — so
            // peak live data stays near the largest co-resident set instead of the whole union. Driven
            // entirely by the registry's dataTypes (no runtime discovery, no speculative table IO).
            var scheduling = DataLocalityEnabled;
            var ordered = scheduling ? ScheduleByDataLocality(metas) : metas;
            var remainingByType = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            if (scheduling)
                foreach (var m in metas)
                    if (m.DataTypes != null)
                        foreach (var t in m.DataTypes)
                            remainingByType[t] = remainingByType.TryGetValue(t, out var c) ? c + 1 : 1;
            long gcThreshold = GcThresholdBytes;
            long freedSinceGc = 0;

            using (var data = new TenantData(tenantFilter, tables, log))
            {
                foreach (var meta in ordered)
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
                    }
                    else
                    {
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

                    // Release every declared type whose last consumer has now run. Rebuildable and
                    // safe: a later unexpected Get simply re-reads it (results never change). GC-compact
                    // once enough has been freed so the released bytes are returned to the OS (RSS), not
                    // just to the managed heap.
                    if (scheduling && meta.DataTypes != null)
                    {
                        foreach (var t in meta.DataTypes)
                        {
                            if (!remainingByType.TryGetValue(t, out var c)) continue;
                            if (c <= 1) { remainingByType.Remove(t); freedSinceGc += data.Release(t); }
                            else remainingByType[t] = c - 1;
                        }
                        if (gcThreshold > 0 && freedSinceGc >= gcThreshold)
                        {
                            CompactAndCollect();
                            freedSinceGc = 0;
                        }
                    }
                }

                peakBytes = data.PeakBytes;
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
            log.Info($"{suiteLabel} for {tenantFilter}: {ran} ran, {failed} failed, {FormatSeconds(total)}s, peak {peakBytes / (1024 * 1024)}MB parsed",
                tenantFilter, null);

            return new SuiteRunSummary(suiteLabel, tenantFilter, ran, failed, total, timings, peakBytes);
        }

        // ── config knobs (env, resolved once) ──
        // CIPPTestsDataLocality=off disables the scheduler/eviction (registry order, hold-until-end)
        // as a safety switch. CIPPTestsGcThresholdMB tunes how much freed data triggers a compacting
        // GC so released bytes return to the OS (RSS); 0 disables the forced GC. Default 64 MB.
        private static readonly bool DataLocalityEnabled =
            !string.Equals(Environment.GetEnvironmentVariable("CIPPTestsDataLocality"), "off", StringComparison.OrdinalIgnoreCase);

        private static readonly long GcThresholdBytes = ResolveGcThresholdBytes();

        private static long ResolveGcThresholdBytes()
        {
            var v = Environment.GetEnvironmentVariable("CIPPTestsGcThresholdMB");
            if (v != null && long.TryParse(v, out var mb) && mb >= 0) return mb * 1024L * 1024L;
            return 64L * 1024 * 1024;
        }

        private static readonly string[] NoTypes = Array.Empty<string>();

        // Deterministic, config-only data-locality schedule. Greedily runs the pending test that pulls
        // in the fewest NEW cached types; ties go to the test that frees the most types right after
        // (finishing off currently-loaded data), then to a stable order (type-set signature, then id).
        // Keeps the working set small so peak ≈ the largest co-resident set. No byte sizes or runtime
        // probing — purely a function of the registry's declared dataTypes.
        private static List<TestMeta> ScheduleByDataLocality(IReadOnlyList<TestMeta> metas)
        {
            var types = new string[metas.Count][];
            var sigs = new string[metas.Count];
            var remaining = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < metas.Count; i++)
            {
                var dt = metas[i].DataTypes;
                var arr = (dt != null && dt.Count > 0) ? dt.OrderBy(x => x, StringComparer.Ordinal).ToArray() : NoTypes;
                types[i] = arr;
                sigs[i] = string.Join("|", arr);
                foreach (var t in arr) remaining[t] = remaining.TryGetValue(t, out var c) ? c + 1 : 1;
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
                    bool better =
                        newCount < bestNew ||
                        (newCount == bestNew && freed > bestFreed) ||
                        (newCount == bestNew && freed == bestFreed && string.CompareOrdinal(sigs[i], bestSig) < 0) ||
                        (newCount == bestNew && freed == bestFreed && sigs[i] == bestSig && string.CompareOrdinal(metas[i].Id, bestId) < 0);
                    if (best == -1 || better)
                    { best = i; bestNew = newCount; bestFreed = freed; bestSig = sigs[i]; bestId = metas[i].Id; }
                }

                used[best] = true;
                order.Add(metas[best]);
                foreach (var t in types[best]) { loaded.Add(t); if (--remaining[t] == 0) loaded.Remove(t); }
            }
            return order;
        }

        // Return freed managed memory (LOH included) to the OS so RSS drops, not just the heap.
        private static void CompactAndCollect()
        {
            try
            {
                System.Runtime.GCSettings.LargeObjectHeapCompactionMode =
                    System.Runtime.GCLargeObjectHeapCompactionMode.CompactOnce;
                GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
            }
            catch { /* GC tuning is best-effort */ }
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

        // ── data-locality experiment ────────────────────────────────────────────────
        // Measures whether scheduling tests by the cached data they need (and releasing each type
        // once its last consumer has run) lowers peak parsed-data memory vs the current "hold the
        // union until the end" model. Writes nothing — it runs the tests twice on the same data and
        // compares (1) peak live bytes and (2) that verdicts are identical. Not on the production
        // dispatch path; a harness/PS session calls it to evaluate the idea.

        private static (CippTestResult result, string[] types) EvalOne(
            TestRegistry registry, TestMeta meta, TenantData data, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities, bool record)
        {
            if (!IsLicensed(meta, capabilities))
            {
                var caps = string.Join(", ", meta.RequiredCapabilities ?? Array.Empty<string>());
                return (new CippTestResult(TestStatus.Unlicensed,
                    $"This tenant is not licensed for the required capabilities: {caps}."), Array.Empty<string>());
            }

            HashSet<string>? sink = record ? new HashSet<string>(StringComparer.OrdinalIgnoreCase) : null;
            data.RecordSink = sink;
            CippTestResult result;
            try
            {
                var test = registry.CreateTest(meta);
                result = test.Evaluate(data, log) ?? new CippTestResult(TestStatus.Failed, "Test returned no result.");
            }
            catch (Exception ex)
            {
                result = new CippTestResult(TestStatus.Failed, $"Test failed: {ex.Message}");
            }
            finally { data.RecordSink = null; }

            // Config tests declare their type in the rule; class tests are discovered via the sink.
            string[] types;
            if (string.Equals(meta.Kind, "config", StringComparison.OrdinalIgnoreCase)
                && meta.Rule != null && !string.IsNullOrEmpty(meta.Rule.Type))
                types = new[] { meta.Rule.Type };
            else
                types = sink != null ? sink.ToArray() : Array.Empty<string>();

            return (result, types);
        }

        /// <summary>
        /// Diagnostic: run every test in <paramref name="suiteNames"/> once on the tenant's real
        /// cached data with access recording on, and return test-id → the cached types it actually
        /// read. Used offline to cross-check the static data-type analysis that populates the
        /// registry — NOT a runtime path. Writes no results.
        /// </summary>
        public static Dictionary<string, string[]> RecordTestTypes(
            string tenantFilter, string[] suiteNames, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var registry = Registry.Value;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var map = new Dictionary<string, string[]>(StringComparer.Ordinal);
            using var data = new TenantData(tenantFilter, tables, log);
            foreach (var suite in suiteNames ?? Array.Empty<string>())
            {
                if (string.IsNullOrWhiteSpace(suite)) continue;
                IReadOnlyList<TestMeta> sm;
                try { sm = registry.GetSuite(suite); } catch (KeyNotFoundException) { continue; }
                foreach (var meta in sm)
                {
                    if (!seen.Add(meta.Id)) continue;
                    var (_, types) = EvalOne(registry, meta, data, log, capabilities, record: true);
                    map[meta.Id] = types;
                }
            }
            return map;
        }

        /// <summary>
        /// Diagnostic: run <paramref name="suiteNames"/> two ways on the same cached data and report
        /// peak parsed bytes for each — (A) union: registry order, nothing released (the pre-scheduler
        /// behaviour); (B) the production data-locality schedule + eviction, driven by the registry's
        /// declared dataTypes. Also asserts verdicts are identical, and counts declaration drift
        /// (types a test actually read that its dataTypes did not list — should be 0). Writes nothing.
        /// </summary>
        public static DataLocalityReport ExperimentDataLocality(
            string tenantFilter, string[] suiteNames, ITableClient tables, ILogSink log,
            IReadOnlyDictionary<string, bool>? capabilities = null)
        {
            var registry = Registry.Value;
            var metas = new List<TestMeta>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var suite in suiteNames ?? Array.Empty<string>())
            {
                if (string.IsNullOrWhiteSpace(suite)) continue;
                IReadOnlyList<TestMeta> sm;
                try { sm = registry.GetSuite(suite); } catch (KeyNotFoundException) { continue; }
                foreach (var m in sm) if (seen.Add(m.Id)) metas.Add(m);
            }

            // ── Pass A: union — registry order, no release, record what each test actually reads ──
            var resultsA = new Dictionary<string, CippTestResult>(StringComparer.Ordinal);
            var actual = new Dictionary<string, string[]>(StringComparer.Ordinal);
            long unionPeak;
            Dictionary<string, long> sizes;
            using (var dataA = new TenantData(tenantFilter, tables, log))
            {
                foreach (var meta in metas)
                {
                    var (res, types) = EvalOne(registry, meta, dataA, log, capabilities, record: true);
                    resultsA[meta.Id] = res;
                    actual[meta.Id] = types;
                }
                unionPeak = dataA.PeakBytes;
                sizes = dataA.SnapshotTypeSizes();
            }

            // Declaration drift: a type actually read but not declared in the registry's dataTypes.
            int drift = 0;
            foreach (var m in metas)
            {
                var declared = new HashSet<string>(m.DataTypes ?? (IReadOnlyList<string>)Array.Empty<string>(), StringComparer.OrdinalIgnoreCase);
                foreach (var t in actual[m.Id]) if (!declared.Contains(t)) drift++;
            }

            // ── Pass B: the production schedule + eviction, driven by declared dataTypes ──
            var order = ScheduleByDataLocality(metas);
            var remaining = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var m in metas)
                if (m.DataTypes != null)
                    foreach (var t in m.DataTypes)
                        remaining[t] = remaining.TryGetValue(t, out var c) ? c + 1 : 1;

            var resultsB = new Dictionary<string, CippTestResult>(StringComparer.Ordinal);
            long schedPeak;
            using (var dataB = new TenantData(tenantFilter, tables, log))
            {
                foreach (var meta in order)
                {
                    var (res, _) = EvalOne(registry, meta, dataB, log, capabilities, record: false);
                    resultsB[meta.Id] = res;
                    if (meta.DataTypes != null)
                        foreach (var t in meta.DataTypes)
                            if (remaining.TryGetValue(t, out var c))
                            {
                                if (c <= 1) { remaining.Remove(t); dataB.Release(t); }
                                else remaining[t] = c - 1;
                            }
                }
                schedPeak = dataB.PeakBytes;
            }

            // ── Compare verdicts (Status + data + markdown) ──
            int diffs = 0;
            foreach (var id in resultsA.Keys)
            {
                var a = resultsA[id];
                if (!resultsB.TryGetValue(id, out var b)) { diffs++; continue; }
                if (a.Status != b.Status || a.ResultDataJson != b.ResultDataJson || a.Markdown != b.Markdown) diffs++;
            }

            long largest = 0;
            foreach (var kv in sizes) if (kv.Value > largest) largest = kv.Value;

            return new DataLocalityReport(metas.Count, sizes.Count, unionPeak, schedPeak, largest, diffs, drift);
        }
    }

    /// <summary>Result of <see cref="TestEngine.ExperimentDataLocality"/>.</summary>
    public sealed record DataLocalityReport(
        int TestCount, int DistinctTypes,
        long UnionPeakBytes, long ScheduledPeakBytes, long LargestTypeBytes,
        int VerdictDiffs, int DeclarationDriftAccesses);

    /// <summary>Per-test timing for the suite summary.</summary>
    public sealed record TestTiming(string Id, double Seconds, bool Errored);

    /// <summary>Summary of one engine call — counts, per-test timings, and peak parsed bytes.</summary>
    public sealed record SuiteRunSummary(
        string Suite, string Tenant, int Ran, int Failed, double TotalSeconds,
        IReadOnlyList<TestTiming> Timings, long PeakParsedBytes = 0);
}
