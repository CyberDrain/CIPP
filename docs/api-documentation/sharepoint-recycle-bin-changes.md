# SharePoint Recycle Bin API Changes

## Fixed Endpoints

### ExecEmptySiteRecycleBin

**Bug Fixed**: The endpoint previously reported success without verifying deletion. On 10/13/2026, it returned HTTP 200 with `deletedAttempts: 2` when nothing was actually deleted from a bin containing 500 items (114 GB).

**Changes**:

1. **Verification After Bulk Delete**: After calling bulk delete endpoints (`deleteAll()`, `deleteAllSecondStageItems`), the endpoint now re-reads the recycle bin to verify items were actually deleted.

2. **Fallback to Batched Deletion**: If items remain after bulk deletion (e.g., due to retention policies or legal holds), the endpoint falls back to deleting items by ID in batches of 25.

3. **Throttling Handling**: Batch deletion now handles HTTP 429 (Too Many Requests) and 503 (Service Unavailable) responses by respecting the `Retry-After` header and retrying up to 5 times per batch.

4. **Accurate Counts and Metrics**: The response now includes:
   - `itemsBefore`: Total items before deletion
   - `itemsDeleted`: Items successfully deleted
   - `itemsRemaining`: Items that could not be deleted
   - `bytesFreed`: Bytes freed by deletion
   - `firstStage`: Detailed stats for first-stage recycle bin (when applicable)
     - `beforeCount`, `beforeBytes`, `deletedCount`, `bytesFreed`, `remainingCount`, `remainingBytes`
   - `secondStage`: Detailed stats for second-stage recycle bin (when applicable)
     - `beforeCount`, `beforeBytes`, `deletedCount`, `bytesFreed`, `remainingCount`, `remainingBytes`

5. **Clear Error Messages**: When items remain after deletion attempts, the endpoint returns a clear message indicating items may be held by retention policies or legal holds, and surfaces SharePoint's error messages.

6. **Proper Logging**: Logs now reflect the actual outcome (Info for complete success, Warn for partial success, Error for complete failure).

**Request Schema** (unchanged):
```json
{
  "tenantFilter": "contoso.onmicrosoft.com",
  "SiteUrl": "https://contoso.sharepoint.com/sites/teamsite",
  "Stage": "Both|First|Second"
}
```

**Response Schema** (updated):
```json
{
  "Results": "Successfully emptied recycle bin (Both) for https://contoso.sharepoint.com/sites/teamsite. Deleted 500 items, freed 114000 MB.",
  "itemsBefore": 500,
  "itemsDeleted": 500,
  "itemsRemaining": 0,
  "bytesFreed": 119537778688,
  "firstStage": {
    "beforeCount": 500,
    "beforeBytes": 119537778688,
    "deletedCount": 500,
    "bytesFreed": 119537778688,
    "remainingCount": 0,
    "remainingBytes": 0
  },
  "secondStage": null
}
```

**Partial Success Response** (when items remain):
```json
{
  "Results": "Partially emptied recycle bin (First) for https://contoso.sharepoint.com/sites/teamsite. Deleted 400 of 500 items, 100 items remain (may be held by retention policy or legal hold).",
  "itemsBefore": 500,
  "itemsDeleted": 400,
  "itemsRemaining": 100,
  "bytesFreed": 95630222950,
  "firstStage": {
    "beforeCount": 500,
    "beforeBytes": 119537778688,
    "deletedCount": 400,
    "bytesFreed": 95630222950,
    "remainingCount": 100,
    "remainingBytes": 23907555738
  },
  "secondStage": null
}
```

### ListSiteRecycleBinSummary

**Bug Fixed**: The endpoint stopped at 500 items and incorrectly reported `capped: false` because SharePoint's RecycleBin REST API doesn't return `@odata.nextLink`.

**Changes**:

1. **Skip-Based Pagination**: Replaced `@odata.nextLink`-based pagination with `$skip`-based pagination that increments by the page size (500) until no more items are returned.

2. **Correct Capping**: The `capped` field is now set to `true` only when the `MaxItems` limit is reached, not when the endpoint naturally exhausts all items.

3. **Reads All Items**: The endpoint now correctly reads all items in the recycle bin (up to `MaxItems`, default 5000, max 20000) instead of stopping at the first 500.

