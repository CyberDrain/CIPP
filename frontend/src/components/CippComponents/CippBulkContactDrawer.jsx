import { useEffect, useMemo, useState } from "react";
import { CippIcons } from "../../utils/icon-registry";
import {
  Alert,
  Button,
  Link,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
} from "@mui/material";
import { Grid } from "@mui/system";
import { useForm, useWatch } from "react-hook-form";
import { CippOffCanvas } from "./CippOffCanvas";
import CippFormComponent from "./CippFormComponent";
import { CippDataTable } from "../CippTable/CippDataTable";
import { CippApiResults } from "./CippApiResults";
import { useSettings } from "../../hooks/use-settings";
import { ApiPostCall } from "../../api/ApiCall";
import { getCippTranslation } from "../../utils/get-cipp-translation";
import { getCippValidator } from "../../utils/get-cipp-validator";

// CSV cells arrive as strings; send a real boolean so the backend never has to interpret "false".
const truthy = (value) => ["true", "1", "yes"].includes(String(value ?? "").trim().toLowerCase());

const isValidRow = (row) =>
  Boolean(String(row?.displayName ?? "").trim()) && getCippValidator(row?.email, "email") === true;

export const CippBulkContactDrawer = ({
  buttonText = "Bulk Add Contacts",
  requiredPermissions = [],
  PermissionButton = Button,
}) => {
  const [drawerVisible, setDrawerVisible] = useState(false);
  const [addRowDialogOpen, setAddRowDialogOpen] = useState(false);
  const tenantDomain = useSettings().currentTenant;

  const fields = [
    "displayName",
    "firstName",
    "lastName",
    "email",
    "hidefromGAL",
    "jobTitle",
    "companyName",
    "mobilePhone",
    "businessPhone",
    "streetAddress",
    "city",
    "state",
    "postalCode",
    "country",
    "website",
    "mailTip",
  ];

  // Two sample rows in the same column order as `fields`, so the download shows what each column
  // expects, including true/false for hidefromGAL. Values must stay free of commas and quotes.
  const exampleRows = [
    [
      "Jane Doe",
      "Jane",
      "Doe",
      "jane.doe@example.com",
      "false",
      "Account Manager",
      "Contoso Ltd",
      "+1 555 0100",
      "+1 555 0101",
      "1 Main Street",
      "Seattle",
      "WA",
      "98101",
      "United States",
      "https://www.contoso.com",
      "Replies within one business day",
    ],
    [
      "Supplier Helpdesk",
      "",
      "",
      "helpdesk@example.com",
      "true",
      "",
      "Fabrikam",
      "",
      "+1 555 0200",
      "",
      "",
      "",
      "",
      "",
      "",
      "Hidden from the address book",
    ],
  ];
  const exampleCsv = [fields, ...exampleRows].map((row) => row.join(",")).join("\n") + "\n";

  const fieldValidators = {
    displayName: { required: "Display Name is required" },
    email: {
      required: "Email is required",
      validate: (value) => getCippValidator(value, "email"),
    },
  };

  const formControl = useForm({
    mode: "onBlur",
    defaultValues: {
      bulkContacts: [],
    },
  });

  const bulkContactsData = useWatch({ control: formControl.control, name: "bulkContacts" });

  // CSV rows skip the manual dialog's validators, so the same rule is applied to the queue as a whole.
  const invalidRowCount = useMemo(
    () => (bulkContactsData || []).filter((row) => !isValidRow(row)).length,
    [bulkContactsData],
  );

  const addContacts = ApiPostCall({
    relatedQueryKeys: [`Contacts - ${tenantDomain}`],
  });

  // Every queued row has been posted once a batch succeeds; keep them and "Create More Contacts"
  // would re-post them all as duplicates.
  useEffect(() => {
    if (addContacts.isSuccess) {
      formControl.setValue("bulkContacts", [], { shouldValidate: true });
    }
  }, [addContacts.isSuccess, formControl]);

  formControl.register("bulkContacts", {
    validate: (value) => Array.isArray(value) && value.length > 0,
  });

  const handleRemoveItem = (row) => {
    if (row === undefined) return false;
    const currentData = formControl.getValues("bulkContacts") || [];
    const rowKey = JSON.stringify(row);
    const index = currentData.findIndex((item) => JSON.stringify(item) === rowKey);
    if (index === -1) return false;
    const newData = [...currentData];
    newData.splice(index, 1);
    formControl.setValue("bulkContacts", newData, { shouldValidate: true });
  };

  const handleAddItem = async () => {
    const valid = await formControl.trigger(["addrow.displayName", "addrow.email"]);
    if (!valid) return;
    const newRowData = formControl.getValues("addrow");
    if (newRowData === undefined) return false;
    const currentData = formControl.getValues("bulkContacts") || [];
    formControl.setValue("bulkContacts", [...currentData, newRowData], { shouldValidate: true });
    setAddRowDialogOpen(false);
    formControl.reset({
      ...formControl.getValues(),
      addrow: {},
    });
  };

  const handleSubmit = () => {
    // Same payload as CippAddContactDrawer, one request per row.
    const payload = (formControl.getValues("bulkContacts") || []).map((row) => ({
      tenantID: tenantDomain,
      DisplayName: row.displayName,
      FirstName: row.firstName,
      LastName: row.lastName,
      email: row.email,
      hidefromGAL: truthy(row.hidefromGAL),
      Title: row.jobTitle,
      Company: row.companyName,
      mobilePhone: row.mobilePhone,
      phone: row.businessPhone,
      StreetAddress: row.streetAddress,
      City: row.city,
      State: row.state,
      PostalCode: row.postalCode,
      CountryOrRegion: row.country,
      website: row.website,
      mailTip: row.mailTip,
    }));

    addContacts.mutate({
      url: "/api/AddContact",
      bulkRequest: true,
      data: payload,
    });
  };

  const handleCloseDrawer = () => {
    setDrawerVisible(false);
    formControl.reset({ bulkContacts: [] });
    addContacts.reset();
  };

  const actions = [
    {
      icon: <CippIcons.Delete />,
      label: "Delete Row",
      confirmText: "Are you sure you want to delete this row?",
      customFunction: handleRemoveItem,
      noConfirm: true,
    },
  ];

  return (
    <>
      <PermissionButton
        {...(PermissionButton !== Button ? { requiredPermissions } : {})}
        onClick={() => setDrawerVisible(true)}
        startIcon={<CippIcons.GroupAdd />}
      >
        {buttonText}
      </PermissionButton>
      <CippOffCanvas
        title="Bulk Add Contacts"
        visible={drawerVisible}
        onClose={handleCloseDrawer}
        size="lg"
        footer={
          <div style={{ display: "flex", gap: "8px", justifyContent: "flex-start" }}>
            <Button
              variant="contained"
              color="primary"
              onClick={handleSubmit}
              disabled={
                addContacts.isPending ||
                !bulkContactsData ||
                bulkContactsData.length === 0 ||
                invalidRowCount > 0
              }
            >
              {addContacts.isPending
                ? "Creating Contacts..."
                : addContacts.isSuccess
                  ? "Create More Contacts"
                  : "Create Contacts"}
            </Button>
            <Button variant="outlined" onClick={handleCloseDrawer}>
              Close
            </Button>
          </div>
        }
      >
        <Grid container spacing={2}>
          <Grid size={{ xs: 12 }}>
            <Link
              href={`data:text/csv;charset=utf-8,%EF%BB%BF${encodeURIComponent(exampleCsv)}`}
              download="BulkContacts.csv"
            >
              Download Example CSV
            </Link>
          </Grid>

          <Grid size={{ xs: 12 }}>
            <CippFormComponent
              type="CSVReader"
              name="bulkContacts"
              formControl={formControl}
              onRemove={() => formControl.setValue("bulkContacts", [], { shouldValidate: true })}
            />
          </Grid>

          <Grid size={{ xs: 12 }}>
            <Button size="small" onClick={() => setAddRowDialogOpen(true)}>
              Add Contact Manually
            </Button>
          </Grid>

          {invalidRowCount > 0 && (
            <Grid size={{ xs: 12 }}>
              <Alert severity="warning">
                {invalidRowCount} row{invalidRowCount === 1 ? " is" : "s are"} missing a display
                name or a valid email address. Fix the CSV or delete the row before creating
                contacts.
              </Alert>
            </Grid>
          )}

          <Grid size={{ xs: 12 }}>
            <CippDataTable
              actions={actions}
              title="Contact Preview"
              data={bulkContactsData || []}
              simple={false}
              simpleColumns={fields}
              noCard={true}
            />
          </Grid>

          <CippApiResults apiObject={addContacts} />
        </Grid>

        <Dialog
          open={addRowDialogOpen}
          onClose={() => setAddRowDialogOpen(false)}
          maxWidth="md"
          fullWidth
        >
          <DialogTitle>Add a new contact</DialogTitle>
          <DialogContent>
            <Grid container spacing={2} sx={{ py: 1 }}>
              {fields.map((field) => (
                <Grid size={{ md: 6, xs: 12 }} key={field}>
                  <CippFormComponent
                    name={`addrow.${field}`}
                    label={getCippTranslation(field)}
                    type={field === "hidefromGAL" ? "switch" : "textField"}
                    formControl={formControl}
                    validators={fieldValidators[field]}
                  />
                </Grid>
              ))}
            </Grid>
          </DialogContent>
          <DialogActions>
            <Button variant="outlined" onClick={() => setAddRowDialogOpen(false)}>
              Cancel
            </Button>
            <Button variant="contained" onClick={handleAddItem}>
              Add
            </Button>
          </DialogActions>
        </Dialog>
      </CippOffCanvas>
    </>
  );
};
