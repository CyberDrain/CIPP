import { useEffect } from 'react'
import { useRouter } from 'next/router'
import { useForm } from 'react-hook-form'
import CippFormPage from '../../../components/CippFormPages/CippFormPage'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippCloudBackupDestinationForm } from '../../../components/CippFormPages/CippCloudBackupDestinationForm'
import { ApiGetCall } from '../../../api/ApiCall'
import {
  CLOUD_BACKUP_SECRET_SENTINEL,
  formatCloudBackupDestination,
} from '../../../utils/cloud-backup'

const Page = () => {
  const router = useRouter()
  const { id } = router.query
  const formControl = useForm({ mode: 'onChange' })

  const destination = ApiGetCall({
    url: '/api/ListCloudBackupDestinations',
    data: { Id: id },
    queryKey: `ListCloudBackupDestinations-edit-${id}`,
    waiting: !!id,
  })

  useEffect(() => {
    const row = Array.isArray(destination.data)
      ? destination.data[0]
      : undefined
    if (!row) return
    const secret =
      row.SecretSet === CLOUD_BACKUP_SECRET_SENTINEL
        ? CLOUD_BACKUP_SECRET_SENTINEL
        : ''
    formControl.reset({
      Id: row.Id,
      Name: row.Name,
      Provider: row.Provider,
      AuthMode: row.AuthMode ?? '',
      StorageAccount: row.StorageAccount ?? '',
      Container: row.Container ?? '',
      SubscriptionId: row.SubscriptionId ?? '',
      ResourceGroup: row.ResourceGroup ?? '',
      AzureTenantId: row.AzureTenantId ?? '',
      ClientId: row.ClientId ?? '',
      ClientSecret:
        row.Provider === 'AzureBlob' && row.AuthMode !== 'CippApp'
          ? secret
          : '',
      Endpoint: row.Endpoint ?? '',
      Region: row.Region ?? '',
      Bucket: row.Bucket ?? '',
      AccessKeyId: row.AccessKeyId ?? '',
      SecretAccessKey: row.Provider === 'S3' ? secret : '',
      ForcePathStyle: row.ForcePathStyle === true,
    })
  }, [destination.data, formControl])

  return (
    <CippFormPage
      formControl={formControl}
      title="Backup Destination"
      formPageType="Edit"
      backButtonTitle="Destinations"
      backUrl="/cloud-backup/destinations"
      postUrl="/api/ExecCloudBackupDestination"
      queryKey={['ListCloudBackupDestinations*', 'ListCloudBackupOverview*']}
      isFetching={destination.isFetching}
      customDataformatter={(values) =>
        formatCloudBackupDestination(values, 'Edit')
      }
    >
      <CippCloudBackupDestinationForm formControl={formControl} isEdit />
    </CippFormPage>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout usesTenant={false}>{page}</DashboardLayout>
)

export default Page