**Request Schema** (unchanged):
```
GET /api/ListSiteRecycleBinSummary?TenantFilter=contoso.onmicrosoft.com&SiteUrl=https://contoso.sharepoint.com/sites/teamsite&MaxItems=5000
```

**Response Schema** (unchanged):
```json
{
  "Results": {
    "siteUrl": "https://contoso.sharepoint.com/sites/teamsite",
    "itemCount": 5500,
    "totalBytes": 119537778688,
    "firstStageCount": 5500,
    "firstStageBytes": 119537778688,
    "secondStageCount": 0,
    "secondStageBytes": 0,
    "capped": true,
    "scannedItems": 5000
  }
}
```

### ListSiteRecycleBin

**Bug Fixed**: Same pagination issue as `ListSiteRecycleBinSummary` - stopped at 500 items.

**Changes**:

1. **Skip-Based Pagination**: Now uses `$skip`-based pagination to read all recycle bin items instead of stopping at 500.

**Request Schema** (unchanged):
```
GET /api/ListSiteRecycleBin?TenantFilter=contoso.onmicrosoft.com&SiteUrl=https://contoso.sharepoint.com/sites/teamsite
```

**Response Schema** (unchanged):
```json
{
  "Results": [
    {
      "Id": "00000000-0000-0000-0000-000000000000",
      "Title": "Document.docx",
      "LeafName": "Document.docx",
      "DirName": "Shared Documents",
      "ItemType": "File",
      "ItemState": "First Stage",
      "Size": 12345,
      "DeletedByName": "John Doe",
      "DeletedDate": "2026-10-13T10:30:00Z"
    }
  ]
}
```

## Testing Against a Live Site

To verify these fixes against a real SharePoint site:

1. **Setup**: Create a test site with items in the recycle bin (or use an existing site with a populated recycle bin).

2. **Test ListSiteRecycleBinSummary**:
   ```bash
   curl -X GET "https://your-cipp-instance/api/ListSiteRecycleBinSummary?TenantFilter=contoso.onmicrosoft.com&SiteUrl=https://contoso.sharepoint.com/sites/test&MaxItems=10000" \
     -H "Authorization: Bearer YOUR_TOKEN"
   ```
   - Verify `scannedItems` matches the actual number of items in the bin (not capped at 500)
   - Verify `capped: false` when all items are scanned
   - Verify `capped: true` only when `MaxItems` is reached

3. **Test ExecEmptySiteRecycleBin with verification**:
   ```bash
   # First, check the current state
   curl -X GET "https://your-cipp-instance/api/ListSiteRecycleBinSummary?TenantFilter=contoso.onmicrosoft.com&SiteUrl=https://contoso.sharepoint.com/sites/test"
   
   # Then empty the bin
   curl -X POST "https://your-cipp-instance/api/ExecEmptySiteRecycleBin" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -d '{
       "tenantFilter": "contoso.onmicrosoft.com",
       "SiteUrl": "https://contoso.sharepoint.com/sites/test",
       "Stage": "Both"
     }'
   
   # Verify the response includes accurate counts
   # Check: itemsBefore, itemsDeleted, itemsRemaining, bytesFreed
   # Check: firstStage and secondStage detailed stats
   
   # Finally, verify the bin is actually empty
   curl -X GET "https://your-cipp-instance/api/ListSiteRecycleBinSummary?TenantFilter=contoso.onmicrosoft.com&SiteUrl=https://contoso.sharepoint.com/sites/test"
   ```

4. **Test with Retention Policies**:
   - Apply a retention policy or legal hold to some items
   - Attempt to empty the recycle bin
   - Verify the response shows `itemsRemaining > 0`
   - Verify the Results message indicates items are held by retention policy or legal hold
   - Verify the HTTP status is still 200 (partial success, not error)

## Backward Compatibility

- **Request schemas**: Unchanged, fully backward compatible
- **Response schema for ExecEmptySiteRecycleBin**: Extended with new fields; existing `Results` field still present
  - Old clients ignoring new fields will continue to work
  - The `deletedAttempts` field has been removed (it was misleading); replaced with accurate `itemsDeleted`
- **Response schemas for List endpoints**: Unchanged
