import { useState } from 'react'
import { useForm } from 'react-hook-form'
import {
  Alert,
  FormControl,
  FormControlLabel,
  FormLabel,
  Radio,
  RadioGroup,
  Skeleton,
  Stack,
  Typography,
} from '@mui/material'
import CippFormPage from '../../../components/CippFormPages/CippFormPage'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippCloudBackupDestinationForm } from '../../../components/CippFormPages/CippCloudBackupDestinationForm'
import {
  CippCloudBackupProvisionForm,
  CippCloudBackupProvisionProgress,
} from '../../../components/CippFormPages/CippCloudBackupProvisionForm'
import { ApiGetCall } from '../../../api/ApiCall'
import {
  CLOUD_BACKUP_PROVISION_DEFAULTS,
  cloudBackupManualPrefill,
  formatCloudBackupDestination,
  formatCloudBackupProvision,
} from '../../../utils/cloud-backup'

const Page = () => {
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: { Provider: 'AzureBlob', ForcePathStyle: false },
  })
  const provisionForm = useForm({
    mode: 'onChange',
    defaultValues: CLOUD_BACKUP_PROVISION_DEFAULTS,
  })
  const [chosenMode, setChosenMode] = useState(null)
  const [jobId, setJobId] = useState(null)

  const options = ApiGetCall({
    url: '/api/ListCloudBackupProvisioningOptions',
    queryKey: 'ListCloudBackupProvisioningOptions',
  })
  const available = options.data?.Available === true
  const loading = !chosenMode && options.isLoading
  const mode = chosenMode ?? (available ? 'create' : 'manual')

  const switchToManual = (result) => {
    formControl.reset(
      cloudBackupManualPrefill(result, provisionForm.getValues('Name'))
    )
    setJobId(null)
    setChosenMode('manual')
  }

  const choice = (
    <Stack spacing={2} sx={{ mb: 3 }}>
      <FormControl>
        <FormLabel id="cloud-backup-setup-mode">
          How do you want to set up this destination?
        </FormLabel>
        <RadioGroup
          aria-labelledby="cloud-backup-setup-mode"
          value={mode}
          onChange={(event) => setChosenMode(event.target.value)}
        >
          <FormControlLabel
            value="create"
            disabled={!available}
            control={<Radio />}
            label="Create a storage account for me (recommended)"
          />
          <FormControlLabel
            value="manual"
            control={<Radio />}
            label="Use an existing Azure storage account or S3 bucket"
          />
        </RadioGroup>
      </FormControl>
      {options.isSuccess && !available && (
        <Alert severity="info">
          <Typography variant="body2">
            {options.data?.Reason
              ? `CIPP can't create a storage account here: ${options.data.Reason}`
              : "CIPP can't create a storage account here."}
          </Typography>
          <Typography variant="body2" sx={{ mt: 1 }}>
            To use this option, give CIPP's managed identity the{' '}
            <strong>Contributor</strong> and{' '}
            <strong>User Access Administrator</strong> roles on an Azure
            subscription, then reload this page. Until then, set the destination
            up manually.
          </Typography>
        </Alert>
      )}
    </Stack>
  )

  if (mode === 'create') {
    return (
      <CippFormPage
        key="create"
        formControl={provisionForm}
        title="Backup Destination"
        backButtonTitle="Destinations"
        backUrl="/cloud-backup/destinations"
        postUrl="/api/ExecCloudBackupProvision"
        queryKey={['ListCloudBackupJobs*']}
        hideSubmit={Boolean(jobId)}
        customDataformatter={formatCloudBackupProvision}
        onSubmitResult={(result) => {
          if (result?.JobId) setJobId(result.JobId)
        }}
      >
        {jobId ? (
          <CippCloudBackupProvisionProgress
            jobId={jobId}
            onManual={switchToManual}
            onRetry={() => setJobId(null)}
          />
        ) : (
          <>
            {choice}
            <CippCloudBackupProvisionForm
              formControl={provisionForm}
              options={options.data}
            />
          </>
        )}
      </CippFormPage>
    )
  }

  return (
    <CippFormPage
      key="manual"
      hideSubmit={loading}
      formControl={formControl}
      title="Backup Destination"
      backButtonTitle="Destinations"
      backUrl="/cloud-backup/destinations"
      postUrl="/api/ExecCloudBackupDestination"
      queryKey={['ListCloudBackupDestinations*', 'ListCloudBackupOverview*']}
      customDataformatter={(values) =>
        formatCloudBackupDestination(values, 'Add')
      }
    >
      {loading ? (
        <Skeleton variant="rounded" height={240} />
      ) : (
        <>
          {choice}
          <CippCloudBackupDestinationForm formControl={formControl} />
        </>
      )}
    </CippFormPage>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout usesTenant={false}>{page}</DashboardLayout>
)

export default Page
