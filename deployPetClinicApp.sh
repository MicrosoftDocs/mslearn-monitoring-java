#!/bin/bash
set -e

# ==== Customize the below for your environment====
resource_group='rg-learn-petclinic'
region='eastus'
spring_apps_service='asa-fm-learn-petclinic'
mysql_server_name='mysql-fm-learn-petclinic'
mysql_server_admin_name='azureuser'
mysql_server_admin_password='Corp123456789!'
log_analytics='law-fm-learn-petclinic'

#########################################################
# When error happened following function will be executed
#########################################################

function error_handler() {
# az group delete --no-wait --yes --name $resource_group
echo "ERROR occured :line no = $2" >&2
exit 1
}

trap 'error_handler $? ${LINENO}' ERR
#########################################################
# Resource Creation
#########################################################

#Add Required extensions
az extension add --name spring

#set variables
DEVBOX_IP_ADDRESS=$(curl ifconfig.me)

#Create directory for github code
project_directory=$HOME
cd ${project_directory}
mkdir -p source-code
cd source-code
rm -rdf spring-petclinic-microservices

#Clone GitHub Repo
printf "\n"
printf "Cloning the sample project: https://github.com/felipmiguel/spring-petclinic-microservices"
printf "\n"

git clone https://github.com/felipmiguel/spring-petclinic-microservices
cd spring-petclinic-microservices
git checkout 3.0.0
mvn clean package -DskipTests

# ==== Service and App Instances ====
api_gateway='api-gateway'
admin_server='admin-server'
customers_service='customers-service'
vets_service='vets-service'
visits_service='visits-service'

# ==== PetClinic version ====
petclinic_version='3.0.1'

# ==== JARS ====
api_gateway_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-api-gateway/target/spring-petclinic-api-gateway-${petclinic_version}.jar"
admin_server_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-admin-server/target/spring-petclinic-admin-server-${petclinic_version}.jar"
customers_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-customers-service/target/spring-petclinic-customers-service-${petclinic_version}.jar"
vets_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-vets-service/target/spring-petclinic-vets-service-${petclinic_version}.jar"
visits_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-visits-service/target/spring-petclinic-visits-service-${petclinic_version}.jar"

# ==== MYSQL INFO ====
mysql_server_full_name="${mysql_server_name}.mysql.database.azure.com"
mysql_server_admin_login_name="${mysql_server_admin_name}@${mysql_server_full_name}"
mysql_database_name='petclinic'
mysql_msi_name="msi-${mysql_server_name}"

cd "${project_directory}/source-code/spring-petclinic-microservices"

printf "\n"
printf "Creating the Resource Group: ${resource_group} Region: ${region}"
printf "\n"

az group create --name ${resource_group} --location ${region}

printf "\n"
printf "Creating the MySQL Server: ${mysql_server_name}"
printf "\n"

az mysql flexible-server create \
    --resource-group ${resource_group} \
    --name ${mysql_server_name} \
    --location ${region} \
    --tier Burstable \
    --sku-name Standard_B1ms \
    --public-access 0.0.0.0 \
    --storage-size 32 \
    --admin-user ${mysql_server_admin_name} \
    --admin-password ${mysql_server_admin_password}

az mysql flexible-server db create \
    --resource-group ${resource_group} \
    --server-name ${mysql_server_name} \
    --database-name ${mysql_database_name}

az mysql flexible-server firewall-rule create \
    --resource-group ${resource_group} \
    --rule-name ${mysql_server_name}-database-allow-local-ip \
    --name ${mysql_server_name} \
    --start-ip-address ${DEVBOX_IP_ADDRESS} \
    --end-ip-address ${DEVBOX_IP_ADDRESS}

# create managed identity for mysql. By assigning the identity to the mysql server, it will enable Azure AD authentication
az identity create \
        --name ${mysql_msi_name} \
        --resource-group ${resource_group} \
        --location ${region}

IDENTITY_ID=$(az identity show --name ${mysql_msi_name} --resource-group ${resource_group} --query id -o tsv)



printf "\n"
printf "Creating the Spring Apps: ${spring_apps_service}"
printf "\n"

