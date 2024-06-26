# Terraform a new Google Cloud Container Registry

Based on the following Terraform [example](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_registry).

Prerequisites:

* You have installed these CLIs:
  * [docker](https://docs.docker.com/engine/install/)
  * [gcloud](https://cloud.google.com/sdk/docs/install)

Assumes:

* A Google Cloud service account with appropriate role and permissions


## Local testing

### Copy sample configuration

```
cp terraform.tfvars.sample terraform.tfvars
```

### Edit `terraform.tfvars`

Amend the values for

* `project`
* `location`


### Specify environment variables

See [Getting Started with the Google Provider > Adding credentials](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/getting_started#adding-credentials)

```
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```
> Update the value above to be the current path to your service account credentials

### Create registry

```
./create-container-registry.sh
```

### Authenticating w/ registry

```
gcloud auth configure-docker {region}-docker.pkg.dev
cat /path/to/credentials.json | docker login -u _json_key --password-stdin \
  https://{region}.gcr.io
```
> Replace `/path/to/credentials.json` and `{region}` above with path to service account credentials key file and location you used to create the registry

Also see: [Set up authentication for Docker > Service account key](https://cloud.google.com/container-registry/docs/advanced-authentication#json-key)

### Pushing and pulling images

Consult this public documentation:

* [push](https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling#pushing)
* [pull](https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling#pulling)

### Teardown registry

```
./destroy-container-registry.sh
```


## Github Action

This action is workflow dispatched [with inputs](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#onworkflow_dispatchinputs).

See [google-container-registry-2-dispatch.yml](https://github.com/clicktruck/google-actions/actions/workflows/google-container-registry-2-dispatch.yml)


## Credits

* [Reading and using environment variables in Terraform](https://support.hashicorp.com/hc/en-us/articles/4547786359571-Reading-and-using-environment-variables-in-Terraform-runs)