# Conditional Access

This page runs a Conditional Access "what if" evaluation for the user: you describe a sign-in, and CIPP reports which of the tenant's policies would apply to it and why. It is the quickest way to answer questions like whether a new policy would lock someone out, or why an existing one is not catching the sign-ins you expected.

{% hint style="info" %}
The evaluation is a simulation. No sign-in takes place, nothing is written to the tenant, and the user is not affected in any way, so it is safe to run against a live account at any time. The results table reports each policy's state alongside the outcome, so a policy that would apply in report-only mode can be told apart from one that would be enforced.
{% endhint %}

## Test Conditional Access Policy

{% stepper %}
{% step %}
### Select the application to test

The application the simulated sign-in is directed at, chosen from the service principals in the tenant. This is the only required field.
{% endstep %}

{% step %}
### Set any optional conditions

Anything left blank is simply not included in the evaluation, so start with the application alone and add conditions as you narrow down the behavior you are chasing. The options are described below.
{% endstep %}

{% step %}
### Select **Test policies**

The evaluation runs against Entra ID and the results replace whatever is in the table.
{% endstep %}

{% step %}
### Review the results

Work through the table on the right, described in #ca-test-results.
{% endstep %}
{% endstepper %}

## Optional Parameters

| Field                                                | Description                                                                                                                                                                                                |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select the device platform to test                   | The operating system the sign-in comes from: Windows, iOS, Android, MacOS or Linux.                                                                                                                        |
| Select the client application type to test           | How the sign-in reaches Microsoft 365: All, Browser, Mobile apps and desktop clients, Exchange ActiveSync, EAS supported, or Other clients. Legacy authentication policies usually turn on this condition. |
| Select the authentication flow                       | Whether the sign-in uses a flow that policies can target separately: None, Device code flow or Authentication transfer.                                                                                    |
| Test from this IP                                    | The address the sign-in appears to originate from, entered in the form `8.8.8.8`. Use this to check policies built on named locations.                                                                     |
| Test from this country                               | The country the sign-in appears to originate from.                                                                                                                                                         |
| Select the sign-in risk level of the user signing in | The risk Entra ID Protection would assign to the sign-in itself: Low, Medium, High or None.                                                                                                                |
| Select the user risk level of the user signing in    | The risk Entra ID Protection would assign to the account: Low, Medium, High or None.                                                                                                                       |

{% hint style="info" %}
The two risk conditions describe risk the evaluation should assume, not risk the account currently carries. Setting them is how you test a risk-based policy without waiting for Entra ID Protection to flag someone, and the policies themselves still need the licensing that risk-based Conditional Access requires before they will do anything in production.
{% endhint %}

## CA Test Results

Each of the tenant's Conditional Access policies is listed with what the evaluation decided about it.

| Column           | Description                                                                                                               |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Display Name     | The name of the policy.                                                                                                   |
| State            | Whether the policy is enabled, disabled, or enabled in report-only mode.                                                  |
| Policy Applies   | Whether the policy would apply to the sign-in as described.                                                               |
| Analysis Reasons | Why the evaluation reached that conclusion, which for a policy that does not apply names the condition that ruled it out. |

{% hint style="info" %}
Analysis Reasons is the column that earns its keep. A policy showing as not applying will usually name the single condition responsible, so it points straight at the assignment or condition to change rather than leaving you to compare the policy against your test settings by hand.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