az spring create \
    --resource-group ${resource_group} \
    --name ${spring_apps_service} \
    --location ${region} \
    --sku standard \
    --disable-app-insights false 

az configure --defaults group=${resource_group} location=${region} spring=${spring_apps_service}

az spring config-server set --config-file application.yml --name ${spring_apps_service}

printf "\n"
printf "Creating the microservice apps"
printf "\n"

az spring app create --name ${api_gateway} --instance-count 1 --assign-endpoint true \
    --runtime-version Java_17 \
    --memory 2Gi --jvm-options='-Xms2048m -Xmx2048m' &
az spring app create --name ${admin_server} --instance-count 1 --assign-endpoint true \
    --runtime-version Java_17 \
    --memory 2Gi --jvm-options='-Xms2048m -Xmx2048m' &
az spring app create --name ${customers_service} \
    --runtime-version Java_17 \
    --instance-count 1 --memory 2Gi --jvm-options='-Xms2048m -Xmx2048m' &
az spring app create --name ${vets_service} \
    --runtime-version Java_17 \
    --instance-count 1 --memory 2Gi --jvm-options='-Xms2048m -Xmx2048m' &
az spring app create --name ${visits_service} \
    --runtime-version Java_17 \
    --instance-count 1 --memory 2Gi --jvm-options='-Xms2048m -Xmx2048m' &

wait

# increase connection timeout
az mysql flexible-server parameter set --name wait_timeout \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value 2147483

az mysql flexible-server parameter set --name slow_query_log \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql flexible-server parameter set --name audit_log_enabled \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql flexible-server parameter set --name audit_log_events \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value "ADMIN,CONNECTION,DCL,DDL,DML,DML_NONSELECT,DML_SELECT,GENERAL,TABLE_ACCESS"

az mysql flexible-server parameter set --name log_queries_not_using_indexes \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql flexible-server parameter set --name long_query_time \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value 0

#mysql Configuration 
# mysql -h"${mysql_server_full_name}" -u"${mysql_server_admin_login_name}" \
#      -p"${mysql_server_admin_password}" \
#      -e  "CREATE DATABASE petclinic;CREATE USER 'root' IDENTIFIED BY 'petclinic';GRANT ALL PRIVILEGES ON petclinic.* TO 'root';"

# mysql -h"${mysql_server_full_name}" -u"${mysql_server_admin_login_name}" \
#      -p"${mysql_server_admin_password}" \
#      -e  "CALL mysql.az_load_timezone();"

az mysql flexible-server parameter set --name time_zone \
  --resource-group ${resource_group} \
  --server ${mysql_server_name} --value "US/Central"

az mysql flexible-server parameter set --name slow_query_log  \
  --resource-group ${resource_group} \
  --server ${mysql_server_name} --value ON

# az mysql flexible-server parameter set --name query_store_capture_interval \
#   --resource-group ${resource_group} \
#   --server ${mysql_server_name} --value 5

printf "\n"
printf "Create service connections from Spring Apps applications to MySQL database"
printf "\n"

az spring connection create mysql-flexible \
    --resource-group ${resource_group} \
    --service ${spring_apps_service} \
    --app ${customers_service} \
    --deployment default \
    --tg ${resource_group} \
    --server ${mysql_server_name} \
    --database ${mysql_database_name} \
    --system-identity mysql-identity-id=$IDENTITY_ID \
    --client-type springboot &

az spring connection create mysql-flexible \
    --resource-group ${resource_group} \
    --service ${spring_apps_service} \
    --app ${visits_service} \
    --deployment default \
    --tg ${resource_group} \
    --server ${mysql_server_name} \
    --database ${mysql_database_name} \
    --system-identity mysql-identity-id=$IDENTITY_ID \
    --client-type springboot &

az spring connection create mysql-flexible \
    --resource-group ${resource_group} \
    --service ${spring_apps_service} \
    --app ${vets_service} \
    --deployment default \
    --tg ${resource_group} \
    --server ${mysql_server_name} \
    --database ${mysql_database_name} \
    --system-identity mysql-identity-id=$IDENTITY_ID \
    --client-type springboot &

