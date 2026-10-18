using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Management.Automation;
using System.Reflection;
using System.Text.RegularExpressions;

namespace CIPP
{
    // Enumerating PSObject.Properties builds reserved member sets and caches that stay attached to every row (~3 KB each).
    // Public so PowerShell can walk a record's own properties the same way: [CIPP.PSMembers]::InstanceProperties($Row).
    public static class PSMembers
    {
        private static readonly Func<object, IEnumerable<PSMemberInfo>?>? s_instanceMembers = Build();
        // Enumerating Properties once adds the reserved pstypenames to the instance members, marked hidden.
        private static readonly Func<PSMemberInfo, bool>? s_isHidden = BuildIsHidden();

        private static Func<PSMemberInfo, bool>? BuildIsHidden()
        {
            try
            {
                var property = typeof(PSMemberInfo).GetProperty("IsHidden", BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance);
                if (property == null || property.PropertyType != typeof(bool)) return null;
                var member = Expression.Parameter(typeof(PSMemberInfo));
                return Expression.Lambda<Func<PSMemberInfo, bool>>(Expression.Property(member, property), member).Compile();
            }
            catch { return null; }
        }

        private static Func<object, IEnumerable<PSMemberInfo>?>? Build()
        {
            try
            {
                var method = typeof(PSObject).GetMethod("HasInstanceMembers", BindingFlags.NonPublic | BindingFlags.Static);
                if (method == null) return null;
                var parameters = method.GetParameters();
                if (parameters.Length != 2 || !parameters[1].ParameterType.IsByRef) return null;
                var collectionType = parameters[1].ParameterType.GetElementType()!;
                if (!typeof(IEnumerable<PSMemberInfo>).IsAssignableFrom(collectionType)) return null;

                var obj = Expression.Parameter(typeof(object));
                var members = Expression.Variable(collectionType);
                var body = Expression.Block(new[] { members },
                    Expression.Condition(Expression.Call(method, obj, members),
                        Expression.Convert(members, typeof(IEnumerable<PSMemberInfo>)),
                        Expression.Constant(null, typeof(IEnumerable<PSMemberInfo>))));
                return Expression.Lambda<Func<object, IEnumerable<PSMemberInfo>?>>(body, obj).Compile();
            }
            catch { return null; }
        }

        public static bool Available => s_instanceMembers != null && s_isHidden != null;

        // Properties.Add minus the member copy and the type-table check (JSON records have no type data): ~1/3 faster
        private static readonly Func<string, bool>? s_isReserved = BuildIsReserved();
        private static readonly Action<PSObject, PSMemberInfo>? s_addInstance = BuildAddInstance();

        private static Func<string, bool>? BuildIsReserved()
        {
            try
            {
                var method = typeof(PSMemberInfoCollection<PSPropertyInfo>).GetMethod("IsReservedName", BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(string) });
                return method == null ? null : (Func<string, bool>)method.CreateDelegate(typeof(Func<string, bool>));
            }
            catch { return null; }
        }

        private static Action<PSObject, PSMemberInfo>? BuildAddInstance()
        {
            try
            {
                var asm = typeof(PSObject).Assembly;
                var replicate = typeof(PSMemberInfo).GetMethod("ReplicateInstance", BindingFlags.NonPublic | BindingFlags.Instance, new[] { typeof(object) });
                var instanceMembers = typeof(PSObject).GetProperty("InstanceMembers", BindingFlags.NonPublic | BindingFlags.Instance);
                var add = instanceMembers?.PropertyType.GetMethod("Add", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, new[] { typeof(PSMemberInfo), typeof(bool) });
                var hasInstanceMember = asm.GetType("System.Management.Automation.Language.PSGetMemberBinder")?.GetMethod("SetHasInstanceMember", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(string) });
                var noteType = asm.GetType("System.Management.Automation.Language.PSVariableAssignmentBinder")?.GetMethod("NoteTypeHasInstanceMemberOrTypeName", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(Type) });
                if (replicate == null || instanceMembers == null || add == null || hasInstanceMember == null || noteType == null) return null;

