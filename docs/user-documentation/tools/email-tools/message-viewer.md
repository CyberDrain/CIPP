# Message Viewer

The Message Viewer is a tool that allows users to view and analyse EML (Electronic Mail) files. EML files are commonly used to store email messages and can be opened and viewed with various email clients. There are two ways to review files:

## File Upload

{% stepper %}
{% step %}
### Select a file

Drag an EML file into the Load Message section or click to select from your file explorer.
{% endstep %}

{% step %}
### Review message

* **Message Preview**: The tool provides a preview of the selected EML file in HTML or Text format, displaying the sender, recipient, subject, and date of the email.
* **Attachment Extraction**: If the email contains attachments, users can preview or download them to their local system.
{% endstep %}

{% step %}
### Review raw file data

Click on the View Headers or View Source to see the raw message data. These buttons will open popout modals for you to be able to review the raw data selected.
{% endstep %}
{% endstepper %}

## Paste Headers/Source

{% stepper %}
{% step %}
### Toggle to "Paste headers / source"

Click the toggle to change the page's mode
{% endstep %}

{% step %}
### Paste headers

Paste the headers or source from your email client
{% endstep %}

{% step %}
### Click Analyze

This will run the analysis on the email and you can review the message and raw file data as above.
{% endstep %}
{% endstepper %}



***

{% include "../../../../.gitbook/includes/feature-request.md" %}