wait

printf "\n"
printf "Deploying the apps to Spring Apps"
printf "\n"

az spring app deploy --name ${api_gateway} \
    --artifact-path ${api_gateway_jar} \
    --runtime-version Java_17 \
    --jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql' &

az spring app deploy --name ${admin_server} \
    --artifact-path ${admin_server_jar} \
    --runtime-version Java_17 \
    --jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql' &

az spring app deploy --name ${customers_service} \
--artifact-path ${customers_service_jar} \
--runtime-version Java_17 \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=passwordless' &

az spring app deploy --name ${vets_service} \
--artifact-path ${vets_service_jar} \
--runtime-version Java_17 \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=passwordless' &

az spring app deploy --name ${visits_service} \
--artifact-path ${visits_service_jar} \
--runtime-version Java_17 \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=passwordless' &

wait

printf "\n"
printf "Creating the log anaytics workspace: ${log_analytics}"
printf "\n"

az monitor log-analytics workspace create \
    --workspace-name ${log_analytics} \
    --resource-group ${resource_group} \
    --location ${region}           
                            
export LOG_ANALYTICS_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --resource-group ${resource_group} \
    --workspace-name ${log_analytics} \
    --query 'id' \
    --output tsv)

export WEBAPP_RESOURCE_ID=$(az spring show --name ${spring_apps_service} --resource-group ${resource_group} --query 'id' --output tsv)

az monitor diagnostic-settings create --name "send-spring-logs-and-metrics-to-log-analytics" \
    --resource ${WEBAPP_RESOURCE_ID} \
    --workspace ${LOG_ANALYTICS_RESOURCE_ID} \
    --logs '[
         {
           "category": "SystemLogs",
           "enabled": true,
           "retentionPolicy": {
             "enabled": false,
             "days": 0
           }
         },
         {
            "category": "ApplicationConsole",
            "enabled": true,
            "retentionPolicy": {
              "enabled": false,
              "days": 0
            }
          }        
       ]' \
       --metrics '[
         {
           "category": "AllMetrics",
           "enabled": true,
           "retentionPolicy": {
             "enabled": false,
             "days": 0
           }
         }
       ]'

export MYSQL_RESOURCE_ID=$(az mysql flexible-server show --name ${mysql_server_name} --resource-group ${resource_group} --query 'id' --output tsv)

az monitor diagnostic-settings create --name "send-mysql-logs-and-metrics-to-log-analytics" \
    --resource ${MYSQL_RESOURCE_ID} \
    --workspace ${LOG_ANALYTICS_RESOURCE_ID} \
    --logs '[
         {
           "category": "MySqlAuditLogs",
           "enabled": true,
           "retentionPolicy": {
             "enabled": false,
             "days": 0
           }
         },
         {
            "category": "MySqlSlowLogs",
            "enabled": true,
            "retentionPolicy": {
              "enabled": false,
              "days": 0
            }
          }        
       ]' \
       --metrics '[
         {
           "category": "AllMetrics",
           "enabled": true,
           "retentionPolicy": {
             "enabled": false,
             "days": 0
           }
         }
       ]'

export GATEWAY_URL=$(az spring app show --name ${api_gateway} --query 'properties.url' --output tsv)

printf "\n"
printf "Testing the deployed services at ${GATEWAY_URL}"
printf "\n"

for i in `seq 1 10`; 
do
   curl -g ${GATEWAY_URL}/api/customer/owners
   curl -g ${GATEWAY_URL}/api/customer/owners/4
   curl -g ${GATEWAY_URL}/api/customer/petTypes
   curl -g ${GATEWAY_URL}/api/customer/owners/3/pets/4
   curl -g ${GATEWAY_URL}/api/customer/owners/6/pets/8/
   curl -g ${GATEWAY_URL}/api/vet/vets
   curl -g ${GATEWAY_URL}/api/visit/owners/6/pets/8/visits
done

printf "\n"
printf "Completed testing the deployed services"
printf "\n"
printf "${GATEWAY_URL}"
printf "\n"
