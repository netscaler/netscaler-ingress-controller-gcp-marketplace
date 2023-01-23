include ./app.Makefile
include ./crd.Makefile
include ./gcloud.Makefile
include ./var.Makefile


TAG ?= 1.26.7
GCP_TAG ?=1.26
EXPORTER_TAG ?= 1.4.9
$(info ---- TAG = $(TAG))

APP_DEPLOYER_IMAGE ?= $(REGISTRY)/citrix-k8s-ingress-controller/deployer:$(TAG)
NAME ?= citrix-k8s-ingress-controller-1

ifdef IMAGE_CITRIX_CONTROLLER
  IMAGE_CITRIX_CONTROLLER_FIELD = , "image": "$(IMAGE_CITRIX_CONTROLLER)" endif
endif

ifdef CITRIX_NSIP
  CITRIX_NSIP_FIELD = , "nsIP": "$(CITRIX_NSIP)"
endif

ifdef CITRIX_NSVIP
  CITRIX_NSVIP_FIELD = , "nsVIP": "$(CITRIX_NSVIP)"
endif

ifdef CITRIX_SERVICE_ACCOUNT
  CITRIX_SERVICE_ACCOUNT = , "serviceAccount": "$(CITRIX_SERVICE_ACCOUNT)"
endif

APP_PARAMETERS ?= { \
  "name": "$(NAME)", \
  "namespace": "$(NAMESPACE)" \
  $(IMAGE_CITRIX_CONTROLLER_FIELD) \
  $(CITRIX_NSIP_FIELD) \
  $(CITRIX_NSVIP_FIELD) \
  $(CITRIX_SERVICE_ACCOUNT) \
}

TESTER_IMAGE ?= $(REGISTRY)/citrix-k8s-ingress-controller/tester:$(TAG)


app/build:: .build/citrix-k8s-ingress-controller/debian9  \
            .build/citrix-k8s-ingress-controller/deployer \
            .build/citrix-k8s-ingress-controller/citrix-k8s-ingress-controller \
            .build/citrix-k8s-ingress-controller/exporter \
            .build/citrix-k8s-ingress-controller/tester


.build/citrix-k8s-ingress-controller: | .build
	mkdir -p "$@"


.build/citrix-k8s-ingress-controller/debian9: .build/var/REGISTRY \
                      .build/var/TAG \
                      | .build/citrix-k8s-ingress-controller
	docker pull marketplace.gcr.io/google/debian9
	docker tag marketplace.gcr.io/google/debian9 "$(REGISTRY)/citrix-k8s-ingress-controller/debian9:$(TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller/debian9:$(TAG)"
	@touch "$@"


.build/citrix-k8s-ingress-controller/deployer: deployer/* \
                       chart/citrix-ingress-controller/* \
                       chart/citrix-ingress-controller/templates/* \
                       schema.yaml \
                       .build/var/APP_DEPLOYER_IMAGE \
                       .build/var/MARKETPLACE_TOOLS_TAG \
                       .build/var/REGISTRY \
                       .build/var/TAG \
                       | .build/citrix-k8s-ingress-controller
	docker build \
	    --build-arg REGISTRY="$(REGISTRY)/citrix-k8s-ingress-controller" \
	    --build-arg TAG="$(TAG)" \
	    --build-arg MARKETPLACE_TOOLS_TAG="$(MARKETPLACE_TOOLS_TAG)" \
	    --tag "$(APP_DEPLOYER_IMAGE)" \
	    -f deployer/Dockerfile \
	    .
	docker push "$(APP_DEPLOYER_IMAGE)"
	docker pull "$(APP_DEPLOYER_IMAGE)"
	docker tag "$(APP_DEPLOYER_IMAGE)" \
            "$(REGISTRY)/citrix-k8s-ingress-controller/deployer:$(GCP_TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller/deployer:$(GCP_TAG)"
	@touch "$@"


.build/citrix-k8s-ingress-controller/citrix-k8s-ingress-controller: .build/var/REGISTRY \
                    .build/var/TAG \
                    | .build/citrix-k8s-ingress-controller
	docker pull quay.io/citrix/citrix-k8s-ingress-controller:$(TAG)
	docker tag quay.io/citrix/citrix-k8s-ingress-controller:$(TAG) \
	    "$(REGISTRY)/citrix-k8s-ingress-controller:$(TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller:$(TAG)"
	docker tag quay.io/citrix/citrix-k8s-ingress-controller:$(TAG) \
            "$(REGISTRY)/citrix-k8s-ingress-controller:$(GCP_TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller:$(GCP_TAG)"
	@touch "$@"


.build/citrix-k8s-ingress-controller/exporter: .build/var/REGISTRY \
                    .build/var/TAG \
                    | .build/citrix-k8s-ingress-controller
	docker pull quay.io/citrix/citrix-adc-metrics-exporter:$(EXPORTER_TAG)
	docker tag quay.io/citrix/citrix-adc-metrics-exporter:$(EXPORTER_TAG) \
	    "$(REGISTRY)/citrix-k8s-ingress-controller/citrix-adc-metrics-exporter:$(EXPORTER_TAG)"
	docker tag quay.io/citrix/citrix-adc-metrics-exporter:$(EXPORTER_TAG) \
	    "$(REGISTRY)/citrix-k8s-ingress-controller/citrix-adc-metrics-exporter:$(TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller/citrix-adc-metrics-exporter:$(EXPORTER_TAG)"
	docker push "$(REGISTRY)/citrix-k8s-ingress-controller/citrix-adc-metrics-exporter:$(TAG)"
	@touch "$@"


.build/citrix-k8s-ingress-controller/tester: .build/var/TESTER_IMAGE \
                     $(shell find apptest -type f) \
                     | .build/citrix-k8s-ingress-controller
	$(call print_target,$@)
	cd apptest/tester \
	    && docker build --tag "$(TESTER_IMAGE)" .
	docker push "$(TESTER_IMAGE)"
	@touch "$@"
