# Kubernetes Management Makefile for Homelab
# Supports both Helm-based decentralized app deployments and cluster maintenance.
# Usage:
#   make scaffold-chart TARGET=/path/to/app-repo APP=my-app PORT=8080
#   make deploy APP=demo-app
#   make status APP=demo-app
#   make history APP=demo-app
#   make rollback APP=demo-app REV=1
#   make restart APP=demo-app
#   make logs APP=demo-app
#   make delete APP=demo-app

KUBECONFIG ?= $(HOME)/.kube/config-homelab
export KUBECONFIG

.PHONY: help kubeconfig scaffold-chart deploy update rollback history restart status logs delete

help:
	@echo "Homelab Kubernetes CLI Helper (Helm & Cluster Tooling)"
	@echo ""
	@echo "Available commands:"
	@echo "  make kubeconfig                                Configure local kubeconfig from Ansible artifact"
	@echo "  make scaffold-chart TARGET=<dir> APP=<name>    Scaffold starter Helm chart into an application repo"
	@echo "                                                 (optional: PORT=8080)"
	@echo "  make deploy APP=<name> [CHART=<path>]          Deploy/upgrade app using Helm (default: apps/<name>/)"
	@echo "  make update APP=<name> IMAGE=<repo:tag>        Update container image with rolling update"
	@echo "  make history APP=<name>                        View Helm release revision history"
	@echo "  make rollback APP=<name> [REV=<rev>]           Roll back Helm release to previous or specific revision"
	@echo "  make restart APP=<name>                        Trigger zero-downtime rolling restart"
	@echo "  make status [APP=<name>]                       Check cluster nodes or application Helm release & pods"
	@echo "  make logs APP=<name>                           Follow live logs for application pods"
	@echo "  make delete APP=<name>                         Uninstall Helm release and remove namespace"
	@echo ""

kubeconfig:
	@mkdir -p $(HOME)/.kube
	@if [ -f ../ansible/artifacts/kubeconfig-k8s ]; then \
		cp ../ansible/artifacts/kubeconfig-k8s $(HOME)/.kube/config-homelab; \
		chmod 600 $(HOME)/.kube/config-homelab; \
		echo "Kubeconfig successfully installed to $(HOME)/.kube/config-homelab"; \
		echo "Run: export KUBECONFIG=$(HOME)/.kube/config-homelab"; \
	else \
		echo "Error: ../ansible/artifacts/kubeconfig-k8s not found. Run ansible playbook first."; \
		exit 1; \
	fi

scaffold-chart:
	@if [ -z "$(TARGET)" ] || [ -z "$(APP)" ]; then \
		echo "Error: TARGET and APP parameters are required."; \
		echo "Usage: make scaffold-chart TARGET=/path/to/my-app APP=my-app [PORT=8080]"; \
		exit 1; \
	fi
	@DEST_DIR="$(TARGET)/helm"; \
	mkdir -p "$$DEST_DIR"; \
	cp -r templates/app-template/* "$$DEST_DIR/"; \
	sed -i '' "s/starter-app/$(APP)/g" "$$DEST_DIR/Chart.yaml"; \
	sed -i '' "s/starter-app/$(APP)/g" "$$DEST_DIR/values.yaml"; \
	if [ -n "$(PORT)" ]; then \
		sed -i '' "s/port: 80/port: $(PORT)/g" "$$DEST_DIR/values.yaml"; \
		sed -i '' "s/targetPort: 80/targetPort: $(PORT)/g" "$$DEST_DIR/values.yaml"; \
	fi; \
	echo "Successfully scaffolded Helm chart for '$(APP)' in $$DEST_DIR"; \
	echo "To deploy from that repo, run:"; \
	echo "  helm upgrade --install $(APP) ./helm -n $(APP) --create-namespace --kubeconfig $(KUBECONFIG)"

deploy:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make deploy APP=demo-app)"; exit 1; fi
	@CHART_PATH="$(CHART)"; \
	if [ -z "$$CHART_PATH" ]; then \
		CHART_PATH="apps/$(APP)"; \
	fi; \
	if [ ! -d "$$CHART_PATH" ]; then echo "Error: Chart directory '$$CHART_PATH' does not exist"; exit 1; fi; \
	helm upgrade --install $(APP) "$$CHART_PATH" -n $(APP) --create-namespace --kubeconfig $(KUBECONFIG)

update:
	@if [ -z "$(APP)" ] || [ -z "$(IMAGE)" ]; then echo "Error: APP and IMAGE parameters required (e.g., make update APP=demo-app IMAGE=nginxdemos/hello:latest)"; exit 1; fi
	kubectl set image deployment/$(APP) $(APP)=$(IMAGE) -n $(APP)
	kubectl rollout status deployment/$(APP) -n $(APP)

history:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make history APP=demo-app)"; exit 1; fi
	helm history $(APP) -n $(APP) --kubeconfig $(KUBECONFIG)

rollback:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make rollback APP=demo-app [REV=1])"; exit 1; fi
	helm rollback $(APP) $(REV) -n $(APP) --kubeconfig $(KUBECONFIG)

restart:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make restart APP=demo-app)"; exit 1; fi
	kubectl rollout restart deployment/$(APP) -n $(APP)
	kubectl rollout status deployment/$(APP) -n $(APP)

status:
	@if [ -z "$(APP)" ]; then \
		kubectl get nodes -o wide; \
	else \
		echo "=== Helm Release Status ==="; \
		helm status $(APP) -n $(APP) --kubeconfig $(KUBECONFIG) 2>/dev/null || echo "Helm release '$(APP)' not found."; \
		echo ""; \
		echo "=== Kubernetes Resources ==="; \
		kubectl get all,ingress -n $(APP); \
	fi

logs:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make logs APP=demo-app)"; exit 1; fi
	kubectl logs -l app.kubernetes.io/name=$(APP) -n $(APP) --tail=100 -f

delete:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make delete APP=demo-app)"; exit 1; fi
	helm uninstall $(APP) -n $(APP) --kubeconfig $(KUBECONFIG) || true
	kubectl delete namespace $(APP) --ignore-not-found=true
