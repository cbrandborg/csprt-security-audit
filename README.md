## Running Cloud Security Posture Review Toolkit for clients as an audit in Google Cloud Platform

## Due to limited testing, please do me the favor and test the script without listed permissions

### If a GCP environment has an Organization node -> Use shell script in in export-organisation-assets
### If a GCP environment does not have an Organization node -> Use shell script in in export-no-org

### Client GCP Prerequisites
1. Select or create any project in client GCP environment - Project ID of this project will from here on be referered to as CUSTOMER_PROJECT_ID - Billing project could be an option
2. Enable Cloud Asset API on CUSTOMER_PROJECT_ID
3. Give your user (or a service agent) the following roles on CUSTOMER_PROJECT_ID:
* roles/serviceusage.serviceUsageConsumer
* roles/serviceusage.serviceUsageAdmin
4. Give your user (or a service agent) the following roles on client organisation - Here on referred to as ORGANIZATION_ID:
* roles/cloudasset.owner

### Devoteam GCP Prerequisites
1. Create a project in GCP - Project ID of this project will from here on be referered to as BQ_PROJECT_ID
2. Give your user (or group) the following roles on BQ_PROJECT_ID:
* roles/bigquery.dataEditor
* roles/bigquery.jobUser
3. Run the following commands: \
`gcloud auth login` \
`gcloud auth configure-docker us-docker.pkg.dev` \
`gcloud auth application-default login`

### Running the export
1. Fill in the following variables with your configuration data:
* CUSTOMER - Name of customer
* CUSTOMER_PROJECT_ID - ProjectID for customer
* ORGANIZATION_ID - Organisation ID for customer
* BQ_PROJECT_ID - ProjectID for your BigQuery datasets
* LOCATION - Location of BigQuery datasets
2. Enter `./create-cai.sh` in terminal

### IF only interested in exports of specific folders instead of an entire organisation
Enter all relevant folderIDs in the bash array variable RELEVANT_FOLDERS with the following format:
Example for folders with folderIDs 1251294390, 2589238929, and 320523090234
`RELEVANT_FOLDERS=(1251294390 2589238929 320523090234)`
