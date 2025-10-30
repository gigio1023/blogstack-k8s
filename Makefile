.PHONY: validate bootstrap health

validate:
	@echo "Validating prod overlays...";
	@kustomize build apps/ghost/overlays/prod | kubeconform -summary -strict -schema-location default
	@kustomize build apps/ingress-nginx/overlays/prod | kubeconform -summary -strict -schema-location default
	@kustomize build apps/cloudflared/overlays/prod | kubeconform -summary -strict -schema-location default
	@kustomize build apps/observers/overlays/prod | kubeconform -summary -strict -schema-location default
	@kustomize build security/vault | kubeconform -summary -strict -schema-location default
	@kustomize build security/vso | kubeconform -summary -strict -schema-location default

bootstrap:
	./scripts/bootstrap.sh

health:
	./scripts/health-check.sh