                var pso = Expression.Parameter(typeof(PSObject));
                var member = Expression.Parameter(typeof(PSMemberInfo));
                var body = Expression.Block(
                    Expression.Call(member, replicate, Expression.Convert(pso, typeof(object))),
                    Expression.Call(Expression.Property(pso, instanceMembers), add, Expression.Convert(member, add.GetParameters()[0].ParameterType), Expression.Constant(false)),
                    Expression.Call(hasInstanceMember, Expression.Property(member, nameof(PSMemberInfo.Name))),
                    Expression.Call(noteType, Expression.Constant(typeof(PSCustomObject))));
                return Expression.Lambda<Action<PSObject, PSMemberInfo>>(body, pso, member).Compile();
            }
            catch { return null; }
        }

        /// <summary>pso.Properties.Add(new PSNoteProperty(name, value)) for a PSCustomObject being built.</summary>
        public static void AddNoteProperty(PSObject pso, string name, object? value)
        {
            var member = new PSNoteProperty(name, value);
            if (s_addInstance == null || s_isReserved == null || s_isReserved(name) || pso.BaseObject is not PSCustomObject) pso.Properties.Add(member);
            else s_addInstance(pso, member);
        }

        public static bool FastAddAvailable => s_addInstance != null && s_isReserved != null;

        // Added properties only: adapted .NET properties of a wrapped value are not included.
        public static IEnumerable<PSPropertyInfo> InstanceProperties(PSObject pso)
        {
            var members = s_instanceMembers!(pso);
            if (members == null) yield break;
            foreach (var m in members)
                if (m is PSPropertyInfo p && !s_isHidden!(p)) yield return p;
        }

        /// <summary>
        /// The record's own string properties whose value is a key of one of <paramref name="lookups"/> (a 36-character
        /// value, checked in order, first hit wins) or, for any other length, contains one of <paramref name="markers"/>
        /// (ordinal). One call per record in place of a PowerShell walk over every property; what a match maps to stays
        /// with the caller.
        /// </summary>
        public static List<PropertyMatch> MatchStringProperties(PSObject pso, IDictionary[] lookups, string[] markers)
        {
            var matches = new List<PropertyMatch>();
            foreach (var property in InstanceProperties(pso))
            {
                var value = property.Value is PSObject wrapped ? wrapped.BaseObject : property.Value;
                if (value is not string text || text.Length == 0) continue;
                if (text.Length == 36)
                {
                    for (int i = 0; i < lookups.Length; i++)
                    {
                        if (lookups[i].Contains(text)) { matches.Add(new PropertyMatch(property.Name, text, i)); break; }
                    }
                    continue;
                }
                foreach (var marker in markers)
                {
                    if (text.Contains(marker, StringComparison.Ordinal)) { matches.Add(new PropertyMatch(property.Name, text, -1)); break; }
                }
            }
            return matches;
        }

        /// <summary>
        /// Joins the record's own string properties against <paramref name="lookups"/> in one call: each 36-character
        /// value that is a key of a lookup (checked in order) gets a note property <paramref name="prefix"/> + name, holding
        /// that entry's <paramref name="fields"/>[i] value, or the whole entry when the field is null or empty. An existing
        /// property of that name is replaced and the new one appended, as Properties.Remove + Add does. Values containing
        /// one of <paramref name="markers"/> are returned for the caller to map; they are not touched here.
        /// </summary>
        public static List<PropertyMatch> MapStringProperties(PSObject pso, IDictionary[] lookups, string[] fields, string prefix, string[] markers)
        {
            var unresolved = new List<PropertyMatch>();
            List<KeyValuePair<string, object?>>? mapped = null;
            foreach (var match in MatchStringProperties(pso, lookups, markers))
            {
                if (match.LookupIndex < 0) { unresolved.Add(match); continue; }
                var entry = lookups[match.LookupIndex][match.Value];
                var field = match.LookupIndex < fields.Length ? fields[match.LookupIndex] : null;
                (mapped ??= new()).Add(new(prefix + match.Name, string.IsNullOrEmpty(field) ? entry : ReadMember(entry, field)));
            }
            if (mapped != null)
            {
                foreach (var pair in mapped)
                {
                    pso.Properties.Remove(pair.Key);
                    AddNoteProperty(pso, pair.Key, pair.Value);
                }
            }
            return unresolved;
        }

        // What $entry.<name> reads for a dictionary or an object entry.
        private static object? ReadMember(object? entry, string name)
        {
            switch (entry is PSObject wrapped && wrapped.BaseObject is not PSCustomObject ? wrapped.BaseObject : entry)
            {
                case IDictionary dictionary: return dictionary.Contains(name) ? dictionary[name] : null;
                case PSObject pso: return pso.Properties[name]?.Value;
                case null: return null;
                case var other: return PSObject.AsPSObject(other).Properties[name]?.Value;
            }
        }

        /// <summary>Adds to <paramref name="target"/> each of the record's own string property values that <paramref name="pattern"/> matches.</summary>
        public static void CollectStringValues(PSObject pso, Regex pattern, ICollection<string> target)
        {
            foreach (var property in InstanceProperties(pso))
            {
                var value = property.Value is PSObject wrapped ? wrapped.BaseObject : property.Value;
                if (value is string text && pattern.IsMatch(text)) target.Add(text);
            }
        }

        /// <summary>$Object.PSObject.Copy() less the named properties, in one call: each Properties.Remove made from PowerShell costs ~25 us.</summary>
        public static PSObject CopyExcept(PSObject pso, string[] names)
        {
            var copy = pso.Copy();
            foreach (var name in names) copy.Properties.Remove(name);
            return copy;
        }

        /// <summary>
        /// Add-Member -NotePropertyMembers in one call, in the dictionary's order. A name that is already a member is
        /// replaced (removed, then appended) when <paramref name="force"/>, else left as it is; a name Add-Member would
        /// refuse is skipped, as -ErrorAction SilentlyContinue does.
        /// </summary>
        public static void AddNoteProperties(PSObject pso, IDictionary members, bool force)
        {
            foreach (DictionaryEntry entry in members)
            {
                var name = entry.Key as string ?? entry.Key?.ToString();
                if (string.IsNullOrEmpty(name)) continue;
                try
                {
                    if (pso.Members[name] != null)
                    {
                        if (!force) continue;
                        pso.Members.Remove(name);
                    }
                    AddNoteProperty(pso, name, entry.Value);
                }
                catch (Exception ex) when (ex is ExtendedTypeSystemException or ArgumentException) { }
            }
        }

        public static bool HasNoteProperty(PSObject pso)
        {
            var members = s_instanceMembers!(pso);
            if (members == null) return false;
            foreach (var m in members)
                if (m is PSNoteProperty && !s_isHidden!(m)) return true;
            return false;
        }
    }

    /// <summary>A property found by PSMembers.MatchStringProperties: LookupIndex is the matching lookup, or -1 for a marker.</summary>
    public sealed record PropertyMatch(string Name, string Value, int LookupIndex);
}
