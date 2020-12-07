# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file contains bash functions used by various scripts in this direcotry.
# Don't run this file directly -- it gets loaded by other files.

function add_secret {
  # usage:
  #   add_secret SECRETS_ENV_FILE NAME VALUE
  # Adds an environment variable to the "k8s" section of SECRETS_ENV_FILE, and also sets in
  # in the current environment for the remainder of the current process.
  secrets_env_file=$1
  name=$2
  value=$3
  date="`date`"
  escaped_value=$(echo "$3" | sed -e 's|\/|\\/|g')
  sed "s/^# kbootstrap-end: do not alter or remove this line!\$/export $name=\"$escaped_value\"  # generated by kbootstrap.sh at $date\n&/" ${secrets_env_file} > /tmp/test.env
  if [ -s /tmp/test.env ] ; then
    mv /tmp/test.env ${secrets_env_file}
    export $name="$value"
  else
    echo "Failure while updating secrets file; aborting."
    exit -1
  fi
}

function add_secret_from_file {
  # usage:
  #   add_secret SECRETS_ENV_FILE NAME FILE
  # Adds an environment variable to the "k8s" section of SECRETS_ENV_FILE, using the contents of FILE
  # as the value for the variable.  Also sets the variable in the current environment for the remainder
  # of the current process.
  secrets_env_file=$1
  name=$2
  file=$3
  date="`date`"
  echo "# generated by kbootstrap.sh at ${date}:" > /tmp/newvar.env
  echo "${name}=\$(cat <<EOF_EOF_EOF_EOF" >> /tmp/newvar.env
  cat ${file}            >> /tmp/newvar.env
  echo "EOF_EOF_EOF_EOF" >> /tmp/newvar.env
  echo ")"               >> /tmp/newvar.env
  echo "export ${name}"  >> /tmp/newvar.env
  sed $'/^# kbootstrap-end: do not alter or remove this line!$/{e cat /tmp/newvar.env\n}' ${secrets_env_file} > /tmp/test.env
  if [ -s /tmp/test.env ] ; then
    mv /tmp/test.env ${secrets_env_file}
    . /tmp/newvar.env
    rm /tmp/newvar.env
  else
    echo "Failure while updating secrets file; aborting."
    exit -1
  fi
}

function generate_password {
  # Generates a random 18-character password.
  echo "p`(date ; dd if=/dev/urandom count=2 bs=1024) 2>/dev/null | md5sum | head -c 17`"
}

function generate_bucket_suffix {
  # Generates a random 16-character password that can be used as a bucket name suffix
  echo "b`(date ; dd if=/dev/urandom count=2 bs=1024) 2>/dev/null | md5sum | head -c 15`"
}

function generate_secret_key {
  # Generates a random 16-character string that can be used as a secret key value
  echo "k`(date ; dd if=/dev/urandom count=2 bs=1024) 2>/dev/null | md5sum | head -c 15`"
}

function generate_secret_key50 {
  # Generates a random 50-character string that can be used as a secret key value
  echo "k`((date ; dd if=/dev/urandom count=2 bs=1024) | sha512sum -b | head -c 49) 2>/dev/null`"
}

function wait_for_k8s_job {
  # usage:
  #   wait_for_k8s_job JOB
  # Waits for the k8s job named JOB to complete.  JOB should be a k8s "Job" resource
  # that is configured to run exactly once and then terminate.
  job=$1
  job_wait_recheck_seconds=5
  job_wait_max_seconds=300
  seconds_waited=0
  while [ $seconds_waited -le $job_wait_max_seconds ] ; do 
    echo "waiting for job $job to complete..."
    sleep $job_wait_recheck_seconds
    seconds_waited=$[$seconds_waited+$job_wait_recheck_seconds]
    completions=$(kubectl get job/$job -o=jsonpath='{.status.succeeded}')
    if [ "$completions" == "1" ] ; then
      return 0
    fi
  done
  echo "job $job did not complete after $job_wait_max_seconds seconds; giving up"
  exit -1
}


