using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CIPP.Tests
{
    // ── data access ──────────────────────────────────────────────────────────────
    // Implemented by the CIPP.TableClient adapter (W1). Defined here so the engine
    // (W2) and the class tests (W3) compile and run against a stable contract even
    // before the adapter assembly exists. W1 references this interface.
    /// <summary>
    /// Storage boundary for the test engine. Reads reassembled reporting rows and
    /// writes result entities (split-marker aware) — the engine never touches Azure
    /// SDK types directly, keeping CIPPSharp dependency-free.
    /// </summary>
    public interface ITableClient
    {
        /// <summary>
        /// Stream every row for <paramref name="partitionKey"/> whose RowKey starts with
        /// <paramref name="rowKeyPrefix"/> from <paramref name="table"/>, reassembled from
        /// AzBobbyTables split markers, as raw JSON strings (one per stored row — each a single JSON
        /// object or array). Lazy: the caller parses and projects each row and lets it go, so the
        /// separate full-type string copy is never built (peak drops from two full copies to one).
        /// </summary>
        IEnumerable<string> ReadRows(string table, string partitionKey, string rowKeyPrefix);

        /// <summary>Write result entities to <paramref name="table"/> (split-marker aware).</summary>
        void WriteEntities(string table, IEnumerable<IDictionary<string, object>> entities);
    }

    // ── logging ──────────────────────────────────────────────────────────────────
    /// <summary>
    /// Engine log boundary. PowerShell wires an adapter: Warn/Error → Write-LogMessage
    /// (audit-visible), Info → Write-Information (→ craft.log [INF]). No Write-Host, no
    /// PSObject churn on this path.
    /// </summary>
    public interface ILogSink
    {
        void Info(string message, string? tenant = null, string? testId = null);
        void Warn(string message, string? tenant = null, string? testId = null);
        void Error(string message, string? tenant = null, string? testId = null, Exception? ex = null);
    }

    /// <summary>
    /// An <see cref="ILogSink"/> backed by delegates. PowerShell supplies logging callbacks by
    /// constructing this at runtime (<c>[CIPP.Tests.DelegateLogSink]::new(...)</c>) instead of
    /// declaring a <c>class : ILogSink</c> — a PS class that implements a C# interface fails
    /// ModuleBuilder's parse-time type resolution (the type isn't loaded when the .ps1 is parsed),
    /// which would drop the whole file from the function-parameter cache. Any channel may be null
    /// (no-op), and a throwing callback never breaks a test run.
    /// </summary>
    public sealed class DelegateLogSink : ILogSink
    {
        private readonly Action<string, string?, string?>? _info;
        private readonly Action<string, string?, string?>? _warn;
        private readonly Action<string, string?, string?, Exception?>? _error;

        public DelegateLogSink(
            Action<string, string?, string?>? info = null,
            Action<string, string?, string?>? warn = null,
            Action<string, string?, string?, Exception?>? error = null)
        {
            _info = info;
            _warn = warn;
            _error = error;
        }

        public void Info(string message, string? tenant = null, string? testId = null)
        { try { _info?.Invoke(message, tenant, testId); } catch { /* logging must never break a run */ } }

        public void Warn(string message, string? tenant = null, string? testId = null)
        { try { _warn?.Invoke(message, tenant, testId); } catch { } }

        public void Error(string message, string? tenant = null, string? testId = null, Exception? ex = null)
        { try { _error?.Invoke(message, tenant, testId, ex); } catch { } }
    }

    // ── test abstraction ─────────────────────────────────────────────────────────
    /// <summary>A single built-in test. Metadata lives in the registry, not here.</summary>
    public interface ICippTest
    {
        /// <summary>Must match a registry entry id.</summary>
        string Id { get; }

        CippTestResult Evaluate(TenantData data, ILogSink log);
    }

    /// <summary>
    /// Verdict of one test. <see cref="Status"/> ∈ Passed | Failed | Skipped | Informational
    /// (matches the current PowerShell status strings exactly).
    /// </summary>
    public sealed record CippTestResult(string Status, string Markdown, string ResultDataJson = "");

    /// <summary>
    /// Status string constants — the exact strings the current PS tests emit, so stored
    /// results and the frontend keep reading them unchanged.
    /// </summary>
    public static class TestStatus
    {
        public const string Passed = "Passed";
        public const string Failed = "Failed";
        public const string Skipped = "Skipped";
        public const string Informational = "Informational";
        // Emitted by the engine (not by a test body) when the tenant lacks a test's
        // RequiredCapabilities. License gating lives in the dispatcher+engine, not per test.
        public const string Unlicensed = "Unlicensed";
    }

    // ── registry metadata ────────────────────────────────────────────────────────
    /// <summary>
    /// Per-test metadata as it lives in the registry (single source of truth — no
    /// duplication on the class). <see cref="Suite"/> is filled from the parent suite object.
    /// <see cref="ClassName"/> is set for <c>kind:class</c> tests; <see cref="Rule"/> for
    /// <c>kind:config</c> tests.
    /// </summary>
    public sealed record TestMeta(
        string Id, string Suite, string Kind, string Name, string Risk, string Category,
        string UserImpact, string ImplementationEffort, string TestType,
        string? ClassName, ConfigRule? Rule,
        // Service-plan names the tenant must have at least one of (already expanded from any
        // preset at registry-authoring time). Empty = no license gate. The engine emits
        // TestStatus.Unlicensed for a test whose caps aren't met, before running its body.
        IReadOnlyList<string>? RequiredCapabilities = null,
        // The cached reporting types this test reads (declared in the registry — config tests from
        // their rule.type, class tests from static source analysis). Drives the deterministic
        // data-locality scheduler: tests are ordered by the data they share, and each type is
        // released once its last declared consumer has run. Empty = the test reads no cached data.
        IReadOnlyList<string>? DataTypes = null,
        // Per-type field projection: type → the top-level fields this test reads from it. When EVERY
        // consumer of a type declares its fields, the engine loads that type projected to the union —
        // records keep only those fields, cutting parsed memory. A type any consumer leaves undeclared
        // loads full (safe default), so this fills in per test incrementally.
        IReadOnlyDictionary<string, IReadOnlyList<string>>? DataFields = null);

    // ── config-rule model (drives PredicateTest) ─────────────────────────────────
    /// <summary>A single field/op/value clause. Deserialized from the registry (case-insensitive).</summary>
    public sealed class ConfigClause
    {
        [JsonPropertyName("field")] public string Field { get; set; } = "";
        [JsonPropertyName("op")] public string Op { get; set; } = "";

        /// <summary>
        /// The comparison value as raw JSON (bool/number/string/etc). Left
        /// <see cref="JsonValueKind.Undefined"/> when absent (e.g. for exists/notExists).
        /// </summary>
        [JsonPropertyName("value")] public JsonElement Value { get; set; }
    }

    /// <summary>
    /// The expectation applied to the rows selected by <see cref="ConfigRule.Where"/>.
    /// Mode ∈ all | none | count | percent. <see cref="Of"/> is the AND-set graded per row;
    /// <see cref="Threshold"/> is the minimum for count/percent.
    /// </summary>
    public sealed class ConfigExpect
    {
        [JsonPropertyName("mode")] public string Mode { get; set; } = "all";
        [JsonPropertyName("of")] public List<ConfigClause> Of { get; set; } = new();
        [JsonPropertyName("threshold")] public double? Threshold { get; set; }
    }

    /// <summary>
    /// A config test. The rule <i>is</i> the test: read <see cref="Type"/>, AND-filter by
    /// <see cref="Where"/>, grade with <see cref="Expect"/>, render <see cref="Pass"/>/
    /// <see cref="Fail"/> and (on fail) a table of the <see cref="FailTable"/> columns.
    /// </summary>
    public sealed class ConfigRule
    {
        [JsonPropertyName("type")] public string Type { get; set; } = "";
        [JsonPropertyName("where")] public List<ConfigClause> Where { get; set; } = new();
        [JsonPropertyName("expect")] public ConfigExpect? Expect { get; set; }
        [JsonPropertyName("pass")] public string? Pass { get; set; }
        [JsonPropertyName("fail")] public string? Fail { get; set; }
        [JsonPropertyName("failTable")] public List<string> FailTable { get; set; } = new();
    }
}
