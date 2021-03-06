package apicurioregistry

import (
	ar "github.com/Apicurio/apicurio-registry-operator/pkg/apis/apicur/v1alpha1"
)

var _ ControlFunction = &InfinispanCF{}

const ENV_INFINISPAN_CLUSTER_NAME = "INFINISPAN_CLUSTER_NAME"

type InfinispanCF struct {
	ctx                      *Context
	persistence              string
	infinispanClusterName    string
	valid                    bool
	envInfinispanClusterName string
}

func NewInfinispanCF(ctx *Context) ControlFunction {
	return &InfinispanCF{
		ctx:                      ctx,
		persistence:              "",
		infinispanClusterName:    "",
		valid:                    true,
		envInfinispanClusterName: "",
	}
}

func (this *InfinispanCF) Describe() string {
	return "InfinispanCF"
}

func (this *InfinispanCF) Sense() {
	// Observation #1
	// Read the config values
	if specEntry, exists := this.ctx.GetResourceCache().Get(RC_KEY_SPEC); exists {
		spec := specEntry.GetValue().(*ar.ApicurioRegistry)
		this.persistence = spec.Spec.Configuration.Persistence
		this.infinispanClusterName = spec.Spec.Configuration.Infinispan.ClusterName
		// Default values
		if this.infinispanClusterName == "" {
			this.infinispanClusterName = spec.Name
		}
	}

	// Observation #2 + #3
	// Is the correct persistence type selected?
	// Validate the config values
	this.valid = this.persistence == "infinispan"

	// Observation #4
	// Read the env values
	if val, exists := this.ctx.GetEnvCache().Get(ENV_INFINISPAN_CLUSTER_NAME); exists {
		this.envInfinispanClusterName = val.GetValue().Value
	}

	// We won't actively delete old env values if not used
}

func (this *InfinispanCF) Compare() bool {
	// Condition #1
	// Is Infinispan & config values are valid
	// Condition #2 + #3
	// The required env vars are not present OR they differ
	return this.valid &&
		this.infinispanClusterName != this.envInfinispanClusterName
}

func (this *InfinispanCF) Respond() {
	// Response #1
	// Just set the value(s)!
	this.ctx.GetEnvCache().Set(NewSimpleEnvCacheEntry(ENV_INFINISPAN_CLUSTER_NAME, this.infinispanClusterName))
}
