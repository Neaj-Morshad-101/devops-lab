argocd repo add https://github.com/neaj-morshad-101/devops-lab


devops-lab/
  └── postgres/gitops/
       ├── sr.yaml



argocd app create kubedb \
  --repo https://github.com/neaj-morshad-101/devops-lab \
  --path postgres/gitops \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated


argocd app list
argocd app get mongodb-app
kubectl get pods




# print initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo

# insecure because port-forward uses a k8s-generated cert
argocd login localhost:8080 \
  --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure


argocd repo add https://github.com/neaj-morshad-101/devops-lab --insecure-ignore-host-key



argocd login localhost:8080


kubectl port-forward svc/argocd-server -n argocd 8080:443


argocd app sync kubedb
argocd app set kubedb --sync-policy automated


argocd app sync kubedb --prune --retry
--prune → delete resources that exist in the cluster but were removed from Git.
--retry → retry failed resources immediately.