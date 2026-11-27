# Cyber Insurance Report

This report answers the questions on a cyber insurance application for one client tenant, using settings read from the tenant. Export it as a PDF and attach it to the application so the underwriter sees evidence instead of self-attested checkboxes.

The report requires a single tenant. Select the client in the tenant selector in the menu bar.

## What the report covers

The report lists 25 application questions in a fixed order. Each question has one of three sources.

| Source      | Meaning                                                                                                              |
| ----------- | -------------------------------------------------------------------------------------------------------------------- |
| Verified    | CIPP reads the answer from the tenant.                                                                               |
| Partial     | CIPP reads the Microsoft 365 side only. A non-Microsoft product could still satisfy the question.                    |
| Attestation | The answer is not visible in Microsoft 365, such as firewalls, backups and staff training. The MSP answers these.    |

{% hint style="warning" %}
The report reads Microsoft 365, Entra ID, Intune and Defender only. It does not replace the signed application, and the applicant remains responsible for the answers on it. If an answer here differs from the application, raise it with the broker before submitting.
{% endhint %}

## Syncing data

**Sync data** collects the tenant's data and answers the questions again. A full refresh can take up to two hours. Choose the tests-only option to re-answer the questions from data CIPP already holds.

**Last data refresh** shows the age of the oldest data the report uses. The same date is printed on every page of the PDF.

## Exporting the report

**Export Report** opens a preview of the PDF and lets you download it. The PDF contains a summary, the 25 questions in order, the detail behind each verified answer, the questions the MSP attests to, and a scope and limitations statement.

## Entering an attestation

Use **Enter attestation** on a question to record the MSP's answer. Name the tool or vendor, what it covers, and any date or value the application asks for. CIPP stores who entered it and when, and prints the attestation in the PDF under that question. Save an empty attestation to remove it.

**Add attestation question** adds a question of your own for this tenant, with its attestation. Added questions are listed after the application questions and printed in the PDF. Saving an empty attestation on an added question removes the question.

## Table Details

| Column   | Description                                             |
| -------- | ------------------------------------------------------- |
| Number   | The question's position on the application.             |
| Question | The application question.                               |
| Coverage | Where the answer comes from: Verified, Partial or Attestation. |
| Answer   | The answer for this tenant. See below.                  |
| Attested By | Who entered the attestation for this question, if one exists. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Enter attestation</td><td>Records or replaces the MSP's attestation for the question.</td><td>false</td></tr><tr><td>Set to Yes</td><td>Sets the answer to Yes for a question the MSP attests to. The attestation text is kept.</td><td>false</td></tr><tr><td>Set to No</td><td>Sets the answer to No for a question the MSP attests to. The attestation text is kept.</td><td>false</td></tr></tbody></table>

Select a row to see the detail behind the answer, including the figures it is based on.

### Answer

| Answer          | Meaning                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------- |
| Yes             | The tenant meets the question.                                                           |
| No              | The tenant does not meet the question.                                                   |
| Partial         | The tenant meets part of the question, or the result needs a decision. Read the detail.  |
| Reported        | The question asks for a value, not a yes or no. The value is in the detail.              |
| MSP attestation | The MSP answers this question. Any supporting evidence from the tenant is in the detail. |
| Not licensed    | The tenant does not hold the licence needed to read this. It is not a failure.           |
| No data         | The data has not been collected yet. Use **Sync data**.                                  |

{% include "../../../../.gitbook/includes/feature-request.md" %}
