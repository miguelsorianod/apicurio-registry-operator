package apicurioregistry

import (
	ar "github.com/Apicurio/apicurio-registry-operator/pkg/apis/apicur/v1alpha1"
	apps "k8s.io/api/apps/v1"
)

var _ ControlFunction = &ReplicasCF{}

type ReplicasCF struct {
	ctx              *Context
	deploymentEntry  ResourceCacheEntry
	deploymentExists bool
	existingReplicas int32
	targetReplicas   int32
}

// This CF makes sure number of replicas is aligned
// If there is some other way of determining the number of replicas needed outside of CR,
// modify the Sense stage so this CF knows about it
func NewReplicasCF(ctx *Context) ControlFunction {
	return &ReplicasCF{
		ctx:              ctx,
		deploymentEntry:  nil,
		deploymentExists: false,
		existingReplicas: 0,
		targetReplicas:   0,
	}
}

func (this *ReplicasCF) Describe() string {
	return "ReplicasCF"
}

func (this *ReplicasCF) Sense() {

	// Observation #1
	// Get the cached Deployment (if it exists and/or the value)
	deploymentEntry, deploymentExists := this.ctx.GetResourceCache().Get(RC_KEY_DEPLOYMENT)
	this.deploymentEntry = deploymentEntry
	this.deploymentExists = deploymentExists

	// Observation #2
	// Get the existing replicas (if present)
	this.existingReplicas = 0
	if this.deploymentExists {
		this.existingReplicas = *deploymentEntry.GetValue().(*apps.Deployment).Spec.Replicas
	}

	// Observation #3
	// Get the target replicas name
	if specEntry, exists := this.ctx.GetResourceCache().Get(RC_KEY_SPEC); exists {
		this.targetReplicas = specEntry.GetValue().(*ar.ApicurioRegistry).Spec.Deployment.Replicas
	}
	if this.targetReplicas < 1 {
		this.targetReplicas = 1
	}

	// Update state
	this.ctx.GetConfiguration().SetConfigInt32P(CFG_STA_REPLICA_COUNT, &this.existingReplicas)
}

func (this *ReplicasCF) Compare() bool {
	// Condition #1
	// Deployment exists
	// Condition #2
	// Existing replicas is not the same as the target replicas (assuming it is never empty)
	return this.deploymentEntry != nil &&
		this.existingReplicas != this.targetReplicas
}

func (this *ReplicasCF) Respond() {
	// Response #1
	// Patch the resource
	this.deploymentEntry.ApplyPatch(func(value interface{}) interface{} {
		deployment := value.(*apps.Deployment).DeepCopy()
		deployment.Spec.Replicas = &this.targetReplicas
		return deployment
	})
}
