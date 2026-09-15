# Attribution

The table-client code in this assembly is derived from
[PipeHow/AzBobbyTables](https://github.com/PipeHow/AzBobbyTables) (the
`AzBobbyTables.Core` project), licensed under the MIT License. See
`LICENSE.AzBobbyTables` for the original license text.

Files derived from AzBobbyTables:

- `AzDataTableService.cs`
- `EntitySplitter.cs`
- `ExternalTokenCredential.cs`
- `Helpers.cs`
- `AzDataTableException.cs`
- `IncompleteEntityException.cs`

This copy was vendored into CIPP from the intermediate RevealReports vendoring
(`RevealReports.TableClient`), which itself derived from AzBobbyTables.

Changes made when vendoring into CIPP:

- The PowerShell coupling was removed upstream (the `Conversion/` and `Logging/`
  folders were dropped; input/output work directly in terms of
  `Azure.Data.Tables.TableEntity`; `AzDataTableException` carries a plain
  error-code string instead of a PowerShell `ErrorRecord`).
- Retargeted from `net10.0` to `net8.0` (CIPP runs on PowerShell 7.4 / .NET 8).
- The `Microsoft.Extensions.Logging.ILogger` dependency was removed so this
  assembly's only package reference is `Azure.Data.Tables`. Internal diagnostic
  logging was dropped; the reassembly warning/incomplete-entity callbacks are
  surfaced through the existing `Action<string> onWarning` parameter instead.
- `Azure.Data.Tables` 12.11.0 is bundled with runtime assets included (Craft
  vendors the same version; the dual-stack Azure Functions host supplies none),
  where the RevealReports copy excluded runtime assets.

The `namespace` is CIPP-owned (`CIPP.TableClient`). The `CIPP.Tests` adapter
(`CippTableClient`) and the `ITableClient` contract are original CIPP code, not
derived from AzBobbyTables.
