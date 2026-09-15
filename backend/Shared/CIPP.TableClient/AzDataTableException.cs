using System;

namespace CIPP.TableClient;

/// <summary>
/// Wraps a failure from a table operation, carrying a stable error code so callers can
/// branch on it. Derived from PipeHow/AzBobbyTables (MIT); the original carried a
/// PowerShell ErrorRecord, which is replaced here by a plain error-code string.
/// </summary>
public class AzDataTableException : Exception
{
    /// <summary>Stable identifier for the failing operation (e.g. "AddEntitiesError").</summary>
    public string ErrorCode { get; }

    public AzDataTableException(string errorCode, Exception innerException)
        : base(innerException.Message, innerException) => ErrorCode = errorCode;
}
