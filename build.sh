#!/bin/bash

help() {
  echo "Help:"
  echo "Apicurio Registry Operator build tool"
  echo "Note: Run this script from the root dir of the project."
  echo -e "\n$0 [command] [parameters]..."
  echo -e "\nCommands: "
  echo "  build"
  echo "  help"
  echo "  mkdeploy"
  echo "  mkundeploy"
  echo "  push"
  echo -e "\nParameters:"
  echo "  -r|--repository [repository] Operator image repository"
  echo "  -n|--namespace [namespace] Namespace where the operator is deployed"
  echo "  --cr [file] Path to a file with 'ApicurioRegistry' custom resource to be deployed"
  echo "  --nocr Do not deploy default 'ApicurioRegistry' custom resource"
  echo "  --crname [name] Name of the 'ApicurioRegistry' custom resource (e.g. for mkundeploy), default is 'example-apicurioregistry'"
  echo "  --latest Also push the image with the 'latest' tag"
  exit 1
}

error() {
  echo -e "Error: $1\n"
  help
}

require() {
  if [[ -z "$1" ]]; then
    error "$2"
  fi
}

init_image() {
  require "$OPERATOR_IMAGE_REPOSITORY" "Parameter '-r' is required."
  VERSION=$(sed -n 's/^.*Version.*=.*"\(.*\)".*$/\1/p' ./version/version.go)
  DASH_VERSION_RELEASE=$(echo "$VERSION" | sed -n 's/^[0-9\.]*-\([^-+]*\).*$/-\1/p')
  require "$VERSION" "Could not read project version."
  OPERATOR_IMAGE_NAME="$OPERATOR_IMAGE_REPOSITORY/apicurio-registry-operator"
  OPERATOR_IMAGE="$OPERATOR_IMAGE_NAME:$VERSION"
}

replace() {
  init_image
  sed -i "s|{OPERATOR_IMAGE}|$OPERATOR_IMAGE # replaced {OPERATOR_IMAGE}|g" ./deploy/operator.yaml
}

unreplace() {
  sed -i "s|$OPERATOR_IMAGE # replaced {OPERATOR_IMAGE}|{OPERATOR_IMAGE}|g" ./deploy/operator.yaml
}

build() {
  replace
  operator-sdk generate k8s
  operator-sdk generate crds
  operator-sdk build "$OPERATOR_IMAGE"
  docker tag "$OPERATOR_IMAGE" "$OPERATOR_IMAGE_NAME:latest$DASH_VERSION_RELEASE"
  compile_qs_yaml
  unreplace
}

minikube_deploy_cr() {
  if [[ -z "$CR_PATH" ]]; then
    if [[ -z "$NO_DEFAULT_CR" ]]; then
      kubectl create -f ./deploy/crds/apicur.io_apicurioregistries_cr.yaml
    fi
  else
    kubectl create -f "$CR_PATH"
  fi
}

minikube_deploy() {
  require "$OPERATOR_NAMESPACE" "Argument -n or --namespace is required."
  replace
  kubectl create -f ./deploy/service_account.yaml
  kubectl create -f ./deploy/role.yaml
  kubectl create -f ./deploy/role_binding.yaml
  kubectl create -f ./deploy/cluster_role.yaml
  cat ./deploy/cluster_role_binding.yaml | sed "s/{NAMESPACE}/$OPERATOR_NAMESPACE # replaced {NAMESPACE}/g" | kubectl apply -f -
  kubectl create -f ./deploy/crds/apicur.io_apicurioregistries_crd.yaml
  kubectl create -f ./deploy/operator.yaml
  minikube_deploy_cr
  kubectl get deployments
  unreplace
}

compile_qs_yaml() {
  FILE="./docs/resources/install.yaml"
  echo "Warning: Make sure '$FILE' contains correct image references before committing."
  if [ -f "$FILE" ]; then
    rm "$FILE"
  fi
  echo -e "\n---"  >> "$FILE" && cat ./deploy/service_account.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/role.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/role_binding.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/cluster_role.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/cluster_role_binding.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/crds/apicur.io_apicurioregistries_crd.yaml >> "$FILE"
  echo -e "\n---"  >> "$FILE" && cat ./deploy/operator.yaml >> "$FILE"
  echo ""  >> "$FILE"
}

minikube_undeploy() {
  #kubectl delete ApicurioRegistry "$CR_NAME"
  kubectl delete deployment apicurio-registry-operator
  kubectl delete CustomResourceDefinition apicurioregistries.apicur.io
  kubectl delete RoleBinding apicurio-registry-operator
  kubectl delete Role apicurio-registry-operator
  kubectl delete ClusterRoleBinding apicurio-registry-operator
  kubectl delete ClusterRole apicurio-registry-operator
  kubectl delete ServiceAccount apicurio-registry-operator
}

push() {
  init_image
  docker push "$OPERATOR_IMAGE"
  if [[ -n "$PUSH_LATEST" ]]; then
    docker push "$OPERATOR_IMAGE_NAME:latest$DASH_VERSION_RELEASE"
  fi
}

if [ ! -f "./version/version.go" ]; then
    echo "Please run this script from the repository root."
    exit 1
fi

TARGET="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -r | --repository)
    OPERATOR_IMAGE_REPOSITORY="$2"
    shift
    ;;
  -n | --namespace)
    OPERATOR_NAMESPACE="$2"
    shift
    ;;
  --cr)
    CR_PATH="$2"
    shift
    ;;
  --nocr)
    NO_DEFAULT_CR="true"
    shift
    ;;
  --crname)
    CR_NAME="$2"
    shift
    ;;
  --latest)
    PUSH_LATEST="true"
    shift
    ;;
  *)
    echo -e "Unknown parameter: '$1'.\n"
    help
    ;;
  esac
  shift
done

if [[ -z "$CR_NAME" ]]; then
  CR_NAME="example-apicurioregistry"
fi

case "$TARGET" in
build) build ;;
mkdeploy) minikube_deploy ;;
mkundeploy) minikube_undeploy ;;
push) push ;;
help) help ;;
*)
  echo -e "Unknown command: '$TARGET'.\n"
  help
  ;;
esac
