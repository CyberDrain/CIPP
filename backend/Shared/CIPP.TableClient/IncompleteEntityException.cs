using System;

namespace CIPP.TableClient;

/// <summary>
/// Thrown when a split entity cannot be reassembled because some of the rows or chunk
/// properties it was split into are not present.
/// </summary>
/// <remarks>
/// An incomplete read fails rather than returning what it managed to reassemble, which
/// would be indistinguishable from the real value.
/// </remarks>
public class IncompleteEntityException : Exception
{
    /// <summary>The PartitionKey of the entity that could not be reassembled.</summary>
    public string EntityPartitionKey { get; }

    /// <summary>The RowKey of the entity that could not be reassembled.</summary>
    public string EntityRowKey { get; }

    /// <summary>Create an exception for an entity that could not be reassembled.</summary>
    public IncompleteEntityException(string partitionKey, string rowKey, string message)
        : base(message)
    {
        EntityPartitionKey = partitionKey;
        EntityRowKey = rowKey;
    }
}
