// PDF generation benchmark and profiling harness. It renders CIPP's own reports (fixtures/*.json, built from the
// real report builders by Export-PdfBenchFixtures.ps1) through the report kit, the same call the API makes.
//
//   dotnet run -c Release --project build/tools/pdf-bench -- <mode> [options]
//   dotnet run -c Release --project build/tools/pdf-bench -p:OfficeImoSource=C:\GitHub\OfficeIMO -- <mode> ...
//
// Modes:
//   bench      time, allocation, GC counts and peak heap per report (--iterations 10 --warmup 3)
//              --save results/<label>.json keeps the run; --compare results/<label>.json prints the change
//   verify     renders every report and checks it is byte-identical to baseline.sha256.json (--update rewrites it);
//              the gate for an optimisation that must not change output
//   write      writes each report's PDF to out/ to look at
//   alloc      what the renders allocate, by type, split small/large object heap (sampled GC allocation ticks)
//   loop       renders for --seconds (default 30) so a profiler can attach, e.g.
//              dotnet-trace collect --format speedscope -- dotnet bin/Release/net8.0/PdfBench.dll loop --seconds 30
//   concurrent --parallel N renders at once for --seconds, like several API workers in one process:
//              throughput, latency, peak heap and working set (--gcinfo prints the GC configuration in effect)
//   cverify    --parallel N threads render in shuffled orders and check every output against the baseline hashes;
//              the gate for any change that shares state between renders (a cache)
//   retained   live and committed heap after each of --rounds passes: memory a change keeps between renders
//   cold       time of the Nth pass in a fresh process (--at 1,2,3,5,10,30,100), for first-render cost after a restart
// Every mode takes --filter <substring> (or --exclude a,b) to pick reports. bench reports CPU cycles (Mcyc), which
// hold up when the machine is busy; wall-clock times do not. -p:KitDir=<a copy of Reporting\> benches a report-kit
// change without touching the tree.
//
// Production runs the kit on .NET 8 with workstation GC (the Craft image: DOTNET_gcServer=0, GCConserveMemory=7,
// a heap hard limit), so this targets net8.0. Keep it there: .NET 9+ compresses with zlib-ng, which changes the
// bytes of every Flate stream and so every hash in baseline.sha256.json.

using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Tracing;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using CIPP.Reporting;

var opts = Options.Parse(args);
var root = AppContext.BaseDirectory;
var projectDir = FindProjectDir();
var fixtures = Fixture.LoadAll(Path.Combine(projectDir, "fixtures"), opts.Get("filter"));
if (opts.Get("exclude") is { } ex) fixtures = fixtures.Where(f => !ex.Split(',').Any(x => f.Name.Contains(x, StringComparison.OrdinalIgnoreCase))).ToList();
if (fixtures.Count == 0) { Console.Error.WriteLine("No fixtures matched."); return 1; }
Console.WriteLine($"OfficeIMO.Pdf {Fixture.EngineVersion()} | {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription} | {fixtures.Count} reports");

switch (opts.Mode)
{
    case "bench": return Modes.Bench(fixtures, opts, projectDir);
    case "verify": return Modes.Verify(fixtures, opts, projectDir);
    case "write": return Modes.Write(fixtures, opts, projectDir);
    case "alloc": return Modes.Alloc(fixtures, opts);
    case "loop": return Modes.Loop(fixtures, opts);
    case "concurrent": return Modes.Concurrent(fixtures, opts);
    case "retained": return Modes.Retained(fixtures, opts);
    case "cold": return Modes.Cold(fixtures, opts);
    case "cverify": return Modes.ConcurrentVerify(fixtures, opts, projectDir);
    default: Console.Error.WriteLine($"Unknown mode '{opts.Mode}'. Modes: bench, verify, write, alloc, loop, concurrent, cverify, retained, cold."); return 1;
}

static string FindProjectDir()
{
    for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        if (File.Exists(Path.Combine(dir.FullName, "PdfBench.csproj"))) return dir.FullName;
    throw new InvalidOperationException("PdfBench.csproj not found above " + AppContext.BaseDirectory);
}

