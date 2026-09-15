using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CIPP.Tests
{
    /// <summary>
    /// Loader + fail-closed validator for <c>backend/Modules/CIPPTests/tests.registry.json</c>.
    /// The registry is the single source of "what tests exist" and "what to run": a by-suite →
    /// per-test tree of <see cref="TestMeta"/>. Validation refuses to run a partially-wired
    /// registry — every <c>kind:class</c> id must resolve to a compiled <see cref="ICippTest"/>,
    /// and every compiled class test must appear in the registry.
    /// </summary>
    public sealed class TestRegistry
    {
        private readonly List<TestMeta> _all;
        private readonly Dictionary<string, List<TestMeta>> _bySuite;
        private readonly Dictionary<string, TestMeta> _byId;
        private readonly Dictionary<string, Type> _classTypes; // registry class name -> concrete Type

        private TestRegistry(List<TestMeta> all, Dictionary<string, Type> classTypes)
        {
            _all = all;
            _classTypes = classTypes;
            _bySuite = all.GroupBy(t => t.Suite, StringComparer.OrdinalIgnoreCase)
                          .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.OrdinalIgnoreCase);
            _byId = all.ToDictionary(t => t.Id, t => t, StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>All registered tests, flattened across suites.</summary>
        public IReadOnlyList<TestMeta> All => _all;

        /// <summary>Tests in <paramref name="suite"/>. Throws on an unknown suite (fail-closed).</summary>
        public IReadOnlyList<TestMeta> GetSuite(string suite)
        {
            if (!_bySuite.TryGetValue(suite, out var list))
                throw new KeyNotFoundException($"Unknown test suite '{suite}'.");
            return list;
        }

        /// <summary>Metadata for the given ids, in the order requested. Throws on an unknown id.</summary>
        public IReadOnlyList<TestMeta> GetTests(IEnumerable<string> ids)
        {
            var result = new List<TestMeta>();
            foreach (var id in ids)
            {
                if (!_byId.TryGetValue(id, out var meta))
                    throw new KeyNotFoundException($"Unknown test id '{id}'.");
                result.Add(meta);
            }
            return result;
        }

        /// <summary>
        /// Instantiate the <see cref="ICippTest"/> for a registry entry: config → a
        /// <see cref="PredicateTest"/> over its rule; class → the resolved concrete type.
        /// </summary>
        public ICippTest CreateTest(TestMeta meta)
        {
            if (string.Equals(meta.Kind, "config", StringComparison.OrdinalIgnoreCase))
            {
                if (meta.Rule == null)
                    throw new InvalidOperationException($"Config test '{meta.Id}' has no rule.");
                return new PredicateTest(meta.Id, meta.Rule);
            }

            if (string.Equals(meta.Kind, "class", StringComparison.OrdinalIgnoreCase))
            {
                var className = meta.ClassName ?? meta.Id;
                if (!_classTypes.TryGetValue(className, out var type))
                    throw new InvalidOperationException(
                        $"Class test '{meta.Id}' references unknown class '{className}'.");
                var instance = (ICippTest?)Activator.CreateInstance(type)
                    ?? throw new InvalidOperationException($"Could not instantiate class '{className}'.");
                return instance;
            }

            throw new InvalidOperationException($"Test '{meta.Id}' has unknown kind '{meta.Kind}'.");
        }

        // ── loading ────────────────────────────────────────────────────────────────

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };

        /// <summary>
        /// Load and validate the registry from an explicit path. An absent or empty file yields
        /// an empty registry (tolerated so the engine builds before any tests are wired), but the
        /// fail-closed validation still runs against whatever classes are compiled.
        /// </summary>
        public static TestRegistry Load(string? path = null, Assembly? testAssembly = null)
        {
            var assembly = testAssembly ?? typeof(TestRegistry).Assembly;
            var classTypes = DiscoverClassTests(assembly);

            var metas = new List<TestMeta>();
            var resolvedPath = path ?? ResolveDefaultPath();
            if (resolvedPath != null && File.Exists(resolvedPath))
            {
                var json = File.ReadAllText(resolvedPath);
                metas = Parse(json);
            }

            Validate(metas, classTypes);
            return new TestRegistry(metas, classTypes);
        }

        /// <summary>Parse the registry JSON into a flat <see cref="TestMeta"/> list (no validation).</summary>
        public static List<TestMeta> Parse(string json)
        {
            var result = new List<TestMeta>();
            if (string.IsNullOrWhiteSpace(json)) return result;

            var doc = JsonSerializer.Deserialize<RegistryFile>(json, JsonOpts);
            if (doc?.Suites == null) return result;

            foreach (var suite in doc.Suites)
            {
                if (suite?.Tests == null) continue;
                foreach (var t in suite.Tests)
                {
                    if (t == null || string.IsNullOrEmpty(t.Id)) continue;
                    result.Add(new TestMeta(
                        Id: t.Id,
                        Suite: suite.Name ?? "",
                        Kind: t.Kind ?? "class",
                        Name: t.Name ?? "",
                        Risk: t.Risk ?? "",
                        Category: t.Category ?? "",
                        UserImpact: t.UserImpact ?? "",
                        ImplementationEffort: t.ImplementationEffort ?? "",
                        TestType: t.TestType ?? "Identity",
                        ClassName: t.Class,
                        Rule: t.Rule,
                        RequiredCapabilities: (t.RequiredCapabilities != null && t.RequiredCapabilities.Count > 0)
                            ? t.RequiredCapabilities
                            : null,
                        DataTypes: (t.DataTypes != null && t.DataTypes.Count > 0)
                            ? t.DataTypes
                            : null));
                }
            }
            return result;
        }

        // Concrete, public-or-internal ICippTest implementations, keyed by type name. Excludes the
        // generic PredicateTest — it is the config engine, not a per-id class test.
        private static Dictionary<string, Type> DiscoverClassTests(Assembly assembly)
        {
            var map = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase);
            foreach (var type in assembly.GetTypes())
            {
                if (type.IsAbstract || type.IsInterface) continue;
                if (!typeof(ICippTest).IsAssignableFrom(type)) continue;
                if (type == typeof(PredicateTest)) continue;
                map[type.Name] = type;
            }
            return map;
        }

        // Fail-closed: no dangling class references either direction, no duplicate ids.
        private static void Validate(List<TestMeta> metas, Dictionary<string, Type> classTypes)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var m in metas)
            {
                if (!seen.Add(m.Id))
                    throw new InvalidOperationException($"Duplicate test id '{m.Id}' in registry.");
            }

            var referenced = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var m in metas)
            {
                if (!string.Equals(m.Kind, "class", StringComparison.OrdinalIgnoreCase)) continue;
                var className = m.ClassName ?? m.Id;
                if (!classTypes.ContainsKey(className))
                    throw new InvalidOperationException(
                        $"Registry class test '{m.Id}' references class '{className}', which is not a compiled ICippTest.");
                referenced.Add(className);
            }

            // Every compiled class test must be registered — an orphan class is a wiring bug.
            foreach (var typeName in classTypes.Keys)
            {
                if (!referenced.Contains(typeName))
                    throw new InvalidOperationException(
                        $"Compiled class test '{typeName}' is not present in the registry.");
            }
        }

        // Best-effort location of tests.registry.json relative to the running assembly / cwd. An
        // override wins; otherwise probe up from the assembly dir toward backend/Modules/CIPPTests.
        private static string? ResolveDefaultPath()
        {
            var env = Environment.GetEnvironmentVariable("CIPP_TESTS_REGISTRY");
            if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;

            // Candidates cover both layouts: the repo (backend/Modules/...) and the runtime
            // container, where backend/ is bind-mounted/copied to /app/API so modules sit directly
            // under Modules/ with no backend/ prefix. The prefix-less form also matches when probing
            // from the CIPPTests module dir itself.
            string[] rels =
            {
                "backend/Modules/CIPPTests/tests.registry.json",
                "Modules/CIPPTests/tests.registry.json",
                "CIPPTests/tests.registry.json",
                "tests.registry.json",
            };
            var starts = new List<string>();
            var asmDir = Path.GetDirectoryName(typeof(TestRegistry).Assembly.Location);
            if (!string.IsNullOrEmpty(asmDir)) starts.Add(asmDir);
            starts.Add(Directory.GetCurrentDirectory());

            foreach (var start in starts)
            {
                var dir = new DirectoryInfo(start);
                for (int i = 0; i < 12 && dir != null; i++, dir = dir.Parent)
                {
                    foreach (var rel in rels)
                    {
                        var candidate = Path.Combine(dir.FullName, rel.Replace('/', Path.DirectorySeparatorChar));
                        if (File.Exists(candidate)) return candidate;
                    }
                }
            }
            return null;
        }

        // ── deserialization DTOs (registry file shape) ──────────────────────────────
        private sealed class RegistryFile
        {
            [JsonPropertyName("suites")] public List<RegistrySuite>? Suites { get; set; }
        }

        private sealed class RegistrySuite
        {
            [JsonPropertyName("name")] public string? Name { get; set; }
            [JsonPropertyName("displayName")] public string? DisplayName { get; set; }
            [JsonPropertyName("tests")] public List<RegistryTest>? Tests { get; set; }
        }

        private sealed class RegistryTest
        {
            [JsonPropertyName("id")] public string? Id { get; set; }
            [JsonPropertyName("kind")] public string? Kind { get; set; }
            [JsonPropertyName("class")] public string? Class { get; set; }
            [JsonPropertyName("name")] public string? Name { get; set; }
            [JsonPropertyName("risk")] public string? Risk { get; set; }
            [JsonPropertyName("category")] public string? Category { get; set; }
            [JsonPropertyName("userImpact")] public string? UserImpact { get; set; }
            [JsonPropertyName("implementationEffort")] public string? ImplementationEffort { get; set; }
            [JsonPropertyName("testType")] public string? TestType { get; set; }
            [JsonPropertyName("rule")] public ConfigRule? Rule { get; set; }
            [JsonPropertyName("requiredCapabilities")] public List<string>? RequiredCapabilities { get; set; }
            [JsonPropertyName("dataTypes")] public List<string>? DataTypes { get; set; }
        }
    }
}
