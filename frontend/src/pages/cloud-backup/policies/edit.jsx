import { useEffect } from 'react'
import { useRouter } from 'next/router'
import { useForm } from 'react-hook-form'
import CippFormPage from '../../../components/CippFormPages/CippFormPage'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippCloudBackupPolicyForm } from '../../../components/CippFormPages/CippCloudBackupPolicyForm'
import { ApiGetCall } from '../../../api/ApiCall'
import {
  formatCloudBackupPolicy,
  toCloudBackupPolicyForm,
} from '../../../utils/cloud-backup'

const Page = () => {
  const router = useRouter()
  const { id } = router.query
  const formControl = useForm({ mode: 'onChange' })

  const policy = ApiGetCall({
    url: '/api/ListCloudBackupPolicies',
    data: { Id: id },
    queryKey: `ListCloudBackupPolicies-edit-${id}`,
    waiting: !!id,
  })

  useEffect(() => {
    const row = Array.isArray(policy.data) ? policy.data[0] : undefined
    if (!row) return
    formControl.reset(toCloudBackupPolicyForm(row))
  }, [policy.data, formControl])

  return (
    <CippFormPage
      formControl={formControl}
      title="Backup Policy"
      formPageType="Edit"
      backButtonTitle="Backup Policies"
      backUrl="/cloud-backup/policies"
      postUrl="/api/ExecCloudBackupPolicy"
      queryKey={[
        'ListCloudBackupPolicies*',
        'ListCloudBackupOverview*',
        'ListCloudBackupUnusedPermissions*',
      ]}
      isFetching={policy.isFetching}
      customDataformatter={(values) => formatCloudBackupPolicy(values, 'Edit')}
    >
      <CippCloudBackupPolicyForm formControl={formControl} />
    </CippFormPage>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout usesTenant={false}>{page}</DashboardLayout>
)

export default Page
