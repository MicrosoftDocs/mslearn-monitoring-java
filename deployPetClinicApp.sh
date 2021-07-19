#!/bin/bash
set -e

# ==== Customize the below for your environment====
resource_group='your-resource-group-name'
region='westeurope'
spring_cloud_service='your-azure-spring-cloud-name'
mysql_server_name='your-sql-server-name'
mysql_server_admin_name='your-sql-server-admin-name'
mysql_server_admin_password='your-password'
log_analytics='your-analytics-name'

#########################################################
# When error happened following function will be executed
#########################################################

function error_handler() {
az group delete --no-wait --yes --name $resource_group
echo "ERROR occured :line no = $2" >&2
exit 1
}

trap 'error_handler $? ${LINENO}' ERR
#########################################################
# Resource Creation
#########################################################

#Add Required extensions
az extension add --name spring-cloud

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
printf "Cloning the sample project: https://github.com/azure-samples/spring-petclinic-microservices"
printf "\n"

git clone https://github.com/azure-samples/spring-petclinic-microservices
cd spring-petclinic-microservices
mvn clean package -DskipTests -Denv=cloud

# ==== Service and App Instances ====
api_gateway='api-gateway'
admin_server='admin-server'
customers_service='customers-service'
vets_service='vets-service'
visits_service='visits-service'

# ==== JARS ====
api_gateway_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-api-gateway/target/spring-petclinic-api-gateway-2.3.6.jar"
admin_server_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-admin-server/target/spring-petclinic-admin-server-2.3.6.jar"
customers_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-customers-service/target/spring-petclinic-customers-service-2.3.6.jar"
vets_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-vets-service/target/spring-petclinic-vets-service-2.3.6.jar"
visits_service_jar="${project_directory}/source-code/spring-petclinic-microservices/spring-petclinic-visits-service/target/spring-petclinic-visits-service-2.3.6.jar"

# ==== MYSQL INFO ====
mysql_server_full_name="${mysql_server_name}.mysql.database.azure.com"
mysql_server_admin_login_name="${mysql_server_admin_name}@${mysql_server_full_name}"
mysql_database_name='petclinic'

cd "${project_directory}/source-code/spring-petclinic-microservices"

printf "\n"
printf "Creating the Resource Group: ${resource_group} Region: ${region}"
printf "\n"

az group create --name ${resource_group} --location ${region}

printf "\n"
printf "Creating the MySQL Server: ${mysql_server_name}"
printf "\n"

az mysql server create \
    --resource-group ${resource_group} \
    --name ${mysql_server_name} \
    --location ${region} \
    --sku-name GP_Gen5_2 \
    --storage-size 5120 \
    --admin-user ${mysql_server_admin_name} \
    --admin-password ${mysql_server_admin_password} \
    --ssl-enforcement Disabled

az mysql server firewall-rule create \
    --resource-group ${resource_group} \
    --name ${mysql_server_name}-database-allow-local-ip \
    --server ${mysql_server_name} \
    --start-ip-address ${DEVBOX_IP_ADDRESS} \
    --end-ip-address ${DEVBOX_IP_ADDRESS}

az mysql server firewall-rule create \
    --resource-group ${resource_group} \
    --name allAzureIPs \
    --server ${mysql_server_name} \
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

printf "\n"
printf "Creating the Spring Cloud: ${spring_cloud_service}"
printf "\n"

az spring-cloud create \
    --resource-group ${resource_group} \
    --name ${spring_cloud_service} \
    --location ${region} \
    --sku standard \
    --disable-app-insights false \
    --enable-java-agent true

az configure --defaults group=${resource_group} location=${region} spring-cloud=${spring_cloud_service}

az spring-cloud config-server set --config-file application.yml --name ${spring_cloud_service}

printf "\n"
printf "Creating the MicroService Apps"
printf "\n"

az spring-cloud app create --name ${api_gateway} --instance-count 1 --assign-endpoint true \
    --memory 2 --jvm-options='-Xms2048m -Xmx2048m'
az spring-cloud app create --name ${admin_server} --instance-count 1 --assign-endpoint true \
    --memory 2 --jvm-options='-Xms2048m -Xmx2048m'
az spring-cloud app create --name ${customers_service} \
    --instance-count 1 --memory 2 --jvm-options='-Xms2048m -Xmx2048m'