function wait_for_ingress_ip {
  name=$1
  wait_recheck_seconds=5
  wait_max_seconds=300
  seconds_waited=0
  while [ $seconds_waited -le $wait_max_seconds ] ; do 
    echo "waiting for ingress ip address to become available (this might take up to 5 minutes)..."
    sleep $wait_recheck_seconds
    seconds_waited=$[$seconds_waited+$wait_recheck_seconds]
    INGRESS_IP=$(kubectl get ingress ${name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ "${INGRESS_IP}" != "" ] ; then
      return 0
    fi
  done
  echo "ingress ip address failed to become available after $wait_max_seconds seconds; giving up"
  exit -1
}

function wait_for_k8s_deployment_app_ready {
  # usage:
  #   wait_for_k8s_deployment_app_ready DEPLOYMENT
  # Waits for the named k8s deployment's pod to become ready.  The # replicas (pods) in the deployemtn must be 1.
  deployment=$1
  deployment_wait_recheck_seconds=2
  deployment_wait_max_seconds=300
  seconds_waited=0
  while [ $seconds_waited -le $deployment_wait_max_seconds ] ; do 
    echo "waiting for $deployment to be ready..."
    sleep $deployment_wait_recheck_seconds
    seconds_waited=$[$seconds_waited+$deployment_wait_recheck_seconds]
    phase="$(kubectl get pods --selector=app=${deployment} -o=jsonpath='{.items[0].status.phase}')"
    if [ "$phase" == "Running" ] ; then
      return 0
    fi
  done
  echo "deployment $deployment not ready after $deployment_wait_max_seconds seconds; giving up"
  exit -1
}

function clone_repo {
  # usage:
  #   clone_repo REPO DIR [ PARENT ]
  repo=$1
  dir=$2
  parent=$3

  if [ "$parent" == "" ] ; then
    path="$dir"
    parent="."
  else
    path="$parent/$dir"
  fi
  if [ -d $path ] ; then
    echo "Warning: not cloning $path because directory already exists"
    return
  fi
  ( cd $parent ; git clone $repo $dir )
}


function build_sha {
  app=$1
  if [ "${app}" == "fe" ] ; then
    cat Dockerfile-fe container/config/fe/* | md5sum  | sed -e 's/\(.\{7\}\).*/\1/'
  elif  [ "${app}" == "oauth-proxy" ] ; then
    cat Dockerfile-oauth-proxy container/config/oauth-proxy/* | md5sum  | sed -e 's/\(.\{7\}\).*/\1/'
  elif  [ "${app}" == "editor" ] ; then
    (cd editor-website ; git rev-parse --short HEAD)
  elif  [ "${app}" == "cgimap" ] ; then
    (cd openstreetmap-cgimap ; git rev-parse --short HEAD)
  elif  [ "${app}" == "warper" ] ; then
    (cd warper ; git rev-parse --short HEAD)
  elif  [ "${app}" == "kartta" ] ; then
    (cd kartta ; git rev-parse --short HEAD)
  elif  [ "${app}" == "noter-backend" ] ; then
    (cd noter-backend ; git rev-parse --short HEAD)
  elif  [ "${app}" == "noter-frontend" ] ; then
    (cd noter-frontend ; git rev-parse --short HEAD)
  elif  [ "${app}" == "reservoir" ] ; then
    (cd reservoir ; git rev-parse --short HEAD)
  else
    echo "ERROR: don't know how to generate build sha for app ${app}"
   exit -1
  fi
}

# Return the deployed branch for a repo.
# Usage is like
#    repo_branch "${SOME_REPO}"
# where SOME_REPO is one of the *_REPO vars defined in secrets.env (e.g. MAPWARPER_REPO).
# Note the double-quite delimeters are required.
function repo_branch {
  repo=$1
  branch=$(echo "$repo" | sed -n 's/^.*--branch \([^ ]*\).*$/\1/p')
  if [ -z "$branch" ]; then
    echo "master"
  else
    echo "$branch"
  fi
}




# Return the directory (relative to Project/) for cloud builds for an app.
function build_dir {
  app=$1
  # kartta and reservoir get built from their respective subdirs; everything else gets build from
  # the top level Project dir (".")
  if [ "${app}" == "kartta" ] ; then
    echo "kartta"
  elif  [ "${app}" == "reservoir" ] ; then
    echo "reservoir"
  else
    echo "."
  fi
}

function update_repos {
    app=$1
    case $app in
        cgimap)
	    git pull origin re-brand # update Project repo
            (cd openstreetmap-cgimap ; git pull origin $(repo_branch "${CGIMAP_REPO}"))
            ;;
        editor)
	    git pull origin re-brand # update Project repo
            (cd editor-website ; git pull origin $(repo_branch "${EDITOR_REPO}"))
            ;;
        fe)
	    (cd kscope ; git pull origin $(repo_branch "${KSCOPE_REPO}"))
	    git pull origin re-brand # update Project repo
            ;;
        kartta)
	    git pull origin re-brand # update Project repo
            (cd kartta ; git pull origin $(repo_branch "${KARTTA_REPO}"))
            (cd kartta/antique ; git pull origin $(repo_branch "${ANTIQUE_REPO}"))
            ;;
        noter-backend)
	    git pull origin re-brand # update Project repo
            (cd noter-backend ; git pull origin $(repo_branch "${NOTER_BACKEND_REPO}"))
            ;;
        noter-frontend)
	    git pull origin re-brand # update Project repo
            (cd noter-frontend ; git pull origin $(repo_branch "${NOTER_FRONTEND_REPO}"))
            ;;
        oauth-proxy)
	    git pull origin re-brand # update Project repo
            ;;
        reservoir)
	    git pull origin re-brand # update Project repo
            (cd reservoir ; git pull origin $(repo_branch "${RESERVOIR_REPO}"))
            ;;
        warper)
	    git pull origin re-brand # update Project repo
            (cd warper ; git pull origin $(repo_branch "${MAPWARPER_REPO}"))
            ;;
        tegola)
	    git pull origin re-brand # update Project repo
            (cd tegola ; git pull origin $(repo_branch "${TEGOLA_REPO}"))
            (cd antique ; git pull origin $(repo_branch "${ANTIQUE_REPO}"))
            ;;
        *)
	    echo 'CATCHALL'
            ;;
    esac
}