sealed record Fixture(string Name, string Blocks, string Variables, string Branding, string Tenant, string ReportName, bool Landscape)
{
    // Fixed so the output is byte-for-byte repeatable.
    const string GeneratedOn = "September 23, 2026";

    public byte[] Render() => ReportPdf.Render(Blocks, Branding, Variables, Tenant, ReportName, GeneratedOn, "A4", Landscape, true);

    public static List<Fixture> LoadAll(string dir, string? filter) =>
        Directory.GetFiles(dir, "*.json").OrderBy(f => f, StringComparer.Ordinal)
            .Where(f => filter is null || Path.GetFileNameWithoutExtension(f).Contains(filter, StringComparison.OrdinalIgnoreCase))
            .Select(f =>
            {
                var j = JsonNode.Parse(File.ReadAllText(f))!;
                return new Fixture(Path.GetFileNameWithoutExtension(f), (string)j["blocks"]!, (string)j["variables"]!, (string)j["branding"]!,
                    (string)j["tenant"]!, (string)j["reportName"]!, (bool)j["landscape"]!);
            }).ToList();

    public static string EngineVersion() =>
        typeof(OfficeIMO.Pdf.PdfDocument).Assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false)
            .OfType<System.Reflection.AssemblyInformationalVersionAttribute>().FirstOrDefault()?.InformationalVersion ?? "?";

    public static string Sha(byte[] b) => Convert.ToHexString(SHA256.HashData(b));
    public static int Pages(byte[] b) => OfficeIMO.Pdf.PdfReadDocument.Open(b).Pages.Count;
}

sealed class Options
{
    public string Mode = "bench";
    readonly Dictionary<string, string?> values = new(StringComparer.OrdinalIgnoreCase);
    public static Options Parse(string[] args)
    {
        var o = new Options();
        var i = 0;
        if (args.Length > 0 && !args[0].StartsWith("--")) o.Mode = args[i++].ToLowerInvariant();
        for (; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--")) continue;
            var key = args[i][2..];
            o.values[key] = i + 1 < args.Length && !args[i + 1].StartsWith("--") ? args[++i] : "true";
        }
        return o;
    }
    public string? Get(string key) => values.TryGetValue(key, out var v) ? v : null;
    public int Int(string key, int fallback) => int.TryParse(Get(key), out var v) ? v : fallback;
    public bool Flag(string key) => Get(key) == "true";
}

sealed record Result(string Name, int Pages, long Bytes, string Sha256, bool Deterministic, double MedianMs, double MinMs,
    double AllocMB, double Gen0, double Gen1, double Gen2, double PeakHeapMB, double CpuMs = 0);

