!/bin/bash

set -euxo pipefail

Client specific variables

export RELEVANT_PROJECTS=()

export RELEVANT_PROJECTS=()
BQ_PROJECT_ID=
LOCATION=eu
CUSTOMER_ORGANIZATION_ID=
Project and BQ Environment Variables


for CUSTOMER_PROJECT_ID in ${RELEVANT_PROJECTS[@]}; do

    CUSTOMER=$(echo ${CUSTOMER_PROJECT_ID^} | tr -d '-')

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

    echo "Adding Service Usage Admin to ${CURRENT_USER}"
    gcloud projects add-iam-policy-binding ${CUSTOMER_PROJECT_ID} --member=user:${CURRENT_USER} --role=roles/serviceusage.serviceUsageAdmin --format "value(projectNumber)"

    echo "Adding Cloud Asset Viewer to ${CURRENT_USER}"
    gcloud projects add-iam-policy-binding ${CUSTOMER_PROJECT_ID} --member=user:${CURRENT_USER} --role=roles/cloudasset.viewer --format "value(projectNumber)"

    # Enabling cloud asset export service in client project
    echo "Enabling Cloud Asset Export API in ${CUSTOMER_PROJECT_ID}..."
    gcloud services enable cloudasset.googleapis.com --project=${CUSTOMER_PROJECT_ID}

    # Creating service agent for cloud asset export in client project
    echo "Creating service agent for Cloud Asset Export in ${BQ_PROJECT_ID}"
    gcloud beta services identity create --service=cloudasset.googleapis.com \
        --project=${CUSTOMER_PROJECT_ID} 

    echo "Adding Cloud Asset Viewer to service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com"
    gcloud projects add-iam-policy-binding ${CUSTOMER_PROJECT_ID} --member \
        serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
        --role roles/cloudasset.viewer --format "value(projectNumber)"

    echo "Adding Storage Admin to service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com"
    gcloud projects add-iam-policy-binding ${BQ_PROJECT_ID} --member \
        serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
        --role roles/storage.admin --format "value(projectNumber)"

    echo "Adding Service Usage Consumer to service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com"
    gcloud projects add-iam-policy-binding ${CUSTOMER_PROJECT_ID} --member \
    serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
    --role roles/serviceusage.serviceUsageConsumer --format "value(projectNumber)"

    # Setting permissions for cloud asset service agent in Devoteam BigQuery Project
    echo "Setting BigQuery Editor and BigQuery User for serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com in ${BQ_PROJECT_ID}"
    gcloud projects add-iam-policy-binding ${BQ_PROJECT_ID} --member \
        serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
        --role roles/bigquery.dataEditor --format "value(projectNumber)"
    gcloud projects add-iam-policy-binding ${BQ_PROJECT_ID} --member \
        serviceAccount:service-${CUSTOMER_PROJECT_NUM}@gcp-sa-cloudasset.iam.gserviceaccount.com \
        --role roles/bigquery.user --format "value(projectNumber)"

    # Exporting resources
    echo "Exporting Cloud Asset content: RESOURCES..."
    gcloud asset export --billing-project $BQ_PROJECT_ID \
        --content-type=resource \
        --project ${CUSTOMER_PROJECT_ID} \
        --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/resource \
        --output-bigquery-force \
        --per-asset-type &

    # Exporting IAM Policies
    echo "Exporting Cloud Asset content: IAM Policies..."
    gcloud asset export --billing-project $BQ_PROJECT_ID \
        --content-type=iam-policy \
        --project ${CUSTOMER_PROJECT_ID}  \
        --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/iam_policy \
        --output-bigquery-force &

    # Exporting Org Policies
    echo "Exporting Cloud Asset content: Org Policies..."
    gcloud asset export --billing-project $BQ_PROJECT_ID \
        --content-type=org-policy \
        --project ${CUSTOMER_PROJECT_ID} \
        --bigquery-table=projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/org_policy \
        --output-bigquery-force &

    # Exporting Access Policies
    gcloud asset export --billing-project $BQ_PROJECT_ID \
        --content-type access-policy \
        --project ${CUSTOMER_PROJECT_ID} \
        --bigquery-table projects/$BQ_PROJECT_ID/datasets/$BQDATASET_CAI/tables/access_policy \
        --output-bigquery-force &

done

sleep 120

for CUSTOMER_PROJECT_ID in ${RELEVANT_PROJECTS[@]}; do

    echo $CUSTOMER

    BQDATASET_CAI=caiDs${CUSTOMER^}
    BQDATASET_FINDING=findingDs${CUSTOMER^}
    BQ_PROJECT_NUM=$(gcloud projects describe ${BQ_PROJECT_ID} --format "value(projectNumber)")
    CUSTOMER_PROJECT_NUM=$(gcloud projects describe ${CUSTOMER_PROJECT_ID} --format "value(projectNumber)")
    CURRENT_USER=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

    INCLUDE_LIST=projects/$CUSTOMER_PROJECT_ID

    docker run -it --rm -e BQ_PROJECT=${BQ_PROJECT_ID} \
        -e LOCATION=${LOCATION} \
        -e ORG_DOMAIN=${CUSTOMER_ORGANIZATION_ID} \
        -e BQDATASET_FINDING=${BQDATASET_FINDING} \
        -e BQDATASET_INVENTORY=${BQDATASET_CAI} \
        -e INCLUDE_LIST=${INCLUDE_LIST} \
        -v "$HOME/.config/gcloud":/root/.config/gcloud \
        us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-scanner:latest
    
    docker ps
done


