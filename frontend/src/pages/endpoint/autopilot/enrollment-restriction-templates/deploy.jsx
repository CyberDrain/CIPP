import { Layout as DashboardLayout } from '../../../../layouts/index'
import { CippWizardConfirmation } from '../../../../components/CippWizard/CippWizardConfirmation'
import CippWizardPage from '../../../../components/CippWizard/CippWizardPage.jsx'
import { CippTenantStep } from '../../../../components/CippWizard/CippTenantStep.jsx'
import { CippWizardEnrollmentRestrictionTemplates } from '../../../../components/CippWizard/CippWizardEnrollmentRestrictionTemplates'

const Page = () => {
  const steps = [
    {
      title: 'Step 1',
      description: 'Tenant Selection',
      component: CippTenantStep,
      componentProps: {
        allTenants: false,
        type: 'multiple',
      },
    },
    {
      title: 'Step 2',
      description: 'Choose Template',
      component: CippWizardEnrollmentRestrictionTemplates,
    },
    {
      title: 'Step 3',
      description: 'Confirmation',
      component: CippWizardConfirmation,
    },
  ]

  return (
    <CippWizardPage
      steps={steps}
      postUrl="/api/AddEnrollmentRestriction"
      wizardTitle="Enrollment Restriction Template Deployment"
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
