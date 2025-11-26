.PHONY: validate bootstrap health

validate:
	./scripts/validate.sh

bootstrap:
	./scripts/bootstrap.sh

health:
	./scripts/health-check.sh