static class Modes
{
    public static int Bench(List<Fixture> fixtures, Options opts, string projectDir)
    {
        int iterations = opts.Int("iterations", 10), warmup = opts.Int("warmup", 3);
        var results = new List<Result>();
        Console.WriteLine($"{"report",-26} {"pages",5} {"KB",7} {"median ms",10} {"min ms",8} {"alloc MB",9} {"gen0",6} {"gen1",6} {"gen2",6} {"peak MB",8}");
        foreach (var f in fixtures)
        {
            byte[] bytes = Array.Empty<byte>();
            for (var w = 0; w < warmup; w++) bytes = f.Render();
            var sha = Fixture.Sha(bytes);
            var deterministic = true;
            var times = new List<double>();
            var cpus = new List<double>();
            var proc = Process.GetCurrentProcess();
            long alloc = 0; int g0 = 0, g1 = 0, g2 = 0;
            for (var i = 0; i < iterations; i++)
            {
                GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
                int c0 = GC.CollectionCount(0), c1 = GC.CollectionCount(1), c2 = GC.CollectionCount(2);
                var a0 = GC.GetTotalAllocatedBytes(true);
                var cpu0 = Cycles.Now();
                var sw = Stopwatch.StartNew();
                bytes = f.Render();
                sw.Stop();
                cpus.Add((Cycles.Now() - cpu0) / 1e6);
                alloc += GC.GetTotalAllocatedBytes(true) - a0;
                g0 += GC.CollectionCount(0) - c0; g1 += GC.CollectionCount(1) - c1; g2 += GC.CollectionCount(2) - c2;
                times.Add(sw.Elapsed.TotalMilliseconds);
                deterministic &= Fixture.Sha(bytes) == sha;
            }
            times.Sort(); cpus.Sort();
            var r = new Result(f.Name, Fixture.Pages(bytes), bytes.Length, sha, deterministic, times[times.Count / 2], times[0],
                alloc / (double)iterations / 1048576, g0 / (double)iterations, g1 / (double)iterations, g2 / (double)iterations, PeakHeapMB(f), cpus[cpus.Count / 2]);
            results.Add(r);
            Console.WriteLine($"{r.Name,-26} {r.Pages,5} {r.Bytes / 1024,7} {r.MedianMs,10:F1} {r.MinMs,8:F1} {r.AllocMB,9:F1} {r.Gen0,6:F1} {r.Gen1,6:F1} {r.Gen2,6:F1} {r.PeakHeapMB,8:F1} Mcyc {r.CpuMs,7:F1}{(r.Deterministic ? "" : "  NONDETERMINISTIC")}");
        }
        Console.WriteLine($"{"TOTAL",-26} {results.Sum(r => r.Pages),5} {results.Sum(r => r.Bytes) / 1024,7} {results.Sum(r => r.MedianMs),10:F1} {results.Sum(r => r.MinMs),8:F1} {results.Sum(r => r.AllocMB),9:F1} {results.Sum(r => r.Gen0),6:F1} {results.Sum(r => r.Gen1),6:F1} {results.Sum(r => r.Gen2),6:F1} {results.Max(r => r.PeakHeapMB),8:F1} Mcyc {results.Sum(r => r.CpuMs),7:F1}");

        if (opts.Get("save") is { } save)
        {
            var path = Path.IsPathRooted(save) ? save : Path.Combine(projectDir, save);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonSerializer.Serialize(new { engine = Fixture.EngineVersion(), runtime = Environment.Version.ToString(), iterations, results }, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine($"saved {path}");
        }
        if (opts.Get("compare") is { } compare) Compare(results, Path.IsPathRooted(compare) ? compare : Path.Combine(projectDir, compare));
        return 0;
    }

    // Peak managed heap growth over one render, sampled from another thread against a collected baseline.
    static double PeakHeapMB(Fixture f)
    {
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        var baseline = GC.GetTotalMemory(true);
        long peak = baseline;
        var running = true;
        var sampler = new Thread(() => { while (Volatile.Read(ref running)) { var m = GC.GetTotalMemory(false); if (m > peak) peak = m; Thread.Yield(); } }) { IsBackground = true };
        sampler.Start();
        f.Render();
        Volatile.Write(ref running, false);
        sampler.Join();
        return (peak - baseline) / 1048576.0;
    }

    static void Compare(List<Result> current, string path)
    {
        var doc = JsonNode.Parse(File.ReadAllText(path))!;
        var before = doc["results"]!.AsArray().ToDictionary(n => (string)n!["Name"]!, n => n!);
        Console.WriteLine($"\nvs {Path.GetFileName(path)} (engine {(string?)doc["engine"]})");
        Console.WriteLine($"{"report",-26} {"median ms",18} {"alloc MB",18} {"peak MB",18}  output");
        static string Delta(double b, double a) => $"{b,7:F1}->{a,-7:F1}{(b == 0 ? "" : $"{(a - b) / b,+4:P0}")}";
        foreach (var r in current)
        {
            if (!before.TryGetValue(r.Name, out var b)) { Console.WriteLine($"{r.Name,-26} (new)"); continue; }
            var same = (string?)b["Sha256"] == r.Sha256 ? "identical" : "CHANGED";
            Console.WriteLine($"{r.Name,-26} {Delta((double)b["MedianMs"]!, r.MedianMs),18} {Delta((double)b["AllocMB"]!, r.AllocMB),18} {Delta((double)b["PeakHeapMB"]!, r.PeakHeapMB),18}  {same}");
        }
        double Sum(string key) => current.Where(r => before.ContainsKey(r.Name)).Sum(r => (double)before[r.Name][key]!);
        Console.WriteLine($"{"TOTAL",-26} {Delta(Sum("MedianMs"), current.Where(r => before.ContainsKey(r.Name)).Sum(r => r.MedianMs)),18} {Delta(Sum("AllocMB"), current.Where(r => before.ContainsKey(r.Name)).Sum(r => r.AllocMB)),18}");
    }

    public static int Verify(List<Fixture> fixtures, Options opts, string projectDir)
    {
        var path = Path.Combine(projectDir, "baseline.sha256.json");
        var baseline = File.Exists(path) ? JsonSerializer.Deserialize<SortedDictionary<string, string>>(File.ReadAllText(path))! : new SortedDictionary<string, string>();
        var failed = 0;
        foreach (var f in fixtures)
        {
            var sha = Fixture.Sha(f.Render());
            var known = baseline.TryGetValue(f.Name, out var expected);
            if (opts.Flag("update")) { baseline[f.Name] = sha; Console.WriteLine($"{f.Name,-26} {sha[..16]}"); continue; }
            var ok = known && expected == sha;
            if (!ok) failed++;
            Console.WriteLine($"{f.Name,-26} {(ok ? "identical" : known ? "CHANGED" : "no baseline")}");
        }
        if (opts.Flag("update")) { File.WriteAllText(path, JsonSerializer.Serialize(baseline, new JsonSerializerOptions { WriteIndented = true })); Console.WriteLine($"wrote {path}"); return 0; }
        Console.WriteLine(failed == 0 ? "all identical" : $"{failed} changed");
        return failed == 0 ? 0 : 1;
    }

    public static int Write(List<Fixture> fixtures, Options opts, string projectDir)
    {
        var dir = opts.Get("out") ?? Path.Combine(projectDir, "out");
        Directory.CreateDirectory(dir);
        foreach (var f in fixtures)
        {
            var bytes = f.Render();
            File.WriteAllBytes(Path.Combine(dir, f.Name + ".pdf"), bytes);
            Console.WriteLine($"{f.Name,-26} {Fixture.Pages(bytes),4} pages {bytes.Length / 1024,6} KB");
        }
        Console.WriteLine($"wrote {dir}");
        return 0;
    }

    public static int Alloc(List<Fixture> fixtures, Options opts)
    {
        int iterations = opts.Int("iterations", 5), top = opts.Int("top", 30);
        foreach (var f in fixtures) f.Render();  // JIT and caches out of the picture
        using var listener = new AllocListener();
        listener.Recording = true;
        var a0 = GC.GetTotalAllocatedBytes(true);
        for (var i = 0; i < iterations; i++) foreach (var f in fixtures) f.Render();
        var total = GC.GetTotalAllocatedBytes(true) - a0;
        listener.Recording = false;
        var sampled = listener.ByType.Values.Sum(v => v.Small + v.Large);
        Console.WriteLine($"allocated {total / 1048576.0:F1} MB over {iterations} x {fixtures.Count} renders ({total / 1048576.0 / iterations / fixtures.Count:F2} MB/render); sampled {sampled / 1048576.0:F1} MB");
        Console.WriteLine($"small object heap {listener.ByType.Values.Sum(v => v.Small) * 100.0 / sampled:F1}%   large object heap {listener.ByType.Values.Sum(v => v.Large) * 100.0 / sampled:F1}%\n");
        Console.WriteLine($"{"share",7} {"LOH",6}  type");
        foreach (var (type, v) in listener.ByType.OrderByDescending(kv => kv.Value.Small + kv.Value.Large).Take(top))
            Console.WriteLine($"{(v.Small + v.Large) * 100.0 / sampled,6:F1}% {(v.Large * 100.0 / Math.Max(1, v.Small + v.Large)),5:F0}%  {type}");
        return 0;
    }

    public static int Loop(List<Fixture> fixtures, Options opts)
    {
        var seconds = opts.Int("seconds", 30);
        var sw = Stopwatch.StartNew();
        var renders = 0;
        while (sw.Elapsed.TotalSeconds < seconds) foreach (var f in fixtures) { f.Render(); renders++; }
        Console.WriteLine($"{renders} renders in {sw.Elapsed.TotalSeconds:F1}s");
        return 0;
    }

    // Live heap after full GCs between rounds of the corpus: memory a render leaves behind (static caches).
    public static int Retained(List<Fixture> fixtures, Options opts)
    {
        int rounds = opts.Int("rounds", 10);
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        var start = GC.GetTotalMemory(true);
        Console.WriteLine($"before any render: {start / 1048576.0:F1} MB");
        for (var r = 1; r <= rounds; r++)
        {
            foreach (var f in fixtures) f.Render();
            GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect(2, GCCollectionMode.Forced, true, true);
            var info = GC.GetGCMemoryInfo();
            Console.WriteLine($"round {r,3}: live {GC.GetTotalMemory(true) / 1048576.0,7:F1} MB | committed {info.TotalCommittedBytes / 1048576.0,7:F1} MB | fragmented {info.FragmentedBytes / 1048576.0,6:F1} MB | ws {Process.GetCurrentProcess().WorkingSet64 / 1048576.0,6:F0} MB");
        }
        return 0;
    }

    // Time of the Nth render in a fresh process (JIT tiers), for each N in --at (default 1,2,3,5,10,30,100).
    public static int Cold(List<Fixture> fixtures, Options opts)
    {
        var at = (opts.Get("at") ?? "1,2,3,5,10,30,100").Split(',').Select(int.Parse).ToHashSet();
        var max = at.Max();
        var total = Stopwatch.StartNew();
        for (var n = 1; n <= max; n++)
        {
            var sw = Stopwatch.StartNew(); var c0 = Cycles.Now();
            foreach (var f in fixtures) f.Render();
            if (at.Contains(n)) Console.WriteLine($"pass {n,4}: {sw.Elapsed.TotalMilliseconds,8:F1} ms {(Cycles.Now() - c0) / 1e6,8:F0} Mcyc (cumulative {total.Elapsed.TotalMilliseconds:F0} ms)");
        }
        return 0;
    }

    // --parallel threads render the fixtures in shuffled orders at once and check every output against
    // baseline.sha256.json: the gate for a shared cache (a render must not see another's state).
    public static int ConcurrentVerify(List<Fixture> fixtures, Options opts, string projectDir)
    {
        int parallel = opts.Int("parallel", 8), rounds = opts.Int("rounds", 3);
        var baseline = JsonSerializer.Deserialize<SortedDictionary<string, string>>(File.ReadAllText(Path.Combine(projectDir, "baseline.sha256.json")))!;
        var bad = new ConcurrentBag<string>(); var count = 0;
        var threads = Enumerable.Range(0, parallel).Select(w => new Thread(() =>
        {
            var rng = new Random(w);
            for (var r = 0; r < rounds; r++)
                foreach (var f in fixtures.OrderBy(_ => rng.Next()))
                {
                    if (Fixture.Sha(f.Render()) != baseline[f.Name]) bad.Add(f.Name);
                    Interlocked.Increment(ref count);
                }
        })).ToList();
        threads.ForEach(t => t.Start()); threads.ForEach(t => t.Join());
        Console.WriteLine(bad.IsEmpty ? $"{count} concurrent renders, all identical" : $"{bad.Count} of {count} CHANGED: {string.Join(", ", bad.Distinct())}");
        return bad.IsEmpty ? 0 : 1;
    }

    public static int Concurrent(List<Fixture> fixtures, Options opts)
    {
        int parallel = opts.Int("parallel", 4), seconds = opts.Int("seconds", 20);
        if (opts.Flag("gcinfo")) Console.WriteLine($"gc: server={System.Runtime.GCSettings.IsServerGC} latency={System.Runtime.GCSettings.LatencyMode} " + string.Join(" ", GC.GetConfigurationVariables().Where(kv => kv.Key is "ConcurrentGC" or "GCConserveMem" or "GCHeapHardLimit").Select(kv => $"{kv.Key}={kv.Value}")));
        foreach (var f in fixtures) f.Render();
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        var baseline = GC.GetTotalMemory(true);
        long peak = baseline;
        var latencies = new ConcurrentBag<double>();
        var stop = Stopwatch.StartNew();
        int c2 = GC.CollectionCount(2), c1 = GC.CollectionCount(1), c0 = GC.CollectionCount(0); var pause0 = GC.GetTotalPauseDuration();
        var a0 = GC.GetTotalAllocatedBytes(true);
        var sampling = true;
        var sampler = new Thread(() => { while (Volatile.Read(ref sampling)) { var m = GC.GetTotalMemory(false); if (m > peak) peak = m; Thread.Sleep(1); } }) { IsBackground = true };
        sampler.Start();
        var workers = Enumerable.Range(0, parallel).Select(w => new Thread(() =>
        {
            for (var i = w; stop.Elapsed.TotalSeconds < seconds; i++)
            {
                var sw = Stopwatch.StartNew();
                fixtures[i % fixtures.Count].Render();
                latencies.Add(sw.Elapsed.TotalMilliseconds);
            }
        })).ToList();
        workers.ForEach(t => t.Start());
        workers.ForEach(t => t.Join());
        Volatile.Write(ref sampling, false);
        sampler.Join();
        var elapsed = stop.Elapsed.TotalSeconds;
        var sorted = latencies.OrderBy(x => x).ToList();
        Console.WriteLine($"{parallel} parallel: {sorted.Count} renders in {elapsed:F1}s = {sorted.Count / elapsed:F1}/s | latency p50 {sorted[sorted.Count / 2]:F0} ms p95 {sorted[(int)(sorted.Count * 0.95)]:F0} ms");
        Console.WriteLine($"allocation {(GC.GetTotalAllocatedBytes(true) - a0) / 1048576.0 / elapsed:F0} MB/s | gen0 {GC.CollectionCount(0) - c0} gen1 {GC.CollectionCount(1) - c1} gen2 {GC.CollectionCount(2) - c2} pause {(GC.GetTotalPauseDuration() - pause0).TotalMilliseconds:F0} ms | peak heap growth {(peak - baseline) / 1048576.0:F0} MB | peak working set {Process.GetCurrentProcess().PeakWorkingSet64 / 1048576.0:F0} MB");
        return 0;
    }
}

// Sums the runtime's GCAllocationTick events (one about every 100 KB allocated) by type and heap.
sealed class AllocListener : EventListener
{
    public volatile bool Recording;
    public readonly ConcurrentDictionary<string, (long Small, long Large)> ByType = new();
    protected override void OnEventSourceCreated(EventSource source)
    {
        if (source.Name == "Microsoft-Windows-DotNETRuntime") EnableEvents(source, EventLevel.Verbose, (EventKeywords)0x1);
    }
    protected override void OnEventWritten(EventWrittenEventArgs e)
    {
        if (!Recording || e.EventName?.StartsWith("GCAllocationTick") != true || e.Payload is null) return;
        var names = e.PayloadNames!;
        var type = e.Payload[names.IndexOf("TypeName")] as string ?? "?";
        var amountIndex = names.IndexOf("AllocationAmount64");
        var amount = amountIndex >= 0 ? Convert.ToInt64(e.Payload[amountIndex]) : Convert.ToInt64(e.Payload[names.IndexOf("AllocationAmount")]);
        var large = Convert.ToInt32(e.Payload[names.IndexOf("AllocationKind")]) == 1;
        ByType.AddOrUpdate(type, large ? (0, amount) : (amount, 0), (_, v) => large ? (v.Small, v.Large + amount) : (v.Small + amount, v.Large));
    }
}

static class Cycles
{
    [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern bool QueryProcessCycleTime(IntPtr h, out ulong c);
    [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    public static double Now() { QueryProcessCycleTime(GetCurrentProcess(), out var c); return c; }
}