az spring-cloud app create --name ${vets_service} \
    --instance-count 1 --memory 2 --jvm-options='-Xms2048m -Xmx2048m'
az spring-cloud app create --name ${visits_service} \
    --instance-count 1 --memory 2 --jvm-options='-Xms2048m -Xmx2048m'

# increase connection timeout
az mysql server configuration set --name wait_timeout \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value 2147483

az mysql server configuration set --name slow_query_log \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql server configuration set --name audit_log_enabled \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql server configuration set --name audit_log_events \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value "ADMIN,CONNECTION,DCL,DDL,DML,DML_NONSELECT,DML_SELECT,GENERAL,TABLE_ACCESS"

az mysql server configuration set --name log_queries_not_using_indexes \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value ON

az mysql server configuration set --name long_query_time \
 --resource-group ${resource_group} \
 --server ${mysql_server_name} --value 0

#mysql Configuration 
mysql -h"${mysql_server_full_name}" -u"${mysql_server_admin_login_name}" \
     -p"${mysql_server_admin_password}" \
     -e  "CREATE DATABASE petclinic;CREATE USER 'root' IDENTIFIED BY 'petclinic';GRANT ALL PRIVILEGES ON petclinic.* TO 'root';"

mysql -h"${mysql_server_full_name}" -u"${mysql_server_admin_login_name}" \
     -p"${mysql_server_admin_password}" \
     -e  "CALL mysql.az_load_timezone();"

az mysql server configuration set --name time_zone \
  --resource-group ${resource_group} \
  --server ${mysql_server_name} --value "US/Eastern"

az mysql server configuration set --name query_store_capture_mode \
  --resource-group ${resource_group} \
  --server ${mysql_server_name} --value ALL

az mysql server configuration set --name query_store_capture_interval \
  --resource-group ${resource_group} \
  --server ${mysql_server_name} --value 5

printf "\n"
printf "Deploying the Apps to the Spring Cloud"
printf "\n"

az spring-cloud app deploy --name ${api_gateway} \
    --jar-path ${api_gateway_jar} \
    --jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql'

az spring-cloud app deploy --name ${admin_server} \
    --jar-path ${admin_server_jar} \
    --jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql'

az spring-cloud app deploy --name ${customers_service} \
--jar-path ${customers_service_jar} \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql' \
--env mysql_server_full_name=${mysql_server_full_name} \
      mysql_database_name=${mysql_database_name} \
      mysql_server_admin_login_name=${mysql_server_admin_login_name} \
      mysql_server_admin_password=${mysql_server_admin_password}

az spring-cloud app deploy --name ${vets_service} \
--jar-path ${vets_service_jar} \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql' \
--env mysql_server_full_name=${mysql_server_full_name} \
      mysql_database_name=${mysql_database_name} \
      mysql_server_admin_login_name=${mysql_server_admin_login_name} \
      mysql_server_admin_password=${mysql_server_admin_password}

az spring-cloud app deploy --name ${visits_service} \
--jar-path ${visits_service_jar} \
--jvm-options='-Xms2048m -Xmx2048m -Dspring.profiles.active=mysql' \
--env mysql_server_full_name=${mysql_server_full_name} \
      mysql_database_name=${mysql_database_name} \
      mysql_server_admin_login_name=${mysql_server_admin_login_name} \
      mysql_server_admin_password=${mysql_server_admin_password}

printf "\n"
printf "Creating the log anaytics workspace: ${log_analytics}"
printf "\n"

az monitor log-analytics workspace create \
    --workspace-name ${log_analytics} \
    --resource-group ${resource_group} \
    --location ${region}           
                            
export LOG_ANALYTICS_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --resource-group ${resource_group} \
    --workspace-name ${log_analytics} | jq -r '.id')

export WEBAPP_RESOURCE_ID=$(az spring-cloud show --name ${spring_cloud_service} --resource-group ${resource_group} | jq -r '.id')

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

export MYSQL_RESOURCE_ID=$(az mysql server show --name ${mysql_server_name} --resource-group ${resource_group} | jq -r '.id')

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

export GATEWAY_URL=$(az spring-cloud app show --name ${api_gateway} | jq -r '.properties.url')

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
