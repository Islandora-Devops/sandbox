#!/command/with-contenv bash
# shellcheck shell=bash
set -e

# shellcheck disable=SC1091
source /etc/islandora/utilities.sh

readonly SITE="default"
readonly QUEUES=(
	islandora-connector-fits
	islandora-connector-homarus
	islandora-connector-houdini
	islandora-connector-ocr
)

function jolokia {
	local type="${1}"
	local queue="${2}"
	local action="${3}"
	# @todo use environment variables?
	local url="http://${DRUPAL_DEFAULT_BROKER_HOST}:8161/api/jolokia/${type}/org.apache.activemq:type=Broker,brokerName=localhost,destinationType=Queue,destinationName=${queue}"
	if [ "$action" != "" ]; then
		url="${url}/$action"
	fi
	curl -u "admin:${DRUPAL_ACTIVEMQ_WEB_ADMIN_PASSWORD}" "${url}"
}

function pause_queues {
	for queue in "${QUEUES[@]}"; do
		jolokia "exec" "${queue}" "pause" &
	done
	wait
}

function resume_queues {
	for queue in "${QUEUES[@]}"; do
		jolokia "exec" "${queue}" "resume" &
	done
	wait
}

function purge_queues {
	for queue in "${QUEUES[@]}"; do
		jolokia "exec" "${queue}" "purge" &
	done
	wait
}

function configure {
 # Work around for when the cache is in a bad state, as Drush will access
 # the cache before rebuilding it for some dumb reason, preventing
 # Drush from being able to clear it.
  local params=$(/var/www/drupal/web/core/scripts/rebuild_token_calculator.sh 2>/dev/null)
  curl "${DRUPAL_DRUSH_URI}/core/rebuild.php?${params}"
	# Starter site post install steps.
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" cache:rebuild
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" user:role:add fedoraadmin admin
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" pm:uninstall pgsql sqlite
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" migrate:import --userid=1 --tag=islandora
	# Pause queue consumption during import.
	pause_queues
	# Ingest Content via Workbench.
	cd /var/www/drupal/islandora_workbench
	./workbench --config /var/www/drupal/islandora_demo_objects/create_islandora_objects.yml
	cd /var/www/drupal
	# Files already exist clear the brokers to prevent generating derivatives again.
	purge_queues
	# Resume consumption of the queues.
	resume_queues
	# Remaining cleanup.
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" cron || true
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" search-api:index || true
	drush --root=/var/www/drupal --uri="${DRUPAL_DRUSH_URI}" cache:rebuild
}

function wait_for_valid_certificate {
	# Set the start time
	start_time=$(date +%s)

	# Set the maximum time to wait (5 minutes)
	max_time=300

	# Loop until the request is successful or the maximum time has passed
	while true; do
		# Make the curl request and save the response status
		response=$(timeout $max_time curl --silent --output /dev/null --write-out "%{http_code}" -X HEAD "${DRUPAL_DEFAULT_FCREPO_URL}")

		# If the response status is 200, exit the loop and return 0
		if [ "$response" -eq 200 ]; then
			echo "Valid certificate"
			return 0
		fi

		# Get the current time
		current_time=$(date +%s)

		# If 5 minutes have passed, exit the loop and return 1
		if [ "$((current_time - start_time))" -ge "$max_time" ]; then
			echo "Request failed after 5 minutes."
			return 1
		fi

		# Wait for 1 second before making the next request
		sleep 1
	done
}

function install {
	wait_for_service "${SITE}" db
	create_database "${SITE}"
	install_site "${SITE}"
	wait_for_service "${SITE}" broker
	wait_for_service "${SITE}" fcrepo
	wait_for_service "${SITE}" fits
	wait_for_service "${SITE}" solr
	wait_for_service "${SITE}" triplestore
	create_blazegraph_namespace_with_default_properties "${SITE}"
	if [[ "${DRUPAL_DEFAULT_FCREPO_URL}" == https* ]]; then
		# Certificates might need to be generated which can take many minutes to be issued.
		if ! wait_for_valid_certificate; then
			exit 1
		fi
	fi
	configure
}

function mysql_count_query {
	cat <<-EOF
		    SELECT COUNT(DISTINCT table_name)
		    FROM information_schema.columns
		    WHERE table_schema = '${DRUPAL_DEFAULT_DB_NAME}';
	EOF
}

# Check the number of tables to determine if it has already been installed.
function installed {
	local count
	count=$(execute-sql-file.sh <(mysql_count_query) -- -N 2>/dev/null) || exit $?
	[[ $count -ne 0 ]]
}

# Required even if not installing.
function setup() {
	local site drupal_root subdir site_directory public_files_directory private_files_directory twig_cache_directory
	site="${1}"
	shift

	drupal_root=/var/www/drupal/web
	subdir=$(drupal_site_env "${site}" "SUBDIR")
	site_directory="${drupal_root}/sites/${subdir}"
	public_files_directory="${site_directory}/files"
	private_files_directory="/var/www/drupal/private"
	twig_cache_directory="${private_files_directory}/php"

	# Ensure the files directories are writable by nginx, as when it is a new volume it is owned by root.
	mkdir -p "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
	chown nginx:nginx "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
	chmod ug+rw "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
}

function drush_cache_setup {
	# Make sure the default drush cache directory exists and is writeable.
	mkdir -p /tmp/drush-/cache
	chmod a+rwx /tmp/drush-/cache
}

# External processes can look for `/installed` to check if installation is completed.
function finished {
	touch /installed
	cat <<-EOT


		        #####################
		        # Install Completed #
		        #####################
	EOT
}

function main() {
	# Used to display progress.
	date +%s >/install-started
	chmod a+r /install-started
	# Setup.
	cd /var/www/drupal
	drush_cache_setup
	for_all_sites setup

	if installed; then
		echo "Already Installed"
	else
		echo "Installing"
		install
	fi
	finished
}
main
