using System.Collections.Generic;
using CIPP.TableClient;

namespace CIPP.Tests
{
    /// <summary>
    /// Adapter that implements the engine's <see cref="ITableClient"/> by delegating to the
    /// vendored, dependency-free <see cref="VendoredTableClient"/>. This lives in CIPPSharp (not
    /// in CIPP.TableClient) on purpose: CIPPSharp already references CIPP.TableClient, so the
    /// interface must be implemented here to avoid a circular project reference. The vendored
    /// client keeps all Azure.Data.Tables types encapsulated, so this file — and the rest of
    /// CIPPSharp — never touches the Azure SDK directly.
    /// </summary>
    public sealed class CippTableClient : ITableClient
    {
        private readonly VendoredTableClient _inner = new();

        public IEnumerable<string> ReadRows(string table, string partitionKey, string rowKeyPrefix)
            => _inner.ReadRows(table, partitionKey, rowKeyPrefix);

        public void WriteEntities(string table, IEnumerable<IDictionary<string, object>> entities)
            => _inner.WriteEntities(table, entities);
    }
}
