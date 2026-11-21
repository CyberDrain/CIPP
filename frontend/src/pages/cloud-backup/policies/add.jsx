import { useForm } from 'react-hook-form'
import CippFormPage from '../../../components/CippFormPages/CippFormPage'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippCloudBackupPolicyForm } from '../../../components/CippFormPages/CippCloudBackupPolicyForm'
import {
  cloudBackupPolicyDefaults,
  formatCloudBackupPolicy,
} from '../../../utils/cloud-backup'

const Page = () => {
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: cloudBackupPolicyDefaults(),
  })

  return (
    <CippFormPage
      formControl={formControl}
      title="Backup Policy"
      backButtonTitle="Backup Policies"
      backUrl="/cloud-backup/policies"
      postUrl="/api/ExecCloudBackupPolicy"
      queryKey={[
        'ListCloudBackupPolicies*',
        'ListCloudBackupOverview*',
        'ListCloudBackupUnusedPermissions*',
      ]}
      customDataformatter={(values) => formatCloudBackupPolicy(values, 'Add')}
    >
      <CippCloudBackupPolicyForm formControl={formControl} />
    </CippFormPage>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout usesTenant={false}>{page}</DashboardLayout>
)

export default Page
