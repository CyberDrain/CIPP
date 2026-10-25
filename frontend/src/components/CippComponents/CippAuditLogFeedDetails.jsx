// Row details and filters for one tenant's audit log collection (ListAuditLogFeedStatus), shared by the
// Log Collection and Diagnostics tabs of Audit Logs.
export const auditLogFeedOffCanvas = {
  size: 'lg',
  extendedInfoFields: [
    'Tenant',
    'Log',
    'Status',
    'Problem',
    'ProblemDetail',
    'WhatToDo',
    'DelayMinutes',
    'CheckedUpToDateTime',
    'CollectedUpToDateTime',
    'LastCollectedDateTime',
    'NextTryDateTime',
    'Retries',
    'BatchesWaiting',
    'BatchesFailing',
    'OldestWaitingDateTime',
    'LastBatchError',
    'ErrorCode',
    'ErrorDetail',
    'ErrorDateTime',
    'ContentType',
  ],
}

export const auditLogFeedStatuses = [
  'Up to date',
  'Delayed',
  'Error, retrying',
  'Unavailable',
  'Waiting to start',
]

export const auditLogFeedLogs = [
  'Entra ID',
  'Exchange',
  'SharePoint and OneDrive',
  'General (Teams and more)',
]

export const auditLogFeedFilters = [
  ...auditLogFeedStatuses.map((status) => ({
    filterName: status,
    value: [{ id: 'Status', value: status }],
    type: 'column',
  })),
  ...auditLogFeedLogs.map((log) => ({
    filterName: log,
    value: [{ id: 'Log', value: log }],
    type: 'column',
  })),
]
