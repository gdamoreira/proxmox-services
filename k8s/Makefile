# Kubernetes Management Makefile for Homelab
# Usage:
#   make deploy APP=demo-app
#   make update APP=demo-app IMAGE=nginxdemos/hello:latest
#   make status APP=demo-app
#   make logs APP=demo-app
#   make restart APP=demo-app
#   make delete APP=demo-app

KUBECONFIG ?= $(HOME)/.kube/config-homelab
export KUBECONFIG

.PHONY: help kubeconfig deploy update restart status logs delete

help:
	@echo "Homelab Kubernetes CLI Helper"
	@echo ""
	@echo "Available commands:"
	@echo "  make kubeconfig                       Configure local kubeconfig from Ansible artifact"
	@echo "  make deploy APP=<name>                Deploy application manifests (apps/<name>/)"
	@echo "  make update APP=<name> IMAGE=<image>  Update container image with rolling update"
	@echo "  make restart APP=<name>               Trigger zero-downtime rolling restart"
	@echo "  make status APP=<name>                Check application pods, service, and ingress"
	@echo "  make logs APP=<name>                  Follow live logs for application pods"
	@echo "  make delete APP=<name>                Delete application resources"
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

deploy:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make deploy APP=demo-app)"; exit 1; fi
	@if [ ! -d "apps/$(APP)" ]; then echo "Error: apps/$(APP) directory does not exist"; exit 1; fi
	kubectl apply -f apps/$(APP)/

update:
	@if [ -z "$(APP)" ] || [ -z "$(IMAGE)" ]; then echo "Error: APP and IMAGE parameters required (e.g., make update APP=demo-app IMAGE=nginx:1.25)"; exit 1; fi
	kubectl set image deployment/$(APP) $(APP)=$(IMAGE) -n $(APP)
	kubectl rollout status deployment/$(APP) -n $(APP)

restart:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make restart APP=demo-app)"; exit 1; fi
	kubectl rollout restart deployment/$(APP) -n $(APP)
	kubectl rollout status deployment/$(APP) -n $(APP)

status:
	@if [ -z "$(APP)" ]; then \
		kubectl get nodes -o wide; \
	else \
		kubectl get all,ingress -n $(APP); \
	fi

logs:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make logs APP=demo-app)"; exit 1; fi
	kubectl logs -l app=$(APP) -n $(APP) --tail=100 -f

delete:
	@if [ -z "$(APP)" ]; then echo "Error: APP parameter is required (e.g., make delete APP=demo-app)"; exit 1; fi
	@if [ ! -d "apps/$(APP)" ]; then echo "Error: apps/$(APP) directory does not exist"; exit 1; fi
	kubectl delete -f apps/$(APP)/
