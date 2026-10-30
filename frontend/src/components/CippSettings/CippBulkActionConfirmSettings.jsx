import { Button, Typography, TextField, Box, FormControlLabel, Switch } from "@mui/material";
import CippButtonCard from "../CippCards/CippButtonCard";
import { ApiGetCall, ApiPostCall } from "../../api/ApiCall";
import { CippApiResults } from "../CippComponents/CippApiResults";
import { useState, useEffect } from "react";

const CippBulkActionConfirmSettings = () => {
  const confirmSetting = ApiGetCall({
    url: "/api/ExecBulkActionConfirmConfig?List=true",
    queryKey: "BulkActionConfirmConfig",
  });

  const confirmChange = ApiPostCall({
    datafromUrl: true,
    relatedQueryKeys: "BulkActionConfirmConfig",
  });

  const [enabled, setEnabled] = useState(false);
  const [threshold, setThreshold] = useState(10);
  const [countdownSeconds, setCountdownSeconds] = useState(5);
  const [error, setError] = useState("");

  useEffect(() => {
    const results = confirmSetting?.data?.Results;
    if (results) {
      setEnabled(Boolean(results.Enabled));
      setThreshold(results.Threshold ?? 10);
      setCountdownSeconds(results.CountdownSeconds ?? 5);
    }
  }, [confirmSetting.data]);

  const handleSave = () => {
    const parsedThreshold = parseInt(threshold);
    const parsedSeconds = parseInt(countdownSeconds);

    if (isNaN(parsedThreshold) || parsedThreshold < 1) {
      setError("Item threshold must be a whole number of at least 1");
      return;
    }

    if (isNaN(parsedSeconds) || parsedSeconds < 1 || parsedSeconds > 60) {
      setError("Countdown seconds must be a whole number between 1 and 60");
      return;
    }

    setError("");
    confirmChange.mutate({
      url: "/api/ExecBulkActionConfirmConfig",
      data: {
        Enabled: enabled,
        Threshold: parsedThreshold,
        CountdownSeconds: parsedSeconds,
      },
      queryKey: "BulkActionConfirmConfigPost",
    });
  };

  return (
    <CippButtonCard
      title="Bulk Action Confirmation"
      cardSx={{ display: "flex", flexDirection: "column", height: "100%" }}
      CardButton={
        <Button
          variant="contained"
          color="primary"
          size="small"
          disabled={confirmChange.isPending || confirmSetting.isLoading || !!error}
          onClick={handleSave}
        >
          Save
        </Button>
      }
    >
      <Typography variant="body2" sx={{ mb: 2 }}>
        Require a countdown before the Confirm button is clickable on bulk actions affecting more
        than the configured number of selected rows. Disabled by default.
      </Typography>
      <FormControlLabel
        control={
          <Switch
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
            disabled={confirmChange.isPending || confirmSetting.isLoading}
          />
        }
        label="Enable bulk action confirmation countdown"
      />
      <Box sx={{ display: "flex", gap: 2, mt: 2 }}>
        <TextField
          size="small"
          type="number"
          label="Item threshold"
          value={threshold}
          onChange={(e) => setThreshold(e.target.value)}
          disabled={!enabled || confirmChange.isPending || confirmSetting.isLoading}
          error={!!error}
          slotProps={{ htmlInput: { min: 1 } }}
        />
        <TextField
          size="small"
          type="number"
          label="Countdown seconds"
          value={countdownSeconds}
          onChange={(e) => setCountdownSeconds(e.target.value)}
          disabled={!enabled || confirmChange.isPending || confirmSetting.isLoading}
          error={!!error}
          helperText={error}
          slotProps={{ htmlInput: { min: 1, max: 60 } }}
        />
      </Box>
      <CippApiResults apiObject={confirmChange} />
    </CippButtonCard>
  );
};

export default CippBulkActionConfirmSettings;