function cloud_build {
  # usage:
  #    cloud_build APP
  app=$1

  short_sha=$(build_sha ${app})
  clouddbuild_yaml="k8s/cloudbuild-${app}.yaml"

  if [ ! -f ${clouddbuild_yaml} ] ; then
    echo "Error: not building ${app} because ${clouddbuild_yaml} not found"
    return
  fi

  gcloud builds submit "--gcs-log-dir=${CLOUDBUILD_LOGS_BUCKET}/$app" "--substitutions=SHORT_SHA=${short_sha}"  --config ${clouddbuild_yaml} $(build_dir ${app})
  gcloud container images add-tag --quiet "gcr.io/${GCP_PROJECT_ID}/${app}:${short_sha}" "gcr.io/${GCP_PROJECT_ID}/${app}:latest"
}

function rolling_update {
  # usage:
  #    rolling_update APP
  app=$1
  tag=$(gcloud container images --format=json list-tags gcr.io/${GCP_PROJECT_ID}/${app} | ./k8s/klatest_tag)
  kubectl set image deployment ${app} ${app}=gcr.io/${GCP_PROJECT_ID}/${app}:${tag} --record
  kubectl rollout restart deployment ${app}
}


# Make sure container/secrets is clean and up to date; exit with error message if not.
# This function executes a "git pull" in container/secrets to make sure the local dir
# contains any new updates from remote.  It does not, however, automatically push any
# local updates to remote -- it just checks for them and exits if there are any.
function ensure_synced_secrets {
  cd ./container/secrets

  # initial check for clean working dir
  if output=$(git status --porcelain) && [ -z "$output" ]; then
    : # Working directory clean, continue below
  else
    echo ""
    echo "You appear to have uncommited changes in ./container/secrets."
    echo "Please commit and push them, then try again."
    echo ""
    exit -1
  fi

  # pull from remote
  if git pull origin master; then
    : # pull was successful, continue below
  else
    echo ""
    echo "There was an issue updating your ./container/secrets."
    echo "Please ensure it is up to date and clean, then try again."
    echo ""
    exit -1
  fi    

  # second check for clean working dir, in case the pull above resulting in
  # any issues
  if output=$(git status --porcelain) && [ -z "$output" ]; then
    : # Working directory clean, continue below
  else
    echo ""
    echo "There was an issue updating your ./container/secrets."
    echo "Please ensure it is up to date and clean, then try again."
    echo ""
    exit -1
  fi

  # check for unpushed local commits
  if [ -z "$(git status -sb | grep ahead)" ]; then
    : # local dir is not ahead of remote
  else
    echo ""
    echo "You appear to have unpushed commits in ./container/secrets."
    echo "Please push them, then try again."
    echo ""
    exit -1
  fi

  cd ../..
}
