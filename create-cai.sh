#!/bin/bash

set -euxo pipefail

# Client specific variables
CUSTOMER=
CUSTOMER_PROJECT_ID=
CUSTOMER_ORGANIZATION_ID=
RELEVANT_FOLDERS=()

# Project and BQ Environment Variables

BQ_PROJECT_ID=
LOCATION=eu
BQDATASET_CAI=caiDs${CUSTOMER^}
BQDATASET_FINDING=findingDs${CUSTOMER^}
BQ_PROJECT_NUM=$(gcloud projects describe ${BQ_PROJECT_ID} --format "value(projectNumber)")
CUSTOMER_PROJECT_NUM=$(gcloud projects describe ${CUSTOMER_PROJECT_ID} --format "value(projectNumber)")
CURRENT_USER=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

# Enable BigQuery API
echo "Enabling BigQuery API in ${BQ_PROJECT_ID}..."
gcloud services enable bigquery.googleapis.com --project=${BQ_PROJECT_ID}

# Check whether client is already created as datasets
echo "Checking whether customer datasets exist..."

CUSTOMER_EXISTS=$(gcloud alpha bq datasets list --project=${BQ_PROJECT_ID} --format="value(datasetReference[datasetId])" | grep ${BQDATASET_CAI})
if [ -z "$CUSTOMER_EXISTS" ]; then    
    # Create new datasets
    echo "Creating CAI and Findings datsets in BigQuery..."
    bq mk --location ${LOCATION} --project_id ${BQ_PROJECT_ID} -d ${BQDATASET_CAI}
    bq mk --location ${LOCATION} --project_id ${BQ_PROJECT_ID} -d ${BQDATASET_FINDING}
else
    echo "Datasets for customer exist"
fi

# Enabling cloud asset export service in client project
echo "Enabling Cloud Asset Export API in ${CUSTOMER_PROJECT_ID}..."
gcloud services enable cloudasset.googleapis.com --project=${CUSTOMER_PROJECT_ID}

# Creating service agent for cloud asset export in client project
echo "Creating service agent for Cloud Asset Export in ${BQ_PROJECT_ID}"
gcloud beta services identity create --service=cloudasset.googleapis.com \
    --project=${CUSTOMER_PROJECT_ID} 

gcloud organizations add-iam-policy-binding ${CUSTOMER_ORGANIZATION_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/cloudasset.viewer

gcloud organizations add-iam-policy-binding ${CUSTOMER_ORGANIZATION_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/resourcemanager.folderViewer

gcloud organizations add-iam-policy-binding ${CUSTOMER_ORGANIZATION_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/resourcemanager.organizationViewer

gcloud projects add-iam-policy-binding ${CUSTOMER_PROJECT_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/serviceusage.serviceUsageConsumer
# Setting permissions for cloud asset service agent in Devoteam BigQuery Project
echo "Setting BigQuery Editor and BigQuery User for serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com in ${BQ_PROJECT_ID}"
gcloud projects add-iam-policy-binding ${BQ_PROJECT_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/bigquery.dataEditor
gcloud projects add-iam-policy-binding ${BQ_PROJECT_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/bigquery.user

# Exporting resources
echo "Exporting Cloud Asset content: RESOURCES..."
gcloud asset export --billing-project $BQ_PROJECT_ID \
    --content-type=resource \
    --account ${CURRENT_USER} \
    --organization ${CUSTOMER_ORGANIZATION_ID} \
    --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/resource \
    --output-bigquery-force \
    --per-asset-type \

# Exporting IAM Policies
echo "Exporting Cloud Asset content: IAM Policies..."
gcloud asset export --billing-project $BQ_PROJECT_ID \
    --content-type=iam-policy \
    --account=${CURRENT_USER}m \
    --organization ${CUSTOMER_ORGANIZATION_ID} \
    --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/iam_policy \
    --output-bigquery-force

# Exporting Org Policies
echo "Exporting Cloud Asset content: Org Policies..."
gcloud asset export --billing-project $BQ_PROJECT_ID \
    --content-type=org-policy \
    --organization ${CUSTOMER_ORGANIZATION_ID} \
    --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/org_policy \
    --output-bigquery-force

# Exporting Access Policies
gcloud asset export --billing-project $BQ_PROJECT_ID \
    --content-type access-policy \
    --organization ${CUSTOMER_ORGANIZATION_ID} \
    --bigquery-table projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/access_policy \
    --output-bigquery-force

# Waiting 90 seconds for Exports to finish
sleep 90

# If the whole organisation is to be scanned and exported to BigQuery
if [ -z $RELEVANT_FOLDERS ]; then

    docker run -it --rm -e BQ_PROJECT=${BQ_PROJECT_ID} \
    -e LOCATION=${LOCATION} \
    -e ORG_DOMAIN=${CUSTOMER_ORGANIZATION_ID} \
    -e BQDATASET_FINDING=${BQDATASET_FINDING} \
    -e BQDATASET_INVENTORY=${BQDATASET_CAI} \
    -v "$HOME/.config/gcloud":/root/.config/gcloud \
    us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-scanner:latest
fi

INCLUDE_LIST=()
ITER=0

# If specific folders are required instead of the entire organisation
if [ -n $RELEVANT_FOLDERS ]; then

    for FOLDER in ${RELEVANT_FOLDERS[@]}; do
        if [[ $ITER == $(( ${#RELEVANT_FOLDERS[@]} - 1 )) ]];then
            echo $ITER
            INCLUDE_LIST+=("folders/$FOLDER")

        else
            echo $ITER
            INCLUDE_LIST+=("folders/$FOLDER,")
        fi
        ((ITER++))
    done

    docker run -it --rm -e BQ_PROJECT=${BQ_PROJECT_ID} \
    -e LOCATION=${LOCATION} \
    -e ORG_DOMAIN=${CUSTOMER_ORGANIZATION_ID} \
    -e BQDATASET_FINDING=${BQDATASET_FINDING} \
    -e BQDATASET_INVENTORY=${BQDATASET_CAI} \
    -e INCLUDE_LIST=${INCLUDE_LIST} \
    -v "$HOME/.config/gcloud":/root/.config/gcloud \
    us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-scanner:latest
fi

echo ${INCLUDE_LIST[@]}