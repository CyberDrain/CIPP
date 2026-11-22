import { useMemo, useState } from 'react'
import PropTypes from 'prop-types'
import {
  Alert,
  Breadcrumbs,
  Dialog,
  DialogContent,
  DialogTitle,
  IconButton,
  Link,
  Stack,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { CippDataTable } from '../CippTable/CippDataTable'
import { ApiGetCall } from '../../api/ApiCall'
import { usePermissions } from '../../hooks/use-permissions'
import { getCippError } from '../../utils/get-cipp-error'
import {
  ARCHIVE_WAIT_NOTE,
  getArchiveFileActions,
} from '../../utils/sharepoint-archive'

const EMPTY_ROWS = []
const BROWSE_COLUMNS = [
  'name',
  'type',
  'sizeInBytes',
  'percentOfLibrary',
  'itemCount',
  'archiveStatus',
  'lastModifiedDateTime',
  'lastModifiedBy',
]
const LARGEST_COLUMNS = [
  'name',
  'type',
  'folderPath',
  'sizeInBytes',
  'percentOfLibrary',
  'archiveStatus',
  'lastModifiedDateTime',
  'lastModifiedBy',
]
const DEFAULT_SORTING = [{ id: 'sizeInBytes', desc: true }]

export const CippSharePointLibraryContents = ({
  open = false,
  onClose,
  library,
  tenantFilter,
}) => {
  const [folders, setFolders] = useState([])
  const [view, setView] = useState('browse')
  // Set by an archive action: the listing then skips the server cache, so the new status shows.
  const [changed, setChanged] = useState(false)
  const { checkPermissions } = usePermissions()
  const canWriteSite = checkPermissions(['Sharepoint.Site.ReadWrite'])

  const listId = library?.id
  const libraryName = library?.displayName || library?.name || 'Library'
  const libraryBytes = Number(library?.storageUsedInBytes)
  const siteUrl = library?.siteUrl
  const currentFolder = folders[folders.length - 1]
  const queryPrefix = `ListSiteLibraryContents-${tenantFilter}-${listId}`

  const contents = ApiGetCall({
    url: '/api/ListSiteLibraryContents',
    data: {
      tenantFilter,
      ...(library?.siteId
        ? { SiteId: library.siteId }
        : { SiteUrl: library?.siteUrl }),
      ListId: listId,
      ...(currentFolder ? { FolderId: currentFolder.id } : {}),
      ...(view === 'largest' ? { LargestFiles: true } : {}),
      ...(changed ? { InvalidateCIPPCache: true } : {}),
    },
    queryKey: `${queryPrefix}-${currentFolder?.id ?? 'root'}-${view}`,
    waiting: open && !!tenantFilter && !!listId,
  })

  const rows = useMemo(() => {
    const results = contents.data
    if (!Array.isArray(results)) return EMPTY_ROWS
    return results.map((item) => {
      const bytes = Number(item.sizeInBytes)
      return {
        ...item,
        isFolder: item.type === 'Folder',
        libraryName,
        siteUrl,
        percentOfLibrary:
          libraryBytes > 0 && Number.isFinite(bytes)
            ? Math.min(100, Math.round((bytes / libraryBytes) * 1000) / 10)
            : null,
      }
    })
  }, [contents.data, libraryBytes, libraryName, siteUrl])

  const actions = useMemo(
    () => [
      {
        label: 'Open folder',
        icon: <CippIcons.FolderOpen />,
        noConfirm: true,
        hideBulk: true,
        customFunction: (row) =>
          setFolders((previous) => [
            ...previous,
            { id: row.id, name: row.name },
          ]),
        condition: (row) => Boolean(row?.isFolder),
      },
      ...getArchiveFileActions({
        canWrite: canWriteSite,
        relatedQueryKeys: [`${queryPrefix}*`],
        onSuccess: () => setChanged(true),
      }),
      {
        label: 'Open in SharePoint',
        link: '[webUrl]',
        external: true,
        target: '_blank',
        icon: <CippIcons.Launch />,
        multiPost: false,
        condition: (row) => Boolean(row?.webUrl),
      },
    ],
    [canWriteSite, queryPrefix]
  )

  const cellRenderers = useMemo(
    () => ({
      name: (row, base) =>
        row?.isFolder ? (
          <Link
            component="button"
            underline="hover"
            data-no-row-click="true"
            onClick={() =>
              setFolders((previous) => [
                ...previous,
                { id: row.id, name: row.name },
              ])
            }
            sx={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 0.75,
              textAlign: 'left',
            }}
          >
            <CippIcons.Folder fontSize="small" />
            {row.name}
          </Link>
        ) : (
          base
        ),
      itemCount: (row, base) => (row?.isFolder ? base : null),
      archiveStatus: (row, base) => (row?.isFolder ? null : base),
    }),
    []
  )

  const incomplete = view === 'largest' && rows.some((row) => row.isFolder)

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="xl">
      <DialogTitle sx={{ pr: 7 }}>
        <Typography variant="h6" component="span">
          Folders and files — {libraryName}
        </Typography>
        <IconButton
          aria-label="Close"
          onClick={onClose}
          sx={{ position: 'absolute', right: 8, top: 8 }}
        >
          <CippIcons.Close />
        </IconButton>
      </DialogTitle>
      <DialogContent dividers>
        <Stack spacing={1.5}>
          <Stack
            direction="row"
            spacing={1}
            useFlexGap
            sx={{
              alignItems: 'center',
              justifyContent: 'space-between',
              flexWrap: 'wrap',
            }}
          >
            <Breadcrumbs aria-label="Folder path">
              {[{ id: null, name: libraryName }, ...folders].map(
                (folder, index, all) =>
                  index === all.length - 1 ? (
                    <Typography
                      key={folder.id ?? 'root'}
                      sx={{ color: 'text.primary' }}
                    >
                      {folder.name}
                    </Typography>
                  ) : (
                    <Link
                      key={folder.id ?? 'root'}
                      component="button"
                      underline="hover"
                      onClick={() => setFolders(folders.slice(0, index))}
                    >
                      {folder.name}
                    </Link>
                  )
              )}
            </Breadcrumbs>
            <ToggleButtonGroup
              size="small"
              exclusive
              value={view}
              onChange={(_event, next) => next && setView(next)}
              aria-label="What to show"
            >
              <ToggleButton value="browse">Folders and files</ToggleButton>
              <ToggleButton value="largest">Largest files</ToggleButton>
            </ToggleButtonGroup>
          </Stack>
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            {view === 'largest'
              ? 'The largest files in this folder and every folder below it.'
              : 'Sorted by size, so the folders using the most storage are at the top. Select a folder to open it.'}{' '}
            Sizes are for the files as they are now, so they can add up to less
            than the library total, which also counts version history.{' '}
            {canWriteSite ? ARCHIVE_WAIT_NOTE : ''}
          </Typography>
          {incomplete && (
            <Alert severity="info">
              This folder is too large to search in one go. The folders in this
              list have not been searched yet and could hold larger files:
              select one to search inside it.
            </Alert>
          )}
          {contents.isError && (
            <Alert severity="error">
              {getCippError(contents.error)} Use Refresh to try again, or open
              the library in SharePoint.
            </Alert>
          )}
          <CippDataTable
            key={view}
            title={
              view === 'largest'
                ? 'Largest files'
                : (currentFolder?.name ?? libraryName)
            }
            queryKey={`${queryPrefix}-table`}
            data={rows}
            isFetching={contents.isFetching}
            refreshFunction={contents}
            actions={actions}
            cellRenderers={cellRenderers}
            simpleColumns={
              view === 'largest' ? LARGEST_COLUMNS : BROWSE_COLUMNS
            }
            defaultSorting={DEFAULT_SORTING}
            isInDialog={true}
            maxHeightOffset="420px"
          />
        </Stack>
      </DialogContent>
    </Dialog>
  )
}

CippSharePointLibraryContents.propTypes = {
  open: PropTypes.bool,
  onClose: PropTypes.func,
  library: PropTypes.object,
  tenantFilter: PropTypes.string,
}
